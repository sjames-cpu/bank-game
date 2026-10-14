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
## schedule_confirmed. Saved with the career (save_data()/load_data(), see
## SaveGame), by staff name.

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

## Names of staff terminated by the Branch Manager (StaffReviewManager) —
## gone from the roster for the rest of the career. Their desk stays
## unassigned until the manager fills it (scheduling or HiringManager).
var dismissed_staff: Array[String] = []

## Staff the Branch Manager hired (HiringManager), on the roster after
## StaffRosterData's starting staff. Cleared with the career.
var hired_staff: Array[StaffMember] = []

## The most staff the branch employs at once (dismissed staff don't count).
const MAX_ROSTER_SIZE: int = 8

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
	dismissed_staff.clear()
	hired_staff.clear()
	schedule = _default_schedule()

## The schedule as slot name -> staff name.
func save_data() -> Dictionary:
	var assignments := {}
	for slot_name: String in schedule:
		var member: StaffMember = schedule[slot_name]
		assignments[slot_name] = member.staff_name
	var hired: Array = []
	for member in hired_staff:
		hired.append(SaveGame.resource_to_dict(member))
	return {
		"schedule": assignments,
		"is_teller_window_3_open": is_teller_window_3_open,
		"dismissed_staff": dismissed_staff.duplicate(),
		"hired_staff": hired,
	}

## Staff are looked up by name in the current roster; a slot or name the
## game doesn't know, a dismissed staff member, or someone already placed at
## another desk is left out (that desk stays unassigned). With no schedule
## in `data` at all, the default one is kept (minus dismissed staff). The
## room isn't loaded yet, so schedule_confirmed isn't emitted: the room
## places staff from the schedule when it's ready. Hired staff load first,
## so the schedule can name them; a hired entry without a name, or reusing
## a roster name, is dropped.
func load_data(data: Dictionary) -> void:
	is_teller_window_3_open = SaveGame.bool_of(data, "is_teller_window_3_open", false)
	dismissed_staff.clear()
	for staff_name in SaveGame.strings_of(SaveGame.array_of(data, "dismissed_staff")):
		if not dismissed_staff.has(staff_name):
			dismissed_staff.append(staff_name)
	hired_staff.clear()
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "hired_staff")):
		var member := StaffMember.new()
		SaveGame.fill_resource(member, entry)
		if member.staff_name != "" and not is_known_staff_name(member.staff_name):
			hired_staff.append(member)
	if not data.get("schedule") is Dictionary:
		for staff_name in dismissed_staff:
			schedule.erase(slot_of(staff_name))
		return
	var slot_names: Array[String] = []
	for slot in get_desk_slots():
		slot_names.append(slot["name"])
	var assignments := SaveGame.dict_of(data, "schedule")
	schedule = {}
	for slot_name in slot_names:
		var staff_name := SaveGame.string_of(assignments, slot_name, "")
		if staff_name == "" or slot_of(staff_name) != "":
			continue
		for member in get_roster():
			if member.staff_name == staff_name:
				schedule[slot_name] = member
				break

## The branch's current staff: StaffRosterData plus anyone hired, minus
## anyone dismissed.
func get_roster() -> Array[StaffMember]:
	var roster: Array[StaffMember] = []
	for member in _all_staff():
		if not dismissed_staff.has(member.staff_name):
			roster.append(member)
	return roster

## Starting staff then hired staff, dismissed or not.
func _all_staff() -> Array[StaffMember]:
	var all_staff := StaffRosterData.get_staff()
	all_staff.append_array(hired_staff)
	return all_staff

## Whether the branch has room for another hire (MAX_ROSTER_SIZE).
func has_room_to_hire() -> bool:
	return get_roster().size() < MAX_ROSTER_SIZE

## Whether `staff_name` is, or ever was, on this career's roster (starting,
## hired or dismissed), so a new hire never reuses a name.
func is_known_staff_name(staff_name: String) -> bool:
	if dismissed_staff.has(staff_name):
		return true
	for member in _all_staff():
		if member.staff_name == staff_name:
			return true
	return false

## Every desk that currently takes staff but has nobody assigned, in desk
## order.
func vacant_slots() -> Array[String]:
	var vacant: Array[String] = []
	for slot in get_desk_slots():
		var slot_name: String = slot["name"]
		if get_assigned(slot_name) == null:
			vacant.append(slot_name)
	return vacant

## The StaffMember.role that works `slot_name` ("" if it isn't a desk).
func role_for_slot(slot_name: String) -> String:
	for slot in get_desk_slots():
		if slot["name"] == slot_name:
			return slot["role"]
	return ""

## A new hire joins the roster at the vacant desk `slot_name`, and the
## schedule is re-announced so teller_room.gd places them and opens the
## desk's line. Refused (false) unless the desk is vacant, the branch has
## room, and the name is new.
func hire_staff(member: StaffMember, slot_name: String) -> bool:
	if not vacant_slots().has(slot_name) or not has_room_to_hire() or is_known_staff_name(member.staff_name):
		return false
	hired_staff.append(member)
	schedule[slot_name] = member
	schedule_confirmed.emit(schedule)
	return true

func is_dismissed(staff_name: String) -> bool:
	return dismissed_staff.has(staff_name)

## The desk `staff_name` is assigned to, or "" if none.
func slot_of(staff_name: String) -> String:
	for slot_name: String in schedule:
		var member: StaffMember = schedule[slot_name]
		if member != null and member.staff_name == staff_name:
			return slot_name
	return ""

## Removes a staff member from the roster and their desk (which becomes
## unassigned), then re-announces the schedule so teller_room.gd removes them
## and closes the desk's line.
func dismiss_staff(staff_name: String) -> void:
	if not dismissed_staff.has(staff_name):
		dismissed_staff.append(staff_name)
	var slot := slot_of(staff_name)
	if slot != "":
		schedule.erase(slot)
	schedule_confirmed.emit(schedule)

## First roster member (of `role`, or any role if empty) not at a desk.
func _first_unassigned(role: String) -> StaffMember:
	var assigned_names: Array[String] = []
	for member: StaffMember in schedule.values():
		assigned_names.append(member.staff_name)
	for staff in get_roster():
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
