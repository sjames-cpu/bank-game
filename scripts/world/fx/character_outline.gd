extends Node2D
class_name CharacterOutline

## A thin dark outline around a character's sprite (see CharacterFx).
##
## Drawn as the sprite's current frame stamped four times, one art pixel up,
## down, left and right, tinted dark, behind the sprite itself. Unlike a
## shader this isn't clipped to the 16x24 frame (the art touches its edges)
## and can't pick up the neighbouring frame of the sheet, and it needs no
## new art. The impatience bubble and name labels are separate nodes and are
## never outlined; the day/night tint multiplies the outline like everything
## else.
##
## The copies are only ever positive-size rectangles, one pixel from the
## sprite's own rectangle. A mirrored sprite (facing left) is drawn by
## mirroring the whole drawing about the sprite's centre with a transform,
## never with a negative-width rectangle: Godot anchors such a rectangle at
## its left edge, which once threw the dark copy a whole frame to the right
## of the character, a black body-shaped figure beside it.
##
## If the sprite's art can't be found (no frames, no such animation, no
## texture) the outline draws a visible magenta "missing art" box where the
## character should be, never a dark silhouette and never nothing.

const COLOUR: Color = Color(0.06, 0.04, 0.1, 0.85)
const OFFSETS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

## What a character looks like when its art is missing: a magenta box the
## size of a normal frame, with a cross.
const MISSING_SIZE: Vector2 = Vector2(16, 24)
const MISSING_FILL: Color = Color(1.0, 0.0, 0.8, 0.35)
const MISSING_LINE: Color = Color(1.0, 0.0, 0.8, 1.0)

var sprite: AnimatedSprite2D = null

## How many times a redraw has been asked for (what the tests read: Godot
## can't say whether one is queued).
var redraw_requests: int = 0

var _frames: SpriteFrames = null
var _animation: StringName = &""
var _frame: int = -1
var _flipped: bool = false

func _ready() -> void:
	if sprite == null:
		return
	# The sprite says when its frame or animation changes, so the outline
	# redraws in the same frame, not one late.
	sprite.frame_changed.connect(_request_redraw)
	sprite.animation_changed.connect(_request_redraw)
	sprite.sprite_frames_changed.connect(_request_redraw)

func _process(_delta: float) -> void:
	if sprite == null:
		return
	# flip_h has no signal, so it (and everything else) is also checked here.
	if sprite.frame != _frame or sprite.animation != _animation or sprite.flip_h != _flipped or sprite.sprite_frames != _frames:
		_frame = sprite.frame
		_animation = sprite.animation
		_flipped = sprite.flip_h
		_frames = sprite.sprite_frames
		_request_redraw()

func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()

## The sprite's current frame texture, or null when it can't be found.
func frame_texture() -> Texture2D:
	if sprite == null or sprite.sprite_frames == null:
		return null
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return null
	if sprite.frame < 0 or sprite.frame >= sprite.sprite_frames.get_frame_count(sprite.animation):
		return null
	return sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)

## True when the art is missing, and the warning box is what's drawn.
func is_missing() -> bool:
	return sprite != null and frame_texture() == null

## Where the sprite's frame sits, in this node's space.
func sprite_rect() -> Rect2:
	var texture := frame_texture()
	var size := MISSING_SIZE if texture == null else texture.get_size()
	var origin := sprite.position + sprite.offset
	if sprite.centered:
		origin -= size / 2.0
	return Rect2(origin, size)

## The rectangles the four dark copies are drawn into, before any mirroring:
## the sprite's rectangle moved one pixel in each direction. Always positive
## in size.
func copy_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var base := sprite_rect()
	for step in OFFSETS:
		rects.append(Rect2(base.position + step, base.size))
	return rects

## Mirrors the drawing about the sprite's centre when it faces left, else
## does nothing. A mirrored sprite covers the same rectangle as an unmirrored
## one, so this maps the sprite's rectangle onto itself.
func mirror_transform() -> Transform2D:
	if not sprite.flip_h:
		return Transform2D.IDENTITY
	var centre_x := sprite_rect().get_center().x
	return Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(2.0 * centre_x, 0))

## Everything this draws, as rectangles in this node's space with the mirror
## applied: the four copies, or the warning box when the art is missing.
## What the look tests measure.
func drawn_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if sprite == null:
		return rects
	if is_missing():
		rects.append(sprite_rect())
		return rects
	var mirror := mirror_transform()
	for rect in copy_rects():
		rects.append(mirror * rect)
	return rects

func _draw() -> void:
	if sprite == null:
		return
	var texture := frame_texture()
	if texture == null:
		_draw_missing()
		return
	draw_set_transform_matrix(mirror_transform())
	for rect in copy_rects():
		draw_texture_rect(texture, rect, false, COLOUR)

func _draw_missing() -> void:
	var box := sprite_rect()
	draw_rect(box, MISSING_FILL, true)
	draw_rect(box, MISSING_LINE, false, 1.0)
	draw_line(box.position, box.end, MISSING_LINE, 1.0)
	draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), MISSING_LINE, 1.0)
