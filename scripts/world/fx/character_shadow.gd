extends Node2D
class_name CharacterShadow

## A soft ground shadow under a character's feet (see CharacterFx). Drawn
## once from two precomputed ellipses, so it costs nothing per frame, and
## sits behind the sprite as the character's first child.

## Where the feet are, relative to the character (frames are 16x24, centred).
const FEET: Vector2 = Vector2(0, 10)
const OUTER_COLOUR: Color = Color(0, 0, 0, 0.16)
const INNER_COLOUR: Color = Color(0, 0, 0, 0.2)

static var _outer: PackedVector2Array = _ellipse(8.0, 3.5)
static var _inner: PackedVector2Array = _ellipse(5.5, 2.3)

static func _ellipse(radius_x: float, radius_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points

func _ready() -> void:
	position = FEET

func _draw() -> void:
	draw_colored_polygon(_outer, OUTER_COLOUR)
	draw_colored_polygon(_inner, INNER_COLOUR)
