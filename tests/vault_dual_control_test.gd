extends "res://tests/support/teller_room_suite.gd"

## Dual control for the vault (VaultDualControl, the vault door, the vault
## transfer screen and the Branch Manager's reconciliation): no vault action
## with one person; who is called as the witness; their window pausing and
## resuming; nobody free; history and receipts naming both people; the
## accounting staying exact; the one-time hint; the screens fitting.

var control: VaultDualControl

func before_test() -> void:
	await super()
	control = room.vault_control
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func staff_at(slot_name: String) -> StaffNPC:
	return room._staff_by_slot[slot_name]

## Takes the three loan officers (always idle: no customer line) out of the
## running, as if each were walking somewhere, so a teller is called.
func loan_officers_away() -> void:
	for slot_name in ScheduleManager.LOAN_DESK_SLOTS:
		staff_at(slot_name).state = StaffNPC.State.WALKING

## `count` customers waiting in `line` (a staff window), the first one at the
## window.
func fill_line(line: NpcCustomerLine, count: int) -> Array[CustomerNPC]:
	var added: Array[CustomerNPC] = []
	for i in count:
		line._spawn_customer()
		var customer: CustomerNPC = line.queue[-1]
		customer.queue_spot = line.queue.size() - 1
		customer.global_position = line.queue_positions[customer.queue_spot].global_position
		added.append(customer)
	return added

func choose() -> StaffNPC:
	var chosen := VaultDualControl.choose_witness(room.vault_witness_candidates(), room.vault_door.global_position)
	return chosen["npc"] if not chosen.is_empty() else null

# --- one person is never enough ---------------------------------------------------

func test_no_vault_action_with_one_person() -> void:
	clock_in()
	# The accounting itself refuses a transfer without a witness.
	assert_str(ts.send_to_vault(10000, "")).is_equal(VaultDualControl.NEEDS_TWO_TEXT)
	assert_str(ts.get_from_vault(10000, " ")).is_equal(VaultDualControl.NEEDS_TWO_TEXT)
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)

	# At the door, the vault stays shut while the witness is on the way.
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	control._process(0.0)
	assert_int(control.phase).is_equal(VaultDualControl.Phase.WALKING_IN)
	var witness := control.witness
	await get_tree().process_frame
	assert_bool(room.vault_transfer_screen.visible).is_false()
	var waiting := "Dual control: the vault needs two people. Waiting for %s…" % witness.staff.staff_name
	assert_str(room.desk_notice_label.text).is_equal(waiting)
	assert_bool(room.desk_notice.visible).is_true()
	assert_str(room.interaction_prompt_text(room.vault_door)).is_equal("Waiting for %s…" % witness.staff.staff_name)
	# Both there: it opens, naming them.
	witness.finish_route()
	assert_int(witness.state).is_equal(StaffNPC.State.AT_VAULT)
	control._process(0.0)
	assert_bool(room.vault_transfer_screen.visible).is_true()
	assert_str(room.vault_transfer_screen.dual_control_label.text).is_equal("Dual control: you and %s" % witness.staff.staff_name)
	# The waiting notice is gone as the vault opens (the room is paused then).
	assert_bool(room.desk_notice.visible).is_false()
	room.vault_transfer_screen.close_button.pressed.emit()
	await get_tree().process_frame
	assert_bool(room.desk_notice.visible).is_false()

func test_walking_away_before_the_witness_arrives_calls_it_off() -> void:
	clock_in()
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	control._process(0.0)
	var witness := control.witness
	room.vault_door.player_in_range = false
	control._process(0.0)
	assert_int(control.phase).is_equal(VaultDualControl.Phase.IDLE)
	# They head back to their desk, and the vault never opened.
	assert_int(witness.state).is_equal(StaffNPC.State.WALKING)
	witness.finish_route()
	assert_int(witness.state).is_equal(StaffNPC.State.AT_DESK)
	assert_bool(room.vault_transfer_screen.visible).is_false()

func test_the_vault_door_needs_a_shift() -> void:
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	assert_int(control.phase).is_equal(VaultDualControl.Phase.IDLE)
	assert_str(room.desk_notice_label.text).is_equal(TellerRoom.VAULT_NEEDS_SHIFT_TEXT)
	assert_str(room.interaction_prompt_text(room.vault_door)).is_equal(TellerRoom.VAULT_NEEDS_SHIFT_TEXT)
	clock_in()
	assert_str(room.interaction_prompt_text(room.vault_door)).is_equal("E — Vault transfer (dual control)")

func test_the_teller_screen_points_to_the_vault_door() -> void:
	clock_in()
	open_desk()
	await get_tree().process_frame
	var pointer: Label = ts.get_node("DrawerPanel/VBox/VaultDoorLabel")
	assert_bool(pointer.is_visible_in_tree()).is_true()
	assert_str(pointer.text).contains("vault door")
	# The transfer buttons are gone from the teller screen.
	assert_object(ts.get_node_or_null("DrawerPanel/VBox/SendButton")).is_null()
	assert_object(ts.get_node_or_null("DrawerPanel/VBox/GetButton")).is_null()

# --- who comes ------------------------------------------------------------------

func test_an_idle_loan_officer_nearest_the_vault_comes_first() -> void:
	# Loan officers have no customer line, so they're idle; Loan Desk 2 is
	# right below the vault.
	fill_line(room.window1_npc_line, 1)
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_LOAN_DESK_2))

func test_an_idle_teller_comes_before_a_busy_one() -> void:
	loan_officers_away()
	# Teller Window 2 is idle; Teller Window 1 nearer the vault but serving.
	var customers := fill_line(room.window1_npc_line, 1)
	room.window1_npc_line._serving = customers[0]
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_2))
	# Both idle: the nearer.
	room.window1_npc_line._serving = null
	room.window1_npc_line.queue.clear()
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_1))

func test_someone_in_the_break_room_counts_as_idle() -> void:
	loan_officers_away()
	fill_line(room.window1_npc_line, 3)
	fill_line(room.window2_line, 1)
	staff_at(ScheduleManager.SLOT_TELLER_WINDOW_1).state = StaffNPC.State.ON_BREAK
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_1))

func test_with_everyone_busy_the_shortest_line_comes() -> void:
	loan_officers_away()
	fill_line(room.window1_npc_line, 3)
	fill_line(room.window2_line, 1)
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_2))
	# A tie: the nearer.
	fill_line(room.window2_line, 2)
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_1))

func test_a_closed_window_or_someone_walking_never_comes() -> void:
	loan_officers_away()
	# Teller Window 1's line is closed: even idle, its staff member isn't called.
	room.window1_npc_line.active = false
	fill_line(room.window2_line, 2)
	assert_object(choose()).is_same(staff_at(ScheduleManager.SLOT_TELLER_WINDOW_2))
	staff_at(ScheduleManager.SLOT_TELLER_WINDOW_2).state = StaffNPC.State.WALKING
	assert_object(choose()).is_null()

func test_with_no_one_free_the_vault_stays_shut() -> void:
	clock_in()
	for npc: StaffNPC in room._staff_by_slot.values():
		npc.state = StaffNPC.State.WALKING
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	assert_int(control.phase).is_equal(VaultDualControl.Phase.IDLE)
	assert_str(room.desk_notice_label.text).is_equal("No one is free to witness the vault right now.")
	control._process(0.0)
	assert_bool(room.vault_transfer_screen.visible).is_false()

# --- the witness's window ------------------------------------------------------------

func test_the_witnesss_window_pauses_and_resumes() -> void:
	clock_in()
	loan_officers_away()
	var line := room.window1_npc_line
	var teller := staff_at(ScheduleManager.SLOT_TELLER_WINDOW_1)
	var customers := fill_line(line, 2)
	fill_line(room.window2_line, 3)
	line._process(0.0) # serving the first customer
	assert_bool(line.is_serving()).is_true()

	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	assert_object(control.witness).is_same(teller)
	assert_bool(line.paused_for_vault).is_true()
	# They finish the customer at the window first.
	control._process(0.0)
	assert_int(control.phase).is_equal(VaultDualControl.Phase.FINISHING)
	assert_int(teller.state).is_equal(StaffNPC.State.AT_DESK)
	line._complete_service()
	control._process(0.0)
	assert_int(control.phase).is_equal(VaultDualControl.Phase.WALKING_IN)

	# Away: the next customer stays in line, unserved, and keeps waiting.
	var waiting := customers[1]
	waiting.queue_spot = 0
	waiting.global_position = line.queue_positions[0].global_position
	line._process(0.0)
	assert_bool(line.is_serving()).is_false()
	assert_array(line.queue).contains([waiting])
	var waited := waiting.wait_seconds
	waiting._process(5.0)
	assert_float(waiting.wait_seconds).is_greater(waited)
	# A long wait costs them the customer.
	var abandoned: Array[CustomerNPC] = []
	line.customer_abandoned.connect(func(c: CustomerNPC) -> void: abandoned.append(c))
	waiting.wait_seconds = CustomerNPC.WAIT_ABANDON_SECONDS
	waiting._process(0.1)
	assert_array(abandoned).contains_exactly([waiting])

	# Back at the desk: the window serves again.
	teller.finish_route()
	control._process(0.0)
	room.vault_transfer_screen.close_button.pressed.emit()
	teller.finish_route()
	assert_int(teller.state).is_equal(StaffNPC.State.AT_DESK)
	assert_bool(line.paused_for_vault).is_false()
	var next := fill_line(line, 1)[0]
	next.queue_spot = 0
	next.global_position = line.queue_positions[0].global_position
	line._process(0.0)
	assert_bool(line.is_serving()).is_true()

# --- the Branch Manager ------------------------------------------------------------------

func promote_and_clock_in() -> BranchManagerScreen:
	XPManager._grant_branch_manager()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	return bm

func test_branch_manager_reconciliation_needs_a_witness() -> void:
	var bm := promote_and_clock_in()
	# The hub only points to the vault door.
	assert_bool(bm.vault_reconciliation_button.disabled).is_true()
	assert_str(bm.vault_reconciliation_button.text).is_equal(BranchManagerScreen.VAULT_AT_DOOR_TEXT)
	bm.open_vault_reconciliation("")
	assert_bool(bm.vault_reconciliation_screen.is_visible_in_tree()).is_false()
	bm.hide_screen()

	# At the door: shut until the witness comes.
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	assert_int(control.purpose).is_equal(VaultDualControl.Purpose.RECONCILIATION)
	control._process(0.0)
	var witness := control.witness
	assert_bool(bm.vault_reconciliation_screen.is_visible_in_tree()).is_false()
	witness.finish_route()
	control._process(0.0)
	assert_bool(bm.vault_reconciliation_screen.is_visible_in_tree()).is_true()
	var pieces := CashDenominations.fewest_pieces(VaultManager.expected_cents)
	for i in pieces.size():
		bm.vault_reconciliation_screen.quantity_inputs[i].value = pieces[i]
	bm.vault_reconciliation_screen.submit_button.pressed.emit()
	assert_str(HistoryManager.records[-1].description).is_equal("Vault reconciliation: Perfect (discrepancy $0.00) — dual control: you and %s" % witness.staff.staff_name)
	# Closing it closes the screen (the player is at the vault) and sends the
	# witness back; their time away goes into the Branch summary.
	bm.vault_reconciliation_screen.close_button.pressed.emit()
	assert_bool(bm.visible).is_false()
	GameClock.minutes += 6.0
	witness.finish_route()
	assert_float(bm.shift_vault_minutes[witness.staff.staff_name]).is_equal_approx(6.0, 0.01)
	# Once a shift.
	room._on_vault_door_interacted()
	assert_int(control.phase).is_equal(VaultDualControl.Phase.IDLE)
	assert_str(room.desk_notice_label.text).is_equal(TellerRoom.VAULT_RECONCILED_TEXT)
	bm.show_screen()
	bm.clock_out_button.pressed.emit()
	assert_str(bm.shift_branch_label.text).contains("At the vault: %s 6 min" % witness.staff.staff_name)

# --- records and accounting ---------------------------------------------------------------

func test_history_and_receipt_name_both_people() -> void:
	clock_in()
	var expected_witness := staff_at(ScheduleManager.SLOT_LOAN_DESK_2).staff.staff_name
	vault_transfer(false, 500)
	vault_transfer(true, 500)
	var receipt := "Sold $500 to the vault · witnessed by %s" % expected_witness
	assert_str(room.vault_transfer_screen.receipt_label.text).is_equal(receipt)
	assert_str(ts.transfer_receipt_label.text).is_equal(receipt)
	var transfers: Array[String] = []
	for record in HistoryManager.records:
		if record.grade_label == "Vault transfer":
			transfers.append(record.description)
	assert_array(transfers).contains_exactly([
		"Bought $500 from the vault — dual control: you and %s" % expected_witness,
		"Sold $500 to the vault — dual control: you and %s" % expected_witness,
	])

func test_accounting_stays_exact_through_the_vault_door() -> void:
	clock_in()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 437))
	vault_transfer(true, 900)
	vault_transfer(false, 125)
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS + 43700 - 90000 + 12500)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS + 90000 - 12500)
	# A visit called off changes nothing.
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	control._process(0.0)
	var witness := control.witness
	room.vault_door.player_in_range = false
	control._process(0.0)
	witness.finish_route()
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS + 90000 - 12500)
	while cq.get_customers_left_to_spawn() > 0:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	assert_str(ts.shift_final_discrepancy_label.text).is_equal("Final Discrepancy: $0.00")

# --- the hint and the screen ------------------------------------------------------------

func test_the_vault_door_hint_shows_once() -> void:
	HintManager.reset()
	for hint: int in HintManager.Hint.values():
		if hint != HintManager.Hint.VAULT_DOOR:
			HintManager.mark_shown(hint)
	while room.hud.current_hint != -1:
		room.hud.dismiss_hint()
	clock_in()
	vault_transfer(true, 10)
	assert_bool(HintManager.has_shown(HintManager.Hint.VAULT_DOOR)).is_true()
	assert_int(room.hud.current_hint).is_equal(HintManager.Hint.VAULT_DOOR)
	assert_str(room.hud.hint_label.text).contains("nobody opens the vault alone")
	room.hud.dismiss_hint()
	vault_transfer(true, 10)
	assert_int(room.hud.current_hint).is_equal(-1)

func test_the_vault_transfer_screen_fits_the_window() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	clock_in()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 500))
	call_vault_witness()
	var vault := room.vault_transfer_screen
	vault.amount_input.value = 50
	vault.send_button.pressed.emit()
	vault.amount_input.value = 999999
	vault.send_button.pressed.emit() # an error too
	for i in 4:
		await get_tree().process_frame
	assert_bool(vault.receipt_label.visible).is_true()
	assert_bool(vault.error_label.visible).is_true()
	assert_bool(vault.warning_label.visible).is_true()
	var problems := layout_problems(vault.panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	vault.close_button.pressed.emit()
	get_tree().root.size = window_before
