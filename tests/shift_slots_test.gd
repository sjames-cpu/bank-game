extends "res://tests/support/teller_room_suite.gd"

## The shift in a time-slot day (ShiftSlotAdapter, PlayerShift): Opening
## waits for the player's clock-in at any desk, which records today's role;
## Closing waits for their clock-out; clocking out before Closing is
## refused. A Loan Officer's day neither crashes nor sticks.

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func loan_clock_in() -> void:
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()

## At Closing, where the shift ends.
func loan_clock_out() -> void:
	var screen := room.loan_officer_screen
	to_closing()
	room._on_loan_officer_desk_interacted()
	screen.clock_out_button.pressed.emit()
	screen.hide_screen()

# --- the shared signal ------------------------------------------------------------------

func test_every_desk_reports_its_clock_in_and_out() -> void:
	var heard: Array[String] = []
	var on_in := func(role: PlayerShift.Role) -> void: heard.append("in %d" % role)
	var on_out := func(role: PlayerShift.Role) -> void: heard.append("out %d" % role)
	PlayerShift.clocked_in.connect(on_in)
	PlayerShift.clocked_out.connect(on_out)
	clock_in()
	assert_int(PlayerShift.on_shift).is_equal(PlayerShift.Role.TELLER)
	assert_bool(clock_out()).is_true()
	close_desk()
	assert_int(PlayerShift.on_shift).is_equal(PlayerShift.Role.NONE)
	# The next day, at the Loan Desk.
	await go_to_next_day()
	loan_clock_in()
	loan_clock_out()
	PlayerShift.clocked_in.disconnect(on_in)
	PlayerShift.clocked_out.disconnect(on_out)
	assert_array(heard).is_equal([
		"in %d" % PlayerShift.Role.TELLER, "out %d" % PlayerShift.Role.TELLER,
		"in %d" % PlayerShift.Role.LOAN_OFFICER, "out %d" % PlayerShift.Role.LOAN_OFFICER,
	])

# --- Opening ------------------------------------------------------------------------

func test_opening_waits_for_the_teller_clock_in() -> void:
	start_slots_day()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	await frames(3)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(DayFlow.is_between_slots()).is_false()
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.NONE)

	clock_in()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_9AM)
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.TELLER)

func test_a_failed_opening_count_keeps_the_teller_in_opening() -> void:
	start_slots_day()
	open_desk()
	ts.clock_in_button.pressed.emit()
	count_drawer(TellerScreen.STARTING_FLOAT_CENTS - 50000) # Major: recount
	assert_bool(ts.awaiting_opening_recount).is_true()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(DayFlow.is_between_slots()).is_false()
	# The recount starts the shift, and Opening ends.
	ts.clock_in_button.pressed.emit()
	count_drawer(TellerScreen.STARTING_FLOAT_CENTS)
	close_desk()
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_opening_waits_for_the_loan_clock_in() -> void:
	start_slots_day()
	loan_clock_in()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.LOAN_OFFICER)

func test_todays_role_is_chosen_again_each_day() -> void:
	start_slots_day()
	clock_in()
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.TELLER)
	DayFlow.go_home_early() # straight to Closing
	assert_bool(clock_out()).is_true()
	close_desk()
	DayFlow.start_day()
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.NONE)

# --- Closing --------------------------------------------------------------------------

func test_closing_waits_for_the_clock_out() -> void:
	start_slots_day()
	clock_in()
	DayFlow.go_home_early() # straight to Closing (the work slots are TellerSlotAdapter's)
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(3)
	assert_bool(DayFlow.is_running()).is_true()
	assert_bool(eod.visible).is_false()

	assert_bool(clock_out()).is_true()
	close_desk()
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(DayFlow.end_of_day_due).is_true()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()

func test_clocking_out_before_closing_is_refused() -> void:
	start_slots_day()
	clock_in()
	DayFlow.continue_day() # 9 AM
	# Pressed now (clock_out() would go to Closing first).
	open_desk()
	ts.clock_out_button.pressed.emit()
	assert_bool(ts.drawer_count_screen.visible).is_false()
	assert_str(ts.error_label.text).is_equal("Can't clock out yet — your shift runs until Closing (5 PM).")
	assert_int(ts.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_IN)
	close_desk()

# --- a Loan Officer's day ---------------------------------------------------------------

## The shift around a Loan Officer's day: with every work slot skipped
## (loan_slots_test.gd has the work), Closing waits for the loan clock-out
## and End of Day follows.
func test_a_loan_officer_day_runs_to_its_end_of_day() -> void:
	start_slots_day()
	loan_clock_in()
	var waits := 0
	while DayFlow.is_between_slots() and DayFlow.next_slot().id != DaySchedule.CLOSING:
		waits += 1
		DayFlow.continue_day()
		DayFlow.skip_slot()
	assert_int(waits).is_equal(4)
	DayFlow.continue_day()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(3)
	assert_bool(eod.visible).is_false()
	loan_clock_out()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
