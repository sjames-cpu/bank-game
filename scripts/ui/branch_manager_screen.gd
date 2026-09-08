extends Control

## Branch Manager desk task screen (Phase 5f). Mirrors
## loan_officer_screen.gd's clock-in/out + shift-summary shell — no drawer
## to count, so clocking in starts the shift immediately — but instead of
## one repeated task, the shift's "work" is a menu of three independent
## screens from 5c/5d/5e, each instanced once here and reopened as many
## times as the player wants during the shift:
##
## - StaffSchedulingScreen (5c) has no Score/Reputation/XP consequence yet
##   (scheduling doesn't affect anything else yet — a later step once
##   scheduling connects to actual shift outcomes), so there's nothing to
##   tally from it. This screen just notes whether a schedule was
##   confirmed this shift, read directly off ScheduleManager's own
##   schedule_confirmed signal rather than adding a redundant one just for
##   that.
## - ApprovalsScreen (5d) emits review_completed once per override/flag
##   action — potentially several times in one visit.
## - VaultReconciliationScreen (5e) emits reconciliation_completed once
##   per submission.
##
## Both of those signals plus each screen's closed signal (needed here for
## the first time — a caller now exists to react to it) are how this hub
## tallies a running shift total and knows when to bring its own menu back,
## the same way loan_officer_screen.gd reacts to LoanReviewScreen's
## decision_graded/closed.

@onready var main_panel: Panel = $Panel
@onready var schedule_staff_button: Button = $Panel/VBox/ScheduleStaffButton
@onready var review_approvals_button: Button = $Panel/VBox/ReviewApprovalsButton
@onready var vault_reconciliation_button: Button = $Panel/VBox/VaultReconciliationButton
@onready var clock_in_button: Button = $Panel/VBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ClockOutButton
@onready var close_button: Button = $Panel/VBox/CloseButton

@onready var staff_scheduling_screen: StaffSchedulingScreen = $StaffSchedulingScreen
@onready var approvals_screen: ApprovalsScreen = $ApprovalsScreen
@onready var vault_reconciliation_screen: VaultReconciliationScreen = $VaultReconciliationScreen

@onready var corner_total_score_label: Label = $TotalScoreLabel
@onready var corner_reputation_label: Label = $ReputationLabel
@onready var corner_xp_label: Label = $XPLabel

@onready var shift_summary_panel: Panel = $ShiftSummaryPanel
@onready var shift_start_time_label: Label = $ShiftSummaryPanel/VBox/StartTimeLabel
@onready var shift_end_time_label: Label = $ShiftSummaryPanel/VBox/EndTimeLabel
@onready var shift_actions_completed_label: Label = $ShiftSummaryPanel/VBox/ActionsCompletedLabel
@onready var shift_schedule_label: Label = $ShiftSummaryPanel/VBox/ScheduleLabel
@onready var shift_score_label: Label = $ShiftSummaryPanel/VBox/ShiftScoreLabel
@onready var shift_total_score_label: Label = $ShiftSummaryPanel/VBox/TotalScoreLabel
@onready var shift_reputation_label: Label = $ShiftSummaryPanel/VBox/ReputationLabel
@onready var shift_xp_label: Label = $ShiftSummaryPanel/VBox/ShiftXPLabel
@onready var shift_total_xp_label: Label = $ShiftSummaryPanel/VBox/TotalXPLabel
@onready var shift_summary_done_button: Button = $ShiftSummaryPanel/VBox/DoneButton

enum ShiftState { CLOCKED_OUT, CLOCKED_IN }

var shift_state: ShiftState = ShiftState.CLOCKED_OUT

var shift_start_time: String = ""
var actions_completed: int = 0
var schedule_confirmed_this_shift: bool = false
var shift_score_total: int = 0
var shift_reputation_total: int = 0
var shift_xp_total: int = 0

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	schedule_staff_button.pressed.connect(_on_schedule_staff_button_pressed)
	review_approvals_button.pressed.connect(_on_review_approvals_button_pressed)
	vault_reconciliation_button.pressed.connect(_on_vault_reconciliation_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)

	staff_scheduling_screen.closed.connect(_on_sub_screen_closed)
	approvals_screen.closed.connect(_on_sub_screen_closed)
	vault_reconciliation_screen.closed.connect(_on_sub_screen_closed)

	approvals_screen.review_completed.connect(_on_activity_completed)
	vault_reconciliation_screen.reconciliation_completed.connect(_on_activity_completed)
	ScheduleManager.schedule_confirmed.connect(_on_schedule_confirmed)
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
	actions_completed = 0
	schedule_confirmed_this_shift = false
	shift_score_total = 0
	shift_reputation_total = 0
	shift_xp_total = 0
	_update_shift_controls()

func _on_schedule_staff_button_pressed() -> void:
	main_panel.visible = false
	staff_scheduling_screen.show_screen()

func _on_review_approvals_button_pressed() -> void:
	main_panel.visible = false
	approvals_screen.show_screen()

func _on_vault_reconciliation_button_pressed() -> void:
	main_panel.visible = false
	vault_reconciliation_screen.show_screen()

## Shared by ApprovalsScreen's review_completed and
## VaultReconciliationScreen's reconciliation_completed — both already
## carry (score_delta, reputation_delta, xp_delta) in the same shape
## loan_review_screen.gd's decision_graded does, so one handler covers
## both. Each screen stays open after firing this (the player may keep
## working), so `closed` below is what actually returns to this hub's menu.
func _on_activity_completed(score_delta: int, reputation_delta: int, xp_delta: int) -> void:
	actions_completed += 1
	shift_score_total += score_delta
	shift_reputation_total += reputation_delta
	shift_xp_total += xp_delta

func _on_schedule_confirmed(_schedule: Dictionary) -> void:
	schedule_confirmed_this_shift = true

func _on_sub_screen_closed() -> void:
	_show_main_panel()

## Ends the shift whenever the player chooses to clock out — nothing
## requires having visited all three screens first, same as Loan Officer's
## clock-out being available with a partial shift's worth of tallies.
func _on_clock_out_button_pressed() -> void:
	_prepare_shift_summary()

func _prepare_shift_summary() -> void:
	var shift_end_time := Time.get_datetime_string_from_system()

	shift_start_time_label.text = "Start Time: %s" % shift_start_time
	shift_end_time_label.text = "End Time: %s" % shift_end_time
	shift_actions_completed_label.text = "Actions Completed: %d" % actions_completed
	shift_schedule_label.text = "Schedule Confirmed: %s" % ("Yes" if schedule_confirmed_this_shift else "No (no scoring impact either way)")
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
	schedule_staff_button.disabled = not clocked_in
	review_approvals_button.disabled = not clocked_in
	vault_reconciliation_button.disabled = not clocked_in

func _on_total_score_changed(new_total: int) -> void:
	corner_total_score_label.text = "Total Score: %d" % new_total

func _on_reputation_changed(new_reputation: int) -> void:
	corner_reputation_label.text = "Reputation: %d" % new_reputation

func _on_total_xp_changed(new_total: int) -> void:
	corner_xp_label.text = "XP: %d" % new_total
