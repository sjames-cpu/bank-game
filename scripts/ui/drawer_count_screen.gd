extends Control
class_name DrawerCountScreen

## Cash-counting mini-game: the player enters how many notes of each
## denomination are in the drawer, and it's checked against an expected
## balance the caller supplies (the teller screen's shift system decides
## what that number should be — a fixed starting float, or starting
## balance + deposits - withdrawals at clock-out). This screen doesn't
## know or care which; it just compares and reports.
##
## Every amount is int cents (B3, see MoneyMath), denominations included, so
## coins can be added as more DENOMINATION_CENTS entries.
##
## Manages its own pause state so it works whether or not a caller has
## already paused the tree (TellerScreen currently pauses for its own,
## broader reasons — the whole teller interaction, not just this screen —
## so both this screen and TellerScreen pause defensively; _paused_by_self
## tracks whether *this* screen was the one that did it, so closing this
## screen never unpauses a tree that TellerScreen still needs paused).

signal count_submitted(total_cents: int)
signal closed

## Face value of each row of quantity_inputs: $1000, $500, $100, $50, $10, $1.
const DENOMINATION_CENTS: Array[int] = [100000, 50000, 10000, 5000, 1000, 100]
const MINOR_DISCREPANCY_THRESHOLD_CENTS: int = 50000

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

var expected_cents: int = 0
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
	# value, but we ignore it and just re-sum all six inputs.
	for quantity_input in quantity_inputs:
		quantity_input.value_changed.connect(_on_quantity_changed)

	_reset_form()

func show_screen(new_expected_cents: int, title: String = "Drawer Count") -> void:
	expected_cents = new_expected_cents
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

func _calculate_total_cents() -> int:
	var total := 0
	for i in DENOMINATION_CENTS.size():
		total += DENOMINATION_CENTS[i] * int(quantity_inputs[i].value)
	return total

## The fewest bills mathematically able to make up `target_cents`, largest
## denomination first — greedy is optimal here since each denomination
## divides evenly into the next size up (1000/500/100/50/10/1). Used as
## the "plausible" baseline: real bill counts can vary a little from this
## (a few mid-size bills instead of one big one), but shouldn't need wildly
## more bills than this to reach the same total.
func _minimum_bill_count(target_cents: int) -> int:
	var remaining := target_cents
	var count := 0
	for denom in DENOMINATION_CENTS:
		@warning_ignore("integer_division")
		var quantity := remaining / denom
		count += quantity
		remaining -= quantity * denom
	return count

## How many more bills the player entered than the minimum possible for
## expected_cents — see PERFECT_BILL_COUNT_TOLERANCE's doc comment.
## Public so teller_screen.gd can factor this into its own Score/
## Reputation/XP grading of the ending count, the same way it already
## reads MINOR_DISCREPANCY_THRESHOLD_CENTS directly.
func get_excess_bill_count() -> int:
	var player_bill_count := 0
	for quantity_input in quantity_inputs:
		player_bill_count += int(quantity_input.value)
	return maxi(0, player_bill_count - _minimum_bill_count(expected_cents))

func _update_live_total() -> void:
	your_total_label.text = "Your Total: %s" % MoneyMath.format(_calculate_total_cents())

func _on_submit_button_pressed() -> void:
	var total_cents := _calculate_total_cents()
	var discrepancy_cents := total_cents - expected_cents
	var excess_bills := get_excess_bill_count()

	result_expected_label.text = "Expected Balance: %s" % MoneyMath.format(expected_cents)
	result_total_label.text = "Your Total: %s" % MoneyMath.format(total_cents)
	discrepancy_label.text = "Discrepancy: %s" % MoneyMath.format(discrepancy_cents)

	if discrepancy_cents == 0 and excess_bills <= PERFECT_BILL_COUNT_TOLERANCE:
		status_label.text = "Perfect Count!"
	elif absi(discrepancy_cents) <= MINOR_DISCREPANCY_THRESHOLD_CENTS and excess_bills <= MINOR_BILL_COUNT_TOLERANCE:
		status_label.text = "Minor Discrepancy"
		if discrepancy_cents == 0:
			status_label.text += " (correct total, but an unusual bill mix)"
	else:
		status_label.text = "Major Discrepancy"
		if discrepancy_cents == 0:
			status_label.text += " (correct total, but an implausible bill mix)"

	results_container.visible = true
	count_submitted.emit(total_cents)

## Adds a line under the result's status (e.g. TellerScreen's "Recount
## required" for a Major opening count). Call after count_submitted.
func append_status_note(note: String) -> void:
	status_label.text += "\n" + note
