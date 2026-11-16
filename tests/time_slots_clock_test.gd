extends GdUnitTestSuite

## The clock and the business day with time slots on (DayFlow.slots_enabled):
## GameClock stops running and shows each slot's start time, and BusinessDay's
## hours and cutoff follow the slots instead of the minutes. With slots off,
## nothing changes.

## The reason every slot is held in these tests, so each can be looked at.
const LOOK: StringName = &"test looks at the slot"

func before_test() -> void:
	DayFlow.slots_enabled = DayFlow.SLOTS_ENABLED
	CareerReset.reset_all()

func after_test() -> void:
	if DayFlow.slot_started.is_connected(_hold_slot):
		DayFlow.slot_started.disconnect(_hold_slot)
	DayFlow.slots_enabled = DayFlow.SLOTS_ENABLED
	CareerReset.reset_all()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _hold_slot(_slot: DaySlot) -> void:
	DayFlow.hold(LOOK)

## Starts a day with slots on, held at every slot, and moves on to `id`.
func go_to_slot(id: StringName) -> void:
	if not DayFlow.is_running():
		DayFlow.slots_enabled = true
		DayFlow.slot_started.connect(_hold_slot)
		DayFlow.start_day()
	while DayFlow.current_slot().id != id:
		DayFlow.release(LOOK)

# --- GameClock -----------------------------------------------------------------------

func test_the_clock_stops_running_with_slots_on() -> void:
	GameClock.minutes = 600.0
	DayFlow.slots_enabled = true
	await frames(5)
	assert_float(GameClock.minutes).is_equal(600.0)
	# Off, it runs again (the continuous clock as before).
	DayFlow.slots_enabled = false
	await frames(5)
	assert_float(GameClock.minutes).is_greater(600.0)

func test_the_clock_shows_each_slot_start_time_before_it_is_announced() -> void:
	DayFlow.slots_enabled = true
	var seen: Array[String] = []
	var record := func(_slot: DaySlot) -> void: seen.append(GameClock.time_text())
	DayFlow.slot_started.connect(record)
	DayFlow.start_day()
	DayFlow.slot_started.disconnect(record)
	assert_array(seen).is_equal(["8:30 AM", "9:00 AM", "11:00 AM", "1:00 PM", "3:00 PM", "5:00 PM"])
	assert_int(GameClock.day).is_equal(1)

func test_with_slots_off_dayflow_leaves_the_clock_alone() -> void:
	GameClock.minutes = 600.0
	DayFlow.start_day()
	assert_float(GameClock.minutes).is_equal(600.0)

# --- BusinessDay ----------------------------------------------------------------------

func test_before_the_day_starts() -> void:
	DayFlow.slots_enabled = true
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_false()
	assert_bool(BusinessDay.can_start_shift()).is_true()
	assert_bool(BusinessDay.is_after_cutoff()).is_false()

func test_opening_is_not_open_for_customers() -> void:
	go_to_slot(DaySchedule.OPENING)
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_false()
	assert_bool(BusinessDay.can_start_shift()).is_true()

func test_the_work_slots_are_open() -> void:
	for id: StringName in [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]:
		go_to_slot(id)
		assert_bool(BusinessDay.is_open()).override_failure_message("open at %s" % id).is_true()
		assert_bool(BusinessDay.doors_closed()).is_false()
		assert_bool(BusinessDay.can_start_shift()).is_true()

func test_the_cutoff_is_between_1_pm_and_3_pm() -> void:
	go_to_slot(DaySchedule.SLOT_1PM)
	assert_bool(BusinessDay.is_after_cutoff()).is_false()
	assert_int(BusinessDay.posting_day()).is_equal(1)
	assert_str(BusinessDay.cutoff_text()).is_empty()
	go_to_slot(DaySchedule.SLOT_3PM)
	assert_bool(BusinessDay.is_after_cutoff()).is_true()
	assert_int(BusinessDay.posting_day()).is_equal(2)
	assert_str(BusinessDay.cutoff_text()).is_equal("After cutoff — posts Tue 6 Jan")

func test_closing_closes_the_doors_and_shifts() -> void:
	go_to_slot(DaySchedule.CLOSING)
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_true()
	assert_bool(BusinessDay.can_start_shift()).is_false()

func test_with_slots_on_the_minutes_do_not_decide() -> void:
	# The slot decides, whatever the clock says.
	go_to_slot(DaySchedule.OPENING)
	GameClock.minutes = 10.0 * 60.0
	assert_bool(BusinessDay.is_open()).is_false()
	go_to_slot(DaySchedule.SLOT_1PM)
	GameClock.minutes = 14.0 * 60.0 + 30.0
	assert_bool(BusinessDay.is_after_cutoff()).is_false()

func test_with_slots_off_the_minutes_still_decide() -> void:
	# A day running in DayFlow changes nothing while the switch is off.
	DayFlow.slot_started.connect(_hold_slot)
	DayFlow.start_day()
	DayFlow.release(LOOK) # 9 AM
	GameClock.minutes = 8.0 * 60.0 + 40.0
	assert_bool(BusinessDay.is_open()).is_false()
	GameClock.minutes = 14.0 * 60.0
	assert_bool(BusinessDay.is_open()).is_true()
	assert_bool(BusinessDay.is_after_cutoff()).is_true()
	GameClock.minutes = 17.0 * 60.0
	assert_bool(BusinessDay.doors_closed()).is_true()

func test_not_open_between_slots() -> void:
	DayFlow.slots_enabled = true
	DayFlow.pause_between_slots = true
	DayFlow.start_day()
	DayFlow.continue_day() # 9 AM, unclaimed: ends, and the day waits
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(BusinessDay.is_open()).is_false()
	assert_bool(BusinessDay.doors_closed()).is_false()
