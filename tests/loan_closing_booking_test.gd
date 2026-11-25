extends "res://tests/support/loan/loan_suite.gd"

## Part 2 of the closing step: booking integration. With the switch on
## (LoanConfig.closings_enabled), the player's approval or accepted
## counter-offer opens a closing and books nothing; funding books the loan
## under the number reserved at the approval, with the funding day, and stopping
## never books it. What each action is worth, who is counted as turned away,
## the record-only history entries, the staff taking over at a promotion, and
## the End of Day lines. With the switch off nothing changes (the existing
## loan book, return and edge tests run unchanged).

const LOAN := PlayerShift.Role.LOAN_OFFICER
const SEED := 987654
const Outcome := BookedLoan.Outcome

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

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			application.documents_issued = true
			return application
	return null

## Opens `application` on the desk, verifies, checks credit and decides (a
## counter-offer for $10,000).
func decide(application: LoanApplication, decision: LoanApplication.DecisionType) -> void:
	LoanDeskManager.player_queue.push_front(application)
	lo.applications_reviewed = 0
	lo.review_next_button.pressed.emit()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	match decision:
		LoanApplication.DecisionType.APPROVE:
			review.approve_button.pressed.emit()
		LoanApplication.DecisionType.COUNTER_OFFER:
			review.counter_offer_button.pressed.emit()
			review.counter_offer_amount_spinbox.value = 10000.0
			review.submit_counter_offer_button.pressed.emit()
		_:
			review.reject_button.pressed.emit()
			review.reason_checks[LoanApplication.DenialReason.TOTAL_DTI].button_pressed = true
			review.submit_denial_button.pressed.emit()
	review.close_button.pressed.emit()

## An approved (or counter-offered) application with healthy figures.
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

## A good applicant: low risk, documents fine.
func good_applicant(applicant: String) -> LoanApplication:
	var application := approved(applicant)
	application.credit_score = 800
	application.annual_income = 200000.0
	application.monthly_debt_payments = 0.0
	application.monthly_housing_payment = 800.0
	application.employment_months = 120
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## A risky one (not a good applicant).
func risky_applicant(applicant: String) -> LoanApplication:
	var application := approved(applicant)
	application.credit_score = 520
	application.annual_income = 30000.0
	application.monthly_debt_payments = 900.0
	application.employment_months = 6
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## Puts a closing for `application` in the list, with a loan number reserved
## and (as asked) with or without a problem: the first closing of a career is
## always clean, so a problem one is looked for from number 2 up.
func add_closing(application: LoanApplication, with_problem: bool = false) -> LoanClosing:
	var number := maxi(2, LoanRole.closings.next_number)
	var reserved := LoanBookManager.reserve_loan_id()
	var closing := LoanClosing.create(application, GameClock.day, number, LoanDeskManager.career_seed, reserved)
	while closing.has_problem() != with_problem:
		number += 1
		closing = LoanClosing.create(application, GameClock.day, number, LoanDeskManager.career_seed, reserved)
	LoanRole.closings.closings.append(closing)
	LoanRole.closings.next_number = number + 1
	return closing

func player_stats() -> Dictionary:
	return SaveGame.dict_of(LoanBookManager.period_stats, LoanBookManager.PLAYER)

func stat(key: String) -> float:
	return LoanBookManager.stat(player_stats(), key)

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

func note_roles(role: PlayerShift.Role, days: Array[int]) -> void:
	for day in days:
		LoanRole.note_role(day, role)

func start_business_day(day: int) -> void:
	GameClock.day = day
	BusinessDay.stats_day = day

## The loan, rolled the way the book rolls it, for a comparison.
func reference_loan(closing: LoanClosing, made_day: int, documents_ok: bool) -> BookedLoan:
	var reference := BookedLoan.new()
	reference.made_day = made_day
	reference.risk_tier = closing.risk_tier
	reference.documents_ok = documents_ok
	reference.purpose = closing.application.loan_purpose
	reference.amount = closing.approved_amount
	reference.collateral_kind = closing.collateral_kind
	reference.collateral_value = closing.collateral_value
	LoanBookManager.roll_outcome(reference, LoanBookManager.outcome_rng(closing.loan_id))
	return reference

func history_since(count: int) -> Array[DecisionRecord]:
	var records: Array[DecisionRecord] = []
	for i in range(count, HistoryManager.records.size()):
		records.append(HistoryManager.records[i])
	return records

# --- the switch ------------------------------------------------------------------

func test_the_switch_is_a_static_variable_and_the_loan_suite_starts_it_off() -> void:
	assert_bool(LoanConfig.CLOSINGS_ENABLED_DEFAULT).is_true()
	assert_bool(LoanConfig.closings_enabled).is_false()
	LoanConfig.closings_enabled = true
	assert_bool(LoanConfig.closings_enabled).is_true()
	# (The loan suite turns it off after every test.)

func test_with_the_switch_off_an_approval_books_at_once_as_before() -> void:
	clock_in_at_loan_desk()
	decide(sample("Elena Petrova"), LoanApplication.DecisionType.APPROVE)
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_bool(LoanRole.closings.has_data()).is_false()

# --- decision time ---------------------------------------------------------------

func test_the_players_approval_opens_a_closing_and_books_nothing() -> void:
	LoanConfig.closings_enabled = true
	clock_in_at_loan_desk()
	var records_before := HistoryManager.records.size()
	var application := sample("Elena Petrova")
	decide(application, LoanApplication.DecisionType.APPROVE)
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_float(stat("made")).is_equal(0.0)
	assert_float(stat("lent")).is_equal(0.0)
	assert_int(LoanRole.closings.count()).is_equal(1)
	var closing := LoanRole.closings.closing_for(application)
	assert_object(closing).is_not_null()
	assert_int(closing.kind).is_equal(LoanClosing.Kind.APPROVAL)
	assert_int(closing.loan_id).is_equal(1)
	assert_int(LoanBookManager.next_loan_id).is_equal(2)
	assert_float(closing.approved_amount).is_equal(application.requested_amount)
	assert_int(closing.approval_day).is_equal(GameClock.day)
	assert_int(closing.due_day).is_equal(GameClock.day + LoanConfig.CLOSING_DAYS["Home"])
	# The good applicant is counted as seen, and the decision is graded and
	# recorded as ever (an actionable record, which Approvals can override).
	assert_float(stat("good_seen")).is_equal(1.0)
	var records := history_since(records_before)
	assert_int(records.size()).is_equal(1)
	assert_bool(records[0].has_loan_context).is_true()
	assert_bool(records[0].reviewed).is_false()
	assert_int(records[0].original_decision_type).is_equal(LoanApplication.DecisionType.APPROVE)
	assert_int(lo.applications_reviewed).is_equal(1)

func test_a_counter_offer_opens_a_closing_for_the_countered_amount() -> void:
	LoanConfig.closings_enabled = true
	clock_in_at_loan_desk()
	var application := sample("Jamal Green")
	decide(application, LoanApplication.DecisionType.COUNTER_OFFER)
	assert_int(LoanBookManager.book.size()).is_equal(0)
	var closing := LoanRole.closings.closing_for(application)
	assert_int(closing.kind).is_equal(LoanClosing.Kind.COUNTER_OFFER)
	assert_float(closing.approved_amount).is_equal(10000.0)
	assert_bool(closing.application.decision == LoanApplication.DecisionType.COUNTER_OFFER).is_true()

func test_a_rejection_still_counts_a_good_applicant_turned_away_at_once() -> void:
	LoanConfig.closings_enabled = true
	clock_in_at_loan_desk()
	decide(sample("Elena Petrova"), LoanApplication.DecisionType.REJECT)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_float(stat("good_seen")).is_equal(1.0)
	assert_float(stat("turned_away")).is_equal(1.0)
	assert_float(stat("turned_away_amount")).is_equal(310000.0)

func test_the_teaching_cases_book_at_once_with_the_switch_on() -> void:
	LoanConfig.closings_enabled = true
	clock_in_at_loan_desk()
	decide(sample("Maria Chen"), LoanApplication.DecisionType.APPROVE)
	decide(sample("Angela Reyes"), LoanApplication.DecisionType.COUNTER_OFFER)
	assert_int(LoanBookManager.book.size()).is_equal(2)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_bool(LoanRole.closings.has_data()).is_false()

func test_staff_still_book_at_once_with_the_switch_on() -> void:
	LoanConfig.closings_enabled = true
	var direct := good_applicant("Staff Direct")
	assert_object(LoanBookManager.note_decision(direct, false, "Priya Anand")).is_not_null()
	assert_int(LoanBookManager.book.size()).is_equal(1)
	# And a staff desk deciding through its worker.
	var worker := room.loan_desk_worker
	worker.staff_npc.staff.skill = 10
	for i in 25:
		var safe := sample("Maria Chen")
		safe.applicant_name = "Safe %d" % i
		worker.decide_next(safe)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanBookManager.book.size()).is_greater(1)

func test_the_default_of_note_decision_is_unchanged() -> void:
	LoanConfig.closings_enabled = true
	var loan := LoanBookManager.note_decision(good_applicant("Default Path"), true, LoanBookManager.PLAYER_MAKER)
	assert_object(loan).is_not_null()
	assert_int(LoanRole.closings.count()).is_equal(0)

# --- funding ---------------------------------------------------------------------

func test_funding_books_with_the_reserved_number_the_funding_day_and_the_problem_odds() -> void:
	var clean := add_closing(approved("Fund Clean"))
	var bad := add_closing(approved("Fund Bad", "Business"), true)
	assert_bool(bad.has_problem()).is_true()
	start_business_day(9)
	var clean_result := LoanBookManager.fund(clean)
	var loan: BookedLoan = clean_result["loan"]
	assert_int(loan.loan_id).is_equal(clean.loan_id)
	assert_int(loan.made_day).is_equal(9)
	assert_bool(loan.documents_ok).is_true()
	assert_int(loan.risk_tier).is_equal(clean.risk_tier)
	assert_float(loan.amount).is_equal(clean.approved_amount)
	assert_bool(loan.by_player).is_true()
	assert_str(loan.made_by).is_equal(LoanBookManager.PLAYER_MAKER)
	var expected := reference_loan(clean, 9, true)
	assert_int(loan.outcome).is_equal(expected.outcome)
	assert_int(loan.late_day).is_equal(expected.late_day)
	assert_int(loan.resolve_day).is_equal(expected.resolve_day)
	assert_float(loan.loss).is_equal(expected.loss)
	assert_float(stat("made")).is_equal(1.0)
	# A closing with a problem that is funded anyway: the unverified odds.
	start_business_day(11)
	var bad_loan: BookedLoan = LoanBookManager.fund(bad)["loan"]
	assert_int(bad_loan.loan_id).is_equal(bad.loan_id)
	assert_int(bad_loan.made_day).is_equal(11)
	assert_bool(bad_loan.documents_ok).is_false()
	assert_array(LoanBookManager.odds_for(bad_loan.risk_tier, bad_loan.documents_ok)).is_equal(LoanBookManager.UNVERIFIED_ODDS)
	var bad_expected := reference_loan(bad, 11, false)
	assert_int(bad_loan.outcome).is_equal(bad_expected.outcome)
	assert_int(bad_loan.resolve_day).is_equal(bad_expected.resolve_day)
	assert_float(bad_loan.loss).is_equal(bad_expected.loss)
	assert_int(LoanRole.closings.count()).is_equal(0)
	# A booked loan settles within 20 business days of the funding day.
	assert_int(bad_loan.resolve_day).is_less_equal(11 + LoanBookManager.SETTLE_DAYS)

func test_a_closing_is_funded_only_once() -> void:
	var closing := add_closing(approved("Once Only"))
	assert_dict(LoanBookManager.fund(closing)).is_not_empty()
	var score := ScoreManager.total_score
	assert_dict(LoanBookManager.fund(closing)).is_empty()
	assert_dict(LoanBookManager.stop(closing)).is_empty()
	assert_int(ScoreManager.total_score).is_equal(score)
	assert_int(LoanBookManager.book.size()).is_equal(1)

## The funded loans of one career, by borrower: what became of each.
func fund_in_order(reverse: bool) -> Dictionary:
	LoanDeskManager.seed_source.seed = 777
	CareerReset.reset_all()
	var closings: Array[LoanClosing] = [
		add_closing(approved("Order A", "Auto")),
		add_closing(approved("Order B", "Business"), true),
		add_closing(approved("Order C", "Personal")),
		add_closing(approved("Order D", "Home")),
	]
	start_business_day(9)
	if reverse:
		closings.reverse()
	for closing in closings:
		LoanBookManager.fund(closing)
	var table := {}
	for loan in LoanBookManager.book:
		table[loan.borrower] = [loan.loan_id, loan.outcome, loan.late_day, loan.resolve_day, loan.loss]
	return table

func test_funding_order_never_changes_an_outcome() -> void:
	var forward := fund_in_order(false)
	var backward := fund_in_order(true)
	assert_int(forward.size()).is_equal(4)
	assert_dict(backward).is_equal(forward)
	# Four different numbers, reserved in approval order.
	var ids := {}
	for entry: Array in forward.values():
		ids[entry[0]] = true
	assert_int(ids.size()).is_equal(4)

# --- stopping --------------------------------------------------------------------

func test_stopping_never_books_the_loan() -> void:
	var clean := add_closing(approved("Stop Clean"))
	var bad := add_closing(approved("Stop Bad"), true)
	var book := LoanBookManager.book.size()
	assert_bool(LoanBookManager.stop(clean)["problem"]).is_false()
	assert_bool(LoanBookManager.stop(bad)["problem"]).is_true()
	assert_int(LoanBookManager.book.size()).is_equal(book)
	assert_float(stat("made")).is_equal(0.0)
	assert_int(LoanRole.closings.count()).is_equal(0)

# --- what each action is worth ------------------------------------------------------

func test_every_row_of_the_points_table() -> void:
	assert_int(LoanConfig.CLOSING_FUND_CLEAN_SCORE).is_equal(5)
	assert_int(LoanConfig.CLOSING_STOP_PROBLEM_SCORE).is_equal(8)
	assert_int(LoanConfig.CLOSING_STOP_PROBLEM_REPUTATION).is_equal(1)
	assert_int(LoanConfig.CLOSING_STOP_CLEAN_SCORE).is_equal(-3)
	assert_int(LoanConfig.CLOSING_FUND_PROBLEM_SCORE).is_equal(-10)
	assert_int(LoanConfig.CLOSING_FUND_PROBLEM_REPUTATION).is_equal(-2)
	# [fund or stop, with a problem, Score, Reputation]
	var rows: Array = [
		["fund", false, 5, 0],
		["stop", true, 8, 1],
		["stop", false, -3, 0],
		["fund", true, -10, -2],
	]
	for row: Array in rows:
		var funds: bool = row[0] == "fund"
		var with_problem: bool = row[1]
		var score: int = row[2]
		var reputation: int = row[3]
		CareerReset.reset_all()
		var closing := add_closing(approved("Row Test"), with_problem)
		var start := score_and_reputation()
		var xp := XPManager.total_xp
		var result := LoanBookManager.fund(closing) if funds else LoanBookManager.stop(closing)
		var label := "%s, problem %s" % [row[0], with_problem]
		assert_vector(score_and_reputation() - start).override_failure_message(label).is_equal(Vector2i(score, reputation))
		assert_int(result["score"]).override_failure_message(label).is_equal(score)
		assert_int(result["reputation"]).override_failure_message(label).is_equal(reputation)
		assert_int(result["xp"]).override_failure_message(label).is_equal(score * XPManager.XP_PER_SCORE_POINT)
		assert_int(XPManager.total_xp).override_failure_message(label).is_equal(maxi(0, xp + score * XPManager.XP_PER_SCORE_POINT))

func test_careful_play_beats_blind_funding_beats_stopping_everything() -> void:
	var p := LoanConfig.CLOSING_PROBLEM_CHANCE
	var careful := (1.0 - p) * LoanConfig.CLOSING_FUND_CLEAN_SCORE + p * LoanConfig.CLOSING_STOP_PROBLEM_SCORE
	var blind := (1.0 - p) * LoanConfig.CLOSING_FUND_CLEAN_SCORE + p * LoanConfig.CLOSING_FUND_PROBLEM_SCORE
	var stop_all := (1.0 - p) * LoanConfig.CLOSING_STOP_CLEAN_SCORE + p * LoanConfig.CLOSING_STOP_PROBLEM_SCORE
	assert_float(careful).is_equal_approx(5.43, 0.01)
	assert_float(blind).is_equal_approx(2.86, 0.01)
	assert_float(stop_all).is_equal_approx(-1.43, 0.01)
	assert_float(careful).is_greater(blind)
	assert_float(blind).is_greater(0.0)
	assert_float(stop_all).is_less(0.0)
	# Approve then close, over its two slots, against a correct reject in one.
	var per_slot := (LoanApplication.score_for_grade(LoanApplication.Grade.BEST) + careful) / 2.0
	assert_float(per_slot).is_equal_approx(7.71, 0.01)
	assert_float(per_slot).is_less(float(LoanApplication.score_for_grade(LoanApplication.Grade.BEST)))
	# The same, measured over the closings the career's seed really produces.
	var careful_total := 0.0
	var blind_total := 0.0
	var stop_total := 0.0
	var sample_size := 6000
	var application := approved("Measured")
	for number in range(2, 2 + sample_size):
		var problem := LoanClosing.create(application, 10, number, SEED).has_problem()
		careful_total += LoanConfig.CLOSING_STOP_PROBLEM_SCORE if problem else LoanConfig.CLOSING_FUND_CLEAN_SCORE
		blind_total += LoanConfig.CLOSING_FUND_PROBLEM_SCORE if problem else LoanConfig.CLOSING_FUND_CLEAN_SCORE
		stop_total += LoanConfig.CLOSING_STOP_PROBLEM_SCORE if problem else LoanConfig.CLOSING_STOP_CLEAN_SCORE
	assert_float(careful_total / sample_size).is_equal_approx(careful, 0.2)
	assert_float(blind_total / sample_size).is_equal_approx(blind, 0.3)
	assert_float(stop_total / sample_size).is_equal_approx(stop_all, 0.25)

# --- turned away -----------------------------------------------------------------

func test_a_stopped_clean_closing_of_a_good_applicant_counts_as_turned_away() -> void:
	var good := add_closing(good_applicant("Lost Good"))
	assert_bool(good.is_good_applicant()).is_true()
	LoanBookManager.stop(good)
	assert_float(stat("turned_away")).is_equal(1.0)
	assert_float(stat("turned_away_amount")).is_equal(good.approved_amount)
	# Not a good applicant: nothing counted.
	LoanBookManager.stop(add_closing(risky_applicant("Lost Risky")))
	assert_float(stat("turned_away")).is_equal(1.0)
	# A closing with a real problem is not a good applicant lost.
	LoanBookManager.stop(add_closing(good_applicant("Caught Good"), true))
	assert_float(stat("turned_away")).is_equal(1.0)
	# Funding counts nothing either.
	LoanBookManager.fund(add_closing(good_applicant("Funded Good")))
	assert_float(stat("turned_away")).is_equal(1.0)

func test_a_lapsed_good_applicant_counts_as_turned_away_but_the_quiet_expiry_does_not() -> void:
	var good := add_closing(good_applicant("Lapsed Good"))
	var risky := add_closing(risky_applicant("Lapsed Risky"))
	good.due_day = 6
	risky.due_day = 6
	note_roles(LOAN, [8, 9, 10])
	GameClock.day = 12
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(2)
	assert_float(stat("turned_away")).is_equal(1.0)
	assert_float(stat("turned_away_amount")).is_equal(good.approved_amount)
	# The quiet expiry counts nothing, a good applicant or not.
	var parked := add_closing(good_applicant("Parked Good"))
	parked.due_day = 12 - LoanConfig.ABANDONED_AFTER_DAYS + 1
	GameClock.day = 13
	LoanRole.role_days.clear()
	LoanRole.start_of_day()
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Parked Good"])
	assert_float(stat("turned_away")).is_equal(1.0)
	assert_int(LoanBookManager.book.size()).is_equal(0)

# --- the history -------------------------------------------------------------------

func test_funded_and_stopped_closings_are_record_only_history_entries() -> void:
	var funded := add_closing(approved("Record Fund"))
	var caught := add_closing(approved("Record Caught"), true)
	var lost := add_closing(approved("Record Lost"))
	var wrong := add_closing(approved("Record Wrong"), true)
	var count := HistoryManager.records.size()
	LoanBookManager.fund(funded)
	LoanBookManager.stop(caught)
	LoanBookManager.stop(lost)
	LoanBookManager.fund(wrong)
	var records := history_since(count)
	assert_int(records.size()).is_equal(4)
	for record in records:
		assert_int(record.role).is_equal(DecisionRecord.Role.LOAN_OFFICER)
		assert_bool(record.reviewed).is_true()
		# Not a decision: nothing for Approvals to override or re-grade.
		assert_bool(record.has_loan_context).is_false()
	assert_str(records[0].description).is_equal("Closing: funded Record Fund ($20,000)")
	assert_str(records[0].grade_label).is_equal(LoanBookManager.FUNDED_LABEL)
	assert_str(records[1].description).contains("stopped Record Caught")
	assert_str(records[1].grade_label).starts_with("Good catch")
	assert_str(records[2].grade_label).is_equal(LoanBookManager.STOPPED_CLEAN_LABEL)
	assert_str(records[3].grade_label).starts_with("Serious mistake")
	assert_str(records[3].grade_label).contains(wrong.problem_label())

# --- promotion ------------------------------------------------------------------------

func test_a_promotion_has_the_staff_stop_problem_closings_and_fund_clean_ones() -> void:
	var clean := add_closing(approved("Staff Clean"))
	var bad := add_closing(approved("Staff Bad"), true)
	var good_lost := add_closing(good_applicant("Staff Good"), true)
	note_roles(LOAN, [3])
	start_business_day(8)
	var start := score_and_reputation()
	var xp := XPManager.total_xp
	var records := HistoryManager.records.size()
	LoanRole._on_promoted()
	# No Score, Reputation, XP, history or "turned away".
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(XPManager.total_xp).is_equal(xp)
	assert_int(HistoryManager.records.size()).is_equal(records)
	assert_float(stat("turned_away")).is_equal(0.0)
	# The clean one is booked normally: the reserved number, today.
	assert_int(LoanBookManager.book.size()).is_equal(1)
	var loan := LoanBookManager.book[0]
	assert_str(loan.borrower).is_equal("Staff Clean")
	assert_int(loan.loan_id).is_equal(clean.loan_id)
	assert_int(loan.made_day).is_equal(8)
	assert_bool(loan.documents_ok).is_true()
	assert_bool(bad.has_problem() and good_lost.has_problem()).is_true()
	# Nothing is left open, nor the role days.
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_dict(LoanRole.role_days).is_empty()
	assert_array(LoanRole.closings.summary_lines(8)).is_equal(["Closings passed to your staff: 1 funded, 2 stopped"])
	# Nothing from the closings runs afterwards.
	GameClock.day = 30
	LoanRole.start_of_day()
	assert_int(LoanBookManager.book.size()).is_equal(1)

func test_a_closing_left_over_for_a_branch_manager_goes_to_the_staff_at_opening() -> void:
	add_closing(approved("Left Over"))
	XPManager.is_branch_manager_unlocked = true
	start_business_day(8)
	var start := score_and_reputation()
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanBookManager.book.size()).is_equal(1)
	assert_vector(score_and_reputation()).is_equal(start)

func test_a_promotion_with_no_closings_says_nothing() -> void:
	start_business_day(8)
	LoanRole._on_promoted()
	assert_array(LoanRole.closings.summary_lines(8)).is_empty()
	assert_bool(LoanRole.closings.has_data()).is_false()

func test_a_demotion_after_a_promotion_starts_clean() -> void:
	add_closing(approved("Before"))
	LoanRole._on_promoted()
	LoanRole._on_demoted()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_array(LoanRole.closings.summary_lines(GameClock.day)).is_empty()

# --- the End of Day lines ----------------------------------------------------------------

func test_the_end_of_day_line_for_a_closing_closed_quietly() -> void:
	var quiet := add_closing(approved("Quiet Quinn"))
	quiet.due_day = 12 - LoanConfig.ABANDONED_AFTER_DAYS
	start_business_day(12)
	LoanRole.start_of_day()
	assert_array(LoanBookManager.summary_lines(false)).is_equal(["Closings left open too long were closed: Quiet Quinn"])

func test_the_end_of_day_lines_for_every_kind_of_closing() -> void:
	var lapse := add_closing(approved("Lapsed Larry"))
	lapse.due_day = 6
	note_roles(LOAN, [8, 9, 10])
	start_business_day(12)
	LoanRole.start_of_day()
	var funded := add_closing(approved("Funded Fay"))
	var stopped := add_closing(approved("Stopped Sam"))
	LoanBookManager.fund(funded)
	LoanBookManager.stop(stopped)
	var lines := LoanBookManager.summary_lines(false)
	assert_array(lines).is_equal([
		"Closings funded: Funded Fay",
		"Closings stopped: Stopped Sam",
		"Closings not completed in time: Lapsed Larry (-2 Score, -1 Reputation)",
	])
	# The file lines come first, the loan events last.
	LoanRole.pipeline.log_day = 12
	LoanRole.pipeline.log_expired.append("Cy Diaz")
	lines = LoanBookManager.summary_lines(false)
	assert_str(lines[0]).starts_with("Files that never came back")
	assert_str(lines[1]).starts_with("Closings funded")
	# Another day shows nothing.
	GameClock.day = 13
	assert_array(LoanBookManager.summary_lines(false)).is_empty()

func test_the_end_of_day_closing_lines_survive_a_save_and_a_load() -> void:
	var funded := add_closing(approved("Saved Fund"))
	var stopped := add_closing(approved("Saved Stop"))
	start_business_day(12)
	LoanBookManager.fund(funded)
	LoanBookManager.stop(stopped)
	LoanRole.closings.note_passed(2, 1, 12)
	var lines := LoanRole.closings.summary_lines(12)
	assert_int(lines.size()).is_equal(3)
	var saved := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	LoanRole.reset()
	LoanRole.load_data(saved)
	assert_array(LoanRole.closings.summary_lines(12)).is_equal(lines)

func test_a_closing_keeps_what_it_will_be_booked_as_through_a_save() -> void:
	var home := approved("Frozen Home", "Home")
	home.collateral_issued = true
	home.collateral_kind = LoanApplication.Collateral.HOUSE
	home.purchase_price = 250000.0
	home.collateral_value = 250000.0
	var closing := add_closing(home, true)
	var saved := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	LoanRole.reset()
	LoanRole.load_data(saved)
	var loaded := LoanRole.closings.closings[0]
	assert_int(loaded.risk_tier).is_equal(closing.risk_tier)
	assert_bool(loaded.documents_ok).is_equal(closing.documents_ok)
	assert_int(loaded.collateral_kind).is_equal(LoanApplication.Collateral.HOUSE)
	assert_float(loaded.collateral_value).is_equal(closing.collateral_value)
	assert_float(loaded.collateral_value).is_greater(0.0)
	assert_int(loaded.loan_id).is_equal(closing.loan_id)
	# Funded after a reload: the same loan.
	var loan: BookedLoan = LoanBookManager.fund(loaded)["loan"]
	assert_int(loan.loan_id).is_equal(closing.loan_id)
	assert_int(loan.collateral_kind).is_equal(LoanApplication.Collateral.HOUSE)

func test_the_end_of_day_summary_with_every_closing_line_fits_the_window() -> void:
	XPManager.is_loan_officer_unlocked = true
	var today := BusinessDay.stats_day
	GameClock.day = today
	var closings := LoanRole.closings
	closings.log_day = today
	closings.log_funded.assign(["Funded One", "Funded Two", "Funded Three", "Funded Four"])
	closings.log_stopped.assign(["Stopped One", "Stopped Two"])
	closings.log_lapsed.append({"name": "Lapsed One", "amount": 20000.0, "score": -2, "reputation": -1, "turned_away": true})
	closings.log_lapsed.append({"name": "Lapsed Two", "amount": 20000.0, "score": -2, "reputation": 0, "turned_away": false})
	closings.log_abandoned.assign(["Quiet One", "Quiet Two"])
	closings.log_passed_funded = 3
	closings.log_passed_stopped = 2
	var pipeline := LoanRole.pipeline
	pipeline.log_day = today
	pipeline.log_returned.assign(["Ana Lopez", "Bo Park"])
	pipeline.log_withdrawn.append({"name": "Ben Hart", "score": -2, "reputation": -1})
	pipeline.log_abandoned.assign(["Cal Reed"])
	pipeline.log_expired.assign(["Cy Diaz"])
	pipeline.log_passed = 2
	for i in 5:
		BusinessDay.after_cutoff.append({"time": "2:%02d PM" % (10 + i), "type": "Deposit", "amount_cents": 50000, "account": "Customer %d" % i, "posting_day": today + 1})
	GameClock.minutes = 17 * 60.0 + 1.0
	room.show_end_of_day()
	var eod := room.end_of_day_screen
	assert_bool(eod.is_summary_shown()).is_true()
	var text := eod.summary_label.text
	assert_str(text).contains("Closings funded: Funded One, Funded Two, Funded Three, Funded Four")
	assert_str(text).contains("Closings stopped: Stopped One, Stopped Two")
	assert_str(text).contains("Closings not completed in time: Lapsed One (-2 Score, -1 Reputation), Lapsed Two (-2 Score)")
	assert_str(text).contains("Closings left open too long were closed: Quiet One, Quiet Two")
	assert_str(text).contains("Closings passed to your staff: 3 funded, 2 stopped")
	await frames(4)
	var problems := layout_problems(eod.summary_panel)
	problems.append_array(controls_line_problems(eod.summary_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- the portfolio report ---------------------------------------------------------------

func test_the_report_calls_unverified_defaults_unverified_or_mismatched() -> void:
	var stats := {"defaulted": 2.0, "defaulted_unverified": 1.0, "losses": 18000.0, "settled_amount": 190000.0, "on_time": 8.0, "good_seen": 6.0}
	var rating := LoanBookManager.rate(stats)
	var lines := LoanBookManager.comments({"stats": stats, "rating": rating})
	assert_array(lines).contains(["1 of the defaults was on documents that were unverified or mismatched."])
