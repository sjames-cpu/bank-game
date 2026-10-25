extends "res://tests/support/teller_room_suite.gd"

## The vault's cash supply, part 1 (VaultManager, CashOrdersScreen): its
## limits and warnings; each day's close moving it by the staff windows' net
## cash and the ATM restock, exactly; orders and shipments arriving the next
## business day (weekends and holidays included); the NPC branch manager
## keeping it in range for a month; save, load and reset; the screens fitting.

const START := VaultReconciliationScreen.STARTING_VAULT_CENTS

func before_test() -> void:
	await super()
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

## A staff window serves `customer` straight away (the customer at the
## window), as NpcCustomerLine does at the end of a service.
func staff_serve(line: NpcCustomerLine, type: ShiftTransaction.Type, dollars: int, payment: ShiftTransaction.PaymentMethod) -> CustomerNPC:
	line._spawn_customer()
	var customer: CustomerNPC = line.queue[-1]
	customer.intent_type = type
	customer.intent_amount_cents = dollars * 100
	customer.payment_method = payment
	line._serving = customer
	line._serving_staff = line.staff_npc
	line._complete_service()
	return customer

func promote_and_clock_in() -> BranchManagerScreen:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()
	return bm

# --- limits and warnings -----------------------------------------------------------

func test_the_vault_limits_sit_around_the_starting_total() -> void:
	assert_int(VaultManager.VAULT_MIN_CENTS).is_equal(10000000)
	assert_int(VaultManager.VAULT_MAX_CENTS).is_equal(30000000)
	assert_int(VaultManager.VAULT_MID_CENTS).is_equal(START)
	assert_bool(VaultManager.is_in_range()).is_true()

func test_the_warnings_appear_at_the_limits() -> void:
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS
	assert_str(VaultManager.limit_warning()).is_empty()
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS - 1
	assert_str(VaultManager.limit_warning()).is_equal(VaultManager.VAULT_LOW_TEXT)
	assert_str(VaultManager.limit_warning()).starts_with("Vault low")
	VaultManager.expected_cents = VaultManager.VAULT_MAX_CENTS
	assert_str(VaultManager.limit_warning()).is_empty()
	VaultManager.expected_cents = VaultManager.VAULT_MAX_CENTS + 1
	assert_str(VaultManager.limit_warning()).starts_with("Vault over limit")

func test_the_vault_door_warns_and_never_goes_below_zero() -> void:
	clock_in()
	VaultManager.expected_cents = 50000 # $500: far below the minimum
	var witness := call_vault_witness()
	var vault := room.vault_transfer_screen
	assert_bool(vault.vault_warning_label.visible).is_true()
	assert_str(vault.vault_warning_label.text).is_equal(VaultManager.VAULT_LOW_TEXT)
	vault.amount_input.value = 600
	vault.get_button.pressed.emit()
	assert_bool(vault.error_label.visible).is_true()
	assert_int(VaultManager.expected_cents).is_equal(50000)
	vault.amount_input.value = 500
	vault.get_button.pressed.emit()
	assert_int(VaultManager.expected_cents).is_equal(0)
	vault.close_button.pressed.emit()
	witness.finish_route()
	# Over the maximum: its own warning.
	VaultManager.expected_cents = VaultManager.VAULT_MAX_CENTS + 100
	witness = call_vault_witness()
	assert_str(vault.vault_warning_label.text).is_equal(VaultManager.VAULT_OVER_TEXT)
	vault.close_button.pressed.emit()
	witness.finish_route()

# --- the day's cash flow ---------------------------------------------------------------

func test_staff_windows_count_their_cash_but_not_cards() -> void:
	var line := room.window1_npc_line
	staff_serve(line, ShiftTransaction.Type.DEPOSIT, 430, ShiftTransaction.PaymentMethod.CASH)
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(43000)
	staff_serve(line, ShiftTransaction.Type.WITHDRAWAL, 120, ShiftTransaction.PaymentMethod.CASH)
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(31000)
	staff_serve(line, ShiftTransaction.Type.DEPOSIT, 500, ShiftTransaction.PaymentMethod.CARD)
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(31000)
	# A withdrawal the account can't cover moves no cash.
	room.window2_line._spawn_customer()
	var short: CustomerNPC = room.window2_line.queue[-1]
	short.intent_type = ShiftTransaction.Type.WITHDRAWAL
	short.intent_amount_cents = short.account.balance_cents + 100
	short.payment_method = ShiftTransaction.PaymentMethod.CASH
	room.window2_line._serving = short
	room.window2_line._serving_staff = room.window2_line.staff_npc
	room.window2_line._complete_service()
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(31000)
	# A new day starts from nothing.
	BusinessDay.start_next_day()
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(0)

func test_the_days_close_moves_the_vault_exactly() -> void:
	# Day 2 isn't an ATM day: only the staff windows' net.
	var close := VaultManager.close_day(2, 31234, false)
	assert_int(VaultManager.expected_cents).is_equal(START + 31234)
	assert_int(close["atm_restock"]).is_equal(0)
	# Once a day only.
	VaultManager.close_day(2, 99999, false)
	assert_int(VaultManager.expected_cents).is_equal(START + 31234)
	# Day 3 is: the restock comes out too, to the cent.
	close = VaultManager.close_day(3, -4567, false)
	assert_int(close["atm_restock"]).is_equal(VaultManager.ATM_RESTOCK_CENTS)
	assert_int(VaultManager.expected_cents).is_equal(START + 31234 - 4567 - VaultManager.ATM_RESTOCK_CENTS)
	assert_int(close["expected"]).is_equal(VaultManager.expected_cents)
	assert_bool(VaultManager.is_atm_restock_day(6)).is_true()
	assert_bool(VaultManager.is_atm_restock_day(7)).is_false()

func test_the_end_of_day_summary_shows_the_vaults_day() -> void:
	set_day_and_time(3, 17, 0)
	BusinessDay.note_staff_cash(125050)
	await frames(3)
	var eod := room.end_of_day_screen
	assert_bool(eod.is_summary_shown()).is_true()
	var text := eod.summary_label.text
	assert_str(text).contains("Vault: staff windows +$1250.50 · ATM restock -$24000.00")
	assert_str(text).contains("Vault now %s (limits $100000–$300000)" % MoneyMath.format(START + 125050 - VaultManager.ATM_RESTOCK_CENTS))
	assert_int(VaultManager.expected_cents).is_equal(START + 125050 - VaultManager.ATM_RESTOCK_CENTS)

func set_day_and_time(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func test_a_close_out_of_range_is_recorded() -> void:
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS + 1000
	var close := VaultManager.close_day(3, 0, true) # the restock takes it below
	assert_bool(close["in_range"]).is_false()
	assert_array(Array(VaultManager.out_of_range_days)).is_equal([3])
	assert_str(EndOfDayScreen.vault_text(close)).contains("— out of range")
	VaultManager.expected_cents = VaultManager.VAULT_MAX_CENTS + 1
	VaultManager.close_day(4, 0, true)
	assert_array(Array(VaultManager.out_of_range_days)).is_equal([3, 4])
	VaultManager.expected_cents = START
	VaultManager.close_day(5, 0, true)
	assert_array(Array(VaultManager.out_of_range_days)).is_equal([3, 4])

# --- orders --------------------------------------------------------------------------------

func test_an_order_arrives_at_opening_on_the_next_business_day() -> void:
	assert_str(VaultManager.place_order(5 * VaultManager.STRAP_CENTS, 2)).is_empty()
	assert_int(VaultManager.pending_orders[0]["delivery_day"]).is_equal(3)
	assert_int(VaultManager.expected_cents).is_equal(START)
	VaultManager.receive_deliveries(2)
	assert_int(VaultManager.expected_cents).is_equal(START)
	VaultManager.receive_deliveries(3)
	assert_int(VaultManager.expected_cents).is_equal(START + 5 * VaultManager.STRAP_CENTS)
	assert_array(VaultManager.pending_orders).is_empty()

func test_orders_skip_weekends_and_holidays() -> void:
	# Day 5 is Friday 9 January 2026: an order then arrives on Monday 12th.
	assert_str(BankCalendar.short_text(GameClock.date_of_day(5))).is_equal("Fri 9 Jan")
	VaultManager.place_order(VaultManager.STRAP_CENTS, 5)
	var delivery_day: int = VaultManager.pending_orders[0]["delivery_day"]
	assert_str(BankCalendar.short_text(GameClock.date_of_day(delivery_day))).is_equal("Mon 12 Jan")
	VaultManager.receive_deliveries(delivery_day)
	# Day 10 is Friday 16 January, before Martin Luther King, Jr. Day (Monday
	# 19th, closed): a shipment goes on Tuesday 20th.
	VaultManager.place_order(-2 * VaultManager.STRAP_CENTS, 10)
	delivery_day = VaultManager.pending_orders[0]["delivery_day"]
	assert_str(BankCalendar.short_text(GameClock.date_of_day(delivery_day))).is_equal("Tue 20 Jan")
	VaultManager.receive_deliveries(delivery_day)
	assert_int(VaultManager.expected_cents).is_equal(START + VaultManager.STRAP_CENTS - 2 * VaultManager.STRAP_CENTS)

func test_the_room_receives_orders_as_the_branch_opens_after_a_weekend() -> void:
	set_day_and_time(5, 10, 0) # Friday
	VaultManager.place_order(3 * VaultManager.STRAP_CENTS, 5)
	room._on_exit_door_interacted()
	room.end_of_day_screen.go_home_button.pressed.emit()
	var eod := room.end_of_day_screen
	assert_bool(eod.is_summary_shown()).is_true()
	assert_int(VaultManager.expected_cents).is_equal(START) # not yet
	eod.next_day_button.pressed.emit() # the weekend notice
	assert_bool(eod.is_closure_shown()).is_true()
	eod.next_day_button.pressed.emit()
	assert_int(GameClock.day).is_equal(6)
	assert_str(BankCalendar.short_text(GameClock.today_date())).is_equal("Mon 12 Jan")
	await frames(2)
	assert_int(VaultManager.expected_cents).is_equal(START) # 8:30, before opening
	GameClock.minutes = BusinessDay.OPEN_MINUTES
	await frames(2)
	assert_int(VaultManager.expected_cents).is_equal(START + 3 * VaultManager.STRAP_CENTS)

func test_one_order_a_day_in_whole_straps_and_no_more_than_the_vault_holds() -> void:
	assert_str(VaultManager.place_order(12345, 1)).contains("straps")
	assert_str(VaultManager.place_order(0, 1)).contains("straps")
	assert_str(VaultManager.place_order(-30 * VaultManager.STRAP_CENTS, 1)).contains("doesn't hold")
	assert_str(VaultManager.place_order(VaultManager.STRAP_CENTS, 1)).is_empty()
	assert_str(VaultManager.place_order(VaultManager.STRAP_CENTS, 1)).is_equal("Today's cash order is already placed.")
	assert_str(VaultManager.place_order(VaultManager.STRAP_CENTS, 2)).is_empty()

func test_the_forecast_counts_whats_known() -> void:
	# Day 2 (no restock), tomorrow Day 3 (restock), with an order for Day 3.
	VaultManager.place_order(4 * VaultManager.STRAP_CENTS, 2)
	assert_int(VaultManager.forecast_for_tomorrow(2, 50000)).is_equal(START + 50000 + 4 * VaultManager.STRAP_CENTS - VaultManager.ATM_RESTOCK_CENTS)
	# After today's close, today's figures are in the vault already.
	VaultManager.close_day(2, 50000, true)
	assert_int(VaultManager.forecast_for_tomorrow(2, 50000)).is_equal(START + 50000 + 4 * VaultManager.STRAP_CENTS - VaultManager.ATM_RESTOCK_CENTS)

func test_the_branch_manager_orders_from_the_cash_orders_screen() -> void:
	var bm := promote_and_clock_in()
	assert_bool(bm.cash_orders_button.disabled).is_false()
	bm.cash_orders_button.pressed.emit()
	var orders := bm.cash_orders_screen
	assert_bool(orders.is_visible_in_tree()).is_true()
	assert_str(orders.expected_label.text).is_equal("Vault: %s" % MoneyMath.format(START))
	assert_str(orders.limits_label.text).is_equal("Limits: $100000 – $300000 (middle $200000)")
	assert_str(orders.pending_label.text).is_equal("Pending: none")
	orders.straps_input.value = 7
	assert_str(orders.amount_label.text).is_equal("= $70000")
	orders.order_in_button.pressed.emit()
	var tomorrow := CashOrdersScreen.delivery_text(GameClock.day + 1)
	assert_str(orders.pending_label.text).is_equal("Pending: in $70000 for %s" % tomorrow)
	assert_str(orders.status_label.text).is_equal("Ordered $70000 from the Federal Reserve, for %s." % tomorrow)
	assert_str(HistoryManager.records[-1].description).is_equal("Cash order: Ordered $70000 from the Federal Reserve, for %s." % tomorrow)
	# One a day: both buttons are off now.
	assert_bool(orders.order_in_button.disabled).is_true()
	assert_bool(orders.ship_out_button.disabled).is_true()
	orders.close_button.pressed.emit()
	assert_bool(bm.main_panel.visible).is_true()
	# A manager's close places no NPC order.
	var close := VaultManager.close_day(GameClock.day, 0, true)
	assert_dict(close["order"]).is_empty()

# --- the NPC branch manager ---------------------------------------------------------------

## A month of business days: each opening's deliveries, a day of staff cash
## (seeded, a few thousand either way) and the close, with the NPC branch
## manager ordering. Returns the orders it placed.
func simulate_month(days: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	var orders := 0
	for day in range(1, days + 1):
		VaultManager.receive_deliveries(day)
		assert_bool(VaultManager.is_in_range()).override_failure_message("Day %d opened at %s" % [day, MoneyMath.format(VaultManager.expected_cents)]).is_true()
		var close := VaultManager.close_day(day, rng.randi_range(-300000, 300000), false)
		assert_bool(close["in_range"]).override_failure_message("Day %d closed at %s" % [day, MoneyMath.format(VaultManager.expected_cents)]).is_true()
		var order: Dictionary = close["order"]
		if not order.is_empty():
			orders += 1
	return orders

func test_the_npc_branch_manager_keeps_the_vault_in_range_for_a_month() -> void:
	var orders := simulate_month(21)
	assert_int(orders).is_greater(0)
	assert_array(Array(VaultManager.out_of_range_days)).is_empty()

func test_the_npc_branch_manager_rescues_a_low_or_high_vault() -> void:
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS + 500000
	simulate_month(21)
	assert_array(Array(VaultManager.out_of_range_days)).is_empty()
	CareerReset.reset_all()
	VaultManager.expected_cents = VaultManager.VAULT_MAX_CENTS - 500000
	VaultManager.close_day(1, 3000000, false) # a big day takes it over
	assert_int(VaultManager.pending_orders.size()).is_equal(1)
	assert_int(VaultManager.pending_orders[0]["cents"]).is_less(0)
	VaultManager.receive_deliveries(2)
	assert_bool(VaultManager.is_in_range()).is_true()

# --- save, load, reset ----------------------------------------------------------------------

func test_the_vaults_state_is_saved_and_loaded() -> void:
	VaultManager.expected_cents = 9876543
	VaultManager.place_order(4 * VaultManager.STRAP_CENTS, 7)
	VaultManager.close_day(6, 1234, true) # no NPC order: only this one pending
	VaultManager.out_of_range_days.append(5)
	BusinessDay.note_staff_cash(-777)
	var vault_before := VaultManager.save_data()
	var staff_before := BusinessDay.staff_net_cash_cents
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(VaultManager.save_data()).is_equal(vault_before)
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(staff_before)
	assert_int(VaultManager.pending_orders.size()).is_equal(1)
	assert_array(Array(VaultManager.out_of_range_days)).contains([5])

func test_career_reset_restores_the_starting_vault() -> void:
	VaultManager.expected_cents = 123
	VaultManager.place_order(VaultManager.STRAP_CENTS, 2)
	VaultManager.close_day(3, 0, true)
	CareerReset.reset_all()
	assert_int(VaultManager.expected_cents).is_equal(START)
	assert_array(VaultManager.pending_orders).is_empty()
	assert_array(Array(VaultManager.out_of_range_days)).is_empty()
	assert_int(VaultManager.last_closed_day).is_equal(0)
	assert_int(VaultManager.last_order_day).is_equal(0)
	assert_dict(VaultManager.last_close).is_empty()

# --- fit ---------------------------------------------------------------------------------------

func test_the_cash_orders_screen_fits_the_window() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	var bm := promote_and_clock_in()
	# Two orders pending, the vault low, and a status line.
	VaultManager.pending_orders.append({"placed_day": GameClock.day - 1, "delivery_day": GameClock.day + 1, "cents": -3 * VaultManager.STRAP_CENTS})
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS - 100
	bm.cash_orders_button.pressed.emit()
	bm.cash_orders_screen.order_in_button.pressed.emit()
	await frames(4)
	var orders := bm.cash_orders_screen
	assert_bool(orders.warning_label.visible).is_true()
	assert_bool(orders.status_label.visible).is_true()
	assert_str(orders.pending_label.text).contains("\n")
	var problems := layout_problems(orders.panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	get_tree().root.size = window_before

func test_the_end_of_day_summary_with_the_vault_fits() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	set_day_and_time(3, 17, 0)
	# Every vault line: a delivery, a shipment, staff cash, the restock, out of
	# range and the NPC's order; and a full cutoff list.
	VaultManager.delivered_today_cents = 5 * VaultManager.STRAP_CENTS
	VaultManager.shipped_today_cents = 2 * VaultManager.STRAP_CENTS
	VaultManager.expected_cents = VaultManager.VAULT_MIN_CENTS - 3 * VaultManager.STRAP_CENTS
	BusinessDay.note_staff_cash(-123456)
	for i in EndOfDayScreen.MAX_CUTOFF_LINES + 2:
		BusinessDay.after_cutoff.append({"time": "2:%02d PM" % i, "type": "Withdrawal", "amount_cents": 12345, "account": "Grace O'Connor", "posting_day": 4})
	await frames(3)
	var eod := room.end_of_day_screen
	assert_bool(eod.is_summary_shown()).is_true()
	var text := eod.summary_label.text
	assert_str(text).contains("delivered +$50000.00 · shipped -$20000.00")
	assert_str(text).contains("— out of range")
	assert_str(text).contains("Branch manager's cash order: in")
	await frames(2)
	var problems := layout_problems(eod.summary_panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	get_tree().root.size = window_before
