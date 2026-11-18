extends Node
class_name ArmoredTruckSlot

## The armored truck on the time-slot day (decision 12): on a day with cash
## to move, the crew walks in when DaySchedule.ARMORED_TRUCK_SLOT (9 AM)
## starts (ArmoredTruckVisit.arrive_now()), instead of at 10:30 by the clock.
## Placed in the room by SlotWiring.
##
## - Teller or Loan Officer day: the NPC branch manager receives them as
##   they arrive, as before, and nothing waits for them.
## - Branch Manager day: they hold the slot (DayFlow.hold()) until they've
##   been dealt with at the vault door (signed for, or refused), so the slot
##   goes on after "End this slot" until then. They can't be missed by
##   waiting: time doesn't pass inside a slot.
##
## So the day can never stick on them:
## - if nobody at all could witness the vault (no staff at any desk), they
##   leave, missed, graded as today (ArmoredTruckVisit.miss());
## - if the slot is being skipped (the debug key, or an event), they leave
##   at once with no penalty, since it wasn't the player's choice, and the
##   cash comes the next business day (VaultManager.miss_visit()).

const HOLD_REASON: StringName = &"armored_truck"

## The visit and the room (set by SlotWiring).
var visit: ArmoredTruckVisit
var room: TellerRoom

var _holding: bool = false

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)

## The crew is holding the slot now.
func is_holding() -> bool:
	return _holding

func _on_slot_started(slot: DaySlot) -> void:
	_holding = false
	if slot.id != DaySchedule.ARMORED_TRUCK_SLOT:
		return
	if not visit.arrive_now():
		return
	if PlayerShift.role_today == PlayerShift.Role.BRANCH_MANAGER and PlayerShift.on_shift == PlayerShift.Role.BRANCH_MANAGER:
		_holding = DayFlow.hold(HOLD_REASON)

func _process(_delta: float) -> void:
	if not _holding:
		return
	if DayFlow.is_skip_requested():
		VaultManager.miss_visit(GameClock.day)
		visit.leave()
		_release()
		return
	match visit.phase:
		ArmoredTruckVisit.Phase.IDLE, ArmoredTruckVisit.Phase.LEAVING:
			_release()
		ArmoredTruckVisit.Phase.WAITING:
			if room.vault_witness_candidates().is_empty():
				visit.miss()
				_release()

func _release() -> void:
	_holding = false
	DayFlow.release(HOLD_REASON)
