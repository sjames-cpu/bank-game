extends RefCounted
class_name LoanApplicationsData

## Static provider for the hand-written sample loan applications (Phase 4a).
## Kept separate from LoanApplication (the data shape), mirroring
## InterviewQuestionsData. Since the generator (LoanApplicantGenerator) the
## player sees three of them once, as the first shift's teaching cases
## (teaching_cases()); the rest are reference cases for the tests.

## Three clearly safe, four borderline and three clearly risky applicants.
## Each row's comment gives its worksheet (the new payment at the purpose's
## term and the rate for its credit band, LoanApplication.RATE_TABLE;
## front-end and total DTI) and why it lands on its tier;
## loan_application_test.gd checks every calculate_risk_assessment() matches
## risk_tier. Debt payments run about 2-3% of each balance a month.
##
## Each has a credit report in line with its score that adds no risk points
## (nothing in the last two years the policy counts, and no score under 670
## with a clean recent history), and collateral at a healthy loan-to-value
## (cars 75-88%, homes 77-80% with appraisals at or over the price, Jamal
## Green's equipment 71%; the personal loans and Tom Whitfield's business
## loan unsecured), so the samples teach the worksheet first.
static func get_applications() -> Array[LoanApplication]:
	var applications := _samples()
	for i in applications.size():
		applications[i].applicant_look = SAMPLE_LOOKS[i % SAMPLE_LOOKS.size()]
	return applications

static func _samples() -> Array[LoanApplication]:
	return [
		# 6.25% (very good credit) · payment $292 · front 20.2% · total 25.9%.
		# Six years in the job: safe.
		_collateral(_report(_application("Maria Chen", 15000.0, 780, 95000.0, 1600.0, 8000.0, 160.0, 72, "Auto", LoanApplication.RiskTier.LOW),
			100, 0, 0, 0, 12, 6, 1), LoanApplication.Collateral.VEHICLE, 20000.0, 20000.0),
		# 6.25% (excellent) · mortgage $2,463 replaces $2,400 rent · front
		# 16.4% · total 23.1%.
		_collateral(_report(_application("David Okafor", 400000.0, 810, 180000.0, 2400.0, 40000.0, 1000.0, 108, "Home", LoanApplication.RiskTier.LOW),
			100, 0, 0, 0, 6, 9, 0), LoanApplication.Collateral.HOUSE, 520000.0, 525000.0),
		# 6.50% (very good) · mortgage $1,959 replaces $1,500 rent · front 21.4%
		# · total 36.6%: just past healthy, still safe with very good credit
		# (asks a little over the $300,600 it could carry at 36%).
		_collateral(_report(_application("Elena Petrova", 310000.0, 745, 110000.0, 1500.0, 45000.0, 1400.0, 48, "Home", LoanApplication.RiskTier.LOW),
			99, 1, 0, 0, 24, 7, 1), LoanApplication.Collateral.HOUSE, 390000.0, 395000.0),
		# 19.00% (fair) · payment $293 · front 24.2% · total 39.3%. Fair credit
		# with a few late payments and an old collection: borderline.
		_collateral(_report(_application("Priya Sharma", 8000.0, 650, 52000.0, 1050.0, 12000.0, 360.0, 60, "Personal", LoanApplication.RiskTier.MEDIUM),
			93, 2, 1, 0, 58, 5, 2, 1, 38), LoanApplication.Collateral.NONE, 0.0, 0.0),
		# 7.00% (good) · payment $594 · front 23.8% · total 44.9%: today's
		# payments are 30%, the new car pushes it past 43%. A smaller loan
		# ($12,100) fits.
		_collateral(_report(_application("Angela Reyes", 30000.0, 710, 48000.0, 950.0, 10000.0, 250.0, 36, "Auto", LoanApplication.RiskTier.MEDIUM),
			97, 1, 0, 0, 41, 6, 2), LoanApplication.Collateral.VEHICLE, 34000.0, 34000.0),
		# 10.75% (fair) · payment $818 · front 21.7% · total 40.3%. Seven years
		# running the business: borderline.
		_collateral(_report(_application("Jamal Green", 60000.0, 620, 72000.0, 1300.0, 15000.0, 300.0, 84, "Business", LoanApplication.RiskTier.MEDIUM),
			91, 3, 1, 0, 64, 8, 1, 1, 52), LoanApplication.Collateral.EQUIPMENT, 0.0, 85000.0),
		# 14.00% (good) · payment $342 · front 25.8% · total 34.9%: healthy, but
		# ten months in a new job.
		_collateral(_report(_application("Noah Kim", 10000.0, 695, 65000.0, 1400.0, 10000.0, 150.0, 10, "Personal", LoanApplication.RiskTier.MEDIUM),
			98, 0, 0, 0, 33, 3, 3), LoanApplication.Collateral.NONE, 0.0, 0.0),
		# 10.75% (fair) · payment $6,817 on $5,000 a month · total 193.3%, and
		# twice the $250,000 business maximum.
		_collateral(_report(_application("Tom Whitfield", 500000.0, 590, 60000.0, 1500.0, 45000.0, 1350.0, 36, "Business", LoanApplication.RiskTier.HIGH),
			90, 3, 2, 0, 71, 9, 4), LoanApplication.Collateral.NONE, 0.0, 0.0),
		# 26.00% (poor) · payment $121 · front 38.2% · total 69.3%: today's
		# payments already take 63% of income, and poor credit after a
		# bankruptcy.
		_collateral(_report(_application("Marcus Webb", 3000.0, 480, 22000.0, 700.0, 15000.0, 450.0, 48, "Personal", LoanApplication.RiskTier.HIGH),
			81, 5, 2, 0, 74, 4, 3, 0, 0, 40), LoanApplication.Collateral.NONE, 0.0, 0.0),
		# 14.50% (poor) · payment $424 · front 25.5% · total 42.7%: affordable,
		# but poor credit.
		_collateral(_report(_application("Sophie Laurent", 18000.0, 555, 40000.0, 850.0, 5000.0, 150.0, 30, "Auto", LoanApplication.RiskTier.HIGH),
			86, 4, 2, 0, 69, 5, 2, 2, 30), LoanApplication.Collateral.VEHICLE, 21000.0, 21000.0),
	]

## Hand-written collateral on `application`: a car (its price is its value),
## a home's purchase price and appraisal, business equipment, or none. Every
## sample's LTV is healthy (no LTV points, no mortgage insurance).
static func _collateral(application: LoanApplication, kind: LoanApplication.Collateral, price: float, value: float) -> LoanApplication:
	application.collateral_issued = true
	application.collateral_kind = kind
	application.purchase_price = price
	application.collateral_value = value
	return application

## A hand-written credit report on `application` (see CreditReport).
static func _report(application: LoanApplication, on_time: int, late_30: int, late_60: int, late_90: int, utilization: int, accounts: int, inquiries: int, collections: int = 0, since_collection: int = 0, since_bankruptcy: int = 0) -> LoanApplication:
	application.credit_report_issued = true
	application.on_time_percent = on_time
	application.late_30_days = late_30
	application.late_60_days = late_60
	application.late_90_days = late_90
	application.utilization_percent = utilization
	application.open_accounts = accounts
	application.hard_inquiries = inquiries
	application.collections = collections
	application.months_since_collection = since_collection
	application.months_since_bankruptcy = since_bankruptcy
	return application

## The player's first Loan Officer shift of a career (LoanDeskManager): one
## of each tier, building from clear to borderline. Maria Chen is as safe as
## an application gets (very good credit, 26% total DTI, six years in the
## job); Marcus Webb is plainly risky on two counts (poor credit, and today's
## payments already take 63% of income); Angela Reyes is the borderline one,
## good on paper until the new car pushes total DTI past 43%, so the right
## call is a counter-offer at the $12,100 the worksheet says she can carry.
const TEACHING_CASE_NAMES: Array[String] = ["Maria Chen", "Marcus Webb", "Angela Reyes"]

static func teaching_cases() -> Array[LoanApplication]:
	var cases: Array[LoanApplication] = []
	var samples := get_applications()
	for applicant_name in TEACHING_CASE_NAMES:
		for application in samples:
			if application.applicant_name == applicant_name:
				cases.append(application)
	return cases

## One of the first Loan Officer shift's three teaching cases (the review
## screen offers no request for more documents on these).
static func is_teaching_case(applicant_name: String) -> bool:
	return TEACHING_CASE_NAMES.has(applicant_name)

static func is_sample_name(applicant_name: String) -> bool:
	for application in _samples():
		if application.applicant_name == applicant_name:
			return true
	return false

## Portraits for the samples, in order (CustomerNPC.CUSTOMER_FRAME_SETS),
## spread over the three designs and their recolours.
const SAMPLE_LOOKS: Array[int] = [0, 4, 8, 1, 5, 9, 2, 6, 10, 3]

static func _application(applicant_name: String, requested_amount: float, credit_score: int, annual_income: float, monthly_housing_payment: float, existing_debt: float, monthly_debt_payments: float, employment_months: int, loan_purpose: String, risk_tier: LoanApplication.RiskTier) -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = applicant_name
	application.requested_amount = requested_amount
	application.credit_score = credit_score
	application.annual_income = annual_income
	application.monthly_housing_payment = monthly_housing_payment
	application.existing_debt = existing_debt
	application.monthly_debt_payments = monthly_debt_payments
	application.employment_months = employment_months
	application.loan_purpose = loan_purpose
	application.risk_tier = risk_tier
	return application
