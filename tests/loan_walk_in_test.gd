extends "res://tests/support/teller_room_suite.gd"

## Loan applicants in the room: walking in through the entrance to a loan
## desk, sitting down, saying what the loan is for and leaving after the
## decision with a reaction (LoanDeskSeat, LoanApplicantNPC), at the player's
## Loan Desk 1 and the staff desks; seats and paths that never overlap; the
## documents checked through the review screen (Verify Documents), graded and
## fitting the window; and staff loan officers' document checks, their misses
## going to staff review (Serious when they lent on them, Minor when not).

var lo: LoanOfficerScreen
var review: LoanReviewScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	lo = room.loan_officer_screen
	review = lo.loan_review_screen

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			return application
	return null

## Sample `applicant_name` with documents showing `doc_problem` and/or
## `id_problem`, from the real generator (seeds tried in turn).
func with_problem(applicant_name: String, doc_problem: LoanApplication.DocProblem, id_problem: IdCard.Problem = IdCard.Problem.NONE, new_name: String = "") -> LoanApplication:
	var application := sample(applicant_name)
	if new_name != "":
		application.applicant_name = new_name
	for i in 5000:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		LoanApplicantGenerator.issue_documents(application, rng, GameClock.today_date())
		if application.doc_problem == doc_problem and application.id_problem == id_problem:
			return application
	return null

func open_next(application: LoanApplication) -> void:
	LoanDeskManager.player_queue.push_front(application)
	lo.applications_reviewed = 0
	lo.review_next_button.pressed.emit()
	assert_object(review.current_application()).is_same(application)

func assert_fits() -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

func speech(npc: StaffNPC) -> String:
	return (npc.get_node("SpeechLabel") as Label).text

# --- the player's desk -----------------------------------------------------------

func test_an_applicant_walks_in_sits_down_and_leaves_after_the_decision() -> void:
	# The staff desks' own walk-ins would share the entrance corridor.
	for worker in room.loan_desk_workers:
		worker.active = false
	clock_in_at_loan_desk()
	lo.close_button.pressed.emit()
	var seat := room.player_loan_seat()
	assert_bool(seat.is_empty()).is_true()
	# The pile's next applicant comes in through the entrance.
	room._process(0.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	var applicant := seat.applicant
	var application := seat.application
	assert_object(application).is_same(LoanDeskManager.player_queue[0])
	assert_vector(applicant.global_position).is_equal(LoanDeskSeat.ENTRANCE)
	assert_int(applicant.look).is_equal(application.applicant_look)
	await frames(30)
	assert_float(applicant.global_position.y).is_less(LoanDeskSeat.ENTRANCE.y)
	# Seated at Loan Desk 1, saying what the loan is for.
	applicant.finish_route()
	assert_bool(seat.is_seated()).is_true()
	assert_vector(applicant.global_position).is_equal(LoanDeskSeat.SEATS[ScheduleManager.SLOT_LOAN_DESK_1])
	var lines: Array = LoanApplicantNPC.PURPOSE_LINES[application.loan_purpose]
	assert_bool(lines.has(speech(applicant))).override_failure_message(speech(applicant)).is_true()

	# The review shows them; approved, they leave pleased.
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	assert_object(review.current_application()).is_same(application)
	assert_object(seat.applicant).is_same(applicant)
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.approve_button.pressed.emit()
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	assert_bool(LoanApplicantNPC.APPROVED_LINES.has(speech(applicant))).is_true()
	review.close_button.pressed.emit()
	lo.close_button.pressed.emit()
	# Out the way out, through the entrance, and gone.
	await frames(10)
	assert_float(applicant.global_position.y).is_greater(LoanDeskSeat.SEATS[ScheduleManager.SLOT_LOAN_DESK_1].y)
	seat.finish_leaving()
	assert_vector(applicant.global_position).is_equal(LoanDeskSeat.ENTRANCE)
	assert_bool(seat.is_empty()).is_true()
	await frames(1)
	assert_bool(is_instance_valid(applicant)).is_false()
	# The next one comes in.
	room._process(0.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	assert_object(seat.application).is_same(LoanDeskManager.player_queue[0])

## A rejection and a counter-offer get their own reactions; the review
## screen seats an applicant still on the way at once.
func test_reactions_and_seating_at_once() -> void:
	clock_in_at_loan_desk()
	var seat := room.player_loan_seat()
	# Straight to the review: seated at once.
	lo.review_next_button.pressed.emit()
	assert_bool(seat.is_seated()).is_true()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.TOTAL_DTI].button_pressed = true
	review.submit_denial_button.pressed.emit()
	assert_bool(LoanApplicantNPC.REJECTED_LINES.has(speech(seat.applicant))).is_true()
	review.close_button.pressed.emit()
	# The next one, still leaving the last: the last goes, the next sits.
	lo.review_next_button.pressed.emit()
	assert_bool(seat.is_seated()).is_true()
	assert_object(seat.application).is_same(review.current_application())
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	review.counter_offer_amount_spinbox.value = 1000.0
	review.submit_counter_offer_button.pressed.emit()
	assert_bool(LoanApplicantNPC.COUNTER_LINES.has(speech(seat.applicant))).is_true()
	# Turned away as unverifiable: they'll bring the right papers.
	var unverified := with_problem("Noah Kim", LoanApplication.DocProblem.MISSING_STUB)
	assert_str(LoanApplicantNPC.reaction_line(_decided(unverified, LoanApplication.DecisionType.REJECT), 0)).is_equal(LoanApplicantNPC.UNVERIFIED_LINES[0])

func _decided(application: LoanApplication, decision: LoanApplication.DecisionType) -> LoanApplication:
	application.decision = decision
	return application

func test_clocking_in_sends_the_staff_desks_applicant_away() -> void:
	GameClock.minutes = 10 * 60.0
	var seat := room.player_loan_seat()
	room.loan_desk_worker._process(100.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	var staff_applicant := seat.application
	seat.applicant.finish_route()
	clock_in_at_loan_desk()
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	assert_str(speech(seat.applicant)).is_equal(LoanApplicantNPC.SENT_AWAY_LINE)
	# The player's own applicant replaces them when the review opens.
	lo.review_next_button.pressed.emit()
	assert_object(seat.application).is_not_same(staff_applicant)
	assert_object(seat.application).is_same(review.current_application())
	assert_bool(seat.is_seated()).is_true()

# --- staff desks ---------------------------------------------------------------------

## Loan Desk 2's staff take walk-ins while the branch is open: in, seated,
## decided after their decision time, out with a reaction, then the next.
func test_staff_desks_serve_walk_ins() -> void:
	GameClock.minutes = 10 * 60.0
	var worker := room.get_node("LoanDeskWorker2") as NpcLoanDeskWorker
	var seat := worker.seat
	assert_object(seat).is_same(room.loan_seats[ScheduleManager.SLOT_LOAN_DESK_2])
	var decided: Array[LoanApplication] = []
	worker.decision_made.connect(func(decided_application: LoanApplication, _s: StaffMember, _c: bool) -> void: decided.append(decided_application))
	worker._process(0.1)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	var application := seat.application
	seat.applicant.finish_route()
	assert_vector(seat.applicant.global_position).is_equal(LoanDeskSeat.SEATS[ScheduleManager.SLOT_LOAN_DESK_2])
	# Not before their decision time.
	worker._process(worker.staff_npc.staff.loan_decision_seconds() - 1.0)
	assert_array(decided).is_empty()
	worker._process(1.0)
	assert_array(decided).is_equal([application])
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	seat.finish_leaving()
	assert_bool(seat.is_empty()).is_true()
	# A short gap, then the next.
	worker._process(NpcLoanDeskWorker.ARRIVAL_GAP_RANGE[1] + 0.1)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	assert_object(seat.application).is_not_same(application)
	# After 5 PM nobody new comes in, but whoever is seated is still decided.
	seat.applicant.finish_route()
	GameClock.minutes = 17 * 60.0 + 5.0
	worker._process(100.0)
	assert_int(decided.size()).is_equal(2)
	seat.finish_leaving()
	worker._process(100.0)
	assert_bool(seat.is_empty()).is_true()

## Every desk has its own seat and its own row to walk along; applicants come
## in up one lane of the entrance corridor and leave down the other, and no
## route passes through another desk's seat. One applicant per seat at a time.
func test_seats_and_paths_never_overlap() -> void:
	var seats: Array[Vector2] = []
	var rows: Array[float] = []
	for seat: LoanDeskSeat in room.loan_seats.values():
		assert_bool(seats.has(seat.seat_position())).is_false()
		seats.append(seat.seat_position())
		var row: float = LoanDeskSeat.ROWS[seat.slot_name]
		assert_bool(rows.has(row)).is_false()
		rows.append(row)
		var into := seat.route_in()
		var out := seat.route_out()
		assert_float(into[0].x).is_equal(LoanDeskSeat.LANE_IN_X)
		assert_float(out[2].x).is_equal(LoanDeskSeat.LANE_OUT_X)
		assert_vector(into[-1]).is_equal(seat.seat_position())
		assert_vector(out[-1]).is_equal(LoanDeskSeat.ENTRANCE)
	assert_float(LoanDeskSeat.LANE_IN_X).is_not_equal(LoanDeskSeat.LANE_OUT_X)
	for seat: LoanDeskSeat in room.loan_seats.values():
		for route: Array[Vector2] in [seat.route_in(), seat.route_out()]:
			for i in route.size() - 1:
				for other: LoanDeskSeat in room.loan_seats.values():
					if other == seat:
						continue
					var closest := Geometry2D.get_closest_point_to_segment(other.seat_position(), route[i], route[i + 1])
					assert_float(closest.distance_to(other.seat_position())).override_failure_message("%s's route passes %s's seat" % [seat.slot_name, other.slot_name]).is_greater(20.0)
	# A second arrival waits for the seat.
	GameClock.minutes = 10 * 60.0
	var worker := room.get_node("LoanDeskWorker3") as NpcLoanDeskWorker
	worker._process(0.1)
	var first := worker.seat.application
	assert_bool(worker.seat.arrive(LoanDeskManager.next_staff_application())).is_false()
	assert_object(worker.seat.application).is_same(first)
	# Nobody else starts up the entrance corridor while they're in it...
	assert_bool(LoanDeskSeat.entrance_clear()).is_false()
	var other := room.get_node("LoanDeskWorker2") as NpcLoanDeskWorker
	other._process(10.0)
	assert_bool(other.seat.is_empty()).is_true()
	# ...only once they're past it.
	await frames(4)
	worker.seat.applicant.global_position.y = LoanDeskSeat.CORRIDOR_TOP_Y - 1.0
	assert_bool(LoanDeskSeat.entrance_clear()).is_true()
	other._process(10.0)
	assert_int(other.seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)

func test_going_home_clears_every_seat() -> void:
	GameClock.minutes = 10 * 60.0
	for worker in room.loan_desk_workers:
		worker._process(0.1)
		assert_bool(worker.seat.is_empty()).is_false()
		worker.seat.seat_now()
	room._on_go_home_confirmed()
	for seat: LoanDeskSeat in room.loan_seats.values():
		assert_bool(seat.is_empty()).is_true()

# --- documents through the review screen --------------------------------------------

func test_verify_documents_shows_them_beside_the_stated_income() -> void:
	clock_in_at_loan_desk()
	var application := with_problem("Angela Reyes", LoanApplication.DocProblem.OVERSTATED_INCOME)
	open_next(application)
	assert_str(review.annual_income_label.text).is_equal("Stated income: $48,000 a year ($4,000/mo)")
	assert_bool(review.documents_vbox.visible).is_false()
	review.verify_documents_button.pressed.emit()
	assert_bool(review.documents_verified).is_true()
	assert_bool(review.documents_vbox.visible).is_true()
	assert_str(review.worksheet_title_label.text).is_equal(LoanReviewScreen.DOCUMENTS_TITLE)
	var text := review.documents_text()
	assert_str(text).contains("Name: Angela Reyes")
	assert_str(text).contains("Gross pay this month: %s" % LoanApplication.dollars(application.stub_monthly_gross))
	assert_str(text).contains("Payroll deposits: ")
	assert_str(text).contains(LoanApplication.DOCUMENTS_POLICY_TEXT)
	# Never what's wrong, and no date of birth.
	for hidden: String in ["overstated", "doesn't match", "less than", "born", "Born"]:
		assert_str(text).not_contains(hidden)
	await assert_fits()
	# The worksheet and back.
	review.run_credit_check_button.pressed.emit()
	assert_bool(review.documents_vbox.visible).is_false()
	assert_str(review.run_credit_check_button.text).is_equal(LoanReviewScreen.SHOW_WORKSHEET_TEXT)
	assert_str(review.verify_documents_button.text).is_equal(LoanReviewScreen.SHOW_DOCUMENTS_TEXT)
	review.verify_documents_button.pressed.emit()
	assert_bool(review.documents_vbox.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_true()
	# The tallest the screen gets: documents, six reasons.
	review.reject_button.pressed.emit()
	assert_int(review.reason_checks.size()).is_equal(6)
	await assert_fits()

	# A missing document and no ID read as such.
	var missing := with_problem("Maria Chen", LoanApplication.DocProblem.MISSING_STATEMENT)
	# And no ID either (rare together, so set by hand).
	missing.id_problem = IdCard.Problem.NO_ID
	missing.id_presented = false
	review.cancel_denial_button.pressed.emit()
	review.close_button.pressed.emit()
	open_next(missing)
	review.verify_documents_button.pressed.emit()
	assert_str(review.documents_text()).contains("Photo ID: none provided.")
	assert_str(review.documents_text()).contains("Bank statement: none provided.")
	assert_bool(review.id_portrait.visible).is_false()
	await assert_fits()

## Caught: rejected naming the new reason, +12 and a "Good catch".
func test_a_problem_caught_through_the_screen() -> void:
	clock_in_at_loan_desk()
	open_next(with_problem("Angela Reyes", LoanApplication.DocProblem.STUB_NAME))
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.BEST_DECISION_SCORE + LoanApplication.REASON_RIGHT_SCORE
	assert_vector(totals() - start).is_equal(Vector3i(score, LoanApplication.BEST_DECISION_REPUTATION, score * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).contains("Good catch: the pay stub was in someone else's name.")
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_bool(record.documents_problem).is_true()
	assert_str(record.description).contains("Income or identity could not be verified")
	await assert_fits()

## Approved on documents that don't check out: WORST, with the problem named.
func test_approving_on_unverified_documents_is_serious() -> void:
	clock_in_at_loan_desk()
	open_next(with_problem("Maria Chen", LoanApplication.DocProblem.NONE, IdCard.Problem.EXPIRED))
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	var start := totals()
	review.approve_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.WORST_DECISION_SCORE)
	assert_str(review.decision_status_label.text).contains(LoanApplication.UNVERIFIED_LOAN_DESCRIPTION)
	assert_str(review.decision_status_label.text).not_contains("high-risk")
	assert_str(review.decision_status_label.text).contains("Serious: the income or identity was never verified (the ID had expired).")
	# The Branch Manager's Approvals re-grade it the same way.
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_int(LoanApplication.grade(record.original_decision_type, record.risk_assessment, record.nothing_affordable, not record.documents_problem)).is_equal(LoanApplication.Grade.WORST)
	assert_int(LoanApplication.grade(LoanApplication.DecisionType.REJECT, record.risk_assessment, record.nothing_affordable, not record.documents_problem)).is_equal(LoanApplication.Grade.BEST)
	await assert_fits()

## Deciding without verifying: -3 even when the documents were fine; and
## turning away a good applicant as unverifiable is penalized.
func test_skipping_verification_and_a_false_refusal() -> void:
	clock_in_at_loan_desk()
	open_next(sample("Maria Chen"))
	review.run_credit_check_button.pressed.emit()
	var start := totals()
	review.approve_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.BEST_DECISION_SCORE + LoanApplication.VERIFY_SKIPPED_SCORE)
	assert_str(review.decision_status_label.text).contains("Documents not verified before deciding (-3 Score).")
	review.close_button.pressed.emit()

	open_next(sample("Elena Petrova"))
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	review.reason_checks[LoanApplication.DenialReason.UNVERIFIED].button_pressed = true
	start = totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.BAD_DECISION_SCORE + LoanApplication.REASON_WRONG_SCORE + LoanApplication.FALSE_UNVERIFIED_SCORE
	var reputation := LoanApplication.BAD_DECISION_REPUTATION + LoanApplication.FALSE_UNVERIFIED_REPUTATION
	# (XP is floored at 0, so only Score and Reputation.)
	var change := totals() - start
	assert_vector(Vector2i(change.x, change.y)).is_equal(Vector2i(score, reputation))
	assert_str(review.decision_status_label.text).contains("The documents checked out: turning them away as unverifiable")
	await assert_fits()

# --- staff document checks ------------------------------------------------------------

## A skilled staff officer catches document problems (rejecting, correct,
## never queued); an unskilled one misses most, and every miss goes to staff
## review, saying what was missed only once decided: Serious when they
## approved or counter-offered on the documents, Minor when they rejected the
## loan anyway (no money put at risk).
func test_staff_misses_go_to_review() -> void:
	XPManager._grant_branch_manager()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	var worker := room.get_node("LoanDeskWorker2") as NpcLoanDeskWorker
	var staff := worker.staff_npc.staff
	var outcomes: Array[bool] = []
	worker.decision_made.connect(func(_a: LoanApplication, _s: StaffMember, correct: bool) -> void: outcomes.append(correct))
	var problems := 120

	staff.skill = 10
	for i in problems:
		var application := problem_applicant(i)
		worker.decide_next(application)
	var caught := outcomes.count(true)
	assert_int(caught).is_greater(int(problems * (1.0 - staff.doc_miss_chance()) - 8))
	var queued := StaffReviewManager.queue.size()
	assert_int(queued).is_equal(problems - caught)

	staff.skill = 1
	outcomes.clear()
	var queue_before := StaffReviewManager.queue.size()
	for i in problems:
		worker.decide_next(problem_applicant(1000 + i))
	var missed := outcomes.count(false)
	# About 60% missed at skill 1.
	assert_float(missed / float(problems)).is_between(0.45, 0.75)
	var items: Array[StaffReviewItem] = []
	items.assign(StaffReviewManager.queue.slice(queue_before))
	assert_int(items.size()).is_equal(missed)
	var severities := {}
	for item in items:
		assert_bool(item.docs_missed).is_true()
		var lent := item.decision != LoanApplication.DecisionType.REJECT
		assert_int(item.severity).override_failure_message(LoanApplication.decision_type_label(item.decision)).is_equal(StaffReviewItem.Severity.SERIOUS if lent else StaffReviewItem.Severity.MINOR)
		severities[item.severity] = true
		assert_str(item.documents_text).contains("Pay stub")
		var details := StaffReviewScreen.details_text(item)
		assert_str(details).contains(item.documents_text)
		assert_str(details).not_contains(item.docs_problem_text)
	# Both kinds came up.
	assert_int(severities.size()).is_equal(2)
	assert_str(StaffReviewScreen._result_text(items[0], {"score": 3, "xp": 30, "reputation": 0, "severity": StaffReviewItem.Severity.SERIOUS, "explanation": "Fair report."})).contains("Missed in the documents: %s." % items[0].docs_problem_text)

	# The staff review screen with a documents item still fits.
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	bm.staff_review_screen.show_screen()
	bm.staff_review_screen._index = StaffReviewManager.queue.find(items[0])
	bm.staff_review_screen._refresh()
	await frames(4)
	var layout := layout_problems(bm.staff_review_screen.get_node("Panel") as Control)
	assert_array(layout).override_failure_message("\n".join(layout)).is_empty()

## A clean, safe applicant whose documents have a problem (each named
## differently, so each staff check is its own roll).
func problem_applicant(number: int) -> LoanApplication:
	var kinds := [LoanApplication.DocProblem.OVERSTATED_INCOME, LoanApplication.DocProblem.STUB_NAME, LoanApplication.DocProblem.MISSING_STUB, LoanApplication.DocProblem.MISSING_STATEMENT]
	var kind: LoanApplication.DocProblem = kinds[number % kinds.size()]
	return with_problem("Maria Chen", kind, IdCard.Problem.NONE, "Applicant %d" % number)
