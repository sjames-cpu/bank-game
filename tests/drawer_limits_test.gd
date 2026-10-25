extends "res://tests/support/teller_room_suite.gd"

## Teller drawer limits and cash transfers with the vault (TellerScreen,
## VaultManager): the over/low warnings at the limits, transfers moving cash
## while the closing count stays exact, the vault's expected total following
## transfers, clock-out over the limit as a procedure mistake, the one-time
## hint, the vault total saved, and the panels fitting the window.

const FLOAT := TellerScreen.STARTING_FLOAT_CENTS

func before_test() -> void:
	await super()
	# Hints would sit over the screens; the hint test resets them itself.
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

## Deposits `dollars` in cash for a fresh customer, served correctly.
func cash_deposit(dollars: float) -> void:
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, dollars))

## Each transfer is made at the vault door, under dual control
## (teller_room_suite.gd's vault_transfer()).
func send_to_vault(dollars: int) -> void:
	vault_transfer(true, dollars)

func get_from_vault(dollars: int) -> void:
	vault_transfer(false, dollars)

## The rest of the shift's customers walk out, so clock-out is allowed.
func abandon_the_rest() -> void:
	while cq.get_customers_left_to_spawn() > 0:
		abandon(spawn())

func pending_teller_mistakes() -> int:
	var pending: PackedStringArray = ReportManager._pending_mistakes.get(DecisionRecord.Role.TELLER, PackedStringArray())
	return pending.size()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

# --- limits and warnings ---------------------------------------------------------

func test_the_limits_are_the_tuned_constants() -> void:
	assert_int(TellerScreen.DRAWER_MAX_CENTS).is_equal(335000)
	assert_int(TellerScreen.DRAWER_MIN_CENTS).is_equal(100000)
	# The float sits between them, and customers alone can't empty the
	# drawer below the minimum (4 of the largest withdrawals).
	assert_int(FLOAT).is_between(TellerScreen.DRAWER_MIN_CENTS, TellerScreen.DRAWER_MAX_CENTS)
	assert_int(FLOAT - CustomerQueue.CUSTOMERS_PER_SHIFT_CAP * CustomerQueue.INTENT_MAX_CENTS).is_greater_equal(TellerScreen.DRAWER_MIN_CENTS)

func test_the_over_limit_warning_appears_just_past_the_maximum() -> void:
	clock_in()
	open_desk()
	await frames(1)
	assert_bool(ts.drawer_panel.visible).is_true()
	assert_str(ts.drawer_cash_label.text).is_equal("Cash: $3000.00")
	assert_bool(ts.drawer_warning_label.visible).is_false()
	close_desk()
	# Exactly at the maximum: still within it.
	cash_deposit(350)
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.DRAWER_MAX_CENTS)
	assert_str(ts.drawer_limit_warning()).is_empty()
	# A cent over... a dollar over: over the limit.
	cash_deposit(1)
	assert_str(ts.drawer_limit_warning()).is_equal("Drawer over limit — send excess cash to the vault")
	open_desk()
	assert_bool(ts.drawer_warning_label.visible).is_true()
	assert_str(ts.drawer_warning_label.text).is_equal(TellerScreen.DRAWER_OVER_LIMIT_TEXT)
	assert_str(ts.drawer_cash_label.text).is_equal("Cash: $3351.00")

func test_the_low_warning_appears_just_under_the_minimum() -> void:
	clock_in()
	send_to_vault(2000)
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.DRAWER_MIN_CENTS)
	assert_str(ts.drawer_limit_warning()).is_empty()
	send_to_vault(1)
	assert_str(ts.drawer_limit_warning()).is_equal("Drawer low — get cash from the vault")
	assert_bool(ts.drawer_warning_label.visible).is_true()
	get_from_vault(500)
	assert_str(ts.drawer_limit_warning()).is_empty()

func test_card_transactions_never_count_toward_the_drawer() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 500)
	customer.payment_method = ShiftTransaction.PaymentMethod.CARD
	serve_correctly(customer)
	assert_int(ts.drawer_cash_cents()).is_equal(FLOAT)
	assert_str(ts.drawer_limit_warning()).is_empty()

func test_no_warning_or_panel_off_shift() -> void:
	open_desk()
	await frames(1)
	assert_bool(ts.drawer_panel.visible).is_false()
	assert_str(ts.drawer_limit_warning()).is_empty()

# --- transfers ------------------------------------------------------------------------

func test_transfers_move_cash_and_keep_the_closing_count_exact() -> void:
	clock_in()
	cash_deposit(512)
	var card := spawn(ShiftTransaction.Type.DEPOSIT, 300)
	card.payment_method = ShiftTransaction.PaymentMethod.CARD
	serve_correctly(card)
	send_to_vault(1000)
	assert_str(ts.transfer_receipt_label.text).starts_with("Sold $1000 to the vault · witnessed by ")
	assert_bool(ts.transfer_receipt_label.visible).is_true()
	get_from_vault(250)
	assert_str(ts.transfer_receipt_label.text).starts_with("Bought $250 from the vault · witnessed by ")
	# Float + net cash - sold + bought, to the cent; the card deposit isn't cash.
	var expected := FLOAT + 51200 - 100000 + 25000
	assert_int(ts.drawer_cash_cents()).is_equal(expected)
	assert_int(ts._calculate_expected_ending_cents()).is_equal(expected)
	close_desk()
	# Each transfer is in the history.
	var receipts: Array[String] = []
	for record in HistoryManager.records:
		if record.grade_label == "Vault transfer":
			receipts.append(record.description)
	assert_int(receipts.size()).is_equal(2)
	assert_str(receipts[0]).starts_with("Sold $1000 to the vault — dual control: you and ")
	assert_str(receipts[1]).starts_with("Bought $250 from the vault — dual control: you and ")
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	# Counted exactly: Perfect, nothing off.
	assert_str(ts.shift_final_discrepancy_label.text).is_equal("Final Discrepancy: $0.00")
	assert_str(ts.shift_score_label.text).contains("Perfect")
	assert_str(ts.shift_opening_count_label.text).is_equal("Opening count: Perfect · Vault: sold $1000 · bought $250")
	# The $512 deposit took it over the limit for a while: a warning only.
	assert_str(ts.shift_drawer_limit_label.text).is_equal("Went over the drawer limit (warning only)")

func test_transfers_are_checked_against_what_there_is() -> void:
	clock_in()
	send_to_vault(3001)
	assert_bool(room.vault_transfer_screen.error_label.visible).is_true()
	assert_int(ts.drawer_cash_cents()).is_equal(FLOAT)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)
	get_from_vault(200001) # a dollar more than the vault holds
	assert_bool(room.vault_transfer_screen.error_label.visible).is_true()
	assert_int(ts.drawer_cash_cents()).is_equal(FLOAT)
	send_to_vault(0)
	assert_bool(room.vault_transfer_screen.error_label.visible).is_true()
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)

func test_the_vaults_expected_total_follows_transfers() -> void:
	clock_in()
	send_to_vault(1200)
	get_from_vault(450)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS + 120000 - 45000)
	close_desk()
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	ts.shift_summary_done_button.pressed.emit()
	close_desk()
	# The Branch Manager's reconciliation is graded against it: counting the
	# old fixed total is now off by the transfers; the tracked one is Perfect.
	XPManager._grant_branch_manager()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	reconcile_vault()
	var vault := bm.vault_reconciliation_screen
	assert_str(vault.result_expected_label.text).is_equal("Expected Balance: %s" % MoneyMath.format(VaultManager.expected_cents))
	assert_str(vault.discrepancy_label.text).is_equal("Discrepancy: $0.00")
	var reconciled := false
	for record in HistoryManager.records:
		reconciled = reconciled or record.description.begins_with("Vault reconciliation: Perfect")
	assert_bool(reconciled).is_true()

func test_the_vault_total_is_saved_and_loaded() -> void:
	clock_in()
	send_to_vault(700)
	var expected := VaultManager.expected_cents
	assert_int(expected).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS + 70000)
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)
	SaveGame.restore(SaveGame.read().career)
	assert_int(VaultManager.expected_cents).is_equal(expected)
	# A save from before the vault was tracked has the starting total.
	var older := SaveGame.capture()
	older.erase("vault")
	SaveGame.restore(older)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)

# --- consequences ------------------------------------------------------------------------

func test_clocking_out_over_the_limit_is_a_procedure_mistake() -> void:
	clock_in()
	cash_deposit(500)
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	assert_int(pending_teller_mistakes()).is_equal(TellerScreen.DRAWER_OVER_AT_CLOCK_OUT_MISTAKES)
	var summary := ts.shift_drawer_limit_label.text
	assert_bool(ts.shift_drawer_limit_label.visible).is_true()
	assert_str(summary).contains("procedure mistake")
	assert_str(summary).contains("less cash at risk")
	# The penalty is in the shift's total (the drawer count itself still
	# grades the count, which was exact).
	assert_str(ts.shift_score_label.text).contains("Perfect")
	# A fresh career: the shift's total is the career's.
	assert_str(ts.shift_net_label.text).contains("This shift: Score %+d" % ScoreManager.total_score)

func test_going_over_during_the_shift_is_only_a_warning() -> void:
	clock_in()
	cash_deposit(500)
	send_to_vault(500)
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	assert_int(pending_teller_mistakes()).is_equal(0)
	assert_str(ts.shift_drawer_limit_label.text).contains("Went over the drawer limit (warning only)")

func test_a_shift_within_the_limits_has_no_drawer_line() -> void:
	clock_in()
	cash_deposit(100)
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	assert_int(pending_teller_mistakes()).is_equal(0)
	assert_bool(ts.shift_drawer_limit_label.visible).is_false()

# --- the hint ----------------------------------------------------------------------------

func test_the_drawer_limit_hint_shows_once() -> void:
	HintManager.reset()
	for hint: int in HintManager.Hint.values():
		if hint != HintManager.Hint.DRAWER_LIMIT:
			HintManager.mark_shown(hint)
	while room.hud.current_hint != -1:
		room.hud.dismiss_hint()
	clock_in()
	cash_deposit(300)
	assert_bool(HintManager.has_shown(HintManager.Hint.DRAWER_LIMIT)).is_false()
	cash_deposit(100)
	assert_bool(HintManager.has_shown(HintManager.Hint.DRAWER_LIMIT)).is_true()
	assert_int(room.hud.current_hint).is_equal(HintManager.Hint.DRAWER_LIMIT)
	assert_str(room.hud.hint_label.text).contains("vault door")
	room.hud.dismiss_hint()
	# Back under and over again: no second hint.
	send_to_vault(500)
	cash_deposit(500)
	assert_int(room.hud.current_hint).is_equal(-1)

# --- fit ---------------------------------------------------------------------------------

func test_the_drawer_panel_fits_beside_the_teller_and_id_panels() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	clock_in()
	cash_deposit(500)
	send_to_vault(20)
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	check_id()
	await frames(4)
	assert_bool(ts.drawer_warning_label.visible).is_true()
	assert_bool(ts.transfer_receipt_label.visible).is_true()
	assert_bool(ts.id_card_panel.visible).is_true()
	for panel: Control in [ts.drawer_panel, ts.main_panel, ts.id_card_panel]:
		var problems := layout_problems(panel)
		assert_array(problems).override_failure_message("%s:\n%s" % [panel.name, "\n".join(problems)]).is_empty()
	var drawer := ts.drawer_panel.get_global_rect()
	assert_bool(drawer.intersects(ts.main_panel.get_global_rect())).is_false()
	assert_bool(drawer.intersects(ts.id_card_panel.get_global_rect())).is_false()
	# The low warning wraps longer.
	close_desk()
	send_to_vault(2600)
	open_desk()
	await frames(2)
	assert_str(ts.drawer_warning_label.text).is_equal(TellerScreen.DRAWER_LOW_TEXT)
	assert_array(layout_problems(ts.drawer_panel)).is_empty()
	get_tree().root.size = window_before

func test_the_shift_summary_with_transfers_and_a_breach_fits() -> void:
	clock_in()
	cash_deposit(500)
	send_to_vault(20)
	get_from_vault(10)
	# Every ID count too: the summary at its longest.
	ts._ids_checked = 4
	ts._bad_ids_caught = 2
	ts._id_checks_skipped = 1
	ts._bad_ids_accepted = 1
	ts._valid_ids_refused = 1
	abandon_the_rest()
	assert_bool(clock_out()).is_true()
	assert_str(ts.shift_opening_count_label.text).contains("Vault: sold $20 · bought $10")
	assert_str(ts.shift_drawer_limit_label.text).contains("procedure mistake")
	assert_float(await settled_height(ts.shift_summary_panel)).is_less_equal(648.0)
