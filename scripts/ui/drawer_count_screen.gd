extends Control
class_name DrawerCountScreen

## Cash-counting mini-game: the player enters how many notes of each
## denomination are in the drawer, and it's checked against an expected
## balance the caller supplies (the teller screen's shift system decides
## what that number should be — a fixed starting float, or starting
## balance + deposits - withdrawals at clock-out). This screen doesn't
## know or care which; it just compares and reports.
##
## Manages its own pause state so it works whether or not a caller has
## already paused the tree (TellerScreen currently pauses for its own,
## broader reasons — the whole teller interaction, not just this screen —
## so both this screen and TellerScreen pause defensively; _paused_by_self
## tracks whether *this* screen was the one that did it, so closing this
## screen never unpauses a tree that TellerScreen still needs paused).

signal count_submitted(total: float)
signal closed

const DENOMINATIONS: Array[int] = [1000, 500, 100, 50, 10, 1]
const MINOR_DISCREPANCY_THRESHOLD: float = 500.0

## A correct TOTAL alone used to be enough for a Perfect count, even if the
## denomination breakdown made no sense (e.g. the whole total stuffed into
## $1 bills) — nothing compared the breakdown itself to anything. These
## two constants gate that: excess bill count is the player's total bill
## count minus the minimum bills mathematically needed for the expected
## balance (see _minimum_bill_count()) — using more bills than necessary
## is what an implausible/gamed breakdown looks like, whereas a reasonable
## alternate mix (e.g. a few $500s instead of a $1000) only adds a handful
## of bills over that minimum. A per-denomination cap was considered
## instead, but would wrongly penalize equally-valid real compositions
## that just don't happen to match one arbitrary "canonical" breakdown.
##
## PERFECT_BILL_COUNT_TOLERANCE started at 2, but that was tight enough
## that a perfectly reasonable count — a few mid-size bills swapped in for
## a big one, not deliberately minimizing bill count — would often miss
## Perfect and land on Minor despite the player doing nothing wrong (e.g.
## 49x$1000 + 1x$500 + 5x$100 = the exact same $50,000, just 5 bills over
## the minimum). 4 gives real natural-substitution room (a couple of
## swaps) while still being nowhere near degenerate territory (an all-$1s
## count on the same $50,000 comes in at ~9,950 excess bills), so it still
## clearly separates careful counting from sloppy/gamed counting rather
## than just loosening the check generally. First-pass values, tune
## further after playtesting.
const PERFECT_BILL_COUNT_TOLERANCE: int = 4
const MINOR_BILL_COUNT_TOLERANCE: int = 15

var expected_balance: float = 0.0
var _paused_by_self: bool = false

@onready var title_label: Label = $Panel/VBox/TitleLabel
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

	# Every quantity SpinBox drives the same recalculation, regardless of
	# which one the player just edited — value_changed hands us the new
	# value, but we ignore it and just re-sum all four inputs.
	for quantity_input in quantity_inputs:
		quantity_input.value_changed.connect(_on_quantity_changed)

	_reset_form()

func show_screen(new_expected_balance: float, title: String = "Drawer Count") -> void:
	expected_balance = new_expected_balance
	title_label.text = title
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

## The fewest bills mathematically able to make up `target`, largest
## denomination first — greedy is optimal here since each denomination
## divides evenly into the next size up (1000/500/100/50/10/1). Used as
## the "plausible" baseline: real bill counts can vary a little from this
## (a few mid-size bills instead of one big one), but shouldn't need wildly
## more bills than this to reach the same total.
func _minimum_bill_count(target: float) -> int:
	var remaining := int(round(target))
	var count := 0
	for denom in DENOMINATIONS:
		var quantity := remaining / denom
		count += quantity
		remaining -= quantity * denom
	return count

## How many more bills the player entered than the minimum possible for
## expected_balance — see PERFECT_BILL_COUNT_TOLERANCE's doc comment.
## Public so teller_screen.gd can factor this into its own Score/
## Reputation/XP grading of the ending count, the same way it already
## reads MINOR_DISCREPANCY_THRESHOLD directly.
func get_excess_bill_count() -> int:
	var player_bill_count := 0
	for quantity_input in quantity_inputs:
		player_bill_count += int(quantity_input.value)
	return maxi(0, player_bill_count - _minimum_bill_count(expected_balance))

func _update_live_total() -> void:
	your_total_label.text = "Your Total: $%.2f" % _calculate_total()

func _on_submit_button_pressed() -> void:
	var total := _calculate_total()
	var discrepancy := total - expected_balance
	var excess_bills := get_excess_bill_count()

	result_expected_label.text = "Expected Balance: $%.2f" % expected_balance
	result_total_label.text = "Your Total: $%.2f" % total
	discrepancy_label.text = "Discrepancy: $%.2f" % discrepancy

	if discrepancy == 0.0 and excess_bills <= PERFECT_BILL_COUNT_TOLERANCE:
		status_label.text = "Perfect Count!"
	elif abs(discrepancy) <= MINOR_DISCREPANCY_THRESHOLD and excess_bills <= MINOR_BILL_COUNT_TOLERANCE:
		status_label.text = "Minor Discrepancy"
		if discrepancy == 0.0:
			status_label.text += " (correct total, but an unusual bill mix)"
	else:
		status_label.text = "Major Discrepancy"
		if discrepancy == 0.0:
			status_label.text += " (correct total, but an implausible bill mix)"

	results_container.visible = true
	count_submitted.emit(total)
