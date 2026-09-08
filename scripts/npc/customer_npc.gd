extends CharacterBody2D
class_name CustomerNPC

## Placeholder Phase 6a customer. No dialogue, no patience/complaints (that's
## 6b/6c) — just something that walks from a spawn point to a queue waypoint
## and stands there. The room is empty between those points, so this walks
## straight at the target rather than pathfinding, the same "no obstacles,
## no need for anything fancier" reasoning room_builder.gd gives for its own
## placeholder layout.
##
## Collision layer is deliberately its own (see customer_npc.tscn) — set to
## collide with walls only, not the player or other customers — so a queued
## customer never physically blocks the player from reaching the desk.

signal arrived

## Placeholder identifier only — just enough for the UI to say who's being
## served (see teller_screen.gd's serving-status label). Real names/variety
## are 6b's job; CustomerQueue just assigns these sequentially on spawn.
@export var display_name: String = "Customer"

@export var speed: float = 120.0

const ARRIVAL_DISTANCE: float = 4.0

var target_position: Vector2
var _walking: bool = false

func _ready() -> void:
	target_position = global_position

## Starts walking toward new_target; arrived fires once it gets there.
func walk_to(new_target: Vector2) -> void:
	target_position = new_target
	_walking = true

func _physics_process(_delta: float) -> void:
	if not _walking:
		return

	var to_target := target_position - global_position
	if to_target.length() <= ARRIVAL_DISTANCE:
		global_position = target_position
		velocity = Vector2.ZERO
		_walking = false
		arrived.emit()
		return

	velocity = to_target.normalized() * speed
	move_and_slide()
