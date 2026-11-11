extends GdUnitTestSuite

## Collateral, down payments and loan-to-value (LoanApplication,
## LoanApplicantGenerator.issue_collateral(), LoanBookManager.loss_share()):
## the LTV and down payment maths; an appraisal under the price uses the
## lower value; mortgage insurance in the payment, DTI and affordable amount;
## the tier mix and how often the LTV changes the tier; the counter-offer's
## down payment line; the "Down payment too small for the value" reason; loss
## on default scaling with LTV; fair lending; and saving the new fields.

const Tier := LoanApplication.RiskTier
const Reason := LoanApplication.DenialReason
const Collateral := LoanApplication.Collateral

const SAMPLE_SIZE: int = 2000
const SEED: int = 20261118

func finance_rng(seed_value: int, number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "finance", number])
	return rng

func generated(count: int, seed_value: int = SEED) -> Array[LoanApplication]:
	var list: Array[LoanApplication] = []
	for i in count:
		list.append(LoanApplicantGenerator.generate(finance_rng(seed_value, i)))
	return list

## Very good credit, $10,000 a month, $2,000 rent, five years in the job.
func applicant(purpose: String, amount: float) -> LoanApplication:
	var application := LoanApplication.new()
	application.loan_purpose = purpose
	application.requested_amount = amount
	application.credit_score = 760
	application.annual_income = 120000.0
	application.monthly_housing_payment = 2000.0
	application.employment_months = 60
	return application

func secured(application: LoanApplication, kind: LoanApplication.Collateral, price: float, value: float) -> LoanApplication:
	application.collateral_issued = true
	application.collateral_kind = kind
	application.purchase_price = price
	application.collateral_value = value
	return application

func home(amount: float, price: float, appraisal: float) -> LoanApplication:
	return secured(applicant("Home", amount), Collateral.HOUSE, price, appraisal)

func car(amount: float, price: float) -> LoanApplication:
	return secured(applicant("Auto", amount), Collateral.VEHICLE, price, price)

# --- the maths ---------------------------------------------------------------------

func test_ltv_and_down_payment() -> void:
	# A $300,000 loan on a $400,000 home appraised at $410,000: 75% LTV, $100,000
	# (25%) down.
	var house := home(300000.0, 400000.0, 410000.0)
	assert_bool(house.is_secured()).is_true()
	assert_float(house.value_for_ltv()).is_equal(400000.0)
	assert_float(house.loan_to_value()).is_equal_approx(0.75, 0.000001)
	assert_float(house.down_payment()).is_equal(100000.0)
	assert_float(house.down_payment_share()).is_equal_approx(0.25, 0.000001)
	assert_str(house.down_payment_text()).is_equal("$100,000 (25.0%)")
	# Another amount: a counter-offer's figures.
	assert_float(house.loan_to_value(320000.0)).is_equal_approx(0.80, 0.000001)
	assert_float(house.down_payment(240000.0)).is_equal(160000.0)

	# A car: its price is its value. A loan over the price (taxes, fees or an
	# old loan rolled in) has no down payment.
	var vehicle := car(27000.0, 30000.0)
	assert_float(vehicle.loan_to_value()).is_equal_approx(0.90, 0.000001)
	assert_str(vehicle.down_payment_text()).is_equal("$3,000 (10.0%)")
	vehicle.requested_amount = 33000.0
	assert_float(vehicle.loan_to_value()).is_equal_approx(1.10, 0.000001)
	assert_str(vehicle.down_payment_text()).is_equal("None ($3,000 over the vehicle's price)")

	# Business equipment: an LTV, no down payment.
	var equipment := secured(applicant("Business", 60000.0), Collateral.EQUIPMENT, 0.0, 80000.0)
	assert_float(equipment.loan_to_value()).is_equal_approx(0.75, 0.000001)
	assert_bool(equipment.has_down_payment()).is_false()

	# Unsecured (a personal loan, a business loan with nothing pledged, or no
	# collateral issued): no LTV and no LTV points.
	for none: LoanApplication in [
		secured(applicant("Personal", 9000.0), Collateral.NONE, 0.0, 0.0),
		secured(applicant("Business", 90000.0), Collateral.NONE, 0.0, 0.0),
		applicant("Home", 300000.0),
	]:
		assert_bool(none.is_secured()).is_false()
		assert_float(none.loan_to_value()).is_equal(0.0)
		assert_int(none.ltv_points()).is_equal(0)
		assert_float(none.mortgage_insurance()).is_equal(0.0)

## An appraisal under the purchase price: the LTV is on the appraisal, though
## the down payment (price minus the loan) looks bigger.
func test_an_appraisal_gap_uses_the_lower_value() -> void:
	var gap := home(352000.0, 400000.0, 370000.0)
	assert_bool(gap.has_appraisal_gap()).is_true()
	assert_float(gap.value_for_ltv()).is_equal(370000.0)
	assert_float(gap.loan_to_value()).is_equal_approx(352000.0 / 370000.0, 0.000001)
	# 12% down on the price, but 95.1% LTV: the high band.
	assert_str(gap.down_payment_text()).is_equal("$48,000 (12.0%)")
	assert_int(gap.ltv_points()).is_equal(LoanApplication.LTV_HIGH_POINTS)
	assert_bool(gap.weak_points().has(Reason.DOWN_PAYMENT)).is_true()
	# Had it appraised at the price: 88% LTV, stretched.
	var no_gap := home(352000.0, 400000.0, 400000.0)
	assert_bool(no_gap.has_appraisal_gap()).is_false()
	assert_int(no_gap.ltv_points()).is_equal(LoanApplication.LTV_STRETCHED_POINTS)
	# An appraisal over the price doesn't raise what the bank lends against.
	assert_float(home(352000.0, 400000.0, 450000.0).value_for_ltv()).is_equal(400000.0)

## About 1 in 8 generated home loans come with an appraisal under the price.
func test_about_one_home_in_eight_appraises_under_the_price() -> void:
	var homes := 0
	var gaps := 0
	for application in generated(SAMPLE_SIZE):
		if application.loan_purpose != LoanApplication.HOME_PURPOSE:
			continue
		homes += 1
		assert_float(application.collateral_value).is_greater(0.0)
		if application.has_appraisal_gap():
			gaps += 1
			assert_float(application.collateral_value / application.purchase_price).is_between(0.89, 0.975)
		else:
			assert_float(application.collateral_value / application.purchase_price).is_between(1.0, 1.051)
	print("Home appraisals under the price: %d of %d (%.1f%%)" % [gaps, homes, gaps * 100.0 / homes])
	assert_int(homes).is_greater(300)
	assert_float(gaps / float(homes)).is_between(0.08, 0.17)

func test_the_ltv_bands() -> void:
	var cases := [
		# [purpose, LTV, points]
		["Home", 0.80, 0], ["Home", 0.81, 1], ["Home", 0.95, 1], ["Home", 0.96, 3],
		["Auto", 1.00, 0], ["Auto", 1.01, 1], ["Auto", 1.20, 1], ["Auto", 1.21, 3],
		["Business", 0.75, 0], ["Business", 0.76, 1], ["Business", 1.00, 1], ["Business", 1.01, 3],
	]
	for case: Array in cases:
		var purpose: String = case[0]
		var ltv: float = case[1]
		var kind := Collateral.HOUSE if purpose == "Home" else Collateral.VEHICLE if purpose == "Auto" else Collateral.PROPERTY
		var application := secured(applicant(purpose, 100000.0 * ltv), kind, 100000.0 if kind != Collateral.PROPERTY else 0.0, 100000.0)
		assert_int(application.ltv_points()).override_failure_message("%s at %.2f" % [purpose, ltv]).is_equal(case[2])
	# In the assessment: a clean home buyer with 3% down is borderline.
	var three_percent := home(291000.0, 300000.0, 300000.0)
	three_percent.annual_income = 200000.0
	assert_int(three_percent.points_without_ltv()).is_equal(0)
	assert_int(three_percent.risk_points()).is_equal(3)
	assert_int(three_percent.assessment_without_ltv()).is_equal(Tier.LOW)
	assert_int(three_percent.calculate_risk_assessment()).is_equal(Tier.MEDIUM)

# --- mortgage insurance ------------------------------------------------------------

func test_mortgage_insurance() -> void:
	# Yearly rate by LTV: none to 80%, 0.30% to 85%, 0.50% to 90%, 0.75% to
	# 95%, 1.00% above.
	for case: Array in [[0.80, 0.0], [0.81, 0.003], [0.85, 0.003], [0.86, 0.005], [0.90, 0.005], [0.93, 0.0075], [0.95, 0.0075], [0.96, 0.01]]:
		var ltv: float = case[0]
		var rate: float = case[1]
		assert_float(LoanApplication.mortgage_insurance_rate(ltv)).override_failure_message("LTV %.2f" % ltv).is_equal_approx(rate, 0.0000001)
	# $270,000 on $300,000 (90%): 0.50% a year, $112.50 a month, in the
	# payment, the housing payment and the DTI.
	var house := home(270000.0, 300000.0, 305000.0)
	var principal_and_interest := LoanApplication.monthly_payment(270000.0, house.annual_rate(), 360)
	assert_float(house.mortgage_insurance()).is_equal_approx(112.5, 0.0001)
	assert_float(house.new_loan_payment()).is_equal_approx(principal_and_interest + 112.5, 0.0001)
	assert_float(house.housing_payment_after_loan()).is_equal_approx(principal_and_interest + 112.5, 0.0001)
	assert_float(house.front_end_dti()).is_equal_approx((principal_and_interest + 112.5) / 10000.0, 0.000001)
	# At 80% or less: none.
	assert_float(house.mortgage_insurance(240000.0)).is_equal(0.0)
	# Never on a car or business loan.
	assert_float(car(40000.0, 40000.0).mortgage_insurance()).is_equal(0.0)

## The affordable amount counts the insurance: the largest $100 step whose
## whole payment fits 36% of income, and a step more doesn't.
func test_the_affordable_amount_includes_mortgage_insurance() -> void:
	var house := home(400000.0, 420000.0, 420000.0)
	house.monthly_debt_payments = 600.0
	var room := LoanApplication.HEALTHY_DTI * house.monthly_income() - 600.0
	var affordable := house.affordable_amount()
	assert_float(fmod(affordable, 100.0)).is_equal(0.0)
	assert_float(house.new_loan_payment(affordable)).is_less_equal(room)
	assert_float(house.new_loan_payment(affordable + 100.0)).is_greater(room)
	# Less than ignoring the insurance would allow.
	var ignoring := floorf(LoanApplication.principal_for_payment(room, house.annual_rate(), 360) / 100.0) * 100.0
	assert_float(house.loan_to_value(ignoring)).is_greater(LoanApplication.MORTGAGE_INSURANCE_FROM_LTV)
	assert_float(affordable).is_less(ignoring)
	assert_float(LoanApplication.principal_for_total_payment(1000.0, 0.065, 360, 0.0)).is_equal_approx(LoanApplication.principal_for_payment(1000.0, 0.065, 360), 0.001)

# --- the tier mix and what the LTV changes -------------------------------------------

func test_the_tier_mix_and_how_often_the_ltv_changes_the_tier() -> void:
	var counts := {Tier.LOW: 0, Tier.MEDIUM: 0, Tier.HIGH: 0}
	var changed := 0
	var changes := {}
	var by_band := {}
	var insured := 0
	var homes := 0
	for application in generated(SAMPLE_SIZE):
		var tier := application.calculate_risk_assessment()
		counts[tier] += 1
		var without := application.assessment_without_ltv()
		assert_int(tier).is_greater_equal(without)
		if tier != without:
			changed += 1
			var key := "%s→%s" % [LoanApplication.risk_tier_label(without), LoanApplication.risk_tier_label(tier)]
			changes[key] = changes.get(key, 0) + 1
		var band := "%s %d" % [application.loan_purpose, application.ltv_points()] if application.is_secured() else "%s unsecured" % application.loan_purpose
		by_band[band] = by_band.get(band, 0) + 1
		if application.replaces_housing():
			homes += 1
			if application.mortgage_insurance() > 0.0:
				insured += 1
		# Personal loans are never secured; homes and cars always are.
		match application.loan_purpose:
			"Personal":
				assert_bool(application.is_secured()).is_false()
			"Home", "Auto":
				assert_bool(application.is_secured()).is_true()
	var n := float(SAMPLE_SIZE)
	var low: int = counts[Tier.LOW]
	var medium: int = counts[Tier.MEDIUM]
	var high: int = counts[Tier.HIGH]
	print("Tier mix over %d: LOW %.1f%%, MEDIUM %.1f%%, HIGH %.1f%%" % [SAMPLE_SIZE, low * 100 / n, medium * 100 / n, high * 100 / n])
	print("The LTV changes the tier for %.1f%% of applicants: %s" % [changed * 100 / n, changes])
	print("LTV bands (points) by purpose: %s; home loans with mortgage insurance: %d of %d" % [by_band, insured, homes])
	assert_float(low / n).is_between(0.37, 0.43)
	assert_float(medium / n).is_between(0.32, 0.38)
	assert_float(high / n).is_between(0.22, 0.28)
	assert_float(changed / n).is_between(0.04, 0.15)
	for key: String in ["low risk→medium risk", "medium risk→high risk"]:
		assert_int(changes.get(key, 0)).override_failure_message(key).is_greater(20)
	# Every band of every secured purpose turns up; a fair share of homes pay
	# mortgage insurance.
	for purpose: String in ["Home", "Auto", "Business"]:
		for points: int in [0, 1, 3]:
			assert_int(by_band.get("%s %d" % [purpose, points], 0)).override_failure_message("%s %d" % [purpose, points]).is_greater(5)
	assert_int(by_band.get("Business unsecured", 0)).is_greater(20)
	assert_float(insured / float(homes)).is_between(0.15, 0.6)

# --- counter-offers ---------------------------------------------------------------

func test_a_counter_offer_shows_the_down_payment_it_means() -> void:
	# A request over the healthy band: the line names the target too.
	var house := home(270000.0, 300000.0, 300000.0)
	assert_str(house.counter_offer_collateral_line(240000.0)).is_equal("A $240,000 loan means a $60,000 down payment (20.0%). Healthy LTV needs a loan of $240,000 or less.")
	var vehicle := car(30000.0, 28000.0)
	assert_str(vehicle.counter_offer_collateral_line(25000.0)).is_equal("A $25,000 loan means a $3,000 down payment (10.7%). Healthy LTV needs a loan of $28,000 or less.")
	assert_str(vehicle.counter_offer_collateral_line(30000.0)).is_equal("A $30,000 loan is $2,000 over the vehicle's price: no down payment. Healthy LTV needs a loan of $28,000 or less.")
	# A healthy request: no target.
	assert_str(home(200000.0, 300000.0, 300000.0).counter_offer_collateral_line(180000.0)).is_equal("A $180,000 loan means a $120,000 down payment (40.0%).")
	assert_str(house.healthy_ltv_text()).is_equal("Healthy LTV needs a loan of $240,000 or less.")
	var equipment := secured(applicant("Business", 60000.0), Collateral.EQUIPMENT, 0.0, 80000.0)
	assert_str(equipment.counter_offer_collateral_line(50000.0)).is_equal("A $50,000 loan is 62.5% of the equipment's value.")
	assert_str(secured(applicant("Personal", 9000.0), Collateral.NONE, 0.0, 0.0).counter_offer_collateral_line(5000.0)).is_empty()

# --- grading a counter-offer when the LTV is a weak point -------------------------

## A home bought with 3% down on an appraisal under the price, otherwise
## sound: the LTV is its only weak point.
func little_down() -> LoanApplication:
	var application := home(340000.0, 380000.0, 355000.0)
	application.annual_income = 160000.0
	application.monthly_debt_payments = 180.0
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## The LTV weak: BEST needs a healthy LTV as well as an affordable amount.
func test_a_counter_offer_must_fix_a_weak_ltv() -> void:
	var application := little_down()
	assert_int(application.risk_assessment).is_equal(Tier.MEDIUM)
	assert_array(application.weak_points()).is_equal([Reason.DOWN_PAYMENT])
	assert_bool(application.ltv_is_weak()).is_true()
	assert_float(application.healthy_ltv_amount()).is_equal(284000.0)
	assert_float(application.affordable_amount()).is_greater(340000.0)
	# $339,900 is affordable and below the request, but 95.7% LTV: PARTIAL.
	assert_int(application.grade_counter_offer(339900.0)).is_equal(LoanApplication.Grade.PARTIAL)
	assert_str(application.counter_offer_note(339900.0)).is_equal("Affordable, but the loan-to-value is still 95.7%: Healthy LTV needs a loan of $284,000 or less.")
	# Still stretched at $290,000 (81.7%): PARTIAL.
	assert_int(application.grade_counter_offer(290000.0)).is_equal(LoanApplication.Grade.PARTIAL)
	# At or under $284,000 (80%): BEST.
	assert_int(application.grade_counter_offer(284000.0)).is_equal(LoanApplication.Grade.BEST)
	assert_int(application.grade_counter_offer(250000.0)).is_equal(LoanApplication.Grade.BEST)
	assert_str(application.counter_offer_note(284000.0)).is_equal("Affordable, with a healthy loan-to-value (80.0%).")
	# A lowball is still only reasonable.
	assert_int(application.grade_counter_offer(150000.0)).is_equal(LoanApplication.Grade.PARTIAL)
	# grade_decision() reads it too.
	application.decision = LoanApplication.DecisionType.COUNTER_OFFER
	application.decision_amount = 339900.0
	assert_int(application.grade_decision()).is_equal(LoanApplication.Grade.PARTIAL)
	application.decision_amount = 280000.0
	assert_int(application.grade_decision()).is_equal(LoanApplication.Grade.BEST)

## The LTV and the payment both weak: a counter must be affordable and have a
## healthy LTV.
func test_a_counter_offer_must_fix_both_when_both_are_weak() -> void:
	var application := home(440000.0, 455000.0, 455000.0)
	application.monthly_debt_payments = 700.0
	application.risk_assessment = application.calculate_risk_assessment()
	assert_int(application.risk_assessment).is_equal(Tier.MEDIUM)
	assert_array(application.weak_points()).is_equal([Reason.INCOME, Reason.DOWN_PAYMENT])
	var affordable := application.affordable_amount()
	var healthy := application.healthy_ltv_amount()
	assert_float(healthy).is_equal(364000.0)
	assert_float(affordable).is_between(healthy + 10000.0, 439000.0)
	# Affordable but still a high or stretched LTV: PARTIAL.
	assert_int(application.grade_counter_offer(affordable)).is_equal(LoanApplication.Grade.PARTIAL)
	# A healthy LTV that's more than they can carry can't happen here (the
	# healthy amount is under the affordable one); over both: PARTIAL.
	assert_int(application.grade_counter_offer(affordable + 5000.0)).is_equal(LoanApplication.Grade.PARTIAL)
	# Both fixed: BEST.
	assert_int(application.grade_counter_offer(healthy)).is_equal(LoanApplication.Grade.BEST)

## A stretched LTV that isn't a weak point, or a payment-only weak point:
## graded on affordability as before.
func test_a_counter_offer_is_graded_on_affordability_when_the_ltv_isnt_weak() -> void:
	# Fair credit and a car at 110% of its price: the score is the weak point.
	var stretched := car(22000.0, 20000.0)
	stretched.credit_score = 640
	stretched.risk_assessment = stretched.calculate_risk_assessment()
	assert_int(stretched.risk_assessment).is_equal(Tier.MEDIUM)
	assert_bool(stretched.ltv_is_weak()).is_false()
	# $21,000 is still over the car's price, and BEST.
	assert_int(stretched.ltv_points(21000.0)).is_equal(1)
	assert_int(stretched.grade_counter_offer(21000.0)).is_equal(LoanApplication.Grade.BEST)
	assert_str(stretched.counter_offer_note(21000.0)).is_equal("Affordable at a healthy total DTI.")

# --- the new denial reason --------------------------------------------------------

func test_down_payment_too_small_as_a_denial_reason() -> void:
	assert_str(LoanApplication.denial_reason_label(Reason.DOWN_PAYMENT)).is_equal("Down payment too small for the value")
	assert_int(LoanApplication.DENIAL_REASON_ORDER.size()).is_equal(Reason.size())
	var right := LoanApplication.REASON_RIGHT_SCORE
	var wrong := LoanApplication.REASON_WRONG_SCORE
	var missing := LoanApplication.REASON_MISSING_SCORE
	var down: Array[LoanApplication.DenialReason] = [Reason.DOWN_PAYMENT]
	# A car loan at 125% of the car's value, otherwise sound: borderline, and
	# the down payment is the one reason.
	var over := car(25000.0, 20000.0)
	assert_int(over.calculate_risk_assessment()).is_equal(Tier.MEDIUM)
	assert_array(over.weak_points()).is_equal([Reason.DOWN_PAYMENT])
	assert_dict(over.grade_denial_reasons(down)).is_equal({"right": 1, "wrong": 0, "missing": 0, "score": right})
	var dti: Array[LoanApplication.DenialReason] = [Reason.TOTAL_DTI]
	assert_dict(over.grade_denial_reasons(dti)).is_equal({"right": 0, "wrong": 1, "missing": 1, "score": wrong + missing})
	# A stretched LTV isn't a reason to deny.
	var stretched := car(22000.0, 20000.0)
	assert_int(stretched.ltv_points()).is_equal(1)
	assert_bool(stretched.weak_points().has(Reason.DOWN_PAYMENT)).is_false()
	assert_int(stretched.grade_denial_reasons(down)["wrong"]).is_equal(1)
	# With fair credit too: high risk, both reasons real.
	over.credit_score = 640
	assert_int(over.calculate_risk_assessment()).is_equal(Tier.HIGH)
	assert_array(over.weak_points()).is_equal([Reason.CREDIT_SCORE, Reason.DOWN_PAYMENT])
	# 1-point levels alone (a good score, a stretched LTV and maxed-out cards):
	# the stretched LTV is the reason.
	var ones := car(22000.0, 20000.0)
	ones.credit_score = 700
	ones.credit_report_issued = true
	ones.utilization_percent = 90
	assert_int(ones.calculate_risk_assessment()).is_equal(Tier.MEDIUM)
	assert_array(ones.weak_points()).is_equal([Reason.DOWN_PAYMENT])

# --- loss on default ---------------------------------------------------------------

func test_loss_on_default_scales_with_ltv() -> void:
	var house := LoanApplication.Collateral.HOUSE
	var vehicle := LoanApplication.Collateral.VEHICLE
	# 1 − recovery × value ÷ loan, floored at 10%.
	assert_float(LoanBookManager.loss_share("Home", house, 80000.0, 100000.0)).is_equal_approx(LoanBookManager.MIN_LOSS_SHARE, 0.000001)
	assert_float(LoanBookManager.loss_share("Home", house, 95000.0, 100000.0)).is_equal_approx(1.0 - 0.75 / 0.95, 0.000001)
	assert_float(LoanBookManager.loss_share("Auto", vehicle, 30000.0, 30000.0)).is_equal_approx(0.40, 0.000001)
	assert_float(LoanBookManager.loss_share("Auto", vehicle, 37500.0, 30000.0)).is_equal_approx(1.0 - 0.6 / 1.25, 0.000001)
	assert_float(LoanBookManager.loss_share("Business", LoanApplication.Collateral.EQUIPMENT, 75000.0, 100000.0)).is_equal_approx(1.0 - 0.5 / 0.75, 0.000001)
	assert_float(LoanBookManager.loss_share("Business", LoanApplication.Collateral.PROPERTY, 70000.0, 100000.0)).is_equal_approx(LoanBookManager.MIN_LOSS_SHARE, 0.000001)
	# Unsecured: three quarters. Unknown (a loan booked before collateral): the
	# old flat share by purpose.
	assert_float(LoanBookManager.loss_share("Business", LoanApplication.Collateral.NONE, 50000.0, 0.0)).is_equal(LoanBookManager.UNSECURED_LOSS_SHARE)
	assert_float(LoanBookManager.loss_share("Home", LoanBookManager.COLLATERAL_UNKNOWN, 50000.0, 0.0)).is_equal(0.25)
	# The lower the LTV, the smaller the loss, purpose by purpose.
	for kind: int in [house, vehicle, LoanApplication.Collateral.EQUIPMENT, LoanApplication.Collateral.PROPERTY]:
		var previous := 0.0
		for ltv: float in [0.5, 0.7, 0.9, 1.0, 1.1, 1.3]:
			var share := LoanBookManager.loss_share("Home", kind, ltv * 100000.0, 100000.0)
			assert_float(share).override_failure_message("kind %d at %.1f" % [kind, ltv]).is_greater_equal(previous)
			previous = share

## A loan made from an application books its collateral, and its default
## loses what the collateral doesn't cover; the portfolio report counts the
## secured loans and their average LTV.
func test_booked_loans_carry_their_collateral() -> void:
	LoanBookManager.reset()
	var house := home(285000.0, 300000.0, 300000.0)
	house.applicant_name = "Kira Ibarra"
	house.decision = LoanApplication.DecisionType.APPROVE
	house.decision_amount = 285000.0
	var loan := LoanBookManager.note_decision(house, true, LoanBookManager.PLAYER_MAKER)
	assert_int(loan.collateral_kind).is_equal(Collateral.HOUSE)
	assert_float(loan.collateral_value).is_equal(300000.0)
	if loan.outcome == BookedLoan.Outcome.DEFAULT:
		assert_float(loan.loss).is_equal(roundf(285000.0 * (1.0 - 0.75 / 0.95)))
	# Forced to a default: 95% LTV loses 21%.
	LoanBookManager.roll_outcome(loan, _always_default())
	assert_float(loan.loss).is_equal(roundf(285000.0 * (1.0 - 0.75 / 0.95)))
	# Unsecured personal: three quarters.
	var personal := secured(applicant("Personal", 8000.0), Collateral.NONE, 0.0, 0.0)
	personal.decision = LoanApplication.DecisionType.APPROVE
	personal.decision_amount = 8000.0
	var unsecured := LoanBookManager.note_decision(personal, true, LoanBookManager.PLAYER_MAKER)
	LoanBookManager.roll_outcome(unsecured, _always_default())
	assert_float(unsecured.loss).is_equal(6000.0)
	# The report: one secured loan at 95.0%.
	var stats: Dictionary = LoanBookManager.period_stats[LoanBookManager.PLAYER]
	assert_float(LoanBookManager.stat(stats, "secured_made")).is_equal(1.0)
	assert_str(LoanBookManager.secured_line(stats)).is_equal("Secured loans: 1 at an average 95.0% loan-to-value (the lower it is, the less a default loses)")
	LoanBookManager.reset()

func _always_default() -> RandomNumberGenerator:
	# A generator whose first randf() is over 0.99: past every tier's on-time
	# and late odds, so roll_outcome() defaults.
	var rng := RandomNumberGenerator.new()
	for i in 1000:
		rng.seed = i
		if rng.randf() > 0.99:
			rng.seed = i
			return rng
	return rng

# --- fair lending --------------------------------------------------------------------

## The collateral comes from the finance generator: the same finance seed
## gives the same collateral, LTV and insurance whatever name and look are
## drawn; and across 3,000 applicants each look's share of LTV-driven tier
## changes is about everyone's.
func test_collateral_never_depends_on_the_name_or_look() -> void:
	var fields: Array[String] = ["collateral_issued", "collateral_kind", "purchase_price", "collateral_value"]
	var by_look := {}
	var changed_overall := 0
	var total := 3000
	for i in total:
		var first := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var identity := RandomNumberGenerator.new()
		identity.seed = hash([SEED, "identity", i])
		LoanApplicantGenerator.assign_identity(first, identity, {})
		if i < 300:
			var second := LoanApplicantGenerator.generate(finance_rng(SEED, i))
			var other := RandomNumberGenerator.new()
			other.seed = i + 100000
			LoanApplicantGenerator.assign_identity(second, other, {})
			for field in fields:
				assert_that(second.get(field)).override_failure_message(field).is_equal(first.get(field))
			assert_float(second.loan_to_value()).is_equal(first.loan_to_value())
			assert_float(second.mortgage_insurance()).is_equal(first.mortgage_insurance())
			assert_int(second.ltv_points()).is_equal(first.ltv_points())
		var changed := first.calculate_risk_assessment() != first.assessment_without_ltv()
		if changed:
			changed_overall += 1
		if not by_look.has(first.applicant_look):
			by_look[first.applicant_look] = Vector2i.ZERO
		by_look[first.applicant_look] += Vector2i(1, 1 if changed else 0)
	var overall := changed_overall / float(total)
	for look: int in by_look:
		var group: Vector2i = by_look[look]
		assert_float(absf(group.y / float(group.x) - overall)).override_failure_message("look %d" % look).is_less(0.07)

# --- save and load -------------------------------------------------------------------

func after_test() -> void:
	LoanDeskManager.reset()

## A pending application's collateral survives a save and load; one saved
## before collateral gets a healthy LTV (no points, no insurance), so its call
## doesn't change.
func test_collateral_saves_and_old_saves_load() -> void:
	var gap: LoanApplication = null
	for i in 3000:
		var candidate := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		if candidate.has_appraisal_gap() and candidate.mortgage_insurance() > 0.0:
			gap = candidate
			break
	assert_object(gap).is_not_null()
	gap.applicant_name = "Hugo Valdez"
	LoanDeskManager.player_queue.clear()
	LoanDeskManager.player_queue.append(gap)
	var json: Dictionary = JSON.parse_string(JSON.stringify(LoanDeskManager.save_data()))
	LoanDeskManager.reset()
	LoanDeskManager.load_data(json)
	var loaded := LoanDeskManager.player_queue[0]
	assert_dict(SaveGame.resource_to_dict(loaded)).is_equal(SaveGame.resource_to_dict(gap))
	assert_float(loaded.loan_to_value()).is_equal(gap.loan_to_value())

	var old := SaveGame.resource_to_dict(gap)
	for field: String in ["collateral_issued", "collateral_kind", "purchase_price", "collateral_value"]:
		old.erase(field)
	LoanDeskManager.load_data({"career_seed": 5, "generated_count": 3, "player_queue": [old]})
	var restored := LoanDeskManager.player_queue[0]
	assert_bool(restored.collateral_issued).is_true()
	assert_bool(restored.is_secured()).is_true()
	assert_int(restored.ltv_points()).is_equal(0)
	assert_float(restored.mortgage_insurance()).is_equal(0.0)
	assert_int(restored.risk_assessment).is_equal(restored.assessment_without_ltv())

	# A booked loan saved before collateral: the old flat loss share.
	var booked := BookedLoan.new()
	SaveGame.fill_resource(booked, {"loan_id": 4, "borrower": "Tom Walsh", "purpose": "Home", "amount": 200000.0})
	assert_int(booked.collateral_kind).is_equal(LoanBookManager.COLLATERAL_UNKNOWN)
	assert_float(LoanBookManager.loss_share(booked.purpose, booked.collateral_kind, booked.amount, booked.collateral_value)).is_equal(0.25)
