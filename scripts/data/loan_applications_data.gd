extends RefCounted
class_name LoanApplicationsData

## Static provider for sample loan applications (Phase 4a). Kept separate
## from LoanApplication (the data shape) so the actual application
## content can grow independently of it, mirroring
## InterviewQuestionsData.

## monthly_debt_payments is 1.5-3% of each existing_debt balance per month,
## varied by applicant (per-row comments give the rate and resulting
## monthly DTI): mostly 2-2.5% for typical auto/home-adjacent debt, 3% for
## the shorter-term or higher-interest debt the riskier applicants carry.
static func get_applications() -> Array[LoanApplication]:
	return [
		# Payment: 2.0% of balance -> DTI 2.0%
		_application("Maria Chen", 15000.0, 780, 95000.0, 8000.0, 160.0, "Auto", LoanApplication.RiskTier.LOW),
		# 2.5% -> DTI 6.7%
		_application("David Okafor", 250000.0, 810, 180000.0, 40000.0, 1000.0, "Home", LoanApplication.RiskTier.LOW),
		# 2.0% -> DTI 6.5%
		_application("Elena Petrova", 180000.0, 745, 110000.0, 30000.0, 600.0, "Home", LoanApplication.RiskTier.LOW),
		# 3.0% -> DTI 8.3%
		_application("Priya Sharma", 8000.0, 650, 52000.0, 12000.0, 360.0, "Personal", LoanApplication.RiskTier.MEDIUM),
		# 2.5% -> DTI 12.5%
		_application("Angela Reyes", 12000.0, 710, 48000.0, 20000.0, 500.0, "Auto", LoanApplication.RiskTier.MEDIUM),
		# 2.5% -> DTI 14.0%
		_application("Jamal Green", 60000.0, 620, 58000.0, 27000.0, 675.0, "Business", LoanApplication.RiskTier.MEDIUM),
		# 1.5% -> DTI 2.8%
		_application("Noah Kim", 10000.0, 695, 65000.0, 10000.0, 150.0, "Personal", LoanApplication.RiskTier.MEDIUM),
		# 3.0% -> DTI 27.0%
		_application("Tom Whitfield", 500000.0, 590, 60000.0, 45000.0, 1350.0, "Business", LoanApplication.RiskTier.HIGH),
		# 3.0% -> DTI 24.5%
		_application("Marcus Webb", 3000.0, 480, 22000.0, 15000.0, 450.0, "Personal", LoanApplication.RiskTier.HIGH),
		# 3.0% -> DTI 16.2%
		_application("Sophie Laurent", 20000.0, 555, 40000.0, 18000.0, 540.0, "Auto", LoanApplication.RiskTier.HIGH),
	]

static func _application(applicant_name: String, requested_amount: float, credit_score: int, annual_income: float, existing_debt: float, monthly_debt_payments: float, loan_purpose: String, risk_tier: LoanApplication.RiskTier) -> LoanApplication:
	var application := LoanApplication.new()
	application.applicant_name = applicant_name
	application.requested_amount = requested_amount
	application.credit_score = credit_score
	application.annual_income = annual_income
	application.existing_debt = existing_debt
	application.monthly_debt_payments = monthly_debt_payments
	application.loan_purpose = loan_purpose
	application.risk_tier = risk_tier
	return application
