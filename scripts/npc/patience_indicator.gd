extends Node2D
class_name PatienceIndicator

## The small speech bubble above a waiting customer (CustomerNPC) that shows
## their patience running out, drawn in pixels so it matches the sprites and
## leaves the sprite's own colours alone. Hidden while they're still content;
## then a white "..." bubble, a yellow "!", and finally a red "!!" just
## before they give up and leave (CustomerNPC.WAIT_ABANDON_SECONDS).
##
## Drawn above everything in the room (z_index in customer_npc.tscn) so a
## customer standing in front can't hide it.

enum Stage { HIDDEN, WAITING, IMPATIENT, LEAVING }

## Share of the customer's patience used up (0-1) at which each stage starts.
const WAITING_FROM: float = 0.4
const IMPATIENT_FROM: float = 0.65
const LEAVING_FROM: float = 0.85

const OUTLINE: Color = Color(0.11, 0.1, 0.1)
const WAITING_FILL: Color = Color(0.94, 0.94, 0.94)
const WAITING_MARK: Color = Color(0.43, 0.43, 0.43)
const IMPATIENT_FILL: Color = Color(0.95, 0.79, 0.3)
const IMPATIENT_MARK: Color = Color(0.11, 0.1, 0.1)
const LEAVING_FILL: Color = Color(0.85, 0.28, 0.23)
const LEAVING_MARK: Color = Color(0.98, 0.98, 0.98)

## Motion (skipped with effects off, EffectsSetting): the bubble pops in when
## it first shows, rising POP_PIXELS in whole-pixel steps over POP_SECONDS,
## and every change of stage gives a brief colour pulse (PULSE_SECONDS)
## instead of snapping.
const POP_PIXELS: int = 2
const POP_SECONDS: float = 0.15
const PULSE_SECONDS: float = 0.25
const PULSE_COLOUR: Color = Color(1.9, 1.9, 1.9, 1.0)

var stage: Stage = Stage.HIDDEN

var _rest_y: float = 0.0
var _age: float = -1.0
var _popping: bool = false
var _pop_pixels: int = 0

func _ready() -> void:
	visible = false
	_rest_y = position.y
	set_process(false)

## Shows the stage for `urgency` (0 = just arrived, 1 = about to leave).
func set_urgency(urgency: float) -> void:
	var new_stage := stage_for(urgency)
	if new_stage == stage:
		return
	var was_hidden := stage == Stage.HIDDEN
	stage = new_stage
	visible = stage != Stage.HIDDEN
	queue_redraw()
	if visible and EffectsSetting.is_on():
		_start_motion(was_hidden)
	else:
		_finish_motion()

## How far below its place the bubble is now, in whole art pixels.
func pop_offset() -> int:
	return _pop_pixels

## Whether a pop or pulse is playing.
func is_animating() -> bool:
	return _age >= 0.0

func _start_motion(pop_in: bool) -> void:
	_age = 0.0
	_popping = pop_in
	_pop_pixels = POP_PIXELS if pop_in else 0
	position.y = _rest_y + float(_pop_pixels)
	modulate = PULSE_COLOUR
	set_process(true)

func _finish_motion() -> void:
	_age = -1.0
	_popping = false
	_pop_pixels = 0
	position.y = _rest_y
	modulate = Color.WHITE
	set_process(false)

func _process(delta: float) -> void:
	if _age < 0.0:
		return
	if not EffectsSetting.is_on():
		_finish_motion()
		return
	_age += delta
	if _age >= maxf(POP_SECONDS if _popping else 0.0, PULSE_SECONDS):
		_finish_motion()
		return
	if _popping:
		var step := POP_SECONDS / float(POP_PIXELS + 1)
		_pop_pixels = maxi(0, POP_PIXELS - int(_age / step)) if _age < POP_SECONDS else 0
		position.y = _rest_y + float(_pop_pixels)
	modulate = Color.WHITE.lerp(PULSE_COLOUR, clampf(1.0 - _age / PULSE_SECONDS, 0.0, 1.0))

static func stage_for(urgency: float) -> Stage:
	if urgency >= LEAVING_FROM:
		return Stage.LEAVING
	if urgency >= IMPATIENT_FROM:
		return Stage.IMPATIENT
	if urgency >= WAITING_FROM:
		return Stage.WAITING
	return Stage.HIDDEN

## An 11x7 bubble with a one-pixel outline and a tail at the bottom left,
## centred on this node; the mark inside depends on the stage.
func _draw() -> void:
	if stage == Stage.HIDDEN:
		return
	var fill := WAITING_FILL
	var mark := WAITING_MARK
	match stage:
		Stage.IMPATIENT:
			fill = IMPATIENT_FILL
			mark = IMPATIENT_MARK
		Stage.LEAVING:
			fill = LEAVING_FILL
			mark = LEAVING_MARK
	_pixels(Rect2i(-5, -4, 11, 7), OUTLINE)
	_pixels(Rect2i(-4, -3, 9, 5), fill)
	_pixels(Rect2i(-3, 3, 2, 1), OUTLINE) # tail
	_pixels(Rect2i(-3, 2, 1, 1), fill)
	match stage:
		Stage.WAITING:
			for x: int in [-3, 0, 3]:
				_pixels(Rect2i(x, 0, 1, 1), mark)
		Stage.IMPATIENT:
			_pixels(Rect2i(0, -2, 1, 2), mark)
			_pixels(Rect2i(0, 1, 1, 1), mark)
		Stage.LEAVING:
			for x: int in [-2, 2]:
				_pixels(Rect2i(x, -2, 1, 2), mark)
				_pixels(Rect2i(x, 1, 1, 1), mark)

func _pixels(rect: Rect2i, color: Color) -> void:
	draw_rect(Rect2(rect), color)
