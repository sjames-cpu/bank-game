extends Control

## First-shift interview mini-game (2h). This scene is the project's
## main_scene, so it's the very first thing the player sees — teller_room
## (and its Player/first shift) only loads once the interview ends in
## Hired or Hired-on-Probation. A Rejected outcome loops back to the
## first question right here instead of needing any "quit game" flow.

const TELLER_ROOM_SCENE: String = "res://scenes/world/teller_room.tscn"

@onready var panel: Panel = $Panel
@onready var question_label: Label = $Panel/VBox/QuestionLabel
@onready var answers_container: VBoxContainer = $Panel/VBox/AnswersVBox

@onready var outcome_panel: Panel = $OutcomePanel
@onready var outcome_title_label: Label = $OutcomePanel/VBox/TitleLabel
@onready var outcome_message_label: Label = $OutcomePanel/VBox/MessageLabel
@onready var continue_button: Button = $OutcomePanel/VBox/ContinueButton

var questions: Array[InterviewQuestion] = []
var current_question_index: int = 0
var running_score: int = 0
var instant_rejected: bool = false
var last_outcome: InterviewManager.Outcome = InterviewManager.Outcome.REJECTED

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_button_pressed)
	_start_interview()

func _start_interview() -> void:
	questions = InterviewQuestionsData.get_questions()
	current_question_index = 0
	running_score = 0
	instant_rejected = false
	outcome_panel.visible = false
	panel.visible = true
	_show_current_question()

func _show_current_question() -> void:
	var question := questions[current_question_index]
	question_label.text = question.question_text

	for child in answers_container.get_children():
		child.queue_free()

	for answer in question.answers:
		var button := Button.new()
		button.text = answer.text
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_answer_selected.bind(answer))
		answers_container.add_child(button)

func _on_answer_selected(answer: InterviewAnswer) -> void:
	running_score += answer.score
	if answer.is_instant_reject:
		instant_rejected = true

	current_question_index += 1
	if current_question_index >= questions.size():
		_finish_interview()
	else:
		_show_current_question()

func _finish_interview() -> void:
	last_outcome = InterviewManager.resolve_outcome(running_score, instant_rejected)
	panel.visible = false
	_show_outcome(last_outcome)

func _show_outcome(outcome: InterviewManager.Outcome) -> void:
	match outcome:
		InterviewManager.Outcome.HIRED:
			outcome_title_label.text = "You're Hired!"
			outcome_message_label.text = "Welcome aboard — report to the teller desk to start your first shift."
			continue_button.text = "Start Shift"
		InterviewManager.Outcome.HIRED_ON_PROBATION:
			outcome_title_label.text = "You're Hired — On Probation"
			outcome_message_label.text = "Your answers raised some concerns, but we'll give you a shot on a probationary basis."
			continue_button.text = "Start Shift"
		InterviewManager.Outcome.REJECTED:
			outcome_title_label.text = "Not This Time"
			outcome_message_label.text = "Thank you for your time, but we won't be moving forward with your application."
			continue_button.text = "Try Again"

	outcome_panel.visible = true

func _on_continue_button_pressed() -> void:
	if last_outcome == InterviewManager.Outcome.REJECTED:
		_start_interview()
	else:
		get_tree().change_scene_to_file(TELLER_ROOM_SCENE)
