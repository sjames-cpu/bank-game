extends Node2D
class_name InteractableHighlight

## The gentle pulsing outline on whatever E would act on right now (see
## TellerRoom.update_highlights()). One per interactable, built once: a
## desk or machine with a sprite gets a bright silhouette outline (its
## sprite stamped one pixel around, behind it); one without (the doormat)
## gets a framed box. It exists only while wanted: hidden, it doesn't
## process at all. It runs while the tree is paused (so it can hide itself
## behind a desk screen) and pulses from the clock, so it allocates nothing
## per frame.

const COLOUR: Color = Color(1.0, 0.86, 0.35, 1.0)
const FILL: Color = Color(1.0, 0.86, 0.35, 0.1)
const OFFSETS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const PULSE_PER_SECOND: float = 0.9
const MIN_ALPHA: float = 0.35

var source: Sprite2D = null
var box: Rect2 = Rect2()

var wanted: bool = false
var in_overview: bool = false

## Builds one on `parent`: around `sprite` (a child or descendant of the
## interactable) when there is one, else around `box` (in parent space).
static func attach(parent: Node2D, sprite: Sprite2D, frame: Rect2) -> InteractableHighlight:
	var highlight := InteractableHighlight.new()
	highlight.name = "Highlight"
	highlight.source = sprite
	highlight.box = frame
	if sprite != null:
		highlight.show_behind_parent = true
		sprite.add_child(highlight)
	else:
		parent.add_child(highlight)
	return highlight

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)

func set_wanted(value: bool) -> void:
	if value == wanted:
		return
	wanted = value
	_refresh()

## The 1x overview hides it (it would only be clutter there).
func set_overview(value: bool) -> void:
	if value == in_overview:
		return
	in_overview = value
	_refresh()

func is_shown() -> bool:
	return wanted and not in_overview

func _refresh() -> void:
	var show_it := is_shown()
	visible = show_it
	set_process(show_it)
	if show_it:
		queue_redraw()

func _process(_delta: float) -> void:
	# Behind a desk screen the room is paused: don't glow through it.
	visible = not get_tree().paused
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * PULSE_PER_SECOND)
	modulate.a = lerpf(MIN_ALPHA, 1.0, wave)

func _draw() -> void:
	if source != null and source.texture != null:
		var size := source.texture.get_size()
		var origin := source.offset
		if source.centered:
			origin -= size / 2.0
		for step in OFFSETS:
			draw_texture_rect(source.texture, Rect2(origin + step, size), false, COLOUR)
	elif box.size != Vector2.ZERO:
		draw_rect(box, FILL, true)
		draw_rect(box, COLOUR, false, 1.0)
