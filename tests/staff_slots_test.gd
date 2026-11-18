extends "res://tests/support/teller_room_suite.gd"

## Staff work per time slot (StaffSlotPacer): each work slot gives every
## staff teller window DaySchedule's 4 arrivals and every staff loan desk
## its 2, fresh at each slot; staff never keep a slot from ending; customers
## left in staff lines carry over and never stick the day.

var pacer: StaffSlotPacer

func before_test() -> void:
	await super()
	pacer = room.get_node("StaffSlotPacer")

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func window_cap() -> int:
	return DaySchedule.work_for(DaySchedule.WorkRole.STAFF_TELLER_WINDOW)

func desk_cap() -> int:
	return DaySchedule.work_for(DaySchedule.WorkRole.STAFF_LOAN_DESK)

## A Teller day at 9 AM, the player's own line's timer stopped.
func teller_day_at_9am() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)

## The player's two customers served: the Teller's slot is done.
func finish_teller_slot() -> void:
	for i in TellerConfig.CUSTOMERS_PER_SLOT:
		serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))

func test_every_work_slot_starts_fresh_caps() -> void:
	teller_day_at_9am()
	assert_int(pacer.lines.size()).is_equal(3)
	assert_int(pacer.workers.size()).is_equal(3)
	for line in pacer.lines:
		assert_int(line.arrivals_left_this_slot()).is_equal(window_cap())
	for worker in pacer.workers:
		assert_int(worker.arrivals_left_this_slot()).is_equal(desk_cap())
	# Two arrive at Teller Window 1 in the 9 AM slot.
	var line := room.window1_npc_line
	line._try_spawn()
	line._try_spawn()
	assert_int(line.arrivals_left_this_slot()).is_equal(window_cap() - 2)
	DayFlow.skip_slot()
	# Nothing changes between slots; 11 AM starts fresh, and the two
	# waiting carry over.
	assert_int(line.arrivals_left_this_slot()).is_equal(window_cap() - 2)
	var waiting := line.queue.size()
	assert_int(waiting).is_greater(0)
	continue_to_slot(DaySchedule.SLOT_11AM)
	assert_int(line.arrivals_left_this_slot()).is_equal(window_cap())
	assert_int(line.queue.size()).is_equal(waiting)

func test_a_window_stops_at_its_cap() -> void:
	teller_day_at_9am()
	var line := room.window1_npc_line
	line.begin_slot(1)
	line._try_spawn()
	line._try_spawn()
	assert_int(line.queue.size()).is_equal(1)
	assert_int(line.arrivals_left_this_slot()).is_equal(0)

func test_a_loan_desk_stops_at_its_cap() -> void:
	teller_day_at_9am()
	var worker := room.loan_desk_workers[1]
	var seat := worker.seat
	# The other desks' walk-ins would share the entrance corridor.
	for other in room.loan_desk_workers:
		if other != worker:
			other.active = false
	worker.begin_slot(1)
	# The first applicant walks in, is decided and leaves.
	worker._process(10.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	assert_int(worker.arrivals_left_this_slot()).is_equal(0)
	seat.seat_now()
	worker._process(100.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	seat.finish_leaving()
	assert_bool(seat.is_empty()).is_true()
	# Nobody else this slot.
	worker._process(10.0)
	assert_bool(seat.is_empty()).is_true()
	# The next slot brings more.
	finish_teller_slot()
	await frames(2)
	continue_to_slot(DaySchedule.SLOT_11AM)
	assert_int(worker.arrivals_left_this_slot()).is_equal(desk_cap())
	worker._process(10.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)

func test_staff_never_keep_a_slot_from_ending() -> void:
	teller_day_at_9am()
	for line in pacer.lines:
		if line.active:
			line._try_spawn()
			line._try_spawn()
	var staff_waiting := 0
	for line in pacer.lines:
		staff_waiting += line.queue.size()
	assert_int(staff_waiting).is_greater(0)
	finish_teller_slot()
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)

func test_customers_left_in_staff_lines_never_stick_the_day() -> void:
	teller_day_at_9am()
	for line in pacer.lines:
		if line.active:
			for i in 3:
				line._try_spawn()
	# Straight to Closing with the staff lines full.
	DayFlow.skip_slot()
	DayFlow.go_home_early()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	assert_bool(room.is_lobby_empty()).is_false()
	assert_bool(clock_out()).is_true()
	close_desk()
	# Nobody new comes after Closing; staff serve (or lose) who's there and
	# End of Day follows.
	Engine.time_scale = 40.0
	var shown := false
	for i in 3000:
		await get_tree().process_frame
		if room.end_of_day_screen.is_summary_shown():
			shown = true
			break
	Engine.time_scale = 1.0
	assert_bool(shown).override_failure_message("End of Day never came").is_true()
	assert_bool(room.is_lobby_empty()).is_true()
