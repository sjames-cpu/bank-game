extends Node

## Autoload singleton — the Branch Manager's staff review (NPC coworkers,
## step 4). Same in-memory pattern as the other managers.
##
## - Queue: every staff teller mistake and every staff loan decision not
##   graded BEST becomes a StaffReviewItem, but only once the player is the
##   Branch Manager (before that nobody could review it, and a whole teller
##   career's worth would pile up). The queue is its own list, separate from
##   HistoryManager's 200-record staff cap, so unreviewed items are never
##   dropped. Correct work never enters it.
## - Decisions: Issue Report / Give Feedback / Excuse, graded against the
##   item's severity (hidden from the manager until they've decided).
## - Staff records: reports and feedbacks per staff member, for the career.
##   At STAFF_REPORTS_FOR_TERMINATION reports the manager may terminate them
##   (ScheduleManager.dismiss_staff()).
##
## Registered after ScheduleManager and XPManager in project.godot. Cleared
## by reset() (CareerReset).

signal queue_changed
## Emitted after every review decision with the outcome (see decide()).
signal review_decided(result: Dictionary)
signal staff_terminated(staff_name: String, report_reasons: PackedStringArray)

enum Action { REPORT, FEEDBACK, EXCUSE }

const STAFF_REPORTS_FOR_TERMINATION: int = 3
## A minor mistake by someone who has already had this many feedbacks this
## career is a repeated minor mistake, and warrants a report.
const FEEDBACKS_BEFORE_REPEAT: int = 2

## Point table for the manager (proposed 2026-10-12). Pitched at about half
## an Approvals override (ApprovalsScreen: +5/+1 justified, -5/-1
## unjustified), since each review is one small judgment in a queue the
## manager works through every shift.
const FAIR_CALL_SCORE: int = 3 # XP follows Score (x10)
const UNFAIR_REPORT_SCORE: int = -3
const UNFAIR_REPORT_REPUTATION: int = -1
## Excusing a serious mistake, and leaving one unreviewed at clock-out, both
## cost the same Reputation — a customer was badly let down either way.
const EXCUSED_SERIOUS_REPUTATION: int = -2
const IGNORED_SERIOUS_REPUTATION: int = -2
## Only feedback for a serious mistake — handled too leniently, but better
## than excusing it: Issue Report (+3) > Give Feedback (-1) > Excuse (-2).
const FEEDBACK_ON_SERIOUS_REPUTATION: int = -1

## Oldest first.
var queue: Array[StaffReviewItem] = []

## staff name -> PackedStringArray of report reasons (one per report).
var staff_reports: Dictionary = {}
## staff name -> number of feedbacks given.
var staff_feedbacks: Dictionary = {}

func reset() -> void:
	queue.clear()
	staff_reports.clear()
	staff_feedbacks.clear()
	queue_changed.emit()

# --- queueing ----------------------------------------------------------------

func is_collecting() -> bool:
	return XPManager.is_branch_manager_unlocked

## Called by NpcCustomerLine when a staff teller's transaction went wrong
## (and was fixed on the spot).
func add_teller_mistake(staff: StaffMember, slot_name: String, customer: CustomerNPC, mistake: StaffReviewItem.TellerMistake, detail: String) -> StaffReviewItem:
	if not is_collecting():
		return null
	var item := StaffReviewItem.new()
	item.kind = StaffReviewItem.Kind.TELLER
	item.staff_name = staff.staff_name
	item.staff_slot = slot_name
	item.timestamp = Time.get_datetime_string_from_system()
	item.customer_name = customer.display_name
	item.request_type = customer.intent_type
	item.request_amount_cents = customer.intent_amount_cents
	item.teller_mistake = mistake
	item.mistake_detail = detail
	item.severity = StaffReviewItem.Severity.SERIOUS if mistake == StaffReviewItem.TellerMistake.WRONG_ACCOUNT else StaffReviewItem.Severity.MINOR
	_enqueue(item)
	return item

## Called by NpcLoanDeskWorker after every decision; BEST decisions are
## correct work and don't enter the queue.
func add_loan_decision(staff: StaffMember, slot_name: String, application: LoanApplication, grade: LoanApplication.Grade) -> StaffReviewItem:
	if not is_collecting() or grade == LoanApplication.Grade.BEST:
		return null
	var item := StaffReviewItem.new()
	item.kind = StaffReviewItem.Kind.LOAN
	item.staff_name = staff.staff_name
	item.staff_slot = slot_name
	item.timestamp = Time.get_datetime_string_from_system()
	item.applicant_name = application.applicant_name
	item.requested_amount = application.requested_amount
	item.loan_purpose = application.loan_purpose
	item.credit_score = application.credit_score
	item.annual_income = application.annual_income
	item.monthly_debt_payments = application.monthly_debt_payments
	item.debt_to_income = application.debt_to_income_ratio()
	item.loan_to_income = application.loan_to_income_ratio()
	item.decision = application.decision
	item.decision_amount = application.decision_amount
	item.grade = grade
	item.severity = loan_severity(grade)
	_enqueue(item)
	return item

## WORST (a high-risk loan approved) is serious; PARTIAL (a reasonable call,
## not the optimal one) is acceptable. BAD (a safe loan turned down — overly
## cautious) isn't named in the step 4 spec; treated as a minor mistake that
## deserves feedback, like a teller's fixed slip.
static func loan_severity(grade: LoanApplication.Grade) -> StaffReviewItem.Severity:
	match grade:
		LoanApplication.Grade.WORST:
			return StaffReviewItem.Severity.SERIOUS
		LoanApplication.Grade.PARTIAL:
			return StaffReviewItem.Severity.ACCEPTABLE
		_:
			return StaffReviewItem.Severity.MINOR

func _enqueue(item: StaffReviewItem) -> void:
	queue.append(item)
	queue_changed.emit()

# --- staff records -----------------------------------------------------------

func reports_for(staff_name: String) -> int:
	var reports: PackedStringArray = staff_reports.get(staff_name, PackedStringArray())
	return reports.size()

func feedbacks_for(staff_name: String) -> int:
	return staff_feedbacks.get(staff_name, 0)

func record_text(staff_name: String) -> String:
	var feedbacks := feedbacks_for(staff_name)
	return "Reports: %d / %d · Feedback%s: %d" % [reports_for(staff_name), STAFF_REPORTS_FOR_TERMINATION, "" if feedbacks == 1 else "s", feedbacks]

func can_terminate(staff_name: String) -> bool:
	return reports_for(staff_name) >= STAFF_REPORTS_FOR_TERMINATION and not ScheduleManager.is_dismissed(staff_name)

## Staff on the roster who have reached the report limit, in roster order.
func terminable_staff() -> Array[String]:
	var names: Array[String] = []
	for member in ScheduleManager.get_roster():
		if can_terminate(member.staff_name):
			names.append(member.staff_name)
	return names

# --- decisions ---------------------------------------------------------------

## A minor mistake by someone already given FEEDBACKS_BEFORE_REPEAT feedbacks
## is judged as a repeated minor mistake — decided now, not when queued.
func effective_severity(item: StaffReviewItem) -> StaffReviewItem.Severity:
	if item.severity == StaffReviewItem.Severity.MINOR and feedbacks_for(item.staff_name) >= FEEDBACKS_BEFORE_REPEAT:
		return StaffReviewItem.Severity.REPEATED_MINOR
	return item.severity

static func correct_action(severity: StaffReviewItem.Severity) -> Action:
	match severity:
		StaffReviewItem.Severity.SERIOUS, StaffReviewItem.Severity.REPEATED_MINOR:
			return Action.REPORT
		StaffReviewItem.Severity.MINOR:
			return Action.FEEDBACK
		_:
			return Action.EXCUSE

## Applies `action` to `item`: the staff member's record, the manager's
## Score/Reputation/XP, a HistoryManager record, and removal from the queue.
## Returns {severity, action, fair, verdict, explanation, score, reputation,
## xp} for the screen and the shift summary.
func decide(item: StaffReviewItem, action: Action) -> Dictionary:
	var severity := effective_severity(item)
	var fair := action == correct_action(severity)
	var score := 0
	var reputation := 0
	if fair:
		score = FAIR_CALL_SCORE
	elif action == Action.REPORT:
		score = UNFAIR_REPORT_SCORE
		reputation = UNFAIR_REPORT_REPUTATION
	elif action == Action.EXCUSE and severity == StaffReviewItem.Severity.SERIOUS:
		reputation = EXCUSED_SERIOUS_REPUTATION
	elif action == Action.FEEDBACK and severity == StaffReviewItem.Severity.SERIOUS:
		reputation = FEEDBACK_ON_SERIOUS_REPUTATION

	match action:
		Action.REPORT:
			var reasons: PackedStringArray = staff_reports.get(item.staff_name, PackedStringArray())
			reasons.append(short_description(item))
			staff_reports[item.staff_name] = reasons
		Action.FEEDBACK:
			staff_feedbacks[item.staff_name] = feedbacks_for(item.staff_name) + 1

	if score != 0:
		ScoreManager.add_shift_score(score)
	if reputation != 0:
		ReputationManager.add_reputation(reputation)
	var xp := 0
	if score > 0:
		XPManager.add_shift_xp(score)
		xp = score * XPManager.XP_PER_SCORE_POINT

	var verdict := _verdict(severity, action, fair)
	var explanation := _explanation(item, severity, action, fair)
	HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER,
		"Staff review — %s (%s): %s on %s — %s" % [item.staff_name, item.staff_slot, action_label(action), short_description(item), explanation],
		verdict
	)
	queue.erase(item)
	queue_changed.emit()

	var result := {
		"severity": severity,
		"action": action,
		"fair": fair,
		"unfair_report": not fair and action == Action.REPORT,
		"verdict": verdict,
		"explanation": explanation,
		"score": score,
		"reputation": reputation,
		"xp": xp,
	}
	review_decided.emit(result)
	return result

## Branch Manager clock-out: serious items still in the queue cost
## IGNORED_SERIOUS_REPUTATION each and are closed as ignored. Minor and
## acceptable items carry over with no penalty. Returns {count, reputation}.
func close_ignored_serious() -> Dictionary:
	var ignored: Array[StaffReviewItem] = []
	for item in queue:
		if item.severity == StaffReviewItem.Severity.SERIOUS:
			ignored.append(item)
	for item in ignored:
		queue.erase(item)
		ReputationManager.add_reputation(IGNORED_SERIOUS_REPUTATION)
		HistoryManager.add_record(
			DecisionRecord.Role.BRANCH_MANAGER,
			"Staff review — %s (%s): %s left unreviewed at clock-out" % [item.staff_name, item.staff_slot, short_description(item)],
			"Ignored"
		)
	if not ignored.is_empty():
		queue_changed.emit()
	return {"count": ignored.size(), "reputation": ignored.size() * IGNORED_SERIOUS_REPUTATION}

## The manager's choice once a staff member has reached the report limit:
## they leave the branch and the roster (ScheduleManager.dismiss_staff()),
## their remaining queue items go with them, and a letter is shown
## (DisciplineLetterScreen listens to staff_terminated).
func terminate(staff_name: String) -> bool:
	if not can_terminate(staff_name):
		return false
	var reasons: PackedStringArray = staff_reports.get(staff_name, PackedStringArray())
	var leftover: Array[StaffReviewItem] = []
	for item in queue:
		if item.staff_name == staff_name:
			leftover.append(item)
	for item in leftover:
		queue.erase(item)
	var slot := ScheduleManager.slot_of(staff_name)
	ScheduleManager.dismiss_staff(staff_name)
	HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER,
		"Terminated %s%s after %d staff reports" % [staff_name, " (%s now unassigned)" % slot if slot != "" else "", reasons.size()],
		"Terminated"
	)
	queue_changed.emit()
	staff_terminated.emit(staff_name, reasons)
	return true

# --- text ----------------------------------------------------------------------

func action_label(action: Action) -> String:
	match action:
		Action.REPORT:
			return "Issue Report"
		Action.FEEDBACK:
			return "Give Feedback"
		_:
			return "Excuse"

func severity_label(severity: StaffReviewItem.Severity) -> String:
	match severity:
		StaffReviewItem.Severity.SERIOUS:
			return "Serious"
		StaffReviewItem.Severity.MINOR:
			return "Minor"
		StaffReviewItem.Severity.REPEATED_MINOR:
			return "Repeated minor"
		_:
			return "Acceptable"

## One line naming the work, e.g. "wrong account on Sam Chen's $200 deposit".
static func short_description(item: StaffReviewItem) -> String:
	if item.kind == StaffReviewItem.Kind.TELLER:
		return "%s on %s's %s %s" % [item.mistake_detail, item.customer_name, MoneyMath.format(item.request_amount_cents, true), "deposit" if item.request_type == ShiftTransaction.Type.DEPOSIT else "withdrawal"]
	return "%s decision on %s's $%.0f loan" % [LoanApplication.decision_type_label(item.decision), item.applicant_name, item.requested_amount]

func _verdict(severity: StaffReviewItem.Severity, action: Action, fair: bool) -> String:
	if fair:
		return "Fair"
	if action == Action.REPORT:
		return "Too harsh"
	if severity == StaffReviewItem.Severity.ACCEPTABLE:
		return "Not needed"
	return "Too lenient"

func _what_happened(item: StaffReviewItem) -> String:
	if item.kind == StaffReviewItem.Kind.TELLER:
		match item.teller_mistake:
			StaffReviewItem.TellerMistake.WRONG_ACCOUNT:
				return "sending money to the wrong account"
			StaffReviewItem.TellerMistake.WRONG_TYPE:
				return "doing the wrong type of transaction, caught and fixed on the spot,"
			_:
				return "getting the amount wrong, caught and fixed on the spot,"
	match item.grade:
		LoanApplication.Grade.WORST:
			return "approving a high-risk loan"
		LoanApplication.Grade.BAD:
			return "turning down a loan that was likely safe"
		_:
			return "this decision"

func _explanation(item: StaffReviewItem, severity: StaffReviewItem.Severity, action: Action, fair: bool) -> String:
	var what := _what_happened(item)
	match severity:
		StaffReviewItem.Severity.SERIOUS:
			if fair:
				return "Fair — %s is a serious error." % what
			if action == Action.EXCUSE:
				return "Too lenient — %s is a serious error and can't be excused." % what
			return "Too lenient — %s is a serious error; feedback isn't enough, it needed a report." % what
		StaffReviewItem.Severity.MINOR:
			if fair:
				return "Fair — %s is a coaching moment, not a disciplinary matter." % what
			if action == Action.REPORT:
				return "Too harsh — %s doesn't warrant a report; feedback was enough." % what
			return "Too lenient — %s still deserves feedback." % what
		StaffReviewItem.Severity.REPEATED_MINOR:
			var feedbacks := feedbacks_for(item.staff_name) - (1 if action == Action.FEEDBACK else 0)
			if fair:
				return "Fair — %s has already had %d feedbacks for slips like this; a report is the next step." % [item.staff_name, feedbacks]
			return "Too lenient — %s has already had %d feedbacks for slips like this; it was time for a report." % [item.staff_name, feedbacks]
		_:
			if fair:
				return "Fair — this was a reasonable lending call, not a mistake."
			if action == Action.REPORT:
				return "Too harsh — this was a reasonable lending call, not a mistake."
			return "Not needed — this was a reasonable lending call; it could simply be excused."
