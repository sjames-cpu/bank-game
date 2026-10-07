extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/etc.
## (see ScoreManager for why an autoload is the right fit). Owns the
## player's disciplinary record: every MISTAKES_PER_REPORT mistakes from a
## role become one DisciplinaryReport (a Branch Manager written warning),
## and REPORTS_FOR_TERMINATION reports end the career (see
## discipline_letter_screen.gd for the letters, CareerReset for the reset).
##
## Reports carry across shifts and roles — a Teller who becomes a Loan
## Officer keeps their record. Only teller mistakes feed this today
## (teller_screen.gd calls record_mistake() the first time a customer is
## flagged was_mistake); a Loan Officer mistake would call the same
## record_mistake() with Role.LOAN_OFFICER and a REPORT_REASONS entry.
##
## Once the Branch Manager role is unlocked the player IS the manager, so
## the Branch Manager can no longer discipline them: reports stop and the
## existing record is cleared (see _on_branch_manager_unlocked()).
##
## Like the other managers, this only lives in memory for now.

signal reports_changed(count: int)
signal report_issued(report: DisciplinaryReport)
signal termination_issued(reports: Array[DisciplinaryReport])
signal record_cleared_for_promotion(cleared_count: int)

const MISTAKES_PER_REPORT: int = 2
const REPORTS_FOR_TERMINATION: int = 3

## Player-facing reason per role whose mistakes can produce a report.
## Only TELLER is wired up; add LOAN_OFFICER here (and a record_mistake()
## call from the loan review flow) to have loan mistakes feed reports too.
const REPORT_REASONS: Dictionary = {
	DecisionRecord.Role.TELLER: "Repeated transaction errors at the teller desk",
}

var reports: Array[DisciplinaryReport] = []

## Set once the player is a Branch Manager — see class doc.
var is_exempt: bool = false

## Set when the termination letter is issued; nothing more is recorded
## until CareerReset clears it.
var is_terminated: bool = false

## Role -> PackedStringArray of mistakes not yet rolled into a report.
var _pending_mistakes: Dictionary = {}

func _ready() -> void:
	# XPManager is registered before ReportManager in project.godot.
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	is_exempt = XPManager.is_branch_manager_unlocked

func record_mistake(role: DecisionRecord.Role, description: String) -> void:
	if is_exempt or is_terminated:
		return
	var pending: PackedStringArray = _pending_mistakes.get(role, PackedStringArray())
	pending.append(description)
	_pending_mistakes[role] = pending
	if pending.size() >= MISTAKES_PER_REPORT:
		_pending_mistakes.erase(role)
		_issue_report(role, pending)

func get_report_count() -> int:
	return reports.size()

## "Reports: 1 / 3", or a note that managers aren't subject to reports.
func status_text() -> String:
	if is_exempt:
		return "Reports: n/a (manager)"
	return "Reports: %d / %d" % [reports.size(), REPORTS_FOR_TERMINATION]

func _issue_report(role: DecisionRecord.Role, items: PackedStringArray) -> void:
	var report := DisciplinaryReport.new()
	report.number = reports.size() + 1
	report.role = role
	report.reason = REPORT_REASONS.get(role, "Repeated errors")
	report.items = items
	report.timestamp = Time.get_datetime_string_from_system()
	reports.append(report)
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Written warning %d/%d from the Branch Manager: %s (%s)" % [report.number, REPORTS_FOR_TERMINATION, report.reason, ", ".join(items)],
		"Report %d/%d" % [report.number, REPORTS_FOR_TERMINATION]
	)
	reports_changed.emit(reports.size())

	if reports.size() >= REPORTS_FOR_TERMINATION:
		is_terminated = true
		HistoryManager.add_record(
			DecisionRecord.Role.DISCIPLINARY,
			"Terminated by the Branch Manager after %d disciplinary reports" % reports.size(),
			"Terminated"
		)
		termination_issued.emit(reports)
	else:
		report_issued.emit(report)

## TODO: managers are outside the Branch Manager's authority, so discipline
## for them belongs to a future Regional Manager review system — until that
## exists, a Branch Manager simply can't receive reports.
func _on_branch_manager_unlocked() -> void:
	if is_terminated or is_exempt:
		return
	var cleared := reports.size()
	reports.clear()
	_pending_mistakes.clear()
	is_exempt = true
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Disciplinary record cleared on promotion to Branch Manager (%d report%s removed)" % [cleared, "" if cleared == 1 else "s"],
		"Cleared"
	)
	reports_changed.emit(0)
	record_cleared_for_promotion.emit(cleared)

func reset() -> void:
	reports.clear()
	_pending_mistakes.clear()
	is_exempt = false
	is_terminated = false
	reports_changed.emit(0)
