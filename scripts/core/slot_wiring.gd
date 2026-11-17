extends RefCounted
class_name SlotWiring

## Places the time-slot pieces in the room (teller_room.gd calls install()
## once, when it's ready), so the room itself holds as little slot code as
## possible. Every piece is a no-op with slots off.
##
## - LoanSlotAdapter: the Loan Officer's work slots.
## - ManagerSlotAdapter: the Branch Manager's work slots and their
##   "End this slot" bar.
## - StaffSlotPacer: staff work per slot.
## - ArmoredTruckSlot: the armored truck at 9 AM.

static func install(room: TellerRoom) -> void:
	var loan := LoanSlotAdapter.new()
	loan.name = "LoanSlotAdapter"
	loan.screen = room.loan_officer_screen
	loan.seat = room.player_loan_seat()
	room.add_child(loan)
	var manager := ManagerSlotAdapter.new()
	manager.name = "ManagerSlotAdapter"
	room.add_child(manager)
	var staff := StaffSlotPacer.new()
	staff.name = "StaffSlotPacer"
	staff.lines = [room.window1_npc_line, room.window2_line, room.window3_line]
	staff.workers = room.loan_desk_workers.duplicate()
	room.add_child(staff)
	var truck := ArmoredTruckSlot.new()
	truck.name = "ArmoredTruckSlot"
	truck.visit = room.armored_visit
	truck.room = room
	room.add_child(truck)
