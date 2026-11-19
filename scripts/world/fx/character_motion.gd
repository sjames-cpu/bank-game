extends Node
class_name CharacterMotion

## One character's tiny motion (see CharacterFx, which adds it as a child
## named "Motion"): a breathing step while it stands, a dip when it stops, a
## faster rhythm while staff work. It never moves itself: CharacterMotionDriver
## steps every character in one pass from one shared clock.
##
## Every move is a whole art pixel (0, -1 or +1 straight up and down), so
## the pixel art stays crisp and the 1 px outline stays exactly 1 px. The body
## is the sprite and its outline together: the sprite's position moves and
## the outline follows it, in the same frame. The ground shadow never moves.
## Walking characters don't bob here: the walk animation is their motion.

## Standing still: 1.2 s on the ground, 1.2 s one pixel up, and so on.
const BREATH_STEP_SECONDS: float = 1.2
const BREATH_PERIOD: float = BREATH_STEP_SECONDS * 2.0
## Stopping (or sitting into place): one pixel down, briefly.
const SETTLE_SECONDS: float = 0.1
## Staff serving someone: the same step, faster.
const WORK_STEP_SECONDS: float = 0.25
const WORK_PERIOD: float = WORK_STEP_SECONDS * 2.0
## A character that moved less than this (squared) since the last step is standing.
const MOVE_EPSILON_SQUARED: float = 0.0001
## Spreads the characters' phases along the golden ratio, so the first few
## never line up.
const PHASE_SPREAD: float = 0.6180339887

static var _created: int = 0

var character: Node2D = null
var sprite: AnimatedSprite2D = null
var outline: CharacterOutline = null

## Where in its cycle this character starts, in seconds (different for every
## character, so a crowd never moves in lockstep).
var phase: float = 0.0
## The current move: whole pixels, straight up (negative) or down.
var offset_y: int = 0

var _base: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _was_moving: bool = false
var _settle_left: float = 0.0
var _staff: StaffNPC = null

func _ready() -> void:
	phase = fposmod(float(_created) * PHASE_SPREAD * BREATH_PERIOD, BREATH_PERIOD)
	_created += 1
	_base = sprite.position
	_last_position = character.global_position
	_staff = character as StaffNPC
	CharacterMotionDriver.register(self)

func _exit_tree() -> void:
	CharacterMotionDriver.unregister(self)

## One step: `clock` is the shared time in seconds, `delta` the time since
## the last step. With effects off the character is simply still.
func step(clock: float, delta: float, effects_on: bool) -> void:
	var position_now := character.global_position
	var moving := position_now.distance_squared_to(_last_position) > MOVE_EPSILON_SQUARED
	_last_position = position_now
	if not effects_on:
		stop()
		return
	if moving:
		_was_moving = true
		_settle_left = 0.0
		_move_to(0)
		return
	if _was_moving:
		_was_moving = false
		_settle_left = SETTLE_SECONDS
	if _settle_left > 0.0:
		_settle_left -= delta
		_move_to(1)
		return
	if _staff != null and _staff.is_working():
		_move_to(-1 if fposmod(clock + phase, WORK_PERIOD) >= WORK_STEP_SECONDS else 0)
	else:
		_move_to(-1 if fposmod(clock + phase, BREATH_PERIOD) >= BREATH_STEP_SECONDS else 0)

## The whole thing stops where it stands (effects turned off).
func stop() -> void:
	_was_moving = false
	_settle_left = 0.0
	_move_to(0)

func _move_to(pixels: int) -> void:
	if pixels == offset_y:
		return
	offset_y = pixels
	sprite.position = _base + Vector2(0.0, float(pixels))
	# The outline is stamped from the sprite: tell it now, so it never
	# lags the sprite by a frame.
	outline.refresh()
