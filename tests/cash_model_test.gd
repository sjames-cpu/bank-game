extends "res://tests/support/teller_room_suite.gd"

## The cash model (CashDenominations, DrawerCountScreen,
## VaultReconciliationScreen, TellerScreen): current US notes and coins
## summing to the exact cent; a $3,000 teller float of mostly $20s and
## rolled coins, which counts Perfect as it came; Perfect/Minor/Major at the
## new scale for drawer and vault; withdrawals never take more cash than the
## drawer holds; both count screens fit the 1152x648 window.

const FLOAT := TellerScreen.STARTING_FLOAT_CENTS

var dcs: DrawerCountScreen
var vault: VaultReconciliationScreen

func before_test() -> void:
	await super()
	dcs = ts.drawer_count_screen
	vault = room.branch_manager_screen.vault_reconciliation_screen

# --- helpers -------------------------------------------------------------------

func enter(inputs: Array[SpinBox], quantities: Array[int]) -> void:
	for i in quantities.size():
		inputs[i].value = quantities[i]

func index_of(cents: int) -> int:
	return CashDenominations.DENOMINATION_CENTS.find(cents)

## `quantities` with `count` of `from_cents` swapped for the same value in
## `to_cents` pieces.
func swap(quantities: Array[int], from_cents: int, to_cents: int, count: int) -> Array[int]:
	var swapped := quantities.duplicate()
	swapped[index_of(from_cents)] -= count
	swapped[index_of(to_cents)] += count * floori(float(from_cents) / to_cents)
	return swapped

## Submits `quantities` on a drawer count for `expected` and returns the
## status line.
func drawer_status(expected: int, quantities: Array[int], plausible: int = 0) -> String:
	dcs.show_screen(expected, "Test Count", plausible)
	enter(dcs.quantity_inputs, quantities)
	dcs.submit_button.pressed.emit()
	var status := dcs.status_label.text
	dcs.close_button.pressed.emit()
	return status

func vault_status(quantities: Array[int]) -> String:
	vault.show_screen()
	enter(vault.quantity_inputs, quantities)
	vault.submit_button.pressed.emit()
	var status := vault.status_label.text
	vault.close_button.pressed.emit()
	return status

# --- denominations -------------------------------------------------------------------

func test_current_us_denominations_sum_to_the_exact_cent() -> void:
	assert_array(CashDenominations.DENOMINATION_CENTS).is_equal([10000, 5000, 2000, 1000, 500, 100, 25, 10, 5, 1])
	assert_array(DrawerCountScreen.DENOMINATION_CENTS).is_equal(CashDenominations.DENOMINATION_CENTS)
	assert_array(VaultReconciliationScreen.DENOMINATION_CENTS).is_equal(CashDenominations.DENOMINATION_CENTS)
	assert_int(CashDenominations.LABELS.size()).is_equal(CashDenominations.DENOMINATION_CENTS.size())
	# No $1,000 or $500 bills any more.
	assert_bool(CashDenominations.DENOMINATION_CENTS.has(100000) or CashDenominations.DENOMINATION_CENTS.has(50000)).is_false()
	# Any amount, to the cent.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var amounts: Array[int] = [0, 1, 4, 41, 99, 2999, 300000, 20000000, 12345678]
	for i in 200:
		amounts.append(rng.randi_range(0, 30000000))
	for amount in amounts:
		assert_int(CashDenominations.total_cents(CashDenominations.fewest_pieces(amount))).is_equal(amount)
	# 41 cents: a quarter, a dime, a nickel and a penny.
	assert_array(CashDenominations.fewest_pieces(41)).is_equal([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	# Each screen has one row per denomination and adds them to the cent.
	for inputs: Array[SpinBox] in [dcs.quantity_inputs, vault.quantity_inputs]:
		assert_int(inputs.size()).is_equal(10)
	dcs.show_screen(FLOAT)
	enter(dcs.quantity_inputs, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	assert_int(dcs._calculate_total_cents()).is_equal(18641)
	assert_str(dcs.your_total_label.text).is_equal("Your Total: $186.41")
	dcs.close_button.pressed.emit()

func test_the_float_and_its_mix() -> void:
	assert_int(FLOAT).is_equal(300000)
	assert_int(CashDenominations.total_cents(TellerScreen.STARTING_FLOAT_MIX)).is_equal(FLOAT)
	# Coins: two rolls of each, $35.
	var coins := 0
	for i in range(CashDenominations.FIRST_COIN, CashDenominations.DENOMINATION_CENTS.size()):
		coins += CashDenominations.DENOMINATION_CENTS[i] * TellerScreen.STARTING_FLOAT_MIX[i]
	assert_int(coins).is_equal(3500)
	# The vault is a small branch's: well above every drawer together.
	assert_int(VaultReconciliationScreen.EXPECTED_VAULT_CENTS).is_equal(20000000)
	assert_int(VaultReconciliationScreen.EXPECTED_VAULT_CENTS).is_greater(4 * FLOAT * 10)

# --- grading ----------------------------------------------------------------------

## The float counted as it came, coins and all, is a Perfect opening count;
## so is the fewest pieces. A closing count of that mix plus the day's cash
## in the fewest pieces is Perfect too.
func test_a_correct_count_with_coins_grades_perfect() -> void:
	open_desk()
	ts.clock_in_button.pressed.emit()
	enter(dcs.quantity_inputs, TellerScreen.STARTING_FLOAT_MIX)
	dcs.submit_button.pressed.emit()
	assert_str(dcs.status_label.text).is_equal("Perfect Count!")
	dcs.close_button.pressed.emit()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_IN)
	close_desk()
	cq.spawn_timer.stop()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 120.0))

	var expected := FLOAT + 12000
	assert_int(ts._calculate_expected_ending_cents()).is_equal(expected)
	var closing := TellerScreen.STARTING_FLOAT_MIX.duplicate()
	var taken_in := CashDenominations.fewest_pieces(12000)
	for i in closing.size():
		closing[i] += taken_in[i]
	assert_str(drawer_status(expected, closing, TellerScreen.drawer_plausible_pieces(expected))).is_equal("Perfect Count!")
	assert_str(drawer_status(expected, CashDenominations.fewest_pieces(expected), TellerScreen.drawer_plausible_pieces(expected))).is_equal("Perfect Count!")
	# Coins in a vault count: a dollar as four quarters is still Perfect.
	var vault_count := CashDenominations.fewest_pieces(VaultReconciliationScreen.EXPECTED_VAULT_CENTS - 100)
	vault_count[index_of(25)] += 4
	assert_int(CashDenominations.total_cents(vault_count)).is_equal(VaultReconciliationScreen.EXPECTED_VAULT_CENTS)
	assert_str(vault_status(vault_count)).is_equal("Perfect Count!")

func test_drawer_thresholds_at_the_new_scale() -> void:
	var exact := CashDenominations.fewest_pieces(FLOAT)
	var plausible := TellerScreen.drawer_plausible_pieces(FLOAT)
	assert_str(drawer_status(FLOAT, exact, plausible)).is_equal("Perfect Count!")
	assert_str(drawer_status(FLOAT, TellerScreen.STARTING_FLOAT_MIX, plausible)).is_equal("Perfect Count!")
	# Off by a penny, or a whole $50 note: Minor.
	var penny_over := exact.duplicate()
	penny_over[index_of(1)] += 1
	assert_str(drawer_status(FLOAT, penny_over, plausible)).is_equal("Minor Discrepancy")
	var fifty_over := exact.duplicate()
	fifty_over[index_of(5000)] += 1
	assert_str(drawer_status(FLOAT, fifty_over, plausible)).is_equal("Minor Discrepancy")
	# A $100 note out, or $50.01: Major.
	var hundred_short := exact.duplicate()
	hundred_short[index_of(10000)] -= 1
	assert_str(drawer_status(FLOAT, hundred_short, plausible)).is_equal("Major Discrepancy")
	var fifty_and_a_penny := fifty_over.duplicate()
	fifty_and_a_penny[index_of(1)] += 1
	assert_str(drawer_status(FLOAT, fifty_and_a_penny, plausible)).is_equal("Major Discrepancy")

	# The right total with too many pieces, against the fewest possible: a
	# couple of swaps is fine, a handful unusual, a pile implausible.
	assert_int(DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS).is_equal(5000)
	# (The fewest pieces for $3,000 are 30 $100 notes.)
	assert_str(drawer_status(FLOAT, swap(exact, 10000, 2000, 1))).is_equal("Perfect Count!") # +4 pieces
	assert_str(drawer_status(FLOAT, swap(exact, 10000, 2000, 2))).is_equal("Minor Discrepancy (correct total, but an unusual mix of bills and coins)") # +8
	assert_str(drawer_status(FLOAT, swap(exact, 10000, 100, 1))).is_equal("Major Discrepancy (correct total, but an implausible mix of bills and coins)") # +99
	# The float's own mix with a $1 bill counted out as 100 pennies: implausible.
	var padded := swap(TellerScreen.STARTING_FLOAT_MIX, 100, 1, 1)
	assert_str(drawer_status(FLOAT, padded, plausible)).starts_with("Major Discrepancy")

	# The teller grades the closing count in the same buckets.
	assert_int(ts._categorize_discrepancy(0, DrawerCountScreen.PERFECT_BILL_COUNT_TOLERANCE)).is_equal(TellerScreen.DiscrepancyResult.PERFECT)
	assert_int(ts._categorize_discrepancy(5000, 0)).is_equal(TellerScreen.DiscrepancyResult.MINOR)
	assert_int(ts._categorize_discrepancy(-5001, 0)).is_equal(TellerScreen.DiscrepancyResult.MAJOR)

func test_vault_thresholds_at_the_new_scale() -> void:
	var exact := CashDenominations.fewest_pieces(VaultReconciliationScreen.EXPECTED_VAULT_CENTS)
	assert_str(vault_status(exact)).is_equal("Perfect Count!")
	var minor := exact.duplicate()
	minor[index_of(10000)] += 5 # $500 over
	assert_str(vault_status(minor)).starts_with("Minor")
	var major := minor.duplicate()
	major[index_of(1)] += 1 # $500.01 over
	assert_str(vault_status(major)).starts_with("Major")
	assert_int(VaultReconciliationScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS).is_equal(10 * DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS)

# --- withdrawals --------------------------------------------------------------------

func test_withdrawals_never_exceed_the_drawer_cash() -> void:
	# A full shift of the largest requests still leaves cash in the drawer.
	assert_int(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP * CustomerQueue.INTENT_MAX_CENTS).is_less(FLOAT)
	clock_in()
	var rich := AccountManager.create_account("Pat Rich", 1000000)
	open_desk()
	select_account(rich)
	withdraw(3001.0)
	assert_bool(ts.error_label.visible).is_true()
	assert_str(ts.error_label.text).is_equal("Not enough cash in the drawer ($3000.00).")
	assert_int(rich.balance_cents).is_equal(1000000)
	assert_bool(ts.shift_transactions.is_empty()).is_true()
	# The whole drawer can go, and then nothing more.
	withdraw(3000.0)
	assert_int(ts.drawer_cash_cents()).is_equal(0)
	assert_int(rich.balance_cents).is_equal(1000000 - FLOAT)
	withdraw(1.0)
	assert_str(ts.error_label.text).is_equal("Not enough cash in the drawer ($0.00).")
	# A cash deposit refills it.
	deposit(20.0)
	withdraw(20.0)
	assert_int(ts.drawer_cash_cents()).is_equal(0)
	assert_int(ts.shift_transactions.size()).is_equal(3)
	close_desk()

# --- layout ---------------------------------------------------------------------------

## Bills on the left, coins on the right; with its result showing, each
## screen fits the 1152x648 window.
func test_the_count_screens_fit_the_window() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	# Each count screen opens over its desk's screen.
	open_desk()
	room.branch_manager_screen.visible = true
	for screen: Control in [dcs, vault]:
		var inputs: Array[SpinBox] = dcs.quantity_inputs if screen == dcs else vault.quantity_inputs
		if screen == dcs:
			dcs.show_screen(FLOAT)
		else:
			vault.show_screen()
		enter(inputs, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
		(screen.get_node("Panel/VBox/SubmitButton") as Button).pressed.emit()
		var panel: Control = screen.get_node("Panel")
		# Centred and growing both ways, so it fits while no taller than the window.
		var height: float = await settled_height(panel)
		assert_float(height).override_failure_message("%s panel is %d px tall" % [screen.name, height]).is_less_equal(648.0)
		assert_float(panel.size.x).is_less_equal(1152.0)
		# Two columns: every bill left of every coin, the $1 and penny rows last.
		for i in CashDenominations.FIRST_COIN:
			for j in range(CashDenominations.FIRST_COIN, inputs.size()):
				assert_float(inputs[i].get_global_rect().position.x).is_less(inputs[j].get_global_rect().position.x)
		assert_float(inputs[1].get_global_rect().position.y).is_greater(inputs[0].get_global_rect().position.y)
		assert_float(inputs[CashDenominations.FIRST_COIN].get_global_rect().position.y).is_equal_approx(inputs[0].get_global_rect().position.y, 1.0)
		(screen.get_node("Panel/VBox/CloseButton") as Button).pressed.emit()
	room.branch_manager_screen.visible = false
	close_desk()
	get_tree().root.size = window_before
