extends Node

## Autoload singleton: the bank's game clock (HANDOFF.md design flaw: shifts
## and records used the wall clock, with no business day). Holds the day
## number and the time of day in game minutes, saved with the career
## (save_data()/load_data(), see SaveGame) and reset with it (CareerReset).
##
## Time runs only while the world does: this node pauses with the tree, so
## the clock stops whenever a desk screen or letter is open, the same as NPC
## work and customer patience. It also follows Engine.time_scale, like them.
##
## Speed (GAME_MINUTES_PER_SECOND): a teller shift brings a customer every
## 20 s of running time (CustomerQueue.spawn_interval) and the tree is
## paused while each one is served at the desk, so a 4-customer shift is
## about 80 s of arrivals plus walking: roughly 90 s of running time. At 1.5
## game minutes per second that's about 2 hours 15 minutes, a quarter of
## the 9 AM-5 PM business day, so four shifts fill a day. A whole 24-hour
## day takes 16 real minutes of unpaused play.
##
## Opening hours and the end of the day belong to BusinessDay: every day
## ends at its End of Day summary, whose "Start Day N+1" sets the clock to
## 8:30 AM the next morning. Rolling past midnight on its own (advance())
## is only a fallback for a day left running; BusinessDay still ends that
## day at its summary.

const GAME_MINUTES_PER_SECOND: float = 1.5

const MINUTES_PER_DAY: float = 24.0 * 60.0
## A new career starts on Day 1 at 8:30 AM, half an hour before opening.
const START_DAY: int = 1
const START_MINUTES: float = 8.0 * 60.0 + 30.0

var day: int = START_DAY
## Minutes since midnight, 0 to MINUTES_PER_DAY.
var minutes: float = START_MINUTES

func _process(delta: float) -> void:
	advance(delta * GAME_MINUTES_PER_SECOND)

## Moves the clock on by `game_minutes`, rolling into the next day at
## midnight.
func advance(game_minutes: float) -> void:
	minutes += maxf(0.0, game_minutes)
	while minutes >= MINUTES_PER_DAY:
		minutes -= MINUTES_PER_DAY
		day += 1

func reset() -> void:
	day = START_DAY
	minutes = START_MINUTES

## "10:42 AM", for the current time.
func time_text() -> String:
	return format_time(minutes)

## "Day 3 · 10:42 AM", for the HUD.
func hud_text() -> String:
	return "Day %d · %s" % [day, time_text()]

## "Day 3, 10:42 AM": the time stamped on records, reports, review items and
## shift summaries.
func timestamp() -> String:
	return "Day %d, %s" % [day, time_text()]

## `game_minutes` since midnight as a 12-hour time, whole minutes.
func format_time(game_minutes: float) -> String:
	var whole := floori(game_minutes) % int(MINUTES_PER_DAY)
	var hour := floori(whole / 60.0)
	var minute := whole % 60
	var suffix := "AM" if hour < 12 else "PM"
	var hour_12 := hour % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute, suffix]

func save_data() -> Dictionary:
	return {"day": day, "minutes": minutes}

func load_data(data: Dictionary) -> void:
	day = maxi(START_DAY, SaveGame.int_of(data, "day", START_DAY))
	minutes = clampf(SaveGame.float_of(data, "minutes", START_MINUTES), 0.0, MINUTES_PER_DAY - 0.001)
