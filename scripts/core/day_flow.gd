extends Node

## Autoload singleton: runs the business day as a series of time slots
## (DaySchedule), visual-novel style (TIME_SLOTS_DECISIONS.md). Pure logic:
## no timers and no seconds. A slot ends when its work is done, not when
## time passes.
##
## How a day goes:
## - start_day() begins at Opening and announces it (slot_started).
## - Whoever has work in a slot calls claim_work(claimant) while handling
##   slot_started, and finish_work(claimant) once that work is done.
## - Events can hold(reason) the slot (nothing moves on until every hold is
##   release()d) or skip_slot() it.
## - A slot ends once nobody's work is unfinished and nothing holds it
##   (slot_ended), and the next one starts. Nobody claiming a slot means it
##   ends at once (decision 4).
## - After Closing ends, day_ended fires, once, and the day stops running.
##
## Listeners may call any of these from inside a signal handler: the flow
## waits until each signal has reached every listener before it moves on.
## So a role that claims and finishes its work inside slot_started never
## ends the slot early or twice, and every listener sees the slots in order.
##
## Between slots: with pause_between_slots on (the room turns it on for the
## real game; tests and anything else keep the old instant behaviour), a
## slot that ends doesn't start the next one at once. DayFlow waits "between
## slots" (between_slots(ended_slot, next_slot)) until continue_day(), or
## until go_home_early(), which skips every work slot still ahead
## (slot_skipped for each, never started) and goes to Closing, so the End of
## Day still runs (decision 9). DayFlow knows nothing about how the pause is
## shown (SlotTransitionCard does that).
##
## A skip ends the slot whatever work is still claimed (slot_skipped instead
## of slot_ended; the roles drop that work). If the slot is held, the skip
## waits until the last hold is released.
##
## Roles talk to DayFlow only through these signals and functions
## (ROLE_BOUNDARIES.md). Misuse (finishing work never claimed, releasing an
## unknown hold, calls when no day is running) is a warning, never a crash.

## The temporary switch for the time-slot redesign (Phase A): while it's
## off, the game runs on the continuous clock as before and nothing reads
## DayFlow. The game reads slots_enabled, whose default this is; tests turn
## it on for one test (teller_room_suite.use_slots_setting()). Removed once
## slots are switched on for good (Phase A, session 3).
const SLOTS_ENABLED: bool = false
var slots_enabled: bool = SLOTS_ENABLED

signal slot_started(slot: DaySlot)
signal slot_ended(slot: DaySlot)
signal slot_skipped(slot: DaySlot)
signal day_ended()
## The day is waiting between `ended_slot` and `next_slot` (only with
## pause_between_slots on): continue_day() or go_home_early() moves on.
signal between_slots(ended_slot: DaySlot, next_slot: DaySlot)

## Wait between slots (see the class doc). Off by default and after reset().
var pause_between_slots: bool = false

## With slots on: the day has ended (day_ended fired) and its End of Day is
## due. BusinessDay.is_day_over() reads it, so the room's End of Day check
## (teller_room._check_end_of_day(), every frame the world runs) shows the
## summary, after any review or demotion letters, exactly as at 5 PM on the
## continuous clock. Cleared when a new day starts (start_day(),
## BusinessDay.start_next_day()) and by reset(). Never set with slots off.
var end_of_day_due: bool = false

## Whether a day is running: from start_day() until day_ended.
var _running: bool = false
## The current slot's index in DaySchedule.slots(), -1 before the first day.
var _index: int = -1
## Who has unfinished work in the current slot.
var _claims: Array = []
## Why the current slot is held (several reasons may hold it at once).
var _holds: Array[StringName] = []
var _skip_requested: bool = false
## Waiting between two slots (current_slot() is the one that just ended).
var _between: bool = false
## True while the flow is moving between slots (emitting its signals), so a
## call from a listener waits instead of moving the flow on inside a signal.
var _driving: bool = false

## Saved with the career: whether its day had ended (BusinessDay.is_day_over():
## with slots on DayFlow's own end_of_day_due, with slots off the clock).
## Loaded last (SaveGame.restore()), after the clock and the business day.
## With slots on, an ended day comes back as its End of Day
## (resume_ended_day()); any other starts over from Opening when the room
## starts the day, so a day restarted from a save that had passed Opening
## (an old save made mid-day) starts its day-only counters again
## (BusinessDay.restart_day()). With slots off nothing changes.
func save_data() -> Dictionary:
	return {"day_ended": BusinessDay.is_day_over()}

func load_data(data: Dictionary) -> void:
	if not slots_enabled:
		return
	if SaveGame.day_ended_in(data):
		resume_ended_day()
	elif GameClock.minutes > DaySchedule.slot_at(0).start_minutes():
		BusinessDay.restart_day()

func reset() -> void:
	_clear_day()
	pause_between_slots = false

func _clear_day() -> void:
	_running = false
	_index = -1
	_claims.clear()
	_holds.clear()
	_skip_requested = false
	_between = false
	end_of_day_due = false

# --- the day ----------------------------------------------------------------------

## Starts a day at Opening. Warns if a day is already running.
func start_day() -> bool:
	if _running:
		push_warning("DayFlow.start_day(): a day is already running.")
		return false
	_clear_day()
	_running = true
	_index = 0
	_step(_announce_slot)
	return true

## Between slots: starts the next one.
func continue_day() -> bool:
	if not _check_between("continue_day"):
		return false
	_between = false
	_index += 1
	_step(_announce_slot)
	return true

## Between slots, with at least one work slot still ahead: skips every work
## slot left (slot_skipped for each; they never start) and starts Closing.
func go_home_early() -> bool:
	if not _check_between("go_home_early"):
		return false
	if not can_go_home_early():
		push_warning("DayFlow.go_home_early(): no work slots are left to skip.")
		return false
	_between = false
	_step(_skip_to_closing)
	return true

func _skip_to_closing() -> void:
	var closing := DaySchedule.count() - 1
	for i in range(_index + 1, closing):
		if DaySchedule.slot_at(i).is_work:
			slot_skipped.emit(DaySchedule.slot_at(i))
	_index = closing
	_announce_slot()

## Stopgap (Phase A, until saves know about slots): a career loaded from a
## save made at its End of Day (the clock at 5 PM) has already ended that
## day; this puts DayFlow there, with its End of Day due, instead of
## replaying the day from Opening.
func resume_ended_day() -> void:
	_clear_day()
	_index = DaySchedule.count() - 1
	end_of_day_due = slots_enabled

## Starts `claimant`'s work in the current slot; the slot can't end until
## they finish_work(). Any value works as the claimant (a node, a name), as
## long as finish_work() gets the same one.
func claim_work(claimant: Variant) -> bool:
	if not _check_in_slot("claim_work"):
		return false
	if _claims.has(claimant):
		push_warning("DayFlow.claim_work(): %s has already claimed this slot." % str(claimant))
		return false
	_claims.append(claimant)
	return true

## `claimant`'s work in the current slot is done.
func finish_work(claimant: Variant) -> bool:
	if not _check_in_slot("finish_work"):
		return false
	if not _claims.has(claimant):
		push_warning("DayFlow.finish_work(): %s has no claimed work in this slot." % str(claimant))
		return false
	_claims.erase(claimant)
	_drive()
	return true

## Holds the current slot (and the day) where it is until release(reason).
## Between slots, a hold keeps the next slot from ending once it starts.
func hold(reason: StringName) -> bool:
	if not _check_running("hold"):
		return false
	if _holds.has(reason):
		push_warning("DayFlow.hold(): already held for \"%s\"." % reason)
		return false
	_holds.append(reason)
	return true

func release(reason: StringName) -> bool:
	if not _check_running("release"):
		return false
	if not _holds.has(reason):
		push_warning("DayFlow.release(): nothing is held for \"%s\"." % reason)
		return false
	_holds.erase(reason)
	_drive()
	return true

## Skips the current slot: it ends at once (or once released, if held),
## with slot_skipped instead of slot_ended, dropping any claimed work.
func skip_slot() -> bool:
	if not _check_in_slot("skip_slot"):
		return false
	_skip_requested = true
	_drive()
	return true

# --- what's happening now ------------------------------------------------------------

func is_running() -> bool:
	return _running

## The current slot (Closing once the day has ended), or null before the
## first day starts.
func current_slot() -> DaySlot:
	return DaySchedule.slot_at(_index)

## The current slot's index in DaySchedule.slots(), -1 before the first day.
func current_index() -> int:
	return _index

## From the first slot after the 2 PM cutoff on (DaySchedule).
func is_after_cutoff() -> bool:
	return _index >= DaySchedule.first_after_cutoff_index()

func is_between_slots() -> bool:
	return _between

## The slot that starts next: between slots, the one waiting; otherwise
## the one after the current slot (null after Closing).
func next_slot() -> DaySlot:
	return DaySchedule.slot_at(_index + 1)

## Going home early is allowed now: between slots, with a work slot ahead.
func can_go_home_early() -> bool:
	if not _running or not _between:
		return false
	for i in range(_index + 1, DaySchedule.count()):
		if DaySchedule.slot_at(i).is_work:
			return true
	return false

## A skip of the current slot is waiting for its holds to be released
## (skip_slot()): an event holding the slot can let go now.
func is_skip_requested() -> bool:
	return _running and _skip_requested

func is_held() -> bool:
	return not _holds.is_empty()

## Whether `claimant` has unfinished work in the current slot.
func has_claimed(claimant: Variant) -> bool:
	return _claims.has(claimant)

# --- moving on ----------------------------------------------------------------------

## Moves through every slot that can end now. Re-entrant calls (from a
## listener) return at once; the loop that's already running sees their
## changes once the current signal has reached everyone.
func _drive() -> void:
	if _driving:
		return
	_driving = true
	while _running and not _between and _holds.is_empty() and (_skip_requested or _claims.is_empty()):
		_leave_slot()
	_driving = false

func _leave_slot() -> void:
	var slot := current_slot()
	var skipped := _skip_requested
	_skip_requested = false
	_claims.clear()
	if skipped:
		slot_skipped.emit(slot)
	else:
		slot_ended.emit(slot)
	if not _running:
		return # a listener reset the day
	if _index >= DaySchedule.count() - 1:
		_running = false
		end_of_day_due = slots_enabled
		day_ended.emit()
		return
	if pause_between_slots:
		_between = true
		between_slots.emit(slot, next_slot())
		return
	_index += 1
	_announce_slot()

## Runs `action` (which may emit signals) and then moves the flow on as far
## as it can. Called from a listener while the flow is already moving (say,
## start_day() from day_ended), the loop already running carries on instead.
func _step(action: Callable) -> void:
	var outer := _driving
	_driving = true
	action.call()
	_driving = outer
	if not outer:
		_drive()

## With slots on, the clock shows the slot's start time (GameClock is only
## a display then), set before anyone hears that the slot started.
func _announce_slot() -> void:
	var slot := current_slot()
	if slots_enabled:
		GameClock.minutes = slot.start_minutes()
	slot_started.emit(slot)

func _check_running(action: String) -> bool:
	if _running:
		return true
	push_warning("DayFlow.%s(): no day is running." % action)
	return false

## Inside a running slot (not between two).
func _check_in_slot(action: String) -> bool:
	if not _check_running(action):
		return false
	if _between:
		push_warning("DayFlow.%s(): the day is between slots." % action)
		return false
	return true

func _check_between(action: String) -> bool:
	if not _check_running(action):
		return false
	if not _between:
		push_warning("DayFlow.%s(): only between slots." % action)
		return false
	return true
