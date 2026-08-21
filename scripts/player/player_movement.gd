extends CharacterBody2D

## Simple 8-direction top-down movement for a placeholder player.
## Supports both WASD and arrow keys via the move_up/move_down/move_left/
## move_right InputMap actions (see project.godot's [input] section),
## so keys can be remapped later without touching this script.

@export var speed: float = 200.0

func _physics_process(_delta: float) -> void:
	# get_vector() clamps combined/diagonal input to length 1, same effect
	# as the previous manual normalize() call — diagonal movement stays at
	# the same speed as straight movement instead of being sqrt(2)x faster.
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	velocity = input_vector * speed

	# move_and_slide() moves the body and stops it at collisions
	# (e.g. the TileMapLayer's wall tiles) instead of passing through them.
	move_and_slide()
