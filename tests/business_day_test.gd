extends "res://tests/support/teller_room_suite.gd"

## The business day (BusinessDay): opening hours for customers and
## clock-ins, closing time letting a short shift end, the End of Day summary
## and its totals, starting the next day, going home early, and saving.

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
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

func everyone_leaves() -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)

# --- opening hours -------------------------------------------------------------------

func test_no_customers_before_9_or_after_5() -> void:
	var window := room.window1_npc_line
	set_clock(1, 8, 40)
	assert_bool(BusinessDay.is_open()).is_false()
	# The player may clock in early for the opening count.
	clock_in()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_IN)
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(0)
	assert_int(window.queue.size()).is_equal(0)
	# The Loan Desk's staff don't decide yet either.
	var decisions := [0]
	room.loan_desk_worker.decision_made.connect(func(_a: LoanApplication, _s: StaffMember, _c: bool) -> void: decisions[0] += 1)
	room.loan_desk_worker._process(1000.0)
	assert_int(decisions[0]).is_equal(0)

	# 9:00: the doors open.
	set_clock(1, 9, 0)
	assert_bool(BusinessDay.is_open()).is_true()
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(1)
	assert_int(window.queue.size()).is_equal(1)
	room.loan_desk_worker._process(1000.0)
	assert_int(decisions[0]).is_equal(1)

	# 5:00 PM: closed again.
	set_clock(1, 17, 0)
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_true()
	cq._on_spawn_timer_timeout()
	staff_line_arrival(window)
	assert_int(cq.queue.size()).is_equal(1)
	assert_int(window.queue.size()).is_equal(1)
	room.loan_desk_worker._process(1000.0)
	assert_int(decisions[0]).is_equal(1)

func test_the_first_customers_come_soon_after_opening() -> void:
	# Clocked in early: the player's line has a full 20 s (30 game minutes)
	# on its timer, and the staff lines 12-18 s, which on their own would
	# bring nobody until well after 9:00.
	set_clock(1, 8, 59)
	clock_in()
	cq.spawn_timer.start()
	var lines: Array[CustomerQueue] = [cq, room.window1_npc_line, room.window2_line]
	for line in lines:
		assert_float(line.spawn_timer.time_left).is_greater(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)
	await frames(2)

	# 9:00: every line taking customers starts its timer fresh.
	set_clock(1, 9, 0)
	await frames(1)
	for line in lines:
		assert_float(line.spawn_timer.time_left).is_less_equal(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)
	# Window 3 has no line before promotion: it stays shut.
	assert_bool(room.window3_line.spawn_timer.is_stopped()).is_true()

	# Each line's first customer arrives within a few game minutes.
	Engine.time_scale = 8.0
	var arrived_at: Dictionary[CustomerQueue, float] = {}
	var waited := 0
	while arrived_at.size() < lines.size() and waited < 2000:
		await get_tree().physics_frame
		waited += 1
		for line in lines:
			if not arrived_at.has(line) and line.has_customers():
				arrived_at[line] = GameClock.minutes
	Engine.time_scale = 1.0
	assert_int(arrived_at.size()).is_equal(lines.size())
	for line in lines:
		assert_float(arrived_at[line] - BusinessDay.OPEN_MINUTES).is_less_equal(5.0)
	# After that first one, the player's line is back to its usual gap.
	assert_float(cq.spawn_timer.wait_time).is_equal(cq.spawn_interval)

	# Opening only happens once: later in the day the timers are left alone.
	cq.spawn_timer.start(15.0)
	await frames(2)
	assert_float(cq.spawn_timer.time_left).is_greater(CustomerQueue.OPENING_ARRIVAL_MAX_SECONDS)

func test_clock_in_is_refused_after_4_30() -> void:
	set_clock(1, 16, 31)
	open_desk()
	ts.clock_in_button.pressed.emit()
	assert_bool(ts.error_label.visible).is_true()
	assert_str(ts.error_label.text).is_equal("The branch closes at 5:00 PM — too late to start a new shift.")
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
	# Up to 4:30 it's fine.
	set_clock(1, 16, 30)
	bm.clock_in_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_true()

func test_closing_lets_a_short_shift_clock_out() -> void:
	set_clock(1, 16, 0)
	clock_in()
	serve_correctly(spawn())
	# Still open: the shift's other three customers are owed.
	open_desk()
	ts.clock_out_button.pressed.emit()
	assert_bool(ts.drawer_count_screen.visible).is_false()
	assert_str(ts.error_label.text).contains("3 more customers still to arrive")
	close_desk()

	# 5:00 PM: the ones that never came don't block clock-out.
	set_clock(1, 17, 0)
	assert_str(room.describe_shift_status()).contains("Branch closed — no more customers today")
	assert_int(room.customers_still_to_arrive()).is_equal(0)
	assert_bool(clock_out()).is_true()
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)

	# Customers already inside are still served after closing.
	set_clock(1, 16, 0)
	clock_in()
	var late := spawn()
	set_clock(1, 17, 5)
	open_desk()
	assert_object(room._customer_being_served).is_same(late)
	serve_correctly(late)
	assert_bool(clock_out()).is_true()

func test_staff_finish_their_customers_after_closing_then_idle() -> void:
	var window := room.window1_npc_line
	set_clock(1, 16, 50)
	staff_line_arrival(window)
	staff_line_arrival(window)
	assert_int(window.queue.size()).is_equal(2)
	set_clock(1, 17, 0)
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
	set_clock(1, 9, 0)
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

	# Not before closing, and not while customers are still inside.
	await frames(3)
	assert_bool(eod.visible).is_false()
	set_clock(1, 17, 0)
	staff_line_arrival(window)
	set_clock(1, 16, 59)
	staff_line_arrival(window)
	set_clock(1, 17, 1)
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
	set_clock(1, 17, 0)
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	SaveGame.delete()
	eod.next_day_button.pressed.emit()
	assert_bool(eod.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(GameClock.day).is_equal(2)
	assert_float(GameClock.minutes).is_equal(GameClock.START_MINUTES)
	assert_str(GameClock.timestamp()).is_equal("Day 2, 8:30 AM")
	assert_int(BusinessDay.stats_day).is_equal(2)
	assert_dict(BusinessDay.summary()).is_equal({"day": 2, "customers_by_player": 0, "customers_by_staff": 0, "customers": 0, "shifts": 0, "score": 0, "reputation": 0, "xp": 0})
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
	set_clock(1, 11, 0)
	staff_line_arrival(room.window1_npc_line)
	assert_bool(room.window1_npc_line.has_customers()).is_true()
	var score_before := ScoreManager.total_score

	# On shift, the doormat says to clock out first and does nothing.
	clock_in()
	assert_str(room.interaction_prompt_text(room.exit_door)).is_equal("Clock out before you go home")
	room._on_exit_door_interacted()
	assert_bool(eod.visible).is_false()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	close_desk()
	var score_after_shift := ScoreManager.total_score

	# Off shift: "E — Go home (end Day 1)", then a question first.
	assert_str(room.interaction_prompt_text(room.exit_door)).is_equal("E — Go home (end Day 1)")
	room._on_exit_door_interacted()
	assert_bool(eod.confirm_panel.visible).is_true()
	assert_str(eod.confirm_label.text).is_equal("Go home and end Day 1?")
	eod.stay_button.pressed.emit()
	assert_bool(eod.visible).is_false()
	assert_float(GameClock.minutes).is_less(BusinessDay.CLOSE_MINUTES)

	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	assert_bool(eod.is_summary_shown()).is_true()
	assert_float(GameClock.minutes).is_equal(BusinessDay.CLOSE_MINUTES)
	# Nothing was simulated for the skipped hours, and nobody is left inside.
	assert_int(ScoreManager.total_score).is_equal(score_after_shift)
	assert_bool(room.is_lobby_empty()).is_true()
	assert_str(eod.summary_label.text).contains("Your shifts today: 1")
	assert_int(score_after_shift - score_before).is_equal(BusinessDay.summary()["score"])
	eod.next_day_button.pressed.emit()
	assert_str(GameClock.timestamp()).is_equal("Day 2, 8:30 AM")

func test_the_doormat_is_where_the_player_goes_home() -> void:
	# On the entrance doormat (tiles 11-12, row 21), not at the spawn point.
	var door := room.exit_door
	assert_bool(room._interactables().has(door)).is_true()
	room.player.global_position = Vector2(384, 624)
	for i in 3:
		await get_tree().physics_frame
	assert_bool(door.player_in_range).is_false()
	room.player.global_position = Vector2(384, 690)
	for i in 3:
		await get_tree().physics_frame
	assert_bool(door.player_in_range).is_true()
	assert_object(room.interactable_in_range()).is_same(door)
	await frames(2)
	assert_bool(room.hud.prompt_panel.visible).is_true()
	assert_str(room.hud.prompt_label.text).is_equal("E — Go home (end Day 1)")

func test_a_day_left_open_past_midnight_still_ends_at_its_summary() -> void:
	set_clock(1, 23, 59)
	room.end_of_day_screen.visible = false
	GameClock.advance(2.0)
	assert_int(GameClock.day).is_equal(2)
	assert_bool(BusinessDay.is_day_over()).is_true()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	eod.next_day_button.pressed.emit()
	assert_str(GameClock.timestamp()).is_equal("Day 2, 8:30 AM")

# --- saving ---------------------------------------------------------------------------

func test_save_and_load_mid_day_and_across_days() -> void:
	# Mid-day, Day 2 at 11:15 with a shift and some customers behind it.
	set_clock(2, 11, 15)
	BusinessDay.customers_served_by_player = 3
	BusinessDay.customers_served_by_staff = 7
	BusinessDay.shifts_completed = 1
	ScoreManager.add_shift_score(12)
	get_tree().paused = true # hold the clock still
	var mid_day := SaveGame.capture()
	var summary := BusinessDay.summary()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(SaveGame.capture()).is_equal(mid_day)
	assert_dict(BusinessDay.summary()).is_equal(summary)
	assert_int(summary["score"]).is_equal(12)
	assert_str(GameClock.timestamp()).is_equal("Day 2, 11:15 AM")

	# Across days: end Day 2, start Day 3 (saved), load it.
	get_tree().paused = false
	set_clock(2, 17, 0)
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	eod.next_day_button.pressed.emit()
	get_tree().paused = true
	var next_morning := SaveGame.read().career
	CareerReset.reset_all()
	SaveGame.restore(next_morning)
	assert_str(GameClock.timestamp()).is_equal("Day 3, 8:30 AM")
	assert_int(BusinessDay.stats_day).is_equal(3)
	assert_int(BusinessDay.summary()["customers"]).is_equal(0)
	assert_int(BusinessDay.summary()["score"]).is_equal(0)
	assert_int(ScoreManager.total_score).is_equal(12)

	# A save from before the business day existed: today's totals start now.
	SaveGame.restore({"score": {"total_score": 40}, "clock": {"day": 4, "minutes": 600.0}})
	assert_int(BusinessDay.stats_day).is_equal(4)
	assert_int(BusinessDay.summary()["score"]).is_equal(0)
	assert_bool(BusinessDay.is_day_over()).is_false()
