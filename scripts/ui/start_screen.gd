extends Control
class_name StartScreen

## The game's main scene. With no save it goes straight on to the interview
## (a new game, as before saves existed). With a save it offers "Continue"
## (restore the career, SaveGame.restore(), and walk into teller_room off
## shift) and "New Game" (after a confirmation, delete the save and start
## at the interview). A save that can't be read (damaged, or another
## version) never stops the game: a short message, then a new game, with
## the bad file set aside (SaveGame.set_aside()).

const INTERVIEW_SCENE: String = "res://scenes/ui/interview_screen.tscn"
const TELLER_ROOM_SCENE: String = "res://scenes/world/teller_room.tscn"

const CORRUPT_MESSAGE: String = "Your saved career couldn't be loaded: the save file is damaged.\n\nStarting a new game."
const WRONG_VERSION_MESSAGE: String = "Your saved career is from a different version of BankSim and can't be loaded.\n\nStarting a new game."

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var summary_label: Label = $MenuPanel/VBox/SummaryLabel
@onready var continue_button: Button = $MenuPanel/VBox/ContinueButton
@onready var new_game_button: Button = $MenuPanel/VBox/NewGameButton

@onready var confirm_panel: PanelContainer = $ConfirmPanel
@onready var confirm_button: Button = $ConfirmPanel/VBox/ConfirmButton
@onready var cancel_button: Button = $ConfirmPanel/VBox/CancelButton

@onready var message_panel: PanelContainer = $MessagePanel
@onready var message_label: Label = $MessagePanel/VBox/MessageLabel
@onready var message_ok_button: Button = $MessagePanel/VBox/OkButton

## What SaveGame.read() found at startup.
var saved: SaveGame.ReadResult

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	confirm_button.pressed.connect(_on_confirm_new_game_pressed)
	cancel_button.pressed.connect(_show_only.bind(menu_panel))
	message_ok_button.pressed.connect(_on_message_ok_pressed)
	_show_only(null)

	saved = SaveGame.read()
	match saved.status:
		SaveGame.Status.MISSING:
			# Deferred: the tree is still adding this scene.
			_start_new_career.call_deferred()
		SaveGame.Status.OK:
			summary_label.text = describe(saved)
			_show_only(menu_panel)
		SaveGame.Status.WRONG_VERSION:
			message_label.text = WRONG_VERSION_MESSAGE
			_show_only(message_panel)
		_:
			message_label.text = CORRUPT_MESSAGE
			_show_only(message_panel)

## "Saved career: Loan Officer · Score 120 · Reputation 55", plus when.
static func describe(result: SaveGame.ReadResult) -> String:
	var xp := SaveGame.dict_of(result.career, "xp")
	var role := "Teller"
	if SaveGame.bool_of(xp, "is_branch_manager_unlocked", false):
		role = "Branch Manager"
	elif SaveGame.bool_of(xp, "is_loan_officer_unlocked", false):
		role = "Loan Officer"
	var score := SaveGame.int_of(SaveGame.dict_of(result.career, "score"), "total_score", 0)
	var reputation := SaveGame.int_of(SaveGame.dict_of(result.career, "reputation"), "reputation", ReputationManager.STARTING_REPUTATION)
	var text := "Saved career: %s · Score %d · Reputation %d" % [role, score, reputation]
	if result.saved_at != "":
		text += "\nSaved %s" % result.saved_at.replace("T", " ")
	return text

func _show_only(panel: Control) -> void:
	for each: Control in [menu_panel, confirm_panel, message_panel]:
		each.visible = each == panel

func _on_continue_pressed() -> void:
	SaveGame.restore(saved.career)
	get_tree().change_scene_to_file(TELLER_ROOM_SCENE)

func _on_new_game_pressed() -> void:
	_show_only(confirm_panel)

func _on_confirm_new_game_pressed() -> void:
	SaveGame.delete()
	_start_new_career()

func _on_message_ok_pressed() -> void:
	SaveGame.set_aside()
	_start_new_career()

func _start_new_career() -> void:
	CareerReset.reset_all()
	get_tree().change_scene_to_file(INTERVIEW_SCENE)
