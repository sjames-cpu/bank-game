extends Control
class_name VaultReconciliationScreen

## Branch Manager vault reconciliation screen (Phase 5e). Structurally a
## close cousin of drawer_count_screen.gd — the same six-denomination
## count, the same running total, the same Perfect/Minor/Major shape —
## scaled up from one teller's drawer to the whole branch vault.
##
## Unlike DrawerCountScreen (a reusable "just count and report" component
## whose caller, teller_screen.gd, is the one that applies consequences),
## this screen applies its own Score/Reputation/XP consequences and logs
## its own HistoryManager entry directly, the same way loan_review_screen.gd
## does — there's no Branch Manager shift loop yet (Phase 5f) to delegate
## that to, and the expected vault balance isn't caller-supplied variance
## the way a drawer's starting/ending balance is (see
## EXPECTED_VAULT_BALANCE below), so there's nothing left for a caller to
## own here yet. reconciliation_completed is still emitted (mirroring
## loan_review_screen.gd's decision_graded) so Phase 5f's shift loop can
## tally it into a shift summary without this screen needing to change.
##
## Phase 5f wires this into branch_manager_screen.gd's shift hub, which
## instances this screen and opens it from a menu button. class_name added
## for the same reason LoanReviewScreen got one in 4f — so the hub can
## hold a typed reference and connect to reconciliation_completed/closed
## directly.
##
## Manages its own pause state the same defensive way DrawerCountScreen
## does (_paused_by_self tracks whether *this* screen was the one that
## paused, so hide_screen() never unpauses a tree something else still
## needs paused) — branch_manager_screen.gd pauses for the whole shift the
## same way teller_screen.gd/loan_officer_screen.gd do, so this stays
## defensive rather than assuming it's always the one in charge of
## pausing.

signal reconciliation_completed(score_delta: int, reputation_delta: int, xp_delta: int)
signal closed

const DENOMINATIONS: Array[int] = [1000, 500, 100, 50, 10, 1]

## The whole vault, not one drawer, is being counted here. Summing real
## Teller shift ending balances from HistoryManager was the other option
## this phase's brief offered, but those records only keep a
## human-readable discrepancy description (see teller_screen.gd's
## _prepare_shift_summary()), not a structured ending-balance figure —
## and a real sum would read as $0 whenever this screen is opened
## standalone with no prior Teller shifts played this session, which is
## exactly the debug-key testing this phase asks for. A flat simulated
## total — the same choice teller_screen.gd already makes for
## STARTING_EXPECTED_BALANCE — keeps this screen deterministic and
## testable in isolation; 10x a teller's $50,000 starting drawer reads as
## a reasonable "whole branch" scale.
const EXPECTED_VAULT_BALANCE: float = 500000.0

## A vault holds ~10x what one drawer does, so reusing DrawerCountScreen's
## same $500 absolute threshold here would be a much tighter *relative*
## tolerance (0.1% of the vault vs. 1% of a drawer) despite there being
## more cash — and more chances for small counting slips to stack up — to
## get through. Scaling the threshold by that same 10x keeps the relative
## tolerance identical to a drawer count's, which is the more meaningful
## thing to hold constant across drawer- and vault-scale counts.
const MINOR_DISCREPANCY_THRESHOLD: float = 5000.0

enum DiscrepancyResult { PERFECT, MINOR, MAJOR }

var _paused_by_self: bool = false

@onready var quantity_inputs: Array[SpinBox] = [
	$Panel/VBox/DenominationsGrid/Denom1000SpinBox,
	$Panel/VBox/DenominationsGrid/Denom500SpinBox,
	$Panel/VBox/DenominationsGrid/Denom100SpinBox,
	$Panel/VBox/DenominationsGrid/Denom50SpinBox,
	$Panel/VBox/DenominationsGrid/Denom10SpinBox,
	$Panel/VBox/DenominationsGrid/Denom1SpinBox,
]

@onready var your_total_label: Label = $Panel/VBox/YourTotalLabel
@onready var submit_button: Button = $Panel/VBox/SubmitButton
@onready var close_button: Button = $Panel/VBox/CloseButton

@onready var results_container: VBoxContainer = $Panel/VBox/ResultsContainer
@onready var result_expected_label: Label = $Panel/VBox/ResultsContainer/ResultExpectedLabel
@onready var result_total_label: Label = $Panel/VBox/ResultsContainer/ResultTotalLabel
@onready var discrepancy_label: Label = $Panel/VBox/ResultsContainer/DiscrepancyLabel
@onready var status_label: Label = $Panel/VBox/ResultsContainer/StatusLabel

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	submit_button.pressed.connect(_on_submit_button_pressed)

	for quantity_input in quantity_inputs:
		quantity_input.value_changed.connect(_on_quantity_changed)

	_reset_form()

func show_screen() -> void:
	_reset_form()
	visible = true

	_paused_by_self = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false

	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

	closed.emit()

func _reset_form() -> void:
	for quantity_input in quantity_inputs:
		quantity_input.value = 0
	results_container.visible = false
	_update_live_total()

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_quantity_changed(_new_value: float) -> void:
	_update_live_total()

func _calculate_total() -> float:
	var total := 0.0
	for i in DENOMINATIONS.size():
		total += DENOMINATIONS[i] * quantity_inputs[i].value
	return total

func _update_live_total() -> void:
	your_total_label.text = "Your Total: $%.2f" % _calculate_total()

func _categorize_discrepancy(discrepancy: float) -> DiscrepancyResult:
	if discrepancy == 0.0:
		return DiscrepancyResult.PERFECT
	elif abs(discrepancy) <= MINOR_DISCREPANCY_THRESHOLD:
		return DiscrepancyResult.MINOR
	else:
		return DiscrepancyResult.MAJOR

func _discrepancy_result_label(discrepancy_result: DiscrepancyResult) -> String:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return "Perfect"
		DiscrepancyResult.MINOR:
			return "Minor"
		_:
			return "Major"

## Reuses TellerScreen's exact Perfect/Minor/Major point values rather
## than inventing vault-specific ones — the vault's higher stakes are
## already expressed through MINOR_DISCREPANCY_THRESHOLD above (a "Major"
## vault discrepancy takes a much bigger dollar miss to earn than a
## "Major" drawer one), so inflating the point values on top of that
## would tune the same thing twice.
func _score_for_result(discrepancy_result: DiscrepancyResult) -> int:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return TellerScreen.PERFECT_COUNT_SCORE
		DiscrepancyResult.MINOR:
			return TellerScreen.MINOR_DISCREPANCY_SCORE
		_:
			return TellerScreen.MAJOR_DISCREPANCY_SCORE

func _reputation_for_result(discrepancy_result: DiscrepancyResult) -> int:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return TellerScreen.PERFECT_COUNT_REPUTATION
		DiscrepancyResult.MINOR:
			return TellerScreen.MINOR_DISCREPANCY_REPUTATION
		_:
			return TellerScreen.MAJOR_DISCREPANCY_REPUTATION

func _on_submit_button_pressed() -> void:
	var total := _calculate_total()
	var discrepancy := total - EXPECTED_VAULT_BALANCE
	var discrepancy_result := _categorize_discrepancy(discrepancy)
	var result_label := _discrepancy_result_label(discrepancy_result)

	result_expected_label.text = "Expected Balance: $%.2f" % EXPECTED_VAULT_BALANCE
	result_total_label.text = "Your Total: $%.2f" % total
	discrepancy_label.text = "Discrepancy: $%.2f" % discrepancy
	status_label.text = "%s Count!" % result_label if discrepancy_result == DiscrepancyResult.PERFECT else "%s Discrepancy" % result_label
	results_container.visible = true

	var score := _score_for_result(discrepancy_result)
	var reputation_delta := _reputation_for_result(discrepancy_result)
	var xp := score * XPManager.XP_PER_SCORE_POINT

	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Vault reconciliation: %s (discrepancy $%.2f)" % [result_label, discrepancy], result_label)

	reconciliation_completed.emit(score, reputation_delta, xp)
