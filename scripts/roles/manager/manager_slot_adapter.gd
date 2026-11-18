extends SlotStatusProvider
class_name ManagerSlotAdapter

## The Branch Manager role's part of the time-slot day: the only place the
## Branch Manager talks to DayFlow (ROLE_BOUNDARIES.md: frozen on this
## adapter until the role is redesigned). Placed in the room by SlotWiring.
##
## On a Branch Manager day (PlayerShift.role_today, chosen at Opening by the
## shift's clock-in) each work slot is claimed while the player is clocked
## in as Branch Manager, and finished when they press "End this slot"
## (decision 7) on the bar at the top of the screen (EndSlotBar). An event
## holding the slot (the armored truck at 9 AM) keeps it going after that,
## until it's done.
##
## A clean slot earns DaySchedule.CLEAN_SLOT_REPUTATION (decision 14): one
## that ended (not skipped) with no Reputation lost while it ran, whatever
## lost it (an unfair staff report, a truck mistake, ...).
## Opening, Closing and the clock-out refusal belong to the shift
## (ShiftSlotAdapter).
##
## Its status (SlotStatusProvider): what "End this slot" is waiting for on the
## HUD, and the clean-slot reward (or why there wasn't one) on the card.

const STATUS_TEXT: String = "Press End this slot when you're ready"
const HELD_STATUS_TEXT: String = "Waiting for the armored truck"
const CLEAN_REPORT_TEXT: String = "+%d Reputation: a clean slot"
const NOT_CLEAN_REPORT_TEXT: String = "No clean-slot bonus: Reputation dropped this slot"

## A clean slot was rewarded.
signal clean_slot_rewarded(slot: DaySlot)

var bar: EndSlotBar

## Claimed the current work slot, and "End this slot" isn't pressed yet.
var _claimed: bool = false
## The work slot this manager is in (null outside one), whether Reputation
## went down during it, and the last Reputation seen.
var _tracking: DaySlot = null
var _lost_reputation: bool = false
var _last_reputation: int = 0
## The last work slot that ended for this manager, and whether it was clean.
var _ended_slot: DaySlot = null
var _ended_clean: bool = false

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_ended.connect(_on_slot_ended)
	DayFlow.slot_skipped.connect(_on_slot_skipped)
	ReputationManager.reputation_changed.connect(_on_reputation_changed)
	bar = EndSlotBar.new()
	bar.name = "EndSlotBar"
	bar.adapter = self
	add_child(bar)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_ended.disconnect(_on_slot_ended)
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)
	ReputationManager.reputation_changed.disconnect(_on_reputation_changed)

## Whether today is a Branch Manager day with the player on shift now.
func is_manager_working() -> bool:
	return PlayerShift.role_today == PlayerShift.Role.BRANCH_MANAGER and PlayerShift.on_shift == PlayerShift.Role.BRANCH_MANAGER

func is_claimed() -> bool:
	return _claimed

## Inside one of this manager's work slots (the bar shows), ended or not.
func in_work_slot() -> bool:
	return _tracking != null and DayFlow.is_running() and not DayFlow.is_between_slots()

## "End this slot" works now: only inside a claimed work slot.
func can_end_slot() -> bool:
	return _claimed and in_work_slot()

## "End this slot": the manager's work in this slot is done. Returns
## whether it did anything.
func end_slot() -> bool:
	if not can_end_slot():
		return false
	_claimed = false
	DayFlow.finish_work(self)
	return true

func _on_slot_started(slot: DaySlot) -> void:
	_claimed = false
	_tracking = null
	if not slot.is_work or not is_manager_working():
		return
	_claimed = DayFlow.claim_work(self)
	if _claimed:
		_tracking = slot
		_lost_reputation = false
		_last_reputation = ReputationManager.reputation

func _on_slot_ended(slot: DaySlot) -> void:
	if _tracking != slot:
		return
	_tracking = null
	_claimed = false
	_ended_slot = slot
	_ended_clean = not _lost_reputation
	if not _lost_reputation:
		ReputationManager.add_reputation(DaySchedule.CLEAN_SLOT_REPUTATION)
		clean_slot_rewarded.emit(slot)

func _on_slot_skipped(slot: DaySlot) -> void:
	if _tracking == slot:
		_tracking = null
		_claimed = false

func _on_reputation_changed(new_reputation: int) -> void:
	if _tracking != null and new_reputation < _last_reputation:
		_lost_reputation = true
	_last_reputation = new_reputation

func status_text() -> String:
	if not in_work_slot():
		return ""
	return STATUS_TEXT if can_end_slot() else HELD_STATUS_TEXT

func slot_report(slot: DaySlot) -> PackedStringArray:
	if slot != _ended_slot:
		return PackedStringArray()
	if _ended_clean:
		return PackedStringArray([CLEAN_REPORT_TEXT % DaySchedule.CLEAN_SLOT_REPUTATION])
	return PackedStringArray([NOT_CLEAN_REPORT_TEXT])
