extends "res://tests/support/loan/loan_suite.gd"

## Part 1 of the closing step: the rules and the saves, nothing a player can
## see. A closing (LoanClosing) is an approved loan waiting for its closing
## day; LoanClosings is the list, held by LoanRole. Covered here: the problem
## roll (a pure function of the career seed and the closing's number, never the
## name, look, finances or decision type), the first closing always clean, the
## measured rates and mix, the figures each problem puts on the paperwork, due
## days across weekends and holidays, the lapse (only Loan Officer days, once
## only), the Reputation floor, role days, the promotion plan, demotion, and
## the saves (old saves, and a career that never closes saves what main saved).

const OLD_SAVES := "res://tests/data/old_saves/"
const LOAN := PlayerShift.Role.LOAN_OFFICER
const TELLER := PlayerShift.Role.TELLER
const SEED := 987654
const PURPOSES: Array[String] = ["Auto", "Personal", "Business", "Home"]
const ROLL_SAMPLE := 12000

func before_test() -> void:
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## An approved (or counter-offered) application with healthy figures.
func approved(applicant: String = "Closing Test", purpose: String = "Auto", income: float = 72000.0, counter: bool = false) -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = applicant
	application.loan_purpose = purpose
	application.requested_amount = 200000.0 if purpose == "Home" else 20000.0
	application.annual_income = income
	application.monthly_housing_payment = 1200.0
	application.monthly_debt_payments = 300.0
	application.existing_debt = 9000.0
	application.credit_score = 720
	application.employment_months = 60
	application.decision = LoanApplication.DecisionType.COUNTER_OFFER if counter else LoanApplication.DecisionType.APPROVE
	application.decision_amount = application.requested_amount - 2000.0 if counter else application.requested_amount
	# As on the desk: the assessment is worked out before a decision.
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## A whole number kept in a dictionary under `key` (0 when it isn't there).
func int_in(counts: Dictionary, key: int) -> int:
	return SaveGame.int_value(counts.get(key, 0), 0)

func make(application: LoanApplication, number: int, day: int = 10, career_seed: int = SEED, reserved: int = 0) -> LoanClosing:
	return LoanClosing.create(application, day, number, career_seed, reserved)

## The first closing numbered from 2 up whose problem is `wanted` (the
## career's first is always clean).
func closing_with(application: LoanApplication, wanted: LoanClosing.Problem) -> LoanClosing:
	for number in range(2, 4000):
		var closing := make(application, number)
		if closing.problem == wanted:
			return closing
	return null

func note_roles(role: PlayerShift.Role, days: Array[int]) -> void:
	for day in days:
		LoanRole.note_role(day, role)

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

## Everything about a closing but its application, as saved.
func figures_of(closing: LoanClosing) -> Dictionary:
	var data := closing.save_data()
	data.erase("application")
	return data

## The figures that differ between two closings, as "key: a vs b".
func differences(first: LoanClosing, second: LoanClosing) -> PackedStringArray:
	var one := figures_of(first)
	var two := figures_of(second)
	var found := PackedStringArray()
	for key: String in one:
		if one[key] != two.get(key):
			found.append("%s: %s vs %s" % [key, str(one[key]), str(two.get(key))])
	return found

func loan_day_at_9am() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)

func go_home_from_the_loan_desk() -> void:
	var lo := room.loan_officer_screen
	to_closing()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	lo.shift_summary_done_button.pressed.emit()
	lo.hide_screen()

# --- the switch and the numbers ------------------------------------------------------

func test_the_switch_is_off_and_the_numbers_are_in_the_config() -> void:
	# On in the game (LoanConfig.CLOSINGS_ENABLED_DEFAULT); the loan suite starts
	# every test with it off.
	assert_bool(LoanConfig.CLOSINGS_ENABLED_DEFAULT).is_true()
	assert_bool(LoanConfig.closings_enabled).is_false()
	assert_float(LoanConfig.CLOSING_PROBLEM_CHANCE).is_equal_approx(1.0 / 7.0, 0.0000001)
	var mix := LoanConfig.CLOSING_MIX_TERMS + LoanConfig.CLOSING_MIX_EXPIRED_ID + LoanConfig.CLOSING_MIX_NO_SIGNATURE + LoanConfig.CLOSING_MIX_NEW_DEBT
	assert_float(mix).is_equal_approx(1.0, 0.0000001)
	assert_int(LoanConfig.CLOSING_LAPSE_DAYS).is_equal(3)
	assert_dict(LoanConfig.CLOSING_DAYS).is_equal({"Auto": 1, "Personal": 1, "Business": 2, "Home": 3})

# --- due days -----------------------------------------------------------------------

func test_due_days_by_purpose_skip_weekends_and_holidays() -> void:
	assert_int(GameClock.start_date).is_equal(BankCalendar.epoch_day(2026, 1, 5))
	var expected := {"Auto": 1, "Personal": 1, "Business": 2, "Home": 3}
	for purpose: String in expected:
		var days: int = expected[purpose]
		assert_int(LoanClosing.due_days_for(purpose)).is_equal(days)
		# Approved on a Friday (day 5, 9 January): a weekend in between.
		var friday := make(approved("Fri Test", purpose), 2, 5)
		assert_int(friday.due_day).is_equal(5 + days)
		assert_bool(BankCalendar.is_business_day(friday.closing_date())).is_true()
		assert_bool(BankCalendar.is_weekend(friday.closing_date())).is_false()
		# Approved on Friday the 16th (day 10): the weekend and Martin Luther
		# King Day (19 January) are in between.
		var holiday := make(approved("Holiday Test", purpose), 2, 10)
		assert_int(holiday.due_day).is_equal(10 + days)
		assert_bool(BankCalendar.is_business_day(holiday.closing_date())).is_true()
		assert_bool(holiday.is_due(holiday.due_day - 1)).is_false()
		assert_bool(holiday.is_due(holiday.due_day)).is_true()
		assert_bool(holiday.is_due(holiday.due_day + 5)).is_true()
	assert_int(make(approved("A", "Auto"), 2, 5).closing_date()).is_equal(BankCalendar.epoch_day(2026, 1, 12))
	assert_int(make(approved("B", "Auto"), 2, 10).closing_date()).is_equal(BankCalendar.epoch_day(2026, 1, 20))
	assert_int(make(approved("C", "Home"), 2, 10).closing_date()).is_equal(BankCalendar.epoch_day(2026, 1, 22))
	# A purpose the table doesn't know takes the default.
	assert_int(LoanClosing.due_days_for("Boat")).is_equal(LoanConfig.CLOSING_DAYS_DEFAULT)

func test_due_closings_come_longest_due_first() -> void:
	var home := LoanRole.closings.open(approved("Home Test", "Home"), 5, SEED)
	var auto := LoanRole.closings.open(approved("Auto Test", "Auto"), 5, SEED)
	var other := LoanRole.closings.open(approved("Other Test", "Business"), 5, SEED)
	assert_array(LoanRole.closings.due_closings(5)).is_empty()
	assert_array(LoanRole.closings.due_closings(6)).is_equal([auto])
	assert_array(LoanRole.closings.due_closings(7)).is_equal([auto, other])
	assert_array(LoanRole.closings.due_closings(9)).is_equal([auto, other, home])

func test_only_an_approval_or_an_accepted_counter_offer_makes_a_closing() -> void:
	var rejected := approved()
	rejected.decision = LoanApplication.DecisionType.REJECT
	assert_object(LoanRole.closings.open(rejected, 5, SEED)).is_null()
	var undecided := approved()
	undecided.decision = LoanApplication.DecisionType.NONE
	assert_object(LoanRole.closings.open(undecided, 5, SEED)).is_null()
	assert_int(LoanRole.closings.next_number).is_equal(1)
	var counter := LoanRole.closings.open(approved("Counter Test", "Auto", 72000.0, true), 5, SEED, 77)
	assert_int(counter.kind).is_equal(LoanClosing.Kind.COUNTER_OFFER)
	assert_float(counter.approved_amount).is_equal(18000.0)
	assert_int(counter.loan_id).is_equal(77)
	var plain := LoanRole.closings.open(approved("Plain Test"), 5, SEED)
	assert_int(plain.kind).is_equal(LoanClosing.Kind.APPROVAL)
	assert_int(plain.number).is_equal(2)
	assert_int(LoanRole.closings.next_number).is_equal(3)

func test_the_approved_terms_are_frozen_on_the_closing() -> void:
	var application := approved("Frozen Test", "Auto")
	var closing := make(application, 2)
	var payment := roundf(application.new_loan_payment(20000.0) * 100.0) / 100.0
	assert_float(closing.approved_amount).is_equal(20000.0)
	assert_float(closing.approved_rate).is_equal(application.annual_rate())
	assert_int(closing.approved_term).is_equal(60)
	assert_float(closing.approved_payment).is_equal(payment)
	# Changing the application afterwards does not change what was approved.
	application.credit_score = 500
	assert_float(closing.approved_rate).is_not_equal(application.annual_rate())

# --- the problem roll -----------------------------------------------------------------

func test_the_same_seed_and_number_give_the_same_problem_whatever_the_global_generator_does() -> void:
	for number in range(2, 200):
		seed(1)
		var first := make(approved("Same Test"), number)
		seed(99999)
		randf()
		var second := make(approved("Same Test"), number)
		assert_dict(figures_of(second)).override_failure_message("closing %d" % number).is_equal(figures_of(first))
	# A different career seed or number gives different closings.
	var different := 0
	for number in range(2, 200):
		if make(approved(), number).problem != make(approved(), number, 10, SEED + 1).problem:
			different += 1
	assert_int(different).is_greater(10)

func test_the_first_closing_of_a_career_is_always_clean() -> void:
	for career_seed in 500:
		var first := make(approved(), 1, 10, career_seed)
		assert_int(first.problem).override_failure_message("seed %d" % career_seed).is_equal(LoanClosing.Problem.NONE)
		assert_bool(first.terms_match()).is_true()
		assert_bool(first.signed).is_true()
		assert_bool(first.id_is_expired()).is_false()
		assert_float(first.new_debt_payment).is_equal(0.0)
	# Through the list: the first opened is number 1.
	var opened := LoanRole.closings.open(approved(), 5, SEED)
	assert_int(opened.number).is_equal(1)
	assert_bool(opened.has_problem()).is_false()

func test_the_measured_rates_match_the_configured_ones() -> void:
	var counts := {}
	for problem: int in LoanClosing.Problem.values():
		counts[problem] = 0
	var fields := {}
	for number in range(2, 2 + ROLL_SAMPLE):
		var closing := make(approved(), number)
		counts[closing.problem] += 1
		if closing.problem == LoanClosing.Problem.TERMS:
			fields[closing.terms_field] = int_in(fields, closing.terms_field) + 1
	var problems := ROLL_SAMPLE - int_in(counts, LoanClosing.Problem.NONE)
	assert_float(float(problems) / ROLL_SAMPLE).is_equal_approx(LoanConfig.CLOSING_PROBLEM_CHANCE, 0.015)
	var shares := {
		LoanClosing.Problem.TERMS: LoanConfig.CLOSING_MIX_TERMS,
		LoanClosing.Problem.EXPIRED_ID: LoanConfig.CLOSING_MIX_EXPIRED_ID,
		LoanClosing.Problem.NO_SIGNATURE: LoanConfig.CLOSING_MIX_NO_SIGNATURE,
		LoanClosing.Problem.NEW_DEBT: LoanConfig.CLOSING_MIX_NEW_DEBT,
	}
	for problem: int in shares:
		var share: float = shares[problem]
		assert_float(float(int_in(counts, problem)) / problems).override_failure_message("mix of problem %d" % problem).is_equal_approx(share, 0.04)
	# Every figure of a terms mismatch comes up, about a quarter each.
	var mismatches := int_in(counts, LoanClosing.Problem.TERMS)
	for field: int in [LoanClosing.TermsField.AMOUNT, LoanClosing.TermsField.RATE, LoanClosing.TermsField.TERM, LoanClosing.TermsField.PAYMENT]:
		assert_float(float(int_in(fields, field)) / mismatches).override_failure_message("field %d" % field).is_equal_approx(0.25, 0.07)

func test_the_problem_does_not_depend_on_name_look_finances_or_decision_type() -> void:
	var seen_terms_counter := 0
	for number in range(2, 600):
		var base := make(approved("Base Name", "Auto", 72000.0), number)
		var other := approved("Someone Else Entirely", "Business", 31000.0)
		other.applicant_look = 7
		other.credit_score = 560
		other.monthly_debt_payments = 900.0
		other.requested_amount = 55000.0
		other.decision_amount = 55000.0
		var rich := approved("Another One", "Home", 240000.0)
		rich.applicant_look = 3
		var counter := approved("Counter Name", "Personal", 54000.0, true)
		var variants: Array[LoanApplication] = [other, rich, counter]
		for variant in variants:
			var closing := make(variant, number)
			assert_int(closing.problem).override_failure_message("closing %d" % number).is_equal(base.problem)
			assert_bool(closing.signed).is_equal(base.signed)
		# Decision type changes only the wrong figure of a mismatch.
		var counter_closing := make(counter, number)
		if base.problem == LoanClosing.Problem.TERMS:
			assert_int(counter_closing.terms_field).is_equal(LoanClosing.TermsField.AMOUNT)
			assert_float(counter_closing.paper_amount).is_equal(counter.requested_amount)
			seen_terms_counter += 1
		else:
			assert_int(counter_closing.terms_field).is_equal(LoanClosing.TermsField.NONE)
	assert_int(seen_terms_counter).is_greater(10)

# --- what each problem looks like -------------------------------------------------------

func test_a_terms_mismatch_changes_exactly_one_figure() -> void:
	var application := approved("Terms Test", "Business")
	var fields := {}
	for number in range(2, 3000):
		var closing := make(application, number)
		if closing.problem != LoanClosing.Problem.TERMS:
			assert_bool(closing.terms_match()).is_true()
			continue
		assert_bool(closing.terms_match()).is_false()
		fields[closing.terms_field] = true
		var changed := 0
		changed += 0 if is_equal_approx(closing.paper_amount, closing.approved_amount) else 1
		changed += 0 if is_equal_approx(closing.paper_rate, closing.approved_rate) else 1
		changed += 0 if closing.paper_term == closing.approved_term else 1
		changed += 0 if is_equal_approx(closing.paper_payment, closing.approved_payment) else 1
		assert_int(changed).override_failure_message("closing %d" % number).is_equal(1)
		# Everything else on the paperwork is in order.
		assert_bool(closing.signed).is_true()
		assert_bool(closing.id_is_expired()).is_false()
		assert_float(closing.new_debt_payment).is_equal(0.0)
		assert_float(closing.paper_amount).is_greater(0.0)
		assert_float(closing.paper_rate).is_greater(0.0)
		assert_int(closing.paper_term).is_greater_equal(12)
	assert_int(fields.size()).is_equal(4)

func test_an_accepted_counter_offers_wrong_figure_is_the_amount_first_asked_for() -> void:
	var application := approved("Counter Test", "Auto", 72000.0, true)
	var mismatched := closing_with(application, LoanClosing.Problem.TERMS)
	assert_object(mismatched).is_not_null()
	assert_int(mismatched.terms_field).is_equal(LoanClosing.TermsField.AMOUNT)
	assert_float(mismatched.approved_amount).is_equal(18000.0)
	assert_float(mismatched.paper_amount).is_equal(20000.0)
	assert_float(mismatched.paper_rate).is_equal(mismatched.approved_rate)
	assert_int(mismatched.paper_term).is_equal(mismatched.approved_term)
	assert_float(mismatched.paper_payment).is_equal(mismatched.approved_payment)
	# A counter-offer does not always mismatch: most don't.
	var clean := 0
	for number in range(2, 300):
		if make(application, number).problem == LoanClosing.Problem.NONE:
			clean += 1
	assert_int(clean).is_greater(200)

func test_an_expired_id_and_a_missing_signature_show_on_the_paperwork() -> void:
	var application := approved("Paper Test")
	var expired := closing_with(application, LoanClosing.Problem.EXPIRED_ID)
	assert_bool(expired.id_is_expired()).is_true()
	assert_int(expired.id_expiry_date).is_less(expired.closing_date())
	assert_bool(expired.signed).is_true()
	assert_bool(expired.terms_match()).is_true()
	var unsigned := closing_with(application, LoanClosing.Problem.NO_SIGNATURE)
	assert_bool(unsigned.signed).is_false()
	assert_bool(unsigned.id_is_expired()).is_false()
	assert_bool(unsigned.terms_match()).is_true()
	for number in range(2, 400):
		var closing := make(application, number)
		if closing.problem != LoanClosing.Problem.EXPIRED_ID:
			assert_bool(closing.id_is_expired()).override_failure_message("closing %d" % number).is_false()
		if closing.problem != LoanClosing.Problem.NO_SIGNATURE:
			assert_bool(closing.signed).is_true()

func test_a_new_debt_always_pushes_the_total_debt_to_income_over_43_percent() -> void:
	var healthy := approved("Healthy Test")
	var stretched := approved("Stretched Test", "Auto", 60000.0)
	stretched.monthly_debt_payments = 2400.0
	var home := approved("Home Test", "Home", 150000.0)
	var broke := approved("Broke Test", "Personal", 0.0)
	assert_float(stretched.total_dti(20000.0)).is_greater(LoanApplication.STRETCHED_DTI)
	var tested := 0
	var applications: Array[LoanApplication] = [healthy, stretched, home]
	for application in applications:
		for number in range(2, 1500):
			var closing := make(application, number)
			if closing.problem == LoanClosing.Problem.NEW_DEBT:
				tested += 1
				assert_float(closing.new_debt_payment).is_greater_equal(LoanConfig.NEW_DEBT_MIN_PAYMENT)
				assert_float(fmod(closing.new_debt_payment, 10.0)).is_equal(0.0)
				assert_float(closing.dti_with_new_debt()).override_failure_message("closing %d" % number).is_greater(LoanApplication.STRETCHED_DTI)
				assert_float(closing.dti_with_new_debt()).is_greater(closing.dti_at_approval())
				# Never a clean-looking closing: nothing else is wrong.
				assert_bool(closing.terms_match()).is_true()
				assert_bool(closing.signed).is_true()
			else:
				assert_float(closing.new_debt_payment).is_equal(0.0)
				assert_float(closing.dti_with_new_debt()).is_equal_approx(closing.dti_at_approval(), 0.0000001)
	assert_int(tested).is_greater(100)
	# A healthy applicant's new debt lands in the 44-50% band (the payment
	# rounds up, so a hair above it at most).
	for number in range(2, 1500):
		var closing := make(healthy, number)
		if closing.problem == LoanClosing.Problem.NEW_DEBT:
			assert_float(closing.dti_with_new_debt()).is_between(LoanConfig.NEW_DEBT_DTI_RANGE[0], LoanConfig.NEW_DEBT_DTI_RANGE[1] + 0.01)
	# With no income to measure it against, a new debt becomes a terms mismatch.
	for number in range(2, 600):
		assert_int(make(broke, number).problem).is_not_equal(LoanClosing.Problem.NEW_DEBT)

# --- the lapse ----------------------------------------------------------------------

func test_only_loan_officer_days_count_towards_a_lapse() -> void:
	var closing := LoanRole.closings.open(approved("Lapse Test"), 6, SEED)
	assert_int(closing.due_day).is_equal(7)
	# Day 7 is the due day: the days after it count.
	note_roles(LOAN, [8, 10, 11])
	note_roles(TELLER, [9])
	var roles := LoanRole.role_days
	assert_int(closing.loan_officer_days_since_due(11, roles)).is_equal(2)
	assert_bool(closing.is_overdue(11, roles)).is_false()
	assert_int(closing.days_left(11, roles)).is_equal(1)
	assert_int(closing.loan_officer_days_since_due(12, roles)).is_equal(3)
	assert_bool(closing.is_overdue(12, roles)).is_true()
	# Before the due day it can never be overdue, and a day with no role
	# recorded counts for nothing.
	assert_bool(closing.is_overdue(5, {8: LOAN, 9: LOAN, 10: LOAN, 11: LOAN})).is_false()
	assert_bool(closing.is_overdue(12, {8: LOAN, 9: PlayerShift.Role.NONE, 10: LOAN, 11: PlayerShift.Role.BRANCH_MANAGER})).is_false()
	# The last day it can be closed on if every day from `today` is a Loan
	# Officer day (a Teller day pushes it back).
	assert_int(closing.last_day_to_close(8, {})).is_equal(10)
	assert_int(closing.last_day_to_close(3, {})).is_equal(10)
	assert_int(closing.last_day_to_close(10, {8: LOAN, 9: LOAN})).is_equal(10)
	assert_int(closing.last_day_to_close(10, {8: TELLER, 9: LOAN})).is_equal(11)
	# Long after the due day with no Loan Officer day recorded since, it still
	# has three days, from today.
	assert_int(closing.last_day_to_close(20, {})).is_equal(22)

func test_a_lapse_comes_at_opening_costs_the_withdrawal_penalty_and_happens_once() -> void:
	var closing := LoanRole.closings.open(approved("Once Test"), 6, SEED)
	note_roles(LOAN, [8, 9])
	GameClock.day = 11
	var score_before := score_and_reputation()
	var xp_before := XPManager.total_xp
	LoanRole.start_of_day()
	# At the start of day 11 only days 8 and 9 have passed since it was due.
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_vector(score_and_reputation()).is_equal(score_before)
	# By day 12, days 8, 9 and 10: three.
	note_roles(LOAN, [10])
	GameClock.day = 12
	LoanRole.start_of_day()
	assert_array(LoanRole.closings.closings).is_empty()
	assert_vector(score_and_reputation()).is_equal(score_before + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_int(XPManager.total_xp).is_equal(maxi(0, xp_before + LoanConfig.WITHDRAWN_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)
	assert_str(LoanRole.closings.log_lapsed[0]["name"]).is_equal("Once Test")
	assert_int(LoanRole.closings.log_day).is_equal(12)
	# Again the same day, and on later days: nothing more.
	var score_after := score_and_reputation()
	LoanRole.start_of_day()
	LoanRole.start_of_day()
	assert_vector(score_and_reputation()).is_equal(score_after)
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)
	assert_bool(closing.is_due(12)).is_true()

func test_a_closing_inside_its_days_is_not_touched() -> void:
	LoanRole.closings.open(approved("Fine Test"), 6, SEED)
	note_roles(LOAN, [8, 9])
	note_roles(TELLER, [10, 11])
	GameClock.day = 12
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_vector(score_and_reputation()).is_equal(score_before)
	assert_array(LoanRole.closings.log_lapsed).is_empty()

func test_a_lapse_never_adds_reputation_and_never_takes_it_to_zero() -> void:
	var zero_events: Array = []
	ReputationManager.reputation_reached_zero.connect(func() -> void: zero_events.append(true))
	var reports := ReportManager.reports.size()
	# At 0 and 1 it costs nothing, at 2 or more one point; the Score always costs.
	for reputation: int in [0, 1, 2, 3, 50]:
		CareerReset.reset_all()
		LoanRole.closings.open(approved("Floor Test"), 6, SEED)
		note_roles(LOAN, [8, 9, 10])
		ReputationManager.reputation = reputation
		var score := ScoreManager.total_score
		GameClock.day = 12
		LoanRole.start_of_day()
		var expected := reputation if reputation <= 1 else reputation - 1
		assert_int(ReputationManager.reputation).override_failure_message("from %d" % reputation).is_equal(expected)
		assert_int(ScoreManager.total_score - score).is_equal(LoanConfig.WITHDRAWN_SCORE)
		assert_int(LoanRole.closings.log_lapsed[0]["reputation"]).is_less_equal(0)
		assert_array(LoanRole.closings.closings).is_empty()
	assert_array(zero_events).is_empty()
	assert_int(ReportManager.reports.size()).is_equal(reports)

func test_a_lapsed_good_applicant_can_count_as_turned_away() -> void:
	assert_bool(LoanConfig.LAPSED_GOOD_APPLICANT_TURNED_AWAY).is_true()
	var good := approved("Good Test")
	good.credit_score = 800
	good.annual_income = 200000.0
	good.monthly_debt_payments = 0.0
	good.monthly_housing_payment = 800.0
	good.employment_months = 120
	good.documents_issued = true
	var risky := approved("Risky Test", "Auto", 30000.0)
	risky.credit_score = 520
	risky.monthly_debt_payments = 900.0
	risky.employment_months = 6
	var good_closing := LoanRole.closings.open(good, 6, SEED)
	var risky_closing := LoanRole.closings.open(risky, 6, SEED)
	assert_bool(good_closing.is_good_applicant()).is_true()
	assert_bool(risky_closing.is_good_applicant()).is_false()
	assert_bool(good_closing.counts_as_turned_away_if_lapsed()).is_true()
	assert_bool(risky_closing.counts_as_turned_away_if_lapsed()).is_false()
	note_roles(LOAN, [8, 9, 10])
	GameClock.day = 12
	LoanRole.start_of_day()
	var flags := {}
	for entry in LoanRole.closings.log_lapsed:
		flags[entry["name"]] = entry["turned_away"]
	assert_dict(flags).is_equal({"Good Test": true, "Risky Test": false})

func test_the_lapse_does_not_run_for_a_branch_manager_whose_closing_goes_to_the_staff() -> void:
	LoanRole.closings.open(approved("Boss Test"), 6, SEED)
	note_roles(LOAN, [8, 9, 10])
	XPManager.is_branch_manager_unlocked = true
	GameClock.day = 12
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	# No penalty: a closing left over is passed to the staff (part 2), never lapsed.
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_array(LoanRole.closings.log_lapsed).is_empty()
	assert_vector(score_and_reputation()).is_equal(score_before)
	assert_dict(LoanRole.role_days).is_empty()

# --- role days -----------------------------------------------------------------------

func test_a_closing_keeps_role_days_from_its_due_day_and_saves_them() -> void:
	# No files, no closings: nothing is kept.
	note_roles(LOAN, [3, 4])
	assert_dict(LoanRole.role_days).is_empty()
	assert_dict(LoanRole.save_data()).is_empty()
	var closing := LoanRole.closings.open(approved("Days Test"), 5, SEED)
	assert_int(closing.due_day).is_equal(6)
	GameClock.day = 9
	note_roles(LOAN, [4, 6, 7, 8])
	assert_bool(LoanRole.role_days.has(4)).is_false()
	assert_bool(LoanRole.role_days.has(6)).is_true()
	assert_bool(LoanRole.role_days.has(8)).is_true()
	var saved := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	assert_bool(saved.has(LoanRole.ROLES_KEY)).is_true()
	assert_bool(saved.has(LoanRole.CLOSINGS_KEY)).is_true()
	# Loaded back, the role days and the closing come with it.
	LoanRole.reset()
	assert_dict(LoanRole.role_days).is_empty()
	LoanRole.load_data(saved)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_int(LoanRole.role_days[7]).is_equal(LOAN)
	# Once the closing is gone, so are the role days.
	LoanRole.closings.close(LoanRole.closings.closings[0])
	note_roles(LOAN, [9])
	assert_dict(LoanRole.role_days).is_empty()

func test_a_file_and_a_closing_each_keep_the_role_days_they_need() -> void:
	GameClock.day = 9
	LoanRole.closings.open(approved("Closing Test"), 3, SEED)
	var file_application := LoanDeskManager.generate_application()
	LoanRole.request_documents(file_application, [LoanRequirements.Item.PAY_STUB] as Array[int])
	note_roles(LOAN, [3, 4, 5, 8, 9])
	# The closing is due on day 4, the file's request is from day 9.
	assert_bool(LoanRole.role_days.has(3)).is_false()
	assert_bool(LoanRole.role_days.has(4)).is_true()
	assert_bool(LoanRole.role_days.has(8)).is_true()

# --- promotion and demotion -----------------------------------------------------------

func test_the_promotion_plan_stops_problem_closings_and_funds_clean_ones_and_applies_nothing() -> void:
	var clean := LoanRole.closings.open(approved("Clean Test"), 5, SEED)
	var bad_application := approved("Bad Test")
	var bad := LoanClosing.create(bad_application, 5, 200, SEED)
	for number in range(2, 4000):
		bad = LoanClosing.create(bad_application, 5, number, SEED)
		if bad.has_problem():
			break
	assert_bool(bad.has_problem()).is_true()
	LoanRole.closings.closings.append(bad)
	var plan := LoanRole.closings.promotion_plan()
	assert_int(plan.size()).is_equal(2)
	assert_object(plan[0]["closing"]).is_same(clean)
	assert_int(plan[0]["action"]).is_equal(LoanClosings.StaffAction.FUND)
	assert_object(plan[1]["closing"]).is_same(bad)
	assert_int(plan[1]["action"]).is_equal(LoanClosings.StaffAction.STOP)
	# Nothing was applied: no booking, no penalty, nothing removed.
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_int(LoanRole.closings.count()).is_equal(2)
	# Planning twice gives the same plan (applying it is part 2:
	# loan_closing_booking_test.gd).
	assert_int(LoanRole.closings.promotion_plan().size()).is_equal(2)
	assert_array(LoanClosings.new().promotion_plan()).is_empty()

func test_a_demotion_starts_clean_with_no_old_closings_or_role_days() -> void:
	LoanRole.closings.open(approved("Old Test"), 5, SEED)
	LoanRole.closings.open(approved("Older Test"), 5, SEED)
	note_roles(LOAN, [6, 7])
	LoanRole.closings.log_day = 7
	LoanRole.closings.log_lapsed.append({"name": "Gone Test"})
	LoanRole._on_demoted()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_dict(LoanRole.role_days).is_empty()
	assert_array(LoanRole.closings.log_lapsed).is_empty()
	# The numbers keep counting, so an old closing's roll is never reused.
	assert_int(LoanRole.closings.next_number).is_equal(3)
	assert_int(LoanRole.closings.open(approved("New Test"), 9, SEED).number).is_equal(3)

func test_names_of_open_closings_are_taken() -> void:
	LoanRole.closings.open(approved("Named Closing"), 5, SEED)
	assert_bool(LoanDeskManager.names_taken().has("Named Closing")).is_true()
	assert_array(LoanRole.closings.names()).is_equal(["Named Closing"])
	LoanRole.closings.close(LoanRole.closings.closings[0])
	assert_bool(LoanDeskManager.names_taken().has("Named Closing")).is_false()

# --- saves ---------------------------------------------------------------------------------

func test_a_career_that_never_closes_saves_no_closings() -> void:
	# (loan_edge_test's comparison with tests/data/loan/loan_sections_on_main.json
	# checks the whole of what main saved, byte for byte.)
	assert_dict(LoanRole.save_data()).is_empty()
	assert_bool(LoanRole.save_data().has(LoanRole.CLOSINGS_KEY)).is_false()
	var career := SaveGame.capture()
	var loan := SaveGame.dict_of(SaveGame.dict_of(career, "roles"), "loan")
	assert_bool(loan.has(LoanRole.CLOSINGS_KEY)).is_false()
	# Only once a closing has existed, even after it is gone.
	var closing := LoanRole.closings.open(approved(), 5, SEED)
	assert_bool(LoanRole.save_data().has(LoanRole.CLOSINGS_KEY)).is_true()
	LoanRole.closings.close(closing)
	assert_bool(LoanRole.save_data().has(LoanRole.CLOSINGS_KEY)).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(LoanRole.save_data(), LoanRole.CLOSINGS_KEY), "next_number", 0)).is_equal(2)
	# A reset career is back to saving nothing.
	CareerReset.reset_all()
	assert_dict(LoanRole.save_data()).is_empty()

func test_closings_survive_a_save_and_a_load() -> void:
	var made: Array[LoanClosing] = []
	for number in 40:
		var application := approved("Saved %d" % number, PURPOSES[number % 4], 72000.0, number % 5 == 0)
		made.append(LoanRole.closings.open(application, 5 + number % 3, SEED, 100 + number))
	var problems := 0
	for closing in made:
		if closing.has_problem():
			problems += 1
	assert_int(problems).is_greater(0)
	LoanRole.closings.log_day = 9
	LoanRole.closings.log_lapsed.append({"name": "Lapsed Test", "amount": 12000.0, "score": -2, "reputation": -1, "turned_away": true})
	note_roles(LOAN, [7, 8])
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	assert_int(LoanRole.closings.count()).is_equal(0)
	SaveGame.restore(career)
	assert_int(LoanRole.closings.count()).is_equal(made.size())
	assert_int(LoanRole.closings.next_number).is_equal(41)
	for i in made.size():
		var loaded := LoanRole.closings.closings[i]
		var found := differences(loaded, made[i])
		assert_bool(found.is_empty()).override_failure_message("closing %d: %s" % [i, ", ".join(found)]).is_true()
		assert_str(loaded.application.applicant_name).is_equal(made[i].application.applicant_name)
		assert_int(loaded.application.decision).is_equal(made[i].application.decision)
		assert_float(loaded.application.decision_amount).is_equal(made[i].application.decision_amount)
		assert_int(loaded.loan_id).is_equal(100 + i)
	assert_int(LoanRole.closings.log_day).is_equal(9)
	assert_dict(LoanRole.closings.log_lapsed[0]).is_equal({"name": "Lapsed Test", "amount": 12000.0, "score": -2, "reputation": -1, "turned_away": true})
	assert_int(LoanRole.role_days[8]).is_equal(LOAN)
	# A loaded closing keeps its time rules and its problem, and saves the same.
	assert_dict(SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")).is_equal(SaveGame.dict_of(SaveGame.dict_of(career, "roles"), "loan"))

func test_every_old_save_loads_with_no_closings() -> void:
	var loaded := 0
	for file_name in DirAccess.get_files_at(OLD_SAVES):
		if not file_name.ends_with(".json"):
			continue
		var saved := SaveGame.read_file(OLD_SAVES + file_name)
		assert_int(saved.status).override_failure_message(file_name).is_equal(SaveGame.Status.OK)
		# Something left over from another career must not survive the load.
		LoanRole.closings.open(approved(), 5, SEED)
		SaveGame.restore(saved.career)
		assert_int(LoanRole.closings.count()).override_failure_message(file_name).is_equal(0)
		assert_int(LoanRole.closings.next_number).override_failure_message(file_name).is_equal(1)
		assert_array(LoanRole.closings.log_lapsed).is_empty()
		assert_dict(LoanRole.save_data()).override_failure_message(file_name).is_empty()
		loaded += 1
	assert_int(loaded).is_greater_equal(5)

func test_unreadable_closings_data_loads_as_far_as_it_can() -> void:
	LoanRole.load_data({LoanRole.CLOSINGS_KEY: {"next_number": 4, "closings": [{"number": 2}, "junk", {"application": {}}]}})
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanRole.closings.next_number).is_equal(4)
	LoanRole.load_data({LoanRole.CLOSINGS_KEY: "junk"})
	assert_bool(LoanRole.closings.has_data()).is_false()

# --- through the room: going home early and a reload ------------------------------------

## A closing already past its due day whose Loan Officer days are used up
## after today: it lapses at the next Opening.
func overdue_after_today() -> LoanClosing:
	var closing := LoanRole.closings.open(approved("Home Early Test"), GameClock.day, SEED)
	# Due three days score_before today, with the two days since it Loan Officer days.
	closing.due_day = GameClock.day - 3
	LoanRole.role_days[GameClock.day - 2] = LOAN
	LoanRole.role_days[GameClock.day - 1] = LOAN
	return closing

func test_going_home_early_still_counts_the_day_and_the_closing_lapses_once_next_morning() -> void:
	GameClock.day = 4
	BusinessDay.stats_day = 4
	loan_day_at_9am()
	var closing := overdue_after_today()
	assert_int(closing.due_day).is_equal(1)
	# Day 4 is worked as a Loan Officer, but the player goes home early.
	go_home_from_the_loan_desk()
	assert_int(LoanRole.role_days[4]).is_equal(LOAN)
	assert_int(LoanRole.closings.count()).is_equal(1)
	await run_end_of_day()
	assert_int(LoanRole.closings.count()).is_equal(1)
	var score_before := score_and_reputation()
	var eod := room.end_of_day_screen
	eod.next_day_button.pressed.emit()
	if eod.is_closure_shown():
		eod.next_day_button.pressed.emit()
	assert_int(GameClock.day).is_equal(5)
	# Opening of day 5: days 2, 3 and 4 were Loan Officer days.
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(score_before + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)
	# And never again.
	LoanRole.start_of_day()
	assert_vector(score_and_reputation()).is_equal(score_before + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))

func test_a_reload_neither_loses_nor_repeats_a_lapse() -> void:
	GameClock.day = 4
	BusinessDay.stats_day = 4
	loan_day_at_9am()
	overdue_after_today()
	go_home_from_the_loan_desk()
	await run_end_of_day()
	var saved := SaveGame.read_file(TEST_SAVE_PATH)
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	var loan := SaveGame.dict_of(SaveGame.dict_of(saved.career, "roles"), "loan")
	assert_bool(loan.has(LoanRole.CLOSINGS_KEY)).is_true()
	assert_bool(loan.has(LoanRole.ROLES_KEY)).is_true()
	# Loading the End of Day save brings the closing and its role days back.
	CareerReset.reset_all()
	SaveGame.restore(saved.career)
	assert_int(LoanRole.closings.count()).is_equal(1)
	assert_int(LoanRole.role_days[4]).is_equal(LOAN)
	# The next morning it lapses once, and a second start of the same day (or a
	# reload of what was saved after it) charges nothing more.
	GameClock.day = 5
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	var score_after := score_before + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION)
	assert_vector(score_and_reputation()).is_equal(score_after)
	LoanRole.start_of_day()
	var lapsed_save := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	LoanRole.load_data(lapsed_save)
	LoanRole.start_of_day()
	assert_vector(score_and_reputation()).is_equal(score_after)
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)

# --- quiet expiry of an abandoned closing --------------------------------------------

func test_a_closing_is_abandoned_fifteen_business_days_after_its_due_day() -> void:
	assert_int(LoanConfig.ABANDONED_AFTER_DAYS).is_equal(15)
	var closing := make(approved("Old Closing"), 2, 6)
	assert_int(closing.due_day).is_equal(7)
	assert_bool(closing.is_abandoned(3)).is_false()
	assert_bool(closing.is_abandoned(7)).is_false()
	assert_bool(closing.is_abandoned(21)).is_false()
	assert_bool(closing.is_abandoned(22)).is_true()
	assert_bool(closing.is_abandoned(40)).is_true()

func test_a_closing_left_open_is_closed_quietly_whatever_the_players_role() -> void:
	LoanRole.closings.open(approved("Parked Closing", "Business"), 6, SEED)
	assert_bool(LoanDeskManager.names_taken().has("Parked Closing")).is_true()
	# A Teller (or any other) player: no Loan Officer day was ever recorded.
	note_roles(TELLER, [9, 10, 11, 12])
	var score_before := score_and_reputation()
	var xp_before := XPManager.total_xp
	GameClock.day = 8 + LoanConfig.ABANDONED_AFTER_DAYS - 1
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(1)
	GameClock.day = 8 + LoanConfig.ABANDONED_AFTER_DAYS
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(score_before)
	assert_int(XPManager.total_xp).is_equal(xp_before)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Parked Closing"])
	assert_array(LoanRole.closings.log_lapsed).is_empty()
	assert_int(LoanBookManager.book.size()).is_equal(0)
	assert_float(LoanBookManager.stat(SaveGame.dict_of(LoanBookManager.period_stats, LoanBookManager.PLAYER), "turned_away")).is_equal(0.0)
	# Its name is free again, and a second start of the day changes nothing.
	assert_bool(LoanDeskManager.names_taken().has("Parked Closing")).is_false()
	LoanRole.start_of_day()
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Parked Closing"])
	assert_vector(score_and_reputation()).is_equal(score_before)

func test_the_loan_officer_day_lapse_and_its_penalty_come_before_the_quiet_expiry() -> void:
	LoanRole.closings.open(approved("Used Days"), 6, SEED)
	LoanRole.closings.open(approved("Teller Days"), 6, SEED)
	# The second is due much later: no Loan Officer day has passed since it was.
	LoanRole.closings.closings[1].due_day = 20
	note_roles(LOAN, [8, 9, 10])
	GameClock.day = 36
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	assert_array(LoanRole.closings.closings).is_empty()
	# The first used its three Loan Officer days (due on 7, so past fifteen days as
	# well): the penalty, once, and it is not also listed as abandoned. The second
	# (due on 20, 16 days ago, no Loan Officer day since) went quietly.
	assert_vector(score_and_reputation()).is_equal(score_before + Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_int(LoanRole.closings.log_lapsed.size()).is_equal(1)
	assert_str(LoanRole.closings.log_lapsed[0]["name"]).is_equal("Used Days")
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Teller Days"])

func test_the_abandoned_log_survives_a_save_and_a_load() -> void:
	LoanRole.closings.open(approved("Saved Quiet"), 6, SEED)
	GameClock.day = 30
	LoanRole.start_of_day()
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Saved Quiet"])
	var saved := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	LoanRole.reset()
	LoanRole.load_data(saved)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Saved Quiet"])
	assert_int(LoanRole.closings.log_day).is_equal(30)
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	assert_vector(score_and_reputation()).is_equal(score_before)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Saved Quiet"])

## A closing past its due day by `days` business days at tomorrow's Opening.
func abandoned_by_tomorrow(days: int) -> LoanClosing:
	var closing := LoanRole.closings.open(approved("Home Early Quiet"), GameClock.day, SEED)
	closing.due_day = GameClock.day + 1 - days
	return closing

func test_going_home_early_still_expires_an_abandoned_closing_quietly_next_morning() -> void:
	GameClock.day = 4
	BusinessDay.stats_day = 4
	loan_day_at_9am()
	abandoned_by_tomorrow(LoanConfig.ABANDONED_AFTER_DAYS)
	go_home_from_the_loan_desk()
	assert_int(LoanRole.closings.count()).is_equal(1)
	await run_end_of_day()
	assert_int(LoanRole.closings.count()).is_equal(1)
	var score_before := score_and_reputation()
	var eod := room.end_of_day_screen
	eod.next_day_button.pressed.emit()
	if eod.is_closure_shown():
		eod.next_day_button.pressed.emit()
	assert_int(GameClock.day).is_equal(5)
	# Only day 4 was a Loan Officer day: no lapse, just the quiet expiry.
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_vector(score_and_reputation()).is_equal(score_before)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Home Early Quiet"])
	assert_array(LoanRole.closings.log_lapsed).is_empty()
	assert_bool(LoanDeskManager.names_taken().has("Home Early Quiet")).is_false()

func test_a_reload_neither_loses_nor_repeats_a_quiet_expiry() -> void:
	GameClock.day = 4
	BusinessDay.stats_day = 4
	loan_day_at_9am()
	abandoned_by_tomorrow(LoanConfig.ABANDONED_AFTER_DAYS)
	go_home_from_the_loan_desk()
	await run_end_of_day()
	var saved := SaveGame.read_file(TEST_SAVE_PATH)
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	CareerReset.reset_all()
	SaveGame.restore(saved.career)
	assert_int(LoanRole.closings.count()).is_equal(1)
	GameClock.day = 5
	var score_before := score_and_reputation()
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Home Early Quiet"])
	# Reloading what was saved after it, or starting the day again, changes nothing.
	var after_save := SaveGame.dict_of(through_json({"x": LoanRole.save_data()}), "x")
	LoanRole.load_data(after_save)
	LoanRole.start_of_day()
	assert_int(LoanRole.closings.count()).is_equal(0)
	assert_array(LoanRole.closings.log_abandoned).is_equal(["Home Early Quiet"])
	assert_vector(score_and_reputation()).is_equal(score_before)
