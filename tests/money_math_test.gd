extends GdUnitTestSuite

func test_money_math_rounds_to_cents() -> void:
	assert_int(MoneyMath.to_cents(0.1 + 0.2)).is_equal(30)
