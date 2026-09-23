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
## other at spawn (see CustomerQueue.COMPLAINT_CHANCE), never both. For a
## regular (non-complaint) customer this now holds their stated Deposit/
## Withdraw request rather than a pure flavor line — see intent_type/
## intent_amount below and CustomerQueue._assign_transaction_intent().
var dialogue_line: CustomerDialogueLine = null

## Phase 6c: assigned instead of dialogue_line for "complaint" customers
## (see CustomerQueue._spawn_customer()). teller_screen.gd shows this as a
## branching-response prompt rather than a flavor line.
var complaint: CustomerComplaint = null

## Phase 6h: this customer's own Account, created or reused by name at
## spawn (see CustomerQueue._get_or_create_customer_account()) so serving
## them at the Teller desk selects THEIR account rather than the unrelated
## shared demo one.
var account: Account = null

## Phase 6h: only meaningful for non-complaint customers (see dialogue_line
## above) — what this customer actually wants done, matching the sentence
## in dialogue_line. Reuses ShiftTransaction.Type rather than declaring a
## second, identical enum, the same reasoning payment_method below already
## gives for reusing ShiftTransaction.PaymentMethod.
var intent_type: ShiftTransaction.Type = ShiftTransaction.Type.DEPOSIT
var intent_amount: float = 0.0

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

## Phase 6i: shown briefly above a served customer before they walk off
## toward the exit (see say_farewell_and_leave()). A handful of static
## lines is enough per Requirement 1 — this doesn't need a growing content
## pool the way CustomerDialogueData's flavor lines do.
const FAREWELL_LINES: Array[String] = [
	"Thank you!",
	"Appreciate your help!",
	"Have a great day!",
	"Thanks so much!",
]

const FAREWELL_DISPLAY_SECONDS: float = 1.5

## Quick-designed visual variety (see scratch/gen_customer_sprites.py for
## how these were drawn): each spawned customer gets one of these three
## looks at random in _ready(), same as the .tscn's default (customer_a)
## would otherwise always be. Preloaded once as a class-level const rather
## than re-loaded per instance.
const CUSTOMER_FRAME_SETS: Array[SpriteFrames] = [
	preload("res://assets/sprites/customer_a_frames.tres"),
	preload("res://assets/sprites/customer_b_frames.tres"),
	preload("res://assets/sprites/customer_c_frames.tres"),
]

var target_position: Vector2
var _walking: bool = false

## Set once say_farewell_and_leave() has been called, so it can't be
## triggered twice on the same customer.
var _leaving: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _farewell_label: Label = $FarewellLabel
var _base_modulate: Color

## Mirrors player_movement.gd's own _facing/_facing_flip — side-facing
## reuses one mirrored animation via flip_h rather than separate left/right
## art, same reasoning as there.
var _facing: String = "down"
var _facing_flip: bool = false

func _ready() -> void:
	target_position = global_position
	_sprite.sprite_frames = CUSTOMER_FRAME_SETS.pick_random()
	_base_modulate = _sprite.modulate

## Starts walking toward new_target; arrived fires once it gets there.
func walk_to(new_target: Vector2) -> void:
	target_position = new_target
	_walking = true

## Phase 6i: called once by CustomerQueue.send_customer_off() after this
## customer has been served and the Teller screen closed. Shows a random
## farewell line for FAREWELL_DISPLAY_SECONDS, then walks to exit_position
## (the room's spawn point, i.e. entry path reversed — see walk_to() above,
## the same movement this customer used to enter the queue) and frees
## itself once it arrives. By the time this runs the customer has already
## been popped out of CustomerQueue.queue (see serve_front_customer()), so
## this whole sequence plays independently in the background and never
## delays queue advancement for anyone else.
func say_farewell_and_leave(exit_position: Vector2) -> void:
	if _leaving:
		return
	_leaving = true
	_abandoning = true # stop the patience tint — this customer is done, not waiting

	_farewell_label.text = FAREWELL_LINES.pick_random()
	_farewell_label.visible = true
	await get_tree().create_timer(FAREWELL_DISPLAY_SECONDS).timeout
	_farewell_label.visible = false

	arrived.connect(queue_free, CONNECT_ONE_SHOT)
	walk_to(exit_position)

func _physics_process(_delta: float) -> void:
	if not _walking:
		_update_animation(false)
		return

	var to_target := target_position - global_position
	if to_target.length() <= ARRIVAL_DISTANCE:
		global_position = target_position
		velocity = Vector2.ZERO
		_walking = false
		_update_animation(false)
		arrived.emit()
		return

	velocity = to_target.normalized() * speed
	move_and_slide()
	_update_facing(velocity)
	_update_animation(true)

func _update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return # keep facing the last direction walked while idle

	if absf(direction.x) > absf(direction.y):
		_facing = "side"
		_facing_flip = direction.x < 0.0
	else:
		_facing = "down" if direction.y > 0.0 else "up"

func _update_animation(is_moving: bool) -> void:
	var anim_name := ("walk_" if is_moving else "idle_") + _facing

	_sprite.flip_h = _facing_flip

	# Only (re)start the animation when the resolved state actually
	# changes, same guard player_movement.gd uses, so switching e.g.
	# walk_down -> idle_down doesn't restart the loop mid-frame.
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)

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
