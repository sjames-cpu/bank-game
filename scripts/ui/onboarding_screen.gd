extends Control
class_name OnboardingScreen

## A compliance training lesson (OnboardingData) during onboarding
## (OnboardingFlow): a few lines of bank policy and a two-question
## multiple-choice quiz. "Check Answers" (once every question is answered)
## passes the lesson only if every answer is right; otherwise it explains the
## right answer to each one missed, clears those, and the player tries again
## (as often as needed). The answers are shuffled every time a question is
## shown, retries included (the right ones stay picked), so the right answer
## isn't always in the same place; answers are identified by content (their
## index in TrainingQuestion.answers), never by position. Once passed, the button moves on ("Next Lesson", or
## "Finish Training" after the last, which also names the training XP) and
## lesson_passed fires when it's pressed.
##
## The lesson and quiz sit in a scroll area sized to them, but never so tall
## that the panel passes MAX_PANEL_HEIGHT; the header, feedback and button
## stay put. Pauses the tree while open (process_mode ALWAYS), like the
## letters.

signal lesson_passed(index: int)

@onready var panel: PanelContainer = $Panel
@onready var header_label: Label = $Panel/VBox/HeaderLabel
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_scroll: ScrollContainer = $Panel/VBox/ContentScroll
@onready var content_vbox: VBoxContainer = $Panel/VBox/ContentScroll/ContentVBox
@onready var lesson_text_label: Label = $Panel/VBox/ContentScroll/ContentVBox/LessonTextLabel
@onready var questions_vbox: VBoxContainer = $Panel/VBox/ContentScroll/ContentVBox/QuestionsVBox
@onready var feedback_label: Label = $Panel/VBox/FeedbackLabel
@onready var action_button: Button = $Panel/VBox/ActionButton

## The panel stays within the 648 px window, 10 px clear of each edge.
const MAX_PANEL_HEIGHT: float = 628.0
const CHECK_TEXT: String = "Check Answers"
const UNCHECKED_COLOR: Color = Color(0.72, 0.76, 0.82, 1)
const PASS_COLOR: Color = Color(0.3, 1, 0.3, 1)
const RETRY_COLOR: Color = Color(1, 0.75, 0.35, 1)

var lesson_index: int = -1
var lesson: TrainingLesson = null
## Each question's answer buttons, top to bottom.
var answer_buttons: Array[Array] = []
## Each question's shuffled order: the answer index (TrainingQuestion.answers)
## shown at each position.
var answer_order: Array[PackedInt32Array] = []
## The shuffles' own generator, so they never shift the global random draws a
## seeded run depends on (tests seed it).
var shuffle_rng := RandomNumberGenerator.new()
## Wrong checks so far on this lesson.
var failed_attempts: int = 0
var _passed: bool = false
var _paused_by_self: bool = false

func _ready() -> void:
	visible = false
	shuffle_rng.randomize()
	action_button.pressed.connect(_on_action_button_pressed)
	# Wrapped text only knows its height once it has its width.
	content_vbox.minimum_size_changed.connect(_fit_content)
	content_vbox.resized.connect(_fit_content)
	panel.minimum_size_changed.connect(_recentre)

func show_lesson(index: int) -> void:
	var lessons := OnboardingData.lessons()
	lesson_index = index
	lesson = lessons[index]
	failed_attempts = 0
	_passed = false
	header_label.text = "Compliance Training — Lesson %d of %d" % [index + 1, lessons.size()]
	title_label.text = lesson.title
	lesson_text_label.text = lesson.text
	_build_questions()
	feedback_label.visible = false
	action_button.text = CHECK_TEXT
	_update_action_button()
	visible = true
	content_scroll.scroll_vertical = 0
	_fit_content()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

func is_passed() -> bool:
	return _passed

## Picks answer `answer` (its index in the question's answers, wherever it's
## shown) to question `question`, as clicking it would.
func choose(question: int, answer: int) -> void:
	var button: CheckBox = answer_buttons[question][answer_order[question].find(answer)]
	button.button_pressed = true

## The answer picked for `question` (its index in the question's answers), or
## -1.
func chosen(question: int) -> int:
	var buttons: Array = answer_buttons[question]
	for i in buttons.size():
		var button: CheckBox = buttons[i]
		if button.button_pressed:
			return answer_order[question][i]
	return -1

## Question `question`'s answers as shown, top to bottom.
func shown_answers(question: int) -> PackedStringArray:
	var texts: PackedStringArray = []
	for button: CheckBox in answer_buttons[question]:
		texts.append(button.text)
	return texts

## A fresh shuffle of `count` answer indices.
func _shuffled(count: int) -> PackedInt32Array:
	var order: PackedInt32Array = []
	for i in count:
		order.append(i)
	for i in range(count - 1, 0, -1):
		var j := shuffle_rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	return order

## Builds the questions with their answers freshly shuffled, picking
## `keep[q]` again for question q where it's 0 or more.
func _build_questions(keep: Array[int] = []) -> void:
	for child in questions_vbox.get_children():
		questions_vbox.remove_child(child)
		child.queue_free()
	answer_buttons.clear()
	answer_order.clear()
	for q in lesson.questions.size():
		var question := lesson.questions[q]
		var label := Label.new()
		label.text = "%d. %s" % [q + 1, question.question]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		questions_vbox.add_child(label)
		var group := ButtonGroup.new()
		group.allow_unpress = false
		var buttons: Array[CheckBox] = []
		var order := _shuffled(question.answers.size())
		answer_order.append(order)
		for answer_index in order:
			var button := CheckBox.new()
			button.text = question.answers[answer_index]
			button.button_group = group
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Compact rows: the theme's button panel makes each twice as tall.
			var compact := StyleBoxEmpty.new()
			compact.content_margin_left = 12.0
			compact.content_margin_top = 2.0
			compact.content_margin_bottom = 2.0
			for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				button.add_theme_stylebox_override(style, compact)
			# The theme's empty circle is too dark to see on the panel.
			button.add_theme_icon_override("radio_unchecked", _unchecked_ring())
			button.toggled.connect(func(_on: bool) -> void: _update_action_button())
			questions_vbox.add_child(button)
			buttons.append(button)
			if q < keep.size() and keep[q] == answer_index:
				button.set_pressed_no_signal(true)
		answer_buttons.append(buttons)

static var _ring: ImageTexture = null

## A light 16 px ring for an unpicked answer (built once).
static func _unchecked_ring() -> ImageTexture:
	if _ring != null:
		return _ring
	var side := 16
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var centre := Vector2(side / 2.0 - 0.5, side / 2.0 - 0.5)
	for y in side:
		for x in side:
			var distance := Vector2(x, y).distance_to(centre)
			if distance <= 6.5 and distance >= 5.0:
				image.set_pixel(x, y, UNCHECKED_COLOR)
	_ring = ImageTexture.create_from_image(image)
	return _ring

func _all_answered() -> bool:
	for q in answer_buttons.size():
		if chosen(q) < 0:
			return false
	return true

func _update_action_button() -> void:
	action_button.disabled = not _passed and not _all_answered()

func _on_action_button_pressed() -> void:
	if _passed:
		hide_screen()
		lesson_passed.emit(lesson_index)
		return
	if not _all_answered():
		return
	var notes: PackedStringArray = []
	var keep: Array[int] = []
	for q in lesson.questions.size():
		var question := lesson.questions[q]
		if question.is_correct(chosen(q)):
			keep.append(chosen(q))
		else:
			notes.append("%d. %s" % [q + 1, question.explanation])
			# Cleared, so the player answers it again.
			keep.append(-1)
	if not notes.is_empty():
		# Shuffled again for the retry, the right answers still picked.
		_build_questions(keep)
	feedback_label.visible = true
	if notes.is_empty():
		_passed = true
		for buttons in answer_buttons:
			for button: CheckBox in buttons:
				button.disabled = true
		var last := lesson_index == OnboardingData.lessons().size() - 1
		feedback_label.text = "All correct."
		if last:
			feedback_label.text += " Training complete: +%d XP." % (OnboardingManager.TRAINING_XP_SCORE_POINTS * XPManager.XP_PER_SCORE_POINT)
		feedback_label.modulate = PASS_COLOR
		action_button.text = "Finish Training" if last else "Next Lesson"
	else:
		failed_attempts += 1
		feedback_label.text = "Not quite, try again.\n" + "\n".join(notes)
		feedback_label.modulate = RETRY_COLOR
	_update_action_button()
	_fit_content()

## The scroll area takes the lesson's height, but the panel never passes
## MAX_PANEL_HEIGHT (then the lesson scrolls).
func _fit_content() -> void:
	var content_height := content_vbox.get_combined_minimum_size().y
	var chrome := panel.get_combined_minimum_size().y - content_scroll.custom_minimum_size.y
	var wanted := minf(content_height, maxf(0.0, MAX_PANEL_HEIGHT - chrome))
	if not is_equal_approx(wanted, content_scroll.custom_minimum_size.y):
		content_scroll.custom_minimum_size.y = wanted
	_recentre()

func _recentre() -> void:
	var height := panel.get_combined_minimum_size().y
	panel.offset_top = -height / 2.0
	panel.offset_bottom = height / 2.0
