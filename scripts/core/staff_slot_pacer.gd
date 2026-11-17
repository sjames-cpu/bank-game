extends Node
class_name StaffSlotPacer

## Staff work per time slot (decision 2): at each work slot's start, every
## staff teller window lets in at most DaySchedule.work_for(STAFF_TELLER_WINDOW)
## new customers and every staff loan desk at most work_for(STAFF_LOAN_DESK)
## new applicants (NpcCustomerLine.begin_slot(), NpcLoanDeskWorker.begin_slot()),
## whatever role the player has today. Placed in the room by SlotWiring;
## does nothing with slots off, when staff have no cap.
##
## Staff never claim or hold a slot, so they can't keep one from ending:
## only the player's work and events do. Customers and applicants still there
## when a slot ends simply carry over: between slots the game is paused, and
## in the next slot the staff serve them first (they counted toward the slot
## they arrived in). From Closing nobody new comes (the branch isn't open),
## staff finish whoever is there, and End of Day waits for an empty lobby as
## it always has.

## The staff teller windows' lines and the staff loan desks (set by SlotWiring).
var lines: Array[NpcCustomerLine] = []
var workers: Array[NpcLoanDeskWorker] = []

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)

func _on_slot_started(slot: DaySlot) -> void:
	if not DayFlow.slots_enabled or not slot.is_work:
		return
	for line in lines:
		line.begin_slot(DaySchedule.work_for(DaySchedule.WorkRole.STAFF_TELLER_WINDOW))
	for worker in workers:
		worker.begin_slot(DaySchedule.work_for(DaySchedule.WorkRole.STAFF_LOAN_DESK))
