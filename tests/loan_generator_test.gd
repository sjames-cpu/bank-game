extends GdUnitTestSuite

## Generated loan applicants (LoanApplicantGenerator): every profile can be
## built; values are consistent and in range; the tier mix over 1,000
## applicants; applicants near a band edge; the variety of weak points; and
## fair lending: finances never depend on the name or look, the tier mix is
## the same across names and looks, grading never reads them, and no
## protected characteristic is stored.

const Tier := LoanApplication.RiskTier
const Reason := LoanApplication.DenialReason

const SAMPLE_SIZE: int = 1000
const SEED: int = 20261104

func finance_rng(seed_value: int, number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "finance", number])
	return rng

func identity_rng(seed_value: int, number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "identity", number])
	return rng

## `count` applicants' finances, the way LoanDeskManager seeds them.
func generated(count: int, seed_value: int = SEED) -> Array[LoanApplication]:
	var list: Array[LoanApplication] = []
	for i in count:
		list.append(LoanApplicantGenerator.generate(finance_rng(seed_value, i)))
	return list

## As generated(), each also named and given a look.
func identified(count: int, seed_value: int = SEED) -> Array[LoanApplication]:
	var list := generated(count, seed_value)
	for i in list.size():
		LoanApplicantGenerator.assign_identity(list[i], identity_rng(seed_value, i), {})
	return list

## The financial fields: everything saved except the name and look.
func finances(application: LoanApplication) -> Dictionary:
	var data := SaveGame.resource_to_dict(application)
	data.erase("applicant_name")
	data.erase("applicant_look")
	return data

func describe(application: LoanApplication) -> String:
	return "%s %s: $%.0f, income $%.0f, credit %d, housing $%.0f, debts $%.0f/mo ($%.0f), %d months, DTI %.3f" % [
		application.applicant_name, application.loan_purpose, application.requested_amount, application.annual_income,
		application.credit_score, application.monthly_housing_payment, application.monthly_debt_payments,
		application.existing_debt, application.employment_months, application.total_dti(),
	]

# --- building ------------------------------------------------------------------

## Every profile and every option in it builds, again and again, without
## falling back to a sample.
func test_every_profile_can_be_built() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for row: Array in LoanApplicantGenerator.PROFILES:
		var credit_options: Array = row[2]
		var dti_options: Array = row[3]
		var driver_options: Array = row[5]
		for credit: int in credit_options:
			for dti: int in dti_options:
				for driver: int in driver_options:
					var profile := LoanApplicantGenerator.Profile.new()
					profile.tier = row[0]
					profile.credit_points = credit
					profile.dti_points = dti
					profile.short_job = row[4]
					profile.driver = driver as LoanApplicantGenerator.Driver
					profile.over_max = row[6]
					for i in 30:
						var application := LoanApplicantGenerator.build(rng, profile)
						assert_object(application).override_failure_message("profile %s, credit %d, DTI %d, driver %d" % [row, credit, dti, driver]).is_not_null()
						if application == null:
							return
						assert_bool(LoanApplicantGenerator.matches(application, profile)).is_true()

func test_a_thousand_applicants_never_need_the_fallback() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in SAMPLE_SIZE:
		var profile := LoanApplicantGenerator.pick_profile(rng)
		assert_object(LoanApplicantGenerator.build(rng, profile)).is_not_null()

# --- consistent values -----------------------------------------------------------

func test_generated_values_are_consistent_and_in_range() -> void:
	for application in identified(SAMPLE_SIZE):
		var label := describe(application)
		var purpose := application.loan_purpose
		assert_bool(LoanApplication.PURPOSE_TERMS.has(purpose)).override_failure_message(label).is_true()
		var weak := application.weak_points()
		# The tier it was built for, by the real formula.
		assert_int(application.calculate_risk_assessment()).override_failure_message(label).is_equal(application.risk_tier)
		assert_int(application.risk_assessment).is_equal(application.risk_tier)

		# Amounts: round figures, at least the purpose's smallest, within the
		# policy maximum unless that's the point (then by no more than half).
		var step: float = LoanApplicantGenerator.AMOUNT_STEPS[purpose]
		assert_float(fmod(application.requested_amount, step)).override_failure_message(label).is_equal(0.0)
		var smallest: float = LoanApplicantGenerator.MIN_AMOUNTS[purpose]
		assert_float(application.requested_amount).override_failure_message(label).is_greater_equal(smallest)
		if weak.has(Reason.AMOUNT):
			assert_str(purpose).is_not_equal(LoanApplication.HOME_PURPOSE)
			assert_float(application.requested_amount).override_failure_message(label).is_less_equal(application.policy_maximum() * 1.5)
		else:
			assert_float(application.requested_amount).override_failure_message(label).is_less_equal(application.policy_maximum())

		# Income, credit and employment in their ranges.
		assert_float(application.annual_income).override_failure_message(label).is_between(LoanApplicantGenerator.MIN_INCOME, LoanApplicantGenerator.MAX_INCOME)
		assert_float(fmod(application.annual_income, LoanApplicantGenerator.INCOME_STEP)).is_equal(0.0)
		assert_int(application.credit_score).override_failure_message(label).is_between(500, 850)
		assert_int(application.employment_months).override_failure_message(label).is_between(3, 240)

		# Housing: a real rent or mortgage. A home loan's replaces it, and
		# today's is no more than the new one.
		var monthly := application.monthly_income()
		var housing_share := application.monthly_housing_payment / monthly
		assert_float(housing_share).override_failure_message(label).is_between(0.09, 0.34)
		assert_float(fmod(application.monthly_housing_payment, 25.0)).is_equal(0.0)
		if application.replaces_housing():
			assert_float(application.monthly_housing_payment).override_failure_message(label).is_less_equal(application.new_loan_payment() + 25.0)
			# A mortgage in line with income: 1 to 6.5 times it, its payment
			# under half of it.
			assert_float(application.requested_amount / application.annual_income).override_failure_message(label).is_between(1.0, 6.5)
			assert_float(application.front_end_dti()).override_failure_message(label).is_less(0.46)
		else:
			assert_float(application.new_payment_share()).override_failure_message(label).is_between(0.005, 0.43)

		# Debts: payments in line with the balance (2-3.5% of it a month, to
		# the $500 the balance is rounded to), none at all for no balance.
		var payments := application.monthly_debt_payments
		assert_float(fmod(payments, 5.0)).is_equal(0.0)
		assert_float(payments / monthly).override_failure_message(label).is_between(0.0, 0.31)
		if payments == 0.0:
			assert_float(application.existing_debt).override_failure_message(label).is_equal(0.0)
		else:
			assert_float(payments).override_failure_message(label).is_greater_equal(LoanApplicantGenerator.MIN_DEBT_PAYMENT)
			assert_float(application.existing_debt).override_failure_message(label).is_between(payments / 0.035 - 250.0, payments / 0.02 + 250.0)

		# Total DTI within the generated bands.
		assert_float(application.total_dti()).override_failure_message(label).is_between(0.19, 0.61)

		# Every applicant has a right answer: for a borderline one a
		# counter-offer they can afford, below the request (the one a staff
		# officer makes), or Reject when nothing worth offering is affordable.
		var right := application.correct_decision()
		application.decision = right
		application.decision_amount = NpcLoanDeskWorker._decision_amount(application, right)
		assert_int(application.grade_decision()).override_failure_message(label).is_equal(LoanApplication.Grade.BEST)
		application.decision = LoanApplication.DecisionType.NONE
		application.decision_amount = 0.0

		# A name and a look.
		assert_str(application.applicant_name).contains(" ")
		assert_int(application.applicant_look).is_between(0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)

# --- the mix ---------------------------------------------------------------------

func test_the_tier_mix_over_a_thousand_applicants() -> void:
	var counts := {Tier.LOW: 0, Tier.MEDIUM: 0, Tier.HIGH: 0}
	var purposes := {}
	var nothing_affordable := 0
	for application in generated(SAMPLE_SIZE):
		var tier := application.calculate_risk_assessment()
		counts[tier] += 1
		if application.nothing_affordable():
			nothing_affordable += 1
		purposes[application.loan_purpose] = purposes.get(application.loan_purpose, 0) + 1
	var low: int = counts[Tier.LOW]
	var medium: int = counts[Tier.MEDIUM]
	var high: int = counts[Tier.HIGH]
	print("Loan applicant mix over %d: LOW %d (%.1f%%), MEDIUM %d (%.1f%%), HIGH %d (%.1f%%); purposes %s" % [
		SAMPLE_SIZE, low, low * 100.0 / SAMPLE_SIZE, medium, medium * 100.0 / SAMPLE_SIZE, high, high * 100.0 / SAMPLE_SIZE, purposes])
	print("Borderline applicants with nothing worth counter-offering: %d of %d MEDIUM" % [nothing_affordable, medium])
	# They arise naturally, a minority of borderline applicants.
	assert_int(nothing_affordable).is_greater(20)
	assert_float(float(nothing_affordable)).is_less(medium * 0.5)
	# 40/35/25, within 4 points (about 2.6 standard deviations at n = 1,000).
	assert_float(low / float(SAMPLE_SIZE)).is_between(0.36, 0.44)
	assert_float(medium / float(SAMPLE_SIZE)).is_between(0.31, 0.39)
	assert_float(high / float(SAMPLE_SIZE)).is_between(0.21, 0.29)
	# Every purpose is asked for.
	for purpose: String in LoanApplication.PURPOSE_TERMS:
		assert_int(purposes.get(purpose, 0)).override_failure_message(purpose).is_greater(50)

## Some applicants sit just inside a band edge (credit within 9 points of
## 580/670/740, total DTI within 1.5 points of 36/43/50%, or 18-30 months in
## the job), each kind of edge among them, in every tier.
func test_some_applicants_sit_near_a_band_edge() -> void:
	var near := 0
	var kinds := {"credit": 0, "dti": 0, "employment": 0}
	var tiers := {}
	for application in generated(SAMPLE_SIZE):
		var found := false
		for edge: int in [LoanApplication.FAIR_CREDIT, LoanApplication.GOOD_CREDIT, LoanApplication.VERY_GOOD_CREDIT]:
			if absi(application.credit_score - edge) <= LoanApplicantGenerator.CREDIT_EDGE_POINTS + 1:
				kinds["credit"] += 1
				found = true
		for edge: float in [LoanApplication.HEALTHY_DTI, LoanApplication.STRETCHED_DTI, LoanApplication.HIGH_DTI]:
			if absf(application.total_dti() - edge) <= LoanApplicantGenerator.DTI_EDGE_WIDTH:
				kinds["dti"] += 1
				found = true
		if application.employment_months >= LoanApplicantGenerator.SHORT_JOB_EDGE_MIN and application.employment_months <= LoanApplicantGenerator.STEADY_JOB_EDGE_MAX:
			kinds["employment"] += 1
			found = true
		if found:
			near += 1
			tiers[application.risk_tier] = true
	print("Loan applicants near a band edge: %d of %d (%s)" % [near, SAMPLE_SIZE, kinds])
	assert_float(near / float(SAMPLE_SIZE)).is_greater(0.25)
	for kind: String in kinds:
		assert_int(kinds[kind]).override_failure_message(kind).is_greater(40)
	assert_int(tiers.size()).is_equal(3)

## The weak points behind a MEDIUM or HIGH vary: each denial reason is a
## real weak point for a good share of them, in many combinations, so the
## right reasons differ from case to case. A LOW applicant is never weak on
## credit, total DTI, income or the amount.
func test_weak_points_vary() -> void:
	var by_reason := {}
	var combos := {}
	var medium_combos := {}
	var risky := 0
	for application in generated(SAMPLE_SIZE):
		var weak := application.weak_points()
		var tier := application.calculate_risk_assessment()
		if tier == Tier.LOW:
			for reason: int in [Reason.CREDIT_SCORE, Reason.TOTAL_DTI, Reason.INCOME, Reason.AMOUNT]:
				assert_bool(weak.has(reason)).override_failure_message(describe(application)).is_false()
			continue
		risky += 1
		assert_array(weak).override_failure_message(describe(application)).is_not_empty()
		for reason in weak:
			by_reason[reason] = by_reason.get(reason, 0) + 1
		combos[str(weak)] = combos.get(str(weak), 0) + 1
		if tier == Tier.MEDIUM:
			medium_combos[str(weak)] = true
	var shares: PackedStringArray = []
	# The figures only (the documents are rolled apart: loan_documents_test.gd).
	for reason: int in Reason.values():
		if reason == Reason.UNVERIFIED:
			continue
		var count: int = by_reason.get(reason, 0)
		var label := LoanApplication.denial_reason_label(reason as LoanApplication.DenialReason)
		shares.append("%s %.0f%%" % [label, count * 100.0 / risky])
		# Each reason for at least 5% of risky applicants.
		assert_float(count / float(risky)).override_failure_message(label).is_greater(0.05)
	print("Weak points among %d MEDIUM/HIGH applicants: %s; %d combinations" % [risky, ", ".join(shares), combos.size()])
	assert_int(combos.size()).is_greater_equal(10)
	assert_int(medium_combos.size()).is_greater_equal(5)
	# No one combination dominates.
	for combo: String in combos:
		assert_float(combos[combo] / float(risky)).override_failure_message(combo).is_less(0.3)

# --- fair lending --------------------------------------------------------------

## The finances come from their own generator: the same finance seed gives
## the same applicant whatever name and look are drawn for them, and drawing
## an identity changes nothing financial.
func test_finances_never_depend_on_the_name_or_look() -> void:
	for i in 300:
		var first := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var second := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var expected_finances := finances(first)
		LoanApplicantGenerator.assign_identity(first, identity_rng(SEED, i), {})
		LoanApplicantGenerator.assign_identity(second, identity_rng(SEED + 1, i), {})
		assert_dict(finances(first)).is_equal(expected_finances)
		assert_dict(finances(second)).is_equal(expected_finances)
		assert_int(first.calculate_risk_assessment()).is_equal(second.calculate_risk_assessment())

## Across 3,000 applicants, each look and each group of first names gets
## much the same share of every tier as everyone.
func test_the_tier_mix_doesnt_depend_on_the_name_or_look() -> void:
	var applicants := identified(3000)
	var overall := {Tier.LOW: 0.0, Tier.MEDIUM: 0.0, Tier.HIGH: 0.0}
	var by_look := {}
	var by_name := {}
	for application in applicants:
		var tier := application.calculate_risk_assessment()
		overall[tier] += 1.0 / applicants.size()
		var first_name := application.applicant_name.get_slice(" ", 0)
		count_in(by_look, application.applicant_look, tier)
		count_in(by_name, LoanApplicantGenerator.FIRST_NAMES.find(first_name) % 4, tier)
	assert_int(by_look.size()).is_equal(CustomerNPC.CUSTOMER_FRAME_SETS.size())
	assert_int(by_name.size()).is_equal(4)
	for groups: Dictionary in [by_look, by_name]:
		for key: int in groups:
			var group: Dictionary = groups[key]
			var n: int = group["n"]
			# About 250 a look and 750 a name group: 0.12 is over 3.5
			# standard deviations for a look.
			for tier: int in [Tier.LOW, Tier.MEDIUM, Tier.HIGH]:
				var count: int = group[tier]
				var share := count / float(n)
				var expected: float = overall[tier]
				assert_float(absf(share - expected)).override_failure_message("group %d, tier %d: %.3f against %.3f" % [key, tier, share, expected]).is_less(0.12)

func count_in(groups: Dictionary, key: int, tier: int) -> void:
	if not groups.has(key):
		groups[key] = {Tier.LOW: 0, Tier.MEDIUM: 0, Tier.HIGH: 0, "n": 0}
	var group: Dictionary = groups[key]
	group[tier] += 1
	group["n"] += 1

## Only the financial data and employment decide the tier and the grading:
## another name and look change nothing.
func test_grading_never_reads_the_name_or_look() -> void:
	var cases := LoanApplicationsData.get_applications()
	cases.append_array(identified(200))
	for application in cases:
		var other := LoanApplication.new()
		SaveGame.fill_resource(other, SaveGame.resource_to_dict(application))
		other.applicant_name = "Someone Else"
		other.applicant_look = (application.applicant_look + 5) % CustomerNPC.CUSTOMER_FRAME_SETS.size()
		application.risk_assessment = application.calculate_risk_assessment()
		other.risk_assessment = other.calculate_risk_assessment()
		assert_int(other.risk_points()).is_equal(application.risk_points())
		assert_int(other.risk_assessment).is_equal(application.risk_assessment)
		assert_array(other.weak_points()).is_equal(application.weak_points())
		assert_float(other.affordable_amount()).is_equal(application.affordable_amount())
		for amount: float in [application.affordable_amount(), application.requested_amount * 0.6, application.requested_amount]:
			assert_int(other.grade_counter_offer(amount)).is_equal(application.grade_counter_offer(amount))
		var stated := application.weak_points()
		assert_dict(other.grade_denial_reasons(stated)).is_equal(application.grade_denial_reasons(stated))
		var employment: Array[LoanApplication.DenialReason] = [LoanApplication.DenialReason.EMPLOYMENT]
		assert_dict(other.grade_denial_reasons(employment)).is_equal(application.grade_denial_reasons(employment))

## An application holds its finances, employment, purpose, a name and a look,
## and nothing about who the applicant is beyond that.
func test_no_protected_characteristic_is_stored() -> void:
	var stored: Array[String] = []
	for property in LoanApplication.new().get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			stored.append(property["name"])
	stored.sort()
	assert_array(stored).is_equal([
		"annual_income", "applicant_look", "applicant_name", "credit_score", "decision", "decision_amount",
		"doc_problem", "documents_issued", "employment_months", "existing_debt", "has_pay_stub", "has_statement",
		"id_expiry_date", "id_holder_name", "id_number", "id_portrait_look", "id_presented", "id_problem",
		"loan_purpose", "monthly_debt_payments", "monthly_housing_payment",
		"requested_amount", "risk_assessment", "risk_tier",
		"statement_deposits", "statement_name", "stub_employer", "stub_monthly_gross", "stub_monthly_net", "stub_name",
	])
	for forbidden: String in ["age", "birth", "sex", "gender", "race", "ethnic", "religio", "nation", "origin", "marital", "married", "citizen", "disab"]:
		for property_name in stored:
			assert_str(property_name).override_failure_message("%s looks like a protected characteristic (%s)" % [property_name, forbidden]).not_contains(forbidden)

## Generated names never take a sample's (the teaching cases), a staff
## member's or a job candidate's.
func test_generated_names_avoid_reserved_ones() -> void:
	var reserved := LoanApplicantGenerator.reserved_names()
	assert_bool(reserved.has("Maria Chen")).is_true()
	assert_bool(reserved.has("Nina Ortiz")).is_true()
	assert_bool(reserved.has("Harper Quinn")).is_true()
	for application in identified(500):
		assert_bool(reserved.has(application.applicant_name)).override_failure_message(application.applicant_name).is_false()
