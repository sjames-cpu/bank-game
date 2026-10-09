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
const SLOT_TELLER_WINDOW_3: String = "Teller Window 3"
const SLOT_LOAN_DESK: String = "Loan Desk"

## The Player Teller Window, staffed once the player is promoted to Branch
## Manager (see open_teller_window_3()). Not in DESK_SLOTS: it only exists
## after promotion — use get_desk_slots() for the current set.
const TELLER_WINDOW_3_SLOT: Dictionary = {"name": SLOT_TELLER_WINDOW_3, "role": "Teller"}

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

## Set once Teller Window 3 exists (after promotion to Branch Manager).
var is_teller_window_3_open: bool = false

func _ready() -> void:
	schedule = _default_schedule()
	# XPManager is registered before ScheduleManager in project.godot, and
	# connecting here (before any scene) means the slot is already filled
	# when teller_room.gd reacts to the same signal and places its staff.
	XPManager.branch_manager_unlocked.connect(open_teller_window_3)

func get_assigned(slot_name: String) -> StaffMember:
	return schedule.get(slot_name, null)

## Every desk that currently takes staff: DESK_SLOTS, plus Teller Window 3
## after promotion.
func get_desk_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = DESK_SLOTS.duplicate()
	if is_teller_window_3_open:
		slots.insert(2, TELLER_WINDOW_3_SLOT) # after the other teller windows
	return slots

## The player's own window becomes NPC-staffed. Defaults to a roster member
## not working any desk, preferring a Teller (no new roster entry).
func open_teller_window_3() -> void:
	if is_teller_window_3_open:
		return
	is_teller_window_3_open = true
	var member := _first_unassigned("Teller")
	if member == null:
		member = _first_unassigned("")
	if member != null:
		schedule[SLOT_TELLER_WINDOW_3] = member

## New career after termination — see CareerReset. Back to the default
## desk assignment, not an empty branch, and no Teller Window 3.
func reset() -> void:
	is_teller_window_3_open = false
	schedule = _default_schedule()

## First roster member (of `role`, or any role if empty) not at a desk.
func _first_unassigned(role: String) -> StaffMember:
	var assigned_names: Array[String] = []
	for member: StaffMember in schedule.values():
		assigned_names.append(member.staff_name)
	for staff in StaffRosterData.get_staff():
		if (role == "" or staff.role == role) and not assigned_names.has(staff.staff_name):
			return staff
	return null

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
