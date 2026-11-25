extends Control
class_name LoanOfficerScreen

## Loan Officer desk task screen (Phase 4f). Owns its own show/hide + pause
## behavior, same as teller_screen.gd — callers (teller_room.gd) just say
## "show this."
##
## Mirrors teller_screen.gd's clock-in/out + shift-summary structure, but
## there's no cash drawer to count here, so clocking in starts the shift
## immediately instead of routing through a starting count first. The
## shift's "work" is reviewing a fixed number of loan applications
## (APPLICATIONS_PER_SHIFT) via the same LoanReviewScreen from 4b-4e,
## instanced once here and re-shown for each application — its
## decision_graded signal (emitted alongside the Score/Reputation/XP calls
## it already makes per decision) is how this screen tallies a running
## shift total without re-deriving or re-applying anything itself, and its
## closed signal is how this screen knows when to advance or wrap up.

@onready var main_panel: PanelContainer = $Panel
@onready var progress_label: Label = $Panel/VBox/ProgressLabel
@onready var review_next_button: Button = $Panel/VBox/ReviewNextButton
@onready var clock_in_button: Button = $Panel/VBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ClockOutButton
@onready var error_label: Label = $Panel/VBox/ErrorLabel
@onready var close_button: Button = $Panel/VBox/CloseButton
## The files waiting for documents (LoanRole.pipeline), shown only while there
## are any.
@onready var files_vbox: VBoxContainer = $Panel/VBox/FilesVBox
@onready var files_label: Label = $Panel/VBox/FilesVBox/FilesLabel

## The closings waiting (LoanRole.closings), built in code under the files
## list, shown only while there are any. Its list scrolls inside whatever height
## the panel has left (_fit_closings()), so the panel never outgrows the window.
var closings_vbox: VBoxContainer
var closings_title_label: Label
var closings_scroll: ScrollContainer
var closings_label: Label

const CLOSINGS_TITLE: String = "Closings waiting"
## The panel is centred in the 648 px window, so at this height its bottom edge
## is at y 592, above the controls line (y 598): the closings list scrolls
## rather than push it past.
const MAX_PANEL_HEIGHT: float = 536.0
## At least one closing (two lines) always shows.
const CLOSINGS_ROW_HEIGHT: float = 36.0

@onready var loan_review_screen: LoanReviewScreen = $LoanReviewScreen

@onready var shift_summary_panel: PanelContainer = $ShiftSummaryPanel
@onready var shift_start_time_label: Label = $ShiftSummaryPanel/VBox/StartTimeLabel
@onready var shift_end_time_label: Label = $ShiftSummaryPanel/VBox/EndTimeLabel
@onready var shift_applications_reviewed_label: Label = $ShiftSummaryPanel/VBox/ApplicationsReviewedLabel
@onready var shift_score_label: Label = $ShiftSummaryPanel/VBox/ShiftScoreLabel
@onready var shift_total_score_label: Label = $ShiftSummaryPanel/VBox/TotalScoreLabel
@onready var shift_reputation_label: Label = $ShiftSummaryPanel/VBox/ReputationLabel
@onready var shift_xp_label: Label = $ShiftSummaryPanel/VBox/ShiftXPLabel
@onready var shift_total_xp_label: Label = $ShiftSummaryPanel/VBox/TotalXPLabel
@onready var shift_summary_done_button: Button = $ShiftSummaryPanel/VBox/DoneButton

## Same clock-in/out signals as TellerScreen — teller_room.gd uses them to
## send the Loan Desk's staff member on break while the player works it.
signal shift_clocked_in
signal shift_clocked_out

## Fixed shift length rather than open-ended, so each shift reads as a
## clear, comparable unit of work (same reasoning as Teller's fixed
## clock-in/clock-out structure) instead of the player having to decide
## for themselves when a shift is "done."
const APPLICATIONS_PER_SHIFT: int = 3

## How many applications this shift may review: what the day's slots have
## brought so far (LoanSlotAdapter sets it: 0 at Opening, then DaySchedule's
## amount per work slot).
var applications_per_shift: int = 0:
	set(value):
		applications_per_shift = value
		if is_node_ready():
			_update_shift_controls()

enum ShiftState { CLOCKED_OUT, CLOCKED_IN }

var shift_state: ShiftState = ShiftState.CLOCKED_OUT

var shift_start_time: String = ""
var applications_reviewed: int = 0
var shift_score_total: int = 0
var shift_reputation_total: int = 0
var shift_xp_total: int = 0

func _ready() -> void:
	visible = false
	_build_closings_list()
	close_button.pressed.connect(_on_close_button_pressed)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	review_next_button.pressed.connect(_on_review_next_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)
	loan_review_screen.decision_graded.connect(_on_application_graded)
	loan_review_screen.closed.connect(_on_loan_review_screen_closed)

	_update_shift_controls()

func show_screen() -> void:
	visible = true
	get_tree().paused = true
	_show_main_panel()

func hide_screen() -> void:
	visible = false
	get_tree().paused = false

func _on_close_button_pressed() -> void:
	hide_screen()

func _show_main_panel() -> void:
	shift_summary_panel.visible = false
	main_panel.visible = true
	_refresh_files()
	_refresh_closings()

## The waiting list, one entry per file open today (LoanPipeline.open_files()):
## files whose applicant is back first, marked, the one back longest first,
## then the others by due day. Only what the Loan Officer knows: who, for
## what loan, what was asked for, and the day it is due (or, for a file that
## is back, the day to decide it by). Nothing about whether, or how well, a
## file will come back.
static func files_rows(today: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var pipeline := LoanRole.pipeline
	var waiting: Array[LoanFile] = []
	for file in pipeline.open_files(today):
		if not file.has_returned(today):
			waiting.append(file)
	waiting.sort_custom(func(a: LoanFile, b: LoanFile) -> bool: return a.due_day < b.due_day or (a.due_day == b.due_day and a.number < b.number))
	for file in pipeline.returned_files(today):
		rows.append("%s · %s loan: back\nAsked for: %s\nDecide by %s (Loan Officer days)" % [
			file.application.applicant_name, file.application.loan_purpose.to_lower(),
			LoanRequirements.labels(file.items), BankCalendar.short_text(file.decide_by_date(today, LoanRole.role_days))])
	for file in waiting:
		rows.append("%s · %s loan\nAsked for: %s\nDue %s" % [
			file.application.applicant_name, file.application.loan_purpose.to_lower(),
			LoanRequirements.labels(file.items), BankCalendar.short_text(file.due_date())])
	return rows

## The closings waiting, one entry each (LoanRole.closings): those due now
## first, marked "ready to close" with the day to close by (counting Loan
## Officer days), the one due longest first; then the others by due day. Only
## what the Loan Officer knows: who, what loan, how much, and when. Nothing
## about the paperwork, so nothing says whether a closing has a problem.
static func closings_rows(today: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var closings := LoanRole.closings
	var due := closings.due_closings(today)
	for closing in due:
		rows.append("%s · %s loan · %s: ready to close
Close by %s (Loan Officer days)" % [
			closing.application.applicant_name, closing.application.loan_purpose.to_lower(), LoanApplication.dollars(closing.approved_amount),
			BankCalendar.short_text(GameClock.date_of_day(closing.last_day_to_close(today, LoanRole.role_days)))])
	var later: Array[LoanClosing] = []
	for closing in closings.closings:
		if not closing.is_due(today):
			later.append(closing)
	later.sort_custom(func(a: LoanClosing, b: LoanClosing) -> bool: return a.due_day < b.due_day or (a.due_day == b.due_day and a.number < b.number))
	for closing in later:
		rows.append("%s · %s loan · %s
Due %s" % [
			closing.application.applicant_name, closing.application.loan_purpose.to_lower(), LoanApplication.dollars(closing.approved_amount),
			BankCalendar.short_text(closing.closing_date())])
	return rows

func _build_closings_list() -> void:
	closings_vbox = VBoxContainer.new()
	closings_vbox.add_theme_constant_override("separation", 2)
	closings_vbox.visible = false
	closings_title_label = Label.new()
	closings_title_label.text = CLOSINGS_TITLE
	closings_title_label.add_theme_font_size_override("font_size", 14)
	closings_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	closings_vbox.add_child(closings_title_label)
	closings_scroll = ScrollContainer.new()
	closings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	closings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	closings_vbox.add_child(closings_scroll)
	closings_label = Label.new()
	closings_label.theme_type_variation = &"MutedLabel"
	closings_label.add_theme_font_size_override("font_size", 13)
	closings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	closings_label.custom_minimum_size.x = 320.0
	closings_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	closings_scroll.add_child(closings_label)
	files_vbox.get_parent().add_child(closings_vbox)
	files_vbox.get_parent().move_child(closings_vbox, files_vbox.get_index() + 1)
	closings_label.minimum_size_changed.connect(_fit_closings)
	closings_label.resized.connect(_fit_closings)

func _refresh_closings() -> void:
	var rows := closings_rows(GameClock.day)
	closings_vbox.visible = not rows.is_empty()
	closings_title_label.text = "%s (%d)" % [CLOSINGS_TITLE, rows.size()]
	closings_label.text = "

".join(rows)
	_fit_closings.call_deferred()

## The list's area: as tall as its text, but never so tall that the panel
## passes MAX_PANEL_HEIGHT; a longer list scrolls inside it.
func _fit_closings() -> void:
	if not closings_vbox.visible:
		return
	var text_height := closings_label.get_minimum_size().y
	var without_list := main_panel.get_combined_minimum_size().y - closings_scroll.custom_minimum_size.y
	var room := MAX_PANEL_HEIGHT - without_list
	var height := clampf(text_height, 0.0, maxf(room, minf(text_height, CLOSINGS_ROW_HEIGHT)))
	if not is_equal_approx(closings_scroll.custom_minimum_size.y, height):
		closings_scroll.custom_minimum_size.y = height

func _refresh_files() -> void:
	var rows := files_rows(GameClock.day)
	files_vbox.visible = not rows.is_empty()
	files_label.text = "\n\n".join(rows)

## No new shifts from Closing (BusinessDay.can_start_shift()).
func _on_clock_in_button_pressed() -> void:
	if not BusinessDay.can_start_shift():
		error_label.text = BusinessDay.CLOCK_IN_REFUSED_TEXT
		error_label.visible = true
		return
	error_label.visible = false
	_begin_shift()

func _begin_shift() -> void:
	shift_state = ShiftState.CLOCKED_IN
	shift_start_time = GameClock.timestamp()
	applications_reviewed = 0
	shift_score_total = 0
	shift_reputation_total = 0
	shift_xp_total = 0
	_update_shift_controls()
	shift_clocked_in.emit()

func _on_review_next_button_pressed() -> void:
	main_panel.visible = false
	loan_review_screen.show_screen()

## Fires as soon as a decision is recorded — the review screen is still
## open at this point, showing its own grade/points feedback, so this just
## tallies the shift totals and lets the player close it in their own
## time. Mirrors _on_drawer_count_submitted in teller_screen.gd.
func _on_application_graded(score_delta: int, reputation_delta: int, xp_delta: int) -> void:
	applications_reviewed += 1
	shift_score_total += score_delta
	shift_reputation_total += reputation_delta
	shift_xp_total += xp_delta
	_update_shift_controls()

## Closing without a decision doesn't use up a slot toward
## APPLICATIONS_PER_SHIFT — only an actual decision does (counted in
## _on_application_graded()). LoanReviewScreen keeps the undecided
## application current, so "Review Next Application" brings the same one
## back rather than letting it be skipped.
func _on_loan_review_screen_closed(_was_decided: bool) -> void:
	_show_main_panel()

## Gated on work, not time: the shift only ends once all
## APPLICATIONS_PER_SHIFT have been reviewed (the old 45-second wall-clock
## minimum could just be waited out inside this paused screen).
func _on_clock_out_button_pressed() -> void:
	# Time slots: the shift runs until Closing (shared with every desk).
	var refusal := ShiftSlotAdapter.clock_out_refusal()
	if refusal != "":
		error_label.text = "Can't clock out yet — %s." % refusal
		error_label.visible = true
		return
	var remaining := applications_per_shift - applications_reviewed
	if remaining > 0:
		error_label.text = "Can't clock out yet — %d application%s still to review." % [remaining, "" if remaining == 1 else "s"]
		error_label.visible = true
		return
	error_label.visible = false
	_prepare_shift_summary()

func _prepare_shift_summary() -> void:
	var shift_end_time := GameClock.timestamp()

	shift_start_time_label.text = "Start Time: %s" % shift_start_time
	shift_end_time_label.text = "End Time: %s" % shift_end_time
	shift_applications_reviewed_label.text = "Applications Reviewed: %d" % applications_reviewed
	shift_score_label.text = "Shift Score: %+d" % shift_score_total
	shift_total_score_label.text = "Total Score: %d" % ScoreManager.total_score
	shift_reputation_label.text = "Reputation: %+d (now %d)" % [shift_reputation_total, ReputationManager.reputation]
	shift_xp_label.text = "Shift XP: %+d" % shift_xp_total
	shift_total_xp_label.text = "Total XP: %d" % XPManager.total_xp

	shift_state = ShiftState.CLOCKED_OUT
	main_panel.visible = false
	shift_summary_panel.visible = true
	_update_shift_controls()
	shift_clocked_out.emit()

func _on_shift_summary_done_pressed() -> void:
	_show_main_panel()

func _update_shift_controls() -> void:
	var clocked_in := shift_state == ShiftState.CLOCKED_IN
	clock_in_button.visible = not clocked_in
	clock_out_button.visible = clocked_in
	review_next_button.disabled = not clocked_in or applications_reviewed >= applications_per_shift
	progress_label.visible = clocked_in
	progress_label.text = "Applications Reviewed: %d / %d" % [applications_reviewed, applications_per_shift]

## For the room's HUD and interaction prompt (teller_room.gd).
func is_clocked_in() -> bool:
	return shift_state == ShiftState.CLOCKED_IN

func applications_left() -> int:
	return maxi(0, applications_per_shift - applications_reviewed)
