extends Node
class_name NpcLoanDeskWorker

## A loan desk's staff member deciding loan applications in the background
## (one worker per ScheduleManager.LOAN_DESK_SLOTS desk, `slot_name`).
## teller_room.gd turns Loan Desk 1's `active` off while the player is
## clocked in there; Loan Desks 2 and 3 always work. No walking
## loan customers — one application from its own copy of
## LoanApplicationsData is decided every StaffMember.loan_decision_seconds()
## of unpaused time while the staff member is at the desk.
##
## Decision quality: with StaffMember.loan_correct_chance() (skill / 10) the
## staff member makes the correct call for the application's hidden
## risk_assessment (Approve low / Counter-Offer medium / Reject high);
## otherwise one of the other two decisions. Graded with the existing
## LoanApplication.grade(); BEST counts as correct, anything else as a
## mistake. Logged to HistoryManager as a STAFF record. Never touches the
## player's Score/Reputation/XP.

signal decision_made(application: LoanApplication, staff: StaffMember, correct: bool)

## Fraction of the requested amount offered on a Counter-Offer.
const COUNTER_OFFER_FRACTION: float = 0.6

## The desk (ScheduleManager.SLOT_LOAN_DESK_*) this worker decides for.
@export var slot_name: String = ScheduleManager.SLOT_LOAN_DESK_1

var staff_npc: StaffNPC = null
var active: bool = true

var _applications: Array[LoanApplication] = LoanApplicationsData.get_applications()
var _next_index: int = 0
var _elapsed: float = 0.0

## Works only while the branch is open (BusinessDay); idle at the desk
## before 9 AM and after 5 PM.
func _process(delta: float) -> void:
	if not active or not BusinessDay.is_open() or not is_instance_valid(staff_npc) or staff_npc.state != StaffNPC.State.AT_DESK:
		return
	_elapsed += delta
	if _elapsed >= staff_npc.staff.loan_decision_seconds():
		_elapsed = 0.0
		decide_next()

## Decides the next application now (tests call it directly; see
## staff_review_test.gd).
func decide_next() -> void:
	var staff := staff_npc.staff
	var application := _applications[_next_index]
	_next_index = (_next_index + 1) % _applications.size()
	application.risk_assessment = application.calculate_risk_assessment()

	var right := _correct_decision(application.risk_assessment)
	var decision := right
	if randf() >= staff.loan_correct_chance():
		var others: Array = [LoanApplication.DecisionType.APPROVE, LoanApplication.DecisionType.REJECT, LoanApplication.DecisionType.COUNTER_OFFER]
		others.erase(right)
		decision = others.pick_random()
	application.decision = decision
	application.decision_amount = _decision_amount(application, decision)

	var grade := LoanApplication.grade(decision, application.risk_assessment)
	var correct := grade == LoanApplication.Grade.BEST
	var action := _action_text(application, decision)
	HistoryManager.add_staff_record(
		staff.staff_name,
		slot_name,
		"%s (%s) %s %s's $%.0f %s loan — %s" % [staff.staff_name, slot_name, action, application.applicant_name, application.requested_amount, application.loan_purpose.to_lower(), LoanApplication.grade_description(grade)],
		"Correct" if correct else "Mistake"
	)
	StaffReviewManager.add_loan_decision(staff, slot_name, application, grade)
	staff_npc.say("%s: %s" % [LoanApplication.decision_type_label(decision), application.applicant_name], 3.0)
	decision_made.emit(application, staff, correct)

static func _correct_decision(risk: LoanApplication.RiskTier) -> LoanApplication.DecisionType:
	match risk:
		LoanApplication.RiskTier.LOW:
			return LoanApplication.DecisionType.APPROVE
		LoanApplication.RiskTier.MEDIUM:
			return LoanApplication.DecisionType.COUNTER_OFFER
		_:
			return LoanApplication.DecisionType.REJECT

static func _decision_amount(application: LoanApplication, decision: LoanApplication.DecisionType) -> float:
	match decision:
		LoanApplication.DecisionType.APPROVE:
			return application.requested_amount
		LoanApplication.DecisionType.COUNTER_OFFER:
			return roundf(application.requested_amount * COUNTER_OFFER_FRACTION / 100.0) * 100.0
		_:
			return 0.0

static func _action_text(application: LoanApplication, decision: LoanApplication.DecisionType) -> String:
	match decision:
		LoanApplication.DecisionType.APPROVE:
			return "approved"
		LoanApplication.DecisionType.COUNTER_OFFER:
			return "counter-offered $%.0f on" % application.decision_amount
		_:
			return "rejected"
