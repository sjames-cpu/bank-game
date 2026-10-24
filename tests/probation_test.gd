extends "res://tests/support/teller_room_suite.gd"

## With the interview switched on (InterviewManager.interview_enabled) it is
## the opening scene, and "Hired on Probation" matters: fired at
## InterviewManager.PROBATION_REPORTS_FOR_TERMINATION reports, shown on the
## HUD and in letters, and ended by PROBATION_CLEAN_SHIFTS completed teller
## shifts without a new report. (With it off, a new game starts without a
## probation: save_load_test.gd.)

const INTERVIEW_SCENE := "res://scenes/ui/interview_screen.tscn"
const START_SCREEN := "res://scenes/ui/start_screen.tscn"

var letters: DisciplineLetterScreen
var hud: Hud

func before_test() -> void:
	await super()
	letters = room.get_node("UI/DisciplineLetterScreen")
	hud = room.get_node("HUD")

# --- helpers -------------------------------------------------------------------

func start_probation() -> void:
	assert_int(InterviewManager.resolve_outcome(InterviewManager.PROBATION_THRESHOLD, false)).is_equal(InterviewManager.Outcome.HIRED_ON_PROBATION)
	assert_bool(InterviewManager.is_on_probation).is_true()

## One report's worth of mistakes.
func earn_report() -> void:
	for i in ReportManager.MISTAKES_PER_REPORT:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Customer %d" % i)

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

## A full teller shift: clock in, serve every customer, clock out, close.
## `report_during` earns a report mid-shift.
func play_teller_shift(report_during: bool = false) -> void:
	clock_in()
	if report_during:
		earn_report()
		acknowledge_letters()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		serve_correctly(spawn())
	send_excess_to_vault()
	assert_bool(clock_out()).is_true()
	close_desk()

func hud_text(label: Label) -> String:
	hud.refresh()
	return label.text if label.visible else ""

# --- opening scene ---------------------------------------------------------------

func test_new_game_starts_at_the_interview_and_hiring_starts_the_career() -> void:
	# With the interview on, the game opens on the main menu, and a new game
	# in an empty slot goes on to the interview (save_load_test.gd covers the
	# rest).
	use_interview_setting(true)
	assert_str(str(ProjectSettings.get_setting("application/run/main_scene"))).is_equal(START_SCREEN)
	room.free()
	var start: StartScreen = (load(START_SCREEN) as PackedScene).instantiate()
	get_tree().root.add_child(start)
	get_tree().current_scene = start
	await get_tree().process_frame
	start.play_button.pressed.emit()
	start.slot_buttons[0].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var interview := get_tree().current_scene as InterviewScreen
	assert_object(interview).is_not_null()

	# Play the interview as a new game would: best answer to every question.
	for question: InterviewQuestion in interview.questions:
		var best: Button = null
		var best_score := -999
		for i in question.answers.size():
			if question.answers[i].score > best_score:
				best_score = question.answers[i].score
				best = interview.answers_container.get_child(interview.answers_container.get_child_count() - question.answers.size() + i)
		best.pressed.emit()
	assert_int(interview.last_outcome).is_equal(InterviewManager.Outcome.HIRED)
	assert_bool(InterviewManager.is_on_probation).is_false()
	assert_str(interview.continue_button.text).is_equal("Start Shift")

	interview.continue_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(get_tree().current_scene.scene_file_path).is_equal(TELLER_ROOM_SCENE)

func test_probation_outcome_explains_the_terms() -> void:
	room.free()
	var scene: PackedScene = load(INTERVIEW_SCENE)
	var interview := scene.instantiate() as InterviewScreen
	get_tree().root.add_child(interview)
	get_tree().current_scene = interview
	await get_tree().process_frame
	interview._show_outcome(InterviewManager.Outcome.HIRED_ON_PROBATION)
	assert_str(interview.outcome_message_label.text).contains("Complete 3 teller shifts without a disciplinary report")
	assert_str(interview.outcome_message_label.text).contains("2 reports end your employment")

# --- probation -------------------------------------------------------------------

func test_probation_fires_at_two_reports() -> void:
	start_probation()
	assert_str(hud_text(hud.reports_label)).is_equal("Reports: 0 / 2")
	assert_str(hud_text(hud.probation_label)).is_equal("Probation — 0 of 3 clean shifts")

	earn_report()
	assert_bool(ReportManager.is_terminated).is_false()
	assert_str(letters.title_label.text).is_equal("Written Warning — Report 1 of 2")
	assert_str(letters.body_label.text).contains("This is report 1 of 2. Reaching 2 reports will result in termination.")
	assert_str(letters.body_label.text).contains("You are on probation, so 2 reports end your employment instead of the usual 3.")
	assert_str(hud_text(hud.reports_label)).is_equal("Reports: 1 / 2")
	acknowledge_letters()

	earn_report()
	assert_bool(ReportManager.is_terminated).is_true()
	assert_bool(letters.is_full_screen_letter_shown()).is_true()
	assert_str(letters.body_label.text).contains("Following 2 disciplinary reports during your probation period")

func test_normal_hire_keeps_three_reports() -> void:
	assert_int(InterviewManager.resolve_outcome(InterviewManager.HIRE_THRESHOLD, false)).is_equal(InterviewManager.Outcome.HIRED)
	assert_bool(InterviewManager.is_on_probation).is_false()
	assert_str(hud_text(hud.probation_label)).is_equal("")
	assert_str(hud_text(hud.reports_label)).is_equal("Reports: 0 / 3")

	earn_report()
	assert_str(letters.title_label.text).is_equal("Written Warning — Report 1 of 3")
	assert_str(letters.body_label.text).not_contains("probation")
	acknowledge_letters()
	earn_report()
	assert_bool(ReportManager.is_terminated).is_false()
	acknowledge_letters()
	earn_report()
	assert_bool(ReportManager.is_terminated).is_true()
	assert_str(letters.body_label.text).not_contains("probation")

func test_three_clean_shifts_end_probation_with_a_letter() -> void:
	start_probation()
	play_teller_shift()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(1)
	assert_str(hud_text(hud.probation_label)).is_equal("Probation — 1 of 3 clean shifts")
	play_teller_shift()
	assert_str(hud_text(hud.probation_label)).is_equal("Probation — 2 of 3 clean shifts")
	assert_bool(letters.visible).is_false()

	play_teller_shift()
	assert_bool(InterviewManager.is_on_probation).is_false()
	assert_bool(letters.visible).is_true()
	assert_str(letters.title_label.text).is_equal("Probation Complete")
	assert_str(letters.from_label.text).is_equal("From: Branch Manager")
	assert_str(letters.body_label.text).contains("You've completed your probation period")
	assert_str(letters.body_label.text).contains("the usual limit of 3 reports applies")
	acknowledge_letters()

	# Back to the normal limit.
	assert_str(hud_text(hud.probation_label)).is_equal("")
	assert_str(hud_text(hud.reports_label)).is_equal("Reports: 0 / 3")
	earn_report()
	acknowledge_letters()
	earn_report()
	assert_bool(ReportManager.is_terminated).is_false()

func test_a_report_resets_the_clean_shift_count() -> void:
	start_probation()
	play_teller_shift()
	play_teller_shift()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(2)

	# A report in the third shift: the count starts over and that shift
	# doesn't count either.
	play_teller_shift(true)
	assert_bool(InterviewManager.is_on_probation).is_true()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(0)
	assert_str(hud_text(hud.probation_label)).is_equal("Probation — 0 of 3 clean shifts")

	play_teller_shift()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(1)
	assert_bool(InterviewManager.is_on_probation).is_true()

func test_career_reset_clears_probation() -> void:
	start_probation()
	play_teller_shift()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(1)
	CareerReset.reset_all()
	assert_bool(InterviewManager.is_on_probation).is_false()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(0)
	assert_int(ReportManager.report_limit()).is_equal(ReportManager.REPORTS_FOR_TERMINATION)

## Branch Managers aren't subject to reports, so promotion ends probation
## (without the probation letter).
func test_promotion_ends_probation() -> void:
	start_probation()
	XPManager._grant_branch_manager()
	assert_bool(InterviewManager.is_on_probation).is_false()
	acknowledge_letters()
	assert_str(letters.title_label.text).is_not_equal("Probation Complete")
