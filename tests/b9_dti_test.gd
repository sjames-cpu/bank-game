extends GdUnitTestSuite

## B9: DTI is monthly payments over gross monthly income — not the debt
## balance over annual income. (The underwriting worksheet's front-end and
## total DTI are covered in loan_application_test.gd.)

func test_monthly_payments_over_monthly_income() -> void:
	var application := LoanApplication.new()
	application.loan_purpose = "Auto"
	application.annual_income = 60000.0
	application.monthly_housing_payment = 1000.0
	application.monthly_debt_payments = 500.0
	# A large balance must not affect DTI.
	application.existing_debt = 250000.0
	assert_float(application.dti_before_loan()).is_equal_approx(0.30, 0.000001)
	assert_float(application.total_dti(0.0)).is_equal_approx(0.30, 0.000001)

func test_no_income_does_not_divide_by_zero() -> void:
	var application := LoanApplication.new()
	application.loan_purpose = "Auto"
	application.requested_amount = 10000.0
	application.annual_income = 0.0
	application.monthly_debt_payments = 500.0
	for ratio: float in [application.total_dti(), application.front_end_dti(), application.dti_before_loan(), application.new_payment_share()]:
		assert_bool(is_finite(ratio)).is_true()
	assert_float(application.affordable_amount()).is_equal(0.0)
