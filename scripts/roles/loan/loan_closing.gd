extends RefCounted
class_name LoanClosing

## One approved loan waiting to be closed (LoanClosings): the application the
## player approved (or whose counter-offer the applicant accepted), the terms
## as approved (frozen, so a later change to a table never alters a closing
## already made), when the closing is due, the loan number reserved for it,
## and what the applicant's paperwork will show on the day.
##
## About one closing in LoanConfig.CLOSING_PROBLEM_CHANCE has a problem: the
## final paperwork's terms don't match the approval, the photo ID has expired,
## the signature is missing, or a new debt has appeared since. Whether it has
## one, which, and the details are rolled once, when the closing is made, from
## the career seed and the closing's number and nothing else: never the global
## random generator (so reloading can't re-roll it) and never the applicant's
## name, look, finances or decision type (fair lending). Two things are worked
## out from the application, because they would mean nothing otherwise: the
## size of a new debt (it has to push the total debt-to-income over 43%) and,
## for a counter-offer, the wrong figure on a terms mismatch (the amount the
## applicant first asked for). The career's first closing is always clean.
##
## Everything about time is a pure function of business-day numbers: it is due
## from its due day, and lapses once LoanConfig.CLOSING_LAPSE_DAYS Loan Officer
## days have passed after it (only days whose recorded role was Loan Officer
## count, as for a returned file).

enum Kind { APPROVAL, COUNTER_OFFER }
enum Problem { NONE, TERMS, EXPIRED_ID, NO_SIGNATURE, NEW_DEBT }
## Which figure of a terms mismatch is wrong.
enum TermsField { NONE, AMOUNT, RATE, TERM, PAYMENT }

const PROBLEM_LABELS: Dictionary[int, String] = {
	Problem.NONE: "No problem",
	Problem.TERMS: "Terms don't match the approval",
	Problem.EXPIRED_ID: "Photo ID has expired",
	Problem.NO_SIGNATURE: "Missing signature",
	Problem.NEW_DEBT: "New debt since the approval",
}

var number: int = 0
var application: LoanApplication = null
var kind: Kind = Kind.APPROVAL
## The terms as approved (frozen when the closing was made).
var approved_amount: float = 0.0
var approved_rate: float = 0.0
var approved_term: int = 0
var approved_payment: float = 0.0
var approval_day: int = 0
var due_day: int = 0
## The loan number reserved for it (assigned by whoever makes the closing; the
## loan book books the loan under it, so the order closings are funded in never
## changes how a loan turns out). 0: none reserved.
var loan_id: int = 0

var problem: Problem = Problem.NONE
var terms_field: TermsField = TermsField.NONE

## What the final paperwork shows. The same as the approval unless the problem
## is a terms mismatch (the one wrong figure).
var paper_amount: float = 0.0
var paper_rate: float = 0.0
var paper_term: int = 0
var paper_payment: float = 0.0
## The photo ID's expiry date on closing day (an epoch day).
var id_expiry_date: int = 0
var signed: bool = true
## A new monthly debt payment since the approval (0 when there is none).
var new_debt_payment: float = 0.0

# --- making one ----------------------------------------------------------------------------

## A closing for `application`, which must be approved or counter-offered (null
## otherwise): terms from its decision, due LoanConfig.closing_days() after
## `approval_day`, and the problem rolled from `career_seed` and `closing_number`.
## `reserved_loan_id` is only stored.
static func create(approved_loan: LoanApplication, day_approved: int, closing_number: int, career_seed: int, reserved_loan_id: int = 0) -> LoanClosing:
	if approved_loan == null:
		return null
	var decision_kind: Kind
	match approved_loan.decision:
		LoanApplication.DecisionType.APPROVE:
			decision_kind = Kind.APPROVAL
		LoanApplication.DecisionType.COUNTER_OFFER:
			decision_kind = Kind.COUNTER_OFFER
		_:
			return null
	var closing := LoanClosing.new()
	closing.application = approved_loan
	closing.number = closing_number
	closing.kind = decision_kind
	closing.approval_day = day_approved
	closing.due_day = day_approved + due_days_for(approved_loan.loan_purpose)
	closing.loan_id = reserved_loan_id
	closing.approved_amount = approved_loan.decision_amount
	closing.approved_rate = approved_loan.annual_rate()
	closing.approved_term = approved_loan.term_months()
	closing.approved_payment = _cents(approved_loan.new_loan_payment(closing.approved_amount))
	closing._roll(career_seed)
	return closing

## Business days from the approval to the closing for a `purpose` loan.
static func due_days_for(purpose: String) -> int:
	return LoanConfig.CLOSING_DAYS.get(purpose, LoanConfig.CLOSING_DAYS_DEFAULT)

## Rolls the problem and the paperwork. Every draw is always made, in this
## order, so one thing never shifts another.
func _roll(career_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([career_seed, "closing", number])
	var problem_draw := rng.randf()
	var which := rng.randf()
	var field_draw := rng.randi_range(0, 3)
	var sign_draw := rng.randf()
	var size_draw := rng.randf()
	var term_draw := rng.randi_range(0, LoanConfig.MISMATCH_TERM_SHARES.size() - 1)
	var expired_draw := rng.randf()
	var valid_draw := rng.randf()
	var debt_draw := rng.randf()

	paper_amount = approved_amount
	paper_rate = approved_rate
	paper_term = approved_term
	paper_payment = approved_payment
	signed = true
	new_debt_payment = 0.0
	terms_field = TermsField.NONE
	problem = Problem.NONE
	var date := GameClock.date_of_day(due_day)
	id_expiry_date = date + int(lerpf(LoanConfig.VALID_ID_DAYS[0], LoanConfig.VALID_ID_DAYS[1], valid_draw))

	# The career's first closing is clean, whatever the roll.
	if number <= 1 or problem_draw >= LoanConfig.CLOSING_PROBLEM_CHANCE:
		return
	var picked := _problem_for(which)
	# A new debt means something only with an income to measure it against.
	if picked == Problem.NEW_DEBT and application.monthly_income() <= 0.0:
		picked = Problem.TERMS
	problem = picked
	match problem:
		Problem.TERMS:
			terms_field = (TermsField.AMOUNT + field_draw) as TermsField
			# An accepted counter-offer's wrong figure is the amount first asked
			# for.
			if kind == Kind.COUNTER_OFFER:
				terms_field = TermsField.AMOUNT
			_apply_mismatch(sign_draw, size_draw, term_draw)
		Problem.EXPIRED_ID:
			id_expiry_date = date - maxi(1, int(lerpf(LoanConfig.EXPIRED_ID_DAYS[0], LoanConfig.EXPIRED_ID_DAYS[1], expired_draw)))
		Problem.NO_SIGNATURE:
			signed = false
		Problem.NEW_DEBT:
			new_debt_payment = _new_debt_for(debt_draw)

static func _problem_for(which: float) -> Problem:
	var edge := LoanConfig.CLOSING_MIX_TERMS
	if which < edge:
		return Problem.TERMS
	edge += LoanConfig.CLOSING_MIX_EXPIRED_ID
	if which < edge:
		return Problem.EXPIRED_ID
	edge += LoanConfig.CLOSING_MIX_NO_SIGNATURE
	if which < edge:
		return Problem.NO_SIGNATURE
	return Problem.NEW_DEBT

## Changes the one figure `terms_field` names, up or down by `sign_draw`, by a
## size from `size_draw` (or the term share `term_draw` picks).
func _apply_mismatch(sign_draw: float, size_draw: float, term_draw: int) -> void:
	var up := sign_draw >= 0.5
	match terms_field:
		TermsField.AMOUNT:
			if kind == Kind.COUNTER_OFFER and application.requested_amount != approved_amount:
				paper_amount = application.requested_amount
			else:
				var step := maxf(100.0, roundf(approved_amount * lerpf(LoanConfig.MISMATCH_AMOUNT_SHARE[0], LoanConfig.MISMATCH_AMOUNT_SHARE[1], size_draw) / 100.0) * 100.0)
				paper_amount = approved_amount + step if up or approved_amount - step < 100.0 else approved_amount - step
		TermsField.RATE:
			var points := roundf(lerpf(LoanConfig.MISMATCH_RATE_POINTS[0], LoanConfig.MISMATCH_RATE_POINTS[1], size_draw) * 4.0) / 4.0 / 100.0
			paper_rate = _basis_points(approved_rate + points if up or approved_rate - points < 0.01 else approved_rate - points)
		TermsField.TERM:
			var months := maxi(12, roundi(approved_term * LoanConfig.MISMATCH_TERM_SHARES[term_draw] / 12.0) * 12)
			paper_term = months if months != approved_term else approved_term + 12
		TermsField.PAYMENT:
			var share := lerpf(LoanConfig.MISMATCH_PAYMENT_SHARE[0], LoanConfig.MISMATCH_PAYMENT_SHARE[1], size_draw)
			paper_payment = _cents(approved_payment * (1.0 + share if up else 1.0 - share))
			if paper_payment == approved_payment:
				paper_payment = _cents(approved_payment + 1.0)

## The new monthly debt payment: it takes the total debt-to-income, measured on
## the approved loan, to a share between LoanConfig.NEW_DEBT_DTI_RANGE (both
## over 43%): payment = target × monthly income − what is already owed each
## month (housing, debts and the new loan's payment). It is never less than
## LoanConfig.NEW_DEBT_MIN_SHARE of monthly income or NEW_DEBT_MIN_PAYMENT, and
## it is rounded up to a whole $10, so the total is always over 43%, even for
## an applicant who was over it already.
func _new_debt_for(debt_draw: float) -> float:
	var income := application.monthly_income()
	var owed := application.total_dti(approved_amount) * income
	var target := lerpf(LoanConfig.NEW_DEBT_DTI_RANGE[0], LoanConfig.NEW_DEBT_DTI_RANGE[1], debt_draw)
	var payment := maxf(target * income - owed, maxf(LoanConfig.NEW_DEBT_MIN_SHARE * income, LoanConfig.NEW_DEBT_MIN_PAYMENT))
	return ceilf(payment / 10.0) * 10.0

## A rate rounded to the basis point, so it is the exact double of its decimal
## and survives the save file (a sum like 0.07 - 0.01 would not).
static func _basis_points(rate: float) -> float:
	return roundf(rate * 10000.0) / 10000.0

static func _cents(value: float) -> float:
	return roundf(value * 100.0) / 100.0

# --- what the paperwork shows ---------------------------------------------------------------

func has_problem() -> bool:
	return problem != Problem.NONE

func problem_label() -> String:
	return PROBLEM_LABELS.get(problem, "")

## The date of the closing (an epoch day).
func closing_date() -> int:
	return GameClock.date_of_day(due_day)

## Whether the photo ID has expired by closing day.
func id_is_expired() -> bool:
	return id_expiry_date < closing_date()

## Whether every figure on the final paperwork is the approved one.
func terms_match() -> bool:
	return is_equal_approx(paper_amount, approved_amount) and is_equal_approx(paper_rate, approved_rate) \
			and paper_term == approved_term and is_equal_approx(paper_payment, approved_payment)

## Total debt-to-income at the approval (the approved amount).
func dti_at_approval() -> float:
	return application.total_dti(approved_amount)

## Total debt-to-income with the new debt (the same as at approval when there
## is none).
func dti_with_new_debt() -> float:
	var income := application.monthly_income()
	if income <= 0.0:
		return 0.0
	return dti_at_approval() + new_debt_payment / income

## A good applicant: low risk, documents fine (what the loan book counts as
## good business).
func is_good_applicant() -> bool:
	return application.calculate_risk_assessment() == LoanApplication.RiskTier.LOW and application.documents_check_out()

## Whether letting this closing lapse counts as a good applicant turned away.
func counts_as_turned_away_if_lapsed() -> bool:
	return LoanConfig.LAPSED_GOOD_APPLICANT_TURNED_AWAY and is_good_applicant()

# --- time (pure functions of day numbers) ------------------------------------------------

## The closing is due: the applicant is there to close from the due day on.
func is_due(today: int) -> bool:
	return today >= due_day

## The Loan Officer days after the due day and before `today` (whole days that
## are over). `role_days` is the recorded role of each business day
## (LoanRole.role_days: day number to PlayerShift.Role).
func loan_officer_days_since_due(today: int, role_days: Dictionary) -> int:
	var count := 0
	for day in range(due_day + 1, today):
		if role_days.get(day, PlayerShift.Role.NONE) == PlayerShift.Role.LOAN_OFFICER:
			count += 1
	return count

## Loan Officer days still left to close it in (0: lapsed).
func days_left(today: int, role_days: Dictionary) -> int:
	return maxi(0, LoanConfig.CLOSING_LAPSE_DAYS - loan_officer_days_since_due(today, role_days))

## Due, and its Loan Officer days are used up: it lapses at the start of
## `today`.
func is_overdue(today: int, role_days: Dictionary) -> bool:
	return is_due(today) and days_left(today, role_days) == 0

## Due for LoanConfig.ABANDONED_AFTER_DAYS business days or more and still
## open: closed quietly at Opening whatever the player's role. A pure function
## of the day number. (The Loan Officer day lapse, with its penalty, comes
## first.)
func is_abandoned(today: int) -> bool:
	return is_due(today) and today - due_day >= LoanConfig.ABANDONED_AFTER_DAYS

## The last day it can be closed on if the player works as a Loan Officer on
## every day from `today` on (each other day pushes it back). Never before
## `today`.
func last_day_to_close(today: int, role_days: Dictionary) -> int:
	var days := role_days.duplicate()
	var day := today
	# A closing lapses within a handful of days of the due day.
	while day < maxi(today, due_day) + LoanConfig.CLOSING_LAPSE_DAYS + 2:
		days[day] = PlayerShift.Role.LOAN_OFFICER
		if is_overdue(day + 1, days):
			return day
		day += 1
	return day

# --- save and load ------------------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"number": number,
		"application": SaveGame.resource_to_dict(application),
		"kind": kind,
		"approved_amount": approved_amount,
		"approved_rate": approved_rate,
		"approved_term": approved_term,
		"approved_payment": approved_payment,
		"approval_day": approval_day,
		"due_day": due_day,
		"loan_id": loan_id,
		"problem": problem,
		"terms_field": terms_field,
		"paper_amount": paper_amount,
		"paper_rate": paper_rate,
		"paper_term": paper_term,
		"paper_payment": paper_payment,
		"id_expiry_date": id_expiry_date,
		"signed": signed,
		"new_debt_payment": new_debt_payment,
	}

## A closing from saved data, or null if it can't be read (no application, or a
## purpose the game no longer knows).
static func from_data(data: Dictionary) -> LoanClosing:
	var saved := SaveGame.dict_of(data, "application")
	if saved.is_empty():
		return null
	var loaded := LoanApplication.new()
	SaveGame.fill_resource(loaded, saved)
	if not LoanApplication.PURPOSE_TERMS.has(loaded.loan_purpose):
		return null
	loaded.applicant_look = clampi(loaded.applicant_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)
	loaded.risk_assessment = loaded.calculate_risk_assessment()
	var closing := LoanClosing.new()
	closing.application = loaded
	closing.number = SaveGame.int_of(data, "number", 0)
	closing.kind = clampi(SaveGame.int_of(data, "kind", Kind.APPROVAL), Kind.APPROVAL, Kind.COUNTER_OFFER) as Kind
	closing.approved_amount = SaveGame.float_of(data, "approved_amount", loaded.decision_amount)
	closing.approved_rate = SaveGame.float_of(data, "approved_rate", loaded.annual_rate())
	closing.approved_term = SaveGame.int_of(data, "approved_term", loaded.term_months())
	closing.approved_payment = SaveGame.float_of(data, "approved_payment", 0.0)
	closing.approval_day = SaveGame.int_of(data, "approval_day", 0)
	closing.due_day = SaveGame.int_of(data, "due_day", closing.approval_day + due_days_for(loaded.loan_purpose))
	closing.loan_id = SaveGame.int_of(data, "loan_id", 0)
	closing.problem = clampi(SaveGame.int_of(data, "problem", Problem.NONE), Problem.NONE, Problem.NEW_DEBT) as Problem
	closing.terms_field = clampi(SaveGame.int_of(data, "terms_field", TermsField.NONE), TermsField.NONE, TermsField.PAYMENT) as TermsField
	closing.paper_amount = SaveGame.float_of(data, "paper_amount", closing.approved_amount)
	closing.paper_rate = SaveGame.float_of(data, "paper_rate", closing.approved_rate)
	closing.paper_term = SaveGame.int_of(data, "paper_term", closing.approved_term)
	closing.paper_payment = SaveGame.float_of(data, "paper_payment", closing.approved_payment)
	closing.id_expiry_date = SaveGame.int_of(data, "id_expiry_date", 0)
	closing.signed = SaveGame.bool_of(data, "signed", true)
	closing.new_debt_payment = SaveGame.float_of(data, "new_debt_payment", 0.0)
	return closing
