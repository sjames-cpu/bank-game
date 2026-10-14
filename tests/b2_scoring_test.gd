extends "res://tests/support/teller_room_suite.gd"

## B2: clock-out is gated on customer work, and customers — not the drawer —
## are the main teller score. Expected values are the approved scoring table
## (2026-10-12): +5 per correct request, -3 Score / -2 Reputation per
## abandonment or first mistake, drawer bonus scaled by customers served.

func test_clock_out_blocked_until_all_customers_handled() -> void:
	clock_in()
	assert_bool(clock_out()).is_false()
	assert_str(ts.error_label.text).contains("4 more customers still to arrive")

	var first := spawn()
	close_desk()
	assert_bool(clock_out()).is_false()
	assert_str(ts.error_label.text).contains("1 customer still waiting")

	# Transactions made but not completed still block clock-out.
	deposit(first.intent_amount_cents / 100.0)
	assert_bool(clock_out()).is_false()
	assert_str(ts.error_label.text).contains("transaction isn't completed yet")
	complete()
	close_desk()

	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP - 1:
		serve_correctly(spawn())
	assert_bool(clock_out()).is_true()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)

## [actions per customer, minor count?, expected Score, Reputation, XP]
func _scenarios() -> Dictionary:
	return {
		"all_abandoned_perfect": [["abandon", "abandon", "abandon", "abandon"], false, Vector3i(-12, -8, 0)],
		"all_correct_minor": [["correct", "correct", "correct", "correct"], true, Vector3i(25, 0, 250)],
		"all_correct_perfect": [["correct", "correct", "correct", "correct"], false, Vector3i(30, 2, 300)],
		"two_correct_two_fixed_perfect": [["correct", "correct", "fixed", "fixed"], false, Vector3i(14, -2, 200)],
	}

func _run_shift(actions: Array, minor: bool) -> Vector3i:
	var before := totals()
	clock_in()
	for action: String in actions:
		var customer := spawn(ShiftTransaction.Type.DEPOSIT, 500.0)
		match action:
			"abandon":
				abandon(customer)
			"correct":
				serve_correctly(customer)
			"fixed":
				open_desk()
				deposit(450)
				complete()
				deposit(50)
				complete()
				close_desk()
	assert_bool(clock_out(minor)).is_true()
	return totals() - before

func test_scenario_all_abandoned_perfect() -> void:
	_check_scenario("all_abandoned_perfect")

func test_scenario_all_correct_minor() -> void:
	_check_scenario("all_correct_minor")

func test_scenario_all_correct_perfect() -> void:
	_check_scenario("all_correct_perfect")

func test_scenario_two_correct_two_fixed_perfect() -> void:
	_check_scenario("two_correct_two_fixed_perfect")

func _check_scenario(key: String) -> void:
	var scenario: Array = _scenarios()[key]
	var actions: Array = scenario[0]
	var minor: bool = scenario[1]
	var expected: Vector3i = scenario[2]
	var delta := _run_shift(actions, minor)
	assert_vector(delta).is_equal(expected)
	# The summary's "This shift" line adds drawer + customers up to the same.
	assert_str(ts.shift_net_label.text).is_equal("This shift: Score %+d · Reputation %+d · XP %+d" % [delta.x, delta.y, delta.z])

func test_ignoring_everyone_scores_below_serving_everyone() -> void:
	var abandon_all: Array = _scenarios()["all_abandoned_perfect"][0]
	var serve_all: Array = _scenarios()["all_correct_minor"][0]
	var ignored := _run_shift(abandon_all, false)
	CareerReset.reset_all()
	var served := _run_shift(serve_all, true)
	assert_int(ignored.x).is_less(served.x)
	assert_int(ignored.x).is_less_equal(0)
