extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager.
## Holds the result of the interview mini-game (2h), the game's opening
## scene and the way back in after a termination (see
## discipline_letter_screen.gd), and the probation that a "Hired on
## Probation" outcome starts.
##
## Probation: while on it, ReportManager fires the player at
## PROBATION_REPORTS_FOR_TERMINATION reports instead of the usual
## REPORTS_FOR_TERMINATION (report_limit()). It ends after
## PROBATION_CLEAN_SHIFTS completed teller shifts with no new report
## (teller_room.gd reports teller clock-in/out here); a report resets the
## count. Ending it emits probation_completed (a letter from the Branch
## Manager). A promotion to Branch Manager ends it too, without a letter:
## managers aren't subject to reports at all.
##
## Probation is saved with the career (save_data()/load_data(), see
## SaveGame); whether a report came this shift isn't (mid-shift state).

## Probation ended after enough clean shifts (not on promotion or reset).
signal probation_completed

enum Outcome { HIRED, HIRED_ON_PROBATION, REJECTED }

## THE INTERVIEW SWITCH. The hiring interview is off for now (it's being
## redesigned); set this to true to bring it back exactly as it was.
## - true: a new game (start_screen.gd) and "Apply for a new job" after a
##   termination (discipline_letter_screen.gd) go through the interview,
##   whose result can start a probation.
## - false: a new game starts straight in the room as a regular hired Teller
##   (hire_without_interview(): no probation), and a termination is game
##   over: the letter's button goes back to the start screen.
## Nothing of the interview is removed: its scene, questions, outcomes and
## probation rules stay as they are, and a saved career on probation keeps
## it.
const INTERVIEW_ENABLED: bool = false

## INTERVIEW_ENABLED as the game reads it. Only tests change it, to cover
## both settings; it isn't career state, so reset() and save_data() leave it
## alone.
var interview_enabled: bool = INTERVIEW_ENABLED

const INTERVIEW_SCENE: String = "res://scenes/ui/interview_screen.tscn"

## Score thresholds out of this question set's 30-point maximum (10
## questions, best answer worth +3 each; see InterviewQuestionsData). HIRE_THRESHOLD asks for mostly
## strong answers; PROBATION_THRESHOLD still requires a net-positive
## showing, just not a strong one.
const HIRE_THRESHOLD: int = 15
const PROBATION_THRESHOLD: int = 5

## Completed teller shifts without a new report that end probation.
const PROBATION_CLEAN_SHIFTS: int = 3
## Reports that end a career while on probation (normally
## ReportManager.REPORTS_FOR_TERMINATION).
const PROBATION_REPORTS_FOR_TERMINATION: int = 2

var is_on_probation: bool = false

## Clean teller shifts completed so far this probation.
var probation_clean_shifts: int = 0

## Set when a report is issued during the current teller shift, so that
## shift doesn't count as clean.
var _reported_this_shift: bool = false

func _ready() -> void:
	# XPManager is registered before InterviewManager in project.godot.
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)

## New career after termination — see CareerReset. The next interview sets
## this again via resolve_outcome().
func reset() -> void:
	is_on_probation = false
	probation_clean_shifts = 0
	_reported_this_shift = false

func save_data() -> Dictionary:
	return {"is_on_probation": is_on_probation, "probation_clean_shifts": probation_clean_shifts}

func load_data(data: Dictionary) -> void:
	is_on_probation = SaveGame.bool_of(data, "is_on_probation", false)
	probation_clean_shifts = clampi(SaveGame.int_of(data, "probation_clean_shifts", 0), 0, PROBATION_CLEAN_SHIFTS - 1) if is_on_probation else 0
	_reported_this_shift = false

## Called once the interview screen has asked every question (or hit an
## instant-reject answer). instant_rejected always wins regardless of
## total_score — see InterviewAnswer.is_instant_reject.
func resolve_outcome(total_score: int, instant_rejected: bool) -> Outcome:
	var outcome: Outcome
	if instant_rejected:
		outcome = Outcome.REJECTED
	elif total_score >= HIRE_THRESHOLD:
		outcome = Outcome.HIRED
	elif total_score >= PROBATION_THRESHOLD:
		outcome = Outcome.HIRED_ON_PROBATION
	else:
		outcome = Outcome.REJECTED

	is_on_probation = outcome == Outcome.HIRED_ON_PROBATION
	probation_clean_shifts = 0
	_reported_this_shift = false
	return outcome

## A new career with the interview off (start_screen.gd): hired as a regular
## Teller, as the interview's plain "Hired" outcome would, so no probation.
func hire_without_interview() -> void:
	is_on_probation = false
	probation_clean_shifts = 0
	_reported_this_shift = false

## How many reports end the career right now (ReportManager).
func report_limit() -> int:
	return PROBATION_REPORTS_FOR_TERMINATION if is_on_probation else ReportManager.REPORTS_FOR_TERMINATION

## The HUD's probation line, or "" when not on probation.
func probation_status_text() -> String:
	if not is_on_probation:
		return ""
	return "Probation — %d of %d clean shifts" % [probation_clean_shifts, PROBATION_CLEAN_SHIFTS]

## A teller shift started (teller_room.gd, off TellerScreen.shift_clocked_in).
func begin_teller_shift() -> void:
	_reported_this_shift = false

## A teller shift ended at clock-out. Counts it if no report came during
## it, and ends probation after PROBATION_CLEAN_SHIFTS of them.
func end_teller_shift() -> void:
	if not is_on_probation:
		return
	if _reported_this_shift:
		_reported_this_shift = false
		return
	probation_clean_shifts += 1
	if probation_clean_shifts >= PROBATION_CLEAN_SHIFTS:
		is_on_probation = false
		probation_clean_shifts = 0
		probation_completed.emit()

## ReportManager calls this for every report it issues: the clean-shift
## count starts over, and the current shift no longer counts.
func note_report() -> void:
	if not is_on_probation:
		return
	probation_clean_shifts = 0
	_reported_this_shift = true

func _on_branch_manager_unlocked() -> void:
	is_on_probation = false
	probation_clean_shifts = 0
