extends GdUnitTestSuite

## The underwriting worksheet's maths (LoanApplication): the amortization
## formula, front-end and total DTI, the recalibrated risk tiers, the
## affordable amount, counter-offer grading and denial-reason grading.

const Tier := LoanApplication.RiskTier
const Grade := LoanApplication.Grade
const Reason := LoanApplication.DenialReason

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			application.risk_assessment = application.calculate_risk_assessment()
			return application
	return null

func applicant(purpose: String, amount: float, credit: int, income: float, housing: float, debts: float, months: int) -> LoanApplication:
	var application := LoanApplication.new()
	application.loan_purpose = purpose
	application.requested_amount = amount
	application.credit_score = credit
	application.annual_income = income
	application.monthly_housing_payment = housing
	application.monthly_debt_payments = debts
	application.employment_months = months
	application.risk_assessment = application.calculate_risk_assessment()
	return application

# --- the payment formula -------------------------------------------------------------

func test_the_amortization_formula() -> void:
	# payment = P × r / (1 − (1 + r)^−n), r = rate / 12.
	assert_float(LoanApplication.monthly_payment(10000.0, 0.12, 36)).is_equal_approx(332.14, 0.005)
	assert_float(LoanApplication.monthly_payment(15000.0, 0.07, 60)).is_equal_approx(297.02, 0.005)
	assert_float(LoanApplication.monthly_payment(400000.0, 0.065, 360)).is_equal_approx(2528.27, 0.005)
	assert_float(LoanApplication.monthly_payment(500000.0, 0.09, 120)).is_equal_approx(6333.79, 0.005)
	# No interest: the principal split evenly; nothing borrowed: nothing due.
	assert_float(LoanApplication.monthly_payment(1200.0, 0.0, 12)).is_equal_approx(100.0, 0.0001)
	assert_float(LoanApplication.monthly_payment(0.0, 0.07, 60)).is_equal(0.0)
	# The inverse gives the principal back.
	var payment := LoanApplication.monthly_payment(30000.0, 0.07, 60)
	assert_float(LoanApplication.principal_for_payment(payment, 0.07, 60)).is_equal_approx(30000.0, 0.01)

func test_each_purpose_has_its_term_rate_and_maximum() -> void:
	var expected := {
		"Auto": [60, 0.07, 75000.0],
		"Home": [360, 0.065, 800000.0],
		"Personal": [36, 0.12, 50000.0],
		"Business": [120, 0.09, 250000.0],
	}
	for purpose: String in expected:
		var application := applicant(purpose, 10000.0, 750, 60000.0, 1000.0, 0.0, 60)
		var terms: Array = expected[purpose]
		assert_int(application.term_months()).is_equal(terms[0])
		assert_float(application.annual_rate()).is_equal(terms[1])
		assert_float(application.policy_maximum()).is_equal(terms[2])
	# Every sample uses one of them.
	for application in LoanApplicationsData.get_applications():
		assert_bool(LoanApplication.PURPOSE_TERMS.has(application.loan_purpose)).is_true()

# --- front-end and total DTI ------------------------------------------------------------

func test_front_end_and_total_dti() -> void:
	# Angela Reyes: $4,000 a month, $950 rent, $250 debts, $594.04 new car.
	var angela := sample("Angela Reyes")
	assert_float(angela.monthly_income()).is_equal(4000.0)
	assert_float(angela.new_loan_payment()).is_equal_approx(594.04, 0.005)
	assert_float(angela.front_end_dti()).is_equal_approx(950.0 / 4000.0, 0.000001)
	assert_float(angela.total_dti()).is_equal_approx((950.0 + 250.0 + angela.new_loan_payment()) / 4000.0, 0.000001)
	assert_float(angela.dti_before_loan()).is_equal_approx(0.30, 0.000001)

	# A home loan's mortgage replaces the rent: it's the housing payment, and
	# the rent isn't counted as well.
	var david := sample("David Okafor")
	var mortgage := david.new_loan_payment()
	assert_float(mortgage).is_equal_approx(2528.27, 0.005)
	assert_float(david.housing_payment_after_loan()).is_equal(mortgage)
	assert_float(david.front_end_dti()).is_equal_approx(mortgage / 15000.0, 0.000001)
	assert_float(david.total_dti()).is_equal_approx((mortgage + 1000.0) / 15000.0, 0.000001)

# --- the recalibrated tiers ---------------------------------------------------------------

func test_every_sample_lands_on_its_intended_tier() -> void:
	var expected := {
		"Maria Chen": Tier.LOW, "David Okafor": Tier.LOW, "Elena Petrova": Tier.LOW,
		"Priya Sharma": Tier.MEDIUM, "Angela Reyes": Tier.MEDIUM, "Jamal Green": Tier.MEDIUM, "Noah Kim": Tier.MEDIUM,
		"Tom Whitfield": Tier.HIGH, "Marcus Webb": Tier.HIGH, "Sophie Laurent": Tier.HIGH,
	}
	var applications := LoanApplicationsData.get_applications()
	assert_int(applications.size()).is_equal(expected.size())
	for application in applications:
		var tier := application.calculate_risk_assessment()
		assert_int(tier).override_failure_message("%s: %s" % [application.applicant_name, tier]).is_equal(expected[application.applicant_name])
		assert_int(tier).is_equal(application.risk_tier)

func test_the_risk_points_follow_the_guide_bands() -> void:
	# Clean: excellent credit, 25% total DTI, five years.
	var base := applicant("Auto", 0.0, 800, 120000.0, 2500.0, 0.0, 60)
	assert_float(base.total_dti()).is_equal_approx(0.25, 0.000001)
	assert_int(base.risk_points()).is_equal(0)
	# Credit: 740+ 0 · 670-739 1 · 580-669 3 · under 580 5.
	for case: Array in [[740, 0], [739, 1], [670, 1], [669, 3], [580, 3], [579, 5]]:
		base.credit_score = case[0]
		assert_int(base.risk_points()).override_failure_message("credit %d" % case[0]).is_equal(case[1])
	base.credit_score = 800
	# Total DTI: up to 36% 0 · up to 43% 1 · up to 50% 3 · over 50% 5.
	for case: Array in [[0.36, 0], [0.37, 1], [0.43, 1], [0.44, 3], [0.50, 3], [0.51, 5]]:
		var share: float = case[0]
		base.monthly_housing_payment = share * 10000.0
		assert_int(base.risk_points()).override_failure_message("DTI %.2f" % share).is_equal(case[1])
	base.monthly_housing_payment = 2500.0
	# Employment: under two years 2.
	base.employment_months = 23
	assert_int(base.risk_points()).is_equal(2)
	# 0-2 LOW, 3-4 MEDIUM, 5+ HIGH.
	assert_int(base.calculate_risk_assessment()).is_equal(Tier.LOW)
	base.credit_score = 700
	assert_int(base.calculate_risk_assessment()).is_equal(Tier.MEDIUM)
	base.credit_score = 650
	assert_int(base.calculate_risk_assessment()).is_equal(Tier.HIGH)

# --- the affordable amount ------------------------------------------------------------------

func test_the_affordable_amount() -> void:
	# Angela: 36% of $4,000 is $1,440; less $950 rent and $250 debts leaves
	# $240 a month, which repays $12,120 over 60 months at 7%: $12,100.
	var angela := sample("Angela Reyes")
	assert_float(angela.affordable_amount()).is_equal(12100.0)
	assert_float(angela.total_dti(angela.affordable_amount())).is_less_equal(LoanApplication.HEALTHY_DTI)
	assert_float(angela.total_dti(angela.affordable_amount() + 100.0)).is_greater(LoanApplication.HEALTHY_DTI)
	assert_float(sample("Priya Sharma").affordable_amount()).is_equal(4500.0)
	# A home loan's room isn't reduced by the rent it replaces.
	assert_float(sample("Elena Petrova").affordable_amount()).is_equal(300600.0)
	# Today's payments already over 36%: nothing.
	assert_float(sample("Marcus Webb").affordable_amount()).is_equal(0.0)
	assert_float(sample("Tom Whitfield").affordable_amount()).is_equal(0.0)
	# Never more than the policy maximum.
	var wealthy := applicant("Auto", 50000.0, 800, 600000.0, 3000.0, 0.0, 120)
	assert_float(wealthy.affordable_amount()).is_equal(75000.0)
	# The counter-offer reference is the smaller of it and the request.
	assert_float(sample("Noah Kim").affordable_amount()).is_equal(12000.0)
	assert_float(sample("Noah Kim").counter_offer_reference()).is_equal(10000.0)

# --- counter-offers ----------------------------------------------------------------------

func test_counter_offer_grading() -> void:
	# MEDIUM: affordable and reasonable is the right call.
	var angela := sample("Angela Reyes")
	assert_int(angela.grade_counter_offer(12100.0)).is_equal(Grade.BEST)
	assert_int(angela.grade_counter_offer(6100.0)).is_equal(Grade.BEST)
	# More than they can carry, or a lowball under half the reference.
	assert_int(angela.grade_counter_offer(12200.0)).is_equal(Grade.PARTIAL)
	assert_int(angela.grade_counter_offer(6000.0)).is_equal(Grade.PARTIAL)
	assert_str(angela.counter_offer_note(12200.0)).is_equal("More than they can carry at a healthy total DTI.")
	assert_str(angela.counter_offer_note(6000.0)).is_equal("Affordable, but far below what they could carry.")
	assert_str(angela.counter_offer_note(12000.0)).is_equal("Affordable at a healthy total DTI.")
	# A MEDIUM who could afford the request: the offer must still be below it.
	var noah := sample("Noah Kim")
	assert_int(noah.grade_counter_offer(9000.0)).is_equal(Grade.BEST)
	assert_int(noah.grade_counter_offer(10000.0)).is_equal(Grade.PARTIAL)
	assert_str(noah.counter_offer_note(10000.0)).is_equal("Not below what they asked for.")
	# LOW: they qualified for the full amount.
	var maria := sample("Maria Chen")
	assert_int(maria.grade_counter_offer(12000.0)).is_equal(Grade.PARTIAL)
	# HIGH: affordable is reasonable; more than they can carry is a risky loan.
	var sophie := sample("Sophie Laurent")
	assert_float(sophie.affordable_amount()).is_equal(10100.0)
	assert_int(sophie.grade_counter_offer(8000.0)).is_equal(Grade.PARTIAL)
	assert_int(sophie.grade_counter_offer(15000.0)).is_equal(Grade.WORST)
	# grade_decision() reads the amount for a counter-offer.
	angela.decision = LoanApplication.DecisionType.COUNTER_OFFER
	angela.decision_amount = 15000.0
	assert_int(angela.grade_decision()).is_equal(Grade.PARTIAL)
	angela.decision_amount = 10000.0
	assert_int(angela.grade_decision()).is_equal(Grade.BEST)

# --- denial reasons ------------------------------------------------------------------------

func test_each_samples_weak_points() -> void:
	var expected := {
		"Maria Chen": [], "David Okafor": [], "Elena Petrova": [],
		"Priya Sharma": [Reason.CREDIT_SCORE],
		# The new car pushes total DTI past 43%: DTI and income both.
		"Angela Reyes": [Reason.TOTAL_DTI, Reason.INCOME],
		"Jamal Green": [Reason.CREDIT_SCORE],
		"Noah Kim": [Reason.EMPLOYMENT],
		"Tom Whitfield": [Reason.TOTAL_DTI, Reason.CREDIT_SCORE, Reason.INCOME, Reason.AMOUNT],
		# Today's payments are the problem, not the new loan's size.
		"Marcus Webb": [Reason.TOTAL_DTI, Reason.CREDIT_SCORE],
		"Sophie Laurent": [Reason.CREDIT_SCORE],
	}
	for application in LoanApplicationsData.get_applications():
		var weak: Array = expected[application.applicant_name]
		assert_array(application.weak_points()).override_failure_message(application.applicant_name).is_equal(reasons(weak))

func reasons(list: Array) -> Array[LoanApplication.DenialReason]:
	var typed: Array[LoanApplication.DenialReason] = []
	for reason: int in list:
		typed.append(reason as LoanApplication.DenialReason)
	return typed

func test_denial_reason_grading() -> void:
	var right := LoanApplication.REASON_RIGHT_SCORE
	var wrong := LoanApplication.REASON_WRONG_SCORE
	var missing := LoanApplication.REASON_MISSING_SCORE
	var marcus := sample("Marcus Webb")
	# Both real weak points named.
	assert_dict(marcus.grade_denial_reasons(reasons([Reason.TOTAL_DTI, Reason.CREDIT_SCORE]))).is_equal({"right": 2, "wrong": 0, "missing": 0, "score": 2 * right})
	# One right, one left out.
	assert_dict(marcus.grade_denial_reasons(reasons([Reason.CREDIT_SCORE]))).is_equal({"right": 1, "wrong": 0, "missing": 1, "score": right + missing})
	# One right, one wrong (and so one missing).
	assert_dict(marcus.grade_denial_reasons(reasons([Reason.TOTAL_DTI, Reason.EMPLOYMENT]))).is_equal({"right": 1, "wrong": 1, "missing": 1, "score": right + wrong + missing})
	# A single weak point: one right reason is all there is to name.
	var sophie := sample("Sophie Laurent")
	assert_int(sophie.grade_denial_reasons(reasons([Reason.CREDIT_SCORE]))["score"]).is_equal(right)
	assert_int(sophie.grade_denial_reasons(reasons([Reason.CREDIT_SCORE, Reason.TOTAL_DTI]))["score"]).is_equal(right + wrong)
	assert_int(sophie.grade_denial_reasons(reasons([Reason.EMPLOYMENT]))["score"]).is_equal(wrong + missing)
	# More weak points than reasons allowed: any two of them is full marks.
	var tom := sample("Tom Whitfield")
	assert_int(tom.grade_denial_reasons(reasons([Reason.AMOUNT, Reason.INCOME]))["score"]).is_equal(2 * right)
	# No weak point: every stated reason is wrong.
	var maria := sample("Maria Chen")
	assert_dict(maria.grade_denial_reasons(reasons([Reason.AMOUNT]))).is_equal({"right": 0, "wrong": 1, "missing": 0, "score": wrong})

func test_text_helpers() -> void:
	assert_str(LoanApplication.employment_text(96)).is_equal("8 years")
	assert_str(LoanApplication.employment_text(16)).is_equal("1 year 4 months")
	assert_str(LoanApplication.employment_text(10)).is_equal("10 months")
	assert_str(LoanApplication.employment_text(0)).is_equal("0 months")
	assert_str(LoanApplication.dollars(300600.0)).is_equal("$300,600")
	assert_str(LoanApplication.dollars(594.04)).is_equal("$594")
	assert_str(LoanApplication.percent(0.4485)).is_equal("44.9%")
