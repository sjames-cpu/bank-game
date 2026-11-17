extends "res://tests/support/teller_room_suite.gd"

## The Branch Manager's work slots (ManagerSlotAdapter, EndSlotBar): on a
## Branch Manager day each work slot waits for "End this slot", which works
## only inside a work slot; a clean slot earns +1 Reputation and one where
## Reputation fell (or a skipped one) doesn't; clocking out before Closing is
## refused; the bar fits the screen clear of the HUD and every "E — …"
## prompt; and on Teller and Loan Officer days nothing happens.

var adapter: ManagerSlotAdapter
var bar: EndSlotBar
var bm: BranchManagerScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	adapter = room.get_node("ManagerSlotAdapter")
	bar = adapter.bar
	bm = room.branch_manager_screen
	window_before = get_tree().root.size

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

## Promoted, clocked in as Branch Manager at Opening (the orientation letter
## read), with 9 AM started.
func manager_day_at_9am() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	start_slots_day()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)

func test_the_slot_waits_for_end_this_slot() -> void:
	manager_day_at_9am()
	assert_bool(adapter.is_claimed()).is_true()
	await frames(3)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()
	assert_bool(bar.visible).is_true()
	assert_str(bar.label.text).is_equal("9 AM slot")
	assert_bool(bar.end_button.disabled).is_false()

	bar.end_button.pressed.emit()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)
	await frames(1)
	assert_bool(bar.visible).is_false()

func test_the_button_does_nothing_outside_a_work_slot() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	start_slots_day()
	# Opening, before the clock-in.
	assert_bool(adapter.end_slot()).is_false()
	bar.refresh()
	assert_bool(bar.visible).is_false()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()
	# Between slots.
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(adapter.end_slot()).is_false()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_9AM)
	# Closing.
	for id: StringName in [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]:
		continue_to_slot(id)
		assert_bool(adapter.end_slot()).is_true()
		# Pressed once: the second press does nothing.
		assert_bool(adapter.end_slot()).is_false()
	continue_to_slot(DaySchedule.CLOSING)
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	assert_bool(adapter.end_slot()).is_false()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	bar.refresh()
	assert_bool(bar.visible).is_false()

func test_a_clean_slot_earns_one_reputation() -> void:
	manager_day_at_9am()
	var rep_before := ReputationManager.reputation
	var rewarded: Array[StringName] = []
	adapter.clean_slot_rewarded.connect(func(slot: DaySlot) -> void: rewarded.append(slot.id))
	# Reputation going up during the slot is still clean.
	ReputationManager.add_reputation(2)
	adapter.end_slot()
	assert_int(ReputationManager.reputation).is_equal(rep_before + 2 + DaySchedule.CLEAN_SLOT_REPUTATION)
	assert_array(rewarded).is_equal([DaySchedule.SLOT_9AM])

func test_a_slot_where_reputation_fell_earns_nothing() -> void:
	manager_day_at_9am()
	var rep_before := ReputationManager.reputation
	ReputationManager.add_reputation(-1)
	ReputationManager.add_reputation(3)
	adapter.end_slot()
	assert_int(ReputationManager.reputation).is_equal(rep_before + 2)
	# The next slot starts clean again.
	continue_to_slot(DaySchedule.SLOT_11AM)
	adapter.end_slot()
	assert_int(ReputationManager.reputation).is_equal(rep_before + 2 + DaySchedule.CLEAN_SLOT_REPUTATION)

func test_a_skipped_slot_earns_nothing() -> void:
	manager_day_at_9am()
	var rep_before := ReputationManager.reputation
	DayFlow.skip_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(adapter.is_claimed()).is_false()
	assert_int(ReputationManager.reputation).is_equal(rep_before)

func test_clocking_out_before_closing_is_refused() -> void:
	manager_day_at_9am()
	bm.show_screen()
	bm.clock_out_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_true()
	assert_str(bm.error_label.text).is_equal("Can't clock out yet — %s." % ShiftSlotAdapter.CLOCK_OUT_REFUSED_TEXT)
	bm.hide_screen()

func test_the_bar_fits_clear_of_the_hud_and_the_prompts() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	manager_day_at_9am()
	await frames(2)
	assert_bool(bar.visible).is_true()
	assert_array(layout_problems(bar.panel)).is_empty()
	var bar_rect := bar.panel.get_global_rect()
	# Every "E — …" prompt, at either zoom, with the player at its interactable.
	var camera := get_viewport().get_camera_2d() as RoomCamera
	for overview: bool in [false, true]:
		camera.set_overview(overview)
		for desk in room._interactables():
			room.player.global_position = desk.global_position
			camera.reset_smoothing()
			await frames(2)
			room.hud.show_prompt(room.interaction_prompt_text(desk), desk.global_position)
			var prompt_rect := room.hud.prompt_panel.get_global_rect()
			assert_bool(prompt_rect.intersects(bar_rect)).override_failure_message("%s's prompt %s overlaps the bar %s (overview %s)" % [desk.name, prompt_rect, bar_rect, overview]).is_false()
	camera.set_overview(false)

func test_nothing_on_a_teller_day() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_bool(adapter.is_claimed()).is_false()
	assert_bool(DayFlow.has_claimed(adapter)).is_false()
	await frames(1)
	assert_bool(bar.visible).is_false()
	assert_bool(adapter.end_slot()).is_false()

func test_nothing_on_a_loan_officer_day() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_bool(adapter.is_claimed()).is_false()
	assert_bool(DayFlow.has_claimed(adapter)).is_false()
	await frames(1)
	assert_bool(bar.visible).is_false()
