extends "res://tests/support/shared/room_suite.gd"

## Base for suites that work the Player Teller Window the way a player would:
## clock in, serve customers through TellerScreen's buttons, move cash at the
## vault door and clock out through the drawer count. Everything about the
## room itself is in the shared suite (room_suite.gd). The Teller's helpers
## (Liam's) go here.
##
## Not a test suite itself (no test_ functions) — suites extend it by path.

var ts: TellerScreen

func before_test() -> void:
	await super()
	ts = room.get_node("UI/TellerScreen")

func adopt_room(new_room: TellerRoom, keep_onboarding: bool = false) -> void:
	super(new_room, keep_onboarding)
	ts = room.get_node("UI/TellerScreen")

func teller_slots() -> TellerSlotAdapter:
	return room.get_node("TellerSlotAdapter")

func open_desk() -> void:
	if not ts.visible:
		room._on_teller_desk_interacted()

func close_desk() -> void:
	ts.close_button.pressed.emit()

## Enters `target_cents` into the drawer count with the fewest bills (a
## plausible count), plus one extra $10 bill for a Minor discrepancy, then
## submits and closes the count screen.
func count_drawer(target_cents: int, minor: bool = false) -> void:
	var dcs := ts.drawer_count_screen
	var remaining := target_cents
	for i in DrawerCountScreen.DENOMINATION_CENTS.size():
		var denom := DrawerCountScreen.DENOMINATION_CENTS[i]
		var quantity := floori(float(remaining) / denom)
		dcs.quantity_inputs[i].value = quantity
		remaining -= quantity * denom
	if minor:
		dcs.quantity_inputs[DrawerCountScreen.DENOMINATION_CENTS.find(1000)].value += 1
	dcs.submit_button.pressed.emit()
	dcs.close_button.pressed.emit()

func clock_in() -> void:
	open_desk()
	ts.clock_in_button.pressed.emit()
	count_drawer(TellerScreen.STARTING_FLOAT_CENTS)
	close_desk()
	cq.spawn_timer.stop()

## What a careful teller does before clocking out: sends whatever the
## drawer holds over its limit to the vault (TellerScreen.DRAWER_MAX_CENTS),
## at the vault door, so the clock-out isn't a drawer-limit mistake.
func send_excess_to_vault() -> void:
	var excess := ts.drawer_cash_cents() - TellerScreen.DRAWER_MAX_CENTS
	if excess > 0:
		vault_transfer(true, ceili(excess / 100.0))

## A teller's transfer at the vault door: `dollars` sent to the vault
## (`send`) or got from it, then the vault closed and the witness walked back.
func vault_transfer(send: bool, dollars: int) -> void:
	var witness := call_vault_witness()
	var vault := room.vault_transfer_screen
	assert_bool(vault.visible).override_failure_message("the vault didn't open").is_true()
	vault.amount_input.value = dollars
	(vault.send_button if send else vault.get_button).pressed.emit()
	vault.close_button.pressed.emit()
	if is_instance_valid(witness):
		witness.finish_route()

## Presses Clock Out and, if the gate lets it through, counts the drawer.
## Returns false (and leaves the shift running) when clock-out was blocked.
## The day goes to Closing first (to_closing()), where the
## shift ends.
func clock_out(minor: bool = false) -> bool:
	to_closing()
	open_desk()
	ts.clock_out_button.pressed.emit()
	if not ts.drawer_count_screen.visible:
		return false
	count_drawer(ts._calculate_expected_ending_cents(), minor)
	return true

## Spawns one customer at the back of the player's line with a fixed cash
## request (no complaint), so grading never depends on random rolls.
## `amount` is in dollars, like the amounts tests type into the teller's
## SpinBox (deposit()/withdraw()).
func spawn(intent_type: ShiftTransaction.Type = ShiftTransaction.Type.DEPOSIT, amount: float = 500.0) -> CustomerNPC:
	cq._spawn_customer()
	var customer: CustomerNPC = cq.queue[-1]
	customer.complaint = null
	customer.intent_type = intent_type
	customer.intent_amount_cents = MoneyMath.to_cents(amount)
	customer.payment_method = ShiftTransaction.PaymentMethod.CASH
	var line := CustomerDialogueLine.new()
	line.text = "I'd like to %s $%.0f." % ["deposit" if intent_type == ShiftTransaction.Type.DEPOSIT else "withdraw", amount]
	customer.dialogue_line = line
	give_id(customer, IdCard.Problem.NONE)
	return customer

## Gives `customer` a fresh ID card with `problem` (see KycPolicy).
func give_id(customer: CustomerNPC, problem: IdCard.Problem) -> void:
	customer.id_card = KycPolicy.issue_card(cq.kyc_rng, customer.display_name, customer.look_index, GameClock.today_date(), problem, CustomerNPC.CUSTOMER_FRAME_SETS.size())

## Spawns an account-opening customer (no account yet) asking to open one
## with `amount` dollars, with an ID showing `problem`.
func spawn_opener(amount: float = 200.0, problem: IdCard.Problem = IdCard.Problem.NONE) -> CustomerNPC:
	# Every regular customer opens an account; a complaint customer (rolled
	# separately) is sent away and the next one tried.
	cq.account_opening_chance = 1.0
	var customer: CustomerNPC = null
	for attempt in 20:
		cq._spawn_customer()
		customer = cq.queue[-1]
		if customer.opens_account:
			break
		cq.queue.pop_back()
		cq._customers_spawned_this_shift -= 1
		customer.free()
	cq.account_opening_chance = 0.0
	assert_bool(customer.opens_account).is_true()
	customer.intent_amount_cents = MoneyMath.to_cents(amount)
	customer.dialogue_line.text = "I'd like to open an account with %s." % MoneyMath.format(customer.intent_amount_cents, true)
	customer.payment_method = ShiftTransaction.PaymentMethod.CASH
	give_id(customer, problem)
	return customer

func check_id() -> void:
	ts.check_id_button.pressed.emit()

func refuse_service() -> void:
	ts.refuse_service_button.pressed.emit()

## Opens an account in `holder`'s name through Open New Account, with a
## starting deposit of `starting` dollars.
func open_account(holder: String, starting: float = 0.0) -> void:
	ts.open_account_button.pressed.emit()
	ts.new_name_input.text = holder
	ts.new_balance_input.value = starting
	ts.create_account_button.pressed.emit()

func deposit(amount: float) -> void:
	ts.amount_input.value = amount
	ts.deposit_button.pressed.emit()

func withdraw(amount: float) -> void:
	ts.amount_input.value = amount
	ts.withdraw_button.pressed.emit()

func complete() -> void:
	ts.complete_transaction_button.pressed.emit()

func reverse() -> void:
	ts.reverse_transaction_button.pressed.emit()

## Selects `target` in the teller's account dropdown, as the player would.
func select_account(target: Account) -> void:
	var index := ts._browsable_accounts.find(target)
	assert_int(index).is_not_equal(-1)
	ts.account_option_button.select(index)
	ts._on_account_option_selected(index)

## Serves the front customer correctly in one visit and closes the desk,
## checking their ID first when the request needs it.
func serve_correctly(customer: CustomerNPC) -> void:
	open_desk()
	if KycPolicy.requires_id(customer):
		check_id()
	if customer.intent_type == ShiftTransaction.Type.DEPOSIT:
		deposit(customer.intent_amount_cents / 100.0)
	else:
		withdraw(customer.intent_amount_cents / 100.0)
	complete()
	close_desk()

func abandon(customer: CustomerNPC) -> void:
	customer.patience_expired.emit()
