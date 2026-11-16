extends CanvasLayer
class_name SlotTransitionCard

## The card between two time slots (DayFlow.between_slots, slots on only):
## the next slot, big ("11 AM"), how many customers the player served in
## the slot just finished, a note once the 2 PM cutoff has passed, and
## "Continue" (DayFlow.continue_day()) or "Go home early"
## (DayFlow.go_home_early(), after a confirmation, and only while DayFlow
## allows it: between slots with a work slot ahead, so never before
## Closing).
##
## Like every screen it pauses the game while shown (get_tree().paused), so
## customers' patience and the arrival timers stop, and it only appears
## once nothing else has the game paused: the slot's last customer's teller
## screen closes first. If the day moves on without it (a slot starts, or
## the day ends), it closes itself.
##
## Shared by every role; it knows only DayFlow and BusinessDay's count of
## customers the player served.

const DONE_TEXT: String = "%s slot done — customers you served: %d"
const SHIFT_STARTED_TEXT: String = "Your shift has started."
const CUTOFF_TEXT: String = "The 2 PM cutoff has passed: transactions from now on post on the next business day."
const CLOSING_TEXT: String = "The branch closes. Do your closing count, then head home."
const CONFIRM_TEXT: String = "Go home early?\n\nThe rest of today's slots are skipped: their customers, and the XP they would have earned, are lost. You'll still do your closing count before you leave."

@onready var card_panel: PanelContainer = $Root/CardPanel
@onready var slot_label: Label = $Root/CardPanel/VBox/SlotLabel
@onready var done_label: Label = $Root/CardPanel/VBox/DoneLabel
@onready var note_label: Label = $Root/CardPanel/VBox/NoteLabel
@onready var continue_button: Button = $Root/CardPanel/VBox/ContinueButton
@onready var go_home_button: Button = $Root/CardPanel/VBox/GoHomeButton
@onready var confirm_panel: PanelContainer = $Root/ConfirmPanel
@onready var confirm_label: Label = $Root/ConfirmPanel/VBox/ConfirmLabel
@onready var confirm_button: Button = $Root/ConfirmPanel/VBox/ConfirmButton
@onready var cancel_button: Button = $Root/ConfirmPanel/VBox/CancelButton

## Waiting for the game to be free (unpaused) to show.
var _pending: bool = false
var _ended: DaySlot
var _next: DaySlot
## BusinessDay.customers_served_by_player when the current slot started.
var _served_at_slot_start: int = 0

func _ready() -> void:
	visible = false
	confirm_label.text = CONFIRM_TEXT
	continue_button.pressed.connect(_on_continue_pressed)
	go_home_button.pressed.connect(_show_confirm)
	confirm_button.pressed.connect(_on_go_home_confirmed)
	cancel_button.pressed.connect(_show_card_panel)
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.between_slots.connect(_on_between_slots)
	DayFlow.day_ended.connect(_on_day_moved_on)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.between_slots.disconnect(_on_between_slots)
	DayFlow.day_ended.disconnect(_on_day_moved_on)

func _process(_delta: float) -> void:
	if _pending and not get_tree().paused:
		_show()

func _unhandled_input(event: InputEvent) -> void:
	if visible and confirm_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_show_card_panel()
		get_viewport().set_input_as_handled()

func _on_slot_started(_slot: DaySlot) -> void:
	_served_at_slot_start = BusinessDay.customers_served_by_player
	_on_day_moved_on()

func _on_between_slots(ended: DaySlot, next: DaySlot) -> void:
	if not DayFlow.slots_enabled:
		return
	_ended = ended
	_next = next
	_pending = true
	if not get_tree().paused:
		_show()

func _show() -> void:
	_pending = false
	slot_label.text = _next.label
	done_label.text = done_text()
	done_label.visible = done_label.text != ""
	note_label.text = note_text()
	note_label.visible = note_label.text != ""
	go_home_button.visible = DayFlow.can_go_home_early()
	visible = true
	get_tree().paused = true
	_show_card_panel()

## About the slot just finished: "9 AM slot done — customers you served: 2".
func done_text() -> String:
	if _ended == null:
		return ""
	if _ended.is_work:
		return DONE_TEXT % [_ended.label, BusinessDay.customers_served_by_player - _served_at_slot_start]
	if _ended.id == DaySchedule.OPENING:
		return SHIFT_STARTED_TEXT
	return ""

## The cutoff note before the first slot after it, the closing note before
## Closing.
func note_text() -> String:
	if _next == null:
		return ""
	if _next.id == DaySchedule.FIRST_SLOT_AFTER_CUTOFF:
		return CUTOFF_TEXT
	if _next.id == DaySchedule.CLOSING:
		return CLOSING_TEXT
	return ""

func _show_card_panel() -> void:
	card_panel.visible = true
	confirm_panel.visible = false
	continue_button.grab_focus()

func _show_confirm() -> void:
	card_panel.visible = false
	confirm_panel.visible = true
	cancel_button.grab_focus()

func _on_continue_pressed() -> void:
	_close()
	DayFlow.continue_day()

func _on_go_home_confirmed() -> void:
	_close()
	DayFlow.go_home_early()

## The day moved on without the card (or the card's own button did it).
func _on_day_moved_on() -> void:
	_pending = false
	if visible:
		_close()

func _close() -> void:
	visible = false
	get_tree().paused = false
