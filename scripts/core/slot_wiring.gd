extends RefCounted
class_name SlotWiring

## Places the time-slot pieces in the room (teller_room.gd calls install()
## once, when it's ready), so the room itself holds as little slot code as
## possible. Every piece is a no-op with slots off.
##
## - LoanSlotAdapter: the Loan Officer's work slots.

static func install(room: TellerRoom) -> void:
	var loan := LoanSlotAdapter.new()
	loan.name = "LoanSlotAdapter"
	loan.screen = room.loan_officer_screen
	loan.seat = room.player_loan_seat()
	room.add_child(loan)
