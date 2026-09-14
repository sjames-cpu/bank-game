extends Control
class_name VaultReconciliationScreen

## Branch Manager vault reconciliation screen (Phase 5e). Structurally a
## close cousin of drawer_count_screen.gd — the same six-denomination
## count, the same running total, the same Perfect/Minor/Major shape —
## scaled up from one teller's drawer to the whole branch vault.
##
## Same "just count and report" shape as DrawerCountScreen — this screen
## only computes/displays a result and emits count_submitted(total); it
## does not apply Score/Reputation/XP or log to HistoryManager itself.
## branch_manager_screen.gd (the caller) owns grading, the same way
## teller_screen.gd owns grading for DrawerCountScreen — this used to
## grade itself directly (there was no Branch Manager shift loop yet to
## delegate to), but that meant nothing stopped a second Submit click on
## the same open screen from reapplying the same consequences a second
## time, since this screen never disables its own Submit button. Now that
## branch_manager_screen.gd's shift loop exists, it owns a one-shot
## consumption guard the same way teller_screen.gd's
## pending_drawer_count_purpose does for DrawerCountScreen — see that
## screen's caller-side handler for the pattern this mirrors.
##
## Phase 5f wires this into branch_manager_screen.gd's shift hub, which
## instances this screen and opens it from a menu button. class_name added
## for the same reason LoanReviewScreen got one in 4f — so the hub can
## hold a typed reference and connect to count_submitted/closed directly.
##
## Manages its own pause state the same defensive way DrawerCountScreen
## does (_paused_by_self tracks whether *this* screen was the one that
## paused, so hide_screen() never unpauses a tree something else still
## needs paused) — branch_manager_screen.gd pauses for the whole shift the
## same way teller_screen.gd/loan_officer_screen.gd do, so this stays
## defensive rather than assuming it's always the one in charge of
## pausing.

signal count_submitted(total: float)
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

## Same excess-bill-count check as DrawerCountScreen (see that file's doc
## comment on PERFECT_BILL_COUNT_TOLERANCE for the reasoning, including why
## it's 4 rather than the original 2) — a correct total alone no longer
## counts as Perfect if the bill breakdown behind it is implausible.
## Scaled 10x like MINOR_DISCREPANCY_THRESHOLD above, since the vault's
## canonical minimum bill count is itself 10x a drawer's (500 vs 50 $1000
## bills for the respective expected balances) — keeping the same
## relative tolerance rather than the same absolute one.
const PERFECT_BILL_COUNT_TOLERANCE: int = 40
const MINOR_BILL_COUNT_TOLERANCE: int = 150

enum DiscrepancyResult { PERFECT, MINOR, MAJOR }

var _paused_by_self: bool = false

@onready var quantity_inputs: Array[SpinBox] = [
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom1000SpinBox,
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom500SpinBox,
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom100SpinBox,
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom50SpinBox,
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom10SpinBox,
	$Panel/VBox/CountSection/CountVBox/DenominationsGrid/Denom1SpinBox,
]

@onready var your_total_label: Label = $Panel/VBox/CountSection/CountVBox/YourTotalLabel
@onready var submit_button: Button = $Panel/VBox/SubmitButton
@onready var close_button: Button = $Panel/VBox/CloseButton

@onready var results_container: PanelContainer = $Panel/VBox/ResultsContainer
@onready var result_expected_label: Label = $Panel/VBox/ResultsContainer/ResultsVBox/ResultExpectedLabel
@onready var result_total_label: Label = $Panel/VBox/ResultsContainer/ResultsVBox/ResultTotalLabel
@onready var discrepancy_label: Label = $Panel/VBox/ResultsContainer/ResultsVBox/DiscrepancyLabel
@onready var status_label: Label = $Panel/VBox/ResultsContainer/ResultsVBox/StatusLabel

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

## See DrawerCountScreen._minimum_bill_count() — identical logic, kept as
## its own copy rather than a shared base class, matching how this screen
## already duplicates DENOMINATIONS/_calculate_total() from that one.
func _minimum_bill_count(target: float) -> int:
	var remaining := int(round(target))
	var count := 0
	for denom in DENOMINATIONS:
		var quantity := remaining / denom
		count += quantity
		remaining -= quantity * denom
	return count

## Public so branch_manager_screen.gd can factor this into its own Score/
## Reputation/XP grading of the submitted count — see
## DrawerCountScreen.get_excess_bill_count(), which this mirrors exactly.
func get_excess_bill_count() -> int:
	var player_bill_count := 0
	for quantity_input in quantity_inputs:
		player_bill_count += int(quantity_input.value)
	return maxi(0, player_bill_count - _minimum_bill_count(EXPECTED_VAULT_BALANCE))

func _update_live_total() -> void:
	your_total_label.text = "Your Total: $%.2f" % _calculate_total()

## excess_bills is how many more bills the player entered than the minimum
## possible for EXPECTED_VAULT_BALANCE (see get_excess_bill_count()) — a
## correct total no longer grades Perfect on its own if the breakdown
## behind it is implausible.
func _categorize_discrepancy(discrepancy: float, excess_bills: int) -> DiscrepancyResult:
	if discrepancy == 0.0 and excess_bills <= PERFECT_BILL_COUNT_TOLERANCE:
		return DiscrepancyResult.PERFECT
	elif abs(discrepancy) <= MINOR_DISCREPANCY_THRESHOLD and excess_bills <= MINOR_BILL_COUNT_TOLERANCE:
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

## Purely local display — decides this screen's own status_label text.
## Grading (Score/Reputation/XP) is a separate, independent categorization
## owned by branch_manager_screen.gd, the same duplication-across-the-
## caller-boundary DrawerCountScreen/TellerScreen already have; this
## screen has no scoring responsibility at all.
func _on_submit_button_pressed() -> void:
	var total := _calculate_total()
	var discrepancy := total - EXPECTED_VAULT_BALANCE
	var excess_bills := get_excess_bill_count()
	var discrepancy_result := _categorize_discrepancy(discrepancy, excess_bills)
	var result_label := _discrepancy_result_label(discrepancy_result)

	result_expected_label.text = "Expected Balance: $%.2f" % EXPECTED_VAULT_BALANCE
	result_total_label.text = "Your Total: $%.2f" % total
	discrepancy_label.text = "Discrepancy: $%.2f" % discrepancy
	status_label.text = "%s Count!" % result_label if discrepancy_result == DiscrepancyResult.PERFECT else "%s Discrepancy" % result_label
	if discrepancy == 0.0 and discrepancy_result != DiscrepancyResult.PERFECT:
		status_label.text += " (correct total, but an implausible bill mix)"
	results_container.visible = true

	count_submitted.emit(total)
