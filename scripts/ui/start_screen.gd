extends Control
class_name StartScreen

## The game's main scene: the main menu ("Play", "Quit") and the save slot
## screen behind Play (SaveGame.SLOT_COUNT slots, and "Back").
##
## A slot with a career shows its role, its in-game day and date, and when
## it was last played (saved); clicking it loads that career
## (SaveGame.restore()) and walks into teller_room off shift. An empty slot
## shows "New Game" and starts a new career in it. A slot whose save can't
## be read (damaged, or another version) says so; clicking it offers a new
## game there, with the bad file set aside beside it (SaveGame.set_aside()).
## A filled slot also has a Delete button, which asks "Delete this save?
## This cannot be undone." before deleting that slot only.
##
## Every slot is its own file: choosing one calls SaveGame.use_slot(), so the
## career saves to that slot only.
##
## How a new career starts depends on InterviewManager.interview_enabled
## (the INTERVIEW_ENABLED switch): with the interview off the player is hired
## at once as a regular Teller (no probation), saved, and walks into the
## room; with it on, the new career starts at the interview.
##
## No leftover state: whenever this screen opens (at launch, "Back to Main
## Menu" from the pause menu, or after a termination) it unpauses the game,
## leaves the slot and resets the whole career (CareerReset), so nothing of
## the career just left can reach the next one.

const INTERVIEW_SCENE: String = "res://scenes/ui/interview_screen.tscn"
const TELLER_ROOM_SCENE: String = "res://scenes/world/teller_room.tscn"

enum View { MAIN_MENU, SLOTS }

## The view the next start screen opens on, consumed when it opens:
## termination sets SLOTS (discipline_letter_screen.gd), so the player lands
## on the slot screen, where that slot now offers "New Game".
static var next_view: View = View.MAIN_MENU

const DAMAGED_MESSAGE: String = "The save in Slot %d is damaged and can't be loaded.\n\nStart a new game in this slot? The damaged file is kept beside it, renamed to end in .bad."
const WRONG_VERSION_MESSAGE: String = "The save in Slot %d is from a different version of BankSim and can't be loaded.\n\nStart a new game in this slot? The old file is kept beside it, renamed to end in .bad."

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var play_button: Button = $MenuPanel/VBox/PlayButton
@onready var quit_button: Button = $MenuPanel/VBox/QuitButton

@onready var slot_panel: PanelContainer = $SlotPanel
@onready var slot_buttons: Array[Button] = [
	$SlotPanel/VBox/Slot1Row/Slot1Button,
	$SlotPanel/VBox/Slot2Row/Slot2Button,
	$SlotPanel/VBox/Slot3Row/Slot3Button,
]
## One per slot, shown only on a filled slot (a save that loads).
@onready var delete_buttons: Array[Button] = [
	$SlotPanel/VBox/Slot1Row/Slot1DeleteButton,
	$SlotPanel/VBox/Slot2Row/Slot2DeleteButton,
	$SlotPanel/VBox/Slot3Row/Slot3DeleteButton,
]
@onready var back_button: Button = $SlotPanel/VBox/BackButton

## "Delete this save? This cannot be undone." with Delete / Cancel.
@onready var delete_panel: PanelContainer = $DeletePanel
@onready var confirm_delete_button: Button = $DeletePanel/VBox/ConfirmDeleteButton
@onready var cancel_delete_button: Button = $DeletePanel/VBox/CancelDeleteButton

## The slot the delete confirmation is asking about.
var _delete_slot: int = 0

@onready var message_panel: PanelContainer = $MessagePanel
@onready var message_label: Label = $MessagePanel/VBox/MessageLabel
@onready var message_new_game_button: Button = $MessagePanel/VBox/NewGameButton
@onready var message_back_button: Button = $MessagePanel/VBox/BackButton

## What SaveGame.read_slot() found for each slot (index slot - 1), as shown.
var slot_results: Array[SaveGame.ReadResult] = []

## The unreadable slot the message panel is asking about.
var _message_slot: int = 0

func _ready() -> void:
	# The real game starts here, so from now on it may write the real saves
	# (SaveGame.real_prefix). Nothing else turns this on.
	SaveGame.allow_real_save()
	# Nothing of a previous career survives the menu.
	get_tree().paused = false
	SaveGame.leave_slot()
	CareerReset.reset_all()
	# The single save from before slots becomes Slot 1 (only if Slot 1 is free).
	SaveGame.migrate_legacy_save()

	play_button.pressed.connect(show_slots)
	quit_button.pressed.connect(_on_quit_pressed)
	for i in slot_buttons.size():
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))
		delete_buttons[i].pressed.connect(_on_delete_pressed.bind(i + 1))
	confirm_delete_button.pressed.connect(_on_confirm_delete_pressed)
	cancel_delete_button.pressed.connect(show_slots)
	back_button.pressed.connect(show_main_menu)
	message_new_game_button.pressed.connect(_on_message_new_game_pressed)
	message_back_button.pressed.connect(show_slots)

	var view := next_view
	next_view = View.MAIN_MENU
	if view == View.SLOTS:
		show_slots()
	else:
		show_main_menu()

func show_main_menu() -> void:
	_show_only(menu_panel)
	play_button.grab_focus()

## Reads every slot afresh and shows them.
func show_slots() -> void:
	slot_results.clear()
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		var result := SaveGame.read_slot(slot)
		slot_results.append(result)
		slot_buttons[slot - 1].text = slot_text(slot, result)
		delete_buttons[slot - 1].visible = result.status == SaveGame.Status.OK
	_show_only(slot_panel)
	slot_buttons[0].grab_focus()

## A slot button's text: "Slot 1 — Loan Officer" with the in-game day and
## date and when it was last played, or "New Game" for an empty slot.
static func slot_text(slot: int, result: SaveGame.ReadResult) -> String:
	match result.status:
		SaveGame.Status.MISSING:
			return "Slot %d\nNew Game" % slot
		SaveGame.Status.OK:
			var text := "Slot %d — %s\n%s" % [slot, role_of(result.career), game_date_of(result.career)]
			if result.saved_at != "":
				text += "\nLast played %s" % last_played_text(result.saved_at)
			return text
		SaveGame.Status.WRONG_VERSION:
			return "Slot %d\nSaved by another version of BankSim (can't be loaded)" % slot
		_:
			return "Slot %d\nDamaged save (can't be loaded)" % slot

## The saved career's highest role.
static func role_of(career: Dictionary) -> String:
	var xp := SaveGame.dict_of(career, "xp")
	if SaveGame.bool_of(xp, "is_branch_manager_unlocked", false):
		return "Branch Manager"
	if SaveGame.bool_of(xp, "is_loan_officer_unlocked", false):
		return "Loan Officer"
	return "Teller"

## "Day 3 · Wednesday 7 January 2026 · 10:42 AM": where the career's game
## clock stands.
static func game_date_of(career: Dictionary) -> String:
	var clock := SaveGame.dict_of(career, "clock")
	var day := maxi(GameClock.START_DAY, SaveGame.int_of(clock, "day", GameClock.START_DAY))
	var start := BankCalendar.from_iso(SaveGame.string_of(clock, "start_date", ""), BankCalendar.start_date())
	var minutes := SaveGame.float_of(clock, "minutes", GameClock.START_MINUTES)
	return "Day %d · %s · %s" % [day, BankCalendar.long_text(BankCalendar.business_day_date(start, day)), GameClock.format_time(minutes)]

## The save's real-world time ("2026-10-21T14:05:33") as "2026-10-21 14:05":
## the one place the player sees the wall clock.
static func last_played_text(saved_at: String) -> String:
	var text := saved_at.replace("T", " ")
	# Drop the seconds.
	if text.length() >= 16:
		text = text.substr(0, 16)
	return text

func _show_only(panel: Control) -> void:
	for each: Control in [menu_panel, slot_panel, message_panel, delete_panel]:
		each.visible = each == panel

func _on_slot_pressed(slot: int) -> void:
	var result := slot_results[slot - 1]
	match result.status:
		SaveGame.Status.MISSING:
			start_new_career(slot)
		SaveGame.Status.OK:
			continue_career(slot, result.career)
		_:
			_message_slot = slot
			message_label.text = (WRONG_VERSION_MESSAGE if result.status == SaveGame.Status.WRONG_VERSION else DAMAGED_MESSAGE) % slot
			_show_only(message_panel)
			message_back_button.grab_focus()

## Loads slot `slot`'s career and walks into the room off shift.
func continue_career(slot: int, career: Dictionary) -> void:
	SaveGame.use_slot(slot)
	SaveGame.restore(career)
	get_tree().change_scene_to_file(TELLER_ROOM_SCENE)

## Starts a new career in slot `slot` (empty, or its bad file just set aside).
func start_new_career(slot: int) -> void:
	SaveGame.use_slot(slot)
	CareerReset.reset_all()
	if InterviewManager.interview_enabled:
		# The interview's hire saves the career into this slot.
		get_tree().change_scene_to_file(INTERVIEW_SCENE)
		return
	# Interview off: hired straight away as a regular Teller, and saved at
	# once, the way an interview hire is (interview_screen.gd), so the slot
	# shows the career even if the player quits before the first clock-out.
	InterviewManager.hire_without_interview()
	SaveGame.save()
	get_tree().change_scene_to_file(TELLER_ROOM_SCENE)

func _on_message_new_game_pressed() -> void:
	SaveGame.use_slot(_message_slot)
	SaveGame.set_aside()
	start_new_career(_message_slot)

## A filled slot's Delete: ask first.
func _on_delete_pressed(slot: int) -> void:
	_delete_slot = slot
	_show_only(delete_panel)
	cancel_delete_button.grab_focus()

## Confirmed: that slot's save goes (SaveGame.delete_slot(), the same delete
## a termination uses: that slot only), and the slots show again, with it as
## New Game.
func _on_confirm_delete_pressed() -> void:
	SaveGame.delete_slot(_delete_slot)
	_delete_slot = 0
	show_slots()

func _on_quit_pressed() -> void:
	get_tree().quit()
