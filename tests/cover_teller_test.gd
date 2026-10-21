extends "res://tests/support/teller_room_suite.gd"

## The cover teller (teller_room.gd, ScheduleManager.cover_teller()): while
## the player works Loan Desk 1, the teller who'd take Teller Window 3 at
## promotion (Nina Ortiz by default) walks from the break room to the
## Player Teller Window and runs its line as a staff window. Clock-out:
## they finish their customer, the rest move to Windows 1/2 or leave, and
## they walk back. The covered window says so; a dismissed or busy default
## falls back to another free teller, or nobody; promotion hands the window
## to Teller Window 3's staff and a demotion brings the cover back.

var lo: LoanOfficerScreen
var w3: NpcCustomerLine

func before_test() -> void:
	await super()
	lo = room.loan_officer_screen
	w3 = room.window3_line
	XPManager.is_loan_officer_unlocked = true
	GameClock.minutes = 10 * 60.0
	BusinessDay.stats_day = GameClock.day
	# Arrivals are made by hand here.
	for line: NpcCustomerLine in [room.window1_npc_line, room.window2_line, w3]:
		line.spawn_timer.stop()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func loan_clock_in() -> void:
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.close_button.pressed.emit()
	w3.spawn_timer.stop()

func loan_clock_out() -> void:
	room._on_loan_officer_desk_interacted()
	lo.applications_reviewed = LoanOfficerScreen.APPLICATIONS_PER_SHIFT
	lo.clock_out_button.pressed.emit()
	lo.shift_summary_done_button.pressed.emit()
	if lo.visible:
		lo.close_button.pressed.emit()

## The cover teller is at the window (skipping the walk).
func cover_at_window() -> void:
	room.cover_npc.place_at(room._desk_spot(ScheduleManager.SLOT_TELLER_WINDOW_3), StaffNPC.State.AT_DESK)

## A customer already standing at `line`'s window.
func customer_at_window(line: NpcCustomerLine) -> CustomerNPC:
	line._spawn_customer()
	var customer: CustomerNPC = line.queue[-1]
	customer.global_position = line.queue_positions[0].global_position
	customer.queue_spot = 0
	return customer

func waiting_customers(line: NpcCustomerLine, count: int) -> void:
	for i in count:
		line._spawn_customer()

# --- clocking in --------------------------------------------------------------------

func test_clocking_in_at_a_loan_desk_brings_the_cover_teller() -> void:
	assert_object(room.cover_npc).is_null()
	assert_bool(w3.active).is_false()
	loan_clock_in()
	var cover := room.cover_npc
	assert_object(cover).is_not_null()
	assert_str(cover.staff.staff_name).is_equal("Nina Ortiz")
	assert_str(ScheduleManager.cover_teller().staff_name).is_equal(cover.staff.staff_name)
	# From the break room to the window.
	assert_int(cover.state).is_equal(StaffNPC.State.WALKING)
	assert_vector(cover._route.back()).is_equal(room._desk_spot(ScheduleManager.SLOT_TELLER_WINDOW_3))
	# The window's line runs as a staff window.
	assert_bool(w3.active).is_true()
	assert_object(w3.staff_npc).is_same(cover)
	assert_str(w3.slot_name).is_equal("Player Teller Window")
	# Nobody else moved: the schedule and Teller Windows 1 and 2 as before.
	assert_bool(ScheduleManager.schedule.has(ScheduleManager.SLOT_TELLER_WINDOW_3)).is_false()
	assert_bool(room.window1_npc_line.active and room.window2_line.active).is_true()

	# Served like any staff window: logged, and counted in today's totals.
	cover_at_window()
	var served_before := BusinessDay.customers_served_by_staff
	customer_at_window(w3)
	await frames(2)
	assert_bool(w3.is_serving()).is_true()
	w3._mistake_pending = false
	w3._time_left = 0.0
	await frames(2)
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_int(record.role).is_equal(DecisionRecord.Role.STAFF)
	assert_str(record.staff_name).is_equal("Nina Ortiz")
	assert_str(record.staff_slot).is_equal("Player Teller Window")
	assert_str(record.description).starts_with("Nina Ortiz (Player Teller Window) ")
	assert_int(BusinessDay.customers_served_by_staff).is_equal(served_before + 1)

	# Staff-window rules: at most 3 in line, no complaints, opening hours only.
	for i in 6:
		w3._on_spawn_timer_timeout()
	assert_int(w3.queue.size()).is_equal(3)
	for customer in w3.queue:
		assert_object(customer.complaint).is_null()
	w3.clear_lobby()
	GameClock.minutes = 18 * 60.0
	w3._on_spawn_timer_timeout()
	assert_bool(w3.queue.is_empty()).is_true()

func test_the_covered_window_says_who_is_covering() -> void:
	loan_clock_in()
	var text := "Nina Ortiz is covering this window while you work the Loan Desk."
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal(text)
	room._on_teller_desk_interacted()
	assert_bool(room.teller_screen.visible).is_false()
	assert_bool(room.desk_notice.visible).is_true()
	assert_str(room.desk_notice_label.text).is_equal(text)

# --- clocking out ---------------------------------------------------------------------

func test_clock_out_sends_the_cover_teller_back_and_frees_the_window() -> void:
	loan_clock_in()
	cover_at_window()
	var at_window := customer_at_window(w3)
	waiting_customers(w3, 2)
	await frames(2)
	assert_bool(w3.is_serving()).is_true()
	var moving: CustomerNPC = w3.queue[1]
	var leaving: CustomerNPC = w3.queue[2]
	# Room for one more at Teller Window 1; Teller Window 2 is full.
	waiting_customers(room.window1_npc_line, 2)
	waiting_customers(room.window2_line, 3)

	loan_clock_out()
	assert_bool(lo.is_clocked_in()).is_false()
	# No new arrivals; the first waiting customer moves over, the other leaves.
	assert_bool(w3.active).is_false()
	assert_bool(w3.spawn_timer.is_stopped()).is_true()
	assert_array(w3.queue).is_equal([at_window])
	assert_object(room.window1_npc_line.queue.back()).is_same(moving)
	assert_object(moving.get_parent()).is_same(room.window1_npc_line)
	assert_bool(room.window2_line.queue.has(leaving)).is_false()
	assert_bool(leaving.is_walking()).is_true()
	# The cover teller finishes the customer at the window first.
	assert_bool(room.is_window_covered()).is_true()
	assert_int(room.cover_npc.state).is_equal(StaffNPC.State.AT_DESK)
	w3._mistake_pending = false
	w3._time_left = 0.0
	await frames(3)
	assert_bool(w3.queue.is_empty()).is_true()
	# Then walks back to the break room, and the window is the player's again.
	var cover := room.cover_npc
	assert_bool(room.is_window_covered()).is_false()
	assert_int(cover.state).is_equal(StaffNPC.State.WALKING)
	assert_vector(cover._route.back()).is_equal(room._break_spot_for(ScheduleManager.SLOT_TELLER_WINDOW_3))
	assert_object(w3.staff_npc).is_null()
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal("E — Clock in (Player Teller Window)")
	cover.route_finished.emit()
	await frames(1)
	assert_object(room.cover_npc).is_null()
	assert_bool(is_instance_valid(cover)).is_false()
	# The next Loan Desk shift brings them again.
	loan_clock_in()
	assert_str(room.cover_npc.staff.staff_name).is_equal("Nina Ortiz")

func test_an_empty_window_winds_down_at_once() -> void:
	loan_clock_in()
	cover_at_window()
	loan_clock_out()
	await frames(2)
	assert_bool(room.is_window_covered()).is_false()
	assert_int(room.cover_npc.state).is_equal(StaffNPC.State.WALKING)

# --- who covers ---------------------------------------------------------------------------

func test_the_cover_falls_back_to_a_free_teller_or_nobody() -> void:
	# Nina placed elsewhere: Walter, now off the floor, covers.
	var schedule := ScheduleManager.schedule.duplicate()
	var walter: StaffMember = schedule[ScheduleManager.SLOT_TELLER_WINDOW_2]
	assert_str(walter.staff_name).is_equal("Walter Higgins")
	for member in ScheduleManager.get_roster():
		if member.staff_name == "Nina Ortiz":
			schedule[ScheduleManager.SLOT_TELLER_WINDOW_2] = member
	ScheduleManager.confirm_schedule(schedule)
	assert_str(ScheduleManager.cover_teller().staff_name).is_equal("Walter Higgins")
	loan_clock_in()
	assert_str(room.cover_npc.staff.staff_name).is_equal("Walter Higgins")
	loan_clock_out()
	room._dismiss_cover()

	# Nina dismissed and the other tellers at their windows: nobody covers.
	ScheduleManager.reset()
	ScheduleManager.schedule_confirmed.emit(ScheduleManager.schedule)
	ScheduleManager.dismiss_staff("Nina Ortiz")
	assert_object(ScheduleManager.cover_teller()).is_null()
	loan_clock_in()
	assert_object(room.cover_npc).is_null()
	assert_bool(w3.active).is_false()
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal("E — Clock in (Player Teller Window)")
	loan_clock_out()

	# A hired teller off the floor covers instead.
	var hire := StaffMember.new()
	hire.staff_name = "Ada Park"
	hire.role = "Teller"
	ScheduleManager.hired_staff.append(hire)
	loan_clock_in()
	assert_str(room.cover_npc.staff.staff_name).is_equal("Ada Park")

# --- promotion and demotion ---------------------------------------------------------------

func test_promotion_hands_the_window_to_teller_window_3_and_demotion_brings_the_cover_back() -> void:
	loan_clock_in()
	cover_at_window()
	customer_at_window(w3)
	await frames(2)
	# Promotion earned mid-shift waits for clock-out.
	ReputationManager.reputation = 70
	XPManager.total_xp = XPManager.XP_UNLOCK_THRESHOLD_BRANCH_MANAGER - 10
	XPManager.add_shift_xp(1)
	assert_bool(XPManager.is_branch_manager_promotion_pending).is_true()
	loan_clock_out()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	# Teller Window 3's own staff member has the window and its line; no cover.
	assert_object(room.cover_npc).is_null()
	var window_3: StaffNPC = room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_3]
	assert_str(window_3.staff.staff_name).is_equal("Nina Ortiz")
	assert_object(w3.staff_npc).is_same(window_3)
	assert_bool(w3.active).is_true()
	assert_str(w3.slot_name).is_equal("Teller Window 3")
	assert_int(w3.queue.size()).is_equal(1) # the customer at the window stays
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal("Nina Ortiz is working this window.")

	RegionalManager._demote()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	assert_bool(w3.active).is_false()
	assert_bool(room._staff_by_slot.has(ScheduleManager.SLOT_TELLER_WINDOW_3)).is_false()
	loan_clock_in()
	assert_str(room.cover_npc.staff.staff_name).is_equal("Nina Ortiz")
	assert_bool(w3.active).is_true()
	assert_str(w3.slot_name).is_equal("Player Teller Window")
