extends Node2D
class_name UseGlow

## A soft glow around a machine or door while it is in use: the ATM while its
## screen is open, the vault door while a witness walks over, the vault screen
## is open or the armored truck's crew is here (TellerRoom.update_use_glows()).
## Not the gold pulsing outline of InteractableHighlight, which says "E does
## something here": this one is cool and gentle and says "someone is using it".
##
## The glow is the sprite stamped around itself, tinted and fading with the
## distance (one pixel, then two), behind the sprite: whole pixels, so it
## stays crisp. It exists only while wanted: hidden, it doesn't process. It
## pulses slowly from the clock; with effects off (EffectsSetting) it holds a
## steady brightness. It keeps going while the tree is paused, because the
## screen that makes the glow pauses the game.

const COLOUR: Color = Color(0.55, 0.85, 1.0)
## Each ring: how far from the sprite (pixels) and how strong.
const RINGS: Array[Vector2] = [Vector2(1.0, 0.55), Vector2(2.0, 0.25)]
const DIRECTIONS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
const PULSE_PER_SECOND: float = 0.6
const MIN_ALPHA: float = 0.5
const STEADY_ALPHA: float = 0.8

var source: Sprite2D = null
var wanted: bool = false

## Builds one behind `sprite` (a child of it, like InteractableHighlight).
static func attach(sprite: Sprite2D) -> UseGlow:
	var glow := UseGlow.new()
	glow.name = "UseGlow"
	glow.source = sprite
	glow.show_behind_parent = true
	sprite.add_child(glow)
	return glow

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)

func set_wanted(value: bool) -> void:
	if value == wanted:
		return
	wanted = value
	visible = value
	modulate.a = STEADY_ALPHA
	set_process(value)
	if value:
		queue_redraw()

func is_shown() -> bool:
	return wanted

func _process(_delta: float) -> void:
	if not EffectsSetting.is_on():
		modulate.a = STEADY_ALPHA
		return
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * PULSE_PER_SECOND)
	modulate.a = lerpf(MIN_ALPHA, 1.0, wave)

func _draw() -> void:
	if source == null or source.texture == null:
		return
	var size := source.texture.get_size()
	var origin := source.offset
	if source.centered:
		origin -= size / 2.0
	# Outermost first, so the nearer, stronger ring lies over it.
	for i in range(RINGS.size() - 1, -1, -1):
		var ring := RINGS[i]
		var colour := Color(COLOUR.r, COLOUR.g, COLOUR.b, ring.y)
		for direction in DIRECTIONS:
			draw_texture_rect(source.texture, Rect2(origin + direction * ring.x, size), false, colour)
