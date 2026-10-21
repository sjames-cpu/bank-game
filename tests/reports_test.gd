extends "res://tests/support/teller_room_suite.gd"

## Disciplinary reports: every ReportManager.MISTAKES_PER_REPORT mistaken
## customers = one report; REPORTS_FOR_TERMINATION reports = termination;
## the termination letter's button wipes the whole career (game over with
## the interview off, "Apply for a new job" with it on).

## Serves `customer` wrongly and walks away: graded as a mistake, then the
## customer leaves upset.
func _botch(customer: CustomerNPC) -> void:
	open_desk()
	deposit(customer.intent_amount_cents / 200.0)
	complete()
	close_desk()

func test_report_at_two_mistaken_customers() -> void:
	clock_in()
	_botch(spawn(ShiftTransaction.Type.DEPOSIT, 100.0))
	assert_int(ReportManager.get_report_count()).is_equal(0)
	_botch(spawn(ShiftTransaction.Type.DEPOSIT, 100.0))
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_str(ReportManager.reports[0].reason).is_not_empty()

func test_fixed_mistake_still_counts_toward_a_report() -> void:
	clock_in()
	for i in ReportManager.MISTAKES_PER_REPORT:
		spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
		open_desk()
		deposit(50)
		complete()
		deposit(50)
		complete()
		close_desk()
	assert_int(ReportManager.get_report_count()).is_equal(1)

## Plays to a termination (six mistaken customers over two shifts) and
## checks the letter is up with career progress still there to be wiped.
func _get_fired(letters: DisciplineLetterScreen) -> void:
	# Shift 1: four mistaken customers -> two reports.
	clock_in()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		_botch(spawn(ShiftTransaction.Type.DEPOSIT, 100.0))
		_acknowledge_letters(letters)
	assert_int(ReportManager.get_report_count()).is_equal(2)
	assert_bool(ReportManager.is_terminated).is_false()
	assert_bool(clock_out()).is_true()
	close_desk()

	# Shift 2: the fifth and sixth mistakes -> third report -> fired.
	clock_in()
	_botch(spawn(ShiftTransaction.Type.DEPOSIT, 100.0))
	assert_bool(ReportManager.is_terminated).is_false()
	_botch(spawn(ShiftTransaction.Type.DEPOSIT, 100.0))
	assert_int(ReportManager.get_report_count()).is_equal(ReportManager.REPORTS_FOR_TERMINATION)
	assert_bool(ReportManager.is_terminated).is_true()
	assert_bool(letters.visible).is_true()

	# Career progress to be wiped.
	assert_int(ScoreManager.total_score).is_not_equal(0)
	assert_int(HistoryManager.records.size()).is_greater(0)
	assert_int(AccountManager.get_accounts().size()).is_greater(1)

## Everything a termination's button wipes, whichever way the interview is set.
func _assert_career_wiped() -> void:
	assert_int(ScoreManager.total_score).is_equal(0)
	assert_int(ReputationManager.reputation).is_equal(ReputationManager.STARTING_REPUTATION)
	assert_int(XPManager.total_xp).is_equal(0)
	assert_bool(XPManager.is_loan_officer_unlocked).is_false()
	assert_int(ReportManager.get_report_count()).is_equal(0)
	assert_bool(ReportManager.is_terminated).is_false()
	assert_int(HistoryManager.records.size()).is_equal(0)
	assert_int(AccountManager.get_accounts().size()).is_equal(1)
	assert_bool(InterviewManager.is_on_probation).is_false()
	assert_bool(get_tree().paused).is_false()

## With the interview off, being fired is game over: the letter says so, and
## its button wipes the career and opens the start screen, which (with no
## save left) offers only New Game.
func test_termination_with_the_interview_off_is_game_over() -> void:
	use_interview_setting(false)
	var letters: DisciplineLetterScreen = room.get_node("UI/DisciplineLetterScreen")
	_get_fired(letters)
	assert_str(letters.action_button.text).is_equal(DisciplineLetterScreen.GAME_OVER_BUTTON_TEXT)
	assert_str(letters.body_label.text).contains(DisciplineLetterScreen.GAME_OVER_TEXT)

	letters.action_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_career_wiped()
	var start := get_tree().current_scene as StartScreen
	assert_object(start).is_not_null()
	assert_bool(start.menu_panel.visible).is_true()
	assert_bool(start.continue_button.visible).is_false()
	assert_bool(start.new_game_button.visible).is_true()
	assert_str(start.summary_label.text).is_equal(StartScreen.NO_SAVE_TEXT)

## With the interview on, "Apply for a new job" wipes the career and loads
## the interview, as before the switch existed.
func test_termination_with_the_interview_on_applies_for_a_new_job() -> void:
	use_interview_setting(true)
	var letters: DisciplineLetterScreen = room.get_node("UI/DisciplineLetterScreen")
	_get_fired(letters)
	assert_str(letters.action_button.text).is_equal(DisciplineLetterScreen.NEW_JOB_BUTTON_TEXT)
	assert_str(letters.body_label.text).not_contains(DisciplineLetterScreen.GAME_OVER_TEXT)

	letters.action_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_career_wiped()
	assert_str(get_tree().current_scene.scene_file_path).is_equal(DisciplineLetterScreen.INTERVIEW_SCENE)

## Clicks through any written-warning letters so play can continue.
func _acknowledge_letters(letters: DisciplineLetterScreen) -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()
