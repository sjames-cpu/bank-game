extends Node

## Autoload singleton: the player's shift, whatever the role. Every desk's
## clock-in and clock-out is reported here (teller_room.gd connects each
## role screen's own shift_clocked_in/out signals to report_clock_in/out()),
## so shared code like ShiftSlotAdapter listens to one signal with the role
## in it instead of to each role's screen.
##
## Also remembers the role the player chose today (decision 6: no role
## switching mid-day): the first role clocked in at since new_day().
## Mid-day state: never saved, cleared with the career (CareerReset).

enum Role { NONE, TELLER, LOAN_OFFICER, BRANCH_MANAGER }

signal clocked_in(role: Role)
signal clocked_out(role: Role)

## The role the player chose today (NONE until their first clock-in).
var role_today: Role = Role.NONE
## The role the player is clocked in as now (NONE off shift).
var on_shift: Role = Role.NONE

func reset() -> void:
	role_today = Role.NONE
	on_shift = Role.NONE

## A new day: today's role is chosen again at the next clock-in.
func new_day() -> void:
	role_today = Role.NONE

func is_on_shift() -> bool:
	return on_shift != Role.NONE

func report_clock_in(role: Role) -> void:
	on_shift = role
	if role_today == Role.NONE:
		role_today = role
	clocked_in.emit(role)

func report_clock_out(role: Role) -> void:
	if on_shift == role:
		on_shift = Role.NONE
	clocked_out.emit(role)
