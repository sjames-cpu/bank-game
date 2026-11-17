extends "res://tests/support/teller_room_suite.gd"

## The card between time slots (SlotTransitionCard): when it shows, what it
## says, which buttons appear when (Go home early only while DayFlow allows
## it, so only Continue before Closing), the go-home confirmation, and
## pausing the game like other screens.

var card: SlotTransitionCard
var window_before: Vector2i

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

func before_test() -> void:
	await super()
	card = slot_card()
	window_before = get_tree().root.size

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

## A Teller day, clocked in: the card before 9 AM is up.
func teller_day() -> void:
	start_slots_day()
	clock_in()
	await frames(1)

## The current work slot skipped (as the debug key does), so the next card
## comes up without serving anyone.
func skip_to_next_card() -> void:
	DayFlow.skip_slot()
	await frames(1)

func test_the_card_before_9_am() -> void:
	await teller_day()
	assert_bool(card.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(card.slot_label.text).is_equal("9 AM")
	assert_str(card.done_label.text).is_equal(SlotTransitionCard.SHIFT_STARTED_TEXT)
	assert_bool(card.note_label.visible).is_false()
	assert_bool(card.continue_button.visible).is_true()
	assert_bool(card.go_home_button.visible).is_true()
	assert_object(card.continue_button.get_viewport().gui_get_focus_owner()).is_same(card.continue_button)

func test_continue_starts_the_next_slot() -> void:
	await teller_day()
	card.continue_button.pressed.emit()
	assert_bool(card.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()

func test_it_says_how_many_customers_were_served() -> void:
	await teller_day()
	card.continue_button.pressed.emit()
	cq.spawn_timer.stop()
	serve_correctly(spawn())
	serve_correctly(spawn())
	await frames(2)
	assert_bool(card.visible).is_true()
	assert_str(card.slot_label.text).is_equal("11 AM")
	assert_str(card.done_label.text).is_equal("9 AM slot done — customers you served: 2")

func test_it_waits_for_the_teller_screen_to_close() -> void:
	await teller_day()
	card.continue_button.pressed.emit()
	cq.spawn_timer.stop()
	serve_correctly(spawn())
	var last := spawn()
	open_desk()
	deposit(last.intent_amount_cents / 100.0)
	complete()
	await frames(2)
	assert_bool(card.visible).is_false()
	close_desk()
	await frames(2)
	assert_bool(card.visible).is_true()

func test_the_cutoff_note_before_3_pm() -> void:
	await teller_day()
	card.continue_button.pressed.emit()
	await skip_to_next_card() # before 11 AM
	assert_bool(card.note_label.visible).is_false()
	card.continue_button.pressed.emit()
	await skip_to_next_card() # before 1 PM
	assert_bool(card.note_label.visible).is_false()
	card.continue_button.pressed.emit()
	await skip_to_next_card() # before 3 PM
	assert_str(card.slot_label.text).is_equal("3 PM")
	assert_bool(card.note_label.visible).is_true()
	assert_str(card.note_label.text).is_equal(SlotTransitionCard.CUTOFF_TEXT)
	assert_bool(card.go_home_button.visible).is_true()

func test_only_continue_before_closing() -> void:
	await teller_day()
	for i in 4:
		card.continue_button.pressed.emit()
		await skip_to_next_card()
	assert_str(card.slot_label.text).is_equal("Closing")
	assert_str(card.note_label.text).is_equal(SlotTransitionCard.CLOSING_TEXT)
	assert_bool(card.continue_button.visible).is_true()
	assert_bool(card.go_home_button.visible).is_false()
	card.continue_button.pressed.emit()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)

func test_going_home_asks_first_and_says_what_is_lost() -> void:
	await teller_day()
	card.continue_button.pressed.emit()
	await skip_to_next_card() # before 11 AM
	card.go_home_button.pressed.emit()
	assert_bool(card.confirm_panel.visible).is_true()
	assert_bool(card.card_panel.visible).is_false()
	assert_str(card.confirm_label.text).contains("customers, and the XP they would have earned, are lost")
	# Keep Working: back to the card, nothing skipped.
	card.cancel_button.pressed.emit()
	assert_bool(card.card_panel.visible).is_true()
	assert_bool(DayFlow.is_between_slots()).is_true()

	var skipped: Array[StringName] = []
	var on_skip := func(slot: DaySlot) -> void: skipped.append(slot.id)
	DayFlow.slot_skipped.connect(on_skip)
	card.go_home_button.pressed.emit()
	card.confirm_button.pressed.emit()
	DayFlow.slot_skipped.disconnect(on_skip)
	assert_bool(card.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_array(skipped).is_equal([DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM])
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)

func test_it_closes_if_the_day_moves_on_without_it() -> void:
	await teller_day()
	assert_bool(card.visible).is_true()
	DayFlow.continue_day()
	assert_bool(card.visible).is_false()
	assert_bool(get_tree().paused).is_false()

func test_never_with_slots_off() -> void:
	DayFlow.pause_between_slots = true
	DayFlow.start_day() # slots off: nobody claims, DayFlow waits after Opening
	assert_bool(DayFlow.is_between_slots()).is_true()
	await frames(2)
	assert_bool(card.visible).is_false()
	assert_bool(get_tree().paused).is_false()

func test_the_card_fits_the_screen() -> void:
	# Laid out in the game's 1152x648 window, as screen_fit_test.gd does.
	get_tree().root.size = Vector2i(1152, 648)
	await teller_day()
	for i in 3:
		card.continue_button.pressed.emit()
		await skip_to_next_card()
	# Before 3 PM: every line shown (served, cutoff note, both buttons).
	await frames(1)
	assert_array(layout_problems(card.card_panel)).is_empty()
	card.go_home_button.pressed.emit()
	await frames(1)
	assert_array(layout_problems(card.confirm_panel)).is_empty()
