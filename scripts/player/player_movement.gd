extends CharacterBody2D

## 8-direction top-down movement, driving a 4-direction (down/up/side)
## AnimatedSprite2D. Side-facing uses one mirrored animation via flip_h
## rather than separate left/right art.

@export var speed: float = 200.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing: String = "down"
var _facing_flip: bool = false

func _physics_process(_delta: float) -> void:
	# get_vector() clamps combined/diagonal input to length 1, same effect
	# as the previous manual normalize() call — diagonal movement stays at
	# the same speed as straight movement instead of being sqrt(2)x faster.
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	velocity = input_vector * speed

	# move_and_slide() moves the body and stops it at collisions
	# (e.g. the TileMapLayer's wall tiles) instead of passing through them.
	move_and_slide()

	_update_facing(input_vector)
	_update_animation(input_vector)

func _update_facing(input_vector: Vector2) -> void:
	if input_vector == Vector2.ZERO:
		return # keep facing the last direction walked while idle

	if absf(input_vector.x) > absf(input_vector.y):
		_facing = "side"
		_facing_flip = input_vector.x < 0.0
	else:
		_facing = "down" if input_vector.y > 0.0 else "up"

func _update_animation(input_vector: Vector2) -> void:
	var is_moving := input_vector != Vector2.ZERO
	var anim_name := ("walk_" if is_moving else "idle_") + _facing

	sprite.flip_h = _facing_flip

	# Only (re)start the animation when the resolved state actually changes,
	# so switching between e.g. walk_down and idle_down doesn't restart the
	# loop mid-frame and stutter.
	if sprite.animation != anim_name:
		sprite.play(anim_name)

	# Scale the walk cycle to how fast the player is actually moving so it
	# never looks like the feet are sliding relative to the world.
	sprite.speed_scale = clampf(velocity.length() / speed, 0.6, 1.0) if is_moving else 1.0
