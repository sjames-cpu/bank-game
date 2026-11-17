extends "res://tests/support/teller_room_suite.gd"

## A whole Teller day with time slots on, played through the room as the
## player would: the opening count at Opening, two customers in each work
## slot with Continue on each card, the closing count at Closing, then the
## End of Day summary and save, once. And the same day going home early
## after 11 AM: 1 PM and 3 PM are skipped and End of Day still runs.

var eod: EndOfDayScreen
var card: SlotTransitionCard
var skipped: Array[StringName] = []

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen
	card = slot_card()
	skipped.clear()
	DayFlow.slot_skipped.connect(_on_slot_skipped)

func after_test() -> void:
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)
	await super()

func _on_slot_skipped(slot: DaySlot) -> void:
	skipped.append(slot.id)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

## Continue on the card that's up; the line's own timer is stopped (tests
## bring the slot's customers themselves).
func press_continue() -> void:
	assert_bool(card.visible).override_failure_message("no card is up").is_true()
	card.continue_button.pressed.emit()
	cq.spawn_timer.stop()

## The work slot's customers, served at the window (small deposits, so the
## drawer stays under its limit all day), then the card comes up.
func work_the_slot(id: StringName) -> void:
	assert_str(current_id()).is_equal(id)
	for i in DaySchedule.work_for(DaySchedule.WorkRole.TELLER):
		serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))
	await frames(2)

## Opening: the day waits for the clock-in and its count.
func open_the_day() -> void:
	start_slots_day()
	await frames(2)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(card.visible).is_false()
	clock_in()
	await frames(1)
	assert_str(card.slot_label.text).is_equal("9 AM")

## Closing: the closing count, then the End of Day.
func close_the_day() -> void:
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(2)
	assert_bool(eod.visible).is_false()
	assert_bool(clock_out()).is_true()
	close_desk()
	# End of Day waits for an empty lobby: everyone still walking out leaves.
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)

func test_a_full_teller_day() -> void:
	await open_the_day()
	press_continue()
	for id: StringName in [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]:
		await work_the_slot(id)
		assert_bool(card.visible).override_failure_message("no card after %s" % id).is_true()
		assert_str(card.done_label.text).is_equal("%s slot done\nCustomers you served: 2" % DayFlow.current_slot().label)
		press_continue()
	await close_the_day()

	assert_array(skipped).is_empty()
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	assert_str(eod.summary_label.text).contains("you 8")
	assert_int(BusinessDay.customers_served_by_player).is_equal(8)
	assert_int(VaultManager.last_closed_day).is_equal(1)
	assert_bool(SaveGame.exists()).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "business_day"), "customers_served_by_player", -1)).is_equal(8)
	# Once: nothing more happens while the summary waits.
	SaveGame.delete()
	await frames(5)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(SaveGame.exists()).is_false()

func test_going_home_early_after_11_am() -> void:
	await open_the_day()
	press_continue()
	await work_the_slot(DaySchedule.SLOT_9AM)
	press_continue()
	await work_the_slot(DaySchedule.SLOT_11AM)
	assert_str(card.slot_label.text).is_equal("1 PM")
	card.go_home_button.pressed.emit()
	card.confirm_button.pressed.emit()
	assert_array(skipped).is_equal([DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM])
	await close_the_day()

	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_label.text).contains("you 4")
	assert_int(VaultManager.last_closed_day).is_equal(1)
	assert_bool(SaveGame.exists()).is_true()
	await frames(5)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(DayFlow.is_running()).is_false()
