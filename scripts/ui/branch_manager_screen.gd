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
##   action — potentially several times in one visit. It grades itself
##   (its own _selected_record gets consumed to null right after applying
##   consequences, so a stray repeat signal can't reapply them).
## - VaultReconciliationScreen (5e) emits count_submitted(total) once per
##   Submit press — this screen does NOT grade itself (same "just count
##   and report" shape as DrawerCountScreen); this hub owns grading via
##   _on_vault_count_submitted() below, guarded by
##   _awaiting_vault_reconciliation_result the same way teller_screen.gd's
##   pending_drawer_count_purpose one-shot-consumes DrawerCountScreen's
##   count_submitted. Without that guard, repeatedly pressing Submit on an
##   already-open VaultReconciliationScreen would reapply Score/
##   Reputation/XP every single click.
##
## review_completed/_on_vault_count_submitted plus each screen's closed
## signal (needed here for the first time — a caller now exists to react
## to it) are how this hub tallies a running shift total and knows when to
## bring its own menu back, the same way loan_officer_screen.gd reacts to
## LoanReviewScreen's decision_graded/closed.

@onready var main_panel: Panel = $Panel
@onready var schedule_staff_button: Button = $Panel/VBox/ScheduleStaffButton
@onready var review_approvals_button: Button = $Panel/VBox/ReviewApprovalsButton
@onready var vault_reconciliation_button: Button = $Panel/VBox/VaultReconciliationButton
@onready var clock_in_button: Button = $Panel/VBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ClockOutButton
@onready var error_label: Label = $Panel/VBox/ErrorLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

@onready var staff_scheduling_screen: StaffSchedulingScreen = $StaffSchedulingScreen
@onready var approvals_screen: ApprovalsScreen = $ApprovalsScreen
@onready var vault_reconciliation_screen: VaultReconciliationScreen = $VaultReconciliationScreen

@onready var corner_total_score_label: Label = $ScoreHudPanel/VBox/TotalScoreLabel
@onready var corner_reputation_label: Label = $ScoreHudPanel/VBox/ReputationLabel
@onready var corner_xp_label: Label = $ScoreHudPanel/VBox/XPLabel

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

## Set right before opening VaultReconciliationScreen, consumed (reset to
## false) the moment its first count_submitted after that is graded — the
## same one-shot pattern teller_screen.gd's pending_drawer_count_purpose
## uses for DrawerCountScreen. See _on_vault_count_submitted(). Guards
## against spamming Submit within a single visit.
var _awaiting_vault_reconciliation_result: bool = false

## Separate from the one-shot guard above — that one stops a rapid-click
## spam within a single visit, but nothing stopped closing and reopening
## VaultReconciliationScreen repeatedly across the same shift, resubmitting
## the same always-correct EXPECTED_VAULT_BALANCE answer for another full
## Score/Reputation/XP grant each time (a real bank only reconciles its
## vault once per shift, not on demand). This is that per-shift cap: set
## true the moment a vault count is actually graded, reset false at the
## start of the next shift in _begin_shift(). Checked before a visit is
## even allowed to start (_on_vault_reconciliation_button_pressed()), not
## just before grading, so a second visit doesn't get a false "not yet
## graded" read on _awaiting_vault_reconciliation_result.
var _vault_reconciled_this_shift: bool = false

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
	vault_reconciliation_screen.count_submitted.connect(_on_vault_count_submitted)
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
	_shift_start_ticks_msec = Time.get_ticks_msec()
	_awaiting_vault_reconciliation_result = false
	_vault_reconciled_this_shift = false
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

## Blocks starting a new visit at all once this shift's one allowed
## reconciliation has already been graded — see
## _vault_reconciled_this_shift's doc comment. The button itself is also
## disabled for the same reason (_update_shift_controls()), but this
## explicit check is the authoritative guard, the same "don't just trust
## the UI state" approach _on_teller_desk_interacted() etc. use in
## teller_room.gd.
func _on_vault_reconciliation_button_pressed() -> void:
	if _vault_reconciled_this_shift:
		return
	main_panel.visible = false
	_awaiting_vault_reconciliation_result = true
	vault_reconciliation_screen.show_screen()

## Shared by ApprovalsScreen's review_completed and this hub's own
## _on_vault_count_submitted() below — both hand it (score_delta,
## reputation_delta, xp_delta) in the same shape loan_review_screen.gd's
## decision_graded does, so one handler covers both. Each screen stays
## open after firing this (the player may keep working), so `closed`
## below is what actually returns to this hub's menu.
func _on_activity_completed(score_delta: int, reputation_delta: int, xp_delta: int) -> void:
	actions_completed += 1
	shift_score_total += score_delta
	shift_reputation_total += reputation_delta
	shift_xp_total += xp_delta

## Fires every time Submit is pressed on VaultReconciliationScreen, but
## _awaiting_vault_reconciliation_result makes sure only the first press
## after opening it actually grades anything — VaultReconciliationScreen
## itself never disables its own Submit button, so without this guard
## every subsequent click would reapply Score/Reputation/XP for the same
## already-submitted count. Owns its own categorization (mirroring
## teller_screen.gd's _categorize_discrepancy() for DrawerCountScreen)
## rather than trusting VaultReconciliationScreen's own — that screen's
## copy exists only to decide its own status_label text.
func _on_vault_count_submitted(total: float) -> void:
	if not _awaiting_vault_reconciliation_result:
		return
	_awaiting_vault_reconciliation_result = false
	_vault_reconciled_this_shift = true
	_update_shift_controls()

	var discrepancy := total - VaultReconciliationScreen.EXPECTED_VAULT_BALANCE
	var excess_bills := vault_reconciliation_screen.get_excess_bill_count()
	var discrepancy_result := _categorize_vault_discrepancy(discrepancy, excess_bills)
	var result_label := _vault_discrepancy_result_label(discrepancy_result)

	var score := _vault_score_for_result(discrepancy_result)
	var reputation_delta := _vault_reputation_for_result(discrepancy_result)
	var xp := score * XPManager.XP_PER_SCORE_POINT

	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Vault reconciliation: %s (discrepancy $%.2f)" % [result_label, discrepancy], result_label)

	_on_activity_completed(score, reputation_delta, xp)

## Mirrors VaultReconciliationScreen._categorize_discrepancy() exactly —
## kept as its own copy here (rather than calling into the screen) the
## same way teller_screen.gd owns its own copy for DrawerCountScreen
## rather than reading DrawerCountScreen's.
func _categorize_vault_discrepancy(discrepancy: float, excess_bills: int) -> VaultReconciliationScreen.DiscrepancyResult:
	if discrepancy == 0.0 and excess_bills <= VaultReconciliationScreen.PERFECT_BILL_COUNT_TOLERANCE:
		return VaultReconciliationScreen.DiscrepancyResult.PERFECT
	elif abs(discrepancy) <= VaultReconciliationScreen.MINOR_DISCREPANCY_THRESHOLD and excess_bills <= VaultReconciliationScreen.MINOR_BILL_COUNT_TOLERANCE:
		return VaultReconciliationScreen.DiscrepancyResult.MINOR
	else:
		return VaultReconciliationScreen.DiscrepancyResult.MAJOR

func _vault_discrepancy_result_label(discrepancy_result: VaultReconciliationScreen.DiscrepancyResult) -> String:
	match discrepancy_result:
		VaultReconciliationScreen.DiscrepancyResult.PERFECT:
			return "Perfect"
		VaultReconciliationScreen.DiscrepancyResult.MINOR:
			return "Minor"
		_:
			return "Major"

## Reuses TellerScreen's exact Perfect/Minor/Major point values, same as
## VaultReconciliationScreen used to before it stopped grading itself —
## the vault's higher stakes are already expressed through
## VaultReconciliationScreen.MINOR_DISCREPANCY_THRESHOLD (a "Major" vault
## discrepancy takes a much bigger dollar miss to earn than a "Major"
## drawer one), so inflating the point values on top of that would tune
## the same thing twice.
func _vault_score_for_result(discrepancy_result: VaultReconciliationScreen.DiscrepancyResult) -> int:
	match discrepancy_result:
		VaultReconciliationScreen.DiscrepancyResult.PERFECT:
			return TellerScreen.PERFECT_COUNT_SCORE
		VaultReconciliationScreen.DiscrepancyResult.MINOR:
			return TellerScreen.MINOR_DISCREPANCY_SCORE
		_:
			return TellerScreen.MAJOR_DISCREPANCY_SCORE

func _vault_reputation_for_result(discrepancy_result: VaultReconciliationScreen.DiscrepancyResult) -> int:
	match discrepancy_result:
		VaultReconciliationScreen.DiscrepancyResult.PERFECT:
			return TellerScreen.PERFECT_COUNT_REPUTATION
		VaultReconciliationScreen.DiscrepancyResult.MINOR:
			return TellerScreen.MINOR_DISCREPANCY_REPUTATION
		_:
			return TellerScreen.MAJOR_DISCREPANCY_REPUTATION

func _on_schedule_confirmed(_schedule: Dictionary) -> void:
	schedule_confirmed_this_shift = true

func _on_sub_screen_closed() -> void:
	_show_main_panel()

## Ends the shift whenever the player chooses to clock out — nothing
## requires having visited all three screens first, same as Loan Officer's
## clock-out being available with a partial shift's worth of tallies.
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
	vault_reconciliation_button.disabled = not clocked_in or _vault_reconciled_this_shift
	vault_reconciliation_button.text = "Vault Reconciliation (Done This Shift)" if _vault_reconciled_this_shift else "Vault Reconciliation"

func _on_total_score_changed(new_total: int) -> void:
	corner_total_score_label.text = "Total Score: %d" % new_total

func _on_reputation_changed(new_reputation: int) -> void:
	corner_reputation_label.text = "Reputation: %d" % new_reputation

func _on_total_xp_changed(new_total: int) -> void:
	corner_xp_label.text = "XP: %d" % new_total
