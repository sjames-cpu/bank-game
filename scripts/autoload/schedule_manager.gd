extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/
## XPManager/HistoryManager (see ScoreManager for why an autoload is the
## right fit). Holds the confirmed shift-slot -> StaffMember schedule set
## by staff_scheduling_screen.gd (Phase 5c).
##
## Gets its own autoload rather than living on an existing manager since
## none of them are a natural fit: Score/Reputation/XP are player-progress
## meters, InterviewManager is a one-time outcome, HistoryManager is an
## append-only log. A slot -> staff assignment map is its own distinct
## piece of state, same reasoning each of those got their own autoload.
##
## Nothing reads this yet — how a confirmed schedule affects the
## Approvals workflow / Branch Manager shift loop is a later step. Like
## the other managers, this only lives in memory and resets if the game
## is closed.

signal schedule_confirmed(schedule: Dictionary)

## slot name (String, e.g. "Teller Shift 1") -> StaffMember. Only holds
## entries for slots that were actually assigned — an unassigned slot is
## simply absent rather than mapped to null.
var schedule: Dictionary = {}

func confirm_schedule(new_schedule: Dictionary) -> void:
	schedule = new_schedule
	schedule_confirmed.emit(schedule)
