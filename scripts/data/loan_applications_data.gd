extends RefCounted
class_name LoanApplicationsData

## Static provider for sample loan applications (Phase 4a). Kept separate
## from LoanApplication (the data shape) so the actual application
## content can grow independently of it, mirroring
## InterviewQuestionsData.

## Three clearly safe, four borderline and three clearly risky applicants.
## Each row's comment gives its worksheet (the new payment at the purpose's
## term and rate, front-end and total DTI) and why it lands on its tier;
## loan_application_test.gd checks every calculate_risk_assessment() matches
## risk_tier. Debt payments run about 2-3% of each balance a month.
static func get_applications() -> Array[LoanApplication]:
	return [
		# Payment $297 · front 20.2% · total 26.0%. Very good credit, six years
		# in the job: safe.
		_application("Maria Chen", 15000.0, 780, 95000.0, 1600.0, 8000.0, 160.0, 72, "Auto", LoanApplication.RiskTier.LOW),
		# Mortgage $2,528 replaces $2,400 rent · front 16.9% · total 23.5%.
		_application("David Okafor", 400000.0, 810, 180000.0, 2400.0, 40000.0, 1000.0, 108, "Home", LoanApplication.RiskTier.LOW),
		# Mortgage $1,959 replaces $1,500 rent · front 21.4% · total 36.6%: just
		# past healthy, still safe with very good credit (asks a little over the
		# $300,600 it could carry at 36%).
		_application("Elena Petrova", 310000.0, 745, 110000.0, 1500.0, 45000.0, 1400.0, 48, "Home", LoanApplication.RiskTier.LOW),
		# Payment $266 · front 24.2% · total 38.7%. Fair credit: borderline.
		_application("Priya Sharma", 8000.0, 650, 52000.0, 1050.0, 12000.0, 360.0, 60, "Personal", LoanApplication.RiskTier.MEDIUM),
		# Payment $594 · front 23.8% · total 44.9%: today's payments are 30%, the
		# new car pushes it past 43%. A smaller loan ($12,100) fits.
		_application("Angela Reyes", 30000.0, 710, 48000.0, 950.0, 10000.0, 250.0, 36, "Auto", LoanApplication.RiskTier.MEDIUM),
		# Payment $760 · front 21.7% · total 39.3%. Fair credit, seven years
		# running the business: borderline.
		_application("Jamal Green", 60000.0, 620, 72000.0, 1300.0, 15000.0, 300.0, 84, "Business", LoanApplication.RiskTier.MEDIUM),
		# Payment $332 · front 25.8% · total 34.7%: healthy, but ten months in a
		# new job.
		_application("Noah Kim", 10000.0, 695, 65000.0, 1400.0, 10000.0, 150.0, 10, "Personal", LoanApplication.RiskTier.MEDIUM),
		# Payment $6,334 on $5,000 a month · total 183.7%, fair credit, and twice
		# the $250,000 business maximum.
		_application("Tom Whitfield", 500000.0, 590, 60000.0, 1500.0, 45000.0, 1350.0, 36, "Business", LoanApplication.RiskTier.HIGH),
		# Payment $100 · front 38.2% · total 68.2%: today's payments already
		# take 63% of income, and poor credit.
		_application("Marcus Webb", 3000.0, 480, 22000.0, 700.0, 15000.0, 450.0, 48, "Personal", LoanApplication.RiskTier.HIGH),
		# Payment $396 · front 25.5% · total 41.9%: affordable, but poor credit.
		_application("Sophie Laurent", 20000.0, 555, 40000.0, 850.0, 5000.0, 150.0, 30, "Auto", LoanApplication.RiskTier.HIGH),
	]

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
