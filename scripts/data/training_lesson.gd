extends Resource
class_name TrainingLesson

## One compliance training lesson (OnboardingData): a few lines of bank
## policy and a short quiz the player must pass.

@export var title: String = ""
@export var text: String = ""
var questions: Array[TrainingQuestion] = []
