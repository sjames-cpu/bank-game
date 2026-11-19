extends RefCounted
class_name HudCounter

## One HUD number (Score, Reputation or XP) that counts to a new value over
## COUNT_SECONDS with a brief green flash for a gain or a red one for a
## loss, then settles on the exact value. A change that arrives mid-count
## carries on from what is on screen now (never from the old value) to the
## newest target. With animation off (Effects Off, or the first value shown)
## it is simply the target at once.
##
## Stepped by the HUD's own _process (the HUD always processes, so it counts
## behind an open screen too); no tween and nothing allocated per frame.

const COUNT_SECONDS: float = 0.4
## The flash lasts a little longer than the count, then fades away.
const FLASH_SECONDS: float = 0.6
const GAIN_COLOR: Color = Color(0.55, 1.0, 0.6)
const LOSS_COLOR: Color = Color(1.0, 0.5, 0.5)

## The value this counts to.
var target: int = 0

var _from: float = 0.0
var _shown: float = 0.0
var _elapsed: float = COUNT_SECONDS
var _started: bool = false
var _flash: float = 0.0
var _gain: bool = true

## Counts to `new_target` (at once when `animate` is false or it is the first).
func set_target(new_target: int, animate: bool) -> void:
	if not _started or not animate:
		target = new_target
		_shown = float(new_target)
		_elapsed = COUNT_SECONDS
		_flash = 0.0
		_started = true
		return
	if new_target == target:
		return
	_gain = float(new_target) > _shown
	_from = _shown
	target = new_target
	_elapsed = 0.0
	_flash = FLASH_SECONDS

func step(delta: float) -> void:
	if _elapsed < COUNT_SECONDS:
		_elapsed = minf(_elapsed + delta, COUNT_SECONDS)
		if _elapsed >= COUNT_SECONDS:
			_shown = float(target)
		else:
			var t := _elapsed / COUNT_SECONDS
			_shown = lerpf(_from, float(target), 1.0 - (1.0 - t) * (1.0 - t))
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)

## Everything at its end state at once (Effects turned Off).
func finish() -> void:
	_shown = float(target)
	_elapsed = COUNT_SECONDS
	_flash = 0.0

## What the HUD shows now: the exact target once the count is over.
func value() -> int:
	return target if _elapsed >= COUNT_SECONDS else roundi(_shown)

func is_counting() -> bool:
	return _elapsed < COUNT_SECONDS

func is_flashing() -> bool:
	return _flash > 0.0

## The tint for the label: white, or the flash colour fading back to white.
func tint() -> Color:
	if _flash <= 0.0:
		return Color.WHITE
	return Color.WHITE.lerp(GAIN_COLOR if _gain else LOSS_COLOR, _flash / FLASH_SECONDS)
