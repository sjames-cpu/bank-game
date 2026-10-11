extends "res://tests/support/teller_room_suite.gd"

## B1: clock-out must not leave stale serving state behind — no served
## customer, no "Serving: X" label, and the teller's selected account back
## on a non-customer account.

func test_clock_out_clears_served_customer_and_resets_account() -> void:
	clock_in()
	var last: CustomerNPC
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		last = spawn()
		serve_correctly(last)
	assert_bool(clock_out()).is_true()

	assert_object(room._customer_being_served).is_null()
	assert_object(ts._serving_customer).is_null()
	assert_str(ts.serving_status_label.text).is_equal("No customer waiting.")
	assert_bool(ts.account.is_customer_account).is_false()
	assert_object(ts.account).is_not_same(last.account)
	assert_bool(ts.complete_transaction_button.visible).is_false()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)

func test_clock_out_with_customer_mid_visit_clears_them() -> void:
	clock_in()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP - 1:
		serve_correctly(spawn())
	var last := spawn()
	# The last customer is served while the screen stays open, so clock-out
	# happens in the same visit.
	open_desk()
	deposit(last.intent_amount)
	complete()
	assert_bool(clock_out()).is_true()
	assert_object(ts._serving_customer).is_null()
	assert_bool(ts.account.is_customer_account).is_false()
