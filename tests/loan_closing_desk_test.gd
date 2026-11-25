extends "res://tests/support/loan/loan_suite.gd"

## Part 3 of the closing step: the desk. With closings on
## (LoanConfig.closings_enabled) a due closing takes the desk before a returned
## file and the pile, as the slot's one application; the review screen shows
## the closing panel in place of the worksheet columns (the frozen approved
## terms, then after the check the paperwork, with nothing marked); Fund the
## loan waits for the check; Fund and Stop use the part 2 points; the first
## closing explains itself; the applicant has lines of their own; and every
## state fits the window. With the switch off nothing changes (the existing
## loan tests run unchanged).

const SEED := 987654
const PAY_STUB := LoanRequirements.Item.PAY_STUB
const Problem := LoanClosing.Problem

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
	LoanConfig.closings_enabled = true
	XPManager.is_loan_officer_unlocked = true

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func approved(applicant: String = "Closing Test", purpose: String = "Auto", counter: bool = false) -> LoanApplication:
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
	application.decision = LoanApplication.DecisionType.COUNTER_OFFER if counter else LoanApplication.DecisionType.APPROVE
	application.decision_amount = application.requested_amount - 2000.0 if counter else application.requested_amount
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## A closing for `application`, due today, with a loan number reserved: with the
## problem asked for (-1: none; Problem.NONE is clean), else the career's next
## number (so number 1 is clean and explains itself).
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

## A closing that isn't the career's first (so no explanation).
func second_closing(application: LoanApplication, problem: int = Problem.NONE) -> LoanClosing:
	LoanRole.closings.next_number = maxi(LoanRole.closings.next_number, 2)
	return due_closing(application, problem)

func filed_application(missing: Array[int]) -> LoanApplication:
	var application := LoanDeskManager.generate_application()
	application.loan_purpose = "Personal"
	application.collateral_kind = LoanApplication.Collateral.NONE
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

func loan_day_at_9am() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

func speech(applicant: LoanApplicantNPC) -> String:
	return applicant._speech_label.text

## `text` with its dates, numbers and the signature value masked: what is left
## is the shape every closing's screen has, whatever its paperwork says.
func masked_shape(text: String) -> String:
	var masked := text.replace("not signed", "signed")
	for pattern: Array in [["[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}", "DATE"], ["[A-Z][a-z]{2} [0-9]{1,2} [A-Z][a-z]{2}", "DAY"], ["[0-9][0-9,.]*", "#"]]:
		var find: String = pattern[0]
		var replacement: String = pattern[1]
		masked = RegEx.create_from_string(find).sub(masked, replacement, true)
	return masked

func panel_text() -> String:
	var panel := review.closing_panel
	var parts: Array[String] = [panel.name_label.text, panel.subtitle_label.text]
	if panel.explanation_label.visible:
		parts.append(panel.explanation_label.text)
	parts.append_array([panel.approved_title_label.text, panel.approved_label.text, panel.paperwork_title_label.text, panel.paperwork_label.text])
	for button: Button in [panel.check_button, panel.fund_button, panel.stop_button]:
		if button.visible:
			parts.append(button.text)
	if panel.note_label.visible:
		parts.append(panel.note_label.text)
	if panel.status_label.visible:
		parts.append(panel.status_label.text)
	return "\n".join(parts)

## Through the Loan Officer screen, as the player does: the review screen is
## its child, so it is only laid out while that is open.
func open_desk() -> void:
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()

func close_desk() -> void:
	review.close_button.pressed.emit()
	lo.hide_screen()

func fit_problems() -> Array[String]:
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	return problems

# --- the desk order ----------------------------------------------------------------

func test_a_due_closing_comes_before_a_returned_file_and_the_pile() -> void:
	GameClock.day = 6
	var file_application := filed_application([PAY_STUB])
	request_file(file_application, [PAY_STUB] as Array[int], GameClock.day)
	var closing := due_closing(approved("Due Closing"))
	var pile_first := LoanDeskManager.player_queue[0]
	assert_object(LoanDeskManager.current_player_application()).is_same(closing.application)
	# It stays there until it is funded or stopped.
	assert_object(LoanDeskManager.current_player_application()).is_same(closing.application)
	LoanBookManager.fund(closing)
	assert_object(LoanDeskManager.current_player_application()).is_same(file_application)
	LoanRole.pipeline.close(file_application)
	assert_object(LoanDeskManager.current_player_application()).is_same(pile_first)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(LoanDeskManager.queue_size())

func test_closings_come_longest_due_first_and_one_not_yet_due_waits() -> void:
	GameClock.day = 9
	var newer := due_closing(approved("Newer"))
	newer.due_day = 8
	var older := due_closing(approved("Older"))
	older.due_day = 7
	var later := due_closing(approved("Tomorrow"))
	later.due_day = 10
	assert_object(LoanDeskManager.current_player_application()).is_same(older.application)
	LoanBookManager.stop(older)
	assert_object(LoanDeskManager.current_player_application()).is_same(newer.application)
	LoanBookManager.stop(newer)
	# Not due yet: the pile's first.
	assert_object(LoanDeskManager.current_player_application()).is_same(LoanDeskManager.player_queue[0])

func test_a_closing_never_counts_against_the_three_open_files() -> void:
	GameClock.day = 6
	for i in 3:
		due_closing(approved("Closing %d" % i))
	assert_int(LoanRole.pipeline.open_count(GameClock.day)).is_equal(0)
	assert_int(LoanRole.pipeline.refusal_for(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day)).is_equal(LoanPipeline.Refusal.NONE)
	for i in 3:
		assert_object(request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day + 5)).is_not_null()
	assert_int(LoanRole.pipeline.open_count(GameClock.day)).is_equal(3)
	assert_int(LoanRole.closings.count()).is_equal(3)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(LoanDeskManager.queue_size())

func test_with_no_closing_the_desk_is_what_it_was() -> void:
	LoanConfig.closings_enabled = false
	var first := LoanDeskManager.current_player_application()
	assert_object(first).is_same(LoanDeskManager.player_queue[0])
	review.show_screen()
	assert_bool(review.is_closing()).is_false()
	assert_bool(review.columns_box.visible).is_true()
	assert_bool(review.closing_panel.visible).is_false()
	review.hide_screen()

# --- closing mode ---------------------------------------------------------------------

func test_closing_mode_shows_the_frozen_terms_and_no_worksheet() -> void:
	var application := approved("Terms Test")
	var closing := second_closing(application)
	review.show_screen()
	var panel := review.closing_panel
	assert_bool(review.is_closing()).is_true()
	assert_bool(review.columns_box.visible).is_false()
	assert_bool(panel.visible).is_true()
	assert_object(review.current_application()).is_same(application)
	var terms := panel.approved_label.text
	assert_str(terms).contains("Loan amount: $20,000")
	assert_str(terms).contains("Interest rate: %s" % LoanClosingPanel.rate_text(closing.approved_rate))
	assert_str(terms).contains("Term: 60 months")
	assert_str(terms).contains("Monthly payment: %s" % LoanClosingPanel.payment_text(closing.approved_payment))
	assert_str(terms).contains("Approved as requested")
	# The terms are the approval's, whatever happens to the application after.
	application.credit_score = 500
	assert_str("\n".join(LoanClosingPanel.approved_lines(closing))).is_equal(terms)
	# Before the check: a placeholder for the paperwork, no credit check needed.
	assert_str(panel.paperwork_label.text).is_equal(LoanClosingPanel.PLACEHOLDER_TEXT)
	review.hide_screen()

func test_a_counter_offers_closing_shows_what_was_offered_and_asked_for() -> void:
	var closing := second_closing(approved("Counter Test", "Auto", true))
	review.show_screen()
	assert_str(review.closing_panel.approved_label.text).contains("Accepted counter-offer: $18,000 offered, $20,000 requested")
	assert_str(review.closing_panel.approved_label.text).contains("Loan amount: $18,000")
	assert_float(closing.approved_amount).is_equal(18000.0)
	review.hide_screen()

func test_fund_waits_for_the_check_and_stop_is_always_there() -> void:
	second_closing(approved("Check Test"))
	review.show_screen()
	var panel := review.closing_panel
	assert_bool(panel.fund_button.disabled).is_true()
	assert_str(panel.note_label.text).is_equal("Run the closing check first.")
	assert_bool(panel.note_label.visible).is_true()
	assert_bool(panel.stop_button.disabled).is_false()
	assert_bool(panel.check_button.disabled).is_false()
	# Fund does nothing before the check.
	var score_before := score_and_reputation()
	panel.fund_button.pressed.emit()
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_vector(score_and_reputation()).is_equal(score_before)
	panel.check_button.pressed.emit()
	assert_bool(panel.fund_button.disabled).is_false()
	assert_bool(panel.note_label.visible).is_false()
	assert_bool(panel.stop_button.disabled).is_false()
	review.hide_screen()

func test_the_check_shows_the_paperwork_and_marks_nothing() -> void:
	var closing := second_closing(approved("Paper Test"))
	review.show_screen()
	review.closing_panel.check_button.pressed.emit()
	var text := review.closing_panel.paperwork_label.text
	assert_str(text).is_equal("\n".join(LoanClosingPanel.paperwork_lines(closing, GameClock.today_date())))
	for expected: String in ["Loan amount:", "Interest rate:", "Term:", "Monthly payment:", "Photo ID:", "Signature: signed", "Monthly debt payments at approval:", "Monthly debt payments now:"]:
		assert_str(text).contains(expected)
	# The ID's expiry beside today's date.
	assert_str(text).contains("expires %s (today is %s)" % [IdCard.date_text(closing.id_expiry_date), IdCard.date_text(GameClock.today_date())])
	review.hide_screen()

func test_every_problem_type_looks_the_same_but_for_its_values() -> void:
	var shapes: Array[String] = []
	var texts: Array[String] = []
	var kinds: Array[int] = [Problem.NONE, Problem.TERMS, Problem.EXPIRED_ID, Problem.NO_SIGNATURE, Problem.NEW_DEBT]
	for kind in kinds:
		CareerReset.reset_all()
		LoanConfig.closings_enabled = true
		var closing := second_closing(approved("Same Name"), kind)
		assert_int(closing.problem).is_equal(kind)
		review.show_screen()
		review.closing_panel.check_button.pressed.emit()
		var panel := review.closing_panel
		# Both debt lines are always there.
		assert_str(panel.paperwork_label.text).contains("Monthly debt payments at approval:")
		assert_str(panel.paperwork_label.text).contains("Monthly debt payments now:")
		# No highlight: no colour, no extra control, nothing that names a problem.
		for label: Label in [panel.paperwork_label, panel.approved_label, panel.status_label, panel.note_label]:
			assert_bool(label.has_theme_color_override("font_color")).is_false()
			assert_float(label.modulate.a).is_equal(1.0)
			assert_bool(label.modulate == Color.WHITE).is_true()
		var text := panel_text()
		for word: String in ["mismatch", "does not match", "did not match", "problem", "wrong", "expired", "warning", "!"]:
			assert_str(text.to_lower()).override_failure_message("'%s' in the closing panel" % word).not_contains(word)
		texts.append(text)
		shapes.append(masked_shape(text))
		review.hide_screen()
	for i in range(1, shapes.size()):
		assert_str(shapes[i]).override_failure_message("problem %d differs in shape from a clean closing" % kinds[i]).is_equal(shapes[0])

# --- fund and stop --------------------------------------------------------------------

func test_funding_at_the_desk_books_the_loan_and_uses_the_part_two_points() -> void:
	var closing := second_closing(approved("Fund Desk"))
	var reserved := closing.loan_id
	review.show_screen()
	var panel := review.closing_panel
	panel.check_button.pressed.emit()
	var start := score_and_reputation()
	var graded: Array[Vector3i] = []
	review.decision_graded.connect(func(score: int, reputation: int, xp: int) -> void: graded.append(Vector3i(score, reputation, xp)))
	var recorded: Array[LoanApplication] = []
	review.decision_recorded.connect(func(application: LoanApplication) -> void: recorded.append(application))
	panel.fund_button.pressed.emit()
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_int(LoanBookManager.book[0].loan_id).is_equal(reserved)
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.CLOSING_FUND_CLEAN_SCORE, 0))
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_array(graded).is_equal([Vector3i(5, 0, 50)])
	assert_array(recorded).is_equal([closing.application])
	assert_int(lo.applications_reviewed).is_equal(1)
	# The feedback, and the buttons gone.
	assert_str(panel.status_label.text).starts_with("Loan funded. (+5 Score, +0 Reputation, +50 XP)")
	assert_str(panel.status_label.text).contains("Everything matched the approval.")
	assert_bool(panel.fund_button.visible or panel.stop_button.visible or panel.check_button.visible).is_false()
	# A second press does nothing.
	panel.fund_button.pressed.emit()
	assert_int(LoanBookManager.book.size()).is_equal(1)
	# Closing the screen reports it as decided.
	var closed_with: Array[bool] = []
	review.closed.connect(func(decided: bool) -> void: closed_with.append(decided))
	review.close_button.pressed.emit()
	assert_array(closed_with).is_equal([true])

func test_stopping_at_the_desk_never_books_and_names_what_was_on_screen() -> void:
	var closing := second_closing(approved("Stop Desk"), Problem.NO_SIGNATURE)
	review.show_screen()
	var panel := review.closing_panel
	panel.check_button.pressed.emit()
	var start := score_and_reputation()
	panel.stop_button.pressed.emit()
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.CLOSING_STOP_PROBLEM_SCORE, LoanConfig.CLOSING_STOP_PROBLEM_REPUTATION))
	assert_str(panel.status_label.text).starts_with("Closing stopped: good catch. (+8 Score, +1 Reputation, +80 XP)")
	assert_str(panel.status_label.text).contains("The paperwork was not signed.")
	assert_int(lo.applications_reviewed).is_equal(1)
	assert_bool(closing.has_problem()).is_true()
	review.hide_screen()

func test_every_outcome_has_feedback_from_what_the_paperwork_showed() -> void:
	var today := GameClock.today_date()
	# [problem, funded, text that must be in the feedback]
	var rows: Array = [
		[Problem.NONE, true, "Loan funded. ("],
		[Problem.NONE, false, "Closing stopped, but nothing was wrong."],
		[Problem.TERMS, true, "did not match the approved"],
		[Problem.TERMS, false, "Closing stopped: good catch."],
		[Problem.EXPIRED_ID, true, "The photo ID had expired on"],
		[Problem.NO_SIGNATURE, true, "The paperwork was not signed."],
		[Problem.NEW_DEBT, false, "A new debt of"],
	]
	for row: Array in rows:
		var kind: int = row[0]
		var funds: bool = row[1]
		var expected: String = row[2]
		CareerReset.reset_all()
		LoanConfig.closings_enabled = true
		var closing := second_closing(approved("Feedback Test"), kind)
		var result := LoanBookManager.fund(closing) if funds else LoanBookManager.stop(closing)
		var text := LoanClosingPanel.feedback(closing, funds, result, true, today)
		assert_str(text).override_failure_message("problem %d, funded %s" % [kind, funds]).contains(expected)
		if kind == Problem.NONE:
			assert_str(text).contains("Everything matched the approval.")
		# Never a hidden value: no loan outcome, tier or odds.
		for hidden: String in ["default", "risk", "odds", "tier"]:
			assert_str(text.to_lower()).not_contains(hidden)
	# A stop before the check says so.
	var unchecked := second_closing(approved("Unchecked"))
	var stopped := LoanBookManager.stop(unchecked)
	assert_str(LoanClosingPanel.feedback(unchecked, false, stopped, false, today)).contains("You stopped it without running the closing check.")

func test_a_closing_that_is_not_due_is_refused_with_a_message_and_changes_nothing() -> void:
	GameClock.day = 8
	var closing := second_closing(approved("Early Test"))
	review.show_screen()
	# The day moves back before it is dealt with: it isn't due.
	GameClock.day = closing.due_day - 1
	var panel := review.closing_panel
	panel.check_button.pressed.emit()
	assert_bool(review.is_closing()).is_true()
	var start := score_and_reputation()
	panel.fund_button.pressed.emit()
	assert_str(panel.status_label.text).is_equal("Closing not completed: this closing is due on %s." % BankCalendar.short_text(closing.closing_date()))
	panel.stop_button.pressed.emit()
	assert_str(panel.status_label.text).starts_with("Closing not completed: this closing is due on")
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(lo.applications_reviewed).is_equal(0)
	assert_bool(panel.fund_button.visible).is_true()
	review.hide_screen()

func test_a_closing_that_vanished_at_confirm_changes_nothing() -> void:
	var closing := second_closing(approved("Vanish Test"))
	review.show_screen()
	var panel := review.closing_panel
	panel.check_button.pressed.emit()
	# Something else dealt with it meanwhile.
	LoanRole.closings.close(closing)
	var start := score_and_reputation()
	panel.fund_button.pressed.emit()
	assert_str(panel.status_label.text).is_equal("Closing not completed: it is no longer open.")
	panel.stop_button.pressed.emit()
	assert_str(panel.status_label.text).is_equal("Closing not completed: it is no longer open.")
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(lo.applications_reviewed).is_equal(0)
	review.hide_screen()

func test_the_decision_buttons_do_nothing_on_a_closing() -> void:
	second_closing(approved("Locked Test"))
	review.show_screen()
	var start := score_and_reputation()
	review.approve_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.confirm_request_button.pressed.emit()
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_int(LoanRole.pipeline.files.size()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(start)
	review.hide_screen()

func test_a_closing_closed_undecided_stays_on_the_desk() -> void:
	var closing := second_closing(approved("Stays Test"))
	review.show_screen()
	review.closing_panel.check_button.pressed.emit()
	review.close_button.pressed.emit()
	assert_int(LoanRole.closings.count()).is_equal(1)
	# Shown again, from a fresh state: the check not yet run.
	review.show_screen()
	assert_object(review.current_application()).is_same(closing.application)
	assert_bool(review.closing_panel.checked).is_false()
	assert_bool(review.closing_panel.fund_button.disabled).is_true()
	review.hide_screen()

# --- the first closing ------------------------------------------------------------------

func test_only_the_first_closing_explains_itself() -> void:
	var first := due_closing(approved("First Closing"))
	assert_int(first.number).is_equal(1)
	assert_bool(first.has_problem()).is_false()
	review.show_screen()
	var panel := review.closing_panel
	assert_bool(panel.explanation_label.visible).is_true()
	assert_str(panel.explanation_label.text).is_equal(LoanClosingPanel.FIRST_CLOSING_TEXT)
	assert_int(panel.explanation_label.text.count("\n") + 1).is_less_equal(4)
	assert_str(panel.explanation_label.text).contains("compare")
	panel.check_button.pressed.emit()
	panel.fund_button.pressed.emit()
	review.hide_screen()
	# The second one doesn't.
	due_closing(approved("Second Closing"))
	review.show_screen()
	assert_int(review.closing_panel.shown_closing.number).is_equal(2)
	assert_bool(review.closing_panel.explanation_label.visible).is_false()
	review.hide_screen()

# --- the applicant ---------------------------------------------------------------------

func test_the_applicant_has_lines_of_their_own_and_the_same_name_and_look() -> void:
	var application := approved("Look Test")
	application.applicant_look = 5
	second_closing(application)
	for pick in 8:
		var line := LoanApplicantNPC.arrival_line(application, pick)
		assert_bool(LoanApplicantNPC.CLOSING_LINES.has(line)).is_true()
	assert_str(LoanApplicantNPC.CLOSING_LINES[0]).is_equal("I'm here to sign for my loan.")
	# Anyone else's arrival line is about their loan.
	assert_bool(LoanApplicantNPC.CLOSING_LINES.has(LoanApplicantNPC.arrival_line(approved("Not A Closing"), 0))).is_false()
	# At the desk: they walk in like anyone else, in their own look.
	clock_in_at_loan_desk()
	lo.applications_per_shift = 1
	room._process(0.0)
	var seat := room.player_loan_seat()
	assert_object(seat.application).is_same(application)
	assert_int(seat.applicant.look).is_equal(5)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

func test_the_applicant_is_pleased_after_a_fund_and_confused_after_a_stop() -> void:
	clock_in_at_loan_desk()
	lo.applications_per_shift = 2
	var funded := second_closing(approved("Pleased Test"))
	var stopped := second_closing(approved("Confused Test"))
	stopped.due_day = GameClock.day
	var seat := room.player_loan_seat()
	lo.review_next_button.pressed.emit()
	assert_bool(seat.is_seated()).is_true()
	assert_object(seat.application).is_same(funded.application)
	assert_bool(LoanApplicantNPC.CLOSING_LINES.has(speech(seat.applicant)) or speech(seat.applicant) == "").is_true()
	review.closing_panel.check_button.pressed.emit()
	review.closing_panel.fund_button.pressed.emit()
	assert_bool(LoanApplicantNPC.CLOSING_FUNDED_LINES.has(speech(seat.applicant))).is_true()
	review.close_button.pressed.emit()
	lo.review_next_button.pressed.emit()
	assert_object(seat.application).is_same(stopped.application)
	review.closing_panel.stop_button.pressed.emit()
	assert_bool(LoanApplicantNPC.CLOSING_STOPPED_LINES.has(speech(seat.applicant))).is_true()
	review.close_button.pressed.emit()

func test_the_reactions_read_only_the_outcome_never_the_name_or_look() -> void:
	var one := approved("Alpha One")
	one.applicant_look = 1
	var two := approved("Beta Two")
	two.applicant_look = 9
	var first := second_closing(one)
	var second := second_closing(two)
	LoanBookManager.fund(first)
	LoanBookManager.fund(second)
	for pick in 6:
		assert_str(LoanApplicantNPC.reaction_line(one, pick)).is_equal(LoanApplicantNPC.reaction_line(two, pick))
		assert_str(LoanApplicantNPC.arrival_line(one, pick)).is_equal(LoanApplicantNPC.arrival_line(two, pick))
	assert_bool(LoanApplicantNPC.CLOSING_FUNDED_LINES.has(LoanApplicantNPC.reaction_line(one, 0))).is_true()

# --- the slot ---------------------------------------------------------------------------

func test_a_closing_is_the_slots_one_application_and_the_strings_are_unchanged() -> void:
	assert_str(LoanSlotAdapter.STATUS_TEXT % [0, 1]).is_equal("Application: 0 / 1")
	assert_str(LoanSlotAdapter.REPORT_TEXT % 1).is_equal("Applications decided: 1")
	loan_day_at_9am()
	var adapter := loan_slot_adapter()
	var closing := second_closing(approved("Slot Closing"))
	var pile_first := LoanDeskManager.player_queue[0]
	assert_str(adapter.status_text()).is_equal("Application: 0 / 1")
	assert_int(lo.applications_left()).is_equal(1)
	# The closing is on the desk; the pile's first isn't.
	lo.review_next_button.pressed.emit()
	assert_bool(review.is_closing()).is_true()
	assert_object(review.current_application()).is_same(closing.application)
	review.closing_panel.check_button.pressed.emit()
	review.closing_panel.fund_button.pressed.emit()
	assert_int(lo.applications_reviewed).is_equal(1)
	assert_int(lo.applications_left()).is_equal(0)
	assert_str(adapter.status_text()).is_equal("Application: 1 / 1")
	review.close_button.pressed.emit()
	lo.hide_screen()
	await frames(3)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(slot_card().done_label.text).is_equal("9 AM slot done\nApplications decided: 1")
	# The pile didn't move, and the next slot brings the pile's first.
	assert_object(LoanDeskManager.player_queue[0]).is_same(pile_first)
	continue_to_slot(DaySchedule.SLOT_11AM)
	assert_str(adapter.status_text()).is_equal("Application: 0 / 1")
	assert_object(LoanDeskManager.current_player_application()).is_same(pile_first)

# --- fit -----------------------------------------------------------------------------------

func test_every_closing_state_fits_the_window_and_clears_the_hud_and_controls() -> void:
	var states := 0
	# The first closing explains itself (the tallest before the check).
	var first := due_closing(approved("Fit First"))
	open_desk()
	await frames(3)
	var problems := fit_problems()
	review.closing_panel.check_button.pressed.emit()
	await frames(3)
	problems.append_array(fit_problems())
	review.closing_panel.fund_button.pressed.emit()
	await frames(3)
	problems.append_array(fit_problems())
	close_desk()
	states += 3
	assert_bool(first.number == 1).is_true()
	# Every problem type, before and after the check, and the feedback of a stop
	# and of a funded mistake; a counter-offer and a home loan.
	var cases: Array = [
		[Problem.NONE, "Auto", false], [Problem.TERMS, "Business", true], [Problem.EXPIRED_ID, "Auto", false],
		[Problem.NO_SIGNATURE, "Personal", false], [Problem.NEW_DEBT, "Home", false],
	]
	for case: Array in cases:
		var kind: int = case[0]
		var purpose: String = case[1]
		var counter: bool = case[2]
		second_closing(approved("Fit %d" % kind, purpose, counter), kind)
		open_desk()
		await frames(3)
		problems.append_array(fit_problems())
		review.closing_panel.check_button.pressed.emit()
		await frames(3)
		problems.append_array(fit_problems())
		review.closing_panel.stop_button.pressed.emit()
		await frames(3)
		problems.append_array(fit_problems())
		close_desk()
		states += 3
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	assert_int(states).is_equal(18)
	# Beside the worksheet the old states are unchanged: still fits.
	LoanConfig.closings_enabled = false
	LoanDeskManager.player_queue.clear()
	open_desk()
	await frames(3)
	assert_array(fit_problems()).is_empty()
	close_desk()
