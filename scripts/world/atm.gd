extends Area2D

## Detects the player standing nearby and emits "interacted" when they
## press the interact key. Identical pattern to teller_desk.gd/
## loan_officer_desk.gd — this script only announces the interaction, it
## has no idea what should happen next (open the ATM screen) and, unlike
## the job desks, isn't gated by shift/unlock state at all — see
## teller_room.gd, which just opens atm_screen.gd unconditionally.

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
