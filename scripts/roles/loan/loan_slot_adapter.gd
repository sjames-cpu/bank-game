extends Node
class_name LoanSlotAdapter

## The Loan Officer role's part of the time-slot day: the only place the
## Loan role talks to DayFlow (ROLE_BOUNDARIES.md). Placed in the room by
## SlotWiring; does nothing with slots off, when the Loan Desk keeps its
## own LoanOfficerScreen.APPLICATIONS_PER_SHIFT per shift.
##
## With slots on, the loan shift is the whole day (decision 5), and its
## applications come with the slots: at Opening the screen's allowance
## (LoanOfficerScreen.applications_per_shift) is 0; on a Loan Officer day
## (PlayerShift.role_today, chosen at Opening by the shift's clock-in) each
## work slot is claimed while the player is clocked in at Loan Desk 1, and
## brings DaySchedule.work_for(LOAN_OFFICER) more. The room's walk-in, the
## screen's "Review Next Application" and its own clock-out check all follow
## that allowance. The slot is finished once those applications are
## decided (an Approve, Counter-Offer or Reject: closing the review without
## deciding keeps the application pending, and the slot waits). Applicants
## never give up. Checked only while the world runs, so a slot never ends
## behind an open screen.
##
## A skipped slot's work is dropped with no penalty (decision 11): its
## allowance goes, and an applicant at the desk is sent away (their
## application stays first in the pile, for the next slot).
## Opening, Closing and the clock-out refusal belong to the shift
## (ShiftSlotAdapter).

## The Loan Desk's screen and Loan Desk 1's applicant seat (set by SlotWiring).
var screen: LoanOfficerScreen
var seat: LoanDeskSeat

## Claimed the current work slot, and its work isn't done yet.
var _claimed: bool = false

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_skipped.connect(_on_slot_skipped)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)

## Whether today is a Loan Officer day with the player at Loan Desk 1 now.
func is_loan_officer_working() -> bool:
	return PlayerShift.role_today == PlayerShift.Role.LOAN_OFFICER and PlayerShift.on_shift == PlayerShift.Role.LOAN_OFFICER

## Applications one work slot brings.
func applications_per_slot() -> int:
	return DaySchedule.work_for(DaySchedule.WorkRole.LOAN_OFFICER)

func is_claimed() -> bool:
	return _claimed

func _on_slot_started(slot: DaySlot) -> void:
	_claimed = false
	if not DayFlow.slots_enabled:
		return
	if slot.id == DaySchedule.OPENING:
		screen.applications_per_shift = 0
		return
	if not slot.is_work or not is_loan_officer_working():
		return
	_claimed = DayFlow.claim_work(self)
	if _claimed:
		screen.applications_per_shift = screen.applications_reviewed + applications_per_slot()

## Only a slot that was claimed and is now skipped has work to drop (going
## home early skips slots that never started).
func _on_slot_skipped(_slot: DaySlot) -> void:
	if not _claimed:
		return
	_claimed = false
	screen.applications_per_shift = screen.applications_reviewed
	if seat != null:
		seat.send_off(LoanApplicantNPC.SENT_AWAY_LINE)

func _process(_delta: float) -> void:
	if not _claimed or screen.visible:
		return
	if screen.applications_reviewed < screen.applications_per_shift:
		return
	_claimed = false
	DayFlow.finish_work(self)
