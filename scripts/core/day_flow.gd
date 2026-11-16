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

## Whether a day is running: from start_day() until day_ended.
var _running: bool = false
## The current slot's index in DaySchedule.slots(), -1 before the first day.
var _index: int = -1
## Who has unfinished work in the current slot.
var _claims: Array = []
## Why the current slot is held (several reasons may hold it at once).
var _holds: Array[StringName] = []
var _skip_requested: bool = false
## True while the flow is moving between slots (emitting its signals), so a
## call from a listener waits instead of moving the flow on inside a signal.
var _driving: bool = false

func reset() -> void:
	_clear_day()

func _clear_day() -> void:
	_running = false
	_index = -1
	_claims.clear()
	_holds.clear()
	_skip_requested = false

# --- the day ----------------------------------------------------------------------

## Starts a day at Opening. Warns if a day is already running.
func start_day() -> bool:
	if _running:
		push_warning("DayFlow.start_day(): a day is already running.")
		return false
	_clear_day()
	_running = true
	_index = 0
	# Called from a listener (say, day_ended), the loop already running
	# carries on into this day.
	var outer := _driving
	_driving = true
	_announce_slot()
	_driving = outer
	if not outer:
		_drive()
	return true

## Starts `claimant`'s work in the current slot; the slot can't end until
## they finish_work(). Any value works as the claimant (a node, a name), as
## long as finish_work() gets the same one.
func claim_work(claimant: Variant) -> bool:
	if not _check_running("claim_work"):
		return false
	if _claims.has(claimant):
		push_warning("DayFlow.claim_work(): %s has already claimed this slot." % str(claimant))
		return false
	_claims.append(claimant)
	return true

## `claimant`'s work in the current slot is done.
func finish_work(claimant: Variant) -> bool:
	if not _check_running("finish_work"):
		return false
	if not _claims.has(claimant):
		push_warning("DayFlow.finish_work(): %s has no claimed work in this slot." % str(claimant))
		return false
	_claims.erase(claimant)
	_drive()
	return true

## Holds the current slot (and the day) where it is until release(reason).
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
	if not _check_running("skip_slot"):
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
	while _running and _holds.is_empty() and (_skip_requested or _claims.is_empty()):
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
		day_ended.emit()
		return
	_index += 1
	_announce_slot()

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
