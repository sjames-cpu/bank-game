extends Node

## Autoload singleton: the branch's business day (part 2 of the game clock,
## see GameClock). Owns the opening hours, the day's running totals for the
## End of Day summary, and moving from one day to the next. Saved with the
## career (save_data()/load_data(), see SaveGame), reset with it.
##
## Hours: the branch opens at OPEN (9:00 AM) and its doors close at CLOSE
## (5:00 PM). Customers arrive only while it's open (CustomerQueue and the
## staff lines check is_open() before each arrival, and the Loan Desk's staff
## decide only then). The player may clock in early, from the 8:30 AM start
## of the day, for the opening count, but not after LAST_CLOCK_IN (4:30 PM).
## Several shifts fit in a day: a shift is about a quarter of it.
##
## The day ends at the End of Day summary (end_of_day_screen.gd), which
## teller_room.gd shows once it's past CLOSE, the player is off shift and
## the lobby is empty, or at once when the player goes home early
## (go_home_early()). "Start Day N+1" calls start_next_day(). GameClock's
## midnight rollover is only a fallback: a day still open at midnight ends
## as soon as the room can show the summary (is_day_over()).

const OPEN_MINUTES: float = 9.0 * 60.0
const CLOSE_MINUTES: float = 17.0 * 60.0
const LAST_CLOCK_IN_MINUTES: float = 16.0 * 60.0 + 30.0

const CLOCK_IN_REFUSED_TEXT: String = "The branch closes at 5:00 PM — too late to start a new shift."
const DOORS_CLOSED_TEXT: String = "Branch closed — no more customers today"

## The day today's totals belong to (the day the summary is for).
var stats_day: int = 1
## Customers served today at the player's window and by staff.
var customers_served_by_player: int = 0
var customers_served_by_staff: int = 0
## Shifts the player completed today (any role).
var shifts_completed: int = 0
## Career Score, Reputation and XP when the day started, for today's changes.
var score_at_start: int = 0
var reputation_at_start: int = 0
var xp_at_start: int = 0

## Registered after GameClock and the Score/Reputation/XP managers, so a run
## that starts straight in the room (no start screen) has today's baseline.
func _ready() -> void:
	reset()

func reset() -> void:
	stats_day = GameClock.day
	_start_totals()

func _start_totals() -> void:
	customers_served_by_player = 0
	customers_served_by_staff = 0
	shifts_completed = 0
	score_at_start = ScoreManager.total_score
	reputation_at_start = ReputationManager.reputation
	xp_at_start = XPManager.total_xp

# --- hours ----------------------------------------------------------------------

## Open for customers: from OPEN until the doors close, on the summary's day.
func is_open() -> bool:
	return not is_day_over() and GameClock.minutes >= OPEN_MINUTES and GameClock.minutes < CLOSE_MINUTES

## The doors have closed for the day: no more customers until tomorrow.
func doors_closed() -> bool:
	return is_day_over() or GameClock.minutes >= CLOSE_MINUTES

## Whether a new shift may start now (any role): not after LAST_CLOCK_IN.
func can_start_shift() -> bool:
	return not is_day_over() and GameClock.minutes <= LAST_CLOCK_IN_MINUTES

## Past closing time on the summary's day, or (the fallback) the clock has
## already rolled past midnight into the next day.
func is_day_over() -> bool:
	return GameClock.day > stats_day or GameClock.minutes >= CLOSE_MINUTES

# --- today's totals ---------------------------------------------------------------

func note_customer_served_by_player() -> void:
	customers_served_by_player += 1

func note_customer_served_by_staff() -> void:
	customers_served_by_staff += 1

func note_shift_completed() -> void:
	shifts_completed += 1

## Today's figures for the End of Day summary.
func summary() -> Dictionary:
	return {
		"day": stats_day,
		"customers_by_player": customers_served_by_player,
		"customers_by_staff": customers_served_by_staff,
		"customers": customers_served_by_player + customers_served_by_staff,
		"shifts": shifts_completed,
		"score": ScoreManager.total_score - score_at_start,
		"reputation": ReputationManager.reputation - reputation_at_start,
		"xp": XPManager.total_xp - xp_at_start,
	}

# --- moving between days --------------------------------------------------------------

## Going home early: the clock skips straight to closing time. Nothing that
## would have happened in the skipped time is simulated.
func go_home_early() -> void:
	if not is_day_over():
		GameClock.minutes = CLOSE_MINUTES

## "Start Day N+1": the morning after the summary's day, at the start of the
## day (8:30 AM), with fresh totals.
func start_next_day() -> void:
	GameClock.day = stats_day + 1
	GameClock.minutes = GameClock.START_MINUTES
	stats_day = GameClock.day
	_start_totals()

# --- save and load -----------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"stats_day": stats_day,
		"customers_served_by_player": customers_served_by_player,
		"customers_served_by_staff": customers_served_by_staff,
		"shifts_completed": shifts_completed,
		"score_at_start": score_at_start,
		"reputation_at_start": reputation_at_start,
		"xp_at_start": xp_at_start,
	}

## Loaded after the other managers and GameClock. A save from before the
## business day existed starts today's totals from the loaded career.
func load_data(data: Dictionary) -> void:
	if data.is_empty():
		reset()
		return
	stats_day = clampi(SaveGame.int_of(data, "stats_day", GameClock.day), 1, GameClock.day)
	customers_served_by_player = maxi(0, SaveGame.int_of(data, "customers_served_by_player", 0))
	customers_served_by_staff = maxi(0, SaveGame.int_of(data, "customers_served_by_staff", 0))
	shifts_completed = maxi(0, SaveGame.int_of(data, "shifts_completed", 0))
	score_at_start = SaveGame.int_of(data, "score_at_start", ScoreManager.total_score)
	reputation_at_start = SaveGame.int_of(data, "reputation_at_start", ReputationManager.reputation)
	xp_at_start = SaveGame.int_of(data, "xp_at_start", XPManager.total_xp)
