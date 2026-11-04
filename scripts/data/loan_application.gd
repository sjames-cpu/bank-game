extends Resource
class_name LoanApplication

## A loan application submitted for review, and the underwriting worksheet
## built from it (HANDOFF.md Phase 3). risk_tier is authoring context: the
## tier each sample applicant is meant to land on, or the tier
## LoanApplicantGenerator built a generated one for. Grading
## (grade()/grade_decision() below) only ever reads risk_assessment, never
## risk_tier; loan_application_test.gd and loan_generator_test.gd check the
## two agree.
##
## The rules here are presented in game as bank policy, not as any law:
## the term and rate for each purpose, the DTI guide bands, the policy
## maximums and the denial reasons are the branch's own lending policy.
##
## The money figures here stay whole-dollar floats, not the int cents the
## teller/ATM/drawer use (B3, see MoneyMath). They're figures the player
## judges, never cash that moves through an account or drawer, so nothing
## sums them and they can't drift; decision_amount rounds a counter-offer
## to $100.
## Built in code (see loan_applications_data.gd) rather than loaded from
## .tres files, matching Account/InterviewQuestion.

enum RiskTier { LOW, MEDIUM, HIGH }
enum DecisionType { NONE, APPROVE, REJECT, COUNTER_OFFER }

## Outcome of grade() below — how well a decision matched a risk_assessment.
## BEST is a correct call, PARTIAL is a reasonable-but-not-optimal call,
## BAD/WORST are two levels of wrong (BAD being overly cautious, WORST
## being an outright risky approval).
enum Grade { BEST, PARTIAL, BAD, WORST }

## The main reasons a loan officer can state for a denial (the player picks
## 1-2). Each is a real weak point of an application when weak_points()
## says so. UNVERIFIED: the documents didn't check out (documents_check_out()).
enum DenialReason { TOTAL_DTI, CREDIT_SCORE, INCOME, EMPLOYMENT, AMOUNT, UNVERIFIED }

## What's wrong with an applicant's documents besides their ID (which has
## its own IdCard.Problem): the income stated on the form is more than the pay
## stub and statement show; the pay stub is in someone else's name; or the pay
## stub or bank statement is missing. Rolled by LoanApplicantGenerator.
enum DocProblem { NONE, OVERSTATED_INCOME, STUB_NAME, MISSING_STUB, MISSING_STATEMENT }

## --- Document checks (bank policy) ---
## Verified and caught: the decision's grade (BEST for a rejection naming
## UNVERIFIED) plus the reason's +2. Approving or counter-offering on
## documents that don't check out is WORST, like waving through a high-risk
## loan. Turning away an applicant whose documents were fine as
## "unverifiable" costs this on top of the decision's own grade and the wrong
## reason (pitched like refusing a customer's valid ID at the teller window).
## Deciding without verifying the documents first is a procedure mistake
## whatever they showed, like serving without checking ID.
const FALSE_UNVERIFIED_SCORE: int = -3
const FALSE_UNVERIFIED_REPUTATION: int = -2
const VERIFY_SKIPPED_SCORE: int = -3

## How a loan approved or countered on documents that don't check out is
## described (graded WORST, but not because of the applicant's risk).
const UNVERIFIED_LOAN_DESCRIPTION: String = "Serious mistake — a loan on documents that didn't check out"

## The grade's player-facing description for this application's decision
## (grade_description(), except a loan made on unverified documents).
func decision_description(grade_value: Grade) -> String:
	if not documents_check_out() and decision != DecisionType.REJECT and grade_value == Grade.WORST:
		return UNVERIFIED_LOAN_DESCRIPTION
	return grade_description(grade_value)

const DOCUMENTS_POLICY_TEXT: String = "Bank policy: a valid photo ID (unexpired, in the applicant's name, with their photo), and a pay stub and bank statement in their name showing the income stated on the form."

## Score/Reputation point table for each Grade (Phase 4e). Kept here
## (rather than on loan_review_screen.gd, where they originally lived)
## since Phase 5d's Branch Manager override needs to re-derive what an
## alternate decision *would have* scored against the same
## risk_assessment — a second copy of this table anywhere else would be a
## tuning hazard. Magnitudes are pitched against teller_screen.gd's
## shift-score constants (-5 to +10): BEST tops that range since a correct
## loan call is the clearest "right answer" this game asks for, WORST goes
## further negative since waving through a bad loan is the single worst
## call available. Reputation deltas are kept deliberately smaller than
## Score — a loan decision is a back-office judgment call, not a
## customer-facing interaction the way a drawer count is, so it shouldn't
## swing reputation as hard as a teller shift does.
const BEST_DECISION_SCORE: int = 10
const PARTIAL_CREDIT_SCORE: int = 3
const BAD_DECISION_SCORE: int = -3
const WORST_DECISION_SCORE: int = -10

const BEST_DECISION_REPUTATION: int = 1
const PARTIAL_CREDIT_REPUTATION: int = 0
const BAD_DECISION_REPUTATION: int = -1
const WORST_DECISION_REPUTATION: int = -2

## Stated denial reasons, graded on top of the Reject decision's own grade
## (Score only; XP follows Score). Pitched at a fifth of a correct loan call
## each, so two right reasons add +4 to a correct denial's +10, and a wrong
## or missing reason costs about what it earns: naming the real problems
## matters, but less than making the right call.
const REASON_RIGHT_SCORE: int = 2
const REASON_WRONG_SCORE: int = -2
const REASON_MISSING_SCORE: int = -1
const MAX_DENIAL_REASONS: int = 2

## Total-DTI guide bands (bank policy): at or under HEALTHY_DTI the
## applicant's payments leave comfortable room; up to STRETCHED_DTI is
## manageable; up to HIGH_DTI is a heavy load; beyond that, unaffordable.
const HEALTHY_DTI: float = 0.36
const STRETCHED_DTI: float = 0.43
const HIGH_DTI: float = 0.50

## Credit score bands used by the risk assessment (FICO-style labels, see
## credit_score_band()).
const GOOD_CREDIT: int = 670
const FAIR_CREDIT: int = 580
const VERY_GOOD_CREDIT: int = 740

## Policy looks for two years in the same job or line of work.
const STEADY_EMPLOYMENT_MONTHS: int = 24

## "Income too low for the amount": the new loan's payment alone takes more
## than this share of monthly income (a home loan's mortgage payment is
## judged against the usual 28% front-end guide instead).
const NEW_PAYMENT_SHARE_LIMIT: float = 0.20
const HOME_PAYMENT_SHARE_LIMIT: float = 0.28

## A counter-offer below this share of the reference amount (the affordable
## amount, or the request if that's less) is a lowball, not a reasonable
## offer.
const REASONABLE_COUNTER_SHARE: float = 0.5

## A borderline (MEDIUM) applicant who can afford less than this share of
## what they asked for has no counter-offer worth making: a loan a quarter
## the size of the one they need doesn't meet the need. For them Reject is
## the right call, a counter-offer only reasonable (see nothing_affordable()).
const MIN_COUNTER_SHARE: float = 0.25

const HOME_PURPOSE: String = "Home"

## Bank policy per loan purpose: term (months), annual rate and the most the
## branch lends for it. Typical 2025-26 US figures, one rate per purpose
## (real lenders also price by credit score; the game keeps one rate so the
## worksheet stays readable):
## - Auto: 5 years at 7.0%, about what a new-car loan cost a good-credit
##   borrower; $75,000 covers nearly any new car.
## - Home: a 30-year fixed mortgage at 6.5% (principal and interest only).
##   It replaces the applicant's current rent, so the new payment becomes
##   their housing payment. $800,000 is about the conforming loan limit.
## - Personal: an unsecured 3-year loan at 12.0%, about the average personal
##   loan rate; capped at $50,000.
## - Business: a 10-year small-business term loan at 9.0% (about prime plus
##   two points); capped at $250,000 for a branch to decide.
const PURPOSE_TERMS: Dictionary = {
	"Auto": {"months": 60, "rate": 0.07, "max": 75000.0},
	"Home": {"months": 360, "rate": 0.065, "max": 800000.0},
	"Personal": {"months": 36, "rate": 0.12, "max": 50000.0},
	"Business": {"months": 120, "rate": 0.09, "max": 250000.0},
}

@export var applicant_name: String = ""
@export var requested_amount: float = 0.0
@export var credit_score: int = 0
@export var annual_income: float = 0.0
## Total outstanding balance on the applicant's existing debt — a balance,
## not a payment. See monthly_debt_payments for what DTI actually uses.
@export var existing_debt: float = 0.0
## The applicant's current required monthly payments on existing_debt.
@export var monthly_debt_payments: float = 0.0
## Rent or mortgage, monthly. A Home loan replaces it (see
## housing_payment_after_loan()).
@export var monthly_housing_payment: float = 0.0
## Time in the current job or line of work.
@export var employment_months: int = 0
@export var loan_purpose: String = ""
@export var risk_tier: RiskTier = RiskTier.MEDIUM
## Index into CustomerNPC.CUSTOMER_FRAME_SETS: the applicant's portrait on the
## review screen. Chosen apart from every financial value (fair lending: see
## LoanApplicantGenerator); nothing graded ever reads it, or the name.
@export var applicant_look: int = 0

## --- The documents the applicant hands over (LoanApplicantGenerator
## .issue_documents()). The application form's own figure is annual_income,
## the income they stated. No date of birth on the ID: lending never sees an
## applicant's age (fair lending). ---
@export var documents_issued: bool = false
## Hidden, for grading only: what's wrong, if anything.
@export var doc_problem: DocProblem = DocProblem.NONE
@export var id_problem: IdCard.Problem = IdCard.Problem.NONE
## The photo ID as shown (false: none).
@export var id_presented: bool = true
@export var id_holder_name: String = ""
@export var id_number: String = ""
@export var id_expiry_date: int = 0
@export var id_portrait_look: int = 0
## The pay stub (false: none): this month's gross and net pay.
@export var has_pay_stub: bool = true
@export var stub_name: String = ""
@export var stub_employer: String = ""
@export var stub_monthly_gross: float = 0.0
@export var stub_monthly_net: float = 0.0
## Last month's bank statement (false: none): the payroll deposits, whole
## dollars.
@export var has_statement: bool = true
@export var statement_name: String = ""
@export var statement_deposits: PackedInt32Array = PackedInt32Array()

## Computed from the worksheet by calculate_risk_assessment() (cached here
## the first time a screen runs the credit check math). Never shown to the
## player; grade_decision() grades the player's decision against this alone.
## Exported (like the decision below) so a waiting application saves whole
## (LoanDeskManager); it's worked out again when loaded.
@export var risk_assessment: RiskTier = RiskTier.MEDIUM

## The decision (Phase 4d) — grade_decision() grades this against
## risk_assessment. decision_amount holds the approved/countered amount; for
## APPROVE it's always requested_amount, for REJECT it's unused (0.0), for
## COUNTER_OFFER it's whatever amount was proposed.
@export var decision: DecisionType = DecisionType.NONE
@export var decision_amount: float = 0.0

# --- terms and payments ----------------------------------------------------------

func term_months() -> int:
	return _terms().get("months", 60)

func annual_rate() -> float:
	return _terms().get("rate", 0.10)

func policy_maximum() -> float:
	return _terms().get("max", 0.0)

func _terms() -> Dictionary:
	return PURPOSE_TERMS.get(loan_purpose, {})

## The standard amortization formula: the fixed monthly payment that repays
## `principal` over `months` at `annual_rate` (r = rate / 12):
## payment = principal × r / (1 − (1 + r)^−months).
static func monthly_payment(principal: float, rate: float, months: int) -> float:
	if months <= 0 or principal <= 0.0:
		return 0.0
	var r := rate / 12.0
	if r <= 0.0:
		return principal / months
	return principal * r / (1.0 - pow(1.0 + r, -months))

## The inverse: the principal a fixed monthly `payment` repays over `months`.
static func principal_for_payment(payment: float, rate: float, months: int) -> float:
	if months <= 0 or payment <= 0.0:
		return 0.0
	var r := rate / 12.0
	if r <= 0.0:
		return payment * months
	return payment * (1.0 - pow(1.0 + r, -months)) / r

func monthly_income() -> float:
	return annual_income / 12.0

## The new loan's monthly payment for `amount` (the requested amount by
## default) at this purpose's term and rate.
func new_loan_payment(amount: float = -1.0) -> float:
	return monthly_payment(requested_amount if amount < 0.0 else amount, annual_rate(), term_months())

func replaces_housing() -> bool:
	return loan_purpose == HOME_PURPOSE

## A home loan's mortgage payment replaces the current rent or mortgage.
func housing_payment_after_loan(amount: float = -1.0) -> float:
	return new_loan_payment(amount) if replaces_housing() else monthly_housing_payment

# --- ratios ------------------------------------------------------------------

## Front-end DTI: housing ÷ gross monthly income (housing after the loan, so
## a home loan's new mortgage payment).
func front_end_dti(amount: float = -1.0) -> float:
	if annual_income <= 0.0:
		return 0.0
	return housing_payment_after_loan(amount) / monthly_income()

## Total (back-end) DTI: housing + existing debt payments + the new loan's
## payment, ÷ gross monthly income. A debt *balance* never enters it (B9).
func total_dti(amount: float = -1.0) -> float:
	if annual_income <= 0.0:
		return 0.0
	var monthly := housing_payment_after_loan(amount) + monthly_debt_payments
	if not replaces_housing():
		monthly += new_loan_payment(amount)
	return monthly / monthly_income()

## Total DTI before the new loan: today's housing and debt payments.
func dti_before_loan() -> float:
	if annual_income <= 0.0:
		return 0.0
	return (monthly_housing_payment + monthly_debt_payments) / monthly_income()

## The new loan's payment as a share of income.
func new_payment_share() -> float:
	if annual_income <= 0.0:
		return 0.0
	return new_loan_payment() / monthly_income()

## The largest amount the applicant could carry at HEALTHY_DTI total DTI,
## rounded down to $100 and capped at the policy maximum; 0 when today's
## payments already use up the healthy share.
func affordable_amount() -> float:
	var room := HEALTHY_DTI * monthly_income() - monthly_debt_payments
	if not replaces_housing():
		room -= monthly_housing_payment
	if room <= 0.0:
		return 0.0
	var amount := floorf(principal_for_payment(room, annual_rate(), term_months()) / 100.0) * 100.0
	return minf(amount, policy_maximum())

## What a counter-offer is measured against: the affordable amount, or the
## request when that's smaller.
func counter_offer_reference() -> float:
	return minf(affordable_amount(), requested_amount)

## A borderline applicant with no counter-offer worth making: MEDIUM risk,
## and what they can afford at a healthy total DTI is under MIN_COUNTER_SHARE
## of the request. Works the tier out itself, so it never depends on
## risk_assessment having been set.
func nothing_affordable() -> bool:
	return calculate_risk_assessment() == RiskTier.MEDIUM and affordable_amount() < MIN_COUNTER_SHARE * requested_amount

# --- the risk assessment ----------------------------------------------------------

## Standard FICO-style band label for a credit score. Purely descriptive
## terminology (not a risk verdict) — safe to show to the player.
static func credit_score_band(score: int) -> String:
	if score >= 800:
		return "Excellent"
	elif score >= VERY_GOOD_CREDIT:
		return "Very Good"
	elif score >= GOOD_CREDIT:
		return "Good"
	elif score >= FAIR_CREDIT:
		return "Fair"
	else:
		return "Poor"

## Risk points from the worksheet (lower = safer), summed into a tier by
## calculate_risk_assessment():
## - Credit score: 740+ 0 · 670-739 1 · 580-669 3 · under 580 5.
## - Total DTI: up to 36% 0 · up to 43% 1 · up to 50% 3 · over 50% 5.
## - Employment: two years or more 0 · under two years 2.
## A factor at its weak level (credit under 670, DTI over 43%, under two
## years) costs 2 points or more, and the 1-point levels together reach only
## 2, so every MEDIUM or HIGH application has at least one weak point.
func risk_points() -> int:
	var points := 0
	if credit_score < FAIR_CREDIT:
		points += 5
	elif credit_score < GOOD_CREDIT:
		points += 3
	elif credit_score < VERY_GOOD_CREDIT:
		points += 1

	var dti := total_dti()
	if dti > HIGH_DTI:
		points += 5
	elif dti > STRETCHED_DTI:
		points += 3
	elif dti > HEALTHY_DTI:
		points += 1

	if employment_months < STEADY_EMPLOYMENT_MONTHS:
		points += 2
	return points

## 0-2 points LOW, 3-4 MEDIUM, 5 or more HIGH.
func calculate_risk_assessment() -> RiskTier:
	var points := risk_points()
	if points <= 2:
		return RiskTier.LOW
	elif points <= 4:
		return RiskTier.MEDIUM
	return RiskTier.HIGH

## The application's real weak points, the right reasons for a denial:
## - TOTAL_DTI: total DTI over 43%.
## - CREDIT_SCORE: under 670.
## - INCOME: the new payment alone is over 20% of income (28% for a home
##   loan), or it's what pushes total DTI over 43% (today's payments are
##   within it).
## - EMPLOYMENT: under two years.
## - AMOUNT: over the policy maximum for the purpose.
## A borderline applicant with nothing affordable (nothing_affordable()) is
## denied for their payments: TOTAL_DTI, unless INCOME already says it.
## Documents that don't check out make UNVERIFIED the only real reason: the
## figures can't be relied on, so nothing else about them is judged.
func weak_points() -> Array[DenialReason]:
	var weak: Array[DenialReason] = []
	if not documents_check_out():
		weak.append(DenialReason.UNVERIFIED)
		return weak
	var dti := total_dti()
	var pushed_over := dti > STRETCHED_DTI and dti_before_loan() <= STRETCHED_DTI
	var share_limit := HOME_PAYMENT_SHARE_LIMIT if replaces_housing() else NEW_PAYMENT_SHARE_LIMIT
	var income := new_payment_share() > share_limit or pushed_over
	if dti > STRETCHED_DTI or (nothing_affordable() and not income):
		weak.append(DenialReason.TOTAL_DTI)
	if credit_score < GOOD_CREDIT:
		weak.append(DenialReason.CREDIT_SCORE)
	if income:
		weak.append(DenialReason.INCOME)
	if employment_months < STEADY_EMPLOYMENT_MONTHS:
		weak.append(DenialReason.EMPLOYMENT)
	if requested_amount > policy_maximum():
		weak.append(DenialReason.AMOUNT)
	return weak

# --- documents ---------------------------------------------------------------

## Everything checks out: a valid ID, and a pay stub and statement in the
## applicant's name showing the income on the form.
func documents_check_out() -> bool:
	return doc_problem == DocProblem.NONE and id_problem == IdCard.Problem.NONE

## The payroll deposits on the statement, added up (whole dollars).
func statement_total() -> int:
	var total := 0
	for deposit in statement_deposits:
		total += deposit
	return total

## The ID as an IdCard (for the shared card text).
func id_card() -> IdCard:
	var card := IdCard.new()
	card.presented = id_presented
	card.holder_name = id_holder_name
	card.id_number = id_number
	card.expiry_date = id_expiry_date
	card.portrait_look = id_portrait_look
	card.problem = id_problem
	return card

## The documents as handed over, one line each, never saying what's wrong:
## for the Branch Manager's staff review.
func documents_summary() -> String:
	var lines: PackedStringArray = []
	lines.append("ID: %s · No. %s · expires %s" % [id_holder_name, id_number, IdCard.date_text(id_expiry_date)] if id_presented else "ID: none shown")
	lines.append("Pay stub: %s · %s gross/mo" % [stub_name, dollars(stub_monthly_gross)] if has_pay_stub else "Pay stub: none")
	lines.append("Statement: %s · payroll deposits %s" % [statement_name, dollars(statement_total())] if has_statement else "Statement: none")
	return "\n".join(lines)

## What was wrong with the documents, for text shown after the fact ("the
## pay stub showed less than the income stated").
func documents_problem_text() -> String:
	var problems: PackedStringArray = []
	if id_problem != IdCard.Problem.NONE:
		problems.append("the ID %s" % KycPolicy.problem_text(id_problem))
	match doc_problem:
		DocProblem.OVERSTATED_INCOME:
			problems.append("the pay stub and statement showed less than the income stated")
		DocProblem.STUB_NAME:
			problems.append("the pay stub was in someone else's name")
		DocProblem.MISSING_STUB:
			problems.append("there was no pay stub")
		DocProblem.MISSING_STATEMENT:
			problems.append("there was no bank statement")
	return " and ".join(problems) if not problems.is_empty() else "the documents checked out"

# --- grading -----------------------------------------------------------------

## Grades decision (4d) against risk_assessment — the hidden read of the
## worksheet, which the player had a chance to reason toward via the credit
## check. A counter-offer is graded on its amount (grade_counter_offer());
## Approve and Reject by type alone. Requires decision to already be set.
func grade_decision() -> Grade:
	if decision == DecisionType.COUNTER_OFFER and documents_check_out():
		return grade_counter_offer(decision_amount)
	return grade_type(decision)

## `decision_type` graded by type against this application's risk_assessment
## (and whether a borderline applicant has anything affordable, and whether
## the documents check out): staff decisions, where no amount is judged.
func grade_type(decision_type: DecisionType) -> Grade:
	return grade(decision_type, risk_assessment, nothing_affordable(), documents_check_out())

## The right decision for this application, by type: Approve LOW, Reject
## HIGH, Counter-Offer MEDIUM, except Reject for a borderline applicant with
## nothing affordable, and Reject whenever the documents don't check out
## (unless `figures_only`: the call on the figures alone, as someone who
## took the documents at face value would make it).
func correct_decision(figures_only: bool = false) -> DecisionType:
	if not documents_check_out() and not figures_only:
		return DecisionType.REJECT
	match risk_assessment:
		RiskTier.LOW:
			return DecisionType.APPROVE
		RiskTier.MEDIUM:
			return DecisionType.REJECT if nothing_affordable() else DecisionType.COUNTER_OFFER
		_:
			return DecisionType.REJECT

## Approve/Low, Reject/High, and Counter-Offer/Medium are each the
## "correct" call for that risk level and grade BEST. Approve/High is the
## worst call (a risky loan waved through) and grades WORST. Reject/Low is
## a bad call in the other direction (an overly cautious pass on a safe
## loan) and grades BAD. Everything else — Counter-Offer on Low/High, or
## Approve/Reject on Medium — is a reasonable call that wasn't the optimal
## one, and grades PARTIAL. A borderline applicant with nothing affordable
## (`nothing_affordable`, see nothing_affordable()) swaps two of those: no
## counter-offer is worth making, so Reject is BEST and Counter-Offer
## PARTIAL. Documents that don't check out (`documents_ok` false) override
## all of it: Approve or Counter-Offer WORST (a loan on income or identity
## nobody verified), Reject BEST. By type only: used where no amount or
## stated reason is judged (staff decisions, the Branch Manager's overrides).
static func grade(decision_type: DecisionType, risk_tier_param: RiskTier, nothing_affordable_param: bool = false, documents_ok: bool = true) -> Grade:
	if not documents_ok:
		return Grade.BEST if decision_type == DecisionType.REJECT else Grade.WORST
	if risk_tier_param == RiskTier.MEDIUM and nothing_affordable_param:
		match decision_type:
			DecisionType.REJECT:
				return Grade.BEST
			DecisionType.COUNTER_OFFER:
				return Grade.PARTIAL
	match decision_type:
		DecisionType.APPROVE:
			match risk_tier_param:
				RiskTier.LOW:
					return Grade.BEST
				RiskTier.MEDIUM:
					return Grade.PARTIAL
				_:
					return Grade.WORST
		DecisionType.REJECT:
			match risk_tier_param:
				RiskTier.HIGH:
					return Grade.BEST
				RiskTier.MEDIUM:
					return Grade.PARTIAL
				_:
					return Grade.BAD
		DecisionType.COUNTER_OFFER:
			match risk_tier_param:
				RiskTier.MEDIUM:
					return Grade.BEST
				_:
					return Grade.PARTIAL
		_:
			# NONE (or any future decision type) should never reach here —
			# callers only invoke grade()/grade_decision() right after
			# recording a real decision. Fails loudly in debug rather than
			# silently being graded as if it were a COUNTER_OFFER.
			assert(false, "grade() requires a recorded decision, got %s" % decision_type)
			return Grade.PARTIAL

## Is `amount` a reasonable, affordable counter-offer? Affordable: no more
## than affordable_amount(). Reasonable: below the request and at least
## REASONABLE_COUNTER_SHARE of the reference (counter_offer_reference()).
func is_affordable_counter(amount: float) -> bool:
	return amount <= affordable_amount()

func is_reasonable_counter(amount: float) -> bool:
	return amount < requested_amount and amount >= REASONABLE_COUNTER_SHARE * counter_offer_reference()

## A counter-offer, graded on its amount:
## - MEDIUM (borderline): affordable and reasonable BEST, otherwise PARTIAL;
##   always PARTIAL when nothing worth offering is affordable
##   (nothing_affordable(): Reject is the right call there).
## - LOW: PARTIAL (they qualified for the full amount).
## - HIGH: an affordable amount PARTIAL; more than they can carry WORST (a
##   risky loan went through, just a smaller one).
func grade_counter_offer(amount: float) -> Grade:
	var affordable := is_affordable_counter(amount)
	match risk_assessment:
		RiskTier.MEDIUM:
			if nothing_affordable():
				return Grade.PARTIAL
			return Grade.BEST if affordable and is_reasonable_counter(amount) else Grade.PARTIAL
		RiskTier.HIGH:
			return Grade.PARTIAL if affordable else Grade.WORST
		_:
			return Grade.PARTIAL

## Player-facing note on a counter-offer's amount (shown with its grade).
func counter_offer_note(amount: float) -> String:
	if not is_affordable_counter(amount):
		return "More than they can carry at a healthy total DTI."
	if amount >= requested_amount:
		return "Not below what they asked for."
	if not is_reasonable_counter(amount):
		return "Affordable, but far below what they could carry."
	return "Affordable at a healthy total DTI."

## Grades the stated reasons for a denial against weak_points(): each right
## reason REASON_RIGHT_SCORE, each wrong one REASON_WRONG_SCORE, and each
## real weak point left out (up to MAX_DENIAL_REASONS in all)
## REASON_MISSING_SCORE. Returns {right, wrong, missing, score}.
func grade_denial_reasons(reasons: Array[DenialReason]) -> Dictionary:
	var weak := weak_points()
	var right := 0
	var wrong := 0
	for reason in reasons:
		if weak.has(reason):
			right += 1
		else:
			wrong += 1
	var missing := maxi(0, mini(MAX_DENIAL_REASONS, weak.size()) - right)
	var score := right * REASON_RIGHT_SCORE + wrong * REASON_WRONG_SCORE + missing * REASON_MISSING_SCORE
	return {"right": right, "wrong": wrong, "missing": missing, "score": score}

## The whole grade of the player's decision (already set on `decision` and
## `decision_amount`), with the stated `reasons` for a rejection and whether
## the documents were `verified` before deciding. Returns {grade, score,
## reputation, reasons (grade_denial_reasons(), rejections only), caught,
## false_unverified, skipped}:
## - documents that don't check out: Reject naming UNVERIFIED is BEST
##   (caught); Reject for other reasons only PARTIAL; Approve or Counter-Offer
##   WORST;
## - documents fine: graded as before; naming UNVERIFIED on them adds
##   FALSE_UNVERIFIED_SCORE/REPUTATION;
## - either way, not verified first adds VERIFY_SKIPPED_SCORE.
func grade_documents(reasons: Array[DenialReason], verified: bool) -> Dictionary:
	var ok := documents_check_out()
	var rejected := decision == DecisionType.REJECT
	var grade_value := grade_decision()
	var caught := not ok and rejected and reasons.has(DenialReason.UNVERIFIED)
	if not ok and rejected and not caught:
		grade_value = Grade.PARTIAL
	var score := score_for_grade(grade_value)
	var reputation := reputation_for_grade(grade_value)
	var reason_grade := {}
	if rejected:
		reason_grade = grade_denial_reasons(reasons)
		var reason_score: int = reason_grade["score"]
		score += reason_score
	var false_unverified := ok and rejected and reasons.has(DenialReason.UNVERIFIED)
	if false_unverified:
		score += FALSE_UNVERIFIED_SCORE
		reputation += FALSE_UNVERIFIED_REPUTATION
	if not verified:
		score += VERIFY_SKIPPED_SCORE
	return {
		"grade": grade_value, "score": score, "reputation": reputation, "reasons": reason_grade,
		"caught": caught, "false_unverified": false_unverified, "skipped": not verified,
	}

static func score_for_grade(grade_value: Grade) -> int:
	match grade_value:
		Grade.BEST:
			return BEST_DECISION_SCORE
		Grade.PARTIAL:
			return PARTIAL_CREDIT_SCORE
		Grade.BAD:
			return BAD_DECISION_SCORE
		_:
			return WORST_DECISION_SCORE

static func reputation_for_grade(grade_value: Grade) -> int:
	match grade_value:
		Grade.BEST:
			return BEST_DECISION_REPUTATION
		Grade.PARTIAL:
			return PARTIAL_CREDIT_REPUTATION
		Grade.BAD:
			return BAD_DECISION_REPUTATION
		_:
			return WORST_DECISION_REPUTATION

## Player-facing summary of a grade — never mentions risk_assessment's
## literal value, staying consistent with how the loan review screen keeps
## it hidden and how Phase 5d's override result re-uses this exact same
## wording rather than stating the risk tier outright.
static func grade_description(grade_value: Grade) -> String:
	match grade_value:
		Grade.BEST:
			return "Correct call"
		Grade.PARTIAL:
			return "Reasonable, but not the optimal call"
		Grade.BAD:
			return "Overly cautious — likely missed a safe loan"
		_:
			return "Risky call — a high-risk loan went through"

## Only ever written to HistoryManager for Branch Manager review (Phase
## 5), never shown to the player while a decision is still being made —
## the whole point of risk_assessment is that it stays hidden until after
## the fact.
static func risk_tier_label(tier: RiskTier) -> String:
	match tier:
		RiskTier.LOW:
			return "low risk"
		RiskTier.MEDIUM:
			return "medium risk"
		_:
			return "high risk"

## Plain player-facing name for a decision type — e.g. for approvals_screen.gd
## to name what the original Loan Officer decision was. Not the same as the
## fuller "Approved at $X"/"Rejected"/"Counter-Offered at $X" action-text
## loan_review_screen.gd builds inline for its own decision_status_label —
## that's a sentence describing an action just taken, this is a bare label
## for referencing an already-recorded decision.
static func decision_type_label(decision_type: DecisionType) -> String:
	match decision_type:
		DecisionType.APPROVE:
			return "Approve"
		DecisionType.REJECT:
			return "Reject"
		_:
			return "Counter-Offer"

static func denial_reason_label(reason: DenialReason) -> String:
	match reason:
		DenialReason.TOTAL_DTI:
			return "Total DTI too high"
		DenialReason.CREDIT_SCORE:
			return "Credit score too low"
		DenialReason.INCOME:
			return "Income too low for the amount"
		DenialReason.EMPLOYMENT:
			return "Employment too short"
		DenialReason.AMOUNT:
			return "Amount too large"
		_:
			return "Income or identity could not be verified"

## "8 years", "1 year 4 months", "10 months".
static func employment_text(months: int) -> String:
	var years := floori(months / 12.0)
	var rest := months % 12
	var parts: PackedStringArray = []
	if years > 0:
		parts.append("%d year%s" % [years, "" if years == 1 else "s"])
	if rest > 0 or years == 0:
		parts.append("%d month%s" % [rest, "" if rest == 1 else "s"])
	return " ".join(parts)

## "$12,100" — whole dollars with thousands separators.
static func dollars(amount: float) -> String:
	var digits := str(absi(roundi(amount)))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if roundi(amount) < 0 else "$") + digits + out

## "23.8%".
static func percent(ratio: float) -> String:
	return "%.1f%%" % (ratio * 100.0)
