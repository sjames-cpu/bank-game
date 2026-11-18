extends SlotStatusProvider
class_name LoanSlotAdapter

## The Loan Officer role's part of the time-slot day: the only place the
## Loan role talks to DayFlow (ROLE_BOUNDARIES.md). Placed in the room by
## SlotWiring.
##
## The loan shift is the whole day (decision 5), and its
## applications come with the slots: at Opening the screen's allowance
## (LoanOfficerScreen.applications_per_shift) is 0; on a Loan Officer day
## (PlayerShift.role_today, chosen at Opening by the shift's clock-in) each
## work slot is claimed while the player is clocked in at Loan Desk 1, and
## brings LoanConfig.APPLICATIONS_PER_SLOT more. The room's walk-in, the
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
##
## Its status (SlotStatusProvider): "Application: 0 / 1" on the HUD while the
## slot runs, and "Applications decided: 1" on the card after it.

const STATUS_TEXT: String = "Application: %d / %d"
const REPORT_TEXT: String = "Applications decided: %d"

## The Loan Desk's screen and Loan Desk 1's applicant seat (set by SlotWiring).
var screen: LoanOfficerScreen
var seat: LoanDeskSeat

## Claimed the current work slot, and its work isn't done yet.
var _claimed: bool = false
## The last work slot this adapter claimed (for the card's report), and
## the applications reviewed when it started.
var _worked_slot: DaySlot = null
var _reviewed_at_start: int = 0

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
	return LoanConfig.APPLICATIONS_PER_SLOT

func is_claimed() -> bool:
	return _claimed

func _on_slot_started(slot: DaySlot) -> void:
	_claimed = false
	if slot.id == DaySchedule.OPENING:
		screen.applications_per_shift = 0
		return
	if not slot.is_work or not is_loan_officer_working():
		return
	_claimed = DayFlow.claim_work(self)
	if _claimed:
		_worked_slot = slot
		_reviewed_at_start = screen.applications_reviewed
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

func status_text() -> String:
	if not _claimed:
		return ""
	return STATUS_TEXT % [screen.applications_reviewed - _reviewed_at_start, applications_per_slot()]

func slot_report(slot: DaySlot) -> PackedStringArray:
	if slot != _worked_slot:
		return PackedStringArray()
	return PackedStringArray([REPORT_TEXT % (screen.applications_reviewed - _reviewed_at_start)])
