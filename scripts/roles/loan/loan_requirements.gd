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
