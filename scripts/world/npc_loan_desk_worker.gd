extends Node
class_name NpcLoanDeskWorker

## A loan desk's staff member deciding loan applications in the background
## (one worker per ScheduleManager.LOAN_DESK_SLOTS desk, `slot_name`).
## teller_room.gd turns Loan Desk 1's `active` off while the player is
## clocked in there; Loan Desks 2 and 3 always work. Applicants walk in
## (the desk's LoanDeskSeat: a new applicant from LoanDeskManager, generated
## by LoanApplicantGenerator, no name repeated within the business day) while
## the branch is open, a few seconds after the last one left; once seated,
## they're decided after StaffMember.loan_decision_seconds() of unpaused
## time with the staff member at the desk, and walk out with a reaction.
## After 5 PM nobody new comes in; anyone seated is still decided.
##
## Documents first (bank policy): an applicant whose documents don't check
## out (LoanApplication.documents_check_out()) is caught and rejected, except
## with StaffMember.doc_miss_chance() (from skill), when the staff member
## misses it and decides on the figures as if they were fine. A miss is a
## mistake and goes to staff review: Serious if they approved or counter-offered,
## Minor if they rejected anyway.
##
## Decision quality on the figures: with StaffMember.loan_correct_chance() (skill / 10) the
## staff member makes the correct call for the application's hidden
## risk_assessment, read from the underwriting worksheet
## (LoanApplication.correct_decision(): Approve low / Counter-Offer medium at
## the affordable amount, or Reject when nothing worth offering is affordable
## / Reject high); otherwise one of the other two decisions. Graded by type
## with LoanApplication.grade_type(); BEST counts as correct, anything else as a
## mistake. Logged to HistoryManager as a STAFF record. Never touches the
## player's Score/Reputation/XP.

signal decision_made(application: LoanApplication, staff: StaffMember, correct: bool)

## Fraction of the requested amount offered on a Counter-Offer when the
## worksheet leaves nothing affordable to offer.
const COUNTER_OFFER_FRACTION: float = 0.6

## The desk (ScheduleManager.SLOT_LOAN_DESK_*) this worker decides for.
@export var slot_name: String = ScheduleManager.SLOT_LOAN_DESK_1

## Seconds between one applicant leaving and the next walking in.
const ARRIVAL_GAP_RANGE: Array[float] = [2.0, 6.0]

var staff_npc: StaffNPC = null
var active: bool = true
## This desk's seat (the room sets it). Without one, an application is
## decided every loan_decision_seconds() with nobody walking in.
var seat: LoanDeskSeat = null
## Whether staff can miss a document problem (tests switch it off to make
## every check right).
var staff_doc_slips: bool = true

var _elapsed: float = 0.0
var _gap: float = 0.0
## Paces arrivals (presentation only); never the global generator.
var pace_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	pace_rng.randomize()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(staff_npc) or staff_npc.state != StaffNPC.State.AT_DESK:
		return
	if seat == null:
		if not BusinessDay.is_open():
			return
		_elapsed += delta
		if _elapsed >= staff_npc.staff.loan_decision_seconds():
			_elapsed = 0.0
			decide_next()
		return
	match seat.phase:
		LoanDeskSeat.Phase.EMPTY:
			# New applicants only while the branch is open.
			if not BusinessDay.is_open():
				return
			_gap -= delta
			if _gap <= 0.0 and LoanDeskSeat.entrance_clear():
				_elapsed = 0.0
				seat.arrive(LoanDeskManager.next_staff_application())
		LoanDeskSeat.Phase.SEATED:
			_elapsed += delta
			if _elapsed >= staff_npc.staff.loan_decision_seconds():
				var application := seat.application
				decide_next(application)
				seat.send_off_after_decision(application)
				_gap = pace_rng.randf_range(ARRIVAL_GAP_RANGE[0], ARRIVAL_GAP_RANGE[1])

## The desk is changing hands (the player clocking in at Loan Desk 1): anyone
## at it or on their way leaves.
func release_seat() -> void:
	if seat != null and not seat.is_empty():
		seat.send_off(LoanApplicantNPC.SENT_AWAY_LINE)

## Decides an application now: `application` when given (the seated walk-in,
## or a sample in tests), else a new applicant from LoanDeskManager (tests
## call it directly; see staff_review_test.gd and loan_worksheet_test.gd).
func decide_next(application: LoanApplication = null) -> void:
	var staff := staff_npc.staff
	if application == null:
		application = LoanDeskManager.next_staff_application()
	application.risk_assessment = application.calculate_risk_assessment()

	# The documents first. A problem is caught (and the application rejected)
	# unless the staff member misses it; a miss is decided on the figures.
	var problem := not application.documents_check_out()
	var docs_missed := problem and staff_doc_slips and _check_rng(application).randf() < staff.doc_miss_chance()
	var right := LoanApplication.DecisionType.REJECT if problem and not docs_missed else application.correct_decision(true)
	var decision := right
	# A caught problem is a rejection; otherwise the call on the figures can
	# go wrong.
	var caught := problem and not docs_missed
	if not caught and randf() >= staff.loan_correct_chance():
		var others: Array = [LoanApplication.DecisionType.APPROVE, LoanApplication.DecisionType.REJECT, LoanApplication.DecisionType.COUNTER_OFFER]
		others.erase(right)
		decision = others.pick_random()
	application.decision = decision
	application.decision_amount = _decision_amount(application, decision)

	var grade := application.grade_type(decision)
	# A miss that happened to end in a rejection was still the wrong reason.
	if docs_missed and decision == LoanApplication.DecisionType.REJECT:
		grade = LoanApplication.Grade.PARTIAL
	var correct := grade == LoanApplication.Grade.BEST and not docs_missed
	var action := _action_text(application, decision)
	if problem and not docs_missed:
		action = "rejected (documents didn't check out)"
	elif docs_missed:
		action += " (missed: %s)" % application.documents_problem_text()
	HistoryManager.add_staff_record(
		staff.staff_name,
		slot_name,
		"%s (%s) %s %s's $%.0f %s loan — %s" % [staff.staff_name, slot_name, action, application.applicant_name, application.requested_amount, application.loan_purpose.to_lower(), application.decision_description(grade)],
		"Correct" if correct else "Mistake"
	)
	StaffReviewManager.add_loan_decision(staff, slot_name, application, grade, docs_missed)
	staff_npc.say("%s: %s" % [LoanApplication.decision_type_label(decision), application.applicant_name], 3.0)
	decision_made.emit(application, staff, correct)

## Whether a staff member misses this applicant's document problem: rolled
## from the career's seed and the applicant, never the global generator.
func _check_rng(application: LoanApplication) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([LoanDeskManager.career_seed, "staff-check", slot_name, application.applicant_name, staff_npc.staff.staff_name])
	return rng

static func _decision_amount(application: LoanApplication, decision: LoanApplication.DecisionType) -> float:
	match decision:
		LoanApplication.DecisionType.APPROVE:
			return application.requested_amount
		LoanApplication.DecisionType.COUNTER_OFFER:
			# The worksheet's reference: what they could carry at a healthy
			# total DTI, kept below the request.
			var reference := application.counter_offer_reference()
			if reference >= application.requested_amount:
				reference -= 100.0
			if reference >= 100.0:
				return reference
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
