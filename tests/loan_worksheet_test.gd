extends "res://tests/support/loan/loan_suite.gd"

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

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			return application
	return null

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

## Puts `application` on top of the player's pile and opens it, verifying
## its documents first unless `check_documents` is false.
func open_next(application: LoanApplication, check_documents: bool = true) -> LoanApplication:
	LoanDeskManager.player_queue.push_front(application)
	lo.review_next_button.pressed.emit()
	assert_bool(review.visible).is_true()
	assert_object(review.current_application()).is_same(application)
	if check_documents:
		review.verify_documents_button.pressed.emit()
	return application

## Clocks in at Loan Desk 1 and opens the sample named `applicant_name`.
func open_application(applicant_name: String, check_documents: bool = true) -> LoanApplication:
	clock_in_at_loan_desk()
	return open_next(sample(applicant_name), check_documents)

func assert_fits() -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

func tick(reasons: Array) -> void:
	for reason: int in reasons:
		review.reason_checks[reason].button_pressed = true

# --- the worksheet ------------------------------------------------------------------

func test_the_worksheet_appears_after_the_credit_check() -> void:
	open_application("Angela Reyes", false)
	# Before: the application only, no worksheet, no decisions.
	assert_str(review.requested_amount_label.text).is_equal("Requested: $30,000 auto loan")
	assert_str(review.terms_label.text).is_equal("60 months at 7.00% · up to $75,000")
	assert_str(review.housing_payment_label.text).is_equal("Housing (rent or mortgage): $950/mo")
	assert_str(review.existing_debt_label.text).is_equal("Existing debt: $10,000 balance · $250/mo")
	assert_str(review.employment_label.text).is_equal("Employment: 3 years")
	assert_str(review.worksheet_text()).is_empty()
	assert_bool(review.worksheet_placeholder_label.visible).is_true()
	assert_str(review.credit_report_text()).is_empty()
	assert_bool(review.credit_report_placeholder_label.visible).is_true()
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
		"Rate offered: 7.00%",
		"Priced for Good credit (670-739); auto rates run 5.50% to 14.50%, lower credit paying more.",
		"New loan payment: $594 (60 months)",
		"Front-end DTI: 23.8%",
		"Housing ÷ income: the share of pay that goes on housing.",
		"Total DTI: 44.9%",
		"Housing + debts + new payment ÷ income. Policy guide: about 36% healthy, 43% stretched, 50% high.",
		"Employment: 3 years",
		"Affordable at 36% total DTI: $12,100",
	]:
		assert_str(text).contains(line)
	# The credit report beside it, each item with what it means, and the policy.
	assert_bool(review.credit_report_placeholder_label.visible).is_false()
	var report := review.credit_report_text()
	for line: String in [
		"Credit score: 710 — Good",
		"On-time payments: 97%",
		"Share of all payments made on time.",
		"Late payments (2 yrs): 1 × 30-day",
		"30, 60 or 90+ days overdue.",
		"Credit utilization: 41%",
		"Card balances ÷ limits; 30% or less is healthy.",
		"Open accounts: 6",
		"Hard inquiries (6 mo): 2",
		"Serious marks: None",
		"Collections and bankruptcies stay 7 years.",
		CreditReport.POLICY_TEXT,
	]:
		assert_str(report).contains(line)
	# The hidden verdict is never shown.
	for shown: String in [text, report]:
		for hidden: String in ["low risk", "medium risk", "high risk", "Low", "Medium", "High risk", "Approve", "Reject", "points"]:
			assert_str(shown).not_contains(hidden)
	await assert_fits()

func test_a_home_loans_mortgage_replaces_the_rent_on_the_worksheet() -> void:
	open_application("Elena Petrova")
	review.run_credit_check_button.pressed.emit()
	var text := review.worksheet_text()
	assert_str(text).contains("Housing payment: $1,959 (new mortgage; replaces $1,500)")
	assert_str(text).contains("Rate offered: 6.50%")
	assert_str(text).contains("New loan payment: $1,959 (360 months)")
	assert_str(text).contains("Total DTI: 36.6%")
	await assert_fits()

## Every sample's worksheet and a run of generated ones, with the screen at
## its tallest (the denial reasons open), and after a decision, fits the
## window.
func test_every_applicants_worksheet_fits() -> void:
	clock_in_at_loan_desk()
	var cases := LoanApplicationsData.get_applications()
	for i in 20:
		cases.append(LoanDeskManager.generate_application())
	for application in cases:
		open_next(application)
		review.run_credit_check_button.pressed.emit()
		assert_str(review.run_credit_check_button.text).is_equal(LoanReviewScreen.SHOW_WORKSHEET_TEXT)
		review.reject_button.pressed.emit()
		await frames(4)
		var problems := layout_problems(review.main_panel)
		problems.append_array(controls_line_problems(review.main_panel))
		assert_array(problems).override_failure_message("%s:\n%s" % [application.applicant_name, "\n".join(problems)]).is_empty()
		tick([LoanApplication.DenialReason.TOTAL_DTI, LoanApplication.DenialReason.INCOME])
		review.submit_denial_button.pressed.emit()
		await frames(4)
		problems = layout_problems(review.main_panel)
		problems.append_array(controls_line_problems(review.main_panel))
		assert_array(problems).override_failure_message("%s decided:\n%s" % [application.applicant_name, "\n".join(problems)]).is_empty()
		review.close_button.pressed.emit()
		lo.applications_reviewed = 0

# --- decisions through the screen -------------------------------------------------------

func test_a_denial_needs_one_or_two_reasons_graded_against_the_weak_points() -> void:
	open_application("Marcus Webb")
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	assert_bool(review.reasons_vbox.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_false()
	assert_int(review.reason_checks.size()).is_equal(8)
	# Listed with the credit reasons together.
	var listed: Array[String] = []
	for child in review.reason_checks_vbox.get_children():
		listed.append((child as CheckBox).text)
	assert_array(listed).is_equal(["Total DTI too high", "Credit score too low", "Recent late payments or collections", "Income too low for the amount", "Down payment too small for the value", "Employment too short", "Amount too large", "Income or identity could not be verified"])
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

	# Another borderline applicant, countered for more than they can carry.
	review.close_button.pressed.emit()
	var jamal := open_next(sample("Jamal Green"))
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	review.counter_offer_amount_spinbox.value = jamal.affordable_amount() + 5000.0
	start = totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE)
	assert_str(review.decision_status_label.text).ends_with("More than they can carry at a healthy total DTI.")

## A borderline applicant stretched by their debts, with nothing affordable
## to offer: Reject (for total DTI) is the correct call through the screen,
## a counter-offer only reasonable; the history record carries it for the
## Branch Manager's Approvals, and a skilled staff officer rejects too.
func stretched_by_debts() -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = "Dana Hollis"
	application.loan_purpose = "Personal"
	application.requested_amount = 5000.0
	application.credit_score = 650
	application.annual_income = 60000.0
	application.monthly_housing_payment = 1300.0
	application.existing_debt = 20000.0
	application.monthly_debt_payments = 600.0
	application.employment_months = 60
	application.risk_tier = LoanApplication.RiskTier.MEDIUM
	# Documents that check out (nothing rolled for them).
	application.documents_issued = true
	return application

func test_a_borderline_applicant_with_nothing_affordable_is_rejected_for_total_dti() -> void:
	clock_in_at_loan_desk()
	open_next(stretched_by_debts())
	review.run_credit_check_button.pressed.emit()
	assert_str(review.worksheet_text()).contains("Affordable at 36% total DTI: $0")
	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.TOTAL_DTI, LoanApplication.DenialReason.CREDIT_SCORE])
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.BEST_DECISION_SCORE + 2 * LoanApplication.REASON_RIGHT_SCORE
	assert_int((totals() - start).x).is_equal(score)
	assert_str(review.decision_status_label.text).contains("Correct call")
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_bool(record.nothing_affordable).is_true()
	assert_int(LoanApplication.grade(LoanApplication.DecisionType.COUNTER_OFFER, record.risk_assessment, record.nothing_affordable)).is_equal(LoanApplication.Grade.PARTIAL)
	review.close_button.pressed.emit()

	# Countered instead: only reasonable, whatever the amount.
	open_next(stretched_by_debts())
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	review.counter_offer_amount_spinbox.value = 2000.0
	start = totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE)
	review.close_button.pressed.emit()

	# A skilled staff officer rejects them, and that's correct.
	var worker := room.get_node("LoanDeskWorker2") as NpcLoanDeskWorker
	worker.staff_npc.staff.skill = 10
	var decided: Array[LoanApplication] = []
	var correct: Array[bool] = []
	worker.decision_made.connect(func(application: LoanApplication, _s: StaffMember, right: bool) -> void:
		decided.append(application)
		correct.append(right))
	worker.decide_next(stretched_by_debts())
	assert_int(decided[0].decision).is_equal(LoanApplication.DecisionType.REJECT)
	assert_array(correct).is_equal([true])

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
	for application in LoanApplicationsData.get_applications():
		worker.decide_next(application)
	assert_array(results).not_contains([false])
	assert_int(results.size()).is_equal(10)
	assert_dict(counters).is_equal({"Priya Sharma": 4000.0, "Angela Reyes": 12100.0, "Jamal Green": 41000.0, "Noah Kim": 9900.0})
	assert_int(StaffReviewManager.queue.size()).is_equal(0)

	# The weakest officer gets every call wrong, and each lands in the review
	# queue carrying the worksheet.
	staff.skill = 0
	results.clear()
	for application in LoanApplicationsData.get_applications():
		worker.decide_next(application)
	assert_array(results).not_contains([true])
	assert_int(StaffReviewManager.queue.size()).is_equal(10)
	var angela: StaffReviewItem = StaffReviewManager.queue.filter(func(item: StaffReviewItem) -> bool: return item.applicant_name == "Angela Reyes")[0]
	assert_bool(angela.has_worksheet).is_true()
	assert_float(angela.total_dti).is_equal_approx(0.4485, 0.0001)
	assert_float(angela.affordable_amount).is_equal(12100.0)
	var details := StaffReviewScreen.details_text(angela)
	assert_str(details).starts_with("Applicant: Angela Reyes — $30,000 auto loan (60 months at 7.00%)\nCredit score 710 (Good) · Employed 3 years\nCredit report: on time 97% · late (2 yrs) 1 × 30-day · utilization 41% · 6 accounts · 2 inquiries · marks: None\nStated income $4,000/mo · Housing $950 · Debts $250/mo · New payment $594/mo\nFront-end DTI 23.8% · Total DTI 44.9% · Affordable at 36%: $12,100\nCollateral: vehicle $34,000 · down $4,000 (11.8%) · LTV 88.2%\nDecision: ")
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

# --- the credit report ------------------------------------------------------------------

## A good score hiding a recent collection: a borderline applicant the score
## alone would call safe. Its report shows the collection, and "Recent late
## payments or collections" is the reason to give.
func hidden_collection() -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = "Kira Ibarra"
	application.loan_purpose = "Auto"
	application.requested_amount = 20000.0
	application.credit_score = 705
	application.annual_income = 90000.0
	application.monthly_housing_payment = 1800.0
	application.existing_debt = 9000.0
	application.monthly_debt_payments = 250.0
	application.employment_months = 70
	application.risk_tier = LoanApplication.RiskTier.MEDIUM
	application.documents_issued = true
	application.credit_report_issued = true
	application.on_time_percent = 96
	application.late_30_days = 1
	application.utilization_percent = 38
	application.open_accounts = 6
	application.hard_inquiries = 1
	application.collections = 1
	application.months_since_collection = 9
	return application

func test_a_recent_collection_on_the_report_through_the_screen() -> void:
	clock_in_at_loan_desk()
	var application := open_next(hidden_collection())
	assert_int(application.score_only_assessment()).is_equal(LoanApplication.RiskTier.LOW)
	assert_int(application.calculate_risk_assessment()).is_equal(LoanApplication.RiskTier.MEDIUM)
	review.run_credit_check_button.pressed.emit()
	assert_str(review.credit_report_text()).contains("Serious marks: 1 collection, latest 9 months ago")
	await assert_fits()
	# Rejected for the history: reasonable for a borderline applicant, with the
	# one real reason named.
	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.CREDIT_HISTORY])
	await assert_fits()
	var start := totals()
	review.submit_denial_button.pressed.emit()
	var score := LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_RIGHT_SCORE
	assert_int((totals() - start).x).is_equal(score)
	assert_str(review.decision_status_label.text).contains("Stated reasons: 1 right (+2 Score).")
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).is_equal("Loan rejected: Kira Ibarra (medium risk applicant) — reasons: Recent late payments or collections")
	review.close_button.pressed.emit()

	# Naming the score instead is wrong, and the history is missed.
	var again := hidden_collection()
	again.applicant_name = "Hugo Valdez"
	open_next(again)
	review.run_credit_check_button.pressed.emit()
	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.CREDIT_SCORE])
	start = totals()
	review.submit_denial_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_WRONG_SCORE + LoanApplication.REASON_MISSING_SCORE)

## An application with no report (saved before reports) gets one when it
## comes up, in line with its score and adding nothing to its call.
func test_an_application_without_a_report_gets_one() -> void:
	clock_in_at_loan_desk()
	var application := open_next(stretched_by_debts())
	assert_bool(application.credit_report_issued).is_true()
	assert_int(application.credit_report_points()).is_equal(0)
	review.run_credit_check_button.pressed.emit()
	assert_str(review.credit_report_text()).contains("On-time payments: ")

## Staff loan officers judge the same report and pricing: a perfect officer
## counters the applicant the report makes borderline (at what they can
## afford at their credit band's rate), and the weakest officer's call on
## them is a review item carrying the report.
func test_staff_officers_use_the_report_and_pricing() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var worker := room.loan_desk_worker
	worker.staff_doc_slips = false
	var staff := worker.staff_npc.staff
	var decided: Array[LoanApplication] = []
	var correct: Array[bool] = []
	worker.decision_made.connect(func(application: LoanApplication, _s: StaffMember, right: bool) -> void:
		decided.append(application)
		correct.append(right))
	staff.skill = 10
	worker.decide_next(hidden_collection())
	assert_int(decided[0].risk_assessment).is_equal(LoanApplication.RiskTier.MEDIUM)
	assert_int(decided[0].decision).is_equal(LoanApplication.DecisionType.COUNTER_OFFER)
	# They could carry the whole $20,000: the offer is just below it.
	assert_float(decided[0].affordable_amount()).is_greater(20000.0)
	assert_float(decided[0].decision_amount).is_equal(19900.0)
	assert_float(decided[0].annual_rate()).is_equal_approx(0.07, 0.000001)
	assert_array(correct).is_equal([true])

	# The weakest officer gets it wrong: a review item with the report frozen
	# on it, and the rate offered.
	staff.skill = 0
	worker.decide_next(hidden_collection())
	assert_array(correct).is_equal([true, false])
	assert_int(decided[1].decision).is_not_equal(LoanApplication.DecisionType.COUNTER_OFFER)
	var item: StaffReviewItem = StaffReviewManager.queue[-1]
	assert_str(item.credit_report_text).is_equal("Credit report: on time 96% · late (2 yrs) 1 × 30-day · utilization 38% · 6 accounts · 1 inquiry · marks: 1 collection, latest 9 months ago")
	assert_float(item.annual_rate).is_equal_approx(0.07, 0.000001)
	assert_str(StaffReviewScreen.details_text(item)).contains(item.credit_report_text)
	# Saved and loaded with the queue.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(StaffReviewManager.save_data()))
	StaffReviewManager.reset()
	StaffReviewManager.load_data(saved)
	assert_str(StaffReviewManager.queue[-1].credit_report_text).is_equal(item.credit_report_text)

# --- collateral ------------------------------------------------------------------------

## A home bought with 3% down on an appraisal under the price: a buyer with
## very good credit and a healthy DTI made borderline by the LTV.
func little_down() -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = "Nora Kimura"
	application.loan_purpose = "Home"
	application.requested_amount = 340000.0
	application.credit_score = 765
	application.annual_income = 160000.0
	application.monthly_housing_payment = 2100.0
	application.existing_debt = 6000.0
	application.monthly_debt_payments = 180.0
	application.employment_months = 84
	application.risk_tier = LoanApplication.RiskTier.MEDIUM
	application.documents_issued = true
	application.collateral_issued = true
	application.collateral_kind = LoanApplication.Collateral.HOUSE
	application.purchase_price = 380000.0
	application.collateral_value = 355000.0
	return application

## The worksheet's two tabs: Payments (with the mortgage insurance in the
## payment) and Collateral (price, appraisal, down payment, LTV, insurance),
## each fitting the window at the usual text size.
func test_the_worksheet_has_payments_and_collateral_tabs() -> void:
	clock_in_at_loan_desk()
	var application := open_next(little_down())
	assert_str(review.collateral_label.text).is_equal("Purchase price: $380,000")
	assert_bool(review.worksheet_tabs.visible).is_false()
	review.run_credit_check_button.pressed.emit()
	assert_bool(review.worksheet_tabs.visible).is_true()
	assert_bool(review.worksheet_title_label.visible).is_false()
	assert_int(review.worksheet_tabs.current_tab).is_equal(LoanReviewScreen.WorksheetTab.PAYMENTS)
	assert_bool(review.worksheet_rows_vbox.visible).is_true()
	assert_bool(review.collateral_rows_vbox.visible).is_false()
	var insurance := application.mortgage_insurance()
	assert_float(insurance).is_equal_approx(340000.0 * 0.01 / 12.0, 0.001)
	assert_str(review.worksheet_text()).contains("New loan payment: %s (360 months, with $283 mortgage insurance)" % LoanApplication.dollars(application.new_loan_payment()))
	await assert_fits()

	review.worksheet_tabs.current_tab = LoanReviewScreen.WorksheetTab.COLLATERAL
	assert_bool(review.worksheet_rows_vbox.visible).is_false()
	assert_bool(review.collateral_rows_vbox.visible).is_true()
	var text := review.collateral_text()
	for line: String in [
		"Purchase price: $380,000",
		"Appraised value: $355,000 (below the price)",
		"Down payment: $40,000 (10.5%)",
		"Loan-to-value: 95.8%",
		"Loan ÷ the lower of price and appraisal. Policy guide: up to 80.0% healthy, over 95.0% high.",
		"Mortgage insurance: $283/mo (1.00% a year)",
	]:
		assert_str(text).contains(line)
	for hidden: String in ["low risk", "medium risk", "high risk", "Approve", "Reject", "points"]:
		assert_str(text).not_contains(hidden)
	await assert_fits()
	# The documents view hides both tabs; the worksheet button brings them back.
	review.verify_documents_button.pressed.emit()
	assert_bool(review.worksheet_tabs.visible).is_false()
	assert_bool(review.collateral_rows_vbox.visible).is_false()
	review.run_credit_check_button.pressed.emit()
	assert_bool(review.collateral_rows_vbox.visible).is_true()

	# An unsecured personal loan: nothing on the form, "None" on the tab.
	review.close_button.pressed.emit()
	open_next(sample("Priya Sharma"))
	assert_bool(review.collateral_label.visible).is_false()
	review.run_credit_check_button.pressed.emit()
	review.worksheet_tabs.current_tab = LoanReviewScreen.WorksheetTab.COLLATERAL
	assert_str(review.collateral_text()).contains("Collateral: None (unsecured: a personal loan)")

## The counter-offer shows the down payment its amount implies, as it's
## typed; and a denial for the down payment is graded like the others.
func test_the_counter_offer_down_payment_and_the_down_payment_reason() -> void:
	clock_in_at_loan_desk()
	var application := open_next(little_down())
	assert_int(application.calculate_risk_assessment()).is_equal(LoanApplication.RiskTier.MEDIUM)
	assert_int(application.assessment_without_ltv()).is_equal(LoanApplication.RiskTier.LOW)
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	assert_str(review.counter_offer_down_label.text).is_equal("A $340,000 loan means a $40,000 down payment (10.5%). Healthy LTV needs a loan of $284,000 or less.")
	review.counter_offer_amount_spinbox.value = 300000.0
	assert_str(review.counter_offer_down_label.text).is_equal("A $300,000 loan means a $80,000 down payment (21.1%). Healthy LTV needs a loan of $284,000 or less.")
	await assert_fits()
	# $339,900: affordable, but the LTV is still high: only reasonable.
	review.counter_offer_amount_spinbox.value = 339900.0
	var start := totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE)
	assert_str(review.decision_status_label.text).contains("Affordable, but the loan-to-value is still 95.7%: Healthy LTV needs a loan of $284,000 or less.")
	await assert_fits()
	review.close_button.pressed.emit()
	# $284,000: a healthy LTV, the correct call.
	var again := little_down()
	again.applicant_name = "Hugo Valdez"
	open_next(again)
	review.run_credit_check_button.pressed.emit()
	review.counter_offer_button.pressed.emit()
	review.counter_offer_amount_spinbox.value = 284000.0
	start = totals()
	review.submit_counter_offer_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.BEST_DECISION_SCORE)
	assert_str(review.decision_status_label.text).contains("Affordable, with a healthy loan-to-value (80.0%).")
	review.close_button.pressed.emit()

	# The down payment as a denial reason.
	var third := little_down()
	third.applicant_name = "Iris Navarro"
	open_next(third)
	review.run_credit_check_button.pressed.emit()

	review.reject_button.pressed.emit()
	tick([LoanApplication.DenialReason.DOWN_PAYMENT])
	await assert_fits()
	start = totals()
	review.submit_denial_button.pressed.emit()
	assert_int((totals() - start).x).is_equal(LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_RIGHT_SCORE)
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).is_equal("Loan rejected: Iris Navarro (medium risk applicant) — reasons: Down payment too small for the value")

## Staff officers judge the same LTV: a perfect officer counters the
## borderline buyer, and the weakest officer's item carries the collateral.
func test_staff_officers_use_the_collateral() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var worker := room.loan_desk_worker
	worker.staff_doc_slips = false
	var decided: Array[LoanApplication] = []
	worker.decision_made.connect(func(application: LoanApplication, _s: StaffMember, _c: bool) -> void: decided.append(application))
	worker.staff_npc.staff.skill = 10
	worker.decide_next(little_down())
	assert_int(decided[0].decision).is_equal(LoanApplication.DecisionType.COUNTER_OFFER)
	# At 80% of the $355,000 appraisal: asking for $96,000 down.
	assert_float(decided[0].decision_amount).is_equal(284000.0)
	assert_int(decided[0].grade_type(LoanApplication.DecisionType.COUNTER_OFFER)).is_equal(LoanApplication.Grade.BEST)
	assert_int(decided[0].grade_counter_offer(284000.0)).is_equal(LoanApplication.Grade.BEST)
	worker.staff_npc.staff.skill = 0
	worker.decide_next(little_down())
	var item: StaffReviewItem = StaffReviewManager.queue[-1]
	assert_str(item.collateral_text).is_equal("Collateral: home $380,000 · appraised $355,000 · down $40,000 (10.5%) · LTV 95.8% · mortgage insurance $283/mo")
	assert_str(StaffReviewScreen.details_text(item)).contains(item.collateral_text)

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
