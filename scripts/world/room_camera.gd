extends Camera2D
class_name RoomCamera

## The player's camera (a child of Player in teller_room.tscn): a close
## FOLLOW_ZOOM view that follows the player smoothly, and an OVERVIEW_ZOOM
## view of the room toggled with the toggle_overview action (Z). The
## overview is the 1x view the room used to have (commit 039762e dropped the
## zoom from 2x to 1x so the whole floor plan showed).
##
## Clamped to the room (set_room_bounds(), from teller_room.gd): the view
## never shows past the walls and sidewalk on an axis where the room is
## bigger than the view. Where the view is bigger than the room (the
## overview is wider than the 768px room), the room is centred on that axis
## instead.
##
## Only the world zooms: the HUD, desk screens and letters are on
## CanvasLayers. World-space text (staff names, speech, farewells) keeps a
## readable size at either zoom through WorldText, refreshed on zoom_changed.

signal zoom_changed(zoom_factor: float)

const FOLLOW_ZOOM: float = 2.0
const OVERVIEW_ZOOM: float = 1.0
const TOGGLE_ACTION: StringName = &"toggle_overview"
const SMOOTHING_SPEED: float = 6.0
## The Z toggle eases between the two zooms over this long (skipped with
## effects off, EffectsSetting: then it jumps at once).
const EASE_SECONDS: float = 0.25

var room_bounds: Rect2 = Rect2()
var is_overview: bool = false

var _easing: bool = false
var _ease_from: float = FOLLOW_ZOOM
var _ease_to: float = FOLLOW_ZOOM
var _ease_age: float = 0.0

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTHING_SPEED
	limit_smoothed = true
	_apply_zoom(FOLLOW_ZOOM)
	set_process(false)
	get_viewport().size_changed.connect(_update_limits)

## The room's extent in world pixels; the view stays inside it.
func set_room_bounds(bounds: Rect2) -> void:
	room_bounds = bounds
	_update_limits()
	reset_smoothing()

func zoom_factor() -> float:
	return zoom.x

## Switches between the follow view and the overview.
func toggle_overview() -> void:
	set_overview(not is_overview)

## `is_overview` changes at once; the zoom follows it (eased with effects on),
## and zoom_changed, which is what hides or shows the highlights and numbers
## for the overview, comes when the zoom has arrived.
func set_overview(overview: bool) -> void:
	is_overview = overview
	var target := OVERVIEW_ZOOM if overview else FOLLOW_ZOOM
	if not EffectsSetting.is_on() or not is_inside_tree():
		_easing = false
		set_process(false)
		_apply_zoom(target)
		return
	if is_equal_approx(zoom.x, target):
		_easing = false
		set_process(false)
		_apply_zoom(target)
		return
	_easing = true
	# The limits are hard while the zoom changes: smoothed ones would let the
	# view glide out past the walls for a few frames as the view grows.
	limit_smoothed = false
	_ease_from = zoom.x
	_ease_to = target
	_ease_age = 0.0
	set_process(true)

## Whether the zoom is on its way between the two views.
func is_easing() -> bool:
	return _easing

## Arrives now (tests, and effects turned off mid-ease).
func finish_ease() -> void:
	if _easing:
		_easing = false
		set_process(false)
		_apply_zoom(_ease_to)
		limit_smoothed = true

func _process(delta: float) -> void:
	if not _easing:
		set_process(false)
		return
	if not EffectsSetting.is_on():
		finish_ease()
		return
	_ease_age += delta
	if _ease_age >= EASE_SECONDS:
		finish_ease()
		return
	# Smoothstep: gentle at both ends. The clamp to the room holds all the
	# way (the limits follow the zoom), and a zoom in between is fine; the
	# text refits once it arrives.
	var share := _ease_age / EASE_SECONDS
	var eased := share * share * (3.0 - 2.0 * share)
	var factor := lerpf(_ease_from, _ease_to, eased)
	zoom = Vector2(factor, factor)
	_update_limits()

## The part of the world on screen (after limits), for tests and the room.
func visible_world_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - size / 2.0, size)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION) and not event.is_echo():
		toggle_overview()
		get_viewport().set_input_as_handled()

func _apply_zoom(factor: float) -> void:
	zoom = Vector2(factor, factor)
	_update_limits()
	WorldText.set_zoom(factor, get_tree() if is_inside_tree() else null)
	zoom_changed.emit(factor)

## Per axis: the room's edges when the view fits inside the room, otherwise
## limits centred on the room so it sits in the middle of the view.
func _update_limits() -> void:
	if room_bounds.size == Vector2.ZERO:
		return
	var view := get_viewport_rect().size / zoom
	var centre := room_bounds.get_center()
	if view.x <= room_bounds.size.x:
		limit_left = floori(room_bounds.position.x)
		limit_right = ceili(room_bounds.end.x)
	else:
		limit_left = floori(centre.x - view.x / 2.0)
		limit_right = ceili(centre.x + view.x / 2.0)
	if view.y <= room_bounds.size.y:
		limit_top = floori(room_bounds.position.y)
		limit_bottom = ceili(room_bounds.end.y)
	else:
		limit_top = floori(centre.y - view.y / 2.0)
		limit_bottom = ceili(centre.y + view.y / 2.0)
