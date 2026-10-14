extends Area2D
class_name Interactable

## Something in the room the player can walk up to and use with the interact
## key: the desks and the ATM (TellerDesk, LoanOfficerDesk,
## BranchManagerDesk, ATM extend this). It only detects the player standing
## nearby and emits "interacted" when they press the key; it has no idea
## what should happen next or whether it's usable yet. Whoever cares connects
## to the signal instead (teller_room.gd), which also drives the HUD's
## interaction prompt off player_in_range.

signal interacted

var player_in_range := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(_body: Node2D) -> void:
	player_in_range = true

func _on_body_exited(_body: Node2D) -> void:
	player_in_range = false

func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range:
		return
	# The interact key (E) is an InputMap action so on-screen prompts can name
	# the key that actually works (InputPrompts).
	if event.is_action_pressed("ui_accept") or event.is_action_pressed(InputPrompts.INTERACT):
		interacted.emit()
