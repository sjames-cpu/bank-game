extends RefCounted
class_name LoanReturn

## What an applicant brings back when a file returns (LoanFile), put on the
## application itself so Verify Documents shows it and the final decision
## (and the loan it books) reads it: the requested items now present, one
## still missing (an incomplete return), or one that doesn't match (a wrong
## one, a forged-type problem best answered with Reject naming "could not be
## verified"). Every other problem the application had stays.
##
## Applied once per request, the first time the returned file is put in
## front of the Loan Officer (LoanDeskManager.current_player_application()),
## and recorded on the file (return_applied) so a second look changes
## nothing. What is brought comes from the career seed, the file number and
## the request, never the global random generator, so it is the same on every
## load.

## Puts the return of `file`'s latest request on its application, if it has
## come back by `today` and this request's return isn't on it yet.
static func apply(file: LoanFile, career_seed: int, today: int) -> void:
	if not file.has_returned(today) or file.return_applied >= file.request_count:
		return
	file.return_applied = file.request_count
	var application := file.application
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([career_seed, "return-documents", file.number, file.request_count])
	for item in file.items:
		if item == file.short_item:
			continue
		if item == file.wrong_item:
			_hand_over_wrong(application, item, rng, today)
		else:
			_hand_over(application, item, rng, today)
	# A stub and a statement that both show the stated income clear an
	# overstated one.
	var delivered := file.all_delivered_items(today)
	if application.doc_problem == LoanApplication.DocProblem.OVERSTATED_INCOME \
			and delivered.has(LoanRequirements.Item.PAY_STUB) and delivered.has(LoanRequirements.Item.BANK_STATEMENT):
		_hand_over(application, LoanRequirements.Item.PAY_STUB, rng, today)
		_hand_over(application, LoanRequirements.Item.BANK_STATEMENT, rng, today)
		application.doc_problem = LoanApplication.DocProblem.NONE
	_settle_missing_problem(application)

## The one doc_problem can only name one thing, so after a return it is set
## again from what is still absent: no stub, else no statement, else nothing,
## while a forged-type problem is left as it is.
static func _settle_missing_problem(application: LoanApplication) -> void:
	var problem := application.doc_problem
	if problem != LoanApplication.DocProblem.NONE and problem != LoanApplication.DocProblem.MISSING_STUB and problem != LoanApplication.DocProblem.MISSING_STATEMENT:
		return
	if not application.has_pay_stub:
		application.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	elif not application.has_statement:
		application.doc_problem = LoanApplication.DocProblem.MISSING_STATEMENT
	else:
		application.doc_problem = LoanApplication.DocProblem.NONE

## The monthly gross and net pay a stub shows for the stated income.
static func _pay(application: LoanApplication, rng: RandomNumberGenerator) -> Vector2:
	var gross := roundf(application.annual_income / 12.0)
	var net := roundf(gross * rng.randf_range(LoanApplicantGenerator.NET_SHARE_RANGE[0], LoanApplicantGenerator.NET_SHARE_RANGE[1]))
	return Vector2(gross, net)

static func _hand_over(application: LoanApplication, item: int, rng: RandomNumberGenerator, today: int) -> void:
	match item:
		LoanRequirements.Item.PAY_STUB:
			var pay := _pay(application, rng)
			application.has_pay_stub = true
			application.stub_name = application.applicant_name
			if application.stub_employer == "":
				application.stub_employer = LoanApplicantGenerator.EMPLOYERS[rng.randi_range(0, LoanApplicantGenerator.EMPLOYERS.size() - 1)]
			application.stub_monthly_gross = pay.x
			application.stub_monthly_net = pay.y
			if application.doc_problem == LoanApplication.DocProblem.MISSING_STUB or application.doc_problem == LoanApplication.DocProblem.STUB_NAME:
				application.doc_problem = LoanApplication.DocProblem.NONE
		LoanRequirements.Item.BANK_STATEMENT:
			var net := application.stub_monthly_net if application.has_pay_stub and application.doc_problem != LoanApplication.DocProblem.OVERSTATED_INCOME else _pay(application, rng).y
			application.has_statement = true
			application.statement_name = application.applicant_name
			application.statement_deposits = _deposits(net)
			if application.doc_problem == LoanApplication.DocProblem.MISSING_STATEMENT:
				application.doc_problem = LoanApplication.DocProblem.NONE
		LoanRequirements.Item.PHOTO_ID:
			_give_id(application, IdCard.Problem.NONE, rng, today)
		_:
			_give_paper(application, item)
			if application.paper_mismatch_item == item:
				application.paper_mismatch_item = -1
				if application.doc_problem == LoanApplication.DocProblem.PAPER_MISMATCH:
					application.doc_problem = LoanApplication.DocProblem.NONE

## A document that doesn't match: the stub in someone else's name, a statement
## showing less than the income stated, an ID with another name or photo, or
## a paper that belongs to something else.
static func _hand_over_wrong(application: LoanApplication, item: int, rng: RandomNumberGenerator, today: int) -> void:
	match item:
		LoanRequirements.Item.PAY_STUB:
			_hand_over(application, item, rng, today)
			application.stub_name = KycPolicy.mismatched_name(rng, application.applicant_name)
			application.doc_problem = LoanApplication.DocProblem.STUB_NAME
		LoanRequirements.Item.BANK_STATEMENT:
			var share := rng.randf_range(LoanApplicantGenerator.OVERSTATED_SHARE_RANGE[0], LoanApplicantGenerator.OVERSTATED_SHARE_RANGE[1])
			application.has_statement = true
			application.statement_name = application.applicant_name
			application.statement_deposits = _deposits(roundf(_pay(application, rng).y * share))
			application.doc_problem = LoanApplication.DocProblem.OVERSTATED_INCOME
		LoanRequirements.Item.PHOTO_ID:
			var problem := IdCard.Problem.NAME_MISMATCH if rng.randf() < 0.5 else IdCard.Problem.WRONG_PORTRAIT
			_give_id(application, problem, rng, today)
		_:
			_give_paper(application, item)
			application.paper_mismatch_item = item
			application.doc_problem = LoanApplication.DocProblem.PAPER_MISMATCH

## Paid twice a month: `net` in two deposits.
static func _deposits(net: float) -> PackedInt32Array:
	var first_half := floori(net / 2.0)
	return PackedInt32Array([first_half, int(net) - first_half])

static func _give_id(application: LoanApplication, problem: IdCard.Problem, rng: RandomNumberGenerator, today: int) -> void:
	var card := KycPolicy.issue_card(rng, application.applicant_name, application.applicant_look, today, problem, CustomerNPC.CUSTOMER_FRAME_SETS.size(), false)
	application.id_problem = problem
	application.id_presented = card.presented
	application.id_holder_name = card.holder_name
	application.id_number = card.id_number
	application.id_expiry_date = card.expiry_date
	application.id_portrait_look = card.portrait_look

static func _give_paper(application: LoanApplication, item: int) -> void:
	if not application.papers_received.has(item):
		application.papers_received.append(item)

## What a paper brought back says, for Verify Documents: one short line each
## (so each stays on one line in the narrow column and the review screen gets
## no taller), saying only what the paper shows when it doesn't match.
static func papers_lines(application: LoanApplication) -> PackedStringArray:
	var lines := PackedStringArray()
	for item in application.papers_received:
		var matches := item != application.paper_mismatch_item
		match item:
			LoanRequirements.Item.APPRAISAL:
				lines.append("Appraisal: %s (this property)" % LoanApplication.dollars(application.collateral_value) if matches else "Appraisal: not this property")
			LoanRequirements.Item.DOWN_PAYMENT_PROOF:
				lines.append("Down payment: %s in own account" % LoanApplication.dollars(maxf(0.0, application.down_payment())) if matches else "Down payment: someone else's account")
			LoanRequirements.Item.EXPLANATION_LETTER:
				lines.append("Letter: explains the late payment" if matches else "Letter: about someone else's account")
	return lines
