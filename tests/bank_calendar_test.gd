extends "res://tests/support/teller_room_suite.gd"

## The bank's calendar (BankCalendar, GameClock, BusinessDay): Day 1 is
## Monday 5 January 2026 and each day is the next business day; the HUD,
## records and End of Day summaries show the date; weekends and Federal
## Reserve holidays (observed dates included) are skipped with a notice
## naming them; teller transactions from the 2:00 PM cutoff post on the next
## business day; the Regional Manager counts business days; the calendar is
## saved.

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen

# --- helpers -------------------------------------------------------------------

func set_clock(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func date(year: int, month: int, day: int) -> int:
	return BankCalendar.epoch_day(year, month, day)

## Off shift on `day`: go home, and the End of Day summary is up.
func end_day(day: int) -> void:
	set_clock(day, 12, 0)
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()

# --- the calendar --------------------------------------------------------------------

func test_day_1_is_monday_5_january_2026() -> void:
	assert_int(BankCalendar.weekday(BankCalendar.start_date())).is_equal(BankCalendar.Weekday.MONDAY)
	assert_int(GameClock.today_date()).is_equal(date(2026, 1, 5))
	assert_str(GameClock.hud_text()).is_equal("Mon, Day 1 · 8:30 AM")
	room.hud.refresh()
	assert_str(room.hud.clock_label.text).is_equal("Mon, Day 1 · 8:30 AM")
	assert_str(GameClock.timestamp()).is_equal("Day 1, Mon 5 Jan, 8:30 AM")
	# Records carry the date.
	var record := HistoryManager.add_record(DecisionRecord.Role.TELLER, "test")
	assert_str(record.timestamp).is_equal("Day 1, Mon 5 Jan, 8:30 AM")
	assert_int(GameClock.day_of(record.timestamp)).is_equal(1)
	# Older saves' stamps still give their day.
	assert_int(GameClock.day_of("Day 7, 10:42 AM")).is_equal(7)
	# The summary shows the full date.
	await end_day(1)
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	assert_str(eod.summary_label.text).starts_with("Monday 5 January 2026\n")

func test_date_conversions() -> void:
	assert_int(date(1970, 1, 1)).is_equal(0)
	assert_int(BankCalendar.weekday(0)).is_equal(BankCalendar.Weekday.THURSDAY)
	for day in range(date(1999, 12, 1), date(2032, 3, 1), 37):
		var c := BankCalendar.civil(day)
		assert_int(date(c.x, c.y, c.z)).is_equal(day)
	assert_str(BankCalendar.iso(date(2028, 2, 29))).is_equal("2028-02-29")
	assert_int(BankCalendar.from_iso("2026-01-05", -1)).is_equal(date(2026, 1, 5))
	assert_int(BankCalendar.from_iso("2027-02-29", -1)).is_equal(-1)
	assert_int(BankCalendar.from_iso("soon", -1)).is_equal(-1)
	assert_str(BankCalendar.long_text(date(2026, 1, 20))).is_equal("Tuesday 20 January 2026")

## Day N is the Nth business day: Friday 9 January is Day 5, Monday 12 is
## Day 6, and Monday 19 (a holiday) has no day: Day 11 is Tuesday 20.
func test_days_are_business_days() -> void:
	assert_str(BankCalendar.short_text(GameClock.date_of_day(5))).is_equal("Fri 9 Jan")
	assert_str(BankCalendar.short_text(GameClock.date_of_day(6))).is_equal("Mon 12 Jan")
	assert_str(BankCalendar.short_text(GameClock.date_of_day(10))).is_equal("Fri 16 Jan")
	assert_str(BankCalendar.short_text(GameClock.date_of_day(11))).is_equal("Tue 20 Jan")
	for day in range(1, 300):
		assert_bool(BankCalendar.is_business_day(GameClock.date_of_day(day))).is_true()

# --- weekends and holidays -------------------------------------------------------------

func test_a_weeknight_goes_straight_to_the_next_day() -> void:
	await end_day(2)
	eod.next_day_button.pressed.emit()
	assert_bool(eod.visible).is_false()
	assert_int(GameClock.day).is_equal(3)
	assert_str(GameClock.hud_text()).is_equal("Wed, Day 3 · 8:30 AM")

func test_the_weekend_is_skipped_with_a_notice() -> void:
	await end_day(5)
	assert_str(eod.summary_label.text).starts_with("Friday 9 January 2026")
	assert_str(eod.next_day_button.text).is_equal("Start Day 6")
	eod.next_day_button.pressed.emit()
	# Not yet Monday: the notice first.
	assert_bool(eod.is_closure_shown()).is_true()
	assert_int(GameClock.day).is_equal(5)
	assert_str(eod.summary_title_label.text).is_equal("Weekend — the branch is closed")
	assert_str(eod.summary_label.text).contains("Sat 10 Jan — weekend\nSun 11 Jan — weekend")
	assert_str(eod.summary_label.text).contains("The branch reopens on Monday 12 January 2026.")
	assert_str(eod.next_day_button.text).is_equal("Start Day 6")
	eod.next_day_button.pressed.emit()
	# Straight to Monday morning.
	assert_bool(eod.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(GameClock.day).is_equal(6)
	assert_float(GameClock.minutes).is_equal(GameClock.START_MINUTES)
	assert_str(GameClock.hud_text()).is_equal("Mon, Day 6 · 8:30 AM")

func test_a_holiday_after_a_weekend_is_named() -> void:
	await end_day(10)
	eod.next_day_button.pressed.emit()
	assert_str(eod.summary_title_label.text).is_equal("Weekend and Birthday of Martin Luther King, Jr. — the branch is closed")
	assert_str(eod.summary_label.text).contains("Sat 17 Jan — weekend\nSun 18 Jan — weekend\nMon 19 Jan — Birthday of Martin Luther King, Jr.")
	assert_str(eod.summary_label.text).contains("reopens on Tuesday 20 January 2026")
	eod.next_day_button.pressed.emit()
	assert_str(GameClock.hud_text()).is_equal("Tue, Day 11 · 8:30 AM")

func test_a_midweek_holiday_and_one_before_a_weekend() -> void:
	# A career starting the Monday of Thanksgiving week.
	GameClock.start_date = date(2026, 11, 23)
	await end_day(3) # Wednesday 25 November
	eod.next_day_button.pressed.emit()
	assert_str(eod.summary_title_label.text).is_equal("Thanksgiving Day — the branch is closed")
	assert_str(eod.summary_label.text).contains("Thu 26 Nov — Thanksgiving Day")
	eod.next_day_button.pressed.emit()
	assert_str(BankCalendar.short_text(GameClock.today_date())).is_equal("Fri 27 Nov")

	# Juneteenth 2026 is a Friday: closed with the weekend after it.
	GameClock.start_date = date(2026, 6, 15)
	await end_day(4) # Thursday 18 June
	eod.next_day_button.pressed.emit()
	assert_str(eod.summary_title_label.text).is_equal("Juneteenth National Independence Day and the weekend — the branch is closed")
	eod.next_day_button.pressed.emit()
	assert_str(BankCalendar.short_text(GameClock.today_date())).is_equal("Mon 22 Jun")

func test_the_federal_reserve_holidays_of_2026() -> void:
	var closed := BankCalendar.holidays_in(2026)
	var expected := {
		date(2026, 1, 1): "New Year's Day",
		date(2026, 1, 19): "Birthday of Martin Luther King, Jr.",
		date(2026, 2, 16): "Washington's Birthday",
		date(2026, 5, 25): "Memorial Day",
		date(2026, 6, 19): "Juneteenth National Independence Day",
		date(2026, 9, 7): "Labor Day",
		date(2026, 10, 12): "Columbus Day",
		date(2026, 11, 11): "Veterans Day",
		date(2026, 11, 26): "Thanksgiving Day",
		date(2026, 12, 25): "Christmas Day",
	}
	assert_dict(closed).is_equal(expected)
	# Independence Day 2026 is a Saturday: no weekday closure.
	assert_bool(BankCalendar.is_business_day(date(2026, 7, 3))).is_true()

## Sunday holidays are observed on Monday; Saturday ones aren't moved (the
## Federal Reserve Banks open the Friday before).
func test_observed_holiday_dates() -> void:
	# Sunday -> Monday.
	assert_str(BankCalendar.holiday_name(date(2027, 7, 5))).is_equal("Independence Day (observed)")
	assert_str(BankCalendar.holiday_name(date(2022, 6, 20))).is_equal("Juneteenth National Independence Day (observed)")
	assert_str(BankCalendar.holiday_name(date(2029, 11, 12))).is_equal("Veterans Day (observed)")
	assert_str(BankCalendar.holiday_name(date(2023, 1, 2))).is_equal("New Year's Day (observed)")
	assert_str(BankCalendar.holiday_name(date(2033, 12, 26))).is_equal("Christmas Day (observed)")
	assert_bool(BankCalendar.is_business_day(date(2027, 7, 5))).is_false()
	# Saturday: open the Friday before.
	assert_bool(BankCalendar.is_business_day(date(2027, 12, 24))).is_true() # Christmas 2027
	assert_bool(BankCalendar.is_business_day(date(2027, 12, 31))).is_true() # New Year 2028
	assert_bool(BankCalendar.is_business_day(date(2027, 6, 18))).is_true() # Juneteenth 2027
	assert_str(BankCalendar.holiday_name(date(2027, 12, 27))).is_equal("")
	# Floating holidays.
	assert_str(BankCalendar.holiday_name(date(2027, 5, 31))).is_equal("Memorial Day")
	assert_str(BankCalendar.holiday_name(date(2027, 11, 25))).is_equal("Thanksgiving Day")
	assert_str(BankCalendar.holiday_name(date(2028, 1, 17))).is_equal("Birthday of Martin Luther King, Jr.")

# --- the cutoff ---------------------------------------------------------------------

func test_transactions_after_2_pm_post_on_the_next_business_day() -> void:
	set_clock(5, 13, 50) # Friday
	clock_in()
	var before_cutoff := spawn(ShiftTransaction.Type.DEPOSIT, 200.0)
	open_desk()
	assert_bool(ts.cutoff_label.visible).is_false()
	close_desk()
	serve_correctly(before_cutoff)
	assert_int(ts.shift_transactions[-1].posting_day).is_equal(5)

	GameClock.minutes = 14.0 * 60.0 + 10.0
	var after_cutoff := spawn(ShiftTransaction.Type.WITHDRAWAL, 50.0)
	var balance_before := after_cutoff.account.balance_cents
	var customer_name := after_cutoff.display_name
	open_desk()
	assert_bool(ts.cutoff_label.visible).is_true()
	assert_str(ts.cutoff_label.text).is_equal("After cutoff — posts Mon 12 Jan")
	close_desk()
	serve_correctly(after_cutoff)
	var transaction: ShiftTransaction = ts.shift_transactions[-1]
	assert_int(transaction.posting_day).is_equal(6)
	assert_str(transaction.timestamp).is_equal("Day 5, Fri 9 Jan, 2:10 PM")
	# The balance and the drawer move at once, as before.
	assert_int(after_cutoff.account.balance_cents).is_equal(balance_before - 5000)
	assert_int(ts._calculate_expected_ending_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS + 20000 - 5000)

	# Clock out after the doors close (the shift's other two customers never
	# come), listing the shift's after-cutoff transaction for today.
	GameClock.minutes = 17.0 * 60.0 + 5.0
	assert_bool(clock_out()).is_true()
	assert_int(BusinessDay.after_cutoff.size()).is_equal(1)
	assert_dict(BusinessDay.after_cutoff[0]).is_equal({"time": "2:10 PM", "type": "Withdrawal", "amount_cents": 5000, "account": customer_name, "posting_day": 6})
	ts.shift_summary_done_button.pressed.emit()
	close_desk()
	await everyone_leaves()
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_label.text).contains("After the 2:00 PM cutoff, posting Mon 12 Jan: 1\n2:10 PM Withdrawal $50.00 — %s" % customer_name)
	# The next day starts with none.
	eod.next_day_button.pressed.emit()
	eod.next_day_button.pressed.emit()
	assert_bool(BusinessDay.after_cutoff.is_empty()).is_true()

func everyone_leaves() -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)

# --- the Regional Manager ------------------------------------------------------------

## Promoted on Friday 16 January (Day 10): the review comes after 5 business
## days, on Monday 26 January, past a weekend, a holiday and another weekend.
func test_the_regional_review_counts_business_days() -> void:
	set_clock(10, 12, 0)
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	assert_int(RegionalManager.next_review_day()).is_equal(15)
	assert_str(BankCalendar.short_text(GameClock.date_of_day(11))).is_equal("Tue 20 Jan")
	assert_str(BankCalendar.short_text(GameClock.date_of_day(15))).is_equal("Mon 26 Jan")
	assert_str(RegionalManager.status_text()).is_equal("Next review: Day 15 · Warnings 0/3")

# --- save and load -------------------------------------------------------------------

func test_save_and_load_across_a_weekend() -> void:
	await end_day(5)
	BusinessDay.after_cutoff.append({"time": "3:00 PM", "type": "Deposit", "amount_cents": 1000, "account": "Sam Chen", "posting_day": 6})
	var friday := SaveGame.capture()
	assert_str(SaveGame.dict_of(friday, "clock")["start_date"]).is_equal("2026-01-05")
	assert_bool(SaveGame.save()).is_true()
	eod.close()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(SaveGame.capture()).is_equal(friday)
	assert_str(BankCalendar.short_text(GameClock.today_date())).is_equal("Fri 9 Jan")
	assert_int(BusinessDay.after_cutoff.size()).is_equal(1)

	# Loaded Friday evening: the summary again, then the weekend, then Monday.
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	eod.next_day_button.pressed.emit()
	assert_str(eod.summary_title_label.text).is_equal("Weekend — the branch is closed")
	eod.next_day_button.pressed.emit()
	assert_str(GameClock.hud_text()).is_equal("Mon, Day 6 · 8:30 AM")
	var monday := SaveGame.read().career # saved as the day starts
	CareerReset.reset_all()
	SaveGame.restore(monday)
	assert_int(GameClock.day).is_equal(6)
	assert_str(GameClock.hud_text()).is_equal("Mon, Day 6 · 8:30 AM")

	# A career's own start date is kept.
	GameClock.start_date = date(2026, 11, 23)
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_int(GameClock.start_date).is_equal(BankCalendar.start_date())
	SaveGame.restore(SaveGame.read().career)
	assert_int(GameClock.start_date).is_equal(date(2026, 11, 23))
	# A save from before the calendar starts on 5 January 2026.
	GameClock.load_data({"day": 3, "minutes": 600.0})
	assert_str(BankCalendar.short_text(GameClock.today_date())).is_equal("Wed 7 Jan")
