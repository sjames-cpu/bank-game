extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/etc.
## (see ScoreManager for why an autoload is the right fit). Owns the
## player's disciplinary record: every MISTAKES_PER_REPORT mistakes from a
## role become one DisciplinaryReport (a Branch Manager written warning),
## and REPORTS_FOR_TERMINATION reports end the career (only
## InterviewManager.PROBATION_REPORTS_FOR_TERMINATION while on probation;
## report_limit() gives the current one) (see
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
## existing record is cleared (see _on_branch_manager_unlocked()). Managers
## answer to the Regional Manager instead (RegionalManager's reviews); a
## demotion to Loan Officer makes reports apply again, from none
## (_on_branch_manager_demoted()).
##
## Saved with the career (save_data()/load_data(), see SaveGame). A
## terminated career has no save, so is_terminated never is.

signal reports_changed(count: int)
signal report_issued(report: DisciplinaryReport)
signal termination_issued(reports: Array[DisciplinaryReport])

const MISTAKES_PER_REPORT: int = 2
const REPORTS_FOR_TERMINATION: int = 3

## Player-facing reason per role whose mistakes can produce a report.
## Only TELLER is wired up; add LOAN_OFFICER here (and a record_mistake()
## call from the loan review flow) to have loan mistakes feed reports too.
const REPORT_REASONS: Dictionary = {
	DecisionRecord.Role.TELLER: "Repeated transaction errors at the teller desk",
}
## The report a Teller or Loan Officer gets when Reputation falls to 0
## (ReputationManager.reputation_reached_zero).
const ZERO_REPUTATION_REASON: String = "Customer satisfaction has fallen to zero"

var reports: Array[DisciplinaryReport] = []

## Set once the player is a Branch Manager — see class doc.
var is_exempt: bool = false

## Set when the termination letter is issued; nothing more is recorded
## until CareerReset clears it.
var is_terminated: bool = false

## How many reports the promotion to Branch Manager removed — read by the
## promotion letter (discipline_letter_screen.gd), which reports the
## cleared record itself rather than a separate notice. Set before the
## letter reads it: this autoload connects to branch_manager_unlocked
## before any scene does.
var reports_cleared_on_promotion: int = 0

## Role -> PackedStringArray of mistakes not yet rolled into a report.
var _pending_mistakes: Dictionary = {}

func _ready() -> void:
	# XPManager is registered before ReportManager in project.godot.
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	XPManager.branch_manager_demoted.connect(_on_branch_manager_demoted)
	ReputationManager.reputation_reached_zero.connect(_on_reputation_reached_zero)
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

## How many reports end the career right now: REPORTS_FOR_TERMINATION, or
## fewer while on probation (InterviewManager.report_limit()).
func report_limit() -> int:
	return InterviewManager.report_limit()

## "Reports: 1 / 3" ("1 / 2" on probation), or a note that managers aren't
## subject to reports.
func status_text() -> String:
	if is_exempt:
		return "Reports: n/a (manager)"
	return "Reports: %d / %d" % [reports.size(), report_limit()]

## Reputation fell to 0: one report, in the player's current role (a Branch
## Manager gets a regional warning instead, from RegionalManager).
func _on_reputation_reached_zero() -> void:
	if is_exempt or is_terminated:
		return
	var role := DecisionRecord.Role.LOAN_OFFICER if XPManager.is_loan_officer_unlocked else DecisionRecord.Role.TELLER
	_issue_report(role, PackedStringArray(), ZERO_REPUTATION_REASON)

## `items`: the mistakes behind the report (none for a zero-Reputation one).
func _issue_report(role: DecisionRecord.Role, items: PackedStringArray, reason: String = "") -> void:
	var report := DisciplinaryReport.new()
	report.number = reports.size() + 1
	report.role = role
	report.reason = reason if reason != "" else REPORT_REASONS.get(role, "Repeated errors")
	report.items = items
	report.timestamp = GameClock.timestamp()
	reports.append(report)
	var limit := report_limit()
	var details := " (%s)" % ", ".join(items) if not items.is_empty() else ""
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Written warning %d/%d from the Branch Manager: %s%s" % [report.number, limit, report.reason, details],
		"Report %d/%d" % [report.number, limit]
	)
	# A report during probation starts its clean-shift count over.
	InterviewManager.note_report()
	reports_changed.emit(reports.size())

	if reports.size() >= limit:
		is_terminated = true
		HistoryManager.add_record(
			DecisionRecord.Role.DISCIPLINARY,
			"Terminated by the Branch Manager after %d disciplinary reports" % reports.size(),
			"Terminated"
		)
		termination_issued.emit(reports)
	else:
		report_issued.emit(report)

## Managers are outside the Branch Manager's authority: their discipline is
## the Regional Manager's review (RegionalManager), so a Branch Manager can't
## receive reports.
func _on_branch_manager_unlocked() -> void:
	if is_terminated or is_exempt:
		return
	var cleared := reports.size()
	reports_cleared_on_promotion = cleared
	reports.clear()
	_pending_mistakes.clear()
	is_exempt = true
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Disciplinary record cleared on promotion to Branch Manager (%d report%s removed)" % [cleared, "" if cleared == 1 else "s"],
		"Cleared"
	)
	reports_changed.emit(0)

## Demoted to Loan Officer: the branch's reports apply again, starting from
## none (the record was cleared at promotion).
func _on_branch_manager_demoted() -> void:
	if is_terminated:
		return
	reports.clear()
	_pending_mistakes.clear()
	is_exempt = false
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Disciplinary reports apply again after the demotion to Loan Officer (0 / %d)" % report_limit(),
		"Reports apply"
	)
	reports_changed.emit(0)

func reset() -> void:
	reports.clear()
	_pending_mistakes.clear()
	is_exempt = false
	is_terminated = false
	reports_cleared_on_promotion = 0
	reports_changed.emit(0)

## Pending mistakes are keyed by Role as a String (JSON keys are strings).
func save_data() -> Dictionary:
	var saved_reports: Array = []
	for report in reports:
		saved_reports.append(SaveGame.resource_to_dict(report))
	var pending := {}
	for role: int in _pending_mistakes:
		var mistakes: PackedStringArray = _pending_mistakes[role]
		pending[str(role)] = Array(mistakes)
	return {
		"reports": saved_reports,
		"pending_mistakes": pending,
		"is_exempt": is_exempt,
		"reports_cleared_on_promotion": reports_cleared_on_promotion,
	}

func load_data(data: Dictionary) -> void:
	reports.clear()
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "reports")):
		var report := DisciplinaryReport.new()
		SaveGame.fill_resource(report, entry)
		reports.append(report)
	_pending_mistakes.clear()
	var pending := SaveGame.dict_of(data, "pending_mistakes")
	for key: Variant in pending:
		if not key is String:
			continue
		var role_key: String = key
		var mistakes := SaveGame.strings_of(SaveGame.array_of(pending, role_key))
		if role_key.is_valid_int() and not mistakes.is_empty():
			_pending_mistakes[role_key.to_int()] = mistakes
	is_exempt = SaveGame.bool_of(data, "is_exempt", false)
	is_terminated = false
	reports_cleared_on_promotion = SaveGame.int_of(data, "reports_cleared_on_promotion", 0)
	reports_changed.emit(reports.size())
