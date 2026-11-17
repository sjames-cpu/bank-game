extends RefCounted
class_name SlotWiring

## Places the time-slot pieces in the room (teller_room.gd calls install()
## once, at the end of its _ready()), so the room itself holds as little
## slot code as possible. Every piece is a no-op with slots off. Each is a
## child of the room named after its class, for tests and tools
## (room.get_node("TellerSlotAdapter")).
##
## - Every desk's clock-in and clock-out, reported to PlayerShift with its
##   role: one shared signal for the slot pieces.
## - ShiftSlotAdapter: the shift's Opening and Closing.
## - TellerSlotAdapter: the Teller's work slots.
## - SlotTransitionCard: the card between slots.
## - LoanSlotAdapter: the Loan Officer's work slots.
## - ManagerSlotAdapter: the Branch Manager's work slots and their
##   "End this slot" bar.
## - StaffSlotPacer: staff work per slot.
## - ArmoredTruckSlot: the armored truck at 9 AM.
## - RegionalVisitSlot: the Regional Manager's visit at 11 AM.
##
## Still in the room for now (session 4): starting each day
## (TellerRoom.start_slots_day()), the debug skip key (F3) and the doormat's
## note that going home is on the card.

const SLOT_CARD_SCENE: PackedScene = preload("res://scenes/ui/slot_transition_card.tscn")

static func install(room: TellerRoom) -> void:
	_report_shifts(room)
	var shift := ShiftSlotAdapter.new()
	shift.name = "ShiftSlotAdapter"
	room.add_child(shift)
	var teller := TellerSlotAdapter.new()
	teller.name = "TellerSlotAdapter"
	teller.queue = room.customer_queue
	teller.screen = room.teller_screen
	room.add_child(teller)
	var card: SlotTransitionCard = SLOT_CARD_SCENE.instantiate()
	card.name = "SlotTransitionCard"
	room.add_child(card)
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
	var regional := RegionalVisitSlot.new()
	regional.name = "RegionalVisitSlot"
	regional.room = room
	room.add_child(regional)

## Every desk's clock-in and clock-out, reported to PlayerShift with its role.
static func _report_shifts(room: TellerRoom) -> void:
	room.teller_screen.shift_clocked_in.connect(PlayerShift.report_clock_in.bind(PlayerShift.Role.TELLER))
	room.teller_screen.shift_clocked_out.connect(PlayerShift.report_clock_out.bind(PlayerShift.Role.TELLER))
	room.loan_officer_screen.shift_clocked_in.connect(PlayerShift.report_clock_in.bind(PlayerShift.Role.LOAN_OFFICER))
	room.loan_officer_screen.shift_clocked_out.connect(PlayerShift.report_clock_out.bind(PlayerShift.Role.LOAN_OFFICER))
	room.branch_manager_screen.shift_clocked_in.connect(PlayerShift.report_clock_in.bind(PlayerShift.Role.BRANCH_MANAGER))
	room.branch_manager_screen.shift_clocked_out.connect(PlayerShift.report_clock_out.bind(PlayerShift.Role.BRANCH_MANAGER))
