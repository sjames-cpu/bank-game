extends "res://tests/support/teller_room_suite.gd"

## The business day (BusinessDay) on a time-slot day: customers only in the
## work slots, clock-ins refused once the day has ended, Closing letting a
## short shift end, the End of Day summary and its totals, starting the next
## day, going home early from the card, and saving.

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	# A time-slot day at Opening, as the room starts it.
	start_slots_day()
	eod = room.end_of_day_screen

# --- helpers -------------------------------------------------------------------

## Sets the clock, with the business day following it.
func set_clock(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## A staff-line arrival as its spawn timer would make it (respecting hours).
func staff_line_arrival(line: NpcCustomerLine) -> void:
	line._on_spawn_timer_timeout()

## Clocks in at the Loan Desk / Branch Manager desk through their screens.
func press_loan_clock_in() -> void:
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()

## A day nobody works: Opening skipped, then home from the card, so the day
## ends at Closing (nobody on shift) and its End of Day comes.
func end_unworked_day() -> void:
	DayFlow.skip_slot()
	DayFlow.go_home_early()
	assert_bool(DayFlow.end_of_day_due).is_true()

func everyone_leaves() -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)

# --- opening hours -------------------------------------------------------------------

func test_no_customers_outside_the_work_slots() -> void:
	var window := room.window1_npc_line
	assert_bool(BusinessDay.is_open()).is_false()
	# The player clocks in at Opening for the opening count; until 9 AM the
	# branch is still closed.
	clock_in()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_IN)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(BusinessDay.is_open()).is_false()
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(0)
	assert_int(window.queue.size()).is_equal(0)
	# No loan applicants walk in yet either.
	var decisions := [0]
	var seat := room.player_loan_seat()
	room.loan_desk_worker.decision_made.connect(func(_a: LoanApplication, _s: StaffMember, _c: bool) -> void: decisions[0] += 1)
	room.loan_desk_worker._process(1000.0)
	assert_bool(seat.is_empty()).is_true()
	assert_int(decisions[0]).is_equal(0)

	# The 9 AM slot: the doors open.
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	assert_bool(BusinessDay.is_open()).is_true()
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(1)
	assert_int(window.queue.size()).is_equal(1)
	# An applicant walks in, sits, and is decided.
	room.loan_desk_worker._process(1000.0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	seat.applicant.finish_route()
	assert_bool(seat.is_seated()).is_true()
	room.loan_desk_worker._process(1000.0)
	assert_int(decisions[0]).is_equal(1)
	seat.finish_leaving()
	assert_bool(seat.is_empty()).is_true()

	# Closing: closed again (the player's skipped slot sent its customer away).
	to_closing()
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_true()
	var waiting := cq.queue.size()
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(waiting)
	assert_int(window.queue.size()).is_equal(1)
	room.loan_desk_worker._process(1000.0)
	assert_int(decisions[0]).is_equal(1)

func test_the_first_customers_come_soon_after_opening() -> void:
	# Clocked in at Opening: the player's line has a full 20 s on its timer,
	# and the staff lines 12-18 s, which on their own would bring nobody
	# until well into the 9 AM slot.
	clock_in()
	cq.spawn_timer.start()
	var lines: Array[CustomerQueue] = [cq, room.window1_npc_line, room.window2_line]
	for line in lines:
		assert_float(line.spawn_timer.time_left).is_greater(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)
	await frames(2)

	# The 9 AM slot: every line taking customers starts its timer fresh.
	DayFlow.continue_day()
	await frames(1)
	for line in lines:
		assert_float(line.spawn_timer.time_left).is_less_equal(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)
	# Window 3 has no line before promotion: it stays shut.
	assert_bool(room.window3_line.spawn_timer.is_stopped()).is_true()

	# Each line's first customer arrives within those few seconds.
	Engine.time_scale = 8.0
	var arrived_at: Dictionary[CustomerQueue, float] = {}
	var elapsed := 0.0
	while arrived_at.size() < lines.size() and elapsed < 60.0:
		await get_tree().physics_frame
		elapsed += Engine.time_scale / Engine.physics_ticks_per_second
		for line in lines:
			if not arrived_at.has(line) and line.has_customers():
				arrived_at[line] = elapsed
	Engine.time_scale = 1.0
	assert_int(arrived_at.size()).is_equal(lines.size())
	for line in lines:
		assert_float(arrived_at[line]).is_less_equal(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS + 0.5)
	# After that first one, the player's line is back to its usual gap.
	assert_float(cq.spawn_timer.wait_time).is_equal(cq.spawn_interval)

	# Opening only happens once a slot: later in it the timers are left alone.
	cq.spawn_timer.start(15.0)
	await frames(2)
	assert_float(cq.spawn_timer.time_left).is_greater(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)

func test_clock_in_is_refused_once_the_day_has_ended() -> void:
	# During the day a shift can start.
	assert_bool(BusinessDay.can_start_shift()).is_true()
	open_work_slot()
	assert_bool(BusinessDay.can_start_shift()).is_true()
	# Nobody clocked in, so the day ends when it reaches Closing.
	to_closing()
	assert_bool(BusinessDay.is_day_over()).is_true()
	assert_bool(BusinessDay.can_start_shift()).is_false()
	open_desk()
	ts.clock_in_button.pressed.emit()
	assert_bool(ts.error_label.visible).is_true()
	assert_str(ts.error_label.text).is_equal(BusinessDay.CLOCK_IN_REFUSED_TEXT)
	assert_bool(ts.drawer_count_screen.visible).is_false()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)
	close_desk()
	# The Loan Desk and the Branch Manager desk keep the same hours.
	press_loan_clock_in()
	assert_bool(room.loan_officer_screen.is_clocked_in()).is_false()
	assert_str(room.loan_officer_screen.error_label.text).is_equal(BusinessDay.CLOCK_IN_REFUSED_TEXT)
	room.loan_officer_screen.close_button.pressed.emit()
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_false()
	assert_str(bm.error_label.text).is_equal(BusinessDay.CLOCK_IN_REFUSED_TEXT)
	bm.hide_screen()

func test_closing_lets_a_short_shift_clock_out() -> void:
	clock_in()
	open_work_slot()
	serve_correctly(spawn())
	# Before Closing the shift goes on.
	open_desk()
	ts.clock_out_button.pressed.emit()
	assert_bool(ts.drawer_count_screen.visible).is_false()
	assert_str(ts.error_label.text).contains(ShiftSlotAdapter.CLOCK_OUT_REFUSED_TEXT)
	close_desk()

	# Closing: the customers who never came don't block clock-out.
	to_closing()
	assert_int(room.customers_still_to_arrive()).is_equal(0)
	assert_bool(clock_out()).is_true()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)
	close_desk()

	# The next day: a customer already inside is still served at Closing.
	await go_to_next_day()
	clock_in()
	var late := spawn()
	to_closing()
	assert_bool(BusinessDay.doors_closed()).is_true()
	open_desk()
	assert_object(room._customer_being_served).is_same(late)
	serve_correctly(late)
	assert_bool(clock_out()).is_true()

func test_staff_finish_their_customers_after_closing_then_idle() -> void:
	var window := room.window1_npc_line
	open_work_slot()
	staff_line_arrival(window)
	staff_line_arrival(window)
	assert_int(window.queue.size()).is_equal(2)
	to_closing()
	assert_bool(BusinessDay.doors_closed()).is_true()
	var served := [0]
	window.customer_served.connect(func(_c: CustomerNPC, _s: StaffMember, _m: bool) -> void: served[0] += 1)
	Engine.time_scale = 8.0
	var waited := 0
	while (window.has_customers() or window.is_serving()) and waited < 4000:
		staff_line_arrival(window) # the timer keeps firing; nobody comes
		await get_tree().physics_frame
		waited += 1
	Engine.time_scale = 1.0
	assert_int(served[0]).is_equal(2)
	assert_bool(window.has_customers()).is_false()
	assert_bool(window.is_serving()).is_false()
	# Still at the desk, idle.
	var npc: StaffNPC = room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_1]
	assert_int(npc.state).is_equal(StaffNPC.State.AT_DESK)

# --- end of day ---------------------------------------------------------------------

func test_the_end_of_day_summary_and_its_totals() -> void:
	var start := totals()
	# The player's shift: two served, two who gave up.
	clock_in()
	serve_correctly(spawn())
	serve_correctly(spawn(ShiftTransaction.Type.WITHDRAWAL, 20.0))
	abandon(spawn())
	abandon(spawn())
	assert_bool(clock_out()).is_true()
	close_desk()
	# Staff served three.
	var window := room.window1_npc_line
	for i in 3:
		var customer: CustomerNPC = auto_free(CustomerNPC.new())
		window.customer_served.emit(customer, ScheduleManager.get_roster()[0], false)
	var expected := totals() - start

	# The day has ended, but not while customers are still inside.
	assert_bool(BusinessDay.is_day_over()).is_true()
	window._spawn_customer()
	await frames(3)
	assert_bool(eod.visible).is_false()
	await everyone_leaves()
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(get_tree().paused).is_true()

	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	var text := eod.summary_label.text
	assert_str(text).contains("Customers served by the branch: 5 (you 2, staff 3)")
	assert_str(text).contains("Your shifts today: 1")
	assert_str(text).contains("Score %+d · Reputation %+d · XP %+d" % [expected.x, expected.y, expected.z])
	assert_str(eod.next_day_button.text).is_equal("Start Day 2")
	# Saved as it appears.
	assert_bool(SaveGame.exists()).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "business_day"), "customers_served_by_player", -1)).is_equal(2)

func test_start_the_next_day_at_8_30_and_save() -> void:
	end_unworked_day()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	SaveGame.delete()
	eod.next_day_button.pressed.emit()
	assert_bool(eod.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(GameClock.day).is_equal(2)
	assert_float(GameClock.minutes).is_equal(GameClock.START_MINUTES)
	assert_str(GameClock.timestamp()).is_equal("Day 2, Tue 6 Jan, 8:30 AM")
	assert_int(BusinessDay.stats_day).is_equal(2)
	assert_dict(BusinessDay.summary()).is_equal({"day": 2, "date": BankCalendar.epoch_day(2026, 1, 6), "after_cutoff": [], "customers_by_player": 0, "customers_by_staff": 0, "customers": 0, "shifts": 0, "score": 0, "reputation": 0, "xp": 0})
	# Day 2 starts at Opening: not open yet, and a shift can start.
	assert_str(DayFlow.current_slot().id).is_equal(DaySchedule.OPENING)
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.can_start_shift()).is_true()
	# Saved at the start of the new day.
	var clock := SaveGame.dict_of(SaveGame.read().career, "clock")
	assert_int(SaveGame.int_of(clock, "day", -1)).is_equal(2)
	assert_float(SaveGame.float_of(clock, "minutes", -1.0)).is_equal(GameClock.START_MINUTES)
	# And the new day runs normally.
	await frames(3)
	assert_bool(eod.visible).is_false()

func test_going_home_early_skips_to_the_summary() -> void:
	var score_before := ScoreManager.total_score
	# On shift, the doormat says to clock out first and does nothing.
	clock_in()
	assert_str(room.interaction_prompt_text(room.exit_door)).is_equal("Clock out before you go home")
	room._on_exit_door_interacted()
	assert_bool(eod.visible).is_false()
	continue_to_slot(DaySchedule.SLOT_9AM)
	cq.spawn_timer.stop()
	for i in DaySchedule.work_for(DaySchedule.WorkRole.TELLER):
		abandon(spawn())
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()

	# Home early from the card (asked first): the rest of the slots skipped.
	var card := slot_card()
	assert_bool(card.visible).is_true()
	card.go_home_button.pressed.emit()
	assert_bool(card.confirm_panel.visible).is_true()
	card.confirm_button.pressed.emit()
	assert_str(DayFlow.current_slot().id).is_equal(DaySchedule.CLOSING)
	assert_float(GameClock.minutes).is_equal(BusinessDay.CLOSE_MINUTES)
	assert_bool(clock_out()).is_true()
	close_desk()
	var score_after_shift := ScoreManager.total_score
	await run_end_of_day()
	# Nothing was simulated for the skipped slots.
	assert_int(ScoreManager.total_score).is_equal(score_after_shift)
	assert_str(eod.summary_label.text).contains("Your shifts today: 1")
	assert_int(score_after_shift - score_before).is_equal(BusinessDay.summary()["score"])
	eod.next_day_button.pressed.emit()
	assert_str(GameClock.timestamp()).is_equal("Day 2, Tue 6 Jan, 8:30 AM")

# --- saving ---------------------------------------------------------------------------

func test_save_and_load_at_the_end_and_start_of_days() -> void:
	# Day 1 with a shift and some customers behind it, saved at its End of
	# Day (a career is saved only at the end of a day and its start).
	BusinessDay.customers_served_by_player = 3
	BusinessDay.customers_served_by_staff = 7
	BusinessDay.shifts_completed = 1
	ScoreManager.add_shift_score(12)
	end_unworked_day()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	var at_end := SaveGame.capture()
	var summary := BusinessDay.summary()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(SaveGame.capture()).is_equal(at_end)
	assert_dict(BusinessDay.summary()).is_equal(summary)
	assert_int(summary["score"]).is_equal(12)
	assert_bool(DayFlow.end_of_day_due).is_true()

	# Across days: start Day 2 (saved), load it.
	eod.next_day_button.pressed.emit()
	get_tree().paused = true
	var next_morning := SaveGame.read().career
	CareerReset.reset_all()
	SaveGame.restore(next_morning)
	assert_str(GameClock.timestamp()).is_equal("Day 2, Tue 6 Jan, 8:30 AM")
	assert_int(BusinessDay.stats_day).is_equal(2)
	assert_int(BusinessDay.summary()["customers"]).is_equal(0)
	assert_int(BusinessDay.summary()["score"]).is_equal(0)
	assert_int(ScoreManager.total_score).is_equal(12)

	# A save from before the business day existed: today's totals start now.
	SaveGame.restore({"score": {"total_score": 40}, "clock": {"day": 4, "minutes": 600.0}})
	assert_int(BusinessDay.stats_day).is_equal(4)
	assert_int(BusinessDay.summary()["score"]).is_equal(0)
	assert_bool(BusinessDay.is_day_over()).is_false()
