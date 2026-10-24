extends GdUnitTestSuite

## Base for suites that drive the real teller room (scenes/world/teller_room.tscn)
## the way a player would: clock in, serve customers through TellerScreen's
## buttons, clock out through the drawer count. Each test gets a fresh room
## and a fresh career (CareerReset), and the global RNG is seeded so
## spawned names, staff timing and mistakes are the same every run.
##
## The room saves the career at clock-outs (SaveGame), so every test points
## SaveGame at TEST_SAVE_PATH and starts and ends without a save there: tests
## never read or write the real save.
##
## Not a test suite itself (no test_ functions) — suites extend it by path.

const TELLER_ROOM_SCENE := "res://scenes/world/teller_room.tscn"
const RNG_SEED := 20261012
## Test save files are named from this instead of SaveGame.REAL_PREFIX:
## "user://test_career_slot_<n>.json", and the old single save
## "user://test_career.json". Every test plays in Slot 1 (TEST_SAVE_PATH)
## unless it picks another.
const TEST_PREFIX := "user://test_career"
const TEST_SAVE_PATH := "user://test_career_slot_1.json"

var room: TellerRoom
var ts: TellerScreen
var cq: CustomerQueue

func before_test() -> void:
	seed(RNG_SEED)
	use_test_save_path()
	use_interview_setting(InterviewManager.INTERVIEW_ENABLED)
	CareerReset.reset_all()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	ts = room.get_node("UI/TellerScreen")
	cq = room.get_node("CustomerQueue")
	# Customers in these tests are spawned explicitly (spawn()).
	cq.spawn_timer.stop()

## Makes `new_room` (one a scene change loaded, e.g. from the slot screen)
## the room the helpers below drive, as before_test() does for the first.
func adopt_room(new_room: TellerRoom) -> void:
	room = new_room
	ts = room.get_node("UI/TellerScreen")
	cq = room.get_node("CustomerQueue")
	cq.spawn_timer.stop()

## A fresh, not yet added, teller room.
func instantiate_room() -> TellerRoom:
	var scene: PackedScene = load(TELLER_ROOM_SCENE)
	return scene.instantiate() as TellerRoom

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
	use_test_save_path()
	use_interview_setting(InterviewManager.INTERVIEW_ENABLED)
	# Let queue_free()'d nodes (rebuilt UI rows, re-placed staff) actually go
	# before gdUnit's orphan check.
	await get_tree().process_frame

## Points SaveGame at the test save files (TEST_PREFIX), plays Slot 1
## (TEST_SAVE_PATH), and removes every test save (all slots, the old single
## save, and the files SaveGame writes beside them).
func use_test_save_path() -> void:
	SaveGame.use_saves_named(TEST_PREFIX)
	# Opening the start screen allows the real saves; tests start without it.
	SaveGame.real_prefix = SaveGame.REAL_PREFIX
	SaveGame.real_save_allowed = false
	StartScreen.next_view = StartScreen.View.MAIN_MENU
	var files: Array[String] = [SaveGame.legacy_path()]
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		files.append(SaveGame.slot_path(slot))
	for file in files:
		for leftover: String in [file, file + ".tmp", file + ".bad"]:
			if FileAccess.file_exists(leftover):
				DirAccess.remove_absolute(leftover)

## Turns the hiring interview on or off for this test (the game reads
## InterviewManager.interview_enabled; the INTERVIEW_ENABLED switch is its
## default, restored before and after every test). Tests whose result
## depends on the interview set it explicitly, so they pass whichever way
## the switch is set.
func use_interview_setting(enabled: bool) -> void:
	InterviewManager.interview_enabled = enabled

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

## The HUD column's left edge at 1152x648: screens stay left of it.
const HUD_COLUMN_LEFT: float = 952.0
## Room screens keep from the window's edges, so they never just scrape in.
const WINDOW_MARGIN: float = 8.0

## `panel` (a screen's content panel), laid out, sits inside the 1152x648
## window with a WINDOW_MARGIN to spare and left of the HUD column, and so does every visible control in
## it, each also inside the panel. Controls inside a ScrollContainer scroll
## within it, so the container stands for them. Returns the problems found
## (one line each), so a test can assert there are none.
func layout_problems(panel: Control) -> Array[String]:
	var window := Rect2(0, 0, 1152, 648).grow(-WINDOW_MARGIN)
	var problems: Array[String] = []
	var panel_rect := panel.get_global_rect()
	var checked: Array[Control] = [panel]
	for node in panel.find_children("*", "Control", true, false):
		checked.append(node as Control)
	for control in checked:
		if not control.is_visible_in_tree() or control.size.x <= 0.0 or control.size.y <= 0.0:
			continue
		if _scrolls_inside(control, panel):
			continue
		# Half a pixel of rounding either way.
		var rect := control.get_global_rect().grow(-0.5)
		var label := str(panel.get_path_to(control)) if control != panel else str(panel.name)
		if control != panel and not panel_rect.encloses(rect):
			problems.append("%s %s leaves the panel %s" % [label, rect, panel_rect])
		if not window.encloses(rect):
			problems.append("%s %s comes within %d px of the 1152x648 window's edge" % [label, rect, WINDOW_MARGIN])
		if rect.end.x > HUD_COLUMN_LEFT:
			problems.append("%s %s runs under the HUD column (x >= %d)" % [label, rect, HUD_COLUMN_LEFT])
	return problems

func _scrolls_inside(control: Control, panel: Control) -> bool:
	var node := control.get_parent()
	while node != null and node != panel:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false

## Career totals, for before/after deltas.
func totals() -> Vector3i:
	return Vector3i(ScoreManager.total_score, ReputationManager.reputation, XPManager.total_xp)
