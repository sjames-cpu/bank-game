extends Control
class_name DisciplineLetterScreen

## Shows ReportManager's letters from the Branch Manager over whatever
## screen is open: a written-warning popup per report and a full-screen
## termination letter at REPORTS_FOR_TERMINATION. Also shows the promotion
## letter when the player becomes Branch Manager (XPManager — held until
## clock-out if earned mid-shift), which includes the cleared disciplinary
## record so the player gets one letter, not two, and the one-time
## "Welcome to Branch Management" orientation on the first Branch Manager
## clock-in (show_branch_orientation_once()), and the termination letter
## the Branch Manager sends a staff member (StaffReviewManager), and the
## "Probation Complete" letter (InterviewManager.probation_completed), and
## the Regional Manager's review and demotion letters (RegionalManager). Lives in
## teller_room's UI layer (last, so it draws on top); process_mode ALWAYS so
## it works whether or not a desk screen has the tree paused.
##
## Pauses the tree itself while a letter is up if nothing else already had
## it paused — same _paused_by_self pattern as DrawerCountScreen.
##
## Every letter shares one panel, at most MAX_HEIGHT_SHARE of the window
## tall and centred: a long body scrolls inside it (mouse wheel, scrollbar
## or dragging) while the title, sender and button stay visible, and a short
## letter shrinks to its text.
##
## The termination letter's only button, "Apply for a new job", wipes all
## career progress (CareerReset) and its save (SaveGame, already deleted when
## the letter came up) and loads the interview; passing it starts a new
## career in teller_room the usual way (interview_screen.gd).

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
@onready var body_scroll: ScrollContainer = $LetterPanel/VBox/BodyScroll
@onready var body_label: Label = $LetterPanel/VBox/BodyScroll/BodyLabel
@onready var action_button: Button = $LetterPanel/VBox/ActionButton

## The letter panel is never taller than this share of the window, centred
## with margins above and below. A body that would make it taller scrolls
## inside the panel (body_scroll); the title, "From:" line and button stay
## put. A short letter shrinks to fit its text.
const MAX_HEIGHT_SHARE: float = 0.72

var _mode: Mode = Mode.NONE
var _paused_by_self: bool = false

## Letters waiting behind the one currently shown, as [Mode, title, body, sender].
var _queue: Array = []

func _ready() -> void:
	visible = false
	action_button.pressed.connect(_on_action_button_pressed)
	# The body's wrapped height is only known once it has its width.
	body_label.resized.connect(_fit_to_body)
	letter_panel.minimum_size_changed.connect(_recentre)
	body_scroll.gui_input.connect(_on_body_scroll_input)
	ReportManager.report_issued.connect(_on_report_issued)
	ReportManager.termination_issued.connect(_on_termination_issued)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	StaffReviewManager.staff_terminated.connect(_on_staff_terminated)
	InterviewManager.probation_completed.connect(_on_probation_completed)
	RegionalManager.review_completed.connect(_on_regional_review_completed)
	RegionalManager.demoted.connect(_on_demoted)
	RegionalManager.zero_reputation_warning.connect(_on_zero_reputation_warning)

## The Regional Manager's review of the Branch Manager (RegionalManager), at
## a review day's End of Day: the rating, each area and the outcome.
func _on_regional_review_completed(result: Dictionary) -> void:
	_enqueue(Mode.NOTICE, RegionalManager.review_title(result), RegionalManager.review_body(result), RegionalManager.SENDER)

## Reputation fell to 0 while Branch Manager.
func _on_zero_reputation_warning(warnings_now: int) -> void:
	_enqueue(Mode.WARNING, "Regional Warning — %d of %d" % [warnings_now, RegionalManager.WARNINGS_FOR_DEMOTION], RegionalManager.zero_reputation_body(warnings_now), RegionalManager.SENDER)

## Three regional warnings: back to Loan Officer (after the review letter).
func _on_demoted(warnings_reached: int) -> void:
	_enqueue(Mode.NOTICE, "Notice of Demotion", RegionalManager.demotion_body(warnings_reached), RegionalManager.SENDER)

## The Branch Manager (the player) terminating a staff member — a short
## letter to them, signed by the Branch Manager.
func _on_staff_terminated(staff_name: String, report_reasons: PackedStringArray) -> void:
	var lines: PackedStringArray = []
	for i in report_reasons.size():
		lines.append("Report %d — %s" % [i + 1, report_reasons[i]])
	var body := "To: %s\n\nFollowing %d staff reports, your employment with the branch is terminated, effective immediately.\n\n%s" % [staff_name, report_reasons.size(), "\n".join(lines)]
	_enqueue(Mode.NOTICE, "Notice of Termination — %s" % staff_name, body, BRANCH_MANAGER_SENDER)

func _on_report_issued(report: DisciplinaryReport) -> void:
	var limit := ReportManager.report_limit()
	# A report for Reputation falling to 0 has no customers to list.
	var cause := "for %s.\n\nCustomers affected:\n%s" % [report.reason.to_lower(), _bullets(report.items)]
	if report.items.is_empty():
		cause = "because %s: your Reputation is 0 out of 100." % report.reason.to_lower()
	var body := "This is a formal written warning, issued %s\n\nThis is report %d of %d. Reaching %d reports will result in termination." % [
		cause, report.number, limit, limit,
	]
	if InterviewManager.is_on_probation:
		body += "\n\nYou are on probation, so %d reports end your employment instead of the usual %d. Your probation's clean-shift count starts over: %d teller shifts without a report will complete it." % [
			limit, ReportManager.REPORTS_FOR_TERMINATION, InterviewManager.PROBATION_CLEAN_SHIFTS,
		]
	_enqueue(Mode.WARNING, "Written Warning — Report %d of %d" % [report.number, limit], body)

## Probation ended after enough clean teller shifts.
func _on_probation_completed() -> void:
	var body := "You've completed your probation period: %d teller shifts in a row without a disciplinary report. Well done.\n\nYou're now a permanent member of staff, and the usual limit of %d reports applies." % [
		InterviewManager.PROBATION_CLEAN_SHIFTS, ReportManager.REPORTS_FOR_TERMINATION,
	]
	_enqueue(Mode.NOTICE, "Probation Complete", body)

func _on_termination_issued(reports: Array[DisciplinaryReport]) -> void:
	var lines: PackedStringArray = []
	for report in reports:
		var items := ": " + ", ".join(report.items) if not report.items.is_empty() else ""
		lines.append("Report %d — %s%s" % [report.number, report.reason, items])
	var during := " during your probation period" if InterviewManager.is_on_probation else ""
	var body := "Following %d disciplinary reports%s, your employment with the branch is terminated, effective immediately.\n\n%s" % [reports.size(), during, "\n".join(lines)]
	# The career is over: delete its save now, so quitting at this letter
	# can't bring it back (SaveGame won't save a terminated career either).
	SaveGame.delete()
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

const ORIENTATION_BODY: String = "As Branch Manager, you're responsible for the whole branch, not just one desk. Your main duties:\n\nStaff scheduling — decide who works each window and the Loan Desk. Every staff member has different strengths: fast staff serve more customers but may make more mistakes, careful staff are slower but more accurate. Check their stats before assigning them.\n\nApprovals — review recent decisions and step in when one was wrong.\n\nVault reconciliation — count the branch vault once per shift and make sure it matches the records.\n\nStaff review — you're accountable for your team's work. Review their mistakes and questionable loan calls, and decide whether each deserves a report, feedback, or nothing. Be fair: a report for a reasonable call is too harsh, and a serious error left unreviewed at clock-out reflects on you. Three reports and you may let a staff member go."

## Called on every Branch Manager clock-in (branch_manager_screen.gd's
## shift_clocked_in, wired by teller_room.gd); only the first one per career
## shows the letter — it's kept apart from the promotion letter so the
## player never gets two letters in a row. Returns whether it was shown.
func show_branch_orientation_once() -> bool:
	if XPManager.has_seen_branch_orientation:
		return false
	XPManager.has_seen_branch_orientation = true
	_enqueue(Mode.NOTICE, "Welcome to Branch Management", ORIENTATION_BODY, PROMOTION_SENDER)
	return true

## The termination letter covers the whole window (opaque backdrop); the
## room's HUD hides while it's up.
func is_full_screen_letter_shown() -> bool:
	return visible and _mode == Mode.TERMINATION

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
	body_scroll.scroll_vertical = 0
	_fit_to_body()
	_recentre()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func _on_action_button_pressed() -> void:
	if _mode == Mode.TERMINATION:
		_apply_for_new_job()
		return
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		var mode: Mode = next[0]
		var title: String = next[1]
		var body: String = next[2]
		var sender: String = next[3]
		_show(mode, title, body, sender)
		return
	visible = false
	_mode = Mode.NONE
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

## The tallest the letter panel may be: MAX_HEIGHT_SHARE of the window's
## design height (648), or of the viewport if that's shorter. A window
## stretched taller ("expand" aspect) doesn't make letters taller.
func max_panel_height() -> float:
	var design_height: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	return minf(get_viewport_rect().size.y, design_height) * MAX_HEIGHT_SHARE

## Sizes the body's scroll area to the body text, but no taller than leaves
## the whole panel within max_panel_height(). Runs on every new letter and
## whenever the body label resizes: an autowrapped label only knows its real
## height once its container has given it a width.
func _fit_to_body() -> void:
	var body_height := body_label.get_combined_minimum_size().y
	var chrome := letter_panel.get_combined_minimum_size().y - body_scroll.custom_minimum_size.y
	var wanted := minf(body_height, maxf(0.0, max_panel_height() - chrome))
	if not is_equal_approx(wanted, body_scroll.custom_minimum_size.y):
		body_scroll.custom_minimum_size.y = wanted
		_recentre()

## Sizes the panel to its content, centred on the window's centre (the
## anchor). Runs whenever its minimum size changes; without it a short
## letter after a long one would keep the long one's height.
func _recentre() -> void:
	var height := letter_panel.get_combined_minimum_size().y
	letter_panel.offset_top = -height / 2.0
	letter_panel.offset_bottom = height / 2.0

## Dragging the body with the mouse scrolls it (ScrollContainer only does
## this itself on touchscreens); the mouse wheel and scrollbar work as usual.
func _on_body_scroll_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		body_scroll.scroll_vertical -= roundi(motion.relative.y)
		body_scroll.accept_event()

func _apply_for_new_job() -> void:
	get_tree().paused = false
	SaveGame.delete()
	CareerReset.reset_all()
	get_tree().change_scene_to_file(INTERVIEW_SCENE)

func _bullets(items: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	for item in items:
		lines.append("• " + item)
	return "\n".join(lines)
