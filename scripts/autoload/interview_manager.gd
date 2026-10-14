extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager.
## Holds the result of the interview mini-game (2h) so it survives the
## scene change into teller_room. is_on_probation is set here but nothing
## reads it yet; a later system can check it without re-running the
## interview. The interview is only reached after a termination (see
## discipline_letter_screen.gd), not at startup.
##
## Like the other managers, this only lives in memory for now and resets
## if the game is closed.

enum Outcome { HIRED, HIRED_ON_PROBATION, REJECTED }

## Score thresholds out of this question set's 30-point maximum (10
## questions, best answer worth +3 each; see InterviewQuestionsData). HIRE_THRESHOLD asks for mostly
## strong answers; PROBATION_THRESHOLD still requires a net-positive
## showing, just not a strong one.
const HIRE_THRESHOLD: int = 15
const PROBATION_THRESHOLD: int = 5

var is_on_probation: bool = false

## New career after termination — see CareerReset. The next interview sets
## this again via resolve_outcome().
func reset() -> void:
	is_on_probation = false

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
	return outcome
