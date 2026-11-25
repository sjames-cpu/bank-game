extends "res://tests/support/shared/room_suite.gd"

## Base for suites that work the loan desks (the Loan Officer's role) and
## need none of the teller's helpers. Everything about the room itself is in
## the shared suite (room_suite.gd). The Loan Officer's shared test helpers
## (James's) go here; a helper only one file uses can stay in that file.
##
## Not a test suite itself (no test_ functions) — suites extend it by path.

## The room's LoanSlotAdapter (the Loan Officer's link to the time slots).
func loan_slot_adapter() -> LoanSlotAdapter:
	return room.get_node("LoanSlotAdapter")

## Closings are off in every test unless the test turns them on
## (LoanConfig.closings_enabled is a static variable, so it outlives a test).
func after_test() -> void:
	LoanConfig.closings_enabled = false
	await super()
