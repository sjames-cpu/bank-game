extends RefCounted
class_name LoanApplicantGenerator

## Builds loan applicants for the Loan Officer and the staff loan desks, so
## applications don't repeat and can't be learnt by heart (LoanDeskManager
## owns the career's seeds and the player's queue).
##
## How an applicant is built: first a target tier (TIER_WEIGHTS: about 40%
## LOW, 35% MEDIUM, 25% HIGH), then one of that tier's PROFILES, which says
## how many risk points each factor carries (LoanApplication.risk_points():
## credit band, total-DTI band, under two years in the job) and what drives a
## high DTI: the new loan itself (so "income too low for the amount" is a
## weak point too), or today's debts (so it isn't). A few profiles ask for
## more than the purpose's policy maximum. The values are then built to land
## there: a credit score in its band, a target total DTI in its band, an
## income, the new payment's share of it (from which the amount follows, at
## the purpose's real term and rate), housing, and existing debt payments
## making up the rest of the target, with a balance about 30-50 times the
## payment. About a third of applicants put one factor just inside a band
## edge (NEAR_EDGE_CHANCE), so the call isn't obvious.
##
## Some borderline applicants can afford too little for a counter-offer
## (LoanApplication.nothing_affordable(): Reject is their right call), mostly
## those whose debts already stretch them; they arise as they come.
##
## Every applicant is checked with the real formula before it's used
## (matches(): the tier, the exact risk points and the expected weak points);
## one that missed is built again from the same profile, so rounding never
## shifts the mix. The worksheet, grading, reasons and counter-offer rules are
## LoanApplication's, unchanged.
##
## Fair lending (bank policy): the name and look come from assign_identity(),
## with its own random generator, after and apart from every financial value,
## and nothing graded reads them. No age, sex, race, religion, national
## origin, marital status or any similar characteristic is generated or
## stored. loan_generator_test.gd checks the tiers don't depend on the name or
## look.

const Tier := LoanApplication.RiskTier
const Reason := LoanApplication.DenialReason

## What drives the payments. NONE: nothing (a payment within the guides, DTI
## within 43%). LOAN: the new payment is too big for the income (over 20% of
## it, 28% for a mortgage, or what takes today's payments past 43%): INCOME,
## and TOTAL_DTI when the DTI is over 43%. DEBTS: today's payments are
## already over 43% and the new loan is small: TOTAL_DTI only.
enum Driver { NONE, LOAN, DEBTS }

## The target mix of tiers, in percent.
const TIER_WEIGHTS: Dictionary = {Tier.LOW: 40, Tier.MEDIUM: 35, Tier.HIGH: 25}

## [tier, weight within the tier, credit points options, DTI points options,
## under two years, driver options, over the policy maximum]. Risk points:
## credit 0/1/3/5, total DTI 0/1/3/5, short employment 2; 0-2 LOW, 3-4 MEDIUM,
## 5+ HIGH. Each profile's weak points follow from it: credit points 3+ is
## CREDIT_SCORE, DTI points 3+ TOTAL_DTI, a LOAN driver INCOME, a short job
## EMPLOYMENT, over the maximum AMOUNT.
const PROFILES: Array = [
	# LOW: clean; one or two 1-point factors; or a new job with nothing else.
	[Tier.LOW, 12, [0], [0], false, [Driver.NONE], false],
	[Tier.LOW, 10, [1], [0], false, [Driver.NONE], false],
	[Tier.LOW, 8, [0], [1], false, [Driver.NONE], false],
	[Tier.LOW, 6, [1], [1], false, [Driver.NONE], false],
	[Tier.LOW, 4, [0], [0], true, [Driver.NONE], false],
	# MEDIUM: fair credit, alone or with a payment too big for the income; a
	# stretched DTI from the loan or from today's debts (which leaves nothing
	# worth counter-offering: LoanApplication.nothing_affordable()); a short
	# job with a 1-point factor; a big loan over the maximum.
	[Tier.MEDIUM, 6, [3], [0], false, [Driver.NONE], false],
	[Tier.MEDIUM, 4, [3], [1], false, [Driver.NONE], false],
	[Tier.MEDIUM, 5, [3], [0, 1], false, [Driver.LOAN], false],
	[Tier.MEDIUM, 7, [0, 1], [3], false, [Driver.LOAN], false],
	[Tier.MEDIUM, 4, [0, 1], [3], false, [Driver.DEBTS], false],
	[Tier.MEDIUM, 3, [1], [0], true, [Driver.NONE], false],
	[Tier.MEDIUM, 3, [0], [1], true, [Driver.NONE], false],
	[Tier.MEDIUM, 3, [0, 1], [3], false, [Driver.LOAN], true],
	# HIGH: poor credit; fair credit with a stretched DTI or a short job; a
	# stretched DTI and a short job; payments over half of income from debts or
	# from the loan; a loan over the maximum that's far too big.
	[Tier.HIGH, 6, [5], [0, 1], false, [Driver.NONE], false],
	[Tier.HIGH, 4, [3], [3], false, [Driver.LOAN, Driver.DEBTS], false],
	[Tier.HIGH, 3, [3], [0], true, [Driver.NONE], false],
	[Tier.HIGH, 3, [0, 1], [3], true, [Driver.LOAN, Driver.DEBTS], false],
	[Tier.HIGH, 4, [0, 1, 3], [5], false, [Driver.DEBTS], false],
	[Tier.HIGH, 3, [0, 1, 3], [5], false, [Driver.LOAN], false],
	[Tier.HIGH, 2, [0, 1], [5], false, [Driver.LOAN], true],
]

## Loan purposes and how often each is asked for. A Home loan's mortgage
## replaces the rent, so it never comes with a debts-driven DTI or over the
## maximum (PURPOSES_WITHOUT_HOME).
const PURPOSE_WEIGHTS: Dictionary = {"Auto": 30, "Home": 25, "Personal": 25, "Business": 20}

## Annual income range per purpose, in $500 steps (an applicant asked for
## more than the maximum has the income their payment implies instead).
const INCOME_RANGES: Dictionary = {
	"Auto": [30000.0, 160000.0],
	"Home": [55000.0, 300000.0],
	"Personal": [25000.0, 130000.0],
	"Business": [40000.0, 220000.0],
}
const INCOME_STEP: float = 500.0
const MIN_INCOME: float = 25000.0
const MAX_INCOME: float = 350000.0

## The smallest amount asked for per purpose, and the rounding of amounts
## (a request is a round figure).
const MIN_AMOUNTS: Dictionary = {"Auto": 5000.0, "Home": 60000.0, "Personal": 1000.0, "Business": 10000.0}
const AMOUNT_STEPS: Dictionary = {"Auto": 500.0, "Home": 5000.0, "Personal": 500.0, "Business": 1000.0}
## Requests over the policy maximum: a little over, never absurd.
const OVER_MAX_RANGES: Dictionary = {
	"Auto": [78000.0, 95000.0],
	"Personal": [52000.0, 70000.0],
	"Business": [260000.0, 350000.0],
}

## Credit score ranges for 0/1/3/5 risk points (Very Good+, Good, Fair,
## Poor; LoanApplication's bands).
const CREDIT_RANGES: Dictionary = {0: [740, 830], 1: [670, 739], 3: [580, 669], 5: [500, 579]}
## Total-DTI targets for 0/1/3/5 risk points, kept a little inside the
## bands' edges (36%, 43%, 50%) so rounding the dollars can't cross one.
const DTI_RANGES: Dictionary = {0: [0.20, 0.357], 1: [0.363, 0.427], 3: [0.433, 0.497], 5: [0.503, 0.60]}
## A debts-driven 43-50%: today's payments alone over 43%, plus a small loan.
const DEBTS_STRETCHED_MIN_DTI: float = 0.462
## Months in the job: under two years, or two years to twenty.
const SHORT_JOB_RANGE: Array[int] = [3, 23]
const STEADY_JOB_RANGE: Array[int] = [24, 240]

## Chance that one factor (credit, DTI or employment) sits just inside a band
## edge: credit within 9 points of it, total DTI within 1.5 points, or
## employment 18-23 or 24-30 months.
const NEAR_EDGE_CHANCE: float = 0.35
const CREDIT_EDGE_POINTS: int = 9
const DTI_EDGE_WIDTH: float = 0.015
const SHORT_JOB_EDGE_MIN: int = 18
const STEADY_JOB_EDGE_MAX: int = 30

## Rent or mortgage today, as a share of monthly income.
const MIN_HOUSING_SHARE: float = 0.10
const MAX_HOUSING_SHARE: float = 0.33
## Existing debt payments, as a share of monthly income, at most.
const MAX_DEBT_SHARE: float = 0.30
## Payments under this are rounded away (no debt at all).
const MIN_DEBT_PAYMENT: float = 20.0
## A debt's balance: its monthly payment is 2-3.5% of it, about what credit
## cards, car and student loans ask.
const DEBT_PAYMENT_RATE_RANGE: Array[float] = [0.02, 0.035]
const DEBT_BALANCE_STEP: float = 500.0

## Attempts at one profile before giving up on it (generate() then uses a
## sample of the same tier; loan_generator_test.gd checks it never has to).
const MAX_ATTEMPTS: int = 200

## Generated names: a first name and a surname, chosen apart from everything
## else (assign_identity()).
const FIRST_NAMES: Array[String] = [
	"Adrian", "Beatriz", "Caleb", "Dana", "Elijah", "Farah", "Gabriel", "Helena",
	"Isaac", "Jada", "Kai", "Lucia", "Malik", "Nora", "Oscar", "Paloma",
	"Quentin", "Rosa", "Simon", "Tara", "Uriel", "Vera", "Wade", "Ximena",
	"Yusuf", "Zara", "Amara", "Bruno", "Cora", "Dev", "Elif", "Finn",
	"Gemma", "Hugo", "Iris", "Jonah", "Kira", "Leon", "Maya", "Nikhil",
	"Olga", "Pablo", "Rhea", "Soren", "Thea", "Victor", "Wen", "Yara",
]
const LAST_NAMES: Array[String] = [
	"Abernathy", "Bakshi", "Castillo", "Dalton", "Eriksen", "Ferreira", "Goldberg", "Hollis",
	"Ibarra", "Jensen", "Kaur", "Lindgren", "Mbeki", "Navarro", "Oyelaran", "Pereira",
	"Quinlan", "Rasmussen", "Stewart", "Takahashi", "Underwood", "Valdez", "Walsh", "Xu",
	"Yilmaz", "Zielinski", "Ashford", "Banerjee", "Carrington", "Delacroix", "Esposito", "Fitzgerald",
	"Gutierrez", "Hayashi", "Iverson", "Jovanovic", "Kimura", "Lachance", "Mwangi", "Nakamura",
	"Okonkwo", "Palmer", "Rojas", "Sandoval", "Thornton", "Vasquez", "Whitman", "Young",
]
const MAX_NAME_ATTEMPTS: int = 500

## One applicant's plan: the tier, each factor's risk points and what drives
## the DTI (see PROFILES).
class Profile:
	var tier: LoanApplication.RiskTier = LoanApplication.RiskTier.LOW
	var credit_points: int = 0
	var dti_points: int = 0
	var short_job: bool = false
	var driver: LoanApplicantGenerator.Driver = LoanApplicantGenerator.Driver.NONE
	var over_max: bool = false

	func risk_points() -> int:
		return credit_points + dti_points + (2 if short_job else 0)

# --- generating ----------------------------------------------------------------------

## A new applicant's finances from `rng` (no name or look yet: see
## assign_identity()). Its risk_tier is the tier it was built for, and
## risk_assessment is worked out.
static func generate(rng: RandomNumberGenerator) -> LoanApplication:
	var profile := pick_profile(rng)
	var application := build(rng, profile)
	if application == null:
		application = _fallback(profile.tier)
	application.risk_assessment = application.calculate_risk_assessment()
	return application

## A tier by TIER_WEIGHTS, then one of its PROFILES by weight, with each
## option picked.
static func pick_profile(rng: RandomNumberGenerator) -> Profile:
	var tiers: Array[int] = []
	var tier_weights: Array[int] = []
	for tier: int in TIER_WEIGHTS:
		tiers.append(tier)
		tier_weights.append(TIER_WEIGHTS[tier])
	var tier := tiers[_weighted(rng, tier_weights)]
	var rows: Array[Array] = []
	var weights: Array[int] = []
	for row: Array in PROFILES:
		if row[0] == tier:
			rows.append(row)
			weights.append(row[1])
	var chosen := rows[_weighted(rng, weights)]
	var credit_options: Array = chosen[2]
	var dti_options: Array = chosen[3]
	var short_job: bool = chosen[4]
	var driver_options: Array = chosen[5]
	var over_max: bool = chosen[6]
	var profile := Profile.new()
	profile.tier = tier as LoanApplication.RiskTier
	profile.credit_points = _pick(rng, credit_options)
	profile.dti_points = _pick(rng, dti_options)
	profile.short_job = short_job
	profile.driver = _pick(rng, driver_options) as Driver
	profile.over_max = over_max
	return profile

## An applicant matching `profile` (see matches()), or null when MAX_ATTEMPTS
## all missed.
static func build(rng: RandomNumberGenerator, profile: Profile) -> LoanApplication:
	for attempt in MAX_ATTEMPTS:
		var application := _attempt(rng, profile)
		if application != null and matches(application, profile):
			return application
	return null

## Does `application` land where `profile` meant, by the real formula: the
## tier, the exact risk points, and the weak points it was built for?
static func matches(application: LoanApplication, profile: Profile) -> bool:
	if application.calculate_risk_assessment() != profile.tier:
		return false
	if application.risk_points() != profile.risk_points():
		return false
	var weak := application.weak_points()
	# A borderline applicant with nothing worth counter-offering is denied
	# for their payments too (LoanApplication.weak_points()).
	var payments_reason := application.nothing_affordable() and profile.driver != Driver.LOAN
	return weak.has(Reason.CREDIT_SCORE) == (profile.credit_points >= 3) \
		and weak.has(Reason.TOTAL_DTI) == (profile.dti_points >= 3 or payments_reason) \
		and weak.has(Reason.INCOME) == (profile.driver == Driver.LOAN) \
		and weak.has(Reason.EMPLOYMENT) == profile.short_job \
		and weak.has(Reason.AMOUNT) == profile.over_max

static func _attempt(rng: RandomNumberGenerator, profile: Profile) -> LoanApplication:
	# Which factor, if any, sits near its band edge: 0 credit, 1 DTI, 2 job.
	var edge := -1
	if rng.randf() < NEAR_EDGE_CHANCE:
		edge = rng.randi_range(0, 2)
	var application := LoanApplication.new()
	application.loan_purpose = _pick_purpose(rng, profile)
	application.risk_tier = profile.tier
	application.credit_score = _credit_score(rng, profile.credit_points, edge == 0)
	application.employment_months = _employment(rng, profile.short_job, edge == 2)
	var target := _target_dti(rng, profile, edge == 1)
	var home := application.replaces_housing()
	var share_range := _payment_share_range(profile, target, home)
	if share_range.y < share_range.x:
		return null
	var share := rng.randf_range(share_range.x, share_range.y)
	var purpose := application.loan_purpose
	var step: float = AMOUNT_STEPS[purpose]

	# The amount and the income: over the maximum, the amount first and the
	# income its payment implies; otherwise the income, then the amount whose
	# payment is that share of it.
	if profile.over_max:
		var over: Array = OVER_MAX_RANGES[purpose]
		var over_low: float = over[0]
		var over_high: float = over[1]
		application.requested_amount = _stepped(rng, over_low, over_high, step)
		var payment := application.new_loan_payment()
		application.annual_income = roundf(payment / share * 12.0 / 1000.0) * 1000.0
	else:
		var incomes: Array = INCOME_RANGES[purpose]
		var income_low: float = incomes[0]
		var income_high: float = incomes[1]
		application.annual_income = _stepped(rng, income_low, income_high, INCOME_STEP)
		var principal := LoanApplication.principal_for_payment(share * application.monthly_income(), application.annual_rate(), application.term_months())
		application.requested_amount = floorf(principal / step) * step
		if application.requested_amount < MIN_AMOUNTS[purpose] or application.requested_amount > application.policy_maximum():
			return null
	if application.annual_income < MIN_INCOME or application.annual_income > MAX_INCOME:
		return null

	var monthly := application.monthly_income()
	var new_payment := application.new_loan_payment()
	var new_share := new_payment / monthly
	var debt_payments := 0.0
	if home:
		# The mortgage is the housing payment; the debts make up the rest.
		debt_payments = _rounded(target * monthly - new_payment, 5.0)
		if debt_payments > MAX_DEBT_SHARE * monthly:
			return null
		# Today's rent or mortgage, which the new one replaces: no more than
		# it (or a third of income). When the loan should be what pushes total
		# DTI past 43%, today's payments stay within it.
		var rent_max := minf(new_share, MAX_HOUSING_SHARE)
		if profile.driver == Driver.LOAN and new_share <= LoanApplication.HOME_PAYMENT_SHARE_LIMIT:
			rent_max = minf(rent_max, LoanApplication.STRETCHED_DTI - debt_payments / monthly - 0.01)
		if rent_max < MIN_HOUSING_SHARE:
			return null
		application.monthly_housing_payment = _rounded(rng.randf_range(MIN_HOUSING_SHARE, rent_max) * monthly, 25.0)
	else:
		var rest := target - new_share
		var housing_min := maxf(MIN_HOUSING_SHARE, rest - MAX_DEBT_SHARE)
		var housing_max := minf(MAX_HOUSING_SHARE, rest)
		if housing_max < housing_min:
			return null
		application.monthly_housing_payment = _rounded(rng.randf_range(housing_min, housing_max) * monthly, 25.0)
		debt_payments = _rounded(target * monthly - application.monthly_housing_payment - new_payment, 5.0)
	if debt_payments < 0.0:
		return null
	if debt_payments < MIN_DEBT_PAYMENT:
		debt_payments = 0.0
	application.monthly_debt_payments = debt_payments
	if debt_payments > 0.0:
		var payment_rate := rng.randf_range(DEBT_PAYMENT_RATE_RANGE[0], DEBT_PAYMENT_RATE_RANGE[1])
		application.existing_debt = maxf(DEBT_BALANCE_STEP, _rounded(debt_payments / payment_rate, DEBT_BALANCE_STEP))
	return application

## The new payment's share of monthly income, as a [min, max] range, for the
## target total DTI. Empty (max < min) when the target can't be reached.
static func _payment_share_range(profile: Profile, target: float, home: bool) -> Vector2:
	var stretched := LoanApplication.STRETCHED_DTI
	if home:
		match profile.driver:
			Driver.LOAN:
				if profile.dti_points <= 1:
					# Over the 28% guide, total DTI still within 43%.
					return Vector2(0.29, minf(0.38, target))
				if profile.dti_points >= 5:
					# Over the 28% guide on its own.
					return Vector2(0.29, minf(0.45, target))
				return Vector2(maxf(0.20, target - 0.15), minf(0.38, target))
			_:
				# Within the 28% guide, with up to 15% of income in other debts.
				return Vector2(maxf(0.12, target - 0.15), minf(0.27, target))
	match profile.driver:
		Driver.LOAN:
			if profile.dti_points <= 1 or profile.dti_points >= 5:
				# Over the 20% guide on its own.
				return Vector2(0.215, minf(0.42, target - MIN_HOUSING_SHARE))
			# What takes today's payments past 43%.
			return Vector2(maxf(0.06, target - stretched + 0.008), minf(0.30, target - MIN_HOUSING_SHARE))
		Driver.DEBTS:
			# Small, with today's payments already over 43%.
			return Vector2(0.02, minf(0.12, target - stretched - 0.008))
		_:
			return Vector2(0.03, 0.15)

static func _pick_purpose(rng: RandomNumberGenerator, profile: Profile) -> String:
	var no_home := profile.over_max or profile.driver == Driver.DEBTS
	var purposes: Array[String] = []
	var weights: Array[int] = []
	for purpose: String in PURPOSE_WEIGHTS:
		if no_home and purpose == LoanApplication.HOME_PURPOSE:
			continue
		purposes.append(purpose)
		weights.append(PURPOSE_WEIGHTS[purpose])
	return purposes[_weighted(rng, weights)]

static func _credit_score(rng: RandomNumberGenerator, points: int, near_edge: bool) -> int:
	var band: Array = CREDIT_RANGES[points]
	var low: int = band[0]
	var high: int = band[1]
	if near_edge:
		# The top band has only its lower edge, the bottom band its upper one.
		var lower := points != 5 and (points == 0 or rng.randf() < 0.5)
		if lower:
			high = low + CREDIT_EDGE_POINTS
		else:
			low = high - CREDIT_EDGE_POINTS
	return rng.randi_range(low, high)

static func _target_dti(rng: RandomNumberGenerator, profile: Profile, near_edge: bool) -> float:
	var band: Array = DTI_RANGES[profile.dti_points]
	var low: float = band[0]
	var high: float = band[1]
	var debts_stretched := profile.dti_points == 3 and profile.driver == Driver.DEBTS
	if debts_stretched:
		low = DEBTS_STRETCHED_MIN_DTI
	if near_edge:
		var lower := profile.dti_points != 0 and not debts_stretched and (profile.dti_points == 5 or rng.randf() < 0.5)
		if lower:
			high = low + DTI_EDGE_WIDTH
		else:
			low = high - DTI_EDGE_WIDTH
	return rng.randf_range(low, high)

static func _employment(rng: RandomNumberGenerator, short_job: bool, near_edge: bool) -> int:
	if short_job:
		return rng.randi_range(SHORT_JOB_EDGE_MIN if near_edge else SHORT_JOB_RANGE[0], SHORT_JOB_RANGE[1])
	return rng.randi_range(STEADY_JOB_RANGE[0], STEADY_JOB_EDGE_MAX if near_edge else STEADY_JOB_RANGE[1])

## A sample of `tier`, for the (never seen) case of a profile that can't be
## built.
static func _fallback(tier: LoanApplication.RiskTier) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.risk_tier == tier:
			return application
	return LoanApplicationsData.get_applications()[0]

# --- documents -----------------------------------------------------------------------

## Bad IDs come at the teller window's rate and mix (KycPolicy: about 1 in 7;
## expired 3, name mismatch 2, wrong photo 2, none 1).
const ID_PROBLEM_CHANCE: float = KycPolicy.ID_PROBLEM_CHANCE
## Share of applicants with a problem in their other documents, and how it's
## picked (relative weights): income stated higher than the pay stub and
## statement show; a pay stub in someone else's name; no pay stub; no
## statement. With 0.10 and 4/2/2/2: 4%, 2%, 2% and 2% of applicants. With a
## bad ID as well, about 23% of applicants don't check out.
const DOC_PROBLEM_CHANCE: float = 0.10
const DOC_PROBLEM_WEIGHTS: Dictionary = {
	LoanApplication.DocProblem.OVERSTATED_INCOME: 4,
	LoanApplication.DocProblem.STUB_NAME: 2,
	LoanApplication.DocProblem.MISSING_STUB: 2,
	LoanApplication.DocProblem.MISSING_STATEMENT: 2,
}
## An overstated income: the pay stub shows 60-85% of what was stated.
const OVERSTATED_SHARE_RANGE: Array[float] = [0.60, 0.85]
## Net pay (after tax and deductions) as a share of gross.
const NET_SHARE_RANGE: Array[float] = [0.72, 0.80]
## Fictional employers.
const EMPLOYERS: Array[String] = [
	"Harbor Street Clinic", "Northgate Logistics", "Maple & Finch Accounting", "Riverbend Schools",
	"Copperline Manufacturing", "Summit Grocers", "Brightwater Utilities", "Elmwood Hospitality",
	"Tidewell Software", "Granite Peak Construction", "Lakeside Insurance", "Oakridge Auto Group",
]

## Hands `application` its documents, from `rng` alone (its own generator,
## LoanDeskManager): first whether the ID and the other documents have a
## problem (so the rolls never depend on the finances or the identity), then
## the documents themselves. The ID is issued on `today` (epoch day), with no
## date of birth. `clean`: no problems (the teaching cases).
static func issue_documents(application: LoanApplication, rng: RandomNumberGenerator, today: int, clean: bool = false) -> void:
	var id_problem := KycPolicy.roll_problem(rng, 0.0 if clean else ID_PROBLEM_CHANCE)
	var doc_problem := LoanApplication.DocProblem.NONE
	if not clean and rng.randf() < DOC_PROBLEM_CHANCE:
		var weights: Array[int] = []
		var problems: Array[int] = []
		for problem: int in DOC_PROBLEM_WEIGHTS:
			problems.append(problem)
			weights.append(DOC_PROBLEM_WEIGHTS[problem])
		doc_problem = problems[_weighted(rng, weights)] as LoanApplication.DocProblem
	application.id_problem = id_problem
	application.doc_problem = doc_problem

	var card := KycPolicy.issue_card(rng, application.applicant_name, application.applicant_look, today, id_problem, CustomerNPC.CUSTOMER_FRAME_SETS.size(), false)
	application.id_presented = card.presented
	application.id_holder_name = card.holder_name
	application.id_number = card.id_number
	application.id_expiry_date = card.expiry_date
	application.id_portrait_look = card.portrait_look

	var gross := roundf(application.annual_income / 12.0)
	if doc_problem == LoanApplication.DocProblem.OVERSTATED_INCOME:
		gross = roundf(gross * rng.randf_range(OVERSTATED_SHARE_RANGE[0], OVERSTATED_SHARE_RANGE[1]))
	var net := roundf(gross * rng.randf_range(NET_SHARE_RANGE[0], NET_SHARE_RANGE[1]))
	var stub_name := application.applicant_name
	if doc_problem == LoanApplication.DocProblem.STUB_NAME:
		stub_name = KycPolicy.mismatched_name(rng, application.applicant_name)
	var employer := EMPLOYERS[rng.randi_range(0, EMPLOYERS.size() - 1)]

	application.has_pay_stub = doc_problem != LoanApplication.DocProblem.MISSING_STUB
	application.stub_name = stub_name if application.has_pay_stub else ""
	application.stub_employer = employer if application.has_pay_stub else ""
	application.stub_monthly_gross = gross if application.has_pay_stub else 0.0
	application.stub_monthly_net = net if application.has_pay_stub else 0.0
	# Paid twice a month: last month's net pay in two deposits.
	application.has_statement = doc_problem != LoanApplication.DocProblem.MISSING_STATEMENT
	application.statement_name = application.applicant_name if application.has_statement else ""
	var first_half := floori(net / 2.0)
	application.statement_deposits = PackedInt32Array([first_half, int(net) - first_half]) if application.has_statement else PackedInt32Array()
	application.documents_issued = true

# --- identity ------------------------------------------------------------------------

## Names a generated applicant and gives them a look, from `rng` alone: never
## from, or before, anything financial. `taken` holds names to avoid (today's
## applicants: LoanDeskManager); reserved_names() are always avoided.
static func assign_identity(application: LoanApplication, rng: RandomNumberGenerator, taken: Dictionary) -> void:
	var reserved := reserved_names()
	var applicant_name := ""
	for attempt in MAX_NAME_ATTEMPTS:
		applicant_name = "%s %s" % [FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)], LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]]
		if not taken.has(applicant_name) and not reserved.has(applicant_name):
			break
	application.applicant_name = applicant_name
	application.applicant_look = rng.randi_range(0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)

static var _reserved: Dictionary = {}

## Names a generated applicant never gets: the samples' (the teaching cases),
## and every staff member's and job candidate's, so an applicant never reads
## as someone else.
static func reserved_names() -> Dictionary:
	if _reserved.is_empty():
		for application in LoanApplicationsData.get_applications():
			_reserved[application.applicant_name] = true
		for member in StaffRosterData.get_staff():
			_reserved[member.staff_name] = true
		for candidate_name in StaffCandidatesData.CANDIDATE_NAMES:
			_reserved[candidate_name] = true
	return _reserved

# --- helpers -------------------------------------------------------------------------

## An index into `weights`, chosen in proportion to them.
static func _weighted(rng: RandomNumberGenerator, weights: Array[int]) -> int:
	var total := 0
	for weight in weights:
		total += weight
	var roll := rng.randi_range(1, total)
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0:
			return i
	return weights.size() - 1

static func _pick(rng: RandomNumberGenerator, options: Array) -> int:
	var value: int = options[rng.randi_range(0, options.size() - 1)]
	return value

## A random multiple of `step` from `low` to `high`.
static func _stepped(rng: RandomNumberGenerator, low: float, high: float, step: float) -> float:
	return rng.randi_range(ceili(low / step), floori(high / step)) * step

static func _rounded(value: float, step: float) -> float:
	return roundf(value / step) * step
