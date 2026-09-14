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

	if event.is_action_pressed("ui_accept"):
		interacted.emit()
		return

	# Safe cast: null if `event` isn't a key event, an InputEventKey otherwise.
	# Casting first (instead of checking `event is InputEventKey` and reading
	# .pressed/.echo/.keycode off the base InputEvent type) is what lets GDScript
	# know the exact type of those members.
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_E:
		interacted.emit()
