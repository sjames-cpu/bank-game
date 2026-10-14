extends CanvasModulate

## Atmospheric tint for the room, driven by the game clock (GameClock): a
## CanvasModulate tints every CanvasItem in the room's canvas (floor,
## furniture, characters) without touching the UI, since the HUD, screens
## and letters live on their own CanvasLayers.
##
## Over a game day: night until dawn, brightening to full daylight by 8 AM,
## bright through business hours, warming through the late afternoon to
## 5 PM, then dimming into the evening and night. The colour comes straight
## from the clock (colour_at()), so it stops when the clock does (a desk
## screen or letter pauses both) and matches a loaded save at once.
##
## No gameplay hook: nothing reads the tint, and it affects no spawning, NPC
## behaviour or scoring.

const NIGHT: Color = Color(0.35, 0.4, 0.6, 1.0)
const DAY: Color = Color(1.0, 1.0, 1.0, 1.0)
const LATE_AFTERNOON: Color = Color(1.0, 0.9, 0.76, 1.0)

## (game minutes since midnight, colour) keyframes, blended linearly
## between: night to 6 AM, day from 8 AM to 3 PM, warmest at 5 PM, night
## again from 7:30 PM.
const KEYFRAMES: Array = [
	[0.0, NIGHT],
	[6.0 * 60.0, NIGHT],
	[8.0 * 60.0, DAY],
	[15.0 * 60.0, DAY],
	[17.0 * 60.0, LATE_AFTERNOON],
	[19.5 * 60.0, NIGHT],
	[24.0 * 60.0, NIGHT],
]

func _ready() -> void:
	color = colour_at(GameClock.minutes)

func _process(_delta: float) -> void:
	color = colour_at(GameClock.minutes)

## The tint at `game_minutes` since midnight.
static func colour_at(game_minutes: float) -> Color:
	var at := clampf(game_minutes, 0.0, GameClock.MINUTES_PER_DAY)
	for i in range(1, KEYFRAMES.size()):
		var after: Array = KEYFRAMES[i]
		var after_minutes: float = after[0]
		if at <= after_minutes:
			var before: Array = KEYFRAMES[i - 1]
			var before_minutes: float = before[0]
			var before_colour: Color = before[1]
			var after_colour: Color = after[1]
			var blend := 0.0 if after_minutes == before_minutes else (at - before_minutes) / (after_minutes - before_minutes)
			return before_colour.lerp(after_colour, blend)
	return NIGHT
