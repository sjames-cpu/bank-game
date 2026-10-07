extends RefCounted
class_name CareerReset

## Wipes every piece of cross-scene career state held by the autoloads, for
## starting over after a termination (see discipline_letter_screen.gd's
## "Apply for a new job"). Scene-local state (queues, screens, loan
## application pool) needs no reset — it's rebuilt when the interview hands
## off to a fresh teller_room. Any new autoload holding career progress
## should get a reset() and a line here.

static func reset_all() -> void:
	# XP before Reputation: ReputationManager.reset() emits reputation_changed,
	# which re-runs XPManager's unlock checks — against XP already at 0.
	XPManager.reset()
	ScoreManager.reset()
	ReputationManager.reset()
	ReportManager.reset()
	InterviewManager.reset()
	HistoryManager.reset()
	AccountManager.reset()
	ScheduleManager.reset()
