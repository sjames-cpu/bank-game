extends Node

## Autoload singleton — where this career is in its onboarding (OnboardingData):
## the background check letter, the employment contract, then four compliance
## training lessons, each shown once per career. The room runs it
## (OnboardingFlow) after the hiring interview with the interview switch on,
## or at career start with it off; both lead into the room with a fresh career.
##
## Reset with the career (CareerReset: a new career starts at the background
## check) and saved with it (SaveGame), so quitting mid-onboarding resumes at
## the same step. A save from before onboarding existed has none, and counts
## as done (that career had already started).

## In order; a step's value is saved.
enum Step { BACKGROUND_CHECK, CONTRACT, LESSON_ID, LESSON_DRAWER, LESSON_VAULT, LESSON_PRIVACY, DONE }

signal step_changed(step: Step)
signal completed

## Finishing the training: 50 XP (5 Score points' worth, XPManager's 10 per
## point, no Score), about one correctly served customer, a tenth of the way
## to Loan Officer.
const TRAINING_XP_SCORE_POINTS: int = 5

var step: Step = Step.BACKGROUND_CHECK

func reset() -> void:
	step = Step.BACKGROUND_CHECK

func is_complete() -> bool:
	return step == Step.DONE

func is_lesson(value: Step = step) -> bool:
	return value >= Step.LESSON_ID and value <= Step.LESSON_PRIVACY

## 0-3 for the lesson steps.
func lesson_index(value: Step = step) -> int:
	return value - Step.LESSON_ID

## The current step is done: on to the next. Finishing the last lesson awards
## the training XP.
func advance() -> void:
	if is_complete():
		return
	var finished := step
	step = (step + 1) as Step
	if finished == Step.LESSON_PRIVACY:
		XPManager.add_shift_xp(TRAINING_XP_SCORE_POINTS)
	step_changed.emit(step)
	if is_complete():
		completed.emit()

## Straight to the end, no XP (the debug shortcuts, and tests).
func skip() -> void:
	if is_complete():
		return
	step = Step.DONE
	step_changed.emit(step)
	completed.emit()

func save_data() -> Dictionary:
	return {"step": step}

func load_data(data: Dictionary) -> void:
	var value := SaveGame.int_of(data, "step", Step.DONE)
	step = (value if Step.values().has(value) else Step.DONE) as Step
