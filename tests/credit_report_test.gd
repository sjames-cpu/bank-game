extends GdUnitTestSuite

## Credit reports and risk-based pricing (LoanApplication, CreditReport,
## LoanApplicantGenerator): every applicant's report is consistent with their
## score, with variety; how the report counts in the risk assessment; the
## tier mix and how often the report changes the call the score alone would
## make; the rate table and its effect on the payment, DTI and affordable
## amount; the "Recent late payments or collections" denial reason; fair
## lending; and saving the report with an application (old saves too).

const Tier := LoanApplication.RiskTier
const Reason := LoanApplication.DenialReason
const Story := CreditReport.Story

const SAMPLE_SIZE: int = 2000
const SEED: int = 20261111

func finance_rng(seed_value: int, number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "finance", number])
	return rng

func generated(count: int, seed_value: int = SEED) -> Array[LoanApplication]:
	var list: Array[LoanApplication] = []
	for i in count:
		list.append(LoanApplicantGenerator.generate(finance_rng(seed_value, i)))
	return list

## A plain applicant with no report yet: very good credit, 25% total DTI,
## five years in the job.
func applicant(score: int = 760, purpose: String = "Auto") -> LoanApplication:
	var application := LoanApplication.new()
	application.loan_purpose = purpose
	application.requested_amount = 0.0
	application.credit_score = score
	application.annual_income = 120000.0
	application.monthly_housing_payment = 2500.0
	application.employment_months = 60
	return application

## `application` with a hand-set report (nothing late, utilization 20%).
func with_report(application: LoanApplication, utilization: int = 20) -> LoanApplication:
	application.credit_report_issued = true
	application.on_time_percent = 98
	application.utilization_percent = utilization
	application.open_accounts = 5
	application.hard_inquiries = 1
	return application

func describe(application: LoanApplication) -> String:
	return "score %d: on time %d%%, late %d/%d/%d, utilization %d%%, %d accounts, %d inquiries, %d collections (%d mo), bankruptcy %d mo" % [
		application.credit_score, application.on_time_percent, application.late_30_days, application.late_60_days, application.late_90_days,
		application.utilization_percent, application.open_accounts, application.hard_inquiries,
		application.collections, application.months_since_collection, application.months_since_bankruptcy,
	]

# --- consistent with the score ---------------------------------------------------------

## Every generated report is in range and fits its score: nothing recent or
## maxed out at 740+, at most one 30-day late at 800+, a recent bankruptcy
## only under 600, and an on-time rate under 100% whenever something was late.
func test_reports_are_in_range_and_fit_the_score() -> void:
	for application in generated(SAMPLE_SIZE):
		var label := describe(application)
		assert_bool(application.credit_report_issued).override_failure_message(label).is_true()
		var lates := application.late_30_days + application.late_60_days + application.late_90_days
		assert_int(application.on_time_percent).override_failure_message(label).is_between(70, 100)
		assert_int(application.late_30_days).override_failure_message(label).is_between(0, 6)
		assert_int(application.late_60_days).override_failure_message(label).is_between(0, 3)
		assert_int(application.late_90_days).override_failure_message(label).is_between(0, 2)
		assert_int(application.utilization_percent).override_failure_message(label).is_between(1, 98)
		assert_int(application.open_accounts).override_failure_message(label).is_between(2, 13)
		assert_int(application.hard_inquiries).override_failure_message(label).is_between(0, 5)
		assert_int(application.collections).override_failure_message(label).is_between(0, 3)
		assert_int(application.months_since_collection).override_failure_message(label).is_between(0, CreditReport.REPORT_MONTHS)
		assert_int(application.months_since_bankruptcy).override_failure_message(label).is_between(0, CreditReport.REPORT_MONTHS)
		assert_bool(application.collections > 0).override_failure_message(label).is_equal(application.months_since_collection > 0)
		if lates > 0:
			assert_int(application.on_time_percent).override_failure_message(label).is_less(100)
		if application.credit_score >= LoanApplication.VERY_GOOD_CREDIT:
			assert_bool(application.has_recent_serious_mark()).override_failure_message(label).is_false()
			assert_bool(application.has_high_utilization()).override_failure_message(label).is_false()
			assert_int(application.late_60_days + application.late_90_days).override_failure_message(label).is_equal(0)
			assert_int(application.late_30_days).override_failure_message(label).is_less_equal(1)
			assert_int(application.collections).override_failure_message(label).is_equal(0)
			assert_int(application.months_since_bankruptcy).override_failure_message(label).is_equal(0)
		if application.credit_score >= 800:
			assert_int(application.on_time_percent).override_failure_message(label).is_greater_equal(99)
			assert_int(application.utilization_percent).override_failure_message(label).is_less_equal(12)
		if application.months_since_bankruptcy > 0 and application.months_since_bankruptcy <= CreditReport.RECENT_MONTHS:
			assert_int(application.credit_score).override_failure_message(label).is_less(CreditReport.RECENT_BANKRUPTCY_MAX_SCORE)

## Lower scores come with worse histories, band by band: more late payments,
## higher utilization, a lower on-time rate, more inquiries, and more often a
## serious mark (recent or within seven years).
func test_worse_histories_go_with_lower_scores() -> void:
	var lates: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var utilization: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var on_time: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var inquiries: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var marked: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var recent: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for application in generated(SAMPLE_SIZE):
		var band := CreditReport.band_index(application.credit_score)
		counts[band] += 1
		lates[band] += application.late_30_days + application.late_60_days * 2 + application.late_90_days * 3
		utilization[band] += application.utilization_percent
		on_time[band] += application.on_time_percent
		inquiries[band] += application.hard_inquiries
		if application.collections > 0 or application.months_since_bankruptcy > 0:
			marked[band] += 1
		if application.has_recent_serious_mark():
			recent[band] += 1
	var rows: PackedStringArray = []
	for band in 5:
		var n: int = counts[band]
		assert_int(n).override_failure_message("band %d" % band).is_greater(60)
		for list: Array[float] in [lates, utilization, on_time, inquiries, marked, recent]:
			list[band] = list[band] / n
		rows.append("%s: lates %.2f, utilization %.0f%%, on time %.1f%%, inquiries %.1f, marks %.0f%%, recent %.0f%% (n %d)" % [
			LoanApplication.BAND_RANGES[band], lates[band], utilization[band], on_time[band], inquiries[band], marked[band] * 100.0, recent[band] * 100.0, n])
	print("Credit reports by band:\n  " + "\n  ".join(rows))
	for band in range(1, 5):
		assert_float(lates[band]).override_failure_message("lates, band %d" % band).is_greater(lates[band - 1])
		assert_float(on_time[band]).override_failure_message("on time, band %d" % band).is_less(on_time[band - 1])
		assert_float(inquiries[band]).override_failure_message("inquiries, band %d" % band).is_greater_equal(inquiries[band - 1] - 0.05)
	# Utilization rises down to Fair (Poor is about as high).
	for band in range(1, 4):
		assert_float(utilization[band]).override_failure_message("utilization, band %d" % band).is_greater(utilization[band - 1])
	assert_float(utilization[4]).is_greater(utilization[2])
	# Serious marks: none at 740+, more often the lower the score.
	assert_float(marked[0] + marked[1]).is_equal(0.0)
	assert_float(recent[0] + recent[1]).is_equal(0.0)
	assert_float(marked[3]).is_greater(marked[2])
	assert_float(marked[4]).is_greater(marked[3])
	assert_float(recent[4]).is_greater(recent[3])

## Two applicants with much the same score can have different stories: in a
## band, reports differ in how they count (−1 for a clean recent history,
## 0, +1 for maxed-out cards, +2 or +3 for a recent serious mark), and the
## same 20-point slice of scores holds several of them.
func test_similar_scores_tell_different_stories() -> void:
	var points_by_band := {}
	var slice_points := {}
	var slice_kinds := {}
	for application in generated(SAMPLE_SIZE):
		var band := CreditReport.band_index(application.credit_score)
		if not points_by_band.has(band):
			points_by_band[band] = {}
		var points := application.credit_report_points()
		points_by_band[band][points] = true
		if application.credit_score >= 600 and application.credit_score < 620:
			slice_points[points] = true
			var kind := "late 90" if application.late_90_days > 0 else "recent collection" if application.has_recent_serious_mark() \
				else "clean" if application.has_clean_recent_history() else "maxed" if application.has_high_utilization() else "normal"
			slice_kinds[kind] = true
	print("Report points by band: %s; scores 600-619: points %s, stories %s" % [points_by_band, slice_points.keys(), slice_kinds.keys()])
	var good: Dictionary = points_by_band[2]
	var fair: Dictionary = points_by_band[3]
	var poor: Dictionary = points_by_band[4]
	# Fair: clean (−1), normal, maxed, a recent mark.
	for points: int in [-1, 0, 1, 2]:
		assert_bool(fair.has(points)).override_failure_message("Fair, %d points" % points).is_true()
	# Good: normal, maxed, a recent mark, both.
	for points: int in [0, 1, 2, 3]:
		assert_bool(good.has(points)).override_failure_message("Good, %d points" % points).is_true()
	# Poor: a clean recent history too.
	assert_bool(poor.has(-1)).is_true()
	assert_int(slice_points.size()).is_greater_equal(3)
	assert_int(slice_kinds.size()).is_greater_equal(3)

# --- the report in the risk assessment -------------------------------------------------

func test_how_the_report_counts() -> void:
	# No report (an old application or a test's): no report points.
	var none := applicant(650)
	assert_int(none.credit_report_points()).is_equal(0)
	assert_int(none.risk_points()).is_equal(3)
	assert_int(none.risk_points()).is_equal(none.score_only_points())

	# A 90-day late, a collection or a bankruptcy in the last two years: +2.
	var late := with_report(applicant(710), 40)
	assert_int(late.credit_report_points()).is_equal(0)
	late.late_90_days = 1
	assert_int(late.credit_report_points()).is_equal(CreditReport.SERIOUS_MARK_POINTS)
	assert_bool(late.has_recent_serious_mark()).is_true()
	late.late_90_days = 0
	late.collections = 1
	late.months_since_collection = 24
	assert_int(late.credit_report_points()).is_equal(2)
	late.months_since_collection = 25
	assert_int(late.credit_report_points()).override_failure_message("a collection over two years ago").is_equal(0)
	late.collections = 0
	late.months_since_collection = 0
	late.months_since_bankruptcy = 18
	assert_int(late.credit_report_points()).is_equal(2)
	late.months_since_bankruptcy = 60
	assert_int(late.credit_report_points()).is_equal(0)
	# 30- and 60-day lates aren't serious marks by themselves.
	late.months_since_bankruptcy = 0
	late.late_30_days = 3
	late.late_60_days = 2
	assert_int(late.credit_report_points()).is_equal(0)

	# Utilization over 75%: +1.
	var maxed := with_report(applicant(710), 75)
	assert_int(maxed.credit_report_points()).is_equal(0)
	maxed.utilization_percent = 76
	assert_int(maxed.credit_report_points()).is_equal(CreditReport.HIGH_UTILIZATION_POINTS)

	# A score under 670 with a clean last two years: −1. Not with anything
	# late, or utilization over 30%, or a score of 670 or more.
	var rebuilt := with_report(applicant(650), 30)
	assert_bool(rebuilt.has_clean_recent_history()).is_true()
	assert_int(rebuilt.credit_report_points()).is_equal(CreditReport.CLEAN_HISTORY_POINTS)
	assert_int(rebuilt.risk_points()).is_equal(2)
	assert_int(rebuilt.calculate_risk_assessment()).is_equal(Tier.LOW)
	assert_int(rebuilt.score_only_assessment()).is_equal(Tier.MEDIUM)
	rebuilt.utilization_percent = 31
	assert_int(rebuilt.credit_report_points()).is_equal(0)
	rebuilt.utilization_percent = 20
	rebuilt.late_30_days = 1
	assert_int(rebuilt.credit_report_points()).is_equal(0)
	var good_clean := with_report(applicant(700), 10)
	assert_int(good_clean.credit_report_points()).is_equal(0)

	# Together: a good score hiding a recent collection and maxed-out cards
	# is high risk, where the score alone says low.
	var hidden := with_report(applicant(700), 90)
	hidden.collections = 1
	hidden.months_since_collection = 8
	hidden.monthly_housing_payment = 3800.0
	assert_int(hidden.score_only_points()).is_equal(2)
	assert_int(hidden.risk_points()).is_equal(5)
	assert_int(hidden.score_only_assessment()).is_equal(Tier.LOW)
	assert_int(hidden.calculate_risk_assessment()).is_equal(Tier.HIGH)

## Every story fits the scores it's told for, and a story that doesn't fit
## is told as NORMAL, which never adds or takes away points.
func test_each_story_counts_what_it_says() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for story: int in Story.values():
		for score: int in [500, 579, 580, 640, 669, 670, 739, 740, 800, 840]:
			for i in 40:
				var application := applicant(score)
				CreditReport.issue(application, rng, story as CreditReport.Story)
				var told := story as CreditReport.Story if CreditReport.story_fits(story as CreditReport.Story, score) else Story.NORMAL
				assert_int(application.credit_report_points()).override_failure_message("story %d, %s" % [story, describe(application)]).is_equal(CreditReport.story_points(told))
				assert_bool(application.has_recent_serious_mark()).is_equal(CreditReport.has_recent_mark(told))

# --- the tier mix and the report's effect ------------------------------------------------

## The mix stays about 40/35/25, and the report changes the call the score
## (with DTI and employment) alone would make for some applicants, both ways.
func test_the_tier_mix_and_how_often_the_report_changes_the_tier() -> void:
	var counts := {Tier.LOW: 0, Tier.MEDIUM: 0, Tier.HIGH: 0}
	var riskier := 0
	var safer := 0
	var changes := {}
	for application in generated(SAMPLE_SIZE):
		var tier := application.calculate_risk_assessment()
		var score_only := application.score_only_assessment()
		counts[tier] += 1
		if tier > score_only:
			riskier += 1
		elif tier < score_only:
			safer += 1
		if tier != score_only:
			var key := "%s→%s" % [LoanApplication.risk_tier_label(score_only), LoanApplication.risk_tier_label(tier)]
			changes[key] = changes.get(key, 0) + 1
	var n := float(SAMPLE_SIZE)
	var low: int = counts[Tier.LOW]
	var medium: int = counts[Tier.MEDIUM]
	var high: int = counts[Tier.HIGH]
	print("Tier mix over %d: LOW %.1f%%, MEDIUM %.1f%%, HIGH %.1f%%" % [SAMPLE_SIZE, low * 100 / n, medium * 100 / n, high * 100 / n])
	print("The credit report changes the tier for %.1f%% of applicants (riskier %.1f%%, safer %.1f%%): %s" % [
		(riskier + safer) * 100 / n, riskier * 100 / n, safer * 100 / n, changes])
	# 40/35/25 within 3 points (about 2.7 standard deviations at n = 2,000).
	assert_float(low / n).is_between(0.37, 0.43)
	assert_float(medium / n).is_between(0.32, 0.38)
	assert_float(high / n).is_between(0.22, 0.28)
	# Some, not most: about one applicant in eight, each way.
	assert_float((riskier + safer) / n).is_between(0.08, 0.20)
	assert_float(riskier / n).is_greater(0.05)
	assert_float(safer / n).is_greater(0.02)
	# A good score hiding a recent mark (low → medium), a fair one with a clean
	# recent history (medium → low), and a poor one (high → medium).
	for key: String in ["low risk→medium risk", "medium risk→low risk", "high risk→medium risk", "medium risk→high risk"]:
		assert_int(changes.get(key, 0)).override_failure_message(key).is_greater(10)

# --- risk-based pricing ------------------------------------------------------------------

func test_the_rate_table_by_purpose_and_credit_band() -> void:
	var expected := {
		"Auto": [5.50, 6.25, 7.00, 10.50, 14.50],
		"Home": [6.25, 6.50, 6.75, 7.25, 8.25],
		"Personal": [9.50, 11.00, 14.00, 19.00, 26.00],
		"Business": [7.75, 8.25, 9.00, 10.75, 13.00],
	}
	assert_dict(LoanApplication.RATE_TABLE).is_equal(expected)
	# Each band's edges: 800+, 740-799, 670-739, 580-669, under 580.
	var edges := [[850, 0], [800, 0], [799, 1], [740, 1], [739, 2], [670, 2], [669, 3], [580, 3], [579, 4], [450, 4]]
	for purpose: String in expected:
		var rates: Array = expected[purpose]
		for edge: Array in edges:
			var score: int = edge[0]
			var column: int = edge[1]
			var rate: float = rates[column]
			assert_float(LoanApplication.rate_for(purpose, score)).override_failure_message("%s at %d" % [purpose, score]).is_equal_approx(rate / 100.0, 0.000001)
			assert_float(applicant(score, purpose).annual_rate()).is_equal_approx(rate / 100.0, 0.000001)
		# Lower credit never pays less.
		for i in range(1, rates.size()):
			var worse: float = rates[i]
			var better: float = rates[i - 1]
			assert_float(worse).is_greater(better)
	# An unsecured personal loan's spread is the widest, a mortgage's the narrowest.
	assert_float(26.00 - 9.50).is_greater(14.50 - 5.50)
	assert_float(8.25 - 6.25).is_less(13.00 - 7.75)

## The rate moves the new payment, the total DTI and the amount affordable:
## the same $20,000 car for the same household costs more each month with
## poorer credit.
func test_the_rate_sets_the_payment_dti_and_affordable_amount() -> void:
	var best := applicant(810)
	best.requested_amount = 20000.0
	best.monthly_debt_payments = 300.0
	var fair := applicant(600)
	fair.requested_amount = 20000.0
	fair.monthly_debt_payments = 300.0
	assert_float(best.new_loan_payment()).is_equal_approx(LoanApplication.monthly_payment(20000.0, 0.055, 60), 0.0001)
	assert_float(best.new_loan_payment()).is_equal_approx(382.02, 0.005)
	assert_float(fair.new_loan_payment()).is_equal_approx(429.88, 0.005)
	assert_float(fair.total_dti()).is_equal_approx((2500.0 + 300.0 + fair.new_loan_payment()) / 10000.0, 0.000001)
	assert_float(fair.total_dti()).is_greater(best.total_dti())
	# 36% of $10,000 less $2,800 leaves $800 a month: $41,800 at 5.50%, $37,200
	# at 10.50%.
	assert_float(best.affordable_amount()).is_equal(floorf(LoanApplication.principal_for_payment(800.0, 0.055, 60) / 100.0) * 100.0)
	assert_float(best.affordable_amount()).is_equal(41800.0)
	assert_float(fair.affordable_amount()).is_equal(37200.0)
	# A mortgage: the rate moves the housing payment itself.
	var home_best := applicant(810, "Home")
	home_best.requested_amount = 300000.0
	var home_fair := applicant(600, "Home")
	home_fair.requested_amount = 300000.0
	assert_float(home_best.housing_payment_after_loan()).is_equal_approx(1847.15, 0.005)
	assert_float(home_fair.housing_payment_after_loan()).is_equal_approx(2046.53, 0.005)
	assert_float(home_fair.front_end_dti()).is_greater(home_best.front_end_dti())
	# Why the rate: the band and the table's range, never the verdict.
	assert_str(fair.rate_reason()).is_equal("Priced for Fair credit (580-669); auto rates run 5.50% to 14.50%, lower credit paying more.")

# --- the new denial reason ---------------------------------------------------------------

func test_recent_late_payments_or_collections_as_a_denial_reason() -> void:
	assert_str(LoanApplication.denial_reason_label(Reason.CREDIT_HISTORY)).is_equal("Recent late payments or collections")
	assert_int(LoanApplication.DENIAL_REASON_ORDER.size()).is_equal(Reason.size())
	# A good score with a 90-day late payment and a stretched DTI: medium risk,
	# and the history is the reason to give.
	var late := with_report(applicant(700), 40)
	late.late_90_days = 1
	assert_int(late.calculate_risk_assessment()).is_equal(Tier.MEDIUM)
	assert_array(late.weak_points()).is_equal([Reason.CREDIT_HISTORY])
	var right := LoanApplication.REASON_RIGHT_SCORE
	var wrong := LoanApplication.REASON_WRONG_SCORE
	var missing := LoanApplication.REASON_MISSING_SCORE
	var history: Array[LoanApplication.DenialReason] = [Reason.CREDIT_HISTORY]
	var score_reason: Array[LoanApplication.DenialReason] = [Reason.CREDIT_SCORE]
	assert_dict(late.grade_denial_reasons(history)).is_equal({"right": 1, "wrong": 0, "missing": 0, "score": right})
	assert_dict(late.grade_denial_reasons(score_reason)).is_equal({"right": 0, "wrong": 1, "missing": 1, "score": wrong + missing})
	# A fair score with a collection last year: both credit reasons are real.
	var fair := with_report(applicant(620), 50)
	fair.late_30_days = 2
	fair.collections = 1
	fair.months_since_collection = 11
	assert_int(fair.calculate_risk_assessment()).is_equal(Tier.HIGH)
	assert_array(fair.weak_points()).is_equal([Reason.CREDIT_SCORE, Reason.CREDIT_HISTORY])
	var both: Array[LoanApplication.DenialReason] = [Reason.CREDIT_SCORE, Reason.CREDIT_HISTORY]
	assert_int(fair.grade_denial_reasons(both)["score"]).is_equal(2 * right)
	# The same history three years ago isn't a recent one: naming it is wrong.
	fair.months_since_collection = 36
	assert_array(fair.weak_points()).is_equal([Reason.CREDIT_SCORE])
	assert_int(fair.grade_denial_reasons(history)["wrong"]).is_equal(1)
	# No report, no history reason.
	var no_report := applicant(620)
	assert_bool(no_report.weak_points().has(Reason.CREDIT_HISTORY)).is_false()
	# Medium risk from 1-point levels alone (a good score, a stretched DTI and
	# maxed-out cards): the payments are the reason.
	var ones := with_report(applicant(700), 90)
	ones.monthly_housing_payment = 4000.0
	assert_int(ones.calculate_risk_assessment()).is_equal(Tier.MEDIUM)
	assert_array(ones.weak_points()).is_equal([Reason.TOTAL_DTI])
	# Documents that don't check out still trump everything.
	late.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	assert_array(late.weak_points()).is_equal([Reason.UNVERIFIED])

# --- fair lending --------------------------------------------------------------------

## The report and the rate come from the finances and the score alone: the
## same finance seed gives the same report and rate whatever name and look
## are drawn, a report issued for another name is the same report, and the
## rate is a function of the purpose and score only.
func test_the_report_and_rate_never_depend_on_the_name_or_look() -> void:
	var report_fields: Array[String] = [
		"credit_report_issued", "on_time_percent", "late_30_days", "late_60_days", "late_90_days", "utilization_percent",
		"open_accounts", "hard_inquiries", "collections", "months_since_collection", "months_since_bankruptcy",
	]
	for i in 300:
		var first := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var second := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var identity_a := RandomNumberGenerator.new()
		identity_a.seed = i
		var identity_b := RandomNumberGenerator.new()
		identity_b.seed = i + 100000
		LoanApplicantGenerator.assign_identity(first, identity_a, {})
		LoanApplicantGenerator.assign_identity(second, identity_b, {})
		for field in report_fields:
			assert_that(second.get(field)).override_failure_message(field).is_equal(first.get(field))
		assert_float(second.annual_rate()).is_equal(first.annual_rate())
		assert_int(second.credit_report_points()).is_equal(first.credit_report_points())

		# The same report rolled for another name and look.
		var a := applicant(first.credit_score)
		a.applicant_name = "Someone"
		a.applicant_look = 1
		var b := applicant(first.credit_score)
		b.applicant_name = "Someone Else"
		b.applicant_look = 9
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = i
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = i
		CreditReport.issue(a, rng_a, Story.RECENT_MARK)
		CreditReport.issue(b, rng_b, Story.RECENT_MARK)
		for field in report_fields:
			assert_that(b.get(field)).override_failure_message(field).is_equal(a.get(field))

## The tier the report adds to doesn't depend on the look either: across
## 3,000 applicants, each look's share of report-driven tier changes is
## about everyone's.
func test_report_driven_changes_are_the_same_for_every_look() -> void:
	var by_look := {}
	var changed_overall := 0
	var total := 3000
	for i in total:
		var application := LoanApplicantGenerator.generate(finance_rng(SEED, i))
		var identity := RandomNumberGenerator.new()
		identity.seed = hash([SEED, "identity", i])
		LoanApplicantGenerator.assign_identity(application, identity, {})
		var changed := application.calculate_risk_assessment() != application.score_only_assessment()
		if changed:
			changed_overall += 1
		if not by_look.has(application.applicant_look):
			by_look[application.applicant_look] = Vector2i.ZERO
		by_look[application.applicant_look] += Vector2i(1, 1 if changed else 0)
	var overall := changed_overall / float(total)
	assert_int(by_look.size()).is_equal(CustomerNPC.CUSTOMER_FRAME_SETS.size())
	for look: int in by_look:
		var group: Vector2i = by_look[look]
		# About 250 a look: 0.08 is over 3.5 standard deviations.
		assert_float(absf(group.y / float(group.x) - overall)).override_failure_message("look %d" % look).is_less(0.08)

# --- save and load -------------------------------------------------------------------

func after_test() -> void:
	LoanDeskManager.reset()

## A pending application's report survives a save and load whole; one saved
## before reports gets a report in line with its score that adds nothing, so
## its call stays what the score, DTI and employment say.
func test_the_report_saves_with_the_application_and_old_saves_load() -> void:
	var application := LoanApplicantGenerator.generate(finance_rng(SEED, 7))
	application.applicant_name = "Kira Ibarra"
	var mark := LoanApplicantGenerator.generate(finance_rng(SEED, 8))
	for i in 500:
		if mark.has_recent_serious_mark():
			break
		mark = LoanApplicantGenerator.generate(finance_rng(SEED, 1000 + i))
	mark.applicant_name = "Hugo Valdez"
	LoanDeskManager.player_queue.clear()
	LoanDeskManager.player_queue.append_array([application, mark])
	var saved := LoanDeskManager.save_data()
	var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
	LoanDeskManager.reset()
	LoanDeskManager.load_data(json)
	assert_int(LoanDeskManager.player_queue.size()).is_equal(2)
	for i in 2:
		var saved_one: LoanApplication = [application, mark][i]
		var loaded_one := LoanDeskManager.player_queue[i]
		assert_dict(SaveGame.resource_to_dict(loaded_one)).is_equal(SaveGame.resource_to_dict(saved_one))
		assert_int(loaded_one.risk_assessment).is_equal(saved_one.calculate_risk_assessment())
	assert_bool(LoanDeskManager.player_queue[1].has_recent_serious_mark()).is_true()

	# Saved before credit reports: none of the report's fields.
	var old := SaveGame.resource_to_dict(mark)
	for field: String in old.keys():
		if field in ["credit_report_issued", "on_time_percent", "late_30_days", "late_60_days", "late_90_days", "utilization_percent", "open_accounts", "hard_inquiries", "collections", "months_since_collection", "months_since_bankruptcy"]:
			old.erase(field)
	LoanDeskManager.load_data({"career_seed": 5, "generated_count": 3, "player_queue": [old]})
	var loaded := LoanDeskManager.player_queue[0]
	assert_bool(loaded.credit_report_issued).is_true()
	assert_int(loaded.credit_report_points()).is_equal(0)
	assert_int(loaded.risk_assessment).is_equal(loaded.score_only_assessment())
	assert_bool(loaded.weak_points().has(Reason.CREDIT_HISTORY)).is_false()
