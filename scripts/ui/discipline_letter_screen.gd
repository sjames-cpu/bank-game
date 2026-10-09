extends Control
class_name DisciplineLetterScreen

## Shows ReportManager's letters from the Branch Manager over whatever
## screen is open: a written-warning popup per report and a full-screen
## termination letter at REPORTS_FOR_TERMINATION. Also shows the promotion
## letter when the player becomes Branch Manager (XPManager — held until
## clock-out if earned mid-shift), which includes the cleared disciplinary
## record so the player gets one letter, not two, and the one-time
## "Welcome to Branch Management" orientation on the first Branch Manager
## clock-in (show_branch_orientation_once()). Lives in
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

const BRANCH_MANAGER_SENDER: String = "Branch Manager"
## The promotion makes the player the Branch Manager, so it comes from above.
const PROMOTION_SENDER: String = "Regional Manager"

@onready var backdrop: ColorRect = $Backdrop
@onready var letter_panel: PanelContainer = $LetterPanel
@onready var title_label: Label = $LetterPanel/VBox/TitleLabel
@onready var from_label: Label = $LetterPanel/VBox/FromLabel
@onready var body_label: Label = $LetterPanel/VBox/BodyLabel
@onready var action_button: Button = $LetterPanel/VBox/ActionButton

var _mode: Mode = Mode.NONE
var _paused_by_self: bool = false

## Letters waiting behind the one currently shown, as [Mode, title, body, sender].
var _queue: Array = []

func _ready() -> void:
	visible = false
	action_button.pressed.connect(_on_action_button_pressed)
	ReportManager.report_issued.connect(_on_report_issued)
	ReportManager.termination_issued.connect(_on_termination_issued)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)

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

## ReportManager has already cleared the record by now (it connects to the
## same signal first, as an autoload), so the letter reports that too.
func _on_branch_manager_unlocked() -> void:
	if ReportManager.is_terminated:
		return
	var body := "Congratulations — you are now the Branch Manager of this branch, effective immediately.\n\nThe Branch Manager's office is yours: staff scheduling, approvals and the vault reconciliation are now open to you.\n\nYour disciplinary record has been cleared"
	var cleared := ReportManager.reports_cleared_on_promotion
	if cleared > 0:
		body += " (%d report%s removed)" % [cleared, "" if cleared == 1 else "s"]
	body += ". As Branch Manager you're no longer subject to branch disciplinary reports."
	_enqueue(Mode.NOTICE, "Letter of Promotion", body, PROMOTION_SENDER)

const ORIENTATION_BODY: String = "As Branch Manager, you're responsible for the whole branch, not just one desk. Your main duties:\n\nStaff scheduling — decide who works each window and the Loan Desk. Every staff member has different strengths: fast staff serve more customers but may make more mistakes, careful staff are slower but more accurate. Check their stats before assigning them.\n\nApprovals — review recent decisions and step in when one was wrong.\n\nVault reconciliation — count the branch vault once per shift and make sure it matches the records.\n\nStaff performance — you're accountable for your team's work. Staff review and discipline will be added to your duties soon."

## Called on every Branch Manager clock-in (branch_manager_screen.gd's
## shift_clocked_in, wired by teller_room.gd); only the first one per career
## shows the letter — it's kept apart from the promotion letter so the
## player never gets two letters in a row.
func show_branch_orientation_once() -> void:
	if XPManager.has_seen_branch_orientation:
		return
	XPManager.has_seen_branch_orientation = true
	_enqueue(Mode.NOTICE, "Welcome to Branch Management", ORIENTATION_BODY, PROMOTION_SENDER)

func _enqueue(mode: Mode, title: String, body: String, sender: String = BRANCH_MANAGER_SENDER) -> void:
	if _mode == Mode.TERMINATION:
		return
	if visible:
		_queue.append([mode, title, body, sender])
	else:
		_show(mode, title, body, sender)

func _show(mode: Mode, title: String, body: String, sender: String = BRANCH_MANAGER_SENDER) -> void:
	_mode = mode
	title_label.text = title
	from_label.text = "From: " + sender
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
		_show(next[0], next[1], next[2], next[3])
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
