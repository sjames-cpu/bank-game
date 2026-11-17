extends RefCounted
class_name DaySchedule

## The business day's time slots and how much work each role does in one
## (TIME_SLOTS_DECISIONS.md). Static config only: DayFlow walks through
## these slots, and the role adapters read their work amounts from here.
##
##   Opening (8:30) -> 9 AM -> 11 AM -> 1 PM -> 3 PM -> Closing (5 PM)
##
## Every role uses the same slot list (decision 17). The 2 PM cutoff
## (BusinessDay.CUTOFF_MINUTES) falls between the 1 PM and 3 PM slots, so
## 3 PM is the first slot after it.

const OPENING: StringName = &"opening"
const SLOT_9AM: StringName = &"slot_9am"
const SLOT_11AM: StringName = &"slot_11am"
const SLOT_1PM: StringName = &"slot_1pm"
const SLOT_3PM: StringName = &"slot_3pm"
const CLOSING: StringName = &"closing"

## The first slot after the 2 PM cutoff: from here on, teller transactions
## post on the next business day.
const FIRST_SLOT_AFTER_CUTOFF: StringName = SLOT_3PM

## Who does a slot's work, for work_for().
enum WorkRole { TELLER, LOAN_OFFICER, STAFF_TELLER_WINDOW, STAFF_LOAN_DESK }

## Work per slot (decisions 2 and 17).
const TELLER_CUSTOMERS_PER_SLOT: int = 2
const LOAN_OFFICER_APPLICATIONS_PER_SLOT: int = 1
const STAFF_TELLER_WINDOW_CUSTOMERS_PER_SLOT: int = 4
const STAFF_LOAN_DESK_DECISIONS_PER_SLOT: int = 2

## The slot the armored truck comes in, holding it on a Branch Manager day
## until received (decision 12; ArmoredTruckSlot).
const ARMORED_TRUCK_SLOT: StringName = SLOT_9AM

## The slot the Regional Manager visits in on a review day, without
## holding it (decision 13; RegionalVisitSlot).
const REGIONAL_VISIT_SLOT: StringName = SLOT_11AM

## Reputation a Branch Manager earns for a clean work slot (decision 14:
## ended with "End this slot", not skipped, and no Reputation lost while it
## ran; ManagerSlotAdapter). Known balance issue, to re-tune after a
## playtest: pressing "End this slot" at once, four times, earns +4 a day.
const CLEAN_SLOT_REPUTATION: int = 1

static var _slots: Array[DaySlot] = []

## Every slot of the day, in order. Built once; don't change the slots.
static func slots() -> Array[DaySlot]:
	if _slots.is_empty():
		_slots = [
			DaySlot.new(OPENING, "Opening", 8, 30, false),
			DaySlot.new(SLOT_9AM, "9 AM", 9, 0, true),
			DaySlot.new(SLOT_11AM, "11 AM", 11, 0, true),
			DaySlot.new(SLOT_1PM, "1 PM", 13, 0, true),
			DaySlot.new(SLOT_3PM, "3 PM", 15, 0, true),
			DaySlot.new(CLOSING, "Closing", 17, 0, false),
		]
	return _slots

static func count() -> int:
	return slots().size()

## The slot at `index` (0 is Opening), or null outside the day.
static func slot_at(index: int) -> DaySlot:
	if index < 0 or index >= count():
		return null
	return slots()[index]

## The index of the slot called `id`, or -1.
static func index_of(id: StringName) -> int:
	for i in count():
		if slots()[i].id == id:
			return i
	return -1

static func first_after_cutoff_index() -> int:
	return index_of(FIRST_SLOT_AFTER_CUTOFF)

## How much work `role` does in one work slot.
static func work_for(role: WorkRole) -> int:
	match role:
		WorkRole.TELLER:
			return TELLER_CUSTOMERS_PER_SLOT
		WorkRole.LOAN_OFFICER:
			return LOAN_OFFICER_APPLICATIONS_PER_SLOT
		WorkRole.STAFF_TELLER_WINDOW:
			return STAFF_TELLER_WINDOW_CUSTOMERS_PER_SLOT
		WorkRole.STAFF_LOAN_DESK:
			return STAFF_LOAN_DESK_DECISIONS_PER_SLOT
	return 0
