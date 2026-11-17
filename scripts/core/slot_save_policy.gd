extends RefCounted
class_name SlotSavePolicy

## When a career may be saved with time slots on (decision 8: only at the
## end of a day and at its start). A save is a snapshot the game can resume
## from: an ended day loads into its End of Day again, any other day starts
## over from Opening (decision 10). So a save mid-day would keep that day's
## progress while the day replays, and earn it twice.
##
## Allowed:
## - with slots off, always (saving works as before);
## - with no day running yet (a new career, before the room starts its day);
## - once the day has ended (End of Day: its summary, letters, a demotion,
##   a promotion earned there; BusinessDay.is_day_over());
## - at Opening, before any work (Start Day N+1, onboarding's steps, the
##   Branch Manager's one-time orientation letter at the clock-in).
## Not allowed: inside or between the work slots and at Closing before the
## day ends (the clock-out, a promotion granted at it, Back to Main Menu).
## teller_room.save_career() and so everything saving through it reads
## this.

static func may_save() -> bool:
	if not DayFlow.slots_enabled:
		return true
	if BusinessDay.is_day_over() or not DayFlow.is_running():
		return true
	return DayFlow.current_slot().id == DaySchedule.OPENING
