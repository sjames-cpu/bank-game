extends "res://tests/support/teller_room_suite.gd"

## The Teller's work slots (TellerSlotAdapter): on a Teller day each work
## slot brings DaySchedule's teller amount of customers, one by one, and
## ends once all of them are handled (served or gave up); a skipped slot's
## work is dropped; nothing happens on a Loan Officer's day or with slots
## off.

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func per_slot() -> int:
	return DaySchedule.work_for(DaySchedule.WorkRole.TELLER)

## A Teller day: clocked in at Opening, then into the 9 AM slot. The line's
## own timer is stopped: tests bring customers themselves.
func teller_day_at_9am() -> void:
	start_slots_day()
	clock_in()
	DayFlow.continue_day()
	cq.spawn_timer.stop()

## An arrival as the line's timer would make it (cap and opening hours apply).
func arrival() -> void:
	cq._on_spawn_timer_timeout()
	cq.spawn_timer.stop()

func test_a_work_slot_waits_for_exactly_its_customers() -> void:
	teller_day_at_9am()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.has_claimed(room.teller_slots)).is_true()
	assert_int(per_slot()).is_equal(2)
	assert_int(cq.get_customers_left_to_spawn()).is_equal(per_slot())
	await frames(3)
	assert_bool(DayFlow.is_between_slots()).is_false()

	serve_correctly(spawn())
	await frames(3)
	assert_bool(DayFlow.is_between_slots()).is_false()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)

	serve_correctly(spawn())
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)

	# The next slot brings its own customers, counted afresh.
	DayFlow.continue_day()
	assert_bool(DayFlow.has_claimed(room.teller_slots)).is_true()
	assert_int(cq.get_customers_left_to_spawn()).is_equal(per_slot())

func test_a_customer_who_gives_up_counts_as_handled() -> void:
	teller_day_at_9am()
	abandon(spawn())
	serve_correctly(spawn())
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_the_slot_never_ends_behind_the_open_teller_screen() -> void:
	teller_day_at_9am()
	serve_correctly(spawn())
	var last := spawn()
	open_desk()
	deposit(last.intent_amount_cents / 100.0)
	complete()
	# Served, but the screen is still open (the world is paused).
	assert_bool(cq.queue.is_empty()).is_true()
	assert_bool(DayFlow.is_between_slots()).is_false()
	close_desk()
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_customers_arrive_one_by_one_and_stop_at_the_slots_amount() -> void:
	teller_day_at_9am()
	arrival()
	assert_int(cq.queue.size()).is_equal(1)
	arrival()
	assert_int(cq.queue.size()).is_equal(2)
	arrival()
	arrival()
	assert_int(cq.queue.size()).is_equal(2)
	assert_int(cq.get_customers_left_to_spawn()).is_equal(0)

func test_a_skipped_slot_drops_its_work() -> void:
	teller_day_at_9am()
	arrival()
	assert_int(cq.queue.size()).is_equal(1)
	DayFlow.skip_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(DayFlow.has_claimed(room.teller_slots)).is_false()
	# Whoever was waiting leaves, and no more come.
	assert_int(cq.queue.size()).is_equal(0)
	assert_int(cq.get_customers_left_to_spawn()).is_equal(0)
	await frames(2)
	assert_bool(cq.has_customers()).is_false()
	# 11 AM is a fresh slot.
	DayFlow.continue_day()
	assert_int(cq.get_customers_left_to_spawn()).is_equal(per_slot())

func test_nothing_on_a_loan_officer_day() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()
	var cap_before := cq.spawn_cap
	DayFlow.continue_day() # 9 AM: the Loan Officer's slot (LoanSlotAdapter)
	assert_str(DayFlow.current_slot().id).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.has_claimed(room.get_node("LoanSlotAdapter"))).is_true()
	assert_bool(DayFlow.has_claimed(room.teller_slots)).is_false()
	assert_int(cq.spawn_cap).is_equal(cap_before)

func test_nothing_with_slots_off() -> void:
	clock_in()
	assert_int(cq.spawn_cap).is_equal(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP)
	assert_int(cq.get_customers_left_to_spawn()).is_equal(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP)
	assert_bool(DayFlow.is_running()).is_false()
