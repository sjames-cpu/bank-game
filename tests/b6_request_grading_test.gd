extends "res://tests/support/teller_room_suite.gd"

## B6: a regular customer's request is graded once, at Complete
## Transaction, against the net effect on their own account — with any
## wrong-account transaction required to be reversed, not compensated.

func before_test() -> void:
	await super()
	clock_in()

func test_correct_request_is_rewarded_and_served() -> void:
	var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 120.0)
	var start := customer.account.balance_cents
	var before := totals()
	open_desk()
	assert_bool(ts.complete_transaction_button.visible).is_true()
	assert_bool(ts.complete_transaction_button.disabled).is_true()
	withdraw(120)
	assert_bool(ts.complete_transaction_button.disabled).is_false()
	complete()
	assert_bool(cq.queue.has(customer)).is_false()
	assert_bool(customer.was_mistake).is_false()
	assert_int(customer.account.balance_cents).is_equal(start - 12000)
	assert_int((totals() - before).x).is_equal(TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE)

func test_wrong_amount_is_flagged_once_and_can_be_fixed() -> void:
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 500.0)
	var before := totals()
	open_desk()
	deposit(400)
	complete()
	assert_bool(customer.was_mistake).is_true()
	assert_bool(cq.queue.has(customer)).is_true()
	assert_str(customer.correction_line).contains("only deposited $400").contains("other $100")
	var penalised := totals() - before
	assert_int(penalised.x).is_equal(TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE)
	assert_int(penalised.y).is_equal(TellerScreen.CUSTOMER_REQUEST_WRONG_REPUTATION)
	# A second wrong Complete costs nothing more.
	complete()
	assert_vector(totals() - before).is_equal(penalised)
	deposit(100)
	complete()
	assert_bool(cq.queue.has(customer)).is_false()
	assert_int(ts._mistakes_fixed).is_equal(1)
	assert_vector(totals() - before).is_equal(penalised)

func test_wrong_type_is_flagged() -> void:
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 200.0)
	open_desk()
	withdraw(200)
	complete()
	assert_bool(customer.was_mistake).is_true()
	assert_str(customer.correction_line).is_equal("I wanted to deposit $200, not withdraw it.")

func test_split_deposit_is_graded_correct_on_complete() -> void:
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 500.0)
	open_desk()
	deposit(200)
	# Nothing is graded before Complete.
	assert_bool(customer.was_mistake).is_false()
	assert_bool(cq.queue.has(customer)).is_true()
	deposit(300)
	complete()
	assert_bool(customer.was_mistake).is_false()
	assert_bool(cq.queue.has(customer)).is_false()
	assert_int(ts._customers_correct).is_equal(1)
	assert_int(ReportManager.get_report_count()).is_equal(0)

func test_wrong_account_must_be_reversed_not_compensated() -> void:
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 300.0)
	var demo := AccountManager.get_browsable_accounts()[0]
	var demo_start := demo.balance_cents
	open_desk()
	select_account(demo)
	deposit(300)
	complete()
	assert_bool(customer.was_mistake).is_true()
	assert_str(customer.correction_line).is_equal("That's not my account — I'm %s." % customer.display_name)

	# Doing it right on their own account too isn't enough: the stray
	# deposit is still on someone else's account.
	select_account(customer.account)
	deposit(300)
	complete()
	assert_bool(cq.queue.has(customer)).is_true()
	assert_str(customer.correction_line).contains("still sitting in someone else's account")

	# Reverse undoes newest first: the own-account deposit, then the stray.
	reverse()
	reverse()
	assert_int(demo.balance_cents).is_equal(demo_start)
	select_account(customer.account)
	deposit(300)
	complete()
	assert_bool(cq.queue.has(customer)).is_false()
	assert_int(ts._mistakes_fixed).is_equal(1)

func test_closing_with_open_transactions_completes_them() -> void:
	var right := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	var wrong := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	var waiting := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	open_desk()
	deposit(100)
	close_desk()
	assert_bool(cq.queue.has(right)).is_false()
	assert_bool(right.left_upset).is_false()
	open_desk()
	deposit(60)
	close_desk()
	assert_bool(cq.queue.has(wrong)).is_false()
	assert_bool(wrong.was_mistake).is_true()
	assert_bool(wrong.left_upset).is_true()
	# Closing without any transaction leaves the customer waiting.
	open_desk()
	close_desk()
	assert_bool(cq.queue.has(waiting)).is_true()
	assert_bool(waiting.was_mistake).is_false()
