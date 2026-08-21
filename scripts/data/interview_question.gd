extends Resource
class_name InterviewQuestion

## A single interview question plus its 2-4 answer choices. Built in
## code (see interview_questions_data.gd) the same way Account and
## ShiftTransaction are constructed in code rather than loaded from
## .tres files — there's no save/load need for this data yet.

@export var question_text: String = ""
@export var answers: Array[InterviewAnswer] = []
