extends RefCounted
class_name DebugKeys

## The debug keys each role may use in Phase B (ROLE_BOUNDARIES.md), already
## in project.godot's input map so no role edits it: two for the Teller and
## two for the Loan Officer. Nothing uses them yet. A role reads them only in
## debug builds, like F1-F3:
##
##   if OS.is_debug_build() and event.is_action_pressed(DebugKeys.TELLER_1):
##
## Taken already: F1, F2 (read as keys by the room) and F3 (debug_skip_slot).

const TELLER_1: StringName = &"debug_teller_1" # F5
const TELLER_2: StringName = &"debug_teller_2" # F6
const LOAN_1: StringName = &"debug_loan_1" # F9
const LOAN_2: StringName = &"debug_loan_2" # F10

## Each action's key (a Key value).
const RESERVED: Dictionary[StringName, int] = {
	TELLER_1: KEY_F5,
	TELLER_2: KEY_F6,
	LOAN_1: KEY_F9,
	LOAN_2: KEY_F10,
}
