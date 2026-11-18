extends "res://tests/support/teller_room_suite.gd"

## The bank's game clock (GameClock), on a time-slot day: shows each slot's
## start time (DayFlow sets it), the HUD's day, the day/night tint, stamps
## everything the player sees with game time, and is saved and reset with
## the career.

var hud: Hud
var tint: CanvasModulate

func before_test() -> void:
	await super()
	# A time-slot day at Opening, as the room starts it.
	start_slots_day()
	hud = room.hud
	tint = room.get_node("DayNightCycle")

## Sets the clock, with the business day following it (as if every day
## before it had ended at its summary).
func set_clock(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

# --- running -----------------------------------------------------------------------

func test_a_new_career_starts_on_day_1_at_8_30() -> void:
	assert_int(GameClock.day).is_equal(1)
	assert_float(GameClock.minutes).is_between(GameClock.START_MINUTES, GameClock.START_MINUTES + 1.0)
	assert_float(GameClock.START_MINUTES).is_equal(510.0)
	set_clock(4, 15, 10)
	CareerReset.reset_all()
	assert_int(GameClock.day).is_equal(1)
	assert_float(GameClock.minutes).is_equal(510.0)
	assert_str(GameClock.timestamp()).is_equal("Day 1, Mon 5 Jan, 8:30 AM")

# --- showing it -------------------------------------------------------------------

func test_the_hud_shows_the_day_and_time_at_the_top() -> void:
	set_clock(3, 8, 30)
	hud.refresh()
	assert_str(hud.clock_label.text).is_equal("Wed, Day 3 · Opening")
	# The first line of the HUD column.
	assert_object(hud.clock_label.get_parent().get_child(0)).is_same(hud.clock_label)
	assert_bool(hud.clock_label.is_visible_in_tree()).is_true()
	var formats := {0.0: "12:00 AM", 59.9: "12:59 AM", 510.0: "8:30 AM", 720.0: "12:00 PM", 779.0: "12:59 PM", 1020.0: "5:00 PM", 1439.0: "11:59 PM"}
	for at: float in formats:
		assert_str(GameClock.format_time(at)).is_equal(formats[at])

func test_the_tint_follows_the_clock() -> void:
	get_tree().paused = true # hold the clock still
	var day := Color.WHITE
	var night := Color(0.35, 0.4, 0.6, 1.0)
	var cases := {
		3 * 60: night,                      # 3 AM
		10 * 60: day,                       # business hours
		14 * 60 + 59: day,
		17 * 60: Color(1.0, 0.9, 0.76, 1.0),  # warmest at 5 PM
		21 * 60: night,                     # evening
	}
	# Each new time's colour fades in over the slot fade (DayNightCycle).
	var fade := 1.5
	for at: int in cases:
		GameClock.minutes = at
		tint._process(fade)
		assert_object(tint.color).override_failure_message("at %s" % GameClock.format_time(at)).is_equal(cases[at])
	# Warming through the late afternoon: still bright, less blue.
	GameClock.minutes = 16 * 60
	tint._process(fade)
	assert_float(tint.color.r).is_equal(1.0)
	assert_float(tint.color.b).is_between(0.77, 0.99)
	# Dimming after 5 PM, and brightening before opening.
	GameClock.minutes = 18 * 60
	tint._process(fade)
	assert_float(tint.color.get_luminance()).is_less((Color(1.0, 0.9, 0.76).get_luminance()))
	assert_float(tint.color.get_luminance()).is_greater(night.get_luminance())
	GameClock.minutes = 7 * 60
	tint._process(fade)
	assert_float(tint.color.get_luminance()).is_between(night.get_luminance(), day.get_luminance())
	# No independent real-time cycle any more.
	assert_object(tint.get("cycle_duration_seconds")).is_null()
	assert_object(tint.get("_elapsed")).is_null()

func test_summaries_and_records_use_game_time() -> void:
	# Teller: clocked in at Opening on Day 1 (8:30 AM), out at Closing (5 PM).
	clock_in()
	assert_str(ts.shift_start_time).is_equal("Day 1, Mon 5 Jan, 8:30 AM")
	serve_correctly(spawn())
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP - 1:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	assert_str(ts.shift_start_time_label.text).is_equal("Start Time: Day 1, Mon 5 Jan, 8:30 AM")
	assert_str(ts.shift_end_time_label.text).is_equal("End Time: Day 1, Mon 5 Jan, 5:00 PM")
	var drawer_record: DecisionRecord = HistoryManager.records[-1]
	assert_str(drawer_record.description).starts_with("Drawer count")
	assert_str(drawer_record.timestamp).is_equal("Day 1, Mon 5 Jan, 5:00 PM")
	for record in HistoryManager.records:
		assert_str(record.timestamp).starts_with("Day 1, ")
	close_desk()

	# Day 2: a disciplinary report, stamped with the slot's time.
	await go_to_next_day()
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Alex Rivera")
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Sam Chen")
	assert_str(ReportManager.reports[-1].timestamp).is_equal("Day 2, Tue 6 Jan, 8:30 AM")
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()

	# Loan Officer, the same day: in at Opening, out at Closing.
	XPManager.is_loan_officer_unlocked = true
	var lo := room.loan_officer_screen
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	to_closing()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_str(lo.shift_start_time_label.text).is_equal("Start Time: Day 2, Tue 6 Jan, 8:30 AM")
	assert_str(lo.shift_end_time_label.text).is_equal("End Time: Day 2, Tue 6 Jan, 5:00 PM")
	lo.close_button.pressed.emit()

	# Day 3: Branch Manager, and a staff review item shown with its game time.
	await go_to_next_day()
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	customer.display_name = "Sam Chen"
	var item := StaffReviewManager.add_teller_mistake(ScheduleManager.get_roster()[0], ScheduleManager.SLOT_TELLER_WINDOW_1, customer, StaffReviewItem.TellerMistake.WRONG_ACCOUNT, "used the wrong account")
	assert_str(item.timestamp).is_equal("Day 3, Wed 7 Jan, 8:30 AM")
	bm.review_staff_button.pressed.emit()
	assert_str(bm.staff_review_screen.staff_label.text).contains("Day 3, Wed 7 Jan, 8:30 AM")
	bm.staff_review_screen.close_button.pressed.emit()
	to_closing()
	bm._prepare_shift_summary()
	assert_str(bm.shift_start_time_label.text).is_equal("Start Time: Day 3, Wed 7 Jan, 8:30 AM")
	assert_str(bm.shift_end_time_label.text).is_equal("End Time: Day 3, Wed 7 Jan, 5:00 PM")

	# Nothing the player sees carries a wall-clock date.
	for record in HistoryManager.records:
		assert_str(record.timestamp).starts_with("Day ")
		# An ISO date ("2026-10-21T10:42:00") has hyphens; game timestamps don't.
		assert_str(record.timestamp).not_contains("-")

# --- saving ------------------------------------------------------------------------

func test_the_clock_is_saved_and_shown_on_the_start_screen() -> void:
	set_clock(5, 14, 7)
	GameClock.minutes += 0.5
	get_tree().paused = true # hold the clock still
	var saved_career := SaveGame.capture()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_int(GameClock.day).is_equal(1)
	SaveGame.restore(SaveGame.read().career)
	assert_dict(SaveGame.capture()).is_equal(saved_career)
	assert_int(GameClock.day).is_equal(5)
	assert_float(GameClock.minutes).is_equal(14 * 60 + 7.5)
	# The slot screen: a day saved before it ended picks up at its start.
	assert_str(StartScreen.slot_text(1, SaveGame.read())).contains("Day 5 · Friday 9 January 2026 · Start of day")
	# A save from before the clock existed starts the career's clock afresh.
	SaveGame.restore({})
	assert_str(GameClock.timestamp()).is_equal("Day 1, Mon 5 Jan, 8:30 AM")
	# Out-of-range values are kept in range.
	SaveGame.restore({"clock": {"day": -4, "minutes": 99999}})
	assert_int(GameClock.day).is_equal(1)
	assert_float(GameClock.minutes).is_less(GameClock.MINUTES_PER_DAY)
