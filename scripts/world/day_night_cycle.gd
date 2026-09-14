extends CanvasModulate

## Purely atmospheric day/night tint for the Teller room (Phase 6d) — a
## CanvasModulate tints every CanvasItem in the same canvas (Room,
## Player, desks, CustomerQueue) without touching UI, since UI lives
## under its own CanvasLayer (see teller_room.tscn) and CanvasLayers
## aren't affected by a CanvasModulate in the parent canvas.
##
## No gameplay hook whatsoever — nothing reads _elapsed or the current
## color, and nothing here affects spawn rates, NPC behavior, or
## scoring. Purely a lerp between two colors driven by elapsed time.
##
## process_mode = ALWAYS so the cycle keeps advancing even while a Teller/
## Loan Officer/Branch Manager screen has the tree paused — this is
## environmental atmosphere, not shift state, so it shouldn't visibly
## freeze just because the player opened a desk screen (see Phase 6d
## requirements).

## One full day -> night -> day cycle, in real seconds. 360s (6 minutes)
## keeps the shift noticeable within a normal play session without being
## so fast it feels like flickering.
@export var cycle_duration_seconds: float = 360.0

@export var day_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var night_color: Color = Color(0.35, 0.4, 0.6, 1.0)

var _elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	color = day_color

func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, cycle_duration_seconds)
	color = day_color.lerp(night_color, _day_night_blend())

## 0.0 at the start/end of the cycle (day), smoothly easing up to 1.0 at
## the midpoint (night) and back down — a cosine curve rather than a
## linear ramp so the transition eases in/out instead of changing at a
## constant rate.
func _day_night_blend() -> float:
	var phase := _elapsed / cycle_duration_seconds
	return (1.0 - cos(phase * TAU)) / 2.0
