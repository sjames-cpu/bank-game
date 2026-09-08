extends RefCounted
class_name LoanApplicationsData

## Static provider for sample loan applications (Phase 4a). Kept separate
## from LoanApplication (the data shape) so the actual application
## content can grow independently of it, mirroring
## InterviewQuestionsData.

static func get_applications() -> Array[LoanApplication]:
	return [
		_application("Maria Chen", 15000.0, 780, 95000.0, 8000.0, "Auto", LoanApplication.RiskTier.LOW),
		_application("David Okafor", 250000.0, 810, 180000.0, 40000.0, "Home", LoanApplication.RiskTier.LOW),
		_application("Elena Petrova", 180000.0, 745, 110000.0, 30000.0, "Home", LoanApplication.RiskTier.LOW),
		_application("Priya Sharma", 8000.0, 650, 52000.0, 12000.0, "Personal", LoanApplication.RiskTier.MEDIUM),
		_application("Angela Reyes", 12000.0, 710, 48000.0, 20000.0, "Auto", LoanApplication.RiskTier.MEDIUM),
		_application("Jamal Green", 60000.0, 620, 58000.0, 27000.0, "Business", LoanApplication.RiskTier.MEDIUM),
		_application("Noah Kim", 10000.0, 695, 65000.0, 10000.0, "Personal", LoanApplication.RiskTier.MEDIUM),
		_application("Tom Whitfield", 500000.0, 590, 60000.0, 45000.0, "Business", LoanApplication.RiskTier.HIGH),
		_application("Marcus Webb", 3000.0, 480, 22000.0, 15000.0, "Personal", LoanApplication.RiskTier.HIGH),
		_application("Sophie Laurent", 20000.0, 555, 40000.0, 18000.0, "Auto", LoanApplication.RiskTier.HIGH),
	]

static func _application(applicant_name: String, requested_amount: float, credit_score: int, annual_income: float, existing_debt: float, loan_purpose: String, risk_tier: LoanApplication.RiskTier) -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = applicant_name
	application.requested_amount = requested_amount
	application.credit_score = credit_score
	application.annual_income = annual_income
	application.existing_debt = existing_debt
	application.loan_purpose = loan_purpose
	application.risk_tier = risk_tier
	return application
