extends Node
class_name RegionalVisitSlot

## The Regional Manager's visit on the time-slot day (decision 13): on a
## review day they walk in from the entrance when
## DaySchedule.REGIONAL_VISIT_SLOT (11 AM) starts, stand outside the
## Manager's Office, and walk out when it ends or is skipped. They never
## hold the slot. The room's own 10:00-11:30 clock visit is off with slots
## on, and the review itself still runs at End of Day. Placed in the room by
## SlotWiring; does nothing with slots off.

var room: TellerRoom

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_ended.connect(_on_slot_over)
	DayFlow.slot_skipped.connect(_on_slot_over)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_ended.disconnect(_on_slot_over)
	DayFlow.slot_skipped.disconnect(_on_slot_over)

func _on_slot_started(slot: DaySlot) -> void:
	if not DayFlow.slots_enabled or slot.id != DaySchedule.REGIONAL_VISIT_SLOT:
		return
	if RegionalManager.is_review_day() and not room.regional_visit_done_today() and not is_instance_valid(room.regional_visitor):
		room.start_regional_visit()

func _on_slot_over(slot: DaySlot) -> void:
	if DayFlow.slots_enabled and slot.id == DaySchedule.REGIONAL_VISIT_SLOT:
		room.send_regional_visitor_out()
