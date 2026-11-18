extends "res://tests/support/teller_room_suite.gd"

## What the player sees about the time-slot day (SlotStatus,
## SlotStatusProvider): the HUD's clock line names the slot, its slot line
## comes from whoever's slot it is (the shift at Opening and Closing, the
## Teller, Loan Officer or Branch Manager in a work slot), and the card
## reports on the slot just finished, per role, with a Branch Manager's
## clean-slot +1. The HUD column still fits.

const Hint := HintManager.Hint

var hud: Hud
var card: SlotTransitionCard
var window_before: Vector2i

func before_test() -> void:
	await super()
	hud = room.hud
	card = slot_card()
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

func loan_clock_in() -> void:
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()

func manager_clock_in() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()

func weekday() -> String:
	return BankCalendar.weekday_short(GameClock.today_date())

# --- the HUD ----------------------------------------------------------------------------

func test_the_clock_line_names_the_slot() -> void:
	start_slots_day()
	await frames(1)
	assert_str(hud.clock_label.text).is_equal("%s, Day 1 · Opening" % weekday())
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	DayFlow.skip_slot()
	continue_to_slot(DaySchedule.SLOT_11AM)
	await frames(1)
	assert_str(hud.clock_label.text).is_equal("%s, Day 1 · 11 AM slot" % weekday())

func test_the_shift_speaks_at_opening_and_closing() -> void:
	start_slots_day()
	await frames(1)
	assert_bool(hud.slot_label.visible).is_true()
	assert_str(hud.slot_label.text).is_equal(ShiftSlotAdapter.OPENING_STATUS_TEXT)
	clock_in()
	DayFlow.go_home_early()
	await frames(1)
	assert_str(hud.slot_label.text).is_equal(ShiftSlotAdapter.CLOSING_STATUS_TEXT)

func test_a_teller_slot_counts_its_customers() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	await frames(1)
	assert_str(hud.slot_label.text).is_equal("Customers: 0 / 2")
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))
	await frames(1)
	assert_str(hud.slot_label.text).is_equal("Customers: 1 / 2")

func test_a_loan_slot_counts_its_application() -> void:
	for worker in room.loan_desk_workers:
		worker.active = false
	start_slots_day()
	loan_clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	await frames(1)
	assert_str(hud.slot_label.text).is_equal("Application: 0 / 1")

func test_a_manager_slot_says_what_it_waits_for() -> void:
	start_slots_day()
	manager_clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	await frames(1)
	assert_str(hud.slot_label.text).is_equal(ManagerSlotAdapter.STATUS_TEXT)
	# Held by an event after "End this slot".
	DayFlow.hold(&"test event")
	var manager: ManagerSlotAdapter = room.get_node("ManagerSlotAdapter")
	manager.end_slot()
	await frames(1)
	assert_str(hud.slot_label.text).is_equal(ManagerSlotAdapter.HELD_STATUS_TEXT)
	DayFlow.release(&"test event")

func test_between_slots_the_line_is_hidden() -> void:
	start_slots_day()
	clock_in()
	assert_bool(DayFlow.is_between_slots()).is_true()
	hud.refresh()
	assert_bool(hud.slot_label.visible).is_false()

func test_the_hud_column_still_fits_with_the_slot_line() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	start_slots_day()
	manager_clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	# Every notification up, then every hint in turn below.
	hud.show_unlock_notification(hud.loan_officer_unlocked_label)
	hud.show_unlock_notification(hud.branch_manager_unlocked_label)
	ReputationManager.add_reputation(-100)
	acknowledge_letters()
	for hint: Hint in Hint.values():
		if HintManager.RETIRED.has(hint):
			continue
		hud._show_hint(hint)
		await frames(3)
		assert_bool(hud.slot_label.is_visible_in_tree()).is_true()
		var column: Rect2 = (hud.get_node("RightColumn") as Control).get_global_rect()
		assert_float(column.end.y).override_failure_message("hint %s: the column ends at %.0f" % [Hint.keys()[hint], column.end.y]).is_less(648.0)

# --- the card ----------------------------------------------------------------------------

func test_the_card_reports_a_teller_slot() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))
	await frames(2)
	assert_str(card.done_label.text).is_equal("9 AM slot done\nCustomers you served: 2")

func test_the_card_reports_a_loan_slot() -> void:
	for worker in room.loan_desk_workers:
		worker.active = false
	start_slots_day()
	loan_clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	var lo := room.loan_officer_screen
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	lo.loan_review_screen.run_credit_check_button.pressed.emit()
	lo.loan_review_screen.approve_button.pressed.emit()
	lo.loan_review_screen.close_button.pressed.emit()
	lo.hide_screen()
	await frames(2)
	assert_bool(card.visible).is_true()
	assert_str(card.done_label.text).is_equal("9 AM slot done\nApplications decided: 1")

func test_the_card_reports_a_clean_manager_slot_and_an_unclean_one() -> void:
	start_slots_day()
	manager_clock_in()
	var manager: ManagerSlotAdapter = room.get_node("ManagerSlotAdapter")
	continue_to_slot(DaySchedule.SLOT_9AM)
	manager.end_slot()
	await frames(1)
	assert_str(card.done_label.text).is_equal("9 AM slot done\n+1 Reputation: a clean slot")
	continue_to_slot(DaySchedule.SLOT_11AM)
	ReputationManager.add_reputation(-1)
	manager.end_slot()
	await frames(1)
	assert_str(card.done_label.text).is_equal("11 AM slot done\n" + ManagerSlotAdapter.NOT_CLEAN_REPORT_TEXT)

func test_a_skipped_slot_reports_what_was_done() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	DayFlow.skip_slot()
	await frames(1)
	assert_str(card.done_label.text).is_equal("9 AM slot done\nCustomers you served: 0")
