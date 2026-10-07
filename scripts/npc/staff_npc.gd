extends CharacterBody2D
class_name StaffNPC

## A coworker working one of the branch's desks (see ScheduleManager's desk
## slots and teller_room.gd, which places these). Visual only for now —
## staff don't serve customers yet.
##
## Same placeholder approach as CustomerNPC (customer sprite frames, walks
## straight at a target, no pathfinding), but visibly staff: a blue
## "uniform" tint and their name always shown above them. Movement follows
## a list of waypoints (follow_route()) so teller_room.gd can route them
## around the back-office wall to the break room and back.
##
## Collision layer is its own (see staff_npc.tscn) and only collides with
## walls, like customers, so a coworker never blocks the player.

signal route_finished

enum State { AT_DESK, WALKING, ON_BREAK }

const ARRIVAL_DISTANCE: float = 4.0
const SPEED: float = 110.0

## Strong blue "uniform" tint plus a gold name badge (Badge in the scene)
## mark staff apart from customers at a glance — customers start untinted
## and only redden with impatience, and never wear a badge.
const STAFF_TINT: Color = Color(0.3, 0.5, 1.0)

var staff: StaffMember = null
var state: State = State.AT_DESK

var _route: Array[Vector2] = []
var _route_end_state: State = State.AT_DESK

## How many points of the current/last route have been reached — lets the
## room send someone back along exactly the part of the route they walked
## if they're called back before arriving.
var waypoints_reached: int = 0

## Same "keep facing the last direction walked" bookkeeping as CustomerNPC.
var _facing: String = "down"
var _facing_flip: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _name_label: Label = $NameLabel
@onready var _speech_label: Label = $SpeechLabel

var _speech_token: int = 0

func _ready() -> void:
	_sprite.modulate = STAFF_TINT
	if staff != null:
		_name_label.text = staff.staff_name

## Call before adding to the tree (or any time after) to set who this is.
func setup(member: StaffMember) -> void:
	staff = member
	if is_node_ready():
		_name_label.text = member.staff_name

## Short speech line above the name label, hidden after `seconds` of
## unpaused time unless something newer replaced it.
func say(text: String, seconds: float = 2.2) -> void:
	_speech_token += 1
	_speech_label.text = text
	_speech_label.visible = true
	get_tree().create_timer(seconds, false).timeout.connect(_hide_speech.bind(_speech_token))

func _hide_speech(token: int) -> void:
	if token == _speech_token:
		_speech_label.visible = false

## Walks through `points` in order, ending in `end_state`.
func follow_route(points: Array[Vector2], end_state: State) -> void:
	_route = points.duplicate()
	_route_end_state = end_state
	waypoints_reached = 0
	state = State.WALKING if not _route.is_empty() else end_state

## Jumps straight to a spot (initial placement, or when the room is built
## while the player is already clocked in at this desk).
func place_at(point: Vector2, new_state: State) -> void:
	_route.clear()
	waypoints_reached = 0
	global_position = point
	state = new_state
	_update_animation(false)

func _physics_process(delta: float) -> void:
	if _route.is_empty():
		velocity = Vector2.ZERO
		_update_animation(false)
		return

	var to_target := _route[0] - global_position
	# Arrive if this step would reach/overshoot the target (see CustomerNPC).
	if to_target.length() <= maxf(ARRIVAL_DISTANCE, SPEED * delta):
		global_position = _route[0]
		_route.pop_front()
		waypoints_reached += 1
		if _route.is_empty():
			state = _route_end_state
			# Face the customers again once back behind the desk.
			if state == State.AT_DESK:
				_facing = "down"
				_facing_flip = false
			route_finished.emit()
		return

	velocity = to_target.normalized() * SPEED
	move_and_slide()
	_update_facing(velocity)
	_update_animation(true)

func _update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	if absf(direction.x) > absf(direction.y):
		_facing = "side"
		_facing_flip = direction.x < 0.0
	else:
		_facing = "down" if direction.y > 0.0 else "up"

func _update_animation(is_moving: bool) -> void:
	var anim_name := ("walk_" if is_moving else "idle_") + _facing
	_sprite.flip_h = _facing_flip
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)
