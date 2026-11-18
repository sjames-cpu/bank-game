extends Node2D
class_name CharacterOutline

## A thin dark outline around a character's sprite (see CharacterFx).
##
## Drawn as the sprite's current frame stamped four times, one pixel up,
## down, left and right, tinted dark, behind the sprite itself. Unlike a
## shader this isn't clipped to the 16x24 frame (the art touches its edges)
## and can't pick up the neighbouring frame of the sheet, and it needs no
## new art. It redraws only when the sprite's frame, animation, flip or
## frames change, so a standing crowd costs next to nothing. The impatience
## bubble and name labels are separate nodes and are never outlined; the
## day/night tint multiplies the outline like everything else.

const COLOUR: Color = Color(0.06, 0.04, 0.1, 0.85)
const OFFSETS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

var sprite: AnimatedSprite2D = null

var _frames: SpriteFrames = null
var _animation: StringName = &""
var _frame: int = -1
var _flipped: bool = false

func _process(_delta: float) -> void:
	if sprite == null:
		return
	if sprite.frame != _frame or sprite.animation != _animation or sprite.flip_h != _flipped or sprite.sprite_frames != _frames:
		_frame = sprite.frame
		_animation = sprite.animation
		_flipped = sprite.flip_h
		_frames = sprite.sprite_frames
		queue_redraw()

func _draw() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var size := texture.get_size()
	var origin := sprite.position + sprite.offset
	if sprite.centered:
		origin -= size / 2.0
	# A negative width mirrors the texture, like flip_h.
	var rect := Rect2(origin, size)
	if sprite.flip_h:
		rect = Rect2(origin + Vector2(size.x, 0), Vector2(-size.x, size.y))
	for step in OFFSETS:
		draw_texture_rect(texture, Rect2(rect.position + step, rect.size), false, COLOUR)
