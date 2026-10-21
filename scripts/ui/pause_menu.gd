extends CanvasLayer
class_name PauseMenu

## The in-game pause menu: Esc (the `pause_menu` action) in the room opens
## it, with "Resume" and "Back to Main Menu". It pauses the game while open,
## like a desk screen. It only opens while nothing else has the game paused
## (no desk screen, letter or End of Day summary is up), so it never lands
## on top of a half-finished screen; Esc again, or Resume, closes it.
##
## Back to Main Menu saves first when that's safe, i.e. off shift: a career
## is only ever saved off shift (SaveGame: mid-shift state such as the queue
## and the drawer is never saved), so off shift the save is the same as a
## clock-out's. Clocked in at any desk, it can't be saved, so the menu asks
## first and says what will be lost (ON_SHIFT_TEXT). Either way the room's
## slot is left and the whole career is reset (the start screen does it
## again when it opens), so nothing leaks into the next slot played.

const ACTION: StringName = &"pause_menu"
const START_SCREEN: String = "res://scenes/ui/start_screen.tscn"

const ON_SHIFT_TEXT: String = "You're clocked in, and a career can't be saved in the middle of a shift.\n\nGoing back now loses everything since your last save (your last clock-out): this shift's customers and drawer, and the Score, Reputation and XP they earned.\n\nGo back to the main menu anyway?"

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
	confirm_label.text = ON_SHIFT_TEXT

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

## Off shift: save and go. On shift: ask first (it can't be saved).
func _on_main_menu_pressed() -> void:
	if room != null and room.is_player_on_shift():
		menu_panel.visible = false
		confirm_panel.visible = true
		cancel_button.grab_focus()
		return
	go_to_main_menu(true)

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
