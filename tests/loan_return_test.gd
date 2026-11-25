extends "res://tests/support/loan/loan_suite.gd"

## Part 3 of multi-day loan applications: the returning flow. Returned files
## come first and the pile stays at three; what comes back (complete,
## incomplete, wrong) and the loan it books; a further request after an
## incomplete return; the withdrawal of a returned file left undecided,
## applied once at the start of a work day across reloads, weekends and
## holidays; the waiting list on the Loan Officer screen (and that it gives
## nothing away); the applicant's lines; the End of Day lines; and fit.

const PAY_STUB := LoanRequirements.Item.PAY_STUB
const STATEMENT := LoanRequirements.Item.BANK_STATEMENT
const PHOTO_ID := LoanRequirements.Item.PHOTO_ID
const APPRAISAL := LoanRequirements.Item.APPRAISAL
const DOWN_PAYMENT := LoanRequirements.Item.DOWN_PAYMENT_PROOF
const LETTER := LoanRequirements.Item.EXPLANATION_LETTER

const LOAN := PlayerShift.Role.LOAN_OFFICER
const TELLER := PlayerShift.Role.TELLER
const MANAGER := PlayerShift.Role.BRANCH_MANAGER

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

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## A Loan Officer day, clocked in at Opening, with 9 AM started.
func loan_day_at_9am() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)

## A generated applicant with documents fine except `missing` (any of the pay
## stub, the statement and the ID), a Personal loan with a clean history, so
## exactly `missing` is truly missing.
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
	application.has_statement = not missing.has(STATEMENT)
	if missing.has(PHOTO_ID):
		application.id_presented = false
		application.id_problem = IdCard.Problem.NO_ID
	if missing.has(PAY_STUB):
		application.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	elif missing.has(STATEMENT):
		application.doc_problem = LoanApplication.DocProblem.MISSING_STATEMENT
	assert_array(LoanRequirements.missing_items(application, LoanDeskManager.career_seed)).is_equal(missing)
	return application

## A home loan with a purchase and a late payment on the report, so every one
## of the six items applies.
func home_application() -> LoanApplication:
	var home := filed_application([])
	home.loan_purpose = "Home"
	home.collateral_issued = true
	home.collateral_kind = LoanApplication.Collateral.HOUSE
	home.purchase_price = home.requested_amount + 40000.0
	home.collateral_value = home.purchase_price
	home.late_30_days = 1
	return home

## Asks for `items` for `application` today and sets how the file answers:
## back on `returns_on`, with `quality`, and `short`/`wrong` the item left out or
## not matching. Returns the file.
func request_file(application: LoanApplication, items: Array[int], returns_on: int, quality: LoanFile.Quality = LoanFile.Quality.COMPLETE, short: int = -1, wrong: int = -1) -> LoanFile:
	var file := LoanRole.request_documents(application, items)
	assert_object(file).is_not_null()
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = returns_on
	file.quality = quality
	file.short_item = short
	file.wrong_item = wrong
	return file

## A file that never comes back.
func request_lost_file(application: LoanApplication, items: Array[int]) -> LoanFile:
	var file := LoanRole.request_documents(application, items)
	assert_object(file).is_not_null()
	file.timing = LoanFile.Timing.NEVER
	file.return_day = LoanFile.NEVER_DAY
	return file

## Starts business day `day` as "Start Day N+1" does (the clock, the day's
## totals, a fresh slot day at Opening): the room started Day 1 already.
func start_business_day(day: int) -> void:
	BusinessDay.stats_day = day - 1
	BusinessDay.start_next_day()
	assert_int(GameClock.day).is_equal(day)
	start_slots_day()
	assert_bool(DayFlow.is_running()).is_true()

## The player clocks in at Loan Desk 1 at Opening (nobody's Opening ends
## without that), goes home early from the card and clocks out at Closing:
## a day with no work done, up to the End of Day.
func go_home_from_the_loan_desk() -> void:
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	to_closing()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	lo.shift_summary_done_button.pressed.emit()
	lo.hide_screen()

## Records the player's role on each of `days` (what LoanSlotAdapter notes
## as a day's slots start). The roles are kept only while a file is open, so
## ask for the file first.
func note_roles(role: PlayerShift.Role, days: Array[int]) -> void:
	for day in days:
		LoanRole.note_role(day, role)

func open_desk() -> void:
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()

func assert_fits(label: String = "") -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	assert_array(problems).override_failure_message("%s\n%s\n%s" % [label, "\n".join(problems), layout_dump()]).is_empty()

## The review screen's three columns and what is tall in each, for a failure
## message.
func layout_dump() -> String:
	var parts: PackedStringArray = []
	var columns := review.main_panel.get_node("VBox/Columns") as HBoxContainer
	for column in columns.get_children():
		var control := column as Control
		var inner: PackedStringArray = []
		for child in control.find_children("*", "Control", true, false):
			var node := child as Control
			if node.is_visible_in_tree() and node.size.y > 40.0:
				inner.append("%s %.0f" % [node.name, node.size.y])
		parts.append("%s %.0f (%s)" % [control.name, control.size.y, ", ".join(inner)])
	return " | ".join(parts)

## The career as it would come back from a save file: through JSON.
func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

# --- the numbers -----------------------------------------------------------------

func test_the_withdrawal_numbers_are_in_the_loan_config() -> void:
	assert_int(LoanConfig.DECIDE_WITHIN_DAYS).is_equal(3)
	assert_int(LoanConfig.WITHDRAWN_SCORE).is_equal(-2)
	assert_int(LoanConfig.WITHDRAWN_REPUTATION).is_equal(-1)

# --- returned files come first ----------------------------------------------------

func test_a_returned_file_comes_before_the_pile_and_the_pile_stays_at_three() -> void:
	loan_day_at_9am()
	var first_in_pile := LoanDeskManager.player_queue[0]
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day)
	# Back: it is the one on the desk, and the pile is untouched.
	assert_object(LoanDeskManager.current_player_application()).is_same(file.application)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(3)
	assert_bool(LoanDeskManager.player_queue.has(file.application)).is_false()
	assert_object(LoanDeskManager.player_queue[0]).is_same(first_in_pile)
	# Still there when asked again, and when the review is closed undecided.
	open_desk()
	assert_object(review.current_application()).is_same(file.application)
	review.close_button.pressed.emit()
	assert_object(LoanDeskManager.current_player_application()).is_same(file.application)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(3)
	# Decided: the pile's first is next, and the file is closed.
	open_desk()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	review.submit_denial_button.pressed.emit()
	assert_object(LoanRole.pipeline.file_for(file.application)).is_null()
	assert_object(LoanDeskManager.current_player_application()).is_same(first_in_pile)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(3)

func test_the_file_back_longest_comes_first() -> void:
	loan_day_at_9am()
	GameClock.day = 8
	var late := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 9)
	var early := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 8)
	var same_day := request_file(filed_application([PHOTO_ID]), [PHOTO_ID] as Array[int], 8)
	GameClock.day = 9
	assert_array(LoanRole.pipeline.returned_files(9)).is_equal([early, same_day, late])
	assert_object(LoanDeskManager.current_player_application()).is_same(early.application)

func test_a_file_not_yet_back_does_not_take_the_desk() -> void:
	loan_day_at_9am()
	var pending := LoanDeskManager.current_player_application()
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day + 1)
	assert_object(LoanDeskManager.current_player_application()).is_same(pending)

func test_a_returned_file_is_the_slots_one_application() -> void:
	loan_day_at_9am()
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day)
	assert_str(loan_slot_adapter().status_text()).is_equal("Application: 0 / 1")
	open_desk()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.approve_button.pressed.emit()
	assert_object(LoanRole.pipeline.file_for(file.application)).is_null()
	assert_int(lo.applications_reviewed).is_equal(1)
	review.close_button.pressed.emit()
	lo.hide_screen()
	await frames(3)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(slot_card().done_label.text).is_equal("9 AM slot done\nApplications decided: 1")

# --- what comes back ------------------------------------------------------------

func test_a_complete_return_clears_what_was_asked_for_and_books_with_documents_ok() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB, STATEMENT])
	var file := request_file(application, [PAY_STUB, STATEMENT] as Array[int], GameClock.day)
	assert_bool(application.documents_check_out()).is_false()
	open_desk()
	assert_object(review.current_application()).is_same(application)
	assert_bool(application.has_pay_stub).is_true()
	assert_bool(application.has_statement).is_true()
	assert_str(application.stub_name).is_equal(application.applicant_name)
	assert_str(application.statement_name).is_equal(application.applicant_name)
	assert_float(application.stub_monthly_gross).is_equal(roundf(application.annual_income / 12.0))
	assert_int(application.statement_total()).is_greater(0)
	assert_int(application.doc_problem).is_equal(LoanApplication.DocProblem.NONE)
	assert_bool(application.documents_check_out()).is_true()
	assert_int(file.return_applied).is_equal(1)
	# Verify Documents is needed again, and shows them.
	assert_bool(review.documents_verified).is_false()
	review.verify_documents_button.pressed.emit()
	assert_str(review.documents_text()).not_contains("none provided")
	# The loan books with its documents fine.
	review.run_credit_check_button.pressed.emit()
	review.approve_button.pressed.emit()
	var loan: BookedLoan = LoanBookManager.book.back()
	assert_str(loan.borrower).is_equal(application.applicant_name)
	assert_bool(loan.documents_ok).is_true()

func test_an_incomplete_return_leaves_one_item_missing() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB, STATEMENT])
	request_file(application, [PAY_STUB, STATEMENT] as Array[int], GameClock.day, LoanFile.Quality.INCOMPLETE, STATEMENT)
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_bool(application.has_pay_stub).is_true()
	assert_bool(application.has_statement).is_false()
	assert_int(application.doc_problem).is_equal(LoanApplication.DocProblem.MISSING_STATEMENT)
	assert_str(review.documents_text()).contains("Bank statement: none provided.")
	assert_str(review.documents_text()).not_contains("Pay stub: none provided.")
	review.run_credit_check_button.pressed.emit()
	review.approve_button.pressed.emit()
	var booked: BookedLoan = LoanBookManager.book.back()
	assert_bool(booked.documents_ok).is_false()

func test_a_wrong_return_hands_over_a_document_that_does_not_match() -> void:
	loan_day_at_9am()
	# A stub in someone else's name: a forged-type problem, best answered by
	# rejecting it as unverifiable.
	var application := filed_application([PAY_STUB])
	request_file(application, [PAY_STUB] as Array[int], GameClock.day, LoanFile.Quality.WRONG, -1, PAY_STUB)
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_bool(application.has_pay_stub).is_true()
	assert_str(application.stub_name).is_not_equal(application.applicant_name)
	assert_int(application.doc_problem).is_equal(LoanApplication.DocProblem.STUB_NAME)
	assert_bool(application.has_forged_document()).is_true()
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.BEST_DECISION_SCORE + LoanApplication.REASON_RIGHT_SCORE
	assert_vector(totals() - start).is_equal(Vector3i(score, LoanApplication.BEST_DECISION_REPUTATION, score * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).contains("Good catch")

func test_every_kind_of_wrong_item_is_a_forged_type_problem() -> void:
	loan_day_at_9am()
	var cases := [
		[PAY_STUB, LoanApplication.DocProblem.STUB_NAME],
		[STATEMENT, LoanApplication.DocProblem.OVERSTATED_INCOME],
		[APPRAISAL, LoanApplication.DocProblem.PAPER_MISMATCH],
		[DOWN_PAYMENT, LoanApplication.DocProblem.PAPER_MISMATCH],
		[LETTER, LoanApplication.DocProblem.PAPER_MISMATCH],
	]
	for case: Array in cases:
		var item: int = case[0]
		var expected: int = case[1]
		var application := home_application()
		var file := request_file(application, [item] as Array[int], GameClock.day, LoanFile.Quality.WRONG, -1, item)
		LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
		assert_int(application.doc_problem).override_failure_message("item %d" % item).is_equal(expected)
		assert_bool(application.has_forged_document()).is_true()
		assert_bool(application.documents_check_out()).is_false()
		LoanRole.pipeline.close(application)
	# A wrong ID: another name or another face.
	var with_id := filed_application([PHOTO_ID])
	var id_file := request_file(with_id, [PHOTO_ID] as Array[int], GameClock.day, LoanFile.Quality.WRONG, -1, PHOTO_ID)
	LoanReturn.apply(id_file, LoanDeskManager.career_seed, GameClock.day)
	assert_bool(with_id.id_problem == IdCard.Problem.NAME_MISMATCH or with_id.id_problem == IdCard.Problem.WRONG_PORTRAIT).is_true()
	assert_bool(with_id.has_forged_document()).is_true()

func test_a_complete_id_replaces_a_missing_or_expired_one() -> void:
	loan_day_at_9am()
	var application := filed_application([PHOTO_ID])
	var file := request_file(application, [PHOTO_ID] as Array[int], GameClock.day)
	LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
	assert_bool(application.id_presented).is_true()
	assert_int(application.id_problem).is_equal(IdCard.Problem.NONE)
	assert_str(application.id_holder_name).is_equal(application.applicant_name)
	assert_bool(application.documents_check_out()).is_true()

func test_the_applicant_keeps_every_problem_unrelated_to_the_request() -> void:
	loan_day_at_9am()
	# No statement and an expired ID; the request is only for the statement.
	var application := filed_application([STATEMENT])
	application.id_problem = IdCard.Problem.EXPIRED
	var file := request_file(application, [STATEMENT] as Array[int], GameClock.day)
	LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
	assert_bool(application.has_statement).is_true()
	assert_int(application.doc_problem).is_equal(LoanApplication.DocProblem.NONE)
	assert_int(application.id_problem).is_equal(IdCard.Problem.EXPIRED)
	assert_bool(application.documents_check_out()).is_false()
	# A forged ID stays too when only the pay stub is asked for.
	var forged := filed_application([PAY_STUB])
	forged.id_problem = IdCard.Problem.NAME_MISMATCH
	var forged_file := request_file(forged, [PAY_STUB] as Array[int], GameClock.day)
	LoanReturn.apply(forged_file, LoanDeskManager.career_seed, GameClock.day)
	assert_bool(forged.has_pay_stub).is_true()
	assert_int(forged.id_problem).is_equal(IdCard.Problem.NAME_MISMATCH)
	assert_bool(forged.documents_check_out()).is_false()

func test_a_return_is_applied_once_and_the_same_every_load() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB, STATEMENT])
	var file := request_file(application, [PAY_STUB, STATEMENT] as Array[int], GameClock.day)
	LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
	var once := SaveGame.resource_to_dict(application)
	# A second look changes nothing, and applying again from the same state on
	# a copy gives the same documents.
	LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
	assert_dict(SaveGame.resource_to_dict(application)).is_equal(once)
	var again := filed_application([PAY_STUB, STATEMENT])
	again.applicant_name = application.applicant_name
	again.annual_income = application.annual_income
	again.applicant_look = application.applicant_look
	var copy := LoanFile.new()
	copy.number = file.number
	copy.application = again
	copy.request_count = 1
	copy.items = file.items
	copy.timing = LoanFile.Timing.ON_TIME
	copy.return_day = GameClock.day
	LoanReturn.apply(copy, LoanDeskManager.career_seed, GameClock.day)
	assert_int(again.statement_total()).is_equal(application.statement_total())
	assert_float(again.stub_monthly_net).is_equal(application.stub_monthly_net)

func test_papers_brought_back_are_shown_with_verify_documents() -> void:
	loan_day_at_9am()
	var home := home_application()
	request_file(home, [APPRAISAL, DOWN_PAYMENT, LETTER] as Array[int], GameClock.day)
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_bool(review.papers_label.visible).is_true()
	assert_str(review.papers_label.text).contains("Appraisal: ")
	assert_str(review.papers_label.text).contains("Down payment: ")
	assert_str(review.papers_label.text).contains("Letter: explains the late payment")
	assert_str(review.documents_text()).contains("Appraisal: ")
	assert_bool(home.documents_check_out()).is_true()
	await assert_fits("papers shown")
	# A paper that doesn't match says so on its face, and nothing more.
	review.close_button.pressed.emit()
	LoanRole.pipeline.close(home)
	var other := home_application()
	request_file(other, [APPRAISAL] as Array[int], GameClock.day, LoanFile.Quality.WRONG, -1, APPRAISAL)
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_str(review.papers_label.text).contains("not this property")
	assert_int(other.doc_problem).is_equal(LoanApplication.DocProblem.PAPER_MISMATCH)
	assert_str(other.documents_problem_text()).contains("a paper they brought back didn't match")

func test_nothing_is_shown_for_papers_when_none_came() -> void:
	loan_day_at_9am()
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_bool(review.papers_label.visible).is_false()

# --- a further request after an incomplete return --------------------------------

func test_a_further_request_after_an_incomplete_return() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB, STATEMENT])
	var file := request_file(application, [PAY_STUB, STATEMENT] as Array[int], GameClock.day, LoanFile.Quality.INCOMPLETE, STATEMENT)
	var first_in_pile := LoanDeskManager.player_queue[0]
	open_desk()
	review.verify_documents_button.pressed.emit()
	# Allowed: it has asked once.
	assert_bool(review.request_button.disabled).is_false()
	review.request_button.pressed.emit()
	assert_array(review.request_checks.keys()).is_equal([PAY_STUB, STATEMENT, PHOTO_ID])
	review.request_checks[STATEMENT].button_pressed = true
	var start := totals()
	review.confirm_request_button.pressed.emit()
	# What is still missing is exactly what was asked: the right checklist.
	assert_int(totals().x - start.x).is_equal(LoanConfig.REQUEST_RIGHT_SCORE)
	assert_int(file.request_count).is_equal(2)
	assert_array(file.items).is_equal([STATEMENT])
	assert_array(file.delivered_before).is_equal([PAY_STUB])
	assert_int(file.request_day).is_equal(GameClock.day)
	# Out again: the pile's first is next, and the pile is still three.
	assert_object(LoanDeskManager.current_player_application()).is_same(first_in_pile)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(3)
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	# Back again, complete this time: the statement is there.
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = GameClock.day + 1
	file.quality = LoanFile.Quality.COMPLETE
	file.short_item = -1
	file.wrong_item = -1
	review.close_button.pressed.emit()
	GameClock.day += 1
	assert_object(LoanDeskManager.current_player_application()).is_same(application)
	assert_bool(application.has_statement).is_true()
	assert_bool(application.documents_check_out()).is_true()
	assert_int(file.return_applied).is_equal(2)

func test_a_third_request_is_not_offered_on_a_file_that_has_asked_twice() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB] as Array[int], GameClock.day, LoanFile.Quality.INCOMPLETE, PAY_STUB)
	open_desk()
	review.verify_documents_button.pressed.emit()
	review.request_button.pressed.emit()
	review.request_checks[PAY_STUB].button_pressed = true
	review.confirm_request_button.pressed.emit()
	assert_int(file.request_count).is_equal(2)
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = GameClock.day
	file.quality = LoanFile.Quality.INCOMPLETE
	file.short_item = PAY_STUB
	review.close_button.pressed.emit()
	open_desk()
	review.verify_documents_button.pressed.emit()
	assert_bool(review.request_button.disabled).is_true()
	assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_TWICE_TEXT)

# --- the withdrawal ----------------------------------------------------------------

## The clock on a returned file counts only the days recorded as Loan Officer
## days: three of them after the day it came back, then it is withdrawn at the
## start of the next work day. The roles are noted in LoanRole.role_days.

func test_a_file_not_decided_in_three_loan_officer_days_is_withdrawn_at_the_start_of_the_next_work_day() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB] as Array[int], 5)
	# Nothing has been worked yet: decided by day 8 if every day from the next is a Loan Officer day.
	assert_int(file.loan_officer_days_since_return(6, LoanRole.role_days)).is_equal(0)
	assert_int(file.decide_by_day(6, LoanRole.role_days)).is_equal(8)
	note_roles(LOAN, [6, 7, 8])
	var start := score_and_reputation()
	var xp := XPManager.total_xp
	for day in range(5, 9):
		GameClock.day = day
		assert_array(LoanRole.start_of_day()).is_empty()
		assert_bool(file.is_overdue(day, LoanRole.role_days)).is_false()
	assert_vector(score_and_reputation()).is_equal(start)
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	# Three Loan Officer days gone: withdrawn as day 9 starts, costing the constants.
	GameClock.day = 9
	assert_int(file.loan_officer_days_since_return(9, LoanRole.role_days)).is_equal(3)
	assert_bool(file.is_overdue(9, LoanRole.role_days)).is_true()
	assert_array(LoanRole.start_of_day()).is_equal([file])
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_int(XPManager.total_xp).is_equal(maxi(0, xp + LoanConfig.WITHDRAWN_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_object(LoanRole.pipeline.file_for(application)).is_null()
	# Once only.
	assert_array(LoanRole.start_of_day()).is_empty()
	GameClock.day = 10
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))

func test_teller_days_do_not_count_so_the_file_waits() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	# Two days as a Teller, then three as a Loan Officer.
	note_roles(TELLER, [6, 7])
	note_roles(LOAN, [8, 9, 10])
	var start := score_and_reputation()
	for day in range(5, 11):
		GameClock.day = day
		assert_array(LoanRole.start_of_day()).override_failure_message("withdrawn at the start of day %d" % day).is_empty()
	assert_vector(score_and_reputation()).is_equal(start)
	# Days 8, 9 and 10 are the third Loan Officer day only as day 11 starts.
	GameClock.day = 11
	assert_int(file.loan_officer_days_since_return(11, LoanRole.role_days)).is_equal(3)
	assert_array(LoanRole.start_of_day()).is_equal([file])
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))

func test_a_day_as_anything_but_a_loan_officer_or_with_no_role_recorded_does_not_count() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(MANAGER, [6])
	note_roles(TELLER, [7])
	# Day 8 has no role recorded at all; day 9 is a Loan Officer day.
	note_roles(LOAN, [9])
	assert_int(file.loan_officer_days_since_return(10, LoanRole.role_days)).is_equal(1)
	assert_int(file.decide_days_left(10, LoanRole.role_days)).is_equal(2)
	# The day it came back doesn't count either, nor today (still to be worked).
	note_roles(LOAN, [5, 10])
	assert_int(file.loan_officer_days_since_return(10, LoanRole.role_days)).is_equal(1)
	assert_int(file.loan_officer_days_since_return(11, LoanRole.role_days)).is_equal(2)

func test_each_teller_day_pushes_the_decide_by_day_back() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	assert_int(file.decide_by_day(6, LoanRole.role_days)).is_equal(8)
	note_roles(TELLER, [6])
	assert_int(file.decide_by_day(7, LoanRole.role_days)).is_equal(9)
	note_roles(LOAN, [7])
	assert_int(file.decide_by_day(8, LoanRole.role_days)).is_equal(9)
	note_roles(TELLER, [8])
	assert_int(file.decide_by_day(9, LoanRole.role_days)).is_equal(10)

func test_a_file_decided_in_time_costs_nothing() -> void:
	loan_day_at_9am()
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	request_file(application, [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7])
	GameClock.day = 8
	# Decided on the last Loan Officer day it had.
	assert_object(LoanDeskManager.current_player_application()).is_same(application)
	open_desk()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.approve_button.pressed.emit()
	note_roles(LOAN, [8])
	var start := score_and_reputation()
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_vector(score_and_reputation()).is_equal(start)
	assert_array(LoanRole.pipeline.log_withdrawn).is_empty()

func test_the_withdrawal_counts_loan_officer_days_across_a_weekend() -> void:
	# Day 5 is Friday 9 January 2026. Back that day; Loan Officer days Monday
	# the 12th, Tuesday the 13th and Wednesday the 14th (days 6 to 8): withdrawn
	# on the Thursday (day 9).
	assert_str(BankCalendar.iso(GameClock.date_of_day(5))).is_equal("2026-01-09")
	assert_str(BankCalendar.iso(GameClock.date_of_day(6))).is_equal("2026-01-12")
	assert_str(BankCalendar.iso(GameClock.date_of_day(9))).is_equal("2026-01-15")
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	assert_str(BankCalendar.iso(file.decide_by_date(6, LoanRole.role_days))).is_equal("2026-01-14")
	note_roles(LOAN, [6, 7, 8])
	GameClock.day = 8
	assert_array(LoanRole.start_of_day()).is_empty()
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).has_size(1)

func test_the_withdrawal_counts_loan_officer_days_across_a_bank_holiday() -> void:
	# Day 10 is Friday 16 January; Monday the 19th is Martin Luther King Jr.
	# Day. Back that day; Loan Officer days Tuesday the 20th, Wednesday the
	# 21st and Thursday the 22nd (days 11 to 13): withdrawn on the Friday (day 14).
	assert_str(BankCalendar.iso(GameClock.date_of_day(10))).is_equal("2026-01-16")
	assert_str(BankCalendar.iso(GameClock.date_of_day(11))).is_equal("2026-01-20")
	assert_str(BankCalendar.iso(GameClock.date_of_day(14))).is_equal("2026-01-23")
	GameClock.day = 10
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 10)
	assert_str(BankCalendar.iso(file.decide_by_date(11, LoanRole.role_days))).is_equal("2026-01-22")
	note_roles(LOAN, [11, 12, 13])
	GameClock.day = 13
	assert_array(LoanRole.start_of_day()).is_empty()
	GameClock.day = 14
	assert_array(LoanRole.start_of_day()).has_size(1)

func test_the_withdrawal_comes_at_opening_whatever_role_today_turns_out_to_be() -> void:
	# At Opening of day 9 nobody has clocked in yet: today's role isn't chosen,
	# and doesn't count. The three Loan Officer days before it do.
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	var start := score_and_reputation()
	start_business_day(9)
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_bool(LoanRole.pipeline.is_empty()).is_true()

func test_a_branch_manager_is_never_penalised() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	# Promoted since: the Loan Officer days are used up, but nothing is charged.
	XPManager.is_branch_manager_unlocked = true
	var start := score_and_reputation()
	var xp := XPManager.total_xp
	GameClock.day = 9
	assert_bool(file != null).is_true()
	# Nothing from the pipeline runs for a Branch Manager: the file goes to
	# the staff quietly, not withdrawn with a penalty.
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(XPManager.total_xp).is_equal(xp)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Open loan files were passed to your staff"])
	# And Branch Manager days never count towards the clock.
	GameClock.day = 10
	var other := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 10)
	note_roles(MANAGER, [11, 12, 13, 14])
	GameClock.day = 15
	assert_int(other.loan_officer_days_since_return(15, LoanRole.role_days)).is_equal(0)
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_vector(score_and_reputation()).is_equal(start)

func test_a_withdrawal_can_never_take_reputation_to_zero() -> void:
	var zero_events: Array = []
	ReputationManager.reputation_reached_zero.connect(func() -> void: zero_events.append(true))
	var reports := ReportManager.reports.size()
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	# At 1 Reputation: nothing is taken from it, the Score still costs.
	ReputationManager.reputation = 1
	var score := ScoreManager.total_score
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).is_equal([file])
	assert_int(ReputationManager.reputation).is_equal(1)
	assert_int(ScoreManager.total_score - score).is_equal(LoanConfig.WITHDRAWN_SCORE)
	assert_str(LoanRole.pipeline.summary_lines(9)[0]).is_equal("Files withdrawn, not decided in time: %s (%+d Score)" % [file.application.applicant_name, LoanConfig.WITHDRAWN_SCORE])
	# At 2: the one point it costs; two files at once stop at 1.
	LoanRole.reset()
	ReputationManager.reputation = 2
	GameClock.day = 20
	var first := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 20)
	var second := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 20)
	note_roles(LOAN, [21, 22, 23])
	GameClock.day = 24
	assert_array(LoanRole.start_of_day()).has_size(2)
	assert_int(ReputationManager.reputation).is_equal(1)
	assert_array(zero_events).is_empty()
	assert_int(ReportManager.reports.size()).is_equal(reports)
	assert_bool(first != null and second != null).is_true()

func test_a_withdrawal_never_adds_reputation() -> void:
	# At Reputation 0 a withdrawal costs the Score only (the old floor gave +1).
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	ReputationManager.reputation = 0
	var score := ScoreManager.total_score
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).is_equal([file])
	assert_int(ReputationManager.reputation).is_equal(0)
	assert_int(ScoreManager.total_score - score).is_equal(LoanConfig.WITHDRAWN_SCORE)
	assert_str(LoanRole.pipeline.summary_lines(9)[0]).is_equal("Files withdrawn, not decided in time: %s (%+d Score)" % [file.application.applicant_name, LoanConfig.WITHDRAWN_SCORE])

func test_the_roles_are_recorded_as_each_days_slots_start() -> void:
	# With a file open (the roles are kept only then).
	var holder := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day + 5)
	loan_day_at_9am()
	assert_bool(holder != null).is_true()
	assert_int(LoanRole.role_days[GameClock.day]).is_equal(PlayerShift.Role.LOAN_OFFICER)
	# A Teller's day.
	var day := GameClock.day
	DayFlow.reset()
	BusinessDay.stats_day = day
	BusinessDay.start_next_day()
	start_slots_day()
	PlayerShift.report_clock_in(PlayerShift.Role.TELLER)
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_int(LoanRole.role_days[GameClock.day]).is_equal(PlayerShift.Role.TELLER)
	assert_int(LoanRole.role_days[day]).is_equal(PlayerShift.Role.LOAN_OFFICER)

func test_the_roles_are_kept_only_while_a_file_is_open_and_saved_only_then() -> void:
	# No file: nothing kept, nothing saved.
	LoanRole.note_role(3, PlayerShift.Role.LOAN_OFFICER)
	assert_dict(LoanRole.role_days).is_empty()
	var roles := SaveGame.dict_of(SaveGame.capture(), "roles")
	assert_dict(SaveGame.dict_of(roles, "loan")).is_empty()
	# A file open: kept, from its request on, and saved.
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	request_file(application, [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7])
	LoanRole.note_role(2, PlayerShift.Role.TELLER)
	assert_bool(LoanRole.role_days.has(2)).is_false()
	var career := through_json(SaveGame.capture())
	assert_bool(SaveGame.dict_of(SaveGame.dict_of(career, "roles"), "loan").has(LoanRole.ROLES_KEY)).is_true()
	CareerReset.reset_all()
	assert_dict(LoanRole.role_days).is_empty()
	SaveGame.restore(career)
	assert_int(LoanRole.role_days[6]).is_equal(PlayerShift.Role.LOAN_OFFICER)
	assert_int(LoanRole.role_days[7]).is_equal(PlayerShift.Role.LOAN_OFFICER)
	assert_int(LoanRole.role_days.size()).is_equal(2)
	# The file decided: the roles go with it.
	LoanRole.pipeline.close(LoanRole.pipeline.files[0].application)
	LoanRole.note_role(8, PlayerShift.Role.LOAN_OFFICER)
	assert_dict(LoanRole.role_days).is_empty()

func test_reloading_cannot_avoid_or_repeat_the_withdrawal() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	request_file(application, [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	# "Start Day N+1" saves before Opening runs, roles and all.
	GameClock.day = 9
	var before_opening := through_json(SaveGame.capture())
	var base := score_and_reputation()
	LoanRole.start_of_day()
	var penalty := Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION)
	assert_vector(score_and_reputation() - base).is_equal(penalty)
	# Quitting mid-day loses that day: loading the save replays Opening, and
	# the penalty is charged once again, not twice.
	for attempt in 3:
		SaveGame.restore(before_opening)
		assert_vector(score_and_reputation()).is_equal(base)
		assert_int(LoanRole.pipeline.files.size()).is_equal(1)
		assert_int(LoanRole.role_days.size()).is_equal(3)
		LoanRole.start_of_day()
		assert_vector(score_and_reputation() - base).is_equal(penalty)
		assert_bool(LoanRole.pipeline.is_empty()).is_true()
	# A save made after Opening has the file gone and the penalty in the score:
	# loading it and running Opening again charges nothing more.
	var after_opening := through_json(SaveGame.capture())
	SaveGame.restore(after_opening)
	assert_vector(score_and_reputation() - base).is_equal(penalty)
	LoanRole.start_of_day()
	LoanRole.start_of_day()
	assert_vector(score_and_reputation() - base).is_equal(penalty)

func test_quitting_mid_day_cannot_dodge_a_loan_officer_day_it_already_worked() -> void:
	# Day 8 is replayed from the save made before it: the role it ends up with
	# is the role of the day that counts, and the day before it still counts.
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7])
	GameClock.day = 8
	var before_day_8 := through_json(SaveGame.capture())
	# Worked as a Loan Officer, then quit before the day was saved.
	note_roles(LOAN, [8])
	SaveGame.restore(before_day_8)
	assert_bool(LoanRole.role_days.has(8)).is_false()
	# Replayed as a Loan Officer again: the third day counts, the file goes at day 9.
	note_roles(LOAN, [8])
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).has_size(1)

func test_going_home_early_cannot_avoid_the_withdrawal_or_repeat_it() -> void:
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	var base := score_and_reputation()
	start_business_day(9)
	var penalty := Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION)
	# Opening ran before the player could do anything.
	assert_vector(score_and_reputation() - base).is_equal(penalty)
	# Going home early skips the work slots; End of Day runs. Nothing more is charged.
	go_home_from_the_loan_desk()
	await run_end_of_day()
	assert_vector(score_and_reputation() - base).is_equal(penalty)
	assert_str(room.end_of_day_screen.summary_label.text).contains("Files withdrawn, not decided in time: ")

func test_a_file_that_never_returns_expires_quietly() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	var file := request_lost_file(application, [PAY_STUB])
	var start := score_and_reputation()
	for day in range(5, file.expire_day()):
		GameClock.day = day
		LoanRole.start_of_day()
		assert_array(LoanRole.pipeline.log_expired).is_empty()
	GameClock.day = file.expire_day()
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_array(LoanRole.pipeline.log_expired).is_equal([application.applicant_name])
	assert_vector(score_and_reputation()).is_equal(start)
	# Forgotten the day after.
	GameClock.day = file.expire_day() + 1
	LoanRole.start_of_day()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_vector(score_and_reputation()).is_equal(start)

func test_withdrawing_applies_each_file_once_and_only_overdue_ones() -> void:
	GameClock.day = 5
	var a := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	var b := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 7)
	var c := request_file(filed_application([PHOTO_ID]), [PHOTO_ID] as Array[int], 9)
	note_roles(LOAN, [6, 7, 8, 9, 10, 11, 12])
	var start := score_and_reputation()
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).is_equal([a])
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(-2, -1))
	GameClock.day = 11
	assert_array(LoanRole.start_of_day()).is_equal([b])
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(-4, -2))
	assert_array(LoanRole.pipeline.files).is_equal([c])

func test_a_file_sent_off_again_is_not_overdue_while_it_is_out() -> void:
	loan_day_at_9am()
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB] as Array[int], 5, LoanFile.Quality.INCOMPLETE, PAY_STUB)
	note_roles(LOAN, [6, 7])
	# Asked again on day 7: the clock now runs from its next return.
	GameClock.day = 7
	assert_object(LoanRole.request_documents(application, [PAY_STUB] as Array[int])).is_same(file)
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = 9
	note_roles(LOAN, [8, 9])
	GameClock.day = 9
	assert_bool(file.is_overdue(9, LoanRole.role_days)).is_false()
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_int(file.decide_by_day(9, LoanRole.role_days)).is_equal(11)

# --- the waiting list --------------------------------------------------------------

func test_the_waiting_list_names_each_file_and_marks_those_that_are_back() -> void:
	loan_day_at_9am()
	assert_bool(lo.files_vbox.visible).is_false()
	GameClock.day = 5
	var back := filed_application([PAY_STUB])
	back.applicant_name = "Ana Lopez"
	request_file(back, [PAY_STUB, STATEMENT] as Array[int], 5)
	var waiting := filed_application([PHOTO_ID])
	waiting.applicant_name = "Ben Hart"
	waiting.loan_purpose = "Auto"
	request_file(waiting, [PHOTO_ID] as Array[int], 8)
	var later := filed_application([STATEMENT])
	later.applicant_name = "Cy Diaz"
	var later_file := request_file(later, [STATEMENT, PHOTO_ID, PAY_STUB] as Array[int], 11)
	GameClock.day = 6
	var rows := LoanOfficerScreen.files_rows(GameClock.day)
	assert_int(rows.size()).is_equal(3)
	# Back first, marked, with its decide-by day.
	assert_str(rows[0]).is_equal("Ana Lopez · personal loan: back\nAsked for: Pay stub, Bank statement\nDecide by Wed 14 Jan (Loan Officer days)")
	# Then the others by due day.
	assert_str(rows[1]).is_equal("Ben Hart · auto loan\nAsked for: Valid photo ID\nDue " + BankCalendar.short_text(GameClock.date_of_day(waiting_due(waiting))))
	assert_str(rows[2]).contains("Cy Diaz · personal loan")
	assert_str(rows[2]).contains("Asked for: Bank statement, Valid photo ID, Pay stub")
	assert_str(rows[2]).contains("Due " + BankCalendar.short_text(later_file.due_date()))
	# On the screen.
	lo.show_screen()
	assert_bool(lo.files_vbox.visible).is_true()
	assert_str(lo.files_label.text).contains("Ana Lopez · personal loan: back")
	assert_str(lo.files_label.text).contains("Ben Hart · auto loan")

## The due day of `application`'s file.
func waiting_due(application: LoanApplication) -> int:
	return LoanRole.pipeline.file_for(application).due_day

func test_the_waiting_list_gives_nothing_away() -> void:
	loan_day_at_9am()
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB, STATEMENT] as Array[int], 7)
	# A file still out reads the same however it will answer.
	var reference := LoanOfficerScreen.files_rows(GameClock.day)
	assert_int(reference.size()).is_equal(1)
	for timing: int in [LoanFile.Timing.ON_TIME, LoanFile.Timing.LATE, LoanFile.Timing.NEVER]:
		for quality: int in [LoanFile.Quality.COMPLETE, LoanFile.Quality.INCOMPLETE, LoanFile.Quality.WRONG]:
			file.timing = timing as LoanFile.Timing
			file.quality = quality as LoanFile.Quality
			file.short_item = STATEMENT if quality == LoanFile.Quality.INCOMPLETE else -1
			file.wrong_item = PAY_STUB if quality == LoanFile.Quality.WRONG else -1
			file.return_day = 7 if timing == LoanFile.Timing.ON_TIME else (8 if timing == LoanFile.Timing.LATE else LoanFile.NEVER_DAY)
			assert_array(LoanOfficerScreen.files_rows(GameClock.day)).override_failure_message("timing %d quality %d" % [timing, quality]).is_equal(reference)
	# And a file that is back reads the same however well it came back.
	GameClock.day = 8
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = 8
	var back_reference := LoanOfficerScreen.files_rows(GameClock.day)
	for quality: int in [LoanFile.Quality.COMPLETE, LoanFile.Quality.INCOMPLETE, LoanFile.Quality.WRONG]:
		file.quality = quality as LoanFile.Quality
		file.short_item = STATEMENT if quality == LoanFile.Quality.INCOMPLETE else -1
		file.wrong_item = PAY_STUB if quality == LoanFile.Quality.WRONG else -1
		assert_array(LoanOfficerScreen.files_rows(GameClock.day)).is_equal(back_reference)
	# No words about how it will go.
	for row in reference + back_reference:
		for hidden: String in ["late", "never", "incomplete", "complete", "wrong", "expire", "will ", "%", "mismatch", "forged"]:
			assert_str(row.to_lower()).override_failure_message("'%s' in %s" % [hidden, row]).not_contains(hidden)

func test_the_waiting_list_is_hidden_with_no_files_and_adds_nothing_to_the_hud() -> void:
	loan_day_at_9am()
	lo.show_screen()
	assert_bool(lo.files_vbox.visible).is_false()
	var hud_before := room.hud.slot_label.text
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	lo.show_screen()
	assert_bool(lo.files_vbox.visible).is_true()
	assert_str(room.hud.slot_label.text).is_equal(hud_before)
	assert_str(loan_slot_adapter().status_text()).is_equal("Application: 0 / 1")

func test_the_waiting_list_fits_the_window() -> void:
	loan_day_at_9am()
	GameClock.day = 5
	for index in 3:
		var application := home_application()
		request_file(application, [PAY_STUB, STATEMENT, PHOTO_ID, APPRAISAL, DOWN_PAYMENT, LETTER] as Array[int], 5 + index)
	GameClock.day = 6
	lo.show_screen()
	await frames(4)
	var problems := layout_problems(lo.main_panel)
	problems.append_array(controls_line_problems(lo.main_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- the applicant's lines -----------------------------------------------------------

func test_the_applicant_says_what_they_brought() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	var purpose := LoanApplicantNPC.purpose_line(application.loan_purpose, 0)
	# Not asked for anything yet: what the loan is for.
	assert_str(LoanApplicantNPC.arrival_line(application, 0)).is_equal(purpose)
	var file := request_file(application, [PAY_STUB] as Array[int], GameClock.day)
	# On time and complete.
	assert_bool(LoanApplicantNPC.RETURN_LINES.has(LoanApplicantNPC.arrival_line(application, 0))).is_true()
	assert_bool(LoanApplicantNPC.RETURN_LINES.has(LoanApplicantNPC.arrival_line(application, 1))).is_true()
	assert_str(LoanApplicantNPC.RETURN_LINES[0]).is_equal("Here are the documents you asked for.")
	# Late.
	file.timing = LoanFile.Timing.LATE
	assert_bool(LoanApplicantNPC.RETURN_LATE_LINES.has(LoanApplicantNPC.arrival_line(application, 0))).is_true()
	# Incomplete, even when late.
	file.quality = LoanFile.Quality.INCOMPLETE
	file.short_item = PAY_STUB
	assert_bool(LoanApplicantNPC.RETURN_INCOMPLETE_LINES.has(LoanApplicantNPC.arrival_line(application, 0))).is_true()
	# Wrong: they don't know it, so they hand it over like any other.
	file.timing = LoanFile.Timing.ON_TIME
	file.quality = LoanFile.Quality.WRONG
	file.short_item = -1
	file.wrong_item = PAY_STUB
	assert_bool(LoanApplicantNPC.RETURN_LINES.has(LoanApplicantNPC.arrival_line(application, 0))).is_true()
	# Not back yet: no change.
	file.return_day = GameClock.day + 1
	assert_str(LoanApplicantNPC.arrival_line(application, 0)).is_equal(purpose)

func test_a_returned_applicant_walks_in_with_the_same_look_and_name_and_says_so() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	request_file(application, [PAY_STUB] as Array[int], GameClock.day, LoanFile.Quality.INCOMPLETE, PAY_STUB)
	room._process(0.0)
	var seat := room.player_loan_seat()
	assert_bool(seat.is_empty()).is_false()
	assert_object(seat.application).is_same(application)
	assert_str(seat.application.applicant_name).is_equal(application.applicant_name)
	assert_int(seat.applicant.look).is_equal(application.applicant_look)
	seat.seat_now()
	assert_bool(LoanApplicantNPC.RETURN_INCOMPLETE_LINES.has(seat.applicant._speech_label.text)).is_true()

# --- the End of Day lines -------------------------------------------------------------

func test_the_end_of_day_lines_for_returned_withdrawn_and_expired_files() -> void:
	GameClock.day = 5
	var back := filed_application([PAY_STUB])
	back.applicant_name = "Ana Lopez"
	request_file(back, [PAY_STUB] as Array[int], 9)
	var overdue := filed_application([STATEMENT])
	overdue.applicant_name = "Ben Hart"
	request_file(overdue, [STATEMENT] as Array[int], 5)
	var lost := filed_application([PHOTO_ID])
	lost.applicant_name = "Cy Diaz"
	var lost_file := request_lost_file(lost, [PHOTO_ID])
	# A day on which the first has come back, the second is withdrawn and the
	# third expires.
	lost_file.due_day = 6
	note_roles(LOAN, [6, 7, 8])
	GameClock.day = 9
	LoanRole.start_of_day()
	var lines := LoanBookManager.summary_lines(false)
	assert_array(Array(lines)).is_equal([
		"Files back with documents: Ana Lopez",
		"Files withdrawn, not decided in time: Ben Hart (-2 Score, -1 Reputation)",
		"Files that never came back: Cy Diaz",
	])
	# The same for the Branch Manager's whole-branch view.
	assert_array(Array(LoanBookManager.summary_lines(true))).is_equal(Array(lines))
	# Another day: none.
	GameClock.day = 10
	assert_array(Array(LoanBookManager.summary_lines(false))).is_empty()

func test_no_file_lines_when_there_are_no_files() -> void:
	GameClock.day = 9
	LoanRole.start_of_day()
	assert_array(Array(LoanBookManager.summary_lines(false))).is_empty()
	assert_bool(LoanRole.pipeline.log_day == 0).is_true()
	# And nothing extra saved.
	var roles := SaveGame.dict_of(SaveGame.capture(), "roles")
	assert_dict(SaveGame.dict_of(roles, "loan")).is_empty()

func test_the_end_of_day_lines_survive_a_save_and_a_reload() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	application.applicant_name = "Ben Hart"
	request_file(application, [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	GameClock.day = 9
	LoanRole.start_of_day()
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	SaveGame.restore(career)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Files withdrawn, not decided in time: Ben Hart (-2 Score, -1 Reputation)"])

func test_the_end_of_day_summary_shows_the_file_lines_and_fits() -> void:
	GameClock.day = 5
	var back := filed_application([PAY_STUB])
	back.applicant_name = "Ana Lopez"
	request_file(back, [PAY_STUB] as Array[int], 9)
	var overdue := filed_application([STATEMENT])
	overdue.applicant_name = "Ben Hart"
	request_file(overdue, [STATEMENT] as Array[int], 5)
	var lost := filed_application([PHOTO_ID])
	lost.applicant_name = "Cy Diaz"
	var lost_file := request_lost_file(lost, [PHOTO_ID])
	lost_file.due_day = 6
	note_roles(LOAN, [6, 7, 8])
	start_business_day(9)
	go_home_from_the_loan_desk()
	await run_end_of_day()
	var text := room.end_of_day_screen.summary_label.text
	assert_str(text).contains("Loans: Files back with documents: Ana Lopez")
	assert_str(text).contains("Files withdrawn, not decided in time: Ben Hart (-2 Score, -1 Reputation)")
	assert_str(text).contains("Files that never came back: Cy Diaz")
	await frames(4)
	var problems := layout_problems(room.end_of_day_screen.summary_panel)
	problems.append_array(controls_line_problems(room.end_of_day_screen.summary_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- saving ---------------------------------------------------------------------------

func test_a_returned_file_and_what_it_brought_survive_a_save_and_a_load() -> void:
	loan_day_at_9am()
	var application := home_application()
	var file := request_file(application, [APPRAISAL, STATEMENT] as Array[int], GameClock.day, LoanFile.Quality.INCOMPLETE, STATEMENT)
	LoanReturn.apply(file, LoanDeskManager.career_seed, GameClock.day)
	assert_array(file.papers).is_equal([APPRAISAL])
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	SaveGame.restore(career)
	var loaded := LoanRole.pipeline.files[0]
	assert_int(loaded.return_applied).is_equal(1)
	assert_array(loaded.papers).is_equal([APPRAISAL])
	assert_int(loaded.mismatched_paper).is_equal(-1)
	# Applying again after a load changes nothing.
	var saved := SaveGame.resource_to_dict(loaded.application)
	LoanReturn.apply(loaded, LoanDeskManager.career_seed, GameClock.day)
	assert_dict(SaveGame.resource_to_dict(loaded.application)).is_equal(saved)

func test_a_save_from_part_two_loads_with_no_return_applied() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 6)
	var data := file.save_data()
	data.erase("return_applied")
	var loaded := LoanFile.from_data(through_json(data))
	assert_int(loaded.return_applied).is_equal(0)

# --- fit ---------------------------------------------------------------------------------

func test_a_returned_applicants_documents_and_every_decision_state_fit_the_window() -> void:
	loan_day_at_9am()
	var home := home_application()
	request_file(home, [PAY_STUB, STATEMENT, PHOTO_ID, APPRAISAL, DOWN_PAYMENT, LETTER] as Array[int], GameClock.day, LoanFile.Quality.WRONG, -1, LETTER)
	open_desk()
	await assert_fits("returned, not verified")
	review.verify_documents_button.pressed.emit()
	assert_bool(review.papers_label.visible).is_true()
	await assert_fits("returned, documents shown with papers")
	review.run_credit_check_button.pressed.emit()
	await assert_fits("returned, decisions")
	review.reject_button.pressed.emit()
	await assert_fits("returned, the denial reasons")
	review.cancel_denial_button.pressed.emit()
	review.verify_documents_button.pressed.emit()
	review.request_button.pressed.emit()
	for check: CheckBox in review.request_checks.values():
		check.button_pressed = true
	await assert_fits("returned, the checklist")
