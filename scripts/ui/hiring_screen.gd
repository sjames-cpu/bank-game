extends Control
class_name HiringScreen

## Branch Manager hiring (NPC coworkers, step 5): fill a vacant desk from
## HiringManager's candidates. One vacancy at a time (< > to browse when
## there are several); its three candidates are buttons, and the selected
## one shows their background line and their interview so far. "Ask Next
## Question" reveals one more question and answer; the manager may
## interview all three before choosing "Hire" or "Reject All".
##
## Never shows a candidate's stats or an answer's score: only after a hire
## does the "hired" card reveal the new staff member's stats, with the
## feedback on the call and its points, in place of the vacancy until
## "Continue" moves on to any other one.
##
## Opened from branch_manager_screen.gd's hub, which tallies hire_completed
## into the shift total and returns to its menu on closed. Pauses the tree
## defensively, like the hub's other sub-screens.

signal closed
signal hire_completed(score_delta: int, reputation_delta: int, xp_delta: int)

@onready var vacancy_hbox: HBoxContainer = $Panel/VBox/VacancyHBox
@onready var vacancy_label: Label = $Panel/VBox/VacancyHBox/VacancyLabel
@onready var prev_button: Button = $Panel/VBox/VacancyHBox/PrevButton
@onready var next_button: Button = $Panel/VBox/VacancyHBox/NextButton
@onready var message_label: Label = $Panel/VBox/MessageLabel
@onready var candidates_hbox: HBoxContainer = $Panel/VBox/CandidatesHBox
@onready var candidate_section: PanelContainer = $Panel/VBox/CandidateSection
@onready var candidate_name_label: Label = $Panel/VBox/CandidateSection/CandidateVBox/NameLabel
@onready var background_label: Label = $Panel/VBox/CandidateSection/CandidateVBox/BackgroundLabel
@onready var transcript_label: Label = $Panel/VBox/CandidateSection/CandidateVBox/TranscriptScroll/TranscriptLabel
@onready var ask_button: Button = $Panel/VBox/CandidateSection/CandidateVBox/AskButton
@onready var actions_hbox: HBoxContainer = $Panel/VBox/ActionsHBox
@onready var hire_button: Button = $Panel/VBox/ActionsHBox/HireButton
@onready var reject_all_button: Button = $Panel/VBox/ActionsHBox/RejectAllButton
@onready var hired_card: PanelContainer = $Panel/VBox/HiredCard
@onready var hired_label: Label = $Panel/VBox/HiredCard/HiredVBox/HiredLabel
@onready var feedback_label: Label = $Panel/VBox/HiredCard/HiredVBox/FeedbackLabel
@onready var continue_button: Button = $Panel/VBox/HiredCard/HiredVBox/ContinueButton
@onready var close_button: Button = $Panel/VBox/CloseButton

const GOOD_COLOR: Color = Color(0.3, 1, 0.3, 1)
const FAIR_COLOR: Color = Color(1, 0.9, 0.4, 1)
const BAD_COLOR: Color = Color(1, 0.45, 0.35, 1)

var _paused_by_self: bool = false
var _vacancy_index: int = 0
var _selected_index: int = 0

func _ready() -> void:
	visible = false
	prev_button.pressed.connect(_step_vacancy.bind(-1))
	next_button.pressed.connect(_step_vacancy.bind(1))
	ask_button.pressed.connect(_on_ask_pressed)
	hire_button.pressed.connect(_on_hire_pressed)
	reject_all_button.pressed.connect(_on_reject_all_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	close_button.pressed.connect(hide_screen)

func show_screen() -> void:
	_vacancy_index = 0
	_selected_index = 0
	hired_card.visible = false
	message_label.visible = false
	_refresh()
	visible = true
	_paused_by_self = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false
	closed.emit()

## The vacancy shown, or "" when there's none.
func current_vacancy() -> String:
	var vacancies := HiringManager.vacancies()
	if vacancies.is_empty():
		return ""
	return vacancies[clampi(_vacancy_index, 0, vacancies.size() - 1)]

func current_candidates() -> Array[StaffCandidate]:
	var slot_name := current_vacancy()
	if slot_name == "":
		return []
	return HiringManager.candidates_for(slot_name)

## The candidate selected, or null when the vacancy has none.
func selected_candidate() -> StaffCandidate:
	var field := current_candidates()
	if field.is_empty():
		return null
	return field[clampi(_selected_index, 0, field.size() - 1)]

func select_candidate(index: int) -> void:
	_selected_index = index
	_refresh()

func _step_vacancy(delta: int) -> void:
	_vacancy_index = clampi(_vacancy_index + delta, 0, maxi(0, HiringManager.vacancies().size() - 1))
	_selected_index = 0
	_refresh()

func _on_ask_pressed() -> void:
	var candidate := selected_candidate()
	if candidate != null:
		HiringManager.ask_next_question(candidate)
	_refresh()

func _on_hire_pressed() -> void:
	var candidate := selected_candidate()
	if candidate == null:
		return
	var result := HiringManager.hire(current_vacancy(), candidate)
	if result.is_empty():
		return
	hired_label.text = hired_card_text(result)
	feedback_label.text = result_text(result)
	var verdict: HiringManager.Verdict = result["verdict"]
	feedback_label.modulate = GOOD_COLOR if verdict == HiringManager.Verdict.BEST else FAIR_COLOR if verdict == HiringManager.Verdict.MIDDLE else BAD_COLOR
	hired_card.visible = true
	hire_completed.emit(result["score"], result["reputation"], result["xp"])
	_vacancy_index = 0
	_selected_index = 0
	_refresh()

## Puts the hired card away and goes on to any other vacancy.
func _on_continue_pressed() -> void:
	hired_card.visible = false
	_refresh()

func _on_reject_all_pressed() -> void:
	var slot_name := current_vacancy()
	if slot_name == "":
		return
	HiringManager.reject_all(slot_name)
	hired_card.visible = false
	_selected_index = 0
	_refresh()

func _refresh() -> void:
	var vacancies := HiringManager.vacancies()
	_vacancy_index = clampi(_vacancy_index, 0, maxi(0, vacancies.size() - 1))
	prev_button.visible = vacancies.size() > 1
	next_button.visible = vacancies.size() > 1
	prev_button.disabled = _vacancy_index <= 0
	next_button.disabled = _vacancy_index >= vacancies.size() - 1
	var slot_name := current_vacancy()
	var field := current_candidates()
	_selected_index = clampi(_selected_index, 0, maxi(0, field.size() - 1))

	if slot_name == "":
		vacancy_label.text = "No vacant desks — every desk is staffed."
	else:
		vacancy_label.text = "%s (%s)%s" % [slot_name, ScheduleManager.role_for_slot(slot_name), " · vacancy %d of %d" % [_vacancy_index + 1, vacancies.size()] if vacancies.size() > 1 else ""]

	# The hired card stands in for the vacancy until Continue.
	var showing_card := hired_card.visible
	var notice := _vacancy_notice(slot_name)
	message_label.text = notice
	message_label.visible = notice != "" and not showing_card
	vacancy_hbox.visible = not showing_card

	_rebuild_candidate_buttons(field)
	var candidate := selected_candidate()
	candidates_hbox.visible = not field.is_empty() and not showing_card
	candidate_section.visible = candidate != null and not showing_card
	actions_hbox.visible = candidate != null and not showing_card
	if candidate == null:
		return
	candidate_name_label.text = candidate.staff_name
	background_label.text = candidate.background
	transcript_label.text = transcript_text(candidate)
	ask_button.disabled = candidate.is_interview_finished()
	ask_button.text = "Interview finished" if candidate.is_interview_finished() else "Ask Question %d of %d" % [candidate.questions_asked + 1, candidate.question_indices.size()]
	hire_button.text = "Hire %s" % candidate.staff_name

## Why a vacancy has no candidates to show, or "" if it has some.
func _vacancy_notice(slot_name: String) -> String:
	if slot_name == "":
		return ""
	if not ScheduleManager.has_room_to_hire():
		return "The branch already has %d staff, the most it can employ. Assign someone from Staff Scheduling instead." % ScheduleManager.MAX_ROSTER_SIZE
	if HiringManager.rejected_slots.has(slot_name):
		return "You turned down this round of candidates. New applicants will come in at your next clock-in."
	return ""

func _rebuild_candidate_buttons(field: Array[StaffCandidate]) -> void:
	for child in candidates_hbox.get_children():
		candidates_hbox.remove_child(child)
		child.queue_free()
	for i in field.size():
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = i == _selected_index
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = candidate_button_text(field[i])
		button.pressed.connect(select_candidate.bind(i))
		candidates_hbox.add_child(button)

## "Harper Quinn\nInterviewed 2/3" — never the stats.
static func candidate_button_text(candidate: StaffCandidate) -> String:
	if candidate.questions_asked == 0:
		return "%s\nNot interviewed" % candidate.staff_name
	return "%s\nInterviewed %d/%d" % [candidate.staff_name, candidate.questions_asked, candidate.question_indices.size()]

## The questions asked so far and the candidate's answers, without scores.
static func transcript_text(candidate: StaffCandidate) -> String:
	if candidate.questions_asked == 0:
		return "Not interviewed yet."
	var lines: PackedStringArray = []
	for i in candidate.questions_asked:
		lines.append("Q%d: %s\n\"%s\"" % [i + 1, candidate.question(i).question_text, candidate.answer(i).text])
	return "\n\n".join(lines)

## The hired card: who joined which desk, with their stats revealed.
static func hired_card_text(result: Dictionary) -> String:
	var member: StaffMember = result["member"]
	return "Hired: %s — %s, %s\n%s\nSkill %d · Reliability %d · Speed %d · Customer Service %d" % [
		member.staff_name, member.role, result["slot"], member.flavor_text,
		member.skill, member.reliability, member.speed, member.customer_service,
	]

## The feedback on the call, with its points.
static func result_text(result: Dictionary) -> String:
	var points: PackedStringArray = []
	if result["score"] != 0:
		points.append("%+d Score" % result["score"])
	if result["xp"] != 0:
		points.append("%+d XP" % result["xp"])
	if result["reputation"] != 0:
		points.append("%+d Reputation" % result["reputation"])
	var text: String = result["feedback"]
	if not points.is_empty():
		text += " (%s)" % ", ".join(points)
	return text
