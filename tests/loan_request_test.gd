extends "res://tests/support/loan/loan_suite.gd"

## Part 2 of multi-day loan applications: the Request More Documents action
## on the review screen and its grading. The checklist's grading in every
## case (all right, a wrong tick, a missed item, nothing missing, a forged
## document), when the action is off and why, the teaching cases, a file
## joining the pipeline with the pile staying at three, the slot ending as
## before, no history record and no loan booked, the feedback, the document
## grading that moved with it, the exploit arithmetic, and every state
## fitting the window.

const PAY_STUB := LoanRequirements.Item.PAY_STUB
const STATEMENT := LoanRequirements.Item.BANK_STATEMENT
const PHOTO_ID := LoanRequirements.Item.PHOTO_ID
const APPRAISAL := LoanRequirements.Item.APPRAISAL
const DOWN_PAYMENT := LoanRequirements.Item.DOWN_PAYMENT_PROOF
const LETTER := LoanRequirements.Item.EXPLANATION_LETTER

var lo: LoanOfficerScreen
var review: LoanReviewScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	lo = room.loan_officer_screen
	review = lo.loan_review_screen
	# The staff desks' own walk-ins aren't part of these tests.
	for worker in room.loan_desk_workers:
		worker.active = false

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

## A Loan Officer day, clocked in at Opening, with 9 AM started.
func loan_day_at_9am() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)

## A generated applicant whose documents are all fine except `missing` (any of
## the pay stub, the statement and the ID), for a purpose with no appraisal or
## down payment and a clean credit history, so exactly `missing` is truly
## missing.
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

## Puts `application` first in the pile (which stays three) and opens it at the
## desk, its documents verified unless `verify` is false.
func open_on_desk(application: LoanApplication, verified: bool = true) -> LoanApplication:
	LoanDeskManager.current_player_application()
	LoanDeskManager.player_queue[0] = application
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	assert_object(review.current_application()).is_same(application)
	if verified:
		review.verify_documents_button.pressed.emit()
	return application

func tick_items(items: Array[int]) -> void:
	for item in items:
		review.request_checks[item].button_pressed = true

## Opens the checklist and ticks `items`.
func open_checklist(items: Array[int]) -> void:
	review.request_button.pressed.emit()
	tick_items(items)

func assert_fits(label: String = "") -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	assert_array(problems).override_failure_message("%s\n%s" % [label, "\n".join(problems)]).is_empty()

func graded(application: LoanApplication, ticked: Array[int], missing: Array[int]) -> Dictionary:
	return LoanRequirements.grade_request(application, ticked, missing)

# --- the numbers -----------------------------------------------------------------

func test_the_grading_numbers_are_in_the_loan_config() -> void:
	assert_int(LoanConfig.REQUEST_RIGHT_SCORE).is_equal(3)
	assert_int(LoanConfig.REQUEST_WRONG_TICK_SCORE).is_equal(-1)
	assert_int(LoanConfig.REQUEST_MISSED_ITEM_SCORE).is_equal(-1)
	assert_int(LoanConfig.REQUEST_COMPLETE_FILE_SCORE).is_equal(-2)
	assert_int(LoanConfig.REQUEST_FORGED_SCORE).is_equal(-3)
	assert_int(LoanConfig.REQUEST_REPUTATION).is_equal(0)

# --- grading the checklist -------------------------------------------------------

func test_a_checklist_that_is_exactly_right_earns_the_reward() -> void:
	var application := filed_application([PAY_STUB, STATEMENT])
	var result := graded(application, [PAY_STUB, STATEMENT], [PAY_STUB, STATEMENT])
	assert_int(result["kind"]).is_equal(LoanRequirements.RequestKind.EXACT)
	assert_int(result["score"]).is_equal(3)
	assert_int(result["reputation"]).is_equal(0)
	assert_array(result["right"]).is_equal([PAY_STUB, STATEMENT])
	assert_array(result["wrong"]).is_empty()
	assert_array(result["missed"]).is_empty()

func test_one_wrong_tick_costs_a_point_and_the_reward() -> void:
	var application := filed_application([PAY_STUB, STATEMENT])
	var result := graded(application, [PAY_STUB, STATEMENT, PHOTO_ID], [PAY_STUB, STATEMENT])
	assert_int(result["kind"]).is_equal(LoanRequirements.RequestKind.OFF)
	assert_int(result["score"]).is_equal(-1)
	assert_array(result["wrong"]).is_equal([PHOTO_ID])
	assert_array(result["missed"]).is_empty()

func test_one_missed_item_costs_a_point_and_the_reward() -> void:
	var application := filed_application([PAY_STUB, STATEMENT])
	var result := graded(application, [PAY_STUB], [PAY_STUB, STATEMENT])
	assert_int(result["kind"]).is_equal(LoanRequirements.RequestKind.OFF)
	assert_int(result["score"]).is_equal(-1)
	assert_array(result["right"]).is_equal([PAY_STUB])
	assert_array(result["missed"]).is_equal([STATEMENT])

func test_a_wrong_tick_and_a_missed_item_each_cost_a_point() -> void:
	var application := filed_application([PAY_STUB])
	var result := graded(application, [PHOTO_ID, STATEMENT], [PAY_STUB])
	assert_int(result["score"]).is_equal(-3)
	assert_array(result["wrong"]).is_equal([PHOTO_ID, STATEMENT])
	assert_array(result["missed"]).is_equal([PAY_STUB])

func test_a_request_on_a_complete_file_costs_two_however_much_is_ticked() -> void:
	var application := filed_application([])
	var one: Array[int] = [PAY_STUB]
	var three: Array[int] = [PAY_STUB, STATEMENT, PHOTO_ID]
	for index in 2:
		var ticked := one if index == 0 else three
		var result := graded(application, ticked, [])
		assert_int(result["kind"]).is_equal(LoanRequirements.RequestKind.COMPLETE_FILE)
		assert_int(result["score"]).is_equal(-2)
		assert_int(result["reputation"]).is_equal(0)

func test_a_request_on_a_forged_document_is_wrong() -> void:
	var problems := [
		[LoanApplication.DocProblem.OVERSTATED_INCOME, IdCard.Problem.NONE],
		[LoanApplication.DocProblem.STUB_NAME, IdCard.Problem.NONE],
		[LoanApplication.DocProblem.NONE, IdCard.Problem.NAME_MISMATCH],
		[LoanApplication.DocProblem.NONE, IdCard.Problem.WRONG_PORTRAIT],
	]
	for problem: Array in problems:
		var application := filed_application([])
		application.doc_problem = problem[0]
		application.id_problem = problem[1]
		assert_bool(application.has_forged_document()).is_true()
		# Nothing missing, or something ticked that is: wrong either way.
		var result := graded(application, [PAY_STUB], [])
		assert_int(result["kind"]).is_equal(LoanRequirements.RequestKind.FORGED)
		assert_int(result["score"]).is_equal(-3)
		assert_int(graded(application, [PAY_STUB], [PAY_STUB])["score"]).is_equal(-3)

func test_what_counts_as_missing_and_what_as_forged() -> void:
	var application := filed_application([])
	for doc_problem: int in [LoanApplication.DocProblem.MISSING_STUB, LoanApplication.DocProblem.MISSING_STATEMENT]:
		application.doc_problem = doc_problem as LoanApplication.DocProblem
		assert_bool(application.has_forged_document()).is_false()
		assert_bool(application.is_missing_documents_only()).is_true()
	application.doc_problem = LoanApplication.DocProblem.NONE
	for id_problem: int in [IdCard.Problem.NO_ID, IdCard.Problem.EXPIRED]:
		application.id_problem = id_problem as IdCard.Problem
		assert_bool(application.is_missing_documents_only()).is_true()
	application.id_problem = IdCard.Problem.NONE
	assert_bool(application.is_missing_documents_only()).is_false()
	assert_bool(application.has_forged_document()).is_false()

# --- when the action is off ------------------------------------------------------

func test_it_is_off_until_the_documents_are_verified_and_needs_no_credit_check() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]), false)
	assert_bool(review.request_row.visible).is_true()
	assert_bool(review.request_button.visible).is_true()
	assert_bool(review.request_button.disabled).is_true()
	assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_VERIFY_FIRST_TEXT)
	review.verify_documents_button.pressed.emit()
	assert_bool(review.request_button.disabled).is_false()
	assert_str(review.request_note_label.text).is_equal("")
	# No credit check yet: the decisions stay locked, the request is open.
	assert_bool(review.credit_checked).is_false()
	assert_bool(review.decision_hbox.visible).is_false()
	review.request_button.pressed.emit()
	assert_bool(review.request_vbox.visible).is_true()

func test_it_is_off_when_three_files_are_already_open() -> void:
	loan_day_at_9am()
	for index in 3:
		LoanRole.request_documents(filed_application([PAY_STUB]), [PAY_STUB] as Array[int])
	open_on_desk(filed_application([PAY_STUB]))
	assert_bool(review.request_button.disabled).is_true()
	assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_FULL_TEXT)
	assert_str(LoanReviewScreen.request_block_reason(review.current_application(), true, GameClock.day)).is_equal(LoanReviewScreen.REQUEST_FULL_TEXT)
	# A place frees up once a file's applicant never comes back and it expires.
	var expiry := LoanRole.pipeline.files[0].expire_day()
	for file in LoanRole.pipeline.files:
		file.timing = LoanFile.Timing.NEVER
		file.return_day = LoanFile.NEVER_DAY
	assert_str(LoanReviewScreen.request_block_reason(review.current_application(), true, expiry)).is_equal("")

func test_it_is_off_for_a_file_that_has_already_asked_twice_or_is_still_out() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	var file := LoanRole.request_documents(application, [PAY_STUB] as Array[int])
	# Still out.
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = GameClock.day + 1
	assert_str(LoanReviewScreen.request_block_reason(application, true, GameClock.day)).is_equal(LoanReviewScreen.REQUEST_STILL_OUT_TEXT)
	# Back: asking again is fine, a third time isn't.
	file.return_day = GameClock.day
	assert_str(LoanReviewScreen.request_block_reason(application, true, GameClock.day)).is_equal("")
	file.request_count = 2
	assert_str(LoanReviewScreen.request_block_reason(application, true, GameClock.day)).is_equal(LoanReviewScreen.REQUEST_TWICE_TEXT)
	open_on_desk(application)
	assert_bool(review.request_button.disabled).is_true()
	assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_TWICE_TEXT)

func test_the_teaching_cases_have_no_request_button_and_say_why() -> void:
	loan_day_at_9am()
	# A new career's first applicants are the three teaching cases.
	for index in 3:
		var teaching := LoanDeskManager.player_queue[index]
		assert_bool(LoanApplicationsData.is_teaching_case(teaching.applicant_name)).is_true()
		open_on_desk(teaching)
		assert_bool(review.request_row.visible).is_true()
		assert_bool(review.request_button.visible).is_false()
		assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_TEACHING_TEXT)
		review.close_button.pressed.emit()
	# A generated applicant has it.
	open_on_desk(filed_application([PAY_STUB]))
	assert_bool(review.request_button.visible).is_true()
	assert_bool(LoanApplicationsData.is_teaching_case(review.current_application().applicant_name)).is_false()

func test_the_request_row_goes_while_something_else_is_open_or_after_a_decision() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]))
	review.run_credit_check_button.pressed.emit()
	assert_bool(review.request_row.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_true()
	review.reject_button.pressed.emit()
	assert_bool(review.request_row.visible).is_false()
	review.cancel_denial_button.pressed.emit()
	assert_bool(review.request_row.visible).is_true()
	review.counter_offer_button.pressed.emit()
	assert_bool(review.request_row.visible).is_false()
	review.cancel_counter_offer_button.pressed.emit()
	assert_bool(review.request_row.visible).is_true()
	# The checklist, and cancelling it brings the decisions back.
	review.request_button.pressed.emit()
	assert_bool(review.request_row.visible).is_false()
	assert_bool(review.decision_hbox.visible).is_false()
	review.cancel_request_button.pressed.emit()
	assert_bool(review.request_vbox.visible).is_false()
	assert_bool(review.decision_hbox.visible).is_true()
	assert_bool(review.request_row.visible).is_true()
	# Decided: gone.
	review.approve_button.pressed.emit()
	assert_bool(review.request_row.visible).is_false()

# --- the checklist ---------------------------------------------------------------

func test_the_checklist_shows_only_the_items_that_apply() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	open_on_desk(application)
	review.request_button.pressed.emit()
	assert_array(review.request_checks.keys()).is_equal([PAY_STUB, STATEMENT, PHOTO_ID])
	assert_bool(review.confirm_request_button.disabled).is_true()
	review.cancel_request_button.pressed.emit()
	# A home loan with a purchase, and a late payment on the report: all six.
	var home := filed_application([])
	home.loan_purpose = "Home"
	home.collateral_issued = true
	home.collateral_kind = LoanApplication.Collateral.HOUSE
	home.purchase_price = home.requested_amount + 40000.0
	home.collateral_value = home.purchase_price
	home.late_30_days = 1
	assert_bool(LoanRequirements.applies(home, APPRAISAL)).is_true()
	assert_bool(LoanRequirements.applies(home, DOWN_PAYMENT)).is_true()
	assert_bool(LoanRequirements.applies(home, LETTER)).is_true()
	review.close_button.pressed.emit()
	open_on_desk(home)
	review.request_button.pressed.emit()
	assert_array(review.request_checks.keys()).is_equal([PAY_STUB, STATEMENT, PHOTO_ID, APPRAISAL, DOWN_PAYMENT, LETTER])

func test_confirming_needs_a_tick() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]))
	review.request_button.pressed.emit()
	assert_bool(review.confirm_request_button.disabled).is_true()
	tick_items([PAY_STUB] as Array[int])
	assert_bool(review.confirm_request_button.disabled).is_false()
	review.request_checks[PAY_STUB].button_pressed = false
	assert_bool(review.confirm_request_button.disabled).is_true()
	# Nothing is sent by pressing it with nothing ticked.
	review.confirm_request_button.pressed.emit()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()

# --- sending the request ---------------------------------------------------------

func test_confirming_sends_the_file_into_the_pipeline_and_keeps_the_pile_at_three() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB, STATEMENT])
	open_on_desk(application)
	var pile_before := LoanDeskManager.player_queue.duplicate()
	var generated_before := LoanDeskManager.generated_count
	open_checklist([PAY_STUB, STATEMENT])
	review.confirm_request_button.pressed.emit()

	assert_int(LoanRole.pipeline.files.size()).is_equal(1)
	var file := LoanRole.pipeline.files[0]
	assert_object(file.application).is_same(application)
	assert_array(file.items).is_equal([PAY_STUB, STATEMENT])
	assert_int(file.request_count).is_equal(1)
	assert_int(file.request_day).is_equal(GameClock.day)
	assert_int(file.due_day).is_equal(GameClock.day + 3)
	# The same deterministic return as the pipeline rolls anywhere.
	var again := LoanFile.new()
	again.number = file.number
	again.request_count = 1
	again.items = file.items
	again.due_day = file.due_day
	again.roll(LoanDeskManager.career_seed)
	assert_int(again.timing).is_equal(file.timing)
	assert_int(again.return_day).is_equal(file.return_day)
	assert_int(again.quality).is_equal(file.quality)
	# Off the pile, a new applicant in, the pile still three.
	assert_int(LoanDeskManager.player_queue.size()).is_equal(3)
	assert_bool(LoanDeskManager.player_queue.has(application)).is_false()
	assert_int(LoanDeskManager.generated_count).is_equal(generated_before + 1)
	assert_object(LoanDeskManager.player_queue[0]).is_same(pile_before[1])
	# Not a decision.
	assert_int(application.decision).is_equal(LoanApplication.DecisionType.NONE)
	# And the applicant's name stays theirs.
	assert_bool(LoanDeskManager.names_taken().has(application.applicant_name)).is_true()

func test_a_request_writes_no_history_record_and_books_nothing() -> void:
	loan_day_at_9am()
	var records_before := HistoryManager.records.size()
	var book_before := LoanBookManager.book.size()
	var seen_before := LoanBookManager.stat(LoanBookManager.period_stats, "good_seen")
	var turned_before := LoanBookManager.stat(LoanBookManager.period_stats, "turned_away")
	open_on_desk(filed_application([PAY_STUB]))
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_int(HistoryManager.records.size()).is_equal(records_before)
	assert_int(LoanBookManager.book.size()).is_equal(book_before)
	assert_float(LoanBookManager.stat(LoanBookManager.period_stats, "good_seen")).is_equal(seen_before)
	assert_float(LoanBookManager.stat(LoanBookManager.period_stats, "turned_away")).is_equal(turned_before)

func test_the_request_applies_its_score_xp_and_no_reputation() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB, STATEMENT]))
	var start := totals()
	open_checklist([PAY_STUB, STATEMENT])
	review.confirm_request_button.pressed.emit()
	assert_vector(totals() - start).is_equal(Vector3i(3, 0, 3 * XPManager.XP_PER_SCORE_POINT))
	# A request on a complete file: -2 Score, XP never below nothing.
	review.close_button.pressed.emit()
	continue_to_slot(DaySchedule.SLOT_11AM)
	open_on_desk(filed_application([]))
	start = totals()
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_int(totals().x - start.x).is_equal(-2)
	assert_int(totals().y - start.y).is_equal(0)
	assert_int(totals().z).is_greater_equal(0)

func test_the_request_counts_as_the_slots_application_and_the_slot_ends_as_before() -> void:
	loan_day_at_9am()
	var adapter := loan_slot_adapter()
	assert_str(adapter.status_text()).is_equal("Application: 0 / 1")
	assert_str(LoanSlotAdapter.STATUS_TEXT % [0, 1]).is_equal("Application: 0 / 1")
	assert_str(LoanSlotAdapter.REPORT_TEXT % 1).is_equal("Applications decided: 1")
	open_on_desk(filed_application([PAY_STUB]))
	open_checklist([PAY_STUB])
	var signalled: Array = []
	review.decision_graded.connect(func(score: int, reputation: int, xp: int) -> void: signalled.append([score, reputation, xp]))
	review.confirm_request_button.pressed.emit()
	assert_array(signalled).is_equal([[3, 0, 3 * XPManager.XP_PER_SCORE_POINT]])
	assert_int(lo.applications_reviewed).is_equal(1)
	# The slot waits for the screen to close, then ends exactly as it does for a decision.
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	review.close_button.pressed.emit()
	lo.hide_screen()
	await frames(3)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)
	assert_int(lo.applications_left()).is_equal(0)
	# The card reports it the way it reports a decision.
	assert_str(slot_card().done_label.text).is_equal("9 AM slot done
Applications decided: 1")

func test_the_applicant_leaves_through_the_existing_leave_flow() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	LoanDeskManager.player_queue[0] = application
	room._process(0.0)
	var seat := room.player_loan_seat()
	assert_bool(seat.is_empty()).is_false()
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	review.verify_documents_button.pressed.emit()
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	assert_bool(LoanApplicantNPC.REQUEST_LINES.has(LoanApplicantNPC.reaction_line(application, 0))).is_true()
	assert_bool(LoanApplicantNPC.REQUEST_LINES.has(LoanApplicantNPC.reaction_line(application, 1))).is_true()

func test_a_request_refused_at_confirm_says_so_and_changes_nothing() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	open_on_desk(application)
	open_checklist([PAY_STUB])
	# Meanwhile the pipeline fills up (something changed since it opened).
	for index in 3:
		LoanRole.request_documents(filed_application([PAY_STUB]), [PAY_STUB] as Array[int])
	var pile_before := LoanDeskManager.player_queue.duplicate()
	var generated_before := LoanDeskManager.generated_count
	var start := totals()
	var graded_signals: Array = []
	review.decision_graded.connect(func(score: int, reputation: int, xp: int) -> void: graded_signals.append([score, reputation, xp]))
	review.confirm_request_button.pressed.emit()
	# A short message on the screen, in place of silence.
	assert_bool(review.decision_status_label.visible).is_true()
	assert_str(review.decision_status_label.text).is_equal("Request not sent: " + LoanReviewScreen.REQUEST_FULL_TEXT)
	# The panel is closed and the decisions are back, the application still on the desk.
	assert_bool(review.request_vbox.visible).is_false()
	assert_object(review.current_application()).is_same(application)
	# Nothing else happened: no file, no new applicant, no points, no slot used.
	assert_int(LoanRole.pipeline.files.size()).is_equal(3)
	assert_object(LoanRole.pipeline.file_for(application)).is_null()
	assert_array(LoanDeskManager.player_queue).is_equal(pile_before)
	assert_int(LoanDeskManager.generated_count).is_equal(generated_before)
	assert_vector(totals() - start).is_equal(Vector3i.ZERO)
	assert_array(graded_signals).is_empty()
	assert_int(lo.applications_reviewed).is_equal(0)
	assert_int(application.decision).is_equal(LoanApplication.DecisionType.NONE)
	# The button now says why it is off.
	assert_bool(review.request_button.disabled).is_true()
	assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_FULL_TEXT)
	await assert_fits("refusal message")
	# Reopening the checklist clears the message.
	LoanRole.pipeline.reset()
	review.verify_documents_button.pressed.emit()
	assert_bool(review.request_button.disabled).is_false()
	review.request_button.pressed.emit()
	assert_bool(review.decision_status_label.visible).is_false()

func test_each_reason_a_request_can_be_refused_has_a_line() -> void:
	assert_str(LoanReviewScreen.request_refusal_text(LoanPipeline.Refusal.FULL)).is_equal(LoanReviewScreen.REQUEST_FULL_TEXT)
	assert_str(LoanReviewScreen.request_refusal_text(LoanPipeline.Refusal.TOO_MANY_REQUESTS)).is_equal(LoanReviewScreen.REQUEST_TWICE_TEXT)
	assert_str(LoanReviewScreen.request_refusal_text(LoanPipeline.Refusal.STILL_OUT)).is_equal(LoanReviewScreen.REQUEST_STILL_OUT_TEXT)
	assert_str(LoanReviewScreen.request_refusal_text(LoanPipeline.Refusal.NO_ITEMS)).is_equal(LoanReviewScreen.REQUEST_NO_ITEMS_TEXT)
	assert_str(LoanReviewScreen.request_refusal_text(LoanPipeline.Refusal.UNKNOWN_ITEM)).is_equal(LoanReviewScreen.REQUEST_NO_ITEMS_TEXT)

# --- the feedback ----------------------------------------------------------------

func test_the_feedback_names_what_was_right_and_what_was_missed() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB, STATEMENT]))
	open_checklist([PAY_STUB, PHOTO_ID])
	review.confirm_request_button.pressed.emit()
	var text := review.decision_status_label.text
	assert_bool(review.decision_status_label.visible).is_true()
	assert_str(text).contains("Request sent: Pay stub, Valid photo ID. Due ")
	assert_str(text).contains("The checklist was partly off (-2 Score, +0 Reputation, -20 XP)")
	assert_str(text).contains("Right: Pay stub.")
	assert_str(text).contains("Not missing: Valid photo ID.")
	assert_str(text).contains("Missed: Bank statement.")
	await assert_fits("feedback")

func test_the_feedback_for_each_kind_of_request() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]))
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_str(review.decision_status_label.text).contains("Right documents asked for (+3 Score")
	assert_str(review.decision_status_label.text).contains("Right: Pay stub.")
	review.close_button.pressed.emit()
	continue_to_slot(DaySchedule.SLOT_11AM)
	open_on_desk(filed_application([]))
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_str(review.decision_status_label.text).contains("No documents were needed (-2 Score")
	assert_str(review.decision_status_label.text).contains("Nothing was missing from this file.")
	review.close_button.pressed.emit()
	continue_to_slot(DaySchedule.SLOT_1PM)
	var forged := filed_application([])
	forged.doc_problem = LoanApplication.DocProblem.STUB_NAME
	open_on_desk(forged)
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	assert_str(review.decision_status_label.text).contains("A request can't fix a forged document (-3 Score")
	assert_str(review.decision_status_label.text).contains("Reject it as unverifiable.")

func test_the_feedback_gives_no_more_than_right_wrong_and_missed() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]))
	open_checklist([PAY_STUB])
	review.confirm_request_button.pressed.emit()
	var text := review.decision_status_label.text
	# Nothing about when or how the applicant will answer.
	for hidden: String in ["return", "late", "never", "incomplete", "complete", "expire", "%"]:
		assert_str(text.to_lower()).not_contains(hidden)

# --- the document grading that moved ---------------------------------------------

func test_rejecting_missing_documents_through_the_screen_is_only_partial() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([PAY_STUB]))
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_RIGHT_SCORE
	assert_vector(totals() - start).is_equal(Vector3i(score, 0, score * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).contains("asking the applicant to bring the missing documents")
	assert_str(review.decision_status_label.text).not_contains("Good catch")

func test_rejecting_a_forged_document_through_the_screen_is_still_the_best_call() -> void:
	loan_day_at_9am()
	var forged := filed_application([])
	forged.doc_problem = LoanApplication.DocProblem.STUB_NAME
	open_on_desk(forged)
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.BEST_DECISION_SCORE + LoanApplication.REASON_RIGHT_SCORE
	assert_vector(totals() - start).is_equal(Vector3i(score, LoanApplication.BEST_DECISION_REPUTATION, score * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).contains("Good catch")

func test_approving_on_missing_documents_is_still_a_serious_mistake() -> void:
	loan_day_at_9am()
	open_on_desk(filed_application([STATEMENT]))
	review.run_credit_check_button.pressed.emit()
	var start := totals()
	review.approve_button.pressed.emit()
	assert_int(totals().x - start.x).is_equal(LoanApplication.WORST_DECISION_SCORE)
	assert_str(review.decision_status_label.text).contains("Serious: the income or identity was never verified")

# --- the exploit arithmetic ------------------------------------------------------

## Per slot, deciding a good file at once is worth the correct decision (10);
## a request followed by its decision takes two slots, and a request on a file
## with nothing missing costs points on top. So asking is never the way to
## earn more per slot, and on everything it loses.
func test_asking_never_beats_deciding_at_once_per_slot() -> void:
	var best := LoanApplication.BEST_DECISION_SCORE
	# A good file, decided at once: one slot.
	var at_once := float(best)
	# The same file asked about first (wrongly: nothing was missing), then
	# decided once the applicant is back: two slots.
	var asked_first := float(LoanConfig.REQUEST_COMPLETE_FILE_SCORE + best) / 2.0
	assert_float(asked_first).is_less(at_once)
	# Even a right request on a file that was missing something, then its
	# decision, earns less per slot than a good file decided at once.
	var right_then_decided := float(LoanConfig.REQUEST_RIGHT_SCORE + best) / 2.0
	assert_float(right_then_decided).is_less(at_once)
	# Requesting on everything: a wrong one (-2, or -3 on a forged file) every
	# slot never earns anything.
	assert_int(LoanConfig.REQUEST_COMPLETE_FILE_SCORE).is_less(0)
	assert_int(LoanConfig.REQUEST_FORGED_SCORE).is_less(0)
	# For missing documents, a request then its decision beats rejecting at
	# once (partial credit and the reason): that is the point of the action.
	var rejected_at_once := float(LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_RIGHT_SCORE)
	assert_float(right_then_decided).is_greater(rejected_at_once)
	# A file asked about and never answered earns its request and no more: one
	# slot for at most +3.
	assert_int(LoanConfig.REQUEST_RIGHT_SCORE).is_less(best)

func test_the_caps_stop_parking_files() -> void:
	# Three open files at most, two requests each: a fourth is refused until
	# one is decided or expires.
	loan_day_at_9am()
	var apps: Array[LoanApplication] = []
	for index in 4:
		apps.append(filed_application([PAY_STUB]))
	for index in 3:
		assert_object(LoanRole.request_documents(apps[index], [PAY_STUB] as Array[int])).is_not_null()
	assert_object(LoanRole.request_documents(apps[3], [PAY_STUB] as Array[int])).is_null()
	assert_int(LoanRole.pipeline.open_count(GameClock.day)).is_equal(LoanConfig.PIPELINE_MAX)

# --- fit ---------------------------------------------------------------------------

func test_every_state_of_the_request_fits_the_window() -> void:
	loan_day_at_9am()
	var home := filed_application([])
	home.loan_purpose = "Home"
	home.collateral_issued = true
	home.collateral_kind = LoanApplication.Collateral.HOUSE
	home.purchase_price = home.requested_amount + 40000.0
	home.collateral_value = home.purchase_price
	home.late_30_days = 1
	var cases: Array[LoanApplication] = [filed_application([PAY_STUB]), home, LoanDeskManager.player_queue[0]]
	for application in cases:
		open_on_desk(application, false)
		await assert_fits("%s: not verified" % application.applicant_name)
		review.verify_documents_button.pressed.emit()
		await assert_fits("%s: documents shown, request offered" % application.applicant_name)
		review.run_credit_check_button.pressed.emit()
		await assert_fits("%s: decisions and request" % application.applicant_name)
		if review.request_button.visible and not review.request_button.disabled:
			review.request_button.pressed.emit()
			for check: CheckBox in review.request_checks.values():
				check.button_pressed = true
			await assert_fits("%s: the checklist, everything ticked" % application.applicant_name)
			review.cancel_request_button.pressed.emit()
		review.close_button.pressed.emit()

## The review screen's tallest states, measured: the request checklist with
## all six items ticked, and the eight-reason denial state (documents shown, the
## credit check run). Each stays inside the 648 px window with the window
## margin to spare, left of the HUD column, and clear of the controls line.
## The numbers are printed so a failure (or a curious reader) sees them.
func test_the_tallest_states_are_measured_inside_the_window() -> void:
	loan_day_at_9am()
	var home := filed_application([])
	home.loan_purpose = "Home"
	home.collateral_issued = true
	home.collateral_kind = LoanApplication.Collateral.HOUSE
	home.purchase_price = home.requested_amount + 40000.0
	home.collateral_value = home.purchase_price
	home.late_30_days = 1
	open_on_desk(home)
	review.run_credit_check_button.pressed.emit()

	# 1. The checklist, all six items ticked.
	review.request_button.pressed.emit()
	assert_int(review.request_checks.size()).is_equal(6)
	for check: CheckBox in review.request_checks.values():
		check.button_pressed = true
	await frames(4)
	var checklist := measure_panel()
	review.cancel_request_button.pressed.emit()

	# 2. The denial reasons, all eight offered.
	review.reject_button.pressed.emit()
	assert_int(review.reason_checks.size()).is_equal(8)
	await frames(4)
	var denial := measure_panel()
	print("Review screen, tallest states (px): checklist height %.1f, bottom %.1f, clear of the controls line by %.1f, of the window's bottom by %.1f, of the HUD column by %.1f | denial height %.1f, bottom %.1f, controls %.1f, window %.1f, HUD %.1f" % [
		checklist["height"], checklist["bottom"], checklist["controls_clearance"], checklist["window_clearance"], checklist["hud_clearance"],
		denial["height"], denial["bottom"], denial["controls_clearance"], denial["window_clearance"], denial["hud_clearance"]])
	for measured: Dictionary in [checklist, denial]:
		assert_float(measured["height"]).is_less_equal(648.0 - 2.0 * WINDOW_MARGIN)
		assert_float(measured["window_clearance"]).is_greater_equal(WINDOW_MARGIN)
		assert_float(measured["hud_clearance"]).is_greater_equal(0.0)
		assert_float(measured["controls_clearance"]).is_greater(0.0)
	# The checklist is no taller than the old tallest state, plus a pixel of rounding.
	var checklist_height: float = checklist["height"]
	var denial_height: float = denial["height"]
	assert_float(checklist_height).is_less_equal(denial_height + 1.0)

## The review panel's measurements now, in pixels: its height and bottom edge,
## and how clear it is of the controls line (above its top), of the window's
## bottom and of the HUD column.
func measure_panel() -> Dictionary:
	var rect := review.main_panel.get_global_rect()
	var controls := room.hud.controls_panel.get_global_rect()
	return {
		"height": rect.size.y,
		"bottom": rect.end.y,
		"controls_clearance": controls.position.y - rect.end.y,
		"window_clearance": 648.0 - rect.end.y,
		"hud_clearance": HUD_COLUMN_LEFT - rect.end.x,
	}
