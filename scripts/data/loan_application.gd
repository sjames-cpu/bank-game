extends Resource
class_name LoanApplication

## A loan application submitted for review. risk_tier is pre-set here
## rather than computed from credit_score/income/debt, simulating a feed
## from an upstream underwriting/scoring system the way a real bank's
## loan queue would arrive pre-flagged — it lets sample data include
## borderline cases where the "official" tier and a naive read of the
## raw numbers don't perfectly agree, which is exactly the kind of
## judgment call the eventual review mini-game should be testing.
## Built in code (see loan_applications_data.gd) rather than loaded from
## .tres files, matching Account/InterviewQuestion.

enum RiskTier { LOW, MEDIUM, HIGH }
enum DecisionType { NONE, APPROVE, REJECT, COUNTER_OFFER }

## Outcome of grade() below — how well a decision matched a risk_assessment.
## BEST is a correct call, PARTIAL is a reasonable-but-not-optimal call,
## BAD/WORST are two levels of wrong (BAD being overly cautious, WORST
## being an outright risky approval).
enum Grade { BEST, PARTIAL, BAD, WORST }

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

@export var applicant_name: String = ""
@export var requested_amount: float = 0.0
@export var credit_score: int = 0
@export var annual_income: float = 0.0
@export var existing_debt: float = 0.0
@export var loan_purpose: String = ""
@export var risk_tier: RiskTier = RiskTier.MEDIUM

## Computed (Phase 4c), not pre-set like risk_tier above — a naive read of
## the raw numbers via calculate_risk_assessment(), cached here the first
## time a screen runs the credit check math so it only needs computing
## once per applicant. Never shown to the player; Phase 4e will use it
## (likely alongside risk_tier) to judge whether the player's decision
## was "correct". Deliberately can disagree with risk_tier on borderline
## applicants — see the class doc above.
var risk_assessment: RiskTier = RiskTier.MEDIUM

## The player's decision (Phase 4d), captured but not yet judged — Phase 4e
## will compare this against risk_tier/risk_assessment for consequences.
## decision_amount holds the approved/countered amount; for APPROVE it's
## always requested_amount, for REJECT it's unused (0.0), for
## COUNTER_OFFER it's whatever amount the player proposed.
var decision: DecisionType = DecisionType.NONE
var decision_amount: float = 0.0

## existing_debt as a fraction of annual_income (e.g. 0.25 == 25%).
func debt_to_income_ratio() -> float:
	if annual_income <= 0.0:
		return 0.0
	return existing_debt / annual_income

## requested_amount as a fraction of annual_income (e.g. 1.5 == 150%).
func loan_to_income_ratio() -> float:
	if annual_income <= 0.0:
		return 0.0
	return requested_amount / annual_income

## Standard FICO-style band label for a credit score. Purely descriptive
## terminology (not a risk verdict) — safe to show to the player.
static func credit_score_band(score: int) -> String:
	if score >= 800:
		return "Excellent"
	elif score >= 740:
		return "Very Good"
	elif score >= 670:
		return "Good"
	elif score >= 580:
		return "Fair"
	else:
		return "Poor"

## Naive point-based read of credit score + debt-to-income + loan-to-income,
## independent of the pre-set risk_tier. Each factor contributes 0-4 points
## (lower = safer); the summed total is bucketed into a RiskTier. Tune the
## thresholds below as the loan review mini-game gets balanced.
func calculate_risk_assessment() -> RiskTier:
	var points := 0

	if credit_score >= 800:
		points += 0
	elif credit_score >= 740:
		points += 1
	elif credit_score >= 670:
		points += 2
	elif credit_score >= 580:
		points += 3
	else:
		points += 4

	var dti := debt_to_income_ratio()
	if dti < 0.20:
		points += 0
	elif dti < 0.35:
		points += 1
	elif dti < 0.50:
		points += 2
	else:
		points += 3

	var lti := loan_to_income_ratio()
	if lti < 1.0:
		points += 0
	elif lti < 2.5:
		points += 1
	elif lti < 5.0:
		points += 2
	else:
		points += 3

	if points <= 2:
		return RiskTier.LOW
	elif points <= 5:
		return RiskTier.MEDIUM
	else:
		return RiskTier.HIGH

## Grades decision (4d) against risk_assessment (4c) — the "hidden" naive
## read of the numbers, not the pre-set risk_tier, since risk_assessment is
## what the player actually had a chance to reason toward via the credit
## check. Requires decision to already be set (not NONE); callers only
## invoke this right after recording a decision. Thin instance wrapper
## around the static grade() below, which is what Phase 5d's Branch
## Manager override re-derives against a stored (decision_type,
## risk_assessment) pair with no live LoanApplication instance to hand.
func grade_decision() -> Grade:
	return grade(decision, risk_assessment)

## Approve/Low, Reject/High, and Counter-Offer/Medium are each the
## "correct" call for that risk level and grade BEST. Approve/High is the
## worst call (a risky loan waved through) and grades WORST. Reject/Low is
## a bad call in the other direction (an overly cautious pass on a safe
## loan) and grades BAD. Everything else — Counter-Offer on Low/High, or
## Approve/Reject on Medium — is a reasonable call that wasn't the optimal
## one, and grades PARTIAL.
static func grade(decision_type: DecisionType, risk_tier_param: RiskTier) -> Grade:
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
		_:
			match risk_tier_param:
				RiskTier.MEDIUM:
					return Grade.BEST
				_:
					return Grade.PARTIAL

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
