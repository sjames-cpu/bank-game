extends Node
class_name UiMotionDriver

## Interface motion (stage 2b): the one shared place that watches the
## interface and gives it small, code-driven motion, without any screen
## knowing. Added to the room's UI layer by teller_room.gd (install()).
##
## - **Panels** (every desk screen, letter, lesson, summary, review, and the
##   pause menu and the slot transition card): a screen is any Control that has
##   a "Backdrop" child, or a CanvasLayer whose "Root" Control has one. When it
##   becomes visible it fades in over FADE_IN_SECONDS and its panels rise
##   SLIDE_PIXELS whole pixels into place; when it is hidden a ghost (a cropped
##   copy of what was on screen) fades out over FADE_OUT_SECONDS. The hint card
##   (track_panel()) fades only: it lives in a container, which owns its place.
## - **Buttons** (any Button added in the room): a brief brightness change on
##   hover, and while pressed the label sits PRESS_PIXELS lower (the pressed
##   style's top margin grows by 1 and its bottom shrinks by 1, so the
##   button's size and clickable area never move).
##
## It never delays anything: content and input are there from the first
## frame, and when a fade ends every node is exactly where it would be without
## motion (the slide is applied as whole-pixel deltas and removed again). It
## runs while the tree is paused (desk screens pause it), keeps one shared
## clock (advance(), also what tests call to step time by hand), allocates
## nothing per frame, and switches itself off (set_process) when nothing moves.
## With Effects Off (EffectsSetting) nothing animates at all: it all happens at
## once.

const FADE_IN_SECONDS: float = 0.15
const FADE_OUT_SECONDS: float = 0.1
## The slide, in whole pixels (the panel starts this far lower, never past the window).
const SLIDE_PIXELS: int = 8
const HOVER_SECONDS: float = 0.08
const HOVER_BRIGHTNESS: float = 1.12
const PRESS_PIXELS: int = 1
const BACKDROP_NAME: String = "Backdrop"
const LAYER_ROOT_NAME: String = "Root"
## Every screen is laid out for this height (the window may show more).
const DESIGN_HEIGHT: float = 648.0

## One watched screen or panel.
class Unit extends RefCounted:
	## The node whose visibility is watched (a Control, or a CanvasLayer).
	var watch: Node
	## The Control faded (its modulate alpha).
	var fade_node: Control
	## The panels that slide; for a screen, its non-Backdrop children.
	var panels: Array[Control] = []
	## A panel unit's panels are fixed; a screen's are found each time.
	var fixed_panels: bool = false
	var shown: bool = false
	var shown_frame: int = 0
	var fading: bool = false
	var t: float = 0.0
	var base_alpha: float = 1.0
	## Whether the screen's root slides (see _can_slide()).
	var slides: bool = false
	## Whole pixels the root is lower than its own place now.
	var applied: int = 0

## What is left of a closed screen, fading out.
class Ghost extends RefCounted:
	var unit: Unit
	var nodes: Array[Control] = []
	var t: float = 0.0
	var start_alpha: float = 1.0

class ButtonState extends RefCounted:
	var button: Button
	var hover: float = 0.0
	var hover_target: float = 0.0
	var overridden: bool = false

## Where the room is: only what is inside it is watched.
var scope: Node

## Returns the Image of what the window last drew (null: no ghosts). Tests
## replace it; the default reads the viewport.
var capture: Callable = _capture_viewport

## Tests step time by hand (advance()) and set this so _process does not.
var manual: bool = false

var units: Array[Unit] = []
var _active: Array[Unit] = []
var _ghosts: Array[Ghost] = []
var _ghost_root: Control
var _by_watch: Dictionary[int, Unit] = {}
var _buttons: Dictionary[int, ButtonState] = {}
var _hovering: Array[ButtonState] = []

## Adds a driver to `parent` (the UI layer) that watches `room` and
## everything in it now or later.
static func install(room: Node, parent: Node) -> UiMotionDriver:
	var driver := UiMotionDriver.new()
	driver.name = "UiMotionDriver"
	driver.scope = room
	parent.add_child(driver)
	driver.watch_scope()
	return driver

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func watch_scope() -> void:
	if scope == null:
		return
	_scan(scope)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

func _scan(node: Node) -> void:
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _on_node_added(node: Node) -> void:
	if not (node is Control or node is CanvasLayer):
		return
	if scope != null and not scope.is_ancestor_of(node):
		return
	_consider(node)

func _consider(node: Node) -> void:
	if node is Button:
		_track_button(node as Button)
	if _by_watch.has(node.get_instance_id()):
		return
	var screen_root: Control = null
	if node is Control and node.get_node_or_null(BACKDROP_NAME) != null:
		screen_root = node as Control
	elif node is CanvasLayer:
		var root := node.get_node_or_null(LAYER_ROOT_NAME) as Control
		if root != null and root.get_node_or_null(BACKDROP_NAME) != null:
			screen_root = root
	if screen_root != null:
		_track_unit(node, screen_root, [] as Array[Control], false)

## Fades `panel` in and out as it is shown and hidden (the hint card), and
## never slides it (it lives in a container, which owns its place).
func track_panel(panel: Control) -> Unit:
	var existing: Unit = _by_watch.get(panel.get_instance_id())
	if existing != null:
		return existing
	return _track_unit(panel, panel, [panel] as Array[Control], true)

func _track_unit(watch: Node, fade_node: Control, panels: Array[Control], fixed: bool) -> Unit:
	var unit := Unit.new()
	unit.watch = watch
	unit.fade_node = fade_node
	unit.panels = panels
	unit.fixed_panels = fixed
	unit.shown = _is_shown(unit)
	unit.shown_frame = Engine.get_process_frames()
	units.append(unit)
	_by_watch[watch.get_instance_id()] = unit
	if watch is CanvasLayer:
		(watch as CanvasLayer).visibility_changed.connect(_on_visibility_changed.bind(unit))
	else:
		(watch as Control).visibility_changed.connect(_on_visibility_changed.bind(unit))
	watch.tree_exiting.connect(_untrack_unit.bind(unit))
	return unit

func _untrack_unit(unit: Unit) -> void:
	_finish_fade(unit)
	_active.erase(unit)
	_free_ghosts_of(unit)
	units.erase(unit)
	if is_instance_valid(unit.watch):
		_by_watch.erase(unit.watch.get_instance_id())
		var callback := _on_visibility_changed.bind(unit)
		if unit.watch is CanvasLayer:
			var layer := unit.watch as CanvasLayer
			if layer.visibility_changed.is_connected(callback):
				layer.visibility_changed.disconnect(callback)
		elif unit.watch is Control:
			var control := unit.watch as Control
			if control.visibility_changed.is_connected(callback):
				control.visibility_changed.disconnect(callback)
	_wake()

static func _is_shown(unit: Unit) -> bool:
	if not is_instance_valid(unit.watch):
		return false
	if unit.watch is CanvasLayer:
		return (unit.watch as CanvasLayer).visible
	return (unit.watch as Control).is_visible_in_tree()

func _on_visibility_changed(unit: Unit) -> void:
	var now := _is_shown(unit)
	if now == unit.shown:
		return
	unit.shown = now
	if now:
		unit.shown_frame = Engine.get_process_frames()
		if EffectsSetting.is_on():
			_begin_show(unit)
	else:
		_on_hidden(unit)

# --- panels -----------------------------------------------------------------

func _panels_of(unit: Unit) -> Array[Control]:
	if unit.fixed_panels:
		return unit.panels
	var found: Array[Control] = []
	for child in unit.fade_node.get_children():
		var control := child as Control
		if control != null and control.name != BACKDROP_NAME and not control.top_level:
			found.append(control)
	return found

func _begin_show(unit: Unit) -> void:
	_free_ghosts_of(unit)
	_finish_fade(unit)
	unit.panels = _panels_of(unit)
	unit.base_alpha = unit.fade_node.modulate.a
	unit.t = 0.0
	unit.fading = true
	unit.applied = 0
	unit.slides = _can_slide(unit)
	if not _active.has(unit):
		_active.append(unit)
	_apply_fade(unit)
	_wake()

## A screen slides by moving its whole root (a full-window Control that no
## layout ever resizes: its panels, which a change of content resizes and
## re-centres, are never touched) and the Backdrop back by the same amount, so
## the dimming still covers the window. A panel inside a container, or a root
## that isn't the full window, only fades.
func _can_slide(unit: Unit) -> bool:
	if unit.fixed_panels:
		return false
	var root := unit.fade_node
	if root.get_parent() is Container:
		return false
	return root.anchor_left == 0.0 and root.anchor_top == 0.0 and root.anchor_right == 1.0 and root.anchor_bottom == 1.0

static func _eased(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

## Where `unit` is at its t: the alpha, and the slide.
func _apply_fade(unit: Unit) -> void:
	var eased := _eased(unit.t)
	unit.fade_node.modulate.a = unit.base_alpha * eased
	if not unit.slides:
		return
	var offset := roundi(SLIDE_PIXELS * (1.0 - eased))
	if offset > 0:
		# Never past the bottom of the window, whatever the panels' size is
		# right now (a panel's place without the slide is its y - applied).
		var window_height := _window_height()
		for panel in unit.panels:
			if is_instance_valid(panel) and panel.visible:
				var bottom := panel.global_position.y - float(unit.applied) + panel.size.y
				offset = mini(offset, maxi(floori(window_height - bottom), 0))
	_set_slide(unit, offset)

func _set_slide(unit: Unit, offset: int) -> void:
	var delta := offset - unit.applied
	if delta == 0:
		return
	unit.applied = offset
	unit.fade_node.position.y += float(delta)
	var backdrop := unit.fade_node.get_node_or_null(BACKDROP_NAME) as Control
	if backdrop != null:
		backdrop.position.y -= float(delta)

## Ends the fade-in where the screen would be without motion: full alpha and
## no slide left.
func _finish_fade(unit: Unit) -> void:
	if not unit.fading:
		return
	unit.fading = false
	if is_instance_valid(unit.fade_node):
		unit.fade_node.modulate.a = unit.base_alpha
		_set_slide(unit, 0)
	unit.applied = 0

func _on_hidden(unit: Unit) -> void:
	var alpha := 1.0
	var rects: Array[Rect2] = []
	var tint := Color.TRANSPARENT
	var backdrop_rect := Rect2()
	if is_instance_valid(unit.fade_node) and EffectsSetting.is_on() and Engine.get_process_frames() > unit.shown_frame:
		for panel in _panels_of(unit):
			if panel.visible:
				rects.append(panel.get_global_rect())
		var backdrop := unit.fade_node.get_node_or_null(BACKDROP_NAME) as ColorRect
		if backdrop != null and backdrop.visible:
			tint = backdrop.color
			backdrop_rect = backdrop.get_global_rect()
		if unit.fading:
			alpha = _eased(unit.t)
	_finish_fade(unit)
	_active.erase(unit)
	if not rects.is_empty() or tint.a > 0.0:
		_spawn_ghost(unit, alpha, rects, tint, backdrop_rect)
	_wake()

func _spawn_ghost(unit: Unit, alpha: float, rects: Array[Rect2], tint: Color, backdrop_rect: Rect2) -> void:
	var ghost := Ghost.new()
	ghost.unit = unit
	ghost.start_alpha = alpha
	var root := _ensure_ghost_root()
	if tint.a > 0.0:
		var dim := ColorRect.new()
		dim.color = tint
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.position = backdrop_rect.position
		dim.size = backdrop_rect.size
		dim.modulate.a = alpha
		root.add_child(dim)
		ghost.nodes.append(dim)
	var result: Variant = capture.call() if capture.is_valid() else null
	var image: Image = result if result is Image else null
	if image != null and not image.is_empty():
		var window := get_viewport().get_visible_rect().size
		var scale := Vector2(float(image.get_width()) / window.x, float(image.get_height()) / window.y)
		for rect in rects:
			var region := Rect2i(Vector2i((rect.position * scale).floor()), Vector2i((rect.size * scale).ceil()))
			region = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			if region.size.x <= 0 or region.size.y <= 0:
				continue
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(image.get_region(region))
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_SCALE
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			picture.position = rect.position
			picture.size = rect.size
			picture.modulate.a = alpha
			root.add_child(picture)
			ghost.nodes.append(picture)
	if ghost.nodes.is_empty():
		return
	_ghosts.append(ghost)

func _ensure_ghost_root() -> Control:
	if not is_instance_valid(_ghost_root):
		_ghost_root = Control.new()
		_ghost_root.name = "Ghosts"
		_ghost_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ghost_root)
	return _ghost_root

func _free_ghost(ghost: Ghost) -> void:
	for node in ghost.nodes:
		if is_instance_valid(node):
			node.free()
	ghost.nodes.clear()
	_ghosts.erase(ghost)

func _free_ghosts_of(unit: Unit) -> void:
	var i := _ghosts.size() - 1
	while i >= 0:
		if _ghosts[i].unit == unit:
			_free_ghost(_ghosts[i])
		i -= 1

## The ghosts and fades in progress (tests).
func ghost_count() -> int:
	return _ghosts.size()

## How many buttons are being watched (tests: freed ones are let go).
func tracked_button_count() -> int:
	return _buttons.size()

## How many ghost nodes are in the tree (tests: none are left behind).
func ghost_node_count() -> int:
	return _ghost_root.get_child_count() if is_instance_valid(_ghost_root) else 0

func is_animating() -> bool:
	return not _active.is_empty() or not _ghosts.is_empty() or not _hovering.is_empty()

func _window_height() -> float:
	var design: float = ProjectSettings.get_setting("display/window/size/viewport_height", DESIGN_HEIGHT)
	return minf(get_viewport().get_visible_rect().size.y, design)

func _capture_viewport() -> Image:
	# A headless run draws nothing to read back.
	if DisplayServer.get_name() == "headless":
		return null
	var texture := get_viewport().get_texture()
	return texture.get_image() if texture != null else null

# --- buttons ----------------------------------------------------------------

func _track_button(button: Button) -> void:
	if _buttons.has(button.get_instance_id()):
		return
	var state := ButtonState.new()
	state.button = button
	_buttons[button.get_instance_id()] = state
	button.mouse_entered.connect(_on_hover.bind(state, true))
	button.mouse_exited.connect(_on_hover.bind(state, false))
	button.button_down.connect(_on_press.bind(state))
	button.button_up.connect(_on_release.bind(state))
	button.visibility_changed.connect(_on_button_visibility.bind(state))
	button.tree_exiting.connect(_untrack_button.bind(state))

func _untrack_button(state: ButtonState) -> void:
	var button := state.button
	_hovering.erase(state)
	_buttons.erase(button.get_instance_id())
	if is_instance_valid(button):
		_clear_hover(state)
		_release_press(state)
		button.mouse_entered.disconnect(_on_hover.bind(state, true))
		button.mouse_exited.disconnect(_on_hover.bind(state, false))
		button.button_down.disconnect(_on_press.bind(state))
		button.button_up.disconnect(_on_release.bind(state))
		button.visibility_changed.disconnect(_on_button_visibility.bind(state))
		button.tree_exiting.disconnect(_untrack_button.bind(state))
	_wake()

func _on_hover(state: ButtonState, inside: bool) -> void:
	if not EffectsSetting.is_on() or state.button.disabled:
		_clear_hover(state)
		return
	state.hover_target = 1.0 if inside else 0.0
	if not _hovering.has(state):
		_hovering.append(state)
	_wake()

func _on_button_visibility(state: ButtonState) -> void:
	if not state.button.is_visible_in_tree():
		_clear_hover(state)
		_release_press(state)

func _clear_hover(state: ButtonState) -> void:
	state.hover = 0.0
	state.hover_target = 0.0
	_hovering.erase(state)
	_apply_hover(state)

static func _apply_hover(state: ButtonState) -> void:
	var level := lerpf(1.0, HOVER_BRIGHTNESS, state.hover)
	state.button.self_modulate = Color(level, level, level, 1.0)

## The label one pixel lower while pressed: the pressed style with its top
## margin one larger and its bottom margin one smaller (same size, same
## clickable area), as a theme override that is removed on release.
func _on_press(state: ButtonState) -> void:
	var button := state.button
	if not EffectsSetting.is_on() or state.overridden or button.toggle_mode:
		return
	if button is CheckBox or button is CheckButton or button.has_theme_stylebox_override(&"pressed"):
		return
	var base := button.get_theme_stylebox(&"pressed")
	if base == null or base.get_margin(SIDE_BOTTOM) < float(PRESS_PIXELS):
		return
	var pressed := base.duplicate() as StyleBox
	pressed.content_margin_top = base.get_margin(SIDE_TOP) + float(PRESS_PIXELS)
	pressed.content_margin_bottom = base.get_margin(SIDE_BOTTOM) - float(PRESS_PIXELS)
	button.add_theme_stylebox_override(&"pressed", pressed)
	state.overridden = true

func _on_release(state: ButtonState) -> void:
	_release_press(state)

func _release_press(state: ButtonState) -> void:
	if state.overridden:
		state.overridden = false
		if is_instance_valid(state.button):
			state.button.remove_theme_stylebox_override(&"pressed")

# --- time -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not manual:
		advance(delta)

## Steps every fade, ghost and hover by `delta` seconds, in one pass (also
## what tests call to step time by hand).
func advance(delta: float) -> void:
	if not EffectsSetting.is_on():
		finish_all()
		return
	var i := _active.size() - 1
	while i >= 0:
		var unit := _active[i]
		if not is_instance_valid(unit.fade_node):
			unit.fading = false
			_active.remove_at(i)
		else:
			unit.t = minf(unit.t + delta / FADE_IN_SECONDS, 1.0)
			_apply_fade(unit)
			if unit.t >= 1.0:
				_finish_fade(unit)
				_active.remove_at(i)
		i -= 1
	i = _ghosts.size() - 1
	while i >= 0:
		var ghost := _ghosts[i]
		ghost.t = minf(ghost.t + delta / FADE_OUT_SECONDS, 1.0)
		if ghost.t >= 1.0:
			_free_ghost(ghost)
		else:
			for node in ghost.nodes:
				node.modulate.a = ghost.start_alpha * (1.0 - ghost.t)
		i -= 1
	i = _hovering.size() - 1
	while i >= 0:
		var state := _hovering[i]
		if not is_instance_valid(state.button):
			_hovering.remove_at(i)
		else:
			state.hover = move_toward(state.hover, state.hover_target, delta / HOVER_SECONDS)
			_apply_hover(state)
			if is_equal_approx(state.hover, state.hover_target):
				state.hover = state.hover_target
				_apply_hover(state)
				_hovering.remove_at(i)
		i -= 1
	_wake()

## Everything at its end state at once (Effects turned Off, the room leaving).
func finish_all() -> void:
	for unit in _active:
		_finish_fade(unit)
	_active.clear()
	var i := _ghosts.size() - 1
	while i >= 0:
		_free_ghost(_ghosts[i])
		i -= 1
	while not _hovering.is_empty():
		_clear_hover(_hovering[_hovering.size() - 1])
	for id in _buttons:
		_release_press(_buttons[id])
	_wake()

func _wake() -> void:
	set_process(is_animating())

func _exit_tree() -> void:
	finish_all()
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
