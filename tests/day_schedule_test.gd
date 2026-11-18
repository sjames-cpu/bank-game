extends GdUnitTestSuite

## The business day's time slots (DaySchedule): the six slots in order with
## their times, the cutoff between 1 PM and 3 PM, and each role's work per
## slot (TIME_SLOTS_DECISIONS.md).

func test_the_six_slots_in_order() -> void:
	var ids: Array[StringName] = []
	var labels: Array[String] = []
	var times: Array[String] = []
	var work: Array[bool] = []
	for slot in DaySchedule.slots():
		ids.append(slot.id)
		labels.append(slot.label)
		times.append("%d:%02d" % [slot.hour, slot.minute])
		work.append(slot.is_work)
	assert_array(ids).is_equal([DaySchedule.OPENING, DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM, DaySchedule.CLOSING])
	assert_array(labels).is_equal(["Opening", "9 AM", "11 AM", "1 PM", "3 PM", "Closing"])
	assert_array(times).is_equal(["8:30", "9:00", "11:00", "13:00", "15:00", "17:00"])
	assert_array(work).is_equal([false, true, true, true, true, false])
	assert_int(DaySchedule.count()).is_equal(6)

func test_slot_times_match_the_business_day() -> void:
	assert_float(DaySchedule.slot_at(0).start_minutes()).is_equal(GameClock.START_MINUTES)
	assert_float(DaySchedule.slot_at(1).start_minutes()).is_equal(BusinessDay.OPEN_MINUTES)
	assert_float(DaySchedule.slot_at(DaySchedule.count() - 1).start_minutes()).is_equal(BusinessDay.CLOSE_MINUTES)

func test_3_pm_is_the_first_slot_after_the_2_pm_cutoff() -> void:
	var first := DaySchedule.first_after_cutoff_index()
	assert_int(first).is_equal(DaySchedule.index_of(DaySchedule.SLOT_3PM))
	assert_float(DaySchedule.slot_at(first).start_minutes()).is_greater_equal(BusinessDay.CUTOFF_MINUTES)
	assert_float(DaySchedule.slot_at(first - 1).start_minutes()).is_less(BusinessDay.CUTOFF_MINUTES)

func test_lookups() -> void:
	assert_int(DaySchedule.index_of(DaySchedule.OPENING)).is_equal(0)
	assert_int(DaySchedule.index_of(DaySchedule.CLOSING)).is_equal(5)
	assert_int(DaySchedule.index_of(&"lunch")).is_equal(-1)
	assert_object(DaySchedule.slot_at(-1)).is_null()
	assert_object(DaySchedule.slot_at(6)).is_null()
	# Built once and shared.
	assert_object(DaySchedule.slot_at(2)).is_same(DaySchedule.slots()[2])

func test_work_per_slot_for_each_role() -> void:
	# Each role's own amount is in its config.
	assert_int(TellerConfig.CUSTOMERS_PER_SLOT).is_equal(2)
	assert_int(LoanConfig.APPLICATIONS_PER_SLOT).is_equal(1)
	assert_int(DaySchedule.work_for(DaySchedule.WorkRole.STAFF_TELLER_WINDOW)).is_equal(4)
	assert_int(DaySchedule.work_for(DaySchedule.WorkRole.STAFF_LOAN_DESK)).is_equal(2)
