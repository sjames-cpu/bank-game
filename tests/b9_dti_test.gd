extends GdUnitTestSuite

## B9: DTI is monthly debt payments over gross monthly income — not the debt
## balance over annual income.

func test_monthly_payments_over_monthly_income() -> void:
	var application := LoanApplication.new()
	application.annual_income = 60000.0
	application.monthly_debt_payments = 500.0
	# A large balance must not affect DTI.
	application.existing_debt = 250000.0
	assert_float(application.debt_to_income_ratio()).is_equal_approx(0.10, 0.000001)

func test_no_income_does_not_divide_by_zero() -> void:
	var application := LoanApplication.new()
	application.annual_income = 0.0
	application.monthly_debt_payments = 500.0
	var ratio := application.debt_to_income_ratio()
	assert_bool(is_finite(ratio)).is_true()
