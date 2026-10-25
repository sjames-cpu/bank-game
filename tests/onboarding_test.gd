extends "res://tests/support/teller_room_suite.gd"

## Onboarding at the start of every career (OnboardingManager, OnboardingFlow,
## OnboardingScreen, OnboardingData): the background check letter, the
## employment contract and four training lessons, in order, after the
## interview with it on and at career start with it off; quizzes that need
## every answer right and allow retries; quiz answers that match the game's
## real rules; resuming mid-onboarding from the save; a reset starting it
## over; F1/F2 skipping it; and every step fitting the window.

const START_SCREEN := "res://scenes/ui/start_screen.tscn"
const Step := OnboardingManager.Step

var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func letters() -> DisciplineLetterScreen:
	return room.letter_screen

func lesson_screen() -> OnboardingScreen:
	return room.onboarding_screen

## A fresh room for a career at onboarding step `step` (a new career starts
## at the background check).
func room_at(step: Step) -> void:
	room.free()
	OnboardingManager.step = step
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	ts = room.get_node("UI/TellerScreen")
	cq = room.get_node("CustomerQueue")
	cq.spawn_timer.stop()

## Answers every question of the lesson on screen correctly and moves on.
func pass_lesson() -> void:
	var screen := lesson_screen()
	assert_bool(screen.visible).is_true()
	for q in screen.lesson.questions.size():
		screen.choose(q, screen.lesson.questions[q].correct)
	screen.action_button.pressed.emit()
	assert_bool(screen.is_passed()).is_true()
	screen.action_button.pressed.emit()

func assert_fits(panel: Control, what: String) -> void:
	await frames(4)
	var problems := layout_problems(panel)
	assert_array(problems).override_failure_message("%s:\n%s" % [what, "\n".join(problems)]).is_empty()

## The start screen's main menu, Play, and slot 1 (a new game), as a player
## would, returning the scene it opens.
func new_game_from_the_menu() -> Node:
	room.free()
	var start: StartScreen = (load(START_SCREEN) as PackedScene).instantiate()
	get_tree().root.add_child(start)
	get_tree().current_scene = start
	await get_tree().process_frame
	start.play_button.pressed.emit()
	start.slot_buttons[0].pressed.emit()
	await frames(2)
	return get_tree().current_scene

## Walks through the whole onboarding from the background check.
func complete_onboarding() -> void:
	assert_str(letters().title_label.text).is_equal(OnboardingData.BACKGROUND_CHECK_TITLE)
	letters().action_button.pressed.emit()
	assert_str(letters().title_label.text).is_equal(OnboardingData.CONTRACT_TITLE)
	letters().action_button.pressed.emit()
	for i in OnboardingData.lessons().size():
		assert_int(lesson_screen().lesson_index).is_equal(i)
		pass_lesson()

# --- the order of steps ------------------------------------------------------------------

func test_with_the_interview_off_onboarding_starts_the_career() -> void:
	use_interview_setting(false)
	var scene := await new_game_from_the_menu()
	assert_object(scene).is_instanceof(TellerRoom)
	adopt_room(scene as TellerRoom, true)
	assert_int(OnboardingManager.step).is_equal(Step.BACKGROUND_CHECK)
	# The world waits, and the first-run hints wait for the end.
	assert_bool(get_tree().paused).is_true()
	assert_bool(HintManager.has_shown(HintManager.Hint.ARRIVAL)).is_false()

	# 1. The background check.
	assert_bool(letters().visible).is_true()
	assert_str(letters().title_label.text).is_equal(OnboardingData.BACKGROUND_CHECK_TITLE)
	assert_str(letters().from_label.text).is_equal("From: Human Resources")
	assert_str(letters().body_label.text).contains("background check has cleared")
	await assert_fits(letters().letter_panel, "background check")
	letters().action_button.pressed.emit()

	# 2. The contract: the role, the report limit, no probation, "I agree".
	assert_int(OnboardingManager.step).is_equal(Step.CONTRACT)
	assert_str(letters().title_label.text).is_equal(OnboardingData.CONTRACT_TITLE)
	assert_str(letters().action_button.text).is_equal("I agree")
	var contract := letters().body_label.text
	assert_str(contract).contains("Position: Teller")
	assert_str(contract).contains("Dismissal: %d reports end your employment" % ReportManager.REPORTS_FOR_TERMINATION)
	assert_str(contract).contains("every %d customers served wrongly" % ReportManager.MISTAKES_PER_REPORT)
	assert_str(contract).not_contains("Probation")
	await assert_fits(letters().letter_panel, "contract")
	letters().action_button.pressed.emit()

	# 3. Four lessons, in order.
	var titles: Array[String] = []
	var xp_before := XPManager.total_xp
	for i in 4:
		assert_int(OnboardingManager.step).is_equal(Step.LESSON_ID + i)
		assert_bool(letters().visible).is_false()
		titles.append(lesson_screen().title_label.text)
		assert_str(lesson_screen().header_label.text).is_equal("Compliance Training — Lesson %d of 4" % (i + 1))
		pass_lesson()
	assert_array(titles).is_equal(["ID checks", "Your drawer limit", "Dual control at the vault", "Privacy and complaints"])

	# 4. The career starts: training XP, the hints, the world running, saved.
	assert_int(OnboardingManager.step).is_equal(Step.DONE)
	assert_int(XPManager.total_xp - xp_before).is_equal(50)
	assert_bool(lesson_screen().visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(HintManager.has_shown(HintManager.Hint.ARRIVAL)).is_true()
	var saved := SaveGame.read()
	assert_int(SaveGame.int_of(SaveGame.dict_of(saved.career, "onboarding"), "step", -1)).is_equal(Step.DONE)

func test_with_the_interview_on_onboarding_follows_the_hire() -> void:
	use_interview_setting(true)
	var scene := await new_game_from_the_menu()
	var interview := scene as InterviewScreen
	assert_object(interview).is_not_null()
	# A new career, not yet started: no onboarding during the interview.
	assert_int(OnboardingManager.step).is_equal(Step.BACKGROUND_CHECK)
	for question: InterviewQuestion in interview.questions:
		var best: Button = null
		var best_score := -999
		for i in question.answers.size():
			if question.answers[i].score > best_score:
				best_score = question.answers[i].score
				best = interview.answers_container.get_child(interview.answers_container.get_child_count() - question.answers.size() + i)
		best.pressed.emit()
	assert_int(interview.last_outcome).is_equal(InterviewManager.Outcome.HIRED)
	# The hire saved the career at the start of onboarding.
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "onboarding"), "step", -1)).is_equal(Step.BACKGROUND_CHECK)
	interview.continue_button.pressed.emit()
	await frames(2)
	assert_object(get_tree().current_scene).is_instanceof(TellerRoom)
	adopt_room(get_tree().current_scene as TellerRoom, true)
	complete_onboarding()
	assert_bool(OnboardingManager.is_complete()).is_true()

func test_the_contract_states_probation_when_hired_on_it() -> void:
	InterviewManager.is_on_probation = true
	var contract := OnboardingData.contract_body()
	assert_str(contract).contains("Probation: you are hired on probation. While it lasts, %d reports end your employment instead of the usual %d. %d teller shifts in a row without a report complete it." % [
		InterviewManager.PROBATION_REPORTS_FOR_TERMINATION, ReportManager.REPORTS_FOR_TERMINATION, InterviewManager.PROBATION_CLEAN_SHIFTS])
	assert_str(contract).contains("Dismissal: %d reports" % InterviewManager.PROBATION_REPORTS_FOR_TERMINATION)

# --- quizzes -------------------------------------------------------------------------

func test_a_quiz_needs_every_answer_right_and_allows_retries() -> void:
	await room_at(Step.LESSON_ID)
	var screen := lesson_screen()
	assert_bool(screen.visible).is_true()
	assert_int(screen.answer_buttons.size()).is_equal(2)
	# Nothing to check until both are answered.
	assert_bool(screen.action_button.disabled).is_true()
	var first := screen.lesson.questions[0]
	var second := screen.lesson.questions[1]
	screen.choose(0, (first.correct + 1) % first.answers.size())
	assert_bool(screen.action_button.disabled).is_true()
	screen.choose(1, second.correct)
	assert_bool(screen.action_button.disabled).is_false()

	# One wrong: not passed, the right answer explained, that one cleared.
	screen.action_button.pressed.emit()
	assert_bool(screen.is_passed()).is_false()
	assert_int(screen.failed_attempts).is_equal(1)
	assert_str(screen.feedback_label.text).is_equal("Not quite, try again.\n1. %s" % first.explanation)
	assert_int(screen.chosen(0)).is_equal(-1)
	assert_int(screen.chosen(1)).is_equal(second.correct)
	assert_bool(screen.action_button.disabled).is_true()
	assert_int(OnboardingManager.step).is_equal(Step.LESSON_ID)
	await assert_fits(screen.panel, "lesson 1 after a wrong answer")

	# Both wrong this time, then right.
	screen.choose(0, (first.correct + 2) % first.answers.size())
	screen.choose(1, (second.correct + 1) % second.answers.size())
	screen.action_button.pressed.emit()
	assert_int(screen.failed_attempts).is_equal(2)
	assert_str(screen.feedback_label.text).contains("2. %s" % second.explanation)
	screen.choose(0, first.correct)
	screen.choose(1, second.correct)
	screen.action_button.pressed.emit()
	assert_bool(screen.is_passed()).is_true()
	assert_str(screen.feedback_label.text).is_equal("All correct.")
	assert_str(screen.action_button.text).is_equal("Next Lesson")
	# Passed answers are locked.
	var locked: CheckBox = screen.answer_buttons[0][0]
	assert_bool(locked.disabled).is_true()
	screen.action_button.pressed.emit()
	assert_int(OnboardingManager.step).is_equal(Step.LESSON_DRAWER)
	assert_int(screen.lesson_index).is_equal(1)

## Where the right answer is shown for each question, top to bottom.
func correct_positions(screen: OnboardingScreen) -> Array[int]:
	var positions: Array[int] = []
	for q in screen.lesson.questions.size():
		var question := screen.lesson.questions[q]
		positions.append(Array(screen.shown_answers(q)).find(question.answers[question.correct]))
	return positions

func test_answers_are_shuffled_on_every_showing_and_retry() -> void:
	await room_at(Step.LESSON_DRAWER)
	var screen := lesson_screen()
	screen.shuffle_rng.seed = 7
	var seen := {}
	for showing in 12:
		screen.show_lesson(1)
		# Every answer shown once, in some order.
		for q in 2:
			var shown := Array(screen.shown_answers(q))
			shown.sort()
			var answers := Array(screen.lesson.questions[q].answers)
			answers.sort()
			assert_array(shown).is_equal(answers)
		seen[str(correct_positions(screen))] = true
	assert_int(seen.size()).override_failure_message("the right answers never moved").is_greater(1)

	# A retry shuffles again; the right answer picked stays picked, by content.
	var first := screen.lesson.questions[0]
	var second := screen.lesson.questions[1]
	var moved := false
	for attempt in 12:
		var positions_before := correct_positions(screen)
		screen.choose(0, first.correct)
		screen.choose(1, (second.correct + 1) % second.answers.size())
		screen.action_button.pressed.emit()
		assert_bool(screen.is_passed()).is_false()
		assert_int(screen.chosen(0)).is_equal(first.correct)
		assert_int(screen.chosen(1)).is_equal(-1)
		var picked: String = screen.shown_answers(0)[Array(screen.answer_order[0]).find(first.correct)]
		assert_str(picked).is_equal(first.answers[first.correct])
		if correct_positions(screen) != positions_before:
			moved = true
	assert_bool(moved).override_failure_message("a retry never reshuffled").is_true()
	# Picked by content, wherever it's shown: passes.
	screen.choose(1, second.correct)
	screen.action_button.pressed.emit()
	assert_bool(screen.is_passed()).is_true()

func test_no_answer_shows_its_points() -> void:
	await room_at(Step.LESSON_PRIVACY)
	var screen := lesson_screen()
	var replies := OnboardingData.quiz_complaint_replies()
	var shown := Array(screen.shown_answers(1))
	for reply in replies:
		# Exactly the reply's words, nothing added.
		assert_bool(shown.has(reply.text)).override_failure_message(reply.text).is_true()
	# A signed number (+2, -3, −3), a bracketed one ("(0)"), or the words.
	var points := RegEx.create_from_string("[+\\-−]\\d|\\(\\d\\)|Reputation|points?\\b")
	for lesson in OnboardingData.lessons():
		for question in lesson.questions:
			for answer in question.answers:
				assert_object(points.search(answer)).override_failure_message("shows points: %s" % answer).is_null()
	# The lesson text may name them.
	assert_str(screen.lesson.text).contains("+2 Reputation")

func test_the_last_lesson_finishes_the_training() -> void:
	await room_at(Step.LESSON_PRIVACY)
	var screen := lesson_screen()
	for q in 2:
		screen.choose(q, screen.lesson.questions[q].correct)
	screen.action_button.pressed.emit()
	assert_str(screen.feedback_label.text).is_equal("All correct. Training complete: +50 XP.")
	assert_str(screen.action_button.text).is_equal("Finish Training")
	screen.action_button.pressed.emit()
	assert_bool(OnboardingManager.is_complete()).is_true()

func test_every_lesson_and_every_wrong_answer_fits_the_window() -> void:
	for i in 4:
		await room_at((Step.LESSON_ID + i) as Step)
		var screen := lesson_screen()
		await assert_fits(screen.panel, "lesson %d" % (i + 1))
		# All wrong: the longest feedback.
		for q in 2:
			var question := screen.lesson.questions[q]
			screen.choose(q, (question.correct + 1) % question.answers.size())
		screen.action_button.pressed.emit()
		await assert_fits(screen.panel, "lesson %d, all wrong" % (i + 1))
		# The lesson isn't cut off: either it all shows or it scrolls.
		assert_float(screen.content_scroll.custom_minimum_size.y).is_greater(0.0)

# --- the content matches the rules --------------------------------------------------------

func test_quiz_answers_match_the_games_real_rules() -> void:
	var lessons := OnboardingData.lessons()
	assert_int(lessons.size()).is_equal(4)
	for lesson in lessons:
		assert_int(lesson.questions.size()).is_equal(2)
		for question in lesson.questions:
			assert_int(question.answers.size()).is_greater_equal(2)
			assert_bool(question.correct >= 0 and question.correct < question.answers.size()).is_true()
			assert_str(question.explanation).is_not_empty()

	# ID checks: a deposit needs no ID, a withdrawal does; an expired card is
	# refused.
	var id_lesson := lessons[0]
	var depositor := spawn(ShiftTransaction.Type.DEPOSIT, 200)
	assert_bool(KycPolicy.requires_id(depositor)).is_false()
	assert_str(id_lesson.questions[0].answers[id_lesson.questions[0].correct]).is_equal("No, deposits don't need ID")
	var withdrawal := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	assert_bool(KycPolicy.requires_id(withdrawal)).is_true()
	give_id(withdrawal, IdCard.Problem.EXPIRED)
	assert_bool(withdrawal.id_card.is_valid()).is_false()
	assert_str(id_lesson.questions[1].answers[id_lesson.questions[1].correct]).is_equal("Refuse service")
	assert_int(TellerScreen.KYC_BAD_ID_ACCEPTED_MISTAKES).is_equal(2)
	assert_str(OnboardingData.contract_body()).contains("Serving a customer on a bad ID counts as two mistakes at once")

	# The drawer: the real limit and float, and going over is only a warning
	# until clock-out.
	var drawer := lessons[1]
	var max_text := LoanApplication.dollars(TellerScreen.DRAWER_MAX_CENTS / 100.0)
	assert_str(max_text).is_equal("$3,350")
	assert_str(drawer.questions[0].answers[drawer.questions[0].correct]).is_equal(max_text)
	assert_bool(drawer.questions[0].answers.has(LoanApplication.dollars(TellerScreen.STARTING_FLOAT_CENTS / 100.0))).is_true()
	assert_str(drawer.text).contains("$3,350")
	assert_str(drawer.text).contains(LoanApplication.dollars(TellerScreen.DRAWER_MIN_CENTS / 100.0))
	assert_str(drawer.questions[1].answers[drawer.questions[1].correct]).is_equal("Before you clock out")
	assert_int(TellerScreen.DRAWER_OVER_AT_CLOCK_OUT_SCORE).is_less(0)
	clock_in()
	deposit_until_over_limit()
	# Over the limit mid-shift: a warning, and the shift carries on.
	assert_str(ts.drawer_limit_warning()).is_not_empty()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_IN)

	# Dual control: exactly one witness; nobody free keeps the vault shut.
	var vault := lessons[2]
	assert_str(vault.questions[0].answers[vault.questions[0].correct]).is_equal("Two: you and one witness")
	call_vault_witness()
	assert_object(room.vault_control.witness).is_instanceof(StaffNPC)
	assert_str(vault.questions[1].answers[vault.questions[1].correct]).contains("stays shut")
	assert_str(VaultDualControl.NO_ONE_FREE_TEXT).contains("No one is free")

	# Complaints: the best reply is the real best one, the scores are real.
	var privacy := lessons[3]
	var replies := OnboardingData.quiz_complaint_replies()
	var best := replies[privacy.questions[1].correct]
	for reply in replies:
		assert_int(best.score).is_greater_equal(reply.score)
	assert_int(best.score).is_equal(OnboardingData.best_complaint_score())
	assert_str(privacy.text).contains("+%d Reputation" % best.score)
	assert_str(privacy.text).contains("Reputation (%d)" % OnboardingData.worst_complaint_score())
	assert_str(privacy.questions[1].answers[privacy.questions[1].correct]).is_equal(best.text)

## Cash deposits until the drawer is over its limit.
func deposit_until_over_limit() -> void:
	while ts.drawer_cash_cents() <= TellerScreen.DRAWER_MAX_CENTS:
		serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 500))

# --- saving, resuming and resetting --------------------------------------------------------

func test_quitting_mid_onboarding_resumes_at_the_same_step() -> void:
	await room_at(Step.BACKGROUND_CHECK)
	letters().action_button.pressed.emit()
	letters().action_button.pressed.emit()
	pass_lesson()
	assert_int(OnboardingManager.step).is_equal(Step.LESSON_DRAWER)
	# Each step done was saved; quitting mid-lesson loses nothing before it.
	var saved := SaveGame.read()
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	assert_int(SaveGame.int_of(SaveGame.dict_of(saved.career, "onboarding"), "step", -1)).is_equal(Step.LESSON_DRAWER)

	# Quit and load: back at the drawer lesson.
	get_tree().paused = false
	CareerReset.reset_all()
	SaveGame.restore(saved.career)
	await room_at(OnboardingManager.step)
	assert_bool(letters().visible).is_false()
	assert_bool(lesson_screen().visible).is_true()
	assert_str(lesson_screen().title_label.text).is_equal("Your drawer limit")
	for i in 3:
		pass_lesson()
	assert_bool(OnboardingManager.is_complete()).is_true()

func test_a_reset_or_new_game_starts_onboarding_over() -> void:
	OnboardingManager.skip()
	CareerReset.reset_all()
	assert_int(OnboardingManager.step).is_equal(Step.BACKGROUND_CHECK)
	# A save from before onboarding existed has none: that career had started.
	SaveGame.restore({"score": {"total_score": 5}})
	assert_bool(OnboardingManager.is_complete()).is_true()
	# A finished career, then a new game: onboarding again.
	use_interview_setting(false)
	var scene := await new_game_from_the_menu()
	adopt_room(scene as TellerRoom, true)
	assert_int(OnboardingManager.step).is_equal(Step.BACKGROUND_CHECK)
	assert_str(letters().title_label.text).is_equal(OnboardingData.BACKGROUND_CHECK_TITLE)

# --- debug shortcuts ---------------------------------------------------------------------

func key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func test_f1_and_f2_skip_onboarding_in_debug_builds_only() -> void:
	# F1 at the background check: skipped, no training XP, then F1's own unlocks.
	await room_at(Step.BACKGROUND_CHECK)
	assert_bool(letters().visible).is_true()
	room.onboarding_flow._unhandled_input(key(TellerRoom.DEBUG_UNLOCK_KEY))
	assert_bool(OnboardingManager.is_complete()).is_true()
	assert_bool(lesson_screen().visible).is_false()
	# F1's own unlocks follow: Branch Manager, whose promotion letter replaces
	# the background check.
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_str(letters().title_label.text).is_equal("Letter of Promotion")
	assert_bool(HintManager.has_shown(HintManager.Hint.ARRIVAL)).is_true()

	# F2 mid-lesson.
	get_tree().paused = false
	CareerReset.reset_all()
	await room_at(Step.LESSON_VAULT)
	assert_bool(lesson_screen().visible).is_true()
	room.onboarding_flow._unhandled_input(key(TellerRoom.DEBUG_LOAN_OFFICER_KEY))
	assert_bool(OnboardingManager.is_complete()).is_true()
	assert_bool(lesson_screen().visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(XPManager.total_xp).is_equal(XPManager.XP_UNLOCK_THRESHOLD)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()

	# A release build: neither key does anything.
	get_tree().paused = false
	CareerReset.reset_all()
	await room_at(Step.CONTRACT)
	room.debug_cheats_enabled = false
	room.onboarding_flow._unhandled_input(key(TellerRoom.DEBUG_UNLOCK_KEY))
	room.onboarding_flow._unhandled_input(key(TellerRoom.DEBUG_LOAN_OFFICER_KEY))
	assert_int(OnboardingManager.step).is_equal(Step.CONTRACT)
	assert_str(letters().title_label.text).is_equal(OnboardingData.CONTRACT_TITLE)
	assert_int(XPManager.total_xp).is_equal(0)
