extends Node2D
class_name CharacterShadow

## A soft ground shadow under a character's feet (see CharacterFx). Drawn
## once from two precomputed ellipses, so it costs nothing per frame, and
## sits behind the sprite as the character's first child.

## Where the feet are, relative to the character (frames are 16x24, centred).
const FEET: Vector2 = Vector2(0, 10)
const OUTER_COLOUR: Color = Color(0, 0, 0, 0.16)
const INNER_COLOUR: Color = Color(0, 0, 0, 0.2)

## Half the width and height of each ellipse: a small flat oval at the feet,
## never wider than the 16 px frame and never taller than 7 px.
const OUTER_RADIUS: Vector2 = Vector2(8.0, 3.5)
const INNER_RADIUS: Vector2 = Vector2(5.5, 2.3)

static var _outer: PackedVector2Array = _ellipse(OUTER_RADIUS.x, OUTER_RADIUS.y)
static var _inner: PackedVector2Array = _ellipse(INNER_RADIUS.x, INNER_RADIUS.y)

## Every point the shadow draws, in the character's space (what the look
## tests measure).
static func drawn_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _outer:
		points.append(point + FEET)
	for point in _inner:
		points.append(point + FEET)
	return points

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
