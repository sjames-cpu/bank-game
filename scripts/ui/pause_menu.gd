extends CanvasLayer
class_name PauseMenu

## The in-game pause menu: Esc (the `pause_menu` action) in the room opens
## it, with "Resume" and "Back to Main Menu". It pauses the game while open,
## like a desk screen. It only opens while nothing else has the game paused
## (no desk screen, letter or End of Day summary is up), so it never lands
## on top of a half-finished screen; Esc again, or Resume, closes it.
##
## Back to Main Menu: a career is saved only at the end of a day and at its
## start (decision 8, SlotSavePolicy), so once the day is under way the menu
## asks first and says the day will restart from Opening (decision 10,
## MID_DAY_TEXT), and saves nothing; at Opening before the clock-in, or once
## the day has ended, it goes at once (saving if the rules allow). Either way
## the room's slot is left and the whole career is reset (the start screen
## does it again when it opens), so nothing leaks into the next slot played.

const ACTION: StringName = &"pause_menu"
const START_SCREEN: String = "res://scenes/ui/start_screen.tscn"

## Leaving mid-day (decision 10): the day restarts from Opening.
const MID_DAY_TEXT: String = "Today isn't over, and a career is only saved at the end of a day.\n\nIf you go back now, this day restarts from Opening when you load this career: everything since the start of today (its customers, applications, Score, Reputation and XP) is lost.\n\nGo back to the main menu anyway?"
const MID_DAY_CONFIRM_TEXT: String = "Lose Today and Go to Main Menu"

@onready var menu_panel: PanelContainer = $Root/MenuPanel
@onready var resume_button: Button = $Root/MenuPanel/VBox/ResumeButton
@onready var main_menu_button: Button = $Root/MenuPanel/VBox/MainMenuButton
@onready var confirm_panel: PanelContainer = $Root/ConfirmPanel
@onready var confirm_label: Label = $Root/ConfirmPanel/VBox/ConfirmLabel
@onready var confirm_button: Button = $Root/ConfirmPanel/VBox/ConfirmButton
@onready var cancel_button: Button = $Root/ConfirmPanel/VBox/CancelButton

## The room this menu belongs to (its parent), for its shift state and save.
var room: TellerRoom

func _ready() -> void:
	room = get_parent() as TellerRoom
	visible = false
	resume_button.pressed.connect(resume)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	confirm_button.pressed.connect(go_to_main_menu.bind(false))
	cancel_button.pressed.connect(_show_menu)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION) or event.is_echo():
		return
	if visible:
		resume()
		get_viewport().set_input_as_handled()
	elif can_open():
		open()
		get_viewport().set_input_as_handled()

## Only while nothing else has the game paused (see the class doc).
func can_open() -> bool:
	return not visible and not get_tree().paused

func open() -> void:
	visible = true
	get_tree().paused = true
	_show_menu()

func resume() -> void:
	visible = false
	get_tree().paused = false

func _show_menu() -> void:
	menu_panel.visible = true
	confirm_panel.visible = false
	resume_button.grab_focus()

## Mid-day: ask first (the day will restart from Opening). At Opening
## before the clock-in, or once the day has ended, nothing would be lost.
func _on_main_menu_pressed() -> void:
	var warning := leave_warning()
	if warning != "":
		confirm_label.text = warning
		menu_panel.visible = false
		confirm_panel.visible = true
		cancel_button.grab_focus()
		return
	go_to_main_menu(true)

## What leaving now would lose ("" if nothing).
func leave_warning() -> String:
	if not DayFlow.is_running():
		return ""
	var at_opening := DayFlow.current_slot().id == DaySchedule.OPENING
	if at_opening and not PlayerShift.is_on_shift():
		return ""
	return MID_DAY_TEXT

## Back to the main menu, saving first if `save`. The slot is left and the
## career reset, so the next slot played starts clean.
func go_to_main_menu(save: bool) -> void:
	if save and room != null:
		room.save_career()
	visible = false
	get_tree().paused = false
	SaveGame.leave_slot()
	CareerReset.reset_all()
	StartScreen.next_view = StartScreen.View.MAIN_MENU
	get_tree().change_scene_to_file(START_SCREEN)
