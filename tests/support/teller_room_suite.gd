extends GdUnitTestSuite

## Base for suites that drive the real teller room (scenes/world/teller_room.tscn)
## the way a player would: clock in, serve customers through TellerScreen's
## buttons, clock out through the drawer count. Each test gets a fresh room
## and a fresh career (CareerReset), and the global RNG is seeded so
## spawned names, staff timing and mistakes are the same every run.
##
## Not a test suite itself (no test_ functions) — suites extend it by path.

const TELLER_ROOM_SCENE := "res://scenes/world/teller_room.tscn"
const RNG_SEED := 20261012

var room: Node
var ts: TellerScreen
var cq: CustomerQueue

func before_test() -> void:
	seed(RNG_SEED)
	CareerReset.reset_all()
	room = load(TELLER_ROOM_SCENE).instantiate()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	ts = room.get_node("UI/TellerScreen")
	cq = room.get_node("CustomerQueue")
	# Customers in these tests are spawned explicitly (spawn()).
	cq.spawn_timer.stop()

func after_test() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var scene := get_tree().current_scene
	if is_instance_valid(room):
		room.free()
	# A test can change scene (e.g. termination -> interview); free that too.
	if is_instance_valid(scene) and scene != room:
		scene.free()
	room = null
	CareerReset.reset_all()
	# Let queue_free()'d nodes (rebuilt UI rows, re-placed staff) actually go
	# before gdUnit's orphan check.
	await get_tree().process_frame

# --- desk -------------------------------------------------------------------

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

## Presses Clock Out and, if the gate lets it through, counts the drawer.
## Returns false (and leaves the shift running) when clock-out was blocked.
func clock_out(minor: bool = false) -> bool:
	open_desk()
	ts.clock_out_button.pressed.emit()
	if not ts.drawer_count_screen.visible:
		return false
	count_drawer(ts._calculate_expected_ending_cents(), minor)
	return true

# --- customers --------------------------------------------------------------

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
	return customer

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

## Serves the front customer correctly in one visit and closes the desk.
func serve_correctly(customer: CustomerNPC) -> void:
	open_desk()
	if customer.intent_type == ShiftTransaction.Type.DEPOSIT:
		deposit(customer.intent_amount_cents / 100.0)
	else:
		withdraw(customer.intent_amount_cents / 100.0)
	complete()
	close_desk()

func abandon(customer: CustomerNPC) -> void:
	customer.patience_expired.emit()

## Height a centred, auto-sizing panel settles at for its designed width.
## (reset_size() would collapse autowrap labels to their minimum width and
## report a bogus height.) The game window is 648px tall.
func settled_height(panel: Control) -> float:
	var width := panel.offset_right - panel.offset_left
	var last := -1.0
	for i in 10:
		panel.size = Vector2(width, 0)
		await get_tree().process_frame
		await get_tree().process_frame
		if is_equal_approx(panel.size.y, last):
			break
		last = panel.size.y
	return panel.size.y

## Career totals, for before/after deltas.
func totals() -> Vector3i:
	return Vector3i(ScoreManager.total_score, ReputationManager.reputation, XPManager.total_xp)
