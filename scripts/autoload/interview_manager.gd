extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager.
## Holds the result of the interview mini-game (2h) so it survives the
## scene change into teller_room, and so later systems (e.g. a Loan
## Officer unlock) can check is_on_probation without re-running the
## interview.
##
## Like the other two managers, this only lives in memory for now and
## resets if the game is closed.

signal interview_completed(outcome: Outcome)

enum Outcome { HIRED, HIRED_ON_PROBATION, REJECTED }

## Score thresholds out of this question set's ~26-point maximum (9
## questions, best answer worth +3 each). HIRE_THRESHOLD asks for mostly
## strong answers; PROBATION_THRESHOLD still requires a net-positive
## showing, just not a strong one.
const HIRE_THRESHOLD: int = 15
const PROBATION_THRESHOLD: int = 5

var has_completed_interview: bool = false
var is_on_probation: bool = false

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

	has_completed_interview = outcome != Outcome.REJECTED
	is_on_probation = outcome == Outcome.HIRED_ON_PROBATION
	interview_completed.emit(outcome)
	return outcome
