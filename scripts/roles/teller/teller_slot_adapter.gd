extends Node
class_name TellerSlotAdapter

## The Teller role's part of the time-slot day: the only place the Teller
## talks to DayFlow (ROLE_BOUNDARIES.md). Placed in the room by
## teller_room.gd; does nothing with slots off.
##
## On a Teller day (PlayerShift.role_today, chosen at Opening by the shift's
## clock-in, ShiftSlotAdapter) each work slot (9 AM, 11 AM, 1 PM, 3 PM) is
## claimed while the player is clocked in at the teller window. The
## player's line then brings DaySchedule.work_for(TELLER) customers, one by
## one (decision 3, CustomerQueue.begin_batch()), and the slot is finished
## once all of them have arrived and left the line: served, refused, gone
## off upset, or given up waiting (decision 1). That's checked only while
## the world runs, so a slot never ends behind an open teller screen.
##
## A skipped slot's work is dropped: no more arrivals, and anyone still
## waiting in the player's line leaves, with no penalty (decision 11).
## Opening and Closing belong to the shift (ShiftSlotAdapter).

## The player's line and the teller's screen (set by teller_room.gd).
var queue: CustomerQueue
var screen: TellerScreen

## Claimed the current work slot, and its work isn't done yet.
var _claimed: bool = false

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_skipped.connect(_on_slot_skipped)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)

## Whether today is a Teller day with the player at the window now.
func is_teller_working() -> bool:
	return PlayerShift.role_today == PlayerShift.Role.TELLER and PlayerShift.on_shift == PlayerShift.Role.TELLER

## Customers this slot brings.
func customers_per_slot() -> int:
	return DaySchedule.work_for(DaySchedule.WorkRole.TELLER)

func _on_slot_started(slot: DaySlot) -> void:
	_claimed = false
	if not DayFlow.slots_enabled or not slot.is_work or not is_teller_working():
		return
	_claimed = DayFlow.claim_work(self)
	if _claimed:
		queue.begin_batch(customers_per_slot())

## Only a slot that was claimed and is now skipped has work to drop (going
## home early skips slots that never started).
func _on_slot_skipped(_slot: DaySlot) -> void:
	if not _claimed:
		return
	_claimed = false
	queue.begin_batch(0)
	queue.clear_lobby()

func _process(_delta: float) -> void:
	if not _claimed or screen.visible:
		return
	if queue.get_customers_left_to_spawn() > 0 or not queue.queue.is_empty():
		return
	_claimed = false
	DayFlow.finish_work(self)
