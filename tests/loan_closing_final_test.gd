extends "res://tests/support/loan/loan_suite.gd"

## Part 4 of the closing step: switching it on. The closings waiting list on the
## Loan Officer screen, tests that run with the game's own default (closings
## on), the edge cases through the real flow (promotion with a closing open,
## demotion, going home early, a Teller day, a mid-day quit and replay, four
## slots with a closing, a returned file and new applicants), old saves, the
## byte-for-byte save of a career that never closes, and fair lending.

const SEED := 987654
const PAY_STUB := LoanRequirements.Item.PAY_STUB
const LOAN := PlayerShift.Role.LOAN_OFFICER
const TELLER := PlayerShift.Role.TELLER
const Problem := LoanClosing.Problem
const OLD_SAVES := "res://tests/data/old_saves/"

var lo: LoanOfficerScreen
var review: LoanReviewScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	lo = room.loan_officer_screen
	review = lo.loan_review_screen
	for worker in room.loan_desk_workers:
		worker.active = false
	XPManager.is_loan_officer_unlocked = true
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## The game's own setting: closings on.
func use_the_game_default() -> void:
	LoanConfig.closings_enabled = LoanConfig.CLOSINGS_ENABLED_DEFAULT

func approved(applicant: String = "Closing Test", purpose: String = "Auto") -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = applicant
	application.loan_purpose = purpose
	application.requested_amount = 200000.0 if purpose == "Home" else 20000.0
	application.annual_income = 72000.0
	application.monthly_housing_payment = 1200.0
	application.monthly_debt_payments = 300.0
	application.existing_debt = 9000.0
	application.credit_score = 720
	application.employment_months = 60
	application.documents_issued = true
	application.decision = LoanApplication.DecisionType.APPROVE
	application.decision_amount = application.requested_amount
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## A closing for `application`, due today, with a loan number reserved; with the
## problem asked for (-1: the career's next number).
func due_closing(application: LoanApplication, problem: int = -1) -> LoanClosing:
	var closing: LoanClosing
	if problem < 0:
		closing = LoanRole.closings.open(application, GameClock.day, LoanDeskManager.career_seed, LoanBookManager.reserve_loan_id())
	else:
		var number := maxi(2, LoanRole.closings.next_number)
		var reserved := LoanBookManager.reserve_loan_id()
		closing = LoanClosing.create(application, GameClock.day, number, LoanDeskManager.career_seed, reserved)
		while closing.problem != problem:
			number += 1
			closing = LoanClosing.create(application, GameClock.day, number, LoanDeskManager.career_seed, reserved)
		LoanRole.closings.closings.append(closing)
		LoanRole.closings.next_number = number + 1
	closing.due_day = GameClock.day
	return closing

func later_closing(application: LoanApplication, days_ahead: int) -> LoanClosing:
	var closing := LoanRole.closings.open(application, GameClock.day, LoanDeskManager.career_seed, LoanBookManager.reserve_loan_id())
	closing.due_day = GameClock.day + days_ahead
	return closing

func filed_application(missing: Array[int]) -> LoanApplication:
	var application := LoanDeskManager.generate_application()
	application.loan_purpose = "Personal"
	application.collateral_kind = LoanApplication.Collateral.NONE
	application.late_30_days = 0
	application.late_60_days = 0
	application.late_90_days = 0
	application.collections = 0
	application.documents_issued = true
	application.doc_problem = LoanApplication.DocProblem.NONE
	application.id_problem = IdCard.Problem.NONE
	application.id_presented = true
	application.has_pay_stub = not missing.has(PAY_STUB)
	application.has_statement = true
	if missing.has(PAY_STUB):
		application.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	return application

func request_file(application: LoanApplication, items: Array[int], returns_on: int) -> LoanFile:
	var file := LoanRole.request_documents(application, items)
	assert_object(file).is_not_null()
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = returns_on
	file.quality = LoanFile.Quality.COMPLETE
	file.short_item = -1
	file.wrong_item = -1
	return file

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			application.documents_issued = true
			return application
	return null

## Opens `application` through the desk, verifies, checks credit and decides.
func decide(application: LoanApplication, decision: LoanApplication.DecisionType) -> void:
	LoanDeskManager.player_queue.push_front(application)
	lo.applications_reviewed = 0
	lo.review_next_button.pressed.emit()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	match decision:
		LoanApplication.DecisionType.APPROVE:
			review.approve_button.pressed.emit()
		_:
			review.reject_button.pressed.emit()
			review.reason_checks[LoanApplication.DenialReason.TOTAL_DTI].button_pressed = true
			review.submit_denial_button.pressed.emit()
	review.close_button.pressed.emit()

func clock_in_loan() -> void:
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()

func go_home_from_the_loan_desk() -> void:
	to_closing()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	lo.shift_summary_done_button.pressed.emit()
	lo.hide_screen()

func next_day() -> void:
	await run_end_of_day()
	var eod := room.end_of_day_screen
	eod.next_day_button.pressed.emit()
	if eod.is_closure_shown():
		eod.next_day_button.pressed.emit()

func acknowledge_letters() -> void:
	for i in 6:
		await get_tree().process_frame
		while room.letter_screen.visible:
			room.letter_screen.action_button.pressed.emit()

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

func figures_of(closing: LoanClosing) -> Dictionary:
	var data := closing.save_data()
	data.erase("application")
	return data

# --- with the game's own default (closings on) --------------------------------------------

func test_the_game_default_is_on_and_a_players_approval_opens_a_closing() -> void:
	assert_bool(LoanConfig.CLOSINGS_ENABLED_DEFAULT).is_true()
	use_the_game_default()
	assert_bool(LoanConfig.closings_enabled).is_true()
	decide(sample("Elena Petrova"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_str(LoanRole.closings.closings[0].application.applicant_name).is_equal("Elena Petrova")

func test_with_the_game_default_the_three_teaching_cases_still_book_at_once() -> void:
	use_the_game_default()
	decide(sample("Maria Chen"), LoanApplication.DecisionType.APPROVE)
	decide(sample("Marcus Webb"), LoanApplication.DecisionType.REJECT)
	decide(sample("Angela Reyes"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanBookManager.book.size()).is_equal(2)
	assert_int(LoanRole.closings.count()).is_equal(0)
	# And so a career that only ever did the teaching cases saves what main saved.
	assert_bool(LoanRole.closings.has_data()).is_false()
	assert_bool(LoanRole.save_data().has(LoanRole.CLOSINGS_KEY)).is_false()
	assert_dict(LoanRole.save_data()).is_empty()

func test_every_old_save_loads_with_no_closings_under_the_game_default() -> void:
	use_the_game_default()
	var loaded := 0
	for file_name in DirAccess.get_files_at(OLD_SAVES):
		if not file_name.ends_with(".json"):
			continue
		var saved := SaveGame.read_file(OLD_SAVES + file_name)
		assert_int(saved.status).override_failure_message(file_name).is_equal(SaveGame.Status.OK)
		due_closing(approved("Left Over"))
		SaveGame.restore(saved.career)
		assert_int(LoanRole.closings.count()).override_failure_message(file_name).is_equal(0)
		assert_int(LoanRole.closings.next_number).is_equal(1)
		assert_dict(LoanRole.save_data()).override_failure_message(file_name).is_empty()
		loaded += 1
	assert_int(loaded).is_greater_equal(5)

func test_a_career_that_never_closes_saves_nothing_about_closings_whatever_the_switch() -> void:
	for enabled: bool in [true, false]:
		LoanConfig.closings_enabled = enabled
		CareerReset.reset_all()
		var career := SaveGame.capture()
		var loan := SaveGame.dict_of(SaveGame.dict_of(career, "roles"), "loan")
		assert_dict(loan).is_empty()

# --- the closings waiting list ------------------------------------------------------------

func test_the_list_says_who_what_how_much_and_when_and_marks_the_due_ones() -> void:
	GameClock.day = 8
	var due_one := due_closing(approved("Due Dora", "Auto"))
	due_one.due_day = 7
	var later := later_closing(approved("Later Lee", "Home"), 3)
	var rows := LoanOfficerScreen.closings_rows(8)
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0]).starts_with("Due Dora · auto loan · $20,000: ready to close\nClose by ")
	assert_str(rows[0]).ends_with(" (Loan Officer days)")
	assert_str(rows[1]).is_equal("Later Lee · home loan · $200,000\nDue %s" % BankCalendar.short_text(later.closing_date()))
	assert_bool(due_one.is_due(8)).is_true()
	# Nothing waiting: no rows.
	LoanRole.closings.close(due_one)
	LoanRole.closings.close(later)
	assert_array(LoanOfficerScreen.closings_rows(8)).is_empty()

func test_the_list_never_shows_whether_a_closing_has_a_problem() -> void:
	GameClock.day = 8
	var texts: Array[String] = []
	for kind: int in [Problem.NONE, Problem.TERMS, Problem.EXPIRED_ID, Problem.NO_SIGNATURE, Problem.NEW_DEBT]:
		CareerReset.reset_all()
		LoanRole.closings.next_number = 2
		var closing := due_closing(approved("Same Name"), kind)
		assert_int(closing.problem).is_equal(kind)
		var rows := LoanOfficerScreen.closings_rows(8)
		texts.append("\n".join(rows))
		for word: String in ["problem", "mismatch", "expired", "signature", "debt", "wrong"]:
			assert_str(rows[0].to_lower()).not_contains(word)
	for i in range(1, texts.size()):
		assert_str(texts[i]).is_equal(texts[0])

func test_the_list_shows_on_the_loan_officer_screen_and_the_strings_are_unchanged() -> void:
	GameClock.day = 8
	due_closing(approved("Screen Test"))
	room._on_loan_officer_desk_interacted()
	assert_bool(lo.closings_vbox.visible).is_true()
	assert_str(lo.closings_label.text).starts_with("Screen Test · auto loan · $20,000: ready to close")
	assert_bool(lo.files_vbox.visible).is_false()
	# Beside the files list when there are files too.
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day + 4)
	lo.hide_screen()
	room._on_loan_officer_desk_interacted()
	assert_bool(lo.closings_vbox.visible).is_true()
	assert_bool(lo.files_vbox.visible).is_true()
	assert_str(LoanSlotAdapter.STATUS_TEXT % [0, 1]).is_equal("Application: 0 / 1")
	assert_str(LoanSlotAdapter.REPORT_TEXT % 2).is_equal("Applications decided: 2")
	lo.hide_screen()
	# None waiting: the list is gone.
	LoanRole.closings.closings.clear()
	room._on_loan_officer_desk_interacted()
	assert_bool(lo.closings_vbox.visible).is_false()
	lo.hide_screen()

func test_the_screen_with_many_closings_and_three_files_fits_the_window() -> void:
	GameClock.day = 8
	for i in 3:
		request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day + 4)
	for i in 14:
		var closing := due_closing(approved("Closing Number %d" % i, "Home" if i % 2 == 0 else "Auto"))
		if i % 3 == 0:
			closing.due_day = GameClock.day + 2
	room._on_loan_officer_desk_interacted()
	await frames(6)
	var problems := layout_problems(lo.main_panel)
	problems.append_array(controls_line_problems(lo.main_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	assert_float(lo.main_panel.size.y).is_less_equal(LoanOfficerScreen.MAX_PANEL_HEIGHT + 1.0)
	# The list scrolls inside what is left, and at least one closing shows.
	assert_float(lo.closings_scroll.custom_minimum_size.y).is_greater_equal(LoanOfficerScreen.CLOSINGS_ROW_HEIGHT - 1.0)
	assert_float(lo.closings_scroll.custom_minimum_size.y).is_less(lo.closings_label.get_minimum_size().y)
	lo.hide_screen()

func test_a_few_closings_show_whole_without_scrolling() -> void:
	GameClock.day = 8
	due_closing(approved("One"))
	later_closing(approved("Two"), 2)
	room._on_loan_officer_desk_interacted()
	await frames(6)
	assert_float(lo.closings_scroll.custom_minimum_size.y).is_equal_approx(lo.closings_label.get_minimum_size().y, 1.0)
	assert_array(layout_problems(lo.main_panel)).is_empty()
	lo.hide_screen()

# --- the edge cases, through the real flow -----------------------------------------------------

func test_a_promotion_with_closings_open_has_the_staff_stop_and_fund_them() -> void:
	use_the_game_default()
	var clean := due_closing(approved("Open Clean"))
	var bad := due_closing(approved("Open Bad"), Problem.NO_SIGNATURE)
	assert_bool(bad.has_problem()).is_true()
	LoanRole.note_role(GameClock.day, LOAN)
	var score_before := score_and_reputation()
	# The real promotion: enough XP and Reputation, off shift.
	ReputationManager.reputation = 60
	var reputation_before := ReputationManager.reputation
	XPManager.add_shift_xp(150)
	await acknowledge_letters()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_str(LoanBookManager.book[0].borrower).is_equal("Open Clean")
	assert_int(LoanBookManager.book[0].loan_id).is_equal(clean.loan_id)
	assert_int(LoanBookManager.book[0].made_day).is_equal(BusinessDay.stats_day)
	# No Score or Reputation for it, and the End of Day says so.
	assert_int(ScoreManager.total_score).is_equal(score_before.x)
	assert_int(ReputationManager.reputation).is_equal(reputation_before)
	assert_array(LoanRole.closings.summary_lines(GameClock.day)).is_equal(["Closings passed to your staff: 1 funded, 1 stopped"])
	assert_array(LoanBookManager.summary_lines(true)).contains(["Closings passed to your staff: 1 funded, 1 stopped"])
	assert_dict(LoanRole.role_days).is_empty()

func test_a_demotion_starts_clean_after_a_promotion_with_closings() -> void:
	use_the_game_default()
	due_closing(approved("Before Promotion"))
	ReputationManager.reputation = 60
	XPManager.add_shift_xp(150)
	await acknowledge_letters()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	XPManager.demote_branch_manager()
	await acknowledge_letters()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_dict(LoanRole.role_days).is_empty()
	assert_array(LoanRole.closings.summary_lines(GameClock.day + 5)).is_empty()
	# A new closing after the demotion works, and its number goes on.
	var next := LoanRole.closings.open(approved("After Demotion"), GameClock.day, LoanDeskManager.career_seed, LoanBookManager.reserve_loan_id())
	assert_int(next.number).is_equal(2)

func test_going_home_early_with_a_closing_due_keeps_it_due_and_only_loan_officer_days_lapse_it() -> void:
	use_the_game_default()
	var closing := due_closing(approved("Home Early"))
	var due_day := closing.due_day
	assert_int(due_day).is_equal(GameClock.day)
	var start := score_and_reputation()
	# The due day itself, and then days 2, 3 and 4 as a Loan Officer who goes home
	# early each time: the closing stays due through all of them.
	for index in 4:
		clock_in_loan()
		go_home_from_the_loan_desk()
		assert_int(LoanRole.role_days[GameClock.day]).is_equal(LOAN)
		assert_int(LoanRole.closings.count()).override_failure_message("day %d" % GameClock.day).is_equal(1)
		assert_bool(LoanRole.closings.due_closings(GameClock.day).has(closing)).is_true()
		await next_day()
		if index < 3:
			assert_int(LoanRole.closings.count()).override_failure_message("opening of day %d" % GameClock.day).is_equal(1)
			assert_vector(score_and_reputation()).is_equal(start)
	# Opening of day 5: days 2, 3 and 4 were Loan Officer days after the due day.
	assert_int(GameClock.day).is_equal(due_day + 4)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(start + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)
	assert_int(LoanBookManager.book.size()).is_equal(0)

func test_a_closing_due_on_a_teller_day_waits() -> void:
	use_the_game_default()
	var closing := due_closing(approved("Teller Day"))
	var start := score_and_reputation()
	for index in 4:
		# A Teller's day: the closing waits, whatever the days since it was due.
		PlayerShift.report_clock_in(TELLER)
		to_closing()
		PlayerShift.report_clock_out(TELLER)
		assert_int(LoanRole.role_days[GameClock.day]).is_equal(TELLER)
		await next_day()
		assert_int(LoanRole.closings.count()).override_failure_message("opening of day %d" % GameClock.day).is_equal(1)
	assert_bool(LoanRole.closings.due_closings(GameClock.day).has(closing)).is_true()
	assert_int(closing.loan_officer_days_since_due(GameClock.day, LoanRole.role_days)).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(start)
	# Back as a Loan Officer, it is the first application on the desk.
	clock_in_loan()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_object(LoanDeskManager.current_player_application()).is_same(closing.application)

func test_a_mid_day_quit_and_replay_gives_the_same_problem_and_the_same_loan_number() -> void:
	use_the_game_default()
	# A career whose next closing number is one that has a problem.
	var probe := approved("Probe")
	var number := 2
	while not LoanClosing.create(probe, 1, number, LoanDeskManager.career_seed).has_problem():
		number += 1
	LoanRole.closings.next_number = number
	# The saved career at the start of the day (the only place a career is saved).
	var saved := through_json(SaveGame.capture())
	clock_in_loan()
	decide(sample("David Okafor"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanRole.closings.count()).is_equal(1)
	var first := LoanRole.closings.closings[0]
	var first_figures := figures_of(first)
	assert_int(first.number).is_equal(number)
	assert_bool(first.has_problem()).is_true()
	# Quit mid-day: the day restarts from the save, and the approval is made again.
	CareerReset.reset_all()
	SaveGame.restore(saved)
	assert_int(LoanRole.closings.count()).is_equal(0)
	XPManager.is_loan_officer_unlocked = true
	decide(sample("David Okafor"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanRole.closings.count()).is_equal(1)
	var second := LoanRole.closings.closings[0]
	assert_dict(figures_of(second)).is_equal(first_figures)
	assert_int(second.loan_id).is_equal(first.loan_id)
	assert_int(second.problem).is_equal(first.problem)
	assert_int(LoanBookManager.next_loan_id).is_equal(first.loan_id + 1)

func test_a_due_closing_a_returned_file_and_new_applicants_across_four_slots() -> void:
	use_the_game_default()
	clock_in_loan()
	continue_to_slot(DaySchedule.SLOT_9AM)
	var adapter := loan_slot_adapter()
	var closing := due_closing(approved("Slot Closing"))
	var file_application := filed_application([PAY_STUB])
	request_file(file_application, [PAY_STUB] as Array[int], GameClock.day)
	var pile_first := LoanDeskManager.player_queue[0]
	var pile_second := LoanDeskManager.player_queue[1]
	var expected: Array[LoanApplication] = [closing.application, file_application, pile_first, pile_second]
	var slots: Array[StringName] = [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]
	var names: Array[String] = ["9 AM", "11 AM", "1 PM", "3 PM"]
	for index in 4:
		continue_to_slot(slots[index])
		assert_str(adapter.status_text()).is_equal("Application: 0 / 1")
		assert_object(LoanDeskManager.current_player_application()).override_failure_message("slot %s" % names[index]).is_same(expected[index])
		var reviewed_at_start := lo.applications_reviewed
		room._on_loan_officer_desk_interacted()
		lo.review_next_button.pressed.emit()
		match index:
			0:
				assert_bool(review.is_closing()).is_true()
				review.closing_panel.check_button.pressed.emit()
				review.closing_panel.fund_button.pressed.emit()
			1:
				assert_bool(review.is_closing()).is_false()
				review.verify_documents_button.pressed.emit()
				review.run_credit_check_button.pressed.emit()
				review.approve_button.pressed.emit()
			_:
				review.verify_documents_button.pressed.emit()
				review.run_credit_check_button.pressed.emit()
				review.reject_button.pressed.emit()
				review.reason_checks[LoanApplication.DenialReason.TOTAL_DTI].button_pressed = true
				review.submit_denial_button.pressed.emit()
		assert_int(lo.applications_reviewed - reviewed_at_start).is_equal(1)
		assert_str(adapter.status_text()).is_equal("Application: 1 / 1")
		review.close_button.pressed.emit()
		lo.hide_screen()
		await frames(3)
		assert_bool(DayFlow.is_between_slots()).override_failure_message("%s slot didn't end" % names[index]).is_true()
		assert_str(slot_card().done_label.text).is_equal("%s slot done\nApplications decided: 1" % names[index])
		# The pile stays full throughout.
		assert_int(LoanDeskManager.player_queue.size()).is_equal(LoanDeskManager.queue_size())
	assert_int(lo.applications_reviewed).is_equal(4)
	# The closing was funded (booked), the returned file approved (a closing of its
	# own, due later), the two others rejected.
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_object(LoanRole.closings.closings[0].application).is_same(file_application)
	assert_int(LoanRole.pipeline.files.size()).is_equal(0)

# --- fair lending ------------------------------------------------------------------------------

func test_no_protected_characteristic_is_stored_by_a_closing() -> void:
	var closing := due_closing(approved("Fair Test"), Problem.NEW_DEBT)
	var keys: Array[String] = []
	for key: String in closing.save_data():
		keys.append(key)
	for key: String in SaveGame.dict_of(closing.save_data(), "application"):
		keys.append(key)
	for key: String in SaveGame.dict_of(LoanRole.save_data(), LoanRole.CLOSINGS_KEY):
		keys.append(key)
	for forbidden: String in ["age", "birth", "sex", "gender", "race", "ethnic", "religio", "nation", "origin", "marital", "married", "citizen", "disab"]:
		for key in keys:
			assert_str(key).override_failure_message("%s looks like a protected characteristic (%s)" % [key, forbidden]).not_contains(forbidden)
	# What a closing keeps (besides its application): terms, days, numbers, the
	# problem and the paperwork, nothing about the person.
	var kept: Array[String] = []
	for key: String in closing.save_data():
		if key != "application":
			kept.append(key)
	kept.sort()
	assert_array(kept).is_equal([
		"approval_day", "approved_amount", "approved_payment", "approved_rate", "approved_term", "collateral_kind", "collateral_value",
		"documents_ok", "due_day", "id_expiry_date", "kind", "loan_id", "new_debt_payment", "number",
		"paper_amount", "paper_payment", "paper_rate", "paper_term", "problem", "risk_tier", "signed", "terms_field",
	])

func test_the_list_and_the_screen_never_read_the_name_or_the_look() -> void:
	GameClock.day = 8
	var one := approved("Alpha One")
	one.applicant_look = 1
	var two := approved("Beta Two")
	two.applicant_look = 9
	var first := due_closing(one)
	var second := due_closing(two)
	var rows_one := LoanOfficerScreen.closings_rows(8)
	assert_int(rows_one.size()).is_equal(2)
	# The same rows but for the name.
	assert_str(rows_one[0].replace("Alpha One", "NAME")).is_equal(rows_one[1].replace("Beta Two", "NAME"))
	assert_bool(first.number < second.number).is_true()

# --- the demo helpers (F1 and F2; no new debug keys) -------------------------------------------------

func test_f2_unlocks_the_loan_officer_without_promoting_and_leaves_closings_alone() -> void:
	use_the_game_default()
	XPManager.is_loan_officer_unlocked = false
	room.debug_cheats_enabled = true
	due_closing(approved("F2 Test"))
	room.apply_debug_key(KEY_F2)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_int(LoanBookManager.book.size()).is_equal(0)

func test_f1_promotes_and_passes_the_open_closings_to_the_staff() -> void:
	use_the_game_default()
	room.debug_cheats_enabled = true
	var clean := due_closing(approved("F1 Clean"))
	due_closing(approved("F1 Bad"), Problem.EXPIRED_ID)
	room.apply_debug_key(KEY_F1)
	await acknowledge_letters()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_int(LoanBookManager.book[0].loan_id).is_equal(clean.loan_id)
	assert_array(LoanRole.closings.summary_lines(GameClock.day)).is_equal(["Closings passed to your staff: 1 funded, 1 stopped"])

## The fastest way to see a closing: approve a (non-teaching) personal loan, go
## home early, start the next day, and clock in as a Loan Officer.
func test_the_fastest_way_to_see_a_closing() -> void:
	use_the_game_default()
	room.debug_cheats_enabled = true
	XPManager.is_loan_officer_unlocked = false
	room.apply_debug_key(KEY_F2)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	clock_in_loan()
	continue_to_slot(DaySchedule.SLOT_9AM)
	# A personal loan (Noah Kim) approved at the desk: a closing, due tomorrow.
	decide(sample("Noah Kim"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanRole.closings.count()).is_equal(1)
	var closing := LoanRole.closings.closings[0]
	assert_int(closing.due_day).is_equal(GameClock.day + 1)
	assert_int(LoanBookManager.book.size()).is_equal(0)
	lo.hide_screen()
	go_home_from_the_loan_desk()
	await next_day()
	# Clocked in as a Loan Officer, it is the first application of the 9 AM slot.
	clock_in_loan()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_object(LoanDeskManager.current_player_application()).is_same(closing.application)
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	assert_bool(review.is_closing()).is_true()
	review.close_button.pressed.emit()
	lo.hide_screen()
