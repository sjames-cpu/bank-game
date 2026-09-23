extends Control

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

@onready var loan_review_screen: LoanReviewScreen = $LoanReviewScreen

@onready var corner_total_score_label: Label = $ScoreHudPanel/VBox/TotalScoreLabel
@onready var corner_reputation_label: Label = $ScoreHudPanel/VBox/ReputationLabel
@onready var corner_xp_label: Label = $ScoreHudPanel/VBox/XPLabel

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

## Fixed shift length rather than open-ended, so each shift reads as a
## clear, comparable unit of work (same reasoning as Teller's fixed
## clock-in/clock-out structure) instead of the player having to decide
## for themselves when a shift is "done."
const APPLICATIONS_PER_SHIFT: int = 3

## Same anti-instant-shift guard as TellerScreen.MIN_SHIFT_DURATION_SECONDS
## (see that constant's doc comment) — this screen has the same clock-in/
## clock-out shape with no other minimum, so an instant clock-in/out was
## just as free a (zero-)score cycle here. Kept as the same value for
## consistency; tune independently after playtesting if warranted.
const MIN_SHIFT_DURATION_SECONDS: float = 45.0

enum ShiftState { CLOCKED_OUT, CLOCKED_IN }

var shift_state: ShiftState = ShiftState.CLOCKED_OUT

var shift_start_time: String = ""
var _shift_start_ticks_msec: int = 0
var applications_reviewed: int = 0
var shift_score_total: int = 0
var shift_reputation_total: int = 0
var shift_xp_total: int = 0

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	review_next_button.pressed.connect(_on_review_next_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)
	loan_review_screen.decision_graded.connect(_on_application_graded)
	loan_review_screen.closed.connect(_on_loan_review_screen_closed)
	ScoreManager.score_changed.connect(_on_total_score_changed)
	ReputationManager.reputation_changed.connect(_on_reputation_changed)
	XPManager.xp_changed.connect(_on_total_xp_changed)

	_update_shift_controls()
	_on_total_score_changed(ScoreManager.total_score)
	_on_reputation_changed(ReputationManager.reputation)
	_on_total_xp_changed(XPManager.total_xp)

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

func _on_clock_in_button_pressed() -> void:
	_begin_shift()

func _begin_shift() -> void:
	shift_state = ShiftState.CLOCKED_IN
	shift_start_time = Time.get_datetime_string_from_system()
	_shift_start_ticks_msec = Time.get_ticks_msec()
	applications_reviewed = 0
	shift_score_total = 0
	shift_reputation_total = 0
	shift_xp_total = 0
	_update_shift_controls()

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

## LoanReviewScreen reports whether the application it was showing got
## decided before it closed — the player can hit its Close button before
## deciding at all. That still has to consume a slot toward
## APPLICATIONS_PER_SHIFT (with no Score/Reputation/XP change, since
## nothing was graded); otherwise the same application could be reopened
## and skipped indefinitely without review_next_button ever disabling.
func _on_loan_review_screen_closed(was_decided: bool) -> void:
	if not was_decided:
		applications_reviewed += 1
		_update_shift_controls()
	_show_main_panel()

## Ends the shift whenever the player chooses to clock out — usually after
## reviewing all APPLICATIONS_PER_SHIFT (review_next_button disables itself
## once that count is hit, see _update_shift_controls), but nothing stops
## clocking out earlier with a partial shift's worth of tallies.
func _on_clock_out_button_pressed() -> void:
	var elapsed_seconds := (Time.get_ticks_msec() - _shift_start_ticks_msec) / 1000.0
	if elapsed_seconds < MIN_SHIFT_DURATION_SECONDS:
		error_label.text = "Shift just started — come back later."
		error_label.visible = true
		return
	error_label.visible = false
	_prepare_shift_summary()

func _prepare_shift_summary() -> void:
	var shift_end_time := Time.get_datetime_string_from_system()

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

func _on_shift_summary_done_pressed() -> void:
	_show_main_panel()

func _update_shift_controls() -> void:
	var clocked_in := shift_state == ShiftState.CLOCKED_IN
	clock_in_button.visible = not clocked_in
	clock_out_button.visible = clocked_in
	review_next_button.disabled = not clocked_in or applications_reviewed >= APPLICATIONS_PER_SHIFT
	progress_label.visible = clocked_in
	progress_label.text = "Applications Reviewed: %d / %d" % [applications_reviewed, APPLICATIONS_PER_SHIFT]

func _on_total_score_changed(new_total: int) -> void:
	corner_total_score_label.text = "Total Score: %d" % new_total

func _on_reputation_changed(new_reputation: int) -> void:
	corner_reputation_label.text = "Reputation: %d" % new_reputation

func _on_total_xp_changed(new_total: int) -> void:
	corner_xp_label.text = "XP: %d" % new_total
