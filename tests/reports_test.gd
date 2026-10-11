extends "res://tests/support/teller_room_suite.gd"

## Disciplinary reports: every ReportManager.MISTAKES_PER_REPORT mistaken
## customers = one report; REPORTS_FOR_TERMINATION reports = termination;
## "Apply for a new job" wipes the whole career.

## Serves `customer` wrongly and walks away: graded as a mistake, then the
## customer leaves upset.
func _botch(customer: CustomerNPC) -> void:
	open_desk()
	deposit(customer.intent_amount / 2.0)
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

func test_termination_at_six_mistakes_and_full_reset_on_new_job() -> void:
	var letters: DisciplineLetterScreen = room.get_node("UI/DisciplineLetterScreen")
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
	assert_str(letters.action_button.text).is_equal("Apply for a new job")

	# Career progress to be wiped.
	assert_int(ScoreManager.total_score).is_not_equal(0)
	assert_int(HistoryManager.records.size()).is_greater(0)
	assert_int(AccountManager.get_accounts().size()).is_greater(1)

	letters.action_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

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
	assert_str(get_tree().current_scene.scene_file_path).is_equal(DisciplineLetterScreen.INTERVIEW_SCENE)

## Clicks through any written-warning letters so play can continue.
func _acknowledge_letters(letters: DisciplineLetterScreen) -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()
