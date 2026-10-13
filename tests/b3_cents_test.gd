extends "res://tests/support/teller_room_suite.gd"

## B3: money the player handles is int cents end to end, so it stays exact
## to the cent. Many cash transactions with cent amounts (which drift when
## summed as float dollars) must still give the exact expected drawer, and
## counting that drawer correctly must grade Perfect. Dollars appear only in
## display, and MoneyMath.format() must show exactly what the old "%.2f" /
## "%.0f" dollar formatting showed.

func test_many_cash_transactions_sum_to_the_exact_drawer() -> void:
	clock_in()
	# No customers in this test: skip the clock-out customer gate.
	ts.remaining_shift_work = Callable()
	var expected_cents := TellerScreen.STARTING_FLOAT_CENTS
	# $0.10 + $0.20: 0.30000000000000004 as floats, exactly 30 cents here.
	ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 10)
	ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 20)
	expected_cents += 30
	assert_int(ts._calculate_expected_ending_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS + 30)
	# 1000 x $0.10 alone drifts as floats (99.9999999999986).
	for i in 1000:
		ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 10)
		expected_cents += 10
	for i in 300:
		ts._record_transaction(ShiftTransaction.Type.WITHDRAWAL, 33)
		expected_cents -= 33
	for i in 100:
		ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 1999)
		expected_cents += 1999
	# Card transactions don't touch the drawer.
	var card := ts._record_transaction(ShiftTransaction.Type.DEPOSIT, 12345)
	card.payment_method = ShiftTransaction.PaymentMethod.CARD
	# Bring the total back to whole dollars so the drawer (smallest bill $1)
	# can hold it.
	ts._record_transaction(ShiftTransaction.Type.WITHDRAWAL, 30)
	expected_cents -= 30
	assert_int(expected_cents % 100).is_equal(0)

	assert_int(ts._calculate_expected_ending_cents()).is_equal(expected_cents)
	assert_int(expected_cents).is_equal(5000000 + 30 + 10000 - 9900 + 199900 - 30)

	assert_bool(clock_out()).is_true()
	assert_str(ts.drawer_count_screen.result_expected_label.text).is_equal("Expected Balance: $52000.00")
	assert_str(ts.drawer_count_screen.status_label.text).is_equal("Perfect Count!")
	var last: DecisionRecord = HistoryManager.records[-1]
	assert_str(last.grade_label).is_equal("Perfect")
	assert_str(ts.shift_final_discrepancy_label.text).is_equal("Final Discrepancy: $0.00")

## Accounts hold cents too: ten cents plus twenty is exactly thirty.
func test_account_balances_are_exact_cents() -> void:
	var account := AccountManager.create_account("Cents Probe", 0)
	AccountManager.deposit(account, 10)
	AccountManager.deposit(account, 20)
	assert_int(account.balance_cents).is_equal(30)
	for i in 1000:
		AccountManager.deposit(account, 10)
	assert_int(account.balance_cents).is_equal(10030)
	assert_bool(AccountManager.withdraw(account, 10031)).is_false()
	assert_bool(AccountManager.withdraw(account, 10030)).is_true()
	assert_int(account.balance_cents).is_equal(0)

func test_customer_starting_balances_are_whole_dollars() -> void:
	var staff_line: NpcCustomerLine = room.get_node("Window1NpcLine")
	for i in 200:
		var player_account := cq._get_or_create_customer_account("Player Probe %d" % i)
		var staff_account := staff_line._get_or_create_customer_account("Staff Probe %d" % i)
		assert_int(player_account.balance_cents % 100).is_equal(0)
		assert_int(staff_account.balance_cents % 100).is_equal(0)

## format() shows exactly what "$%.2f" did for every cash amount, and
## format(cents, true) what "$%.0f" did for the whole-dollar amounts people
## say — so moving to cents changes no displayed text.
func test_format_matches_the_old_dollar_formatting() -> void:
	for cents: int in [0, 1, 5, 10, 30, 99, 100, 101, 1999, 50000, 164100, 5000000, 50000000, -1, -5, -99, -100, -1000, -100000, -5000000]:
		assert_str(MoneyMath.format(cents)).is_equal("$%.2f" % (cents / 100.0))
	for dollars: int in [0, 10, 20, 120, 500, 1000, 50000, -30]:
		assert_str(MoneyMath.format(dollars * 100, true)).is_equal("$%.0f" % float(dollars))
	# Cents are never hidden in the short form.
	assert_str(MoneyMath.format(30, true)).is_equal("$0.30")
	assert_str(MoneyMath.format(1234, true)).is_equal("$12.34")

## Seeded customers are the same as before money moved to cents: balances,
## requests and what they say. Reference values were recorded from the
## float-dollar code (commit 887cf5c) with the suite's RNG seed, written in
## the same "%.2f" dollar text both versions produce.
func test_seeded_customers_unchanged_by_the_move_to_cents() -> void:
	var lines: PackedStringArray = []
	for i in 60:
		cq._spawn_customer()
		var c: CustomerNPC = cq.queue[-1]
		lines.append("%s|%.2f|%d|%.2f|%s" % [c.display_name, c.account.balance_cents / 100.0, c.intent_type, c.intent_amount_cents / 100.0, c.dialogue_line.text if c.dialogue_line != null and c.complaint == null else "complaint"])
		# The line only has 3 spots; take each one out once read (all RNG
		# draws happen inside _spawn_customer()).
		cq.queue.pop_back()
		c.free()
	assert_str(lines[0]).is_equal("Priya Desai|1456.00|0|450.00|I'd like to deposit $450. I need to get this done fast, I've got somewhere to be.")
	assert_str(lines[1]).is_equal("Noel Grant|802.00|0|0.00|complaint")
	assert_str(lines[2]).is_equal("Mei Lin|1263.00|0|250.00|I'd like to deposit $250. Can we please make this quick? I'm on my lunch break.")
	assert_str("\n".join(lines).md5_text()).is_equal("5f9e99334b62ab61cce202f6ba045146")
