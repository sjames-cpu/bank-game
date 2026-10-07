extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/
## XPManager/HistoryManager (see ScoreManager for why an autoload is the
## right fit). Holds which StaffMember works each desk in the branch.
##
## Gets its own autoload rather than living on an existing manager since
## none of them are a natural fit: Score/Reputation/XP are player-progress
## meters, InterviewManager is a one-time outcome, HistoryManager is an
## append-only log. A slot -> staff assignment map is its own distinct
## piece of state, same reasoning each of those got their own autoload.
##
## Slots are the branch's physical desks (DESK_SLOTS). The schedule starts
## from a default assignment (first eligible roster member per slot, see
## _default_schedule()) so the desks are staffed from the first shift;
## staff_scheduling_screen.gd (Branch Manager) can replace it, and
## teller_room.gd places the StaffNPCs from it — and re-places them on
## schedule_confirmed. Like the other managers, this only lives in memory
## and resets if the game is closed.

signal schedule_confirmed(schedule: Dictionary)

const SLOT_TELLER_WINDOW_1: String = "Teller Window 1"
const SLOT_TELLER_WINDOW_2: String = "Teller Window 2"
const SLOT_LOAN_DESK: String = "Loan Desk"

## One slot per staffed desk, with the StaffMember.role that can work it.
## (Previously four abstract "Teller/Loan Officer Shift 1/2" slots; now that
## staff physically sit at desks, the slots are the desks themselves — two
## teller windows and one loan desk.)
const DESK_SLOTS: Array[Dictionary] = [
	{"name": SLOT_TELLER_WINDOW_1, "role": "Teller"},
	{"name": SLOT_TELLER_WINDOW_2, "role": "Teller"},
	{"name": SLOT_LOAN_DESK, "role": "Loan Officer"},
]

## slot name -> StaffMember. Only holds entries for slots that are actually
## assigned — an unassigned slot is simply absent rather than mapped to null.
var schedule: Dictionary = {}

func _ready() -> void:
	schedule = _default_schedule()

func get_assigned(slot_name: String) -> StaffMember:
	return schedule.get(slot_name, null)

## New career after termination — see CareerReset. Back to the default
## desk assignment, not an empty branch.
func reset() -> void:
	schedule = _default_schedule()

func confirm_schedule(new_schedule: Dictionary) -> void:
	schedule = new_schedule
	schedule_confirmed.emit(schedule)

## Fills each desk, in DESK_SLOTS order, with the first roster member of the
## right role who isn't already at another desk.
static func _default_schedule() -> Dictionary:
	var result: Dictionary = {}
	var used: Array[String] = []
	var roster := StaffRosterData.get_staff()
	for slot in DESK_SLOTS:
		for staff in roster:
			if staff.role == slot["role"] and not used.has(staff.staff_name):
				result[slot["name"]] = staff
				used.append(staff.staff_name)
				break
	return result
