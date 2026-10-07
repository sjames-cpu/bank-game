extends Control
class_name DisciplineLetterScreen

## Shows ReportManager's letters from the Branch Manager over whatever
## screen is open: a written-warning popup per report, a full-screen
## termination letter at REPORTS_FOR_TERMINATION, and a short notice when
## the record is cleared on promotion to Branch Manager. Lives in
## teller_room's UI layer (last, so it draws on top); process_mode ALWAYS so
## it works whether or not a desk screen has the tree paused.
##
## Pauses the tree itself while a letter is up if nothing else already had
## it paused — same _paused_by_self pattern as DrawerCountScreen.
##
## The termination letter's only button, "Apply for a new job", wipes all
## career progress (CareerReset) and loads the interview; passing it starts
## a new career in teller_room the usual way (interview_screen.gd).

const INTERVIEW_SCENE: String = "res://scenes/ui/interview_screen.tscn"

const WARNING_BACKDROP: Color = Color(0, 0, 0, 0.6)
const TERMINATION_BACKDROP: Color = Color(0.08, 0.08, 0.1, 1)

enum Mode { NONE, WARNING, TERMINATION, NOTICE }

@onready var backdrop: ColorRect = $Backdrop
@onready var letter_panel: PanelContainer = $LetterPanel
@onready var title_label: Label = $LetterPanel/VBox/TitleLabel
@onready var from_label: Label = $LetterPanel/VBox/FromLabel
@onready var body_label: Label = $LetterPanel/VBox/BodyLabel
@onready var action_button: Button = $LetterPanel/VBox/ActionButton

var _mode: Mode = Mode.NONE
var _paused_by_self: bool = false

## Letters waiting behind the one currently shown, as [Mode, title, body].
var _queue: Array = []

func _ready() -> void:
	visible = false
	action_button.pressed.connect(_on_action_button_pressed)
	ReportManager.report_issued.connect(_on_report_issued)
	ReportManager.termination_issued.connect(_on_termination_issued)
	ReportManager.record_cleared_for_promotion.connect(_on_record_cleared)

func _on_report_issued(report: DisciplinaryReport) -> void:
	var body := "This is a formal written warning, issued for %s.\n\nCustomers affected:\n%s\n\nThis is report %d of %d. Reaching %d reports will result in termination." % [
		report.reason.to_lower(), _bullets(report.items),
		report.number, ReportManager.REPORTS_FOR_TERMINATION, ReportManager.REPORTS_FOR_TERMINATION,
	]
	_enqueue(Mode.WARNING, "Written Warning — Report %d of %d" % [report.number, ReportManager.REPORTS_FOR_TERMINATION], body)

func _on_termination_issued(reports: Array[DisciplinaryReport]) -> void:
	var lines: PackedStringArray = []
	for report in reports:
		lines.append("Report %d — %s: %s" % [report.number, report.reason, ", ".join(report.items)])
	var body := "Following %d disciplinary reports, your employment with the branch is terminated, effective immediately.\n\n%s" % [reports.size(), "\n".join(lines)]
	# Termination supersedes anything still waiting to be shown.
	_queue.clear()
	_show(Mode.TERMINATION, "Notice of Termination", body)

func _on_record_cleared(cleared_count: int) -> void:
	var body := "As Branch Manager you're no longer subject to Branch Manager reports. "
	if cleared_count > 0:
		body += "Your %d previous report%s ha%s been removed from your record." % [cleared_count, "" if cleared_count == 1 else "s", "s" if cleared_count == 1 else "ve"]
	else:
		body += "Your record is clear."
	_enqueue(Mode.NOTICE, "Disciplinary Record Cleared", body)

func _enqueue(mode: Mode, title: String, body: String) -> void:
	if _mode == Mode.TERMINATION:
		return
	if visible:
		_queue.append([mode, title, body])
	else:
		_show(mode, title, body)

func _show(mode: Mode, title: String, body: String) -> void:
	_mode = mode
	title_label.text = title
	from_label.text = "From: Branch Manager"
	body_label.text = body
	backdrop.color = TERMINATION_BACKDROP if mode == Mode.TERMINATION else WARNING_BACKDROP
	action_button.text = "Apply for a new job" if mode == Mode.TERMINATION else "Acknowledge"
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func _on_action_button_pressed() -> void:
	if _mode == Mode.TERMINATION:
		_apply_for_new_job()
		return
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_show(next[0], next[1], next[2])
		return
	visible = false
	_mode = Mode.NONE
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

func _apply_for_new_job() -> void:
	get_tree().paused = false
	CareerReset.reset_all()
	get_tree().change_scene_to_file(INTERVIEW_SCENE)

func _bullets(items: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	for item in items:
		lines.append("• " + item)
	return "\n".join(lines)
