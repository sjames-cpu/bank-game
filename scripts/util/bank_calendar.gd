class_name BankCalendar
extends RefCounted

## The bank's calendar (HANDOFF.md design flaw: no weekends, holidays or
## cutoffs). Pure date arithmetic, no wall clock: dates are whole days since
## 1 January 1970 ("epoch days", 0 was a Thursday), converted with Howard
## Hinnant's civil-calendar algorithms.
##
## The branch is open Monday to Friday, except on the Federal Reserve's bank
## holidays (holidays_in()). Their observance follows the Federal Reserve: a
## holiday on a Sunday is observed on the Monday after; one on a Saturday
## isn't moved, so the branch is open the Friday before.
##
## A career's "Day N" is its Nth business day (GameClock.date_of_day()), so
## a weekend or holiday never gets a day number.

## Day 1 of a new career: Monday 5 January 2026, the first Monday of the
## year after New Year's Day, so a career starts on a full working week.
## Its first holiday comes in week three (Birthday of Martin Luther King,
## Jr., Monday 19 January, after Day 10).
const START_YEAR: int = 2026
const START_MONTH: int = 1
const START_DAY_OF_MONTH: int = 5

const WEEKDAY_NAMES: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTH_NAMES: Array[String] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

enum Weekday { SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY }

## Year -> {epoch day: holiday name}, the days the branch is closed for a
## holiday that year.
static var _holiday_cache: Dictionary[int, Dictionary] = {}

static func start_date() -> int:
	return epoch_day(START_YEAR, START_MONTH, START_DAY_OF_MONTH)

# --- conversions ---------------------------------------------------------------

## Days since 1970-01-01 for a date in the proleptic Gregorian calendar.
static func epoch_day(year: int, month: int, day: int) -> int:
	var y := year - 1 if month <= 2 else year
	var era := floori(y / 400.0)
	var yoe := y - era * 400
	var mp := month - 3 if month > 2 else month + 9
	var doy := floori((153 * mp + 2) / 5.0) + day - 1
	var doe := yoe * 365 + floori(yoe / 4.0) - floori(yoe / 100.0) + doy
	return era * 146097 + doe - 719468

## The (year, month, day) of an epoch day.
static func civil(date: int) -> Vector3i:
	var z := date + 719468
	var era := floori(z / 146097.0)
	var doe := z - era * 146097
	var yoe := floori((doe - floori(doe / 1460.0) + floori(doe / 36524.0) - floori(doe / 146096.0)) / 365.0)
	var doy := doe - (365 * yoe + floori(yoe / 4.0) - floori(yoe / 100.0))
	var mp := floori((5 * doy + 2) / 153.0)
	var day := doy - floori((153 * mp + 2) / 5.0) + 1
	var month := mp + 3 if mp < 10 else mp - 9
	var year := yoe + era * 400 + (1 if month <= 2 else 0)
	return Vector3i(year, month, day)

static func weekday(date: int) -> Weekday:
	return posmod(date + 4, 7) as Weekday

## "2026-01-05", for the save.
static func iso(date: int) -> String:
	var c := civil(date)
	return "%04d-%02d-%02d" % [c.x, c.y, c.z]

## The epoch day of an iso() date, or `default` if it isn't one.
static func from_iso(text: String, default: int) -> int:
	var parts := text.split("-")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return default
	var year := parts[0].to_int()
	var month := parts[1].to_int()
	var day := parts[2].to_int()
	var date := epoch_day(year, month, day)
	if civil(date) != Vector3i(year, month, day):
		return default
	return date

# --- text ------------------------------------------------------------------------

## "Mon"
static func weekday_short(date: int) -> String:
	return WEEKDAY_NAMES[weekday(date)].substr(0, 3)

## "Mon 5 Jan", for records and labels.
static func short_text(date: int) -> String:
	var c := civil(date)
	return "%s %d %s" % [weekday_short(date), c.z, MONTH_NAMES[c.y - 1].substr(0, 3)]

## "Monday 5 January 2026", for the End of Day summary.
static func long_text(date: int) -> String:
	var c := civil(date)
	return "%s %d %s %d" % [WEEKDAY_NAMES[weekday(date)], c.z, MONTH_NAMES[c.y - 1], c.x]

# --- business days ------------------------------------------------------------------

static func is_weekend(date: int) -> bool:
	var w := weekday(date)
	return w == Weekday.SATURDAY or w == Weekday.SUNDAY

## The holiday the branch is closed for on `date` ("" if none).
static func holiday_name(date: int) -> String:
	var holidays := holidays_in(civil(date).x)
	var holiday: String = holidays.get(date, "")
	return holiday

static func is_business_day(date: int) -> bool:
	return not is_weekend(date) and holiday_name(date) == ""

## The first business day after `date`.
static func next_business_day(date: int) -> int:
	var next := date + 1
	while not is_business_day(next):
		next += 1
	return next

## The date of a career's business day `number` (Day 1 is `start`, or the
## first business day after it), each day after it the next business day.
static func business_day_date(start: int, number: int) -> int:
	var date := start if is_business_day(start) else next_business_day(start)
	for i in maxi(0, number - 1):
		date = next_business_day(date)
	return date

## The closed days strictly between two dates, each {"date", "holiday"}
## ("holiday" is "" for a plain weekend day).
static func closures_between(from_date: int, to_date: int) -> Array[Dictionary]:
	var closed: Array[Dictionary] = []
	for date in range(from_date + 1, to_date):
		closed.append({"date": date, "holiday": holiday_name(date)})
	return closed

## The Federal Reserve's bank holidays in `year`, on the days the branch
## closes for them: {epoch day: name}. A Sunday holiday moves to Monday
## ("(observed)"); a Saturday one isn't moved, as the Federal Reserve
## Banks are open the Friday before.
static func holidays_in(year: int) -> Dictionary:
	if _holiday_cache.has(year):
		return _holiday_cache[year]
	var dates: Dictionary = {
		"New Year's Day": epoch_day(year, 1, 1),
		"Birthday of Martin Luther King, Jr.": nth_weekday(year, 1, Weekday.MONDAY, 3),
		"Washington's Birthday": nth_weekday(year, 2, Weekday.MONDAY, 3),
		"Memorial Day": last_weekday(year, 5, Weekday.MONDAY),
		"Juneteenth National Independence Day": epoch_day(year, 6, 19),
		"Independence Day": epoch_day(year, 7, 4),
		"Labor Day": nth_weekday(year, 9, Weekday.MONDAY, 1),
		"Columbus Day": nth_weekday(year, 10, Weekday.MONDAY, 2),
		"Veterans Day": epoch_day(year, 11, 11),
		"Thanksgiving Day": nth_weekday(year, 11, Weekday.THURSDAY, 4),
		"Christmas Day": epoch_day(year, 12, 25),
	}
	var closed: Dictionary = {}
	for holiday_name_key: String in dates:
		var date: int = dates[holiday_name_key]
		match weekday(date):
			Weekday.SUNDAY:
				closed[date + 1] = holiday_name_key + " (observed)"
			Weekday.SATURDAY:
				pass
			_:
				closed[date] = holiday_name_key
	_holiday_cache[year] = closed
	return closed

## The `n`th `day` of a month (n from 1).
static func nth_weekday(year: int, month: int, day: Weekday, n: int) -> int:
	var first := epoch_day(year, month, 1)
	return first + posmod(day - weekday(first), 7) + 7 * (n - 1)

static func last_weekday(year: int, month: int, day: Weekday) -> int:
	var next_month_first := epoch_day(year + 1, 1, 1) if month == 12 else epoch_day(year, month + 1, 1)
	var last := next_month_first - 1
	return last - posmod(weekday(last) - day, 7)

## "Weekend — the branch is closed", "Thanksgiving Day — the branch is
## closed", "Weekend and Birthday of Martin Luther King, Jr. — ...": what
## closes it, in date order.
static func closure_title(closures: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for closure in closures:
		var holiday: String = closure["holiday"]
		var part := holiday if holiday != "" else ("Weekend" if parts.is_empty() else "the weekend")
		if not parts.has(part) and not (part == "the weekend" and parts.has("Weekend")):
			parts.append(part)
	return "%s — the branch is closed" % " and ".join(parts)
