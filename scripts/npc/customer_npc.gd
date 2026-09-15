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

## Phase 6g: emitted once (see _abandoning guard) when wait_seconds crosses
## WAIT_ABANDON_SECONDS without the customer having been served. CustomerQueue
## listens for this to pop the customer out of line and hands the consequence
## (Reputation penalty + HistoryManager record) off to teller_room.gd, the
## same division of responsibility serve_front_customer() already has.
signal patience_expired

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

## Phase 6g: a compressed stand-in for the ~5-real-minute wait that real
## branch research cites as where customers start abandoning a line —
## 5 minutes of real waiting would just be tedious for a player, so this
## keeps the same "long enough to feel like genuine pressure, short enough
## a normally-paced player rarely sees it" shape at game speed.
const WAIT_ABANDON_SECONDS: float = 50.0

## Tinted toward this as wait_seconds climbs (see _process below), so the
## patience cue reads as "this customer's placeholder tint is reddening"
## rather than replacing their color outright.
const IMPATIENT_COLOR: Color = Color(0.9, 0.15, 0.15)

## How long this customer has been in the queue. Starts counting the moment
## the node exists, which is also the moment CustomerQueue._spawn_customer()
## appends it to queue — there's no separate "spawned but not yet in line"
## state in this architecture, so "since spawn" and "since joined the queue"
## are the same instant here.
var wait_seconds: float = 0.0

## Set once patience_expired has fired so _process stops ticking/re-emitting
## for a customer that's already on their way out.
var _abandoning: bool = false

var target_position: Vector2
var _walking: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
var _base_modulate: Color

func _ready() -> void:
	target_position = global_position
	_base_modulate = _sprite.modulate

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

## No explicit process_mode override, so this inherits PROCESS_MODE_INHERIT
## like everything else in the room (CustomerQueue's SpawnTimer included) —
## meaning wait time (and the visual cue below) only accumulates while the
## world is actually running, not while a screen has the tree paused. That's
## what keeps a customer from abandoning mid-transaction just because the
## player is taking their time on the screen currently serving them.
func _process(delta: float) -> void:
	if _abandoning:
		return
	wait_seconds += delta
	var urgency := clampf(wait_seconds / WAIT_ABANDON_SECONDS, 0.0, 1.0)
	_sprite.modulate = _base_modulate.lerp(IMPATIENT_COLOR, urgency)
	if wait_seconds >= WAIT_ABANDON_SECONDS:
		_abandoning = true
		patience_expired.emit()
