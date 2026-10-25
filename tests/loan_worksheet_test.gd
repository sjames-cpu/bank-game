extends "res://tests/support/teller_room_suite.gd"

## The Loan Officer's underwriting worksheet in the room: the screen before
## and after the credit check (and never naming the hidden verdict), a
## denial with stated reasons and a counter-offer graded through the
## screen, every state fitting the 648 px window, staff loan officers still
## deciding (graded against the new assessment, their review items carrying
## the worksheet), and old saves' loan review items still loading.

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

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

## Clocks in at Loan Desk 1 and opens the application named `applicant_name`.
func open_application(applicant_name: String) -> LoanApplication:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	for i in review.applications.size():
		if review.applications[i].applicant_name == applicant_name:
			review._next_application_index = i
	lo.review_next_button.pressed.emit()
	assert_bool(review.visible).is_true()
	assert_str(review.current_application().applicant_name).is_equal(applicant_name)
	return review.current_application()

func assert_fits() -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

func tick(reasons: Array) -> void:
	for reason: int in reasons:
		review.reason_checks[reason].button_pressed = true

# --- the worksheet ------------------------------------------------------------------

func test_the_worksheet_appears_after_the_credit_check() -> void:
	open_application("Angela Reyes")
	# Before: the application only, no worksheet, no decisions.
	assert_str(review.requested_amount_label.text).is_equal("Requested: $30,000 auto loan")
	assert_str(review.terms_label.text).is_equal("60 months at 7.00% (bank rate for auto loans) · policy maximum $75,000")
	assert_str(review.housing_payment_label.text).is_equal("Housing (rent or mortgage): $950/mo")
	assert_str(review.existing_debt_label.text).is_equal("Existing debt: $10,000 balance · $250/mo")
	assert_str(review.employment_label.text).is_equal("Employment: 3 years")
	assert_str(review.worksheet_text()).is_empty()
	assert_bool(review.worksheet_placeholder_label.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_false()
	await assert_fits()

	review.run_credit_check_button.pressed.emit()
	assert_bool(review.worksheet_placeholder_label.visible).is_false()
	assert_bool(review.decision_hbox.visible).is_true()
	assert_str(review.credit_score_label.text).is_equal("Credit score: 710 — Good")
	var text := review.worksheet_text()
	for line: String in [
		"Monthly income: $4,000",
		"Housing payment: $950",
		"Existing debt payments: $250",
		"New loan payment: $594 (60 months at 7.00%)",
		"Front-end DTI: 23.8%",
		"Housing ÷ income: the share of pay that goes on housing.",
		"Total DTI: 44.9%",
		"Housing + debts + new payment ÷ income. Policy guide: about 36% healthy, 43% stretched, 50% high.",
		"Credit score: 710 — Good",
		"Employment: 3 years",
		"Affordable at 36% total DTI: $12,100",
	]:
		assert_str(text).contains(line)
	# The hidden verdict is never shown.
	for hidden: String in ["low risk", "medium risk", "high risk", "Low", "Medium", "High risk", "Approve", "Reject"]:
		assert_str(text).not_contains(hidden)
	await assert_fits()

func test_a_home_loans_mortgage_replaces_the_rent_on_the_worksheet() -> void:
	open_application("Elena Petrova")
	review.run_credit_check_button.pressed.emit()
	var text := review.worksheet_text()
	assert_str(text).contains("Housing payment: $1,959 (new mortgage; replaces $1,500)")
	assert_str(text).contains("New loan payment: $1,959 (360 months at 6.50%)")
	assert_str(text).contains("Total DTI: 36.6%")
	await assert_fits()

## Every applicant's worksheet, with the screen at its tallest (the denial
## reasons open), and after a decision, fits the window.
func test_every_applicants_worksheet_fits() -> void:
	open_application("Maria Chen")
	for i in review.applications.size():
		var application := review.current_application()
		review.run_credit_check_button.pressed.emit()
		assert_bool(review.run_credit_check_button.visible).is_false()
		review.reject_button.pressed.emit()
		await frames(4)
		var problems := layout_problems(review.main_panel)
		assert_array(problems).override_failure_message("%s:\n%s" % [application.applicant_name, "\n".join(problems)]).is_empty()
		tick([LoanApplication.DenialReason.TOTAL_DTI, LoanApplication.DenialReason.INCOME])
		review.submit_denial_button.pressed.emit()
		await frames(4)
		problems = layout_problems(review.main_panel)
		assert_array(problems).override_failure_message("%s decided:\n%s" % [application.applicant_name, "\n".join(problems)]).is_empty()
		review.close_button.pressed.emit()
		lo.applications_reviewed = 0
		lo.review_next_button.pressed.emit()

# --- decisions through the screen -------------------------------------------------------

func test_a_denial_needs_one_or_two_reasons_graded_against_the_weak_points() -> void:
	open_application("Marcus Webb")
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	assert_bool(review.reasons_vbox.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_false()
	assert_int(review.reason_checks.size()).is_equal(5)
	assert_bool(review.submit_denial_button.disabled).is_true()
	await assert_fits()
	# A third reason is unticked again.
	tick([LoanApplication.DenialReason.TOTAL_DTI, LoanApplication.DenialReason.CREDIT_SCORE, LoanApplication.DenialReason.EMPLOYMENT])
	assert_array(review.selected_reasons()).is_equal([LoanApplication.DenialReason.TOTAL_DTI, LoanApplication.DenialReason.CREDIT_SCORE])
	assert_bool(review.submit_denial_button.disabled).is_false()

	var start := totals()
	review.submit_denial_button.pressed.emit()
	# A correct denial (+10, +1 Reputation) with both real reasons (+2 each).
	var score := LoanApplication.BEST_DECISION_SCORE + 2 * LoanApplication.REASON_RIGHT_SCORE
	assert_vector(totals() - start).is_equal(Vector3i(score, LoanApplication.BEST_DECISION_REPUTATION, score * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).is_equal("Decision recorded: Rejected\nCorrect call (+14 Score, +1 Reputation, +140 XP)\nStated reasons: 2 right (+4 Score).")
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).is_equal("Loan rejected: Marcus Webb (high risk applicant) — reasons: Total DTI too high, Credit score too low")
	assert_int(lo.applications_reviewed).is_equal(1)
	assert_int(lo.shift_score_total).is_equal(score)
	await assert_fits()

func test_wrong_reasons_cost_points_even_on_a_correct_denial() -> void:
	open_application("Sophie Laurent")
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.EMPLOYMENT])
	var start := totals()
	review.submit_denial_button.pressed.emit()
	# +10 for the call, -2 for the wrong reason, -1 for the credit score left out.
	assert_int((totals() - start).x).is_equal(7)
	assert_str(review.decision_status_label.text).ends_with("Stated reasons: 0 right, 1 wrong, 1 missed (-3 Score).")

func test_cancelling_a_denial_goes_back_to_the_decisions() -> void:
	open_application("Maria Chen")
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.AMOUNT])
	review.cancel_denial_button.pressed.emit()
	assert_bool(review.reasons_vbox.visible).is_false()
	assert_bool(review.decision_hbox.visible).is_true()
	# Ticks are cleared next time.
	review.reject_button.pressed.emit()
	assert_array(review.selected_reasons()).is_empty()

func test_a_counter_offer_shows_the_affordable_amount_and_is_graded_on_it() -> void:
	open_application("Angela Reyes")
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	assert_bool(review.counter_offer_vbox.visible).is_true()
	assert_str(review.counter_offer_reference_label.text).is_equal("Affordable at 36% total DTI: $12,100")
	await assert_fits()
	review.counter_offer_amount_spinbox.value = 12000.0
	var start := totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_vector(totals() - start).is_equal(Vector3i(LoanApplication.BEST_DECISION_SCORE, LoanApplication.BEST_DECISION_REPUTATION, LoanApplication.BEST_DECISION_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(review.decision_status_label.text).is_equal("Decision recorded: Counter-offered at $12,000\nCorrect call (+10 Score, +1 Reputation, +100 XP)\nAffordable at a healthy total DTI.")
	await assert_fits()

	# The next borderline applicant, countered for more than they can carry.
	review.close_button.pressed.emit()
	lo.review_next_button.pressed.emit()
	var jamal := review.current_application()
	assert_str(jamal.applicant_name).is_equal("Jamal Green")
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	review.counter_offer_amount_spinbox.value = jamal.affordable_amount() + 5000.0
	start = totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE)
	assert_str(review.decision_status_label.text).ends_with("More than they can carry at a healthy total DTI.")

# --- staff loan officers ----------------------------------------------------------------

func test_staff_still_decide_every_application_against_the_new_assessment() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var worker := room.loan_desk_worker
	var staff := worker.staff_npc.staff
	var results: Array[bool] = []
	worker.decision_made.connect(func(_a: LoanApplication, _s: StaffMember, correct: bool) -> void: results.append(correct))
	# A perfect officer makes the right call on every sample, countering
	# borderline applicants at what they can afford (below the request).
	staff.skill = 10
	var counters := {}
	worker.decision_made.connect(func(application: LoanApplication, _s: StaffMember, _c: bool) -> void:
		if application.decision == LoanApplication.DecisionType.COUNTER_OFFER:
			counters[application.applicant_name] = application.decision_amount)
	for i in LoanApplicationsData.get_applications().size():
		worker.decide_next()
	assert_array(results).not_contains([false])
	assert_int(results.size()).is_equal(10)
	assert_dict(counters).is_equal({"Priya Sharma": 4500.0, "Angela Reyes": 12100.0, "Jamal Green": 44200.0, "Noah Kim": 9900.0})
	assert_int(StaffReviewManager.queue.size()).is_equal(0)

	# The weakest officer gets every call wrong, and each lands in the review
	# queue carrying the worksheet.
	staff.skill = 0
	results.clear()
	for i in LoanApplicationsData.get_applications().size():
		worker.decide_next()
	assert_array(results).not_contains([true])
	assert_int(StaffReviewManager.queue.size()).is_equal(10)
	var angela: StaffReviewItem = StaffReviewManager.queue.filter(func(item: StaffReviewItem) -> bool: return item.applicant_name == "Angela Reyes")[0]
	assert_bool(angela.has_worksheet).is_true()
	assert_float(angela.total_dti).is_equal_approx(0.4485, 0.0001)
	assert_float(angela.affordable_amount).is_equal(12100.0)
	var details := StaffReviewScreen.details_text(angela)
	assert_str(details).starts_with("Applicant: Angela Reyes — $30,000 auto loan (60 months at 7.00%)\nCredit score 710 (Good) · Employed 3 years\nIncome $4,000/mo · Housing $950 · Debts $250/mo · New payment $594/mo\nFront-end DTI 23.8% · Total DTI 44.9% · Affordable at 36%: $12,100\nDecision: ")
	assert_str(details).not_contains("Loan-to-income")
	var elena: StaffReviewItem = StaffReviewManager.queue.filter(func(item: StaffReviewItem) -> bool: return item.applicant_name == "Elena Petrova")[0]
	assert_str(StaffReviewScreen.details_text(elena)).contains("Mortgage $1,959 (replaces $1,500)")

	# The review screen with a worksheet item still fits.
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()
	bm.staff_review_screen.show_screen()
	await frames(4)
	var problems := layout_problems(bm.staff_review_screen.get_node("Panel") as Control)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- old saves ------------------------------------------------------------------------

## A loan review item saved before the worksheet (with the old DTI and
## loan-to-income) loads, and is shown without a worksheet.
func test_an_old_saves_loan_review_item_still_loads() -> void:
	SaveGame.restore({
		"staff_review": {"queue": [{
			"kind": StaffReviewItem.Kind.LOAN, "severity": StaffReviewItem.Severity.ACCEPTABLE,
			"staff_name": "Sana Malik", "staff_slot": "Loan Desk", "timestamp": "Day 2, 9:31 AM",
			"applicant_name": "Avery Stone", "requested_amount": 25000.0, "loan_purpose": "Auto",
			"credit_score": 702, "annual_income": 61234.25, "monthly_debt_payments": 812.4,
			"debt_to_income": 0.1592, "loan_to_income": 0.408,
			"decision": LoanApplication.DecisionType.COUNTER_OFFER, "decision_amount": 15000.0,
			"grade": LoanApplication.Grade.PARTIAL,
		}]},
	})
	assert_int(StaffReviewManager.queue.size()).is_equal(1)
	var item := StaffReviewManager.queue[0]
	assert_bool(item.has_worksheet).is_false()
	assert_float(item.annual_income).is_equal(61234.25)
	assert_str(StaffReviewScreen.details_text(item)).is_equal("Applicant: Avery Stone — $25,000 auto loan\nCredit score 702 · Income $61,234/yr · Debt payments $812/mo\n(No worksheet: decided before it was introduced.)\nDecision: Counter-Offer ($15,000)")
	# Saved again, it's the current shape (no old ratios).
	var saved_queue: Array = StaffReviewManager.save_data()["queue"]
	var saved: Dictionary = saved_queue[0]
	assert_bool(saved.has("debt_to_income")).is_false()
	assert_bool(saved.has("total_dti")).is_true()
