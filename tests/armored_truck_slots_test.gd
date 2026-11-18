extends "res://tests/support/teller_room_suite.gd"

## The armored truck on the time-slot day (ArmoredTruckSlot): the crew comes
## when the 9 AM slot starts; on a Teller or Loan Officer day the NPC branch
## manager receives them and nothing waits; on a Branch Manager day they hold
## 9 AM until received, even after "End this slot"; a skipped 9 AM lets them
## go with no penalty; and with nobody to witness they leave, missed.

const STRAP := VaultManager.STRAP_CENTS
const DAY := 4

var truck: ArmoredTruckVisit
var truck_slot: ArmoredTruckSlot
var manager: ManagerSlotAdapter
var screen: ArmoredTruckScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	truck = room.armored_visit
	truck_slot = room.get_node("ArmoredTruckSlot")
	manager = room.get_node("ManagerSlotAdapter")
	screen = room.armored_truck_screen
	window_before = get_tree().root.size
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)
	# Day DAY, with cash ordered the day before: the truck comes today.
	GameClock.day = DAY
	BusinessDay.stats_day = DAY
	assert_str(VaultManager.place_order(7 * STRAP, DAY - 1)).is_empty()

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

## The crew's walk in skipped: they're at the vault door.
func crew_at_the_door() -> void:
	assert_int(truck.guards.size()).is_equal(2)
	for guard: StaffNPC in truck.guards.duplicate():
		guard.finish_route()

func manager_day_at_9am() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	start_slots_day()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)

## Received at the vault door with a witness: crew checked, bags signed for.
func receive_and_sign() -> void:
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	var control := room.vault_control
	assert_int(control.purpose).is_equal(VaultDualControl.Purpose.ARMORED)
	control._process(0.0)
	control.witness.finish_route()
	control._process(0.0)
	assert_bool(screen.visible).is_true()
	screen.accept_crew_button.pressed.emit()
	screen.sign_button.pressed.emit()
	screen.close_button.pressed.emit()

func test_on_a_teller_day_the_npc_manager_receives_them_and_nothing_waits() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.WALKING_IN)
	assert_bool(truck_slot.is_holding()).is_false()
	assert_bool(DayFlow.is_held()).is_false()
	crew_at_the_door()
	# Signed by the NPC branch manager, and on their way out.
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS + 7 * STRAP)
	assert_bool(VaultManager.has_visit_due(DAY)).is_false()

func test_the_9_am_slot_waits_for_the_truck_on_a_manager_day() -> void:
	manager_day_at_9am()
	assert_bool(truck_slot.is_holding()).is_true()
	assert_bool(DayFlow.is_held()).is_true()
	crew_at_the_door()
	assert_bool(truck.is_waiting()).is_true()
	assert_str(room.desk_notice_label.text).is_equal(ArmoredTruckVisit.ARRIVED_TEXT)
	# "End this slot" isn't enough: the slot waits for the truck.
	manager.bar.end_button.pressed.emit()
	await frames(3)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()
	assert_str(manager.bar.label.text).is_equal(EndSlotBar.HELD_TEXT % "9 AM")
	assert_bool(manager.bar.end_button.disabled).is_true()
	# Received: the slot ends.
	var score := ScoreManager.total_score
	receive_and_sign()
	assert_int(ScoreManager.total_score).is_equal(score + ArmoredTruckScreen.CORRECT_SCORE)
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)
	assert_bool(truck_slot.is_holding()).is_false()

## "End this slot" pressed while the truck is being received (the witness on
## the way to the vault door): the slot still waits until receiving is done.
func test_end_this_slot_while_receiving_waits_for_the_receiving() -> void:
	manager_day_at_9am()
	crew_at_the_door()
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	var control := room.vault_control
	assert_int(control.purpose).is_equal(VaultDualControl.Purpose.ARMORED)
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.BEING_RECEIVED)
	control._process(0.0)
	# The witness is still walking: the room runs, and the bar is up.
	await frames(1)
	assert_bool(manager.bar.visible).is_true()
	manager.bar.end_button.pressed.emit()
	await frames(3)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()
	assert_bool(truck_slot.is_holding()).is_true()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.BEING_RECEIVED)
	# The witness arrives; the crew is checked and the bags signed for.
	control.witness.finish_route()
	control._process(0.0)
	assert_bool(screen.visible).is_true()
	screen.accept_crew_button.pressed.emit()
	screen.sign_button.pressed.emit()
	screen.close_button.pressed.emit()
	await frames(2)
	# Only now does the slot end.
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)

func test_received_before_end_this_slot_the_slot_waits_for_the_button() -> void:
	manager_day_at_9am()
	crew_at_the_door()
	receive_and_sign()
	await frames(2)
	assert_bool(DayFlow.is_held()).is_false()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	manager.end_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_a_skipped_9_am_on_a_truck_day_lets_the_crew_go_with_no_penalty() -> void:
	manager_day_at_9am()
	crew_at_the_door()
	var skipped: Array[StringName] = []
	var on_skip := func(slot: DaySlot) -> void: skipped.append(slot.id)
	DayFlow.slot_skipped.connect(on_skip)
	var score := ScoreManager.total_score
	var reputation := ReputationManager.reputation
	DayFlow.skip_slot()
	# The skip waits for the hold, which lets go at the next frame.
	await frames(2)
	DayFlow.slot_skipped.disconnect(on_skip)
	assert_array(skipped).is_equal([DaySchedule.SLOT_9AM])
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	assert_int(ScoreManager.total_score).is_equal(score)
	assert_int(ReputationManager.reputation).is_equal(reputation)
	# The cash comes the next business day.
	assert_bool(VaultManager.has_visit_due(DAY + 1)).is_true()
	assert_int(VaultManager.expected_cents).is_equal(VaultReconciliationScreen.STARTING_VAULT_CENTS)

func test_with_nobody_to_witness_the_crew_leaves_missed() -> void:
	manager_day_at_9am()
	crew_at_the_door()
	# Every desk empty (as after terminating everyone).
	room._staff_by_slot.clear()
	assert_array(room.vault_witness_candidates()).is_empty()
	var score := ScoreManager.total_score
	await frames(2)
	assert_bool(truck_slot.is_holding()).is_false()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	assert_int(ScoreManager.total_score).is_equal(score + ArmoredTruckVisit.MISSED_SCORE)
	manager.end_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_no_cash_to_move_no_truck() -> void:
	VaultManager.pending_orders.clear()
	manager_day_at_9am()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.IDLE)
	assert_bool(DayFlow.is_held()).is_false()

func test_the_waiting_bar_fits() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	manager_day_at_9am()
	crew_at_the_door()
	manager.end_slot()
	await frames(2)
	assert_str(manager.bar.label.text).is_equal(EndSlotBar.HELD_TEXT % "9 AM")
	assert_array(layout_problems(manager.bar.panel)).is_empty()
