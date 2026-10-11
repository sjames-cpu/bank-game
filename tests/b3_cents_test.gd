extends "res://tests/support/teller_room_suite.gd"

## B3: money stays exact to the cent. Many cash transactions with cent
## amounts (which drift when summed as floats) must still give the exact
## expected drawer, and counting that drawer correctly must grade Perfect.

func test_many_cash_transactions_sum_to_the_exact_drawer() -> void:
	clock_in()
	# No customers in this test: skip the clock-out customer gate.
	ts.remaining_shift_work = Callable()
	var expected_cents := MoneyMath.to_cents(TellerScreen.STARTING_EXPECTED_BALANCE)
	# 1000 x $0.10 alone drifts (sums to 99.9999999999986 as floats).
	for i in 1000:
		ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 0.10)
		expected_cents += 10
	for i in 300:
		ts._record_transaction(ShiftTransaction.Type.WITHDRAWAL, 0.33)
		expected_cents -= 33
	for i in 100:
		ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 19.99)
		expected_cents += 1999
	# The total lands on whole dollars so the drawer (smallest bill $1) can hold it.
	assert_int(expected_cents % 100).is_equal(0)

	var expected := ts._calculate_expected_ending_balance()
	assert_int(MoneyMath.to_cents(expected)).is_equal(expected_cents)

	assert_bool(clock_out()).is_true()
	assert_str(ts.drawer_count_screen.status_label.text).is_equal("Perfect Count!")
	var last: DecisionRecord = HistoryManager.records[-1]
	assert_str(last.grade_label).is_equal("Perfect")
	assert_str(ts.shift_final_discrepancy_label.text).is_equal("Final Discrepancy: $0.00")

func test_customer_starting_balances_are_whole_dollars() -> void:
	var staff_line: NpcCustomerLine = room.get_node("Window1NpcLine")
	for i in 200:
		var player_account := cq._get_or_create_customer_account("Player Probe %d" % i)
		var staff_account := staff_line._get_or_create_customer_account("Staff Probe %d" % i)
		assert_float(player_account.balance).is_equal(roundf(player_account.balance))
		assert_float(staff_account.balance).is_equal(roundf(staff_account.balance))
