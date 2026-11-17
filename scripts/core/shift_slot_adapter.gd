extends SlotStatusProvider
class_name ShiftSlotAdapter

## The shift's part of the time-slot day, for every role (decisions 5 and
## 6): the player clocks in at Opening and out at Closing. Placed in the
## room by teller_room.gd; does nothing with slots off.
##
## - Opening: claimed (a new day, so PlayerShift.role_today is cleared), and
##   finished when the player clocks in at any desk (PlayerShift.clocked_in),
##   which also records today's role. A Major opening count keeps the teller
##   in Opening until a recount, or the supervisor's sign-off, starts the
##   shift: it always does within MAX_OPENING_RECOUNTS, so it never sticks.
## - Closing: claimed while the player is on shift, finished at their
##   clock-out (PlayerShift.clocked_out). End of Day follows.
## - Clocking out before Closing is refused (clock_out_refusal()), at every
##   desk.
##
## The work slots in between belong to each role's own adapter
## (TellerSlotAdapter, LoanSlotAdapter, ManagerSlotAdapter).

## Its status (SlotStatusProvider): the HUD's line at Opening and Closing.
const OPENING_STATUS_TEXT: String = "Clock in at your desk to start the day"
const CLOSING_STATUS_TEXT: String = "Clock out to end the day"
const CLOSED_STATUS_TEXT: String = "End of Day once the branch is empty"

## The clock-out refusal, completing "Can't clock out yet — %s.".
const CLOCK_OUT_REFUSED_TEXT: String = "your shift runs until Closing (5 PM)"

var _claimed_opening: bool = false
var _claimed_closing: bool = false

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_skipped.connect(_on_slot_skipped)
	PlayerShift.clocked_in.connect(_on_clocked_in)
	PlayerShift.clocked_out.connect(_on_clocked_out)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)
	PlayerShift.clocked_in.disconnect(_on_clocked_in)
	PlayerShift.clocked_out.disconnect(_on_clocked_out)

## "" when the player may clock out now; otherwise why not. Static, so every
## desk's clock-out reads the same check (the teller's through
## teller_room._describe_remaining_shift_work(), the Loan Officer's and the
## Branch Manager's in their own screens).
static func clock_out_refusal() -> String:
	if not DayFlow.slots_enabled or not DayFlow.is_running():
		return ""
	if DayFlow.current_slot().id == DaySchedule.CLOSING:
		return ""
	return CLOCK_OUT_REFUSED_TEXT

func _on_slot_started(slot: DaySlot) -> void:
	if not DayFlow.slots_enabled:
		return
	if slot.id == DaySchedule.OPENING:
		PlayerShift.new_day()
		_claimed_closing = false
		if not PlayerShift.is_on_shift():
			_claimed_opening = DayFlow.claim_work(self)
	elif slot.id == DaySchedule.CLOSING and PlayerShift.is_on_shift():
		_claimed_closing = DayFlow.claim_work(self)

## A skipped slot's claim is gone with it (DayFlow drops it).
func _on_slot_skipped(slot: DaySlot) -> void:
	if slot.id == DaySchedule.OPENING:
		_claimed_opening = false
	elif slot.id == DaySchedule.CLOSING:
		_claimed_closing = false

func _on_clocked_in(_role: PlayerShift.Role) -> void:
	if _claimed_opening:
		_claimed_opening = false
		DayFlow.finish_work(self)

func _on_clocked_out(_role: PlayerShift.Role) -> void:
	if _claimed_closing:
		_claimed_closing = false
		DayFlow.finish_work(self)

func status_text() -> String:
	var slot := DayFlow.current_slot()
	if slot == null:
		return ""
	if slot.id == DaySchedule.OPENING and not PlayerShift.is_on_shift():
		return OPENING_STATUS_TEXT
	if slot.id == DaySchedule.CLOSING:
		return CLOSING_STATUS_TEXT if PlayerShift.is_on_shift() else CLOSED_STATUS_TEXT
	return ""
