extends Resource
class_name InterviewAnswer

## One answer choice for an InterviewQuestion. score can be positive,
## negative, or zero and feeds into the interview's running total;
## is_instant_reject overrides that scoring entirely — see
## InterviewManager.resolve_outcome() for how the two combine into a
## final outcome.

@export var text: String = ""
@export var score: int = 0
@export var is_instant_reject: bool = false
