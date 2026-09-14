extends CharacterBody2D
class_name CustomerNPC

## Phase 6a customer, given a name + flavor line in 6b. Still no
## patience/complaints (that's 6c) — just something that walks from a spawn
## point to a queue waypoint and stands there. The room is empty between
## those points, so this walks straight at the target rather than
## pathfinding, the same "no obstacles, no need for anything fancier"
## reasoning room_builder.gd gives for its own placeholder layout.
##
## Collision layer is deliberately its own (see customer_npc.tscn) — set to
## collide with walls only, not the player or other customers — so a queued
## customer never physically blocks the player from reaching the desk.

signal arrived

## Just enough for the UI to say who's being served (see teller_screen.gd's
## serving-status label). CustomerQueue assigns a random name from its pool
## on spawn.
@export var display_name: String = "Customer"

## Assigned once by CustomerQueue at spawn (see _spawn_customer()) and kept
## for the customer's whole time in queue — teller_screen.gd just reads it
## when it's their turn, it never re-rolls.
##
## Mutually exclusive with complaint below — a customer gets one or the
## other at spawn (see CustomerQueue.COMPLAINT_CHANCE), never both.
var dialogue_line: CustomerDialogueLine = null

## Phase 6c: assigned instead of dialogue_line for "complaint" customers
## (see CustomerQueue._spawn_customer()). teller_screen.gd shows this as a
## branching-response prompt rather than a flavor line.
var complaint: CustomerComplaint = null

## Set once the player has picked a response to complaint above, so
## reopening the Teller screen for the same still-queued customer shows
## the normal serving UI instead of the complaint prompt a second time.
var complaint_resolved: bool = false

## Phase 6e: assigned independently of dialogue_line/complaint above — a
## customer can be a complaint AND pay by card, or any combination.
## Reuses ShiftTransaction's enum rather than declaring a second,
## identical one just for this field.
var payment_method: ShiftTransaction.PaymentMethod = ShiftTransaction.PaymentMethod.CASH

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
