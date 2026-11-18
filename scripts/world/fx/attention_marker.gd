extends Node2D
class_name AttentionMarker

## A small pixel icon floating over a desk or door when something there
## needs the player (a customer waiting, the drawer over its limit, the
## armored truck, an applicant seated, staff reviews waiting). Separate from
## the customers' impatience bubbles. It stays up at the 1x overview, where
## the desk may be off to one side, and is kept 16 screen pixels wide at
## either zoom (set_zoom(), from the room on zoom_changed). Hidden it costs
## nothing; shown it bobs from the clock without allocating.

enum Kind { CUSTOMER, DOLLAR, TRUCK, DOCUMENT, EXCLAMATION }

const GROUP: StringName = &"attention_markers"
const ICON_SCREEN_PIXELS: float = 16.0
const BOB_HEIGHT: float = 1.5
const BOB_PER_SECOND: float = 1.2
const PLATE: Color = Color(0.05, 0.05, 0.12, 0.65)

const ICONS: Dictionary = {
	Kind.CUSTOMER: preload("res://assets/sprites/icon_customer.png"),
	Kind.DOLLAR: preload("res://assets/sprites/icon_dollar.png"),
	Kind.TRUCK: preload("res://assets/sprites/icon_truck.png"),
	Kind.DOCUMENT: preload("res://assets/sprites/icon_document.png"),
	Kind.EXCLAMATION: preload("res://assets/sprites/icon_exclamation.png"),
}

var kind: Kind = Kind.EXCLAMATION
var active: bool = false

var _icon: Sprite2D
var _rest_y: float = 0.0

## Builds one on `parent`, `height` above the parent's origin, showing `icon`.
static func attach(parent: Node2D, icon: Kind, above_y: float) -> AttentionMarker:
	var marker := AttentionMarker.new()
	marker.name = "AttentionMarker"
	marker.kind = icon
	marker.position = Vector2(0, above_y)
	parent.add_child(marker)
	return marker

func _ready() -> void:
	z_index = 5
	_rest_y = position.y
	_icon = Sprite2D.new()
	_icon.texture = ICONS[kind]
	add_child(_icon)
	add_to_group(GROUP)
	set_zoom(WorldText.zoom_factor)
	visible = false
	set_process(false)

func set_kind(icon: Kind) -> void:
	if icon == kind and (_icon == null or _icon.texture == ICONS[kind]):
		return
	kind = icon
	if _icon != null:
		_icon.texture = ICONS[kind]

## Shows or hides it (cheap to call every frame).
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	visible = value
	set_process(value)

func set_zoom(zoom: float) -> void:
	scale = Vector2.ONE * (ICON_SCREEN_PIXELS / (8.0 * zoom))

func _process(_delta: float) -> void:
	if not EffectsSetting.is_on():
		position.y = _rest_y
		return
	position.y = _rest_y + sin(Time.get_ticks_msec() / 1000.0 * TAU * BOB_PER_SECOND) * BOB_HEIGHT

func _draw() -> void:
	draw_rect(Rect2(-5, -5, 10, 10), PLATE, true)
