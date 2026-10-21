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
##
## Calendar (BankCalendar): "Day N" is the career's Nth business day. Day 1
## is the career's start_date (BankCalendar.start_date(), a Monday), and each
## day after it is the next business day, so weekends and bank holidays are
## skipped (BusinessDay.closures_before_next_day() names them for the End of
## Day screen). date_of_day() gives any day's date.

const GAME_MINUTES_PER_SECOND: float = 1.5

const MINUTES_PER_DAY: float = 24.0 * 60.0
## A new career starts on Day 1 at 8:30 AM, half an hour before opening.
const START_DAY: int = 1
const START_MINUTES: float = 8.0 * 60.0 + 30.0

var day: int = START_DAY
## Minutes since midnight, 0 to MINUTES_PER_DAY.
var minutes: float = START_MINUTES
## The date of Day 1 (an epoch day, see BankCalendar), saved with the career.
var start_date: int = BankCalendar.start_date()

## date_of_day()'s last answer: dates are worked out by stepping business
## days from start_date, and the HUD asks every frame.
var _cached_day: int = 0
var _cached_date: int = 0
var _cached_start: int = 0

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
	start_date = BankCalendar.start_date()

## The date (epoch day) of business day `number`: start_date for Day 1, then
## each next business day.
func date_of_day(number: int) -> int:
	if number == _cached_day and start_date == _cached_start:
		return _cached_date
	_cached_day = number
	_cached_start = start_date
	_cached_date = BankCalendar.business_day_date(start_date, number)
	return _cached_date

## Today's date.
func today_date() -> int:
	return date_of_day(day)

## "10:42 AM", for the current time.
func time_text() -> String:
	return format_time(minutes)

## "Wed, Day 3 · 10:42 AM", for the HUD.
func hud_text() -> String:
	return "%s, Day %d · %s" % [BankCalendar.weekday_short(today_date()), day, time_text()]

## "Day 3, Wed 7 Jan, 10:42 AM": the time stamped on records, reports, review
## items, transactions and shift summaries.
func timestamp() -> String:
	return "Day %d, %s, %s" % [day, BankCalendar.short_text(today_date()), time_text()]

## The day number of a timestamp() ("Day 3, Wed 7 Jan, 10:42 AM" -> 3, and
## older saves' "Day 3, 10:42 AM" too), or 0 if it isn't one.
func day_of(stamp: String) -> int:
	if not stamp.begins_with("Day "):
		return 0
	var number := stamp.substr(4).get_slice(",", 0)
	return number.to_int() if number.is_valid_int() else 0

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
	return {"day": day, "minutes": SaveGame.time_for_save(minutes), "start_date": BankCalendar.iso(start_date)}

## A save from before the calendar starts on BankCalendar.start_date().
func load_data(data: Dictionary) -> void:
	start_date = BankCalendar.from_iso(SaveGame.string_of(data, "start_date", ""), BankCalendar.start_date())
	day = maxi(START_DAY, SaveGame.int_of(data, "day", START_DAY))
	minutes = clampf(SaveGame.float_of(data, "minutes", START_MINUTES), 0.0, MINUTES_PER_DAY - 0.001)
