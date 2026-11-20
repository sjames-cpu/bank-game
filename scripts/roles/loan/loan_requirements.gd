extends RefCounted
class_name LoanRequirements

## The documents a Loan Officer can ask an applicant to bring back (the
## checklist of a request for more documents), which of them an application
## is truly missing, and how long a request takes. Pure functions: nothing is
## stored, so the same application and career seed always give the same
## answer.
##
## The pay stub, the bank statement and the photo ID are missing when the
## application's own documents say so (LoanApplication.has_pay_stub,
## has_statement and an ID that is absent or expired; a mismatched name or
## photo is an identity problem to reject, not a document to ask for). The
## appraisal, the proof of the down payment and the letter explaining a late
## payment or collection come from a stream of their own (seeded from the
## career and the applicant), so no existing applicant or seeded draw
## changes. Each applies only where the loan and the credit report make it
## relevant, and is missing with LoanConfig.NEW_ITEM_MISSING_CHANCE whatever
## the finances, name or look (fair lending).

enum Item { PAY_STUB, BANK_STATEMENT, PHOTO_ID, APPRAISAL, DOWN_PAYMENT_PROOF, EXPLANATION_LETTER }

const LABELS: Dictionary[int, String] = {
	Item.PAY_STUB: "Pay stub",
	Item.BANK_STATEMENT: "Bank statement",
	Item.PHOTO_ID: "Valid photo ID",
	Item.APPRAISAL: "Appraisal",
	Item.DOWN_PAYMENT_PROOF: "Proof of down payment",
	Item.EXPLANATION_LETTER: "Letter explaining a late payment or collection",
}

## The items whose truly-missing roll comes from the new stream.
const ROLLED_ITEMS: Array[int] = [Item.APPRAISAL, Item.DOWN_PAYMENT_PROOF, Item.EXPLANATION_LETTER]

static func label(item: int) -> String:
	return LABELS.get(item, "Unknown document")

static func is_valid(item: int) -> bool:
	return LABELS.has(item)

## Every item, in checklist order.
static func all_items() -> Array[int]:
	var items: Array[int] = []
	for item: int in LABELS:
		items.append(item)
	return items

## Whether the loan and the credit report make `item` relevant.
static func applies(application: LoanApplication, item: int) -> bool:
	match item:
		Item.APPRAISAL:
			return application.loan_purpose == "Home"
		Item.DOWN_PAYMENT_PROOF:
			return application.has_down_payment() and application.down_payment() > 0.0
		Item.EXPLANATION_LETTER:
			return application.credit_report_issued \
				and (application.late_30_days + application.late_60_days + application.late_90_days > 0 or application.collections > 0)
	return is_valid(item)

## The items `application` is truly missing, in checklist order.
static func missing_items(application: LoanApplication, career_seed: int) -> Array[int]:
	var missing: Array[int] = []
	if application.documents_issued:
		if not application.has_pay_stub:
			missing.append(Item.PAY_STUB)
		if not application.has_statement:
			missing.append(Item.BANK_STATEMENT)
		if not application.id_presented or application.id_problem == IdCard.Problem.EXPIRED:
			missing.append(Item.PHOTO_ID)
	# Every rolled item is always drawn, in this order, so what applies to an
	# application never shifts another item's draw.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([career_seed, "requirements", application.applicant_name])
	for item in ROLLED_ITEMS:
		var drawn := rng.randf() < LoanConfig.NEW_ITEM_MISSING_CHANCE
		if drawn and applies(application, item):
			missing.append(item)
	return missing

## Business days from a request for `item_count` items to its due day: 2 for
## one, one more for each further item, at most 5.
static func due_days(item_count: int) -> int:
	return clampi(LoanConfig.DUE_DAYS_MIN + maxi(0, item_count - 1), LoanConfig.DUE_DAYS_MIN, LoanConfig.DUE_DAYS_MAX)

# --- grading a request -----------------------------------------------------------------

## How a request on a file turned out.
enum RequestKind { EXACT, OFF, COMPLETE_FILE, FORGED }

## The items truly missing from `application` now: what its file still lacks
## after earlier requests, or, with no file yet, everything it is missing.
static func missing_now(application: LoanApplication, career_seed: int, today: int) -> Array[int]:
	var file := LoanRole.pipeline.file_for(application)
	if file != null:
		return file.still_missing(career_seed, today)
	return missing_items(application, career_seed)

## Grades a request for `ticked` on `application` against what is truly
## missing (`missing`): {"kind", "score", "reputation", "right" (ticked and
## missing), "wrong" (ticked, not missing), "missed" (missing, not ticked)}.
## A forged or wrong document makes any request wrong (FORGED); a file with
## nothing missing costs REQUEST_COMPLETE_FILE_SCORE however much was ticked;
## otherwise an exactly right checklist earns REQUEST_RIGHT_SCORE and every
## wrong tick or missed item costs one point.
static func grade_request(application: LoanApplication, ticked: Array[int], missing: Array[int]) -> Dictionary:
	var right: Array[int] = []
	var wrong: Array[int] = []
	var missed: Array[int] = []
	for item in ticked:
		if missing.has(item):
			right.append(item)
		else:
			wrong.append(item)
	for item in missing:
		if not ticked.has(item):
			missed.append(item)
	var kind := RequestKind.OFF
	var score := wrong.size() * LoanConfig.REQUEST_WRONG_TICK_SCORE + missed.size() * LoanConfig.REQUEST_MISSED_ITEM_SCORE
	if application.has_forged_document():
		kind = RequestKind.FORGED
		score = LoanConfig.REQUEST_FORGED_SCORE
	elif missing.is_empty():
		kind = RequestKind.COMPLETE_FILE
		score = LoanConfig.REQUEST_COMPLETE_FILE_SCORE
	elif wrong.is_empty() and missed.is_empty():
		kind = RequestKind.EXACT
		score = LoanConfig.REQUEST_RIGHT_SCORE
	return {"kind": kind, "score": score, "reputation": LoanConfig.REQUEST_REPUTATION, "right": right, "wrong": wrong, "missed": missed}

## What the request amounted to, in a few words.
static func request_description(kind: RequestKind) -> String:
	match kind:
		RequestKind.EXACT:
			return "Right documents asked for"
		RequestKind.COMPLETE_FILE:
			return "No documents were needed"
		RequestKind.FORGED:
			return "A request can't fix a forged document"
	return "The checklist was partly off"

## "Pay stub, Bank statement" for a list of items.
static func labels(items: Array[int]) -> String:
	var names: PackedStringArray = []
	for item in items:
		names.append(label(item))
	return ", ".join(names)
