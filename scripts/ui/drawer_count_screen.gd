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

const DENOMINATIONS: Array[int] = [1000, 500, 100, 50]
const MINOR_DISCREPANCY_THRESHOLD: float = 500.0

var expected_balance: float = 0.0
var _paused_by_self: bool = false

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var quantity_inputs: Array[SpinBox] = [
	$Panel/VBox/DenominationsGrid/Denom1000SpinBox,
	$Panel/VBox/DenominationsGrid/Denom500SpinBox,
	$Panel/VBox/DenominationsGrid/Denom100SpinBox,
	$Panel/VBox/DenominationsGrid/Denom50SpinBox,
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

func _update_live_total() -> void:
	your_total_label.text = "Your Total: $%.2f" % _calculate_total()

func _on_submit_button_pressed() -> void:
	var total := _calculate_total()
	var discrepancy := total - expected_balance

	result_expected_label.text = "Expected Balance: $%.2f" % expected_balance
	result_total_label.text = "Your Total: $%.2f" % total
	discrepancy_label.text = "Discrepancy: $%.2f" % discrepancy

	if discrepancy == 0.0:
		status_label.text = "Perfect Count!"
	elif abs(discrepancy) <= MINOR_DISCREPANCY_THRESHOLD:
		status_label.text = "Minor Discrepancy"
	else:
		status_label.text = "Major Discrepancy"

	results_container.visible = true
	count_submitted.emit(total)
