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
## the term for each purpose, the rate table by credit band, how the credit
## report counts, the DTI guide bands, the policy maximums and the denial
## reasons are the branch's own lending policy.
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
## CREDIT_HISTORY: a serious mark in the last two years on the credit report
## (appended last so saved values keep their meaning; DENIAL_REASON_ORDER is
## the order they're listed in).
## DOWN_PAYMENT: the loan-to-value is in its purpose's high band (appended
## last too).
enum DenialReason { TOTAL_DTI, CREDIT_SCORE, INCOME, EMPLOYMENT, AMOUNT, UNVERIFIED, CREDIT_HISTORY, DOWN_PAYMENT }

## How the reasons are listed on the review screen: the credit reasons
## together, then the loan's own.
const DENIAL_REASON_ORDER: Array[DenialReason] = [
	DenialReason.TOTAL_DTI, DenialReason.CREDIT_SCORE, DenialReason.CREDIT_HISTORY, DenialReason.INCOME,
	DenialReason.DOWN_PAYMENT, DenialReason.EMPLOYMENT, DenialReason.AMOUNT, DenialReason.UNVERIFIED,
]

## What secures a loan (Collateral fields below): a house (home loans), a
## vehicle (auto), business equipment or property, or nothing.
enum Collateral { NONE, HOUSE, VEHICLE, EQUIPMENT, PROPERTY }

## What's wrong with an applicant's documents besides their ID (which has
## its own IdCard.Problem): the income stated on the form is more than the pay
## stub and statement show; the pay stub is in someone else's name; or the pay
## stub or bank statement is missing. Rolled by LoanApplicantGenerator.
# PAPER_MISMATCH (appended: saved values stay the same): an appraisal, proof of
# down payment or explanation letter an applicant brought back that doesn't
# match the application (which one: LoanFile.mismatched_paper).
enum DocProblem { NONE, OVERSTATED_INCOME, STUB_NAME, MISSING_STUB, MISSING_STATEMENT, PAPER_MISMATCH }

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

## Bank policy per loan purpose: term (months) and the most the branch lends
## for it (the rate comes from RATE_TABLE):
## - Auto: 5 years; $75,000 covers nearly any new car.
## - Home: a 30-year fixed mortgage (principal and interest only). It replaces
##   the applicant's current rent, so the new payment becomes their housing
##   payment. $800,000 is about the conforming loan limit.
## - Personal: an unsecured 3-year loan, capped at $50,000.
## - Business: a 10-year small-business term loan, capped at $250,000 for a
##   branch to decide.
const PURPOSE_TERMS: Dictionary = {
	"Auto": {"months": 60, "max": 75000.0},
	"Home": {"months": 360, "max": 800000.0},
	"Personal": {"months": 36, "max": 50000.0},
	"Business": {"months": 120, "max": 250000.0},
}

## Risk-based pricing (bank policy): the annual rate, in percent, by purpose
## and credit band, best first: Excellent 800+, Very Good 740-799, Good
## 670-739, Fair 580-669, Poor under 580 (credit_score_band()). Pitched at
## typical 2025-26 US rates; the Good column is the one rate per purpose the
## branch used before:
## - Auto (60 months): 5.50 / 6.25 / 7.00 / 10.50 / 14.50. A car secures the
##   loan, so the spread is moderate; subprime auto rates run in the teens.
## - Home (30-year fixed): 6.25 / 6.50 / 6.75 / 7.25 / 8.25. The house
##   secures it and credit moves a mortgage rate least, about two points
##   from best to worst.
## - Personal (36 months, unsecured): 9.50 / 11.00 / 14.00 / 19.00 / 26.00.
##   Nothing secures it, so credit moves it most.
## - Business (120 months): 7.75 / 8.25 / 9.00 / 10.75 / 13.00, about prime
##   plus half a point to prime plus six.
## The rate is the lender's charge for the risk of not being repaid: lower
## credit pays more. It depends on the purpose and the score alone (fair
## lending), and it moves the new payment, the DTI and the amount affordable.
const RATE_TABLE: Dictionary = {
	"Auto": [5.50, 6.25, 7.00, 10.50, 14.50],
	"Home": [6.25, 6.50, 6.75, 7.25, 8.25],
	"Personal": [9.50, 11.00, 14.00, 19.00, 26.00],
	"Business": [7.75, 8.25, 9.00, 10.75, 13.00],
}
## The score range of each RATE_TABLE column, for the worksheet.
const BAND_RANGES: Array[String] = ["800+", "740-799", "670-739", "580-669", "under 580"]

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

## --- The credit report (CreditReport.issue(), from the finance generator
## and the credit score alone; see CreditReport for the policy). Late
## payments and hard inquiries are counted over the last two years and six
## months; serious marks over seven years (months since: 0 means none). An
## application with no report (credit_report_issued false: built in a test,
## or saved before reports) scores no report points. ---
@export var credit_report_issued: bool = false
@export var on_time_percent: int = 100
@export var late_30_days: int = 0
@export var late_60_days: int = 0
@export var late_90_days: int = 0
@export var utilization_percent: int = 0
@export var open_accounts: int = 0
@export var hard_inquiries: int = 0
@export var collections: int = 0
@export var months_since_collection: int = 0
@export var months_since_bankruptcy: int = 0

## --- Collateral (LoanApplicantGenerator.issue_collateral(), from the finance
## generator). A home loan: the purchase price and the bank's appraisal; an
## auto loan: the vehicle's price, which is its value; a business loan: the
## equipment or property pledged, if any, and its value; a personal loan:
## none. An application with no collateral issued (built in a test, or saved
## before collateral) has no loan-to-value and scores no LTV points. ---
@export var collateral_issued: bool = false
@export var collateral_kind: Collateral = Collateral.NONE
## What's being bought (home and auto; 0 otherwise).
@export var purchase_price: float = 0.0
## The appraisal (home), the vehicle's value (auto) or the pledged asset's
## value (business).
@export var collateral_value: float = 0.0

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

## The rate offered: RATE_TABLE for the purpose and the credit band.
func annual_rate() -> float:
	return rate_for(loan_purpose, credit_score)

static func rate_for(purpose: String, score: int) -> float:
	var rates: Array = RATE_TABLE.get(purpose, [])
	if rates.is_empty():
		return 0.10
	var percent_rate: float = rates[CreditReport.band_index(score)]
	return percent_rate / 100.0

## Why this rate: "Priced for Good credit (670-739); auto rates run 5.50% to
## 14.50%, lower credit paying more."
func rate_reason() -> String:
	var rates: Array = RATE_TABLE.get(loan_purpose, [])
	if rates.is_empty():
		return ""
	var best: float = rates[0]
	var worst: float = rates[rates.size() - 1]
	return "Priced for %s credit (%s); %s rates run %.2f%% to %.2f%%, lower credit paying more." % [
		credit_score_band(credit_score), BAND_RANGES[CreditReport.band_index(credit_score)], loan_purpose.to_lower(), best, worst,
	]

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
## default): principal and interest at this purpose's term and rate, plus
## mortgage insurance on a home loan over 80% LTV.
func new_loan_payment(amount: float = -1.0) -> float:
	return principal_and_interest(amount) + mortgage_insurance(amount)

func principal_and_interest(amount: float = -1.0) -> float:
	return monthly_payment(_amount_or_request(amount), annual_rate(), term_months())

func _amount_or_request(amount: float) -> float:
	return requested_amount if amount < 0.0 else amount

# --- collateral and loan-to-value (bank policy) ----------------------------------------

## A loan with collateral the bank can value: a home, a vehicle, or business
## equipment or property.
func is_secured() -> bool:
	return collateral_issued and collateral_kind != Collateral.NONE and collateral_value > 0.0

## What the loan is measured against: the lower of the purchase price and the
## appraisal for a home (the bank never lends against more than either), the
## vehicle's or pledged asset's value otherwise; 0 when unsecured.
func value_for_ltv() -> float:
	if not is_secured():
		return 0.0
	if collateral_kind == Collateral.HOUSE and purchase_price > 0.0:
		return minf(purchase_price, collateral_value)
	return collateral_value

## Loan-to-value: the loan ÷ value_for_ltv(); 0 when unsecured.
func loan_to_value(amount: float = -1.0) -> float:
	var value := value_for_ltv()
	if value <= 0.0:
		return 0.0
	return _amount_or_request(amount) / value

## The appraisal came in under the purchase price.
func has_appraisal_gap() -> bool:
	return is_secured() and collateral_kind == Collateral.HOUSE and collateral_value < purchase_price

## A purchase with a down payment: a home or a vehicle.
func has_down_payment() -> bool:
	return is_secured() and (collateral_kind == Collateral.HOUSE or collateral_kind == Collateral.VEHICLE) and purchase_price > 0.0

## The purchase price minus the loan (negative: the loan is more than the
## price, with taxes, fees or an old loan rolled in).
func down_payment(amount: float = -1.0) -> float:
	return purchase_price - _amount_or_request(amount) if has_down_payment() else 0.0

func down_payment_share(amount: float = -1.0) -> float:
	return down_payment(amount) / purchase_price if has_down_payment() else 0.0

## LTV guide bands per purpose (bank policy): [healthy up to, stretched up
## to]; beyond the second, high.
## - Home: up to 80% (20% down, no mortgage insurance) healthy; up to 95%
##   stretched; over 95% (under 5% down) high.
## - Auto: up to 100% normal (no more than the car is worth); up to 120%
##   stretched (taxes, fees or a small old loan rolled in); over 120% high
##   (the borrower owes far more than the car is worth from day one).
## - Business: up to 75% healthy (what lenders usually advance on equipment
##   or property); up to 100% stretched; over 100% high.
const LTV_BANDS: Dictionary = {"Home": [0.80, 0.95], "Auto": [1.00, 1.20], "Business": [0.75, 1.00]}
const LTV_STRETCHED_POINTS: int = 1
const LTV_HIGH_POINTS: int = 3

## Risk points from the loan-to-value (0 when unsecured): healthy 0,
## stretched 1, high 3.
func ltv_points(amount: float = -1.0) -> int:
	var bands: Array = LTV_BANDS.get(loan_purpose, [])
	if bands.is_empty() or not is_secured():
		return 0
	var ltv := loan_to_value(amount)
	var healthy: float = bands[0]
	var stretched: float = bands[1]
	if ltv <= healthy + 0.000001:
		return 0
	if ltv <= stretched + 0.000001:
		return LTV_STRETCHED_POINTS
	return LTV_HIGH_POINTS

## Mortgage insurance (bank policy): a home loan over 80% LTV pays it, a
## yearly share of the loan by LTV, in the monthly payment until the loan is
## paid down. [LTV up to, yearly rate]: 85% 0.30% · 90% 0.50% · 95% 0.75% ·
## above 1.00%. About what private mortgage insurance costs a good-credit
## borrower; it protects the bank, not the borrower.
const MORTGAGE_INSURANCE_FROM_LTV: float = 0.80
const MORTGAGE_INSURANCE_RATES: Array = [[0.85, 0.0030], [0.90, 0.0050], [0.95, 0.0075], [INF, 0.0100]]

## The yearly mortgage insurance rate at `ltv` (0 at 80% or less).
static func mortgage_insurance_rate(ltv: float) -> float:
	if ltv <= MORTGAGE_INSURANCE_FROM_LTV + 0.000001:
		return 0.0
	for band: Array in MORTGAGE_INSURANCE_RATES:
		var up_to: float = band[0]
		if ltv <= up_to + 0.000001:
			var rate: float = band[1]
			return rate
	return 0.0

## The monthly mortgage insurance on `amount` (0 unless a secured home loan
## over 80% LTV).
func mortgage_insurance(amount: float = -1.0) -> float:
	if not replaces_housing() or not is_secured():
		return 0.0
	return _amount_or_request(amount) * mortgage_insurance_rate(loan_to_value(amount)) / 12.0

## The largest loan (to $100) within the purpose's healthy LTV band: what a
## counter-offer asking for more down would lend. 0 when unsecured.
func healthy_ltv_amount() -> float:
	var bands: Array = LTV_BANDS.get(loan_purpose, [])
	if bands.is_empty() or not is_secured():
		return 0.0
	var healthy: float = bands[0]
	return floorf(value_for_ltv() * healthy / 100.0 + 0.000001) * 100.0

## "home", "vehicle", "equipment", "business property".
static func collateral_name(kind: Collateral) -> String:
	match kind:
		Collateral.HOUSE:
			return "home"
		Collateral.VEHICLE:
			return "vehicle"
		Collateral.EQUIPMENT:
			return "equipment"
		Collateral.PROPERTY:
			return "business property"
		_:
			return "none"

## "$34,000 (10.0%)", or "None ($3,000 over the vehicle's value)".
func down_payment_text(amount: float = -1.0) -> String:
	var down := down_payment(amount)
	if down < 0.0:
		return "None (%s over the %s's price)" % [dollars(-down), collateral_name(collateral_kind)]
	return "%s (%s)" % [dollars(down), percent(down_payment_share(amount))]

## What a counter-offer of `amount` implies, so a smaller loan reads as more
## down: "A $240,000 loan means a $60,000 down payment (20.0%)." For business
## collateral, the share of its value; empty when unsecured.
## When the request's LTV is over the healthy band, the target follows:
## "Healthy LTV needs a loan of $272,000 or less."
func counter_offer_collateral_line(amount: float) -> String:
	var line := ""
	if has_down_payment():
		var down := down_payment(amount)
		if down < 0.0:
			line = "A %s loan is %s over the %s's price: no down payment." % [dollars(amount), dollars(-down), collateral_name(collateral_kind)]
		else:
			line = "A %s loan means a %s down payment (%s)." % [dollars(amount), dollars(down), percent(down_payment_share(amount))]
	elif is_secured():
		line = "A %s loan is %s of the %s's value." % [dollars(amount), percent(loan_to_value(amount)), collateral_name(collateral_kind)]
	if ltv_points() > 0:
		line += " " + healthy_ltv_text()
	return line

## "Healthy LTV needs a loan of $272,000 or less."
func healthy_ltv_text() -> String:
	return "Healthy LTV needs a loan of %s or less." % dollars(healthy_ltv_amount())

## The LTV is one of the application's real weak points (DOWN_PAYMENT): a
## counter-offer must then bring it into the healthy band.
func ltv_is_weak() -> bool:
	return weak_points().has(DenialReason.DOWN_PAYMENT)

## Does a counter-offer of `amount` fix the LTV (within the healthy band)?
func fixes_ltv(amount: float) -> bool:
	return ltv_points(amount) == 0

## One line for the Branch Manager's staff review: "Collateral: home $340,000
## · appraised $326,000 · down $34,000 (10.0%) · LTV 94.0% · mortgage
## insurance $170/mo".
func collateral_summary() -> String:
	if not is_secured():
		return "Collateral: none (unsecured)"
	var parts: PackedStringArray = []
	if has_down_payment():
		parts.append("%s %s" % [collateral_name(collateral_kind), dollars(purchase_price)])
		if collateral_kind == Collateral.HOUSE:
			parts.append("appraised %s" % dollars(collateral_value))
		parts.append("down %s" % down_payment_text())
	else:
		parts.append("%s %s" % [collateral_name(collateral_kind), dollars(collateral_value)])
	parts.append("LTV %s" % percent(loan_to_value()))
	if mortgage_insurance() > 0.0:
		parts.append("mortgage insurance %s/mo" % dollars(mortgage_insurance()))
	return "Collateral: " + " · ".join(parts)

## The principal a monthly `payment` covers, with mortgage insurance at
## `insurance_rate` a year of the principal on top of principal and interest.
static func principal_for_total_payment(payment: float, rate: float, months: int, insurance_rate: float) -> float:
	var per_dollar := monthly_payment(1.0, rate, months) + insurance_rate / 12.0
	if per_dollar <= 0.0:
		return 0.0
	return payment / per_dollar

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
## payments already use up the healthy share. A home loan's mortgage
## insurance counts in the payment (so the amount is searched for: a smaller
## loan has a lower LTV and may pay less insurance, or none).
func affordable_amount() -> float:
	var room := HEALTHY_DTI * monthly_income() - monthly_debt_payments
	if not replaces_housing():
		room -= monthly_housing_payment
	if room <= 0.0:
		return 0.0
	var amount := minf(floorf(principal_for_payment(room, annual_rate(), term_months()) / 100.0) * 100.0, policy_maximum())
	if mortgage_insurance(amount) <= 0.0:
		return amount
	# The payment grows with the amount: the largest $100 step within room.
	var low := 0
	var high := roundi(amount / 100.0)
	while low < high:
		var middle := floori((low + high + 1) / 2.0)
		if new_loan_payment(middle * 100.0) <= room:
			low = middle
		else:
			high = middle - 1
	return low * 100.0

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

## Risk points from the worksheet and the credit report (lower = safer),
## summed into a tier by calculate_risk_assessment():
## - Credit score: 740+ 0 · 670-739 1 · 580-669 3 · under 580 5.
## - Credit report (credit_report_points()): a serious mark in the last two
##   years +2; utilization over 75% +1; a score under 670 with a clean last
##   two years −1.
## - Total DTI: up to 36% 0 · up to 43% 1 · up to 50% 3 · over 50% 5.
## - Employment: two years or more 0 · under two years 2.
## - Loan-to-value (ltv_points(), secured loans): healthy 0 · stretched 1 ·
##   high 3 (LTV_BANDS).
## A factor at its weak level (credit under 670, a recent serious mark, DTI
## over 43%, under two years, a high LTV) costs 2 points or more. The 1-point
## levels (a good score, a stretched DTI, high utilization, a stretched LTV)
## can together reach 3 or more, which weak_points() covers.
func risk_points() -> int:
	return _base_points() + credit_report_points() + ltv_points()

## The risk points without the credit report (for comparing what the report
## changes): the score, DTI, employment and LTV.
func score_only_points() -> int:
	return risk_points() - credit_report_points()

## The risk points without the loan-to-value (for comparing what it changes).
func points_without_ltv() -> int:
	return risk_points() - ltv_points()

func _base_points() -> int:
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
	return tier_for_points(risk_points())

## The tier without the credit report.
func score_only_assessment() -> RiskTier:
	return tier_for_points(score_only_points())

## The tier without the loan-to-value.
func assessment_without_ltv() -> RiskTier:
	return tier_for_points(points_without_ltv())

static func tier_for_points(points: int) -> RiskTier:
	if points <= 2:
		return RiskTier.LOW
	elif points <= 4:
		return RiskTier.MEDIUM
	return RiskTier.HIGH

## --- The credit report in the assessment (bank policy, see CreditReport) ---

## A 90-day late payment, a collection or a bankruptcy in the last two years.
func has_recent_serious_mark() -> bool:
	if not credit_report_issued:
		return false
	var recent := CreditReport.RECENT_MONTHS
	return late_90_days > 0 \
		or (collections > 0 and months_since_collection <= recent) \
		or (months_since_bankruptcy > 0 and months_since_bankruptcy <= recent)

func has_high_utilization() -> bool:
	return credit_report_issued and utilization_percent > CreditReport.HIGH_UTILIZATION_PERCENT

## Nothing late and no serious mark in the last two years, and utilization at
## most 30%.
func has_clean_recent_history() -> bool:
	return credit_report_issued and late_30_days + late_60_days + late_90_days == 0 \
		and not has_recent_serious_mark() and utilization_percent <= CreditReport.CLEAN_UTILIZATION_PERCENT

func credit_report_points() -> int:
	var points := 0
	if has_recent_serious_mark():
		points += CreditReport.SERIOUS_MARK_POINTS
	if has_high_utilization():
		points += CreditReport.HIGH_UTILIZATION_POINTS
	if credit_score < GOOD_CREDIT and has_clean_recent_history():
		points += CreditReport.CLEAN_HISTORY_POINTS
	return points

## The application's real weak points, the right reasons for a denial:
## - TOTAL_DTI: total DTI over 43%.
## - CREDIT_SCORE: under 670 (even when a clean recent history offsets it).
## - CREDIT_HISTORY: a serious mark in the last two years on the credit
##   report (a 90-day late payment, a collection or a bankruptcy).
## - INCOME: the new payment alone is over 20% of income (28% for a home
##   loan), or it's what pushes total DTI over 43% (today's payments are
##   within it).
## - DOWN_PAYMENT: the loan-to-value in its purpose's high band (over 95% for
##   a home, 120% for a car, 100% for business collateral).
## - EMPLOYMENT: under two years.
## - AMOUNT: over the policy maximum for the purpose.
## A borderline applicant with nothing affordable (nothing_affordable()) is
## denied for their payments: TOTAL_DTI, unless INCOME already says it. One
## that's MEDIUM or worse from 1-point factors alone (the generator never
## builds one) is denied for the first stretched one: TOTAL_DTI over 36%, else
## DOWN_PAYMENT for a stretched LTV, else CREDIT_SCORE.
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
	if has_recent_serious_mark():
		weak.append(DenialReason.CREDIT_HISTORY)
	if income:
		weak.append(DenialReason.INCOME)
	if ltv_points() >= LTV_HIGH_POINTS:
		weak.append(DenialReason.DOWN_PAYMENT)
	if employment_months < STEADY_EMPLOYMENT_MONTHS:
		weak.append(DenialReason.EMPLOYMENT)
	if requested_amount > policy_maximum():
		weak.append(DenialReason.AMOUNT)
	if weak.is_empty() and calculate_risk_assessment() != RiskTier.LOW:
		if dti > HEALTHY_DTI:
			weak.append(DenialReason.TOTAL_DTI)
		elif ltv_points() > 0:
			weak.append(DenialReason.DOWN_PAYMENT)
		else:
			weak.append(DenialReason.CREDIT_SCORE)
	return weak

# --- documents ---------------------------------------------------------------

## Everything checks out: a valid ID, and a pay stub and statement in the
## applicant's name showing the income on the form.
func documents_check_out() -> bool:
	return doc_problem == DocProblem.NONE and id_problem == IdCard.Problem.NONE

## A document that is there but wrong, which asking for more documents can't
## fix: the pay stub and statement show less than the stated income, the stub
## is in another name, or the ID's name or photo doesn't match.
func has_forged_document() -> bool:
	return doc_problem == DocProblem.OVERSTATED_INCOME or doc_problem == DocProblem.STUB_NAME or doc_problem == DocProblem.PAPER_MISMATCH or id_problem == IdCard.Problem.NAME_MISMATCH or id_problem == IdCard.Problem.WRONG_PORTRAIT

## Documents that are simply not there (or an expired ID), with nothing
## forged: the applicant can bring them, so asking is the best call.
func is_missing_documents_only() -> bool:
	return not documents_check_out() and not has_forged_document()

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
		DocProblem.PAPER_MISMATCH:
			problems.append("a paper they brought back didn't match the application")
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
##   (nothing_affordable(): Reject is the right call there). When the LTV is
##   a weak point (ltv_is_weak()), BEST also needs the amount to bring the LTV
##   into the healthy band (fixes_ltv()); with DTI weak too, it must fix both.
## - LOW: PARTIAL (they qualified for the full amount).
## - HIGH: an affordable amount PARTIAL; more than they can carry WORST (a
##   risky loan went through, just a smaller one).
func grade_counter_offer(amount: float) -> Grade:
	var affordable := is_affordable_counter(amount)
	match risk_assessment:
		RiskTier.MEDIUM:
			if nothing_affordable():
				return Grade.PARTIAL
			var ltv_ok := not ltv_is_weak() or fixes_ltv(amount)
			return Grade.BEST if affordable and is_reasonable_counter(amount) and ltv_ok else Grade.PARTIAL
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
	if ltv_is_weak() and not fixes_ltv(amount):
		return "Affordable, but the loan-to-value is still %s: %s" % [percent(loan_to_value(amount)), healthy_ltv_text()]
	if ltv_is_weak():
		return "Affordable, with a healthy loan-to-value (%s)." % percent(loan_to_value(amount))
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
	# Missing (not forged) documents: asking for them is the best call, so a
	# rejection, whatever its reasons, is only partial credit.
	var missing_only := is_missing_documents_only()
	var caught := not ok and rejected and reasons.has(DenialReason.UNVERIFIED) and not missing_only
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
		DenialReason.CREDIT_HISTORY:
			return "Recent late payments or collections"
		DenialReason.DOWN_PAYMENT:
			return "Down payment too small for the value"
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
