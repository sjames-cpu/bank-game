extends Resource
class_name TrainingQuestion

## One multiple-choice question in a compliance training lesson
## (OnboardingData). Built in code, like the other data resources.

@export var question: String = ""
@export var answers: PackedStringArray = []
## Index into answers of the right one.
@export var correct: int = 0
## Shown when it's answered wrongly: why the right answer is right.
@export var explanation: String = ""

func is_correct(answer: int) -> bool:
	return answer == correct
