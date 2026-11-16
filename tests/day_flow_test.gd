extends GdUnitTestSuite

## The day as time slots (DayFlow): the slots in order, claimed work keeping
## a slot open, holds, skips, unclaimed slots moving on at once, the
## cutoff, day_ended once, listeners acting inside the signals, and misuse
## warning without crashing (TIME_SLOTS_DECISIONS.md).

## Everything DayFlow announced, in order: "start slot_9am", "end slot_9am",
## "skip slot_9am", "day ended".
var events: Array[String] = []
## What the test's role does when a slot starts, by slot id.
var on_start: Dictionary[StringName, Callable] = {}

func before_test() -> void:
	DayFlow.reset()
	events.clear()
	on_start.clear()
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_ended.connect(_on_slot_ended)
	DayFlow.slot_skipped.connect(_on_slot_skipped)
	DayFlow.day_ended.connect(_on_day_ended)

func after_test() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_ended.disconnect(_on_slot_ended)
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)
	DayFlow.day_ended.disconnect(_on_day_ended)
	DayFlow.reset()

func _on_slot_started(slot: DaySlot) -> void:
	events.append("start %s" % slot.id)
	if on_start.has(slot.id):
		on_start[slot.id].call()

func _on_slot_ended(slot: DaySlot) -> void:
	events.append("end %s" % slot.id)

func _on_slot_skipped(slot: DaySlot) -> void:
	events.append("skip %s" % slot.id)

func _on_day_ended() -> void:
	events.append("day ended")

# --- helpers -------------------------------------------------------------------

## The events of slots `from` to the end of the day, each started and ended
## with nobody claiming it.
func unclaimed_from(from: StringName) -> Array[String]:
	var list: Array[String] = []
	for i in range(DaySchedule.index_of(from), DaySchedule.count()):
		var id := DaySchedule.slot_at(i).id
		list.append("start %s" % id)
		list.append("end %s" % id)
	list.append("day ended")
	return list

func claim_at(slot_id: StringName, claimant: Variant) -> void:
	on_start[slot_id] = func() -> void: DayFlow.claim_work(claimant)

func current_id() -> StringName:
	return DayFlow.current_slot().id

# --- the day ----------------------------------------------------------------------

func test_nobody_claiming_runs_the_whole_day_in_order() -> void:
	assert_bool(DayFlow.is_running()).is_false()
	assert_object(DayFlow.current_slot()).is_null()
	assert_bool(DayFlow.start_day()).is_true()
	assert_array(events).is_equal(unclaimed_from(DaySchedule.OPENING))
	assert_bool(DayFlow.is_running()).is_false()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)

func test_claimed_work_keeps_the_slot_until_it_is_finished() -> void:
	claim_at(DaySchedule.SLOT_9AM, "teller")
	DayFlow.start_day()
	assert_array(events).is_equal(["start opening", "end opening", "start slot_9am"])
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_running()).is_true()
	assert_bool(DayFlow.has_claimed("teller")).is_true()

	events.clear()
	assert_bool(DayFlow.finish_work("teller")).is_true()
	assert_array(events).is_equal(unclaimed_from(DaySchedule.SLOT_9AM).slice(1))
	assert_bool(DayFlow.has_claimed("teller")).is_false()

func test_two_claims_both_have_to_finish() -> void:
	on_start[DaySchedule.SLOT_11AM] = func() -> void:
		DayFlow.claim_work("teller")
		DayFlow.claim_work(&"staff window 1")
	DayFlow.start_day()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_11AM)

	DayFlow.finish_work("teller")
	assert_str(current_id()).is_equal(DaySchedule.SLOT_11AM)
	assert_bool(events.has("end slot_11am")).is_false()

	DayFlow.finish_work(&"staff window 1")
	assert_bool(events.has("end slot_11am")).is_true()
	assert_bool(events.has("day ended")).is_true()

func test_holds_keep_the_slot_until_every_one_is_released() -> void:
	on_start[DaySchedule.SLOT_9AM] = func() -> void:
		DayFlow.claim_work("teller")
		DayFlow.hold(&"armored truck")
		DayFlow.hold(&"cutscene")
	DayFlow.start_day()
	assert_bool(DayFlow.is_held()).is_true()

	# The work is done, but the slot is still held.
	DayFlow.finish_work("teller")
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	DayFlow.release(&"cutscene")
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_held()).is_true()

	DayFlow.release(&"armored truck")
	assert_bool(DayFlow.is_held()).is_false()
	assert_bool(events.has("end slot_9am")).is_true()
	assert_bool(events.has("day ended")).is_true()

func test_a_hold_with_no_work_still_holds_the_slot() -> void:
	on_start[DaySchedule.OPENING] = func() -> void: DayFlow.hold(&"opening cutscene")
	DayFlow.start_day()
	assert_array(events).is_equal(["start opening"])
	DayFlow.release(&"opening cutscene")
	assert_array(events).is_equal(unclaimed_from(DaySchedule.OPENING))

# --- skipping -------------------------------------------------------------------

func test_skipping_a_slot_drops_its_claimed_work() -> void:
	claim_at(DaySchedule.SLOT_9AM, "teller")
	claim_at(DaySchedule.SLOT_11AM, "teller")
	DayFlow.start_day()
	events.clear()
	assert_bool(DayFlow.skip_slot()).is_true()
	assert_array(events).is_equal(["skip slot_9am", "start slot_11am"])
	# The 11 AM claim is a new one; the 9 AM work is gone.
	assert_str(current_id()).is_equal(DaySchedule.SLOT_11AM)
	DayFlow.finish_work("teller")
	assert_bool(events.has("end slot_11am")).is_true()

func test_a_skip_inside_slot_started_skips_that_slot() -> void:
	# A break-in skips the 9 AM slot as it starts (decision 11).
	on_start[DaySchedule.SLOT_9AM] = func() -> void: DayFlow.skip_slot()
	DayFlow.start_day()
	var expected: Array[String] = ["start opening", "end opening", "start slot_9am", "skip slot_9am"]
	expected.append_array(unclaimed_from(DaySchedule.SLOT_11AM))
	assert_array(events).is_equal(expected)

func test_a_skip_waits_for_the_holds() -> void:
	on_start[DaySchedule.SLOT_9AM] = func() -> void:
		DayFlow.claim_work("teller")
		DayFlow.hold(&"break-in cutscene")
	DayFlow.start_day()
	DayFlow.skip_slot()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(events.has("skip slot_9am")).is_false()
	DayFlow.release(&"break-in cutscene")
	assert_bool(events.has("skip slot_9am")).is_true()
	assert_bool(events.has("end slot_9am")).is_false()
	assert_bool(events.has("day ended")).is_true()

# --- listeners acting inside the signals -------------------------------------------

func test_work_claimed_and_finished_inside_slot_started_keeps_the_order() -> void:
	# A role that finishes at once, and a second listener after it: the
	# second still hears 9 AM start before anything ends, and 9 AM ends once.
	on_start[DaySchedule.SLOT_9AM] = func() -> void:
		DayFlow.claim_work("instant role")
		DayFlow.finish_work("instant role")
	var second := func(slot: DaySlot) -> void: events.append("second hears %s" % slot.id)
	DayFlow.slot_started.connect(second)
	DayFlow.start_day()
	DayFlow.slot_started.disconnect(second)

	assert_array(events.slice(0, 7)).is_equal([
		"start opening", "second hears opening", "end opening",
		"start slot_9am", "second hears slot_9am", "end slot_9am",
		"start slot_11am",
	])
	assert_int(events.count("end slot_9am")).is_equal(1)
	assert_int(events.count("day ended")).is_equal(1)

func test_finishing_one_slot_stops_at_the_next_claimed_one() -> void:
	# The same role claims each slot as it starts: finishing 9 AM's work
	# starts 11 AM, which waits for its own.
	claim_at(DaySchedule.SLOT_9AM, "teller")
	claim_at(DaySchedule.SLOT_11AM, "teller")
	DayFlow.start_day()
	DayFlow.finish_work("teller")
	assert_str(current_id()).is_equal(DaySchedule.SLOT_11AM)
	assert_bool(DayFlow.has_claimed("teller")).is_true()
	assert_int(events.count("end slot_9am")).is_equal(1)
	assert_bool(events.has("end slot_11am")).is_false()

# --- the cutoff -------------------------------------------------------------------------

func test_the_cutoff_falls_between_1_pm_and_3_pm() -> void:
	assert_bool(DayFlow.is_after_cutoff()).is_false()
	var seen: Array[bool] = []
	var record := func(_slot: DaySlot) -> void: seen.append(DayFlow.is_after_cutoff())
	DayFlow.slot_started.connect(record)
	DayFlow.start_day()
	DayFlow.slot_started.disconnect(record)
	# Opening, 9 AM, 11 AM, 1 PM, 3 PM, Closing.
	assert_array(seen).is_equal([false, false, false, false, true, true])
	# Still after the cutoff once the day has ended (at Closing).
	assert_bool(DayFlow.is_after_cutoff()).is_true()

# --- the end of the day -----------------------------------------------------------------

func test_day_ended_fires_once_per_day() -> void:
	DayFlow.start_day()
	assert_int(events.count("day ended")).is_equal(1)
	# Nothing after the end moves the day on again.
	DayFlow.skip_slot()
	DayFlow.finish_work("teller")
	assert_int(events.count("day ended")).is_equal(1)
	# A new day starts at Opening and ends once more.
	events.clear()
	assert_bool(DayFlow.start_day()).is_true()
	assert_array(events).is_equal(unclaimed_from(DaySchedule.OPENING))

func test_a_new_day_started_from_day_ended_runs_in_order() -> void:
	var days := [0]
	var next_day := func() -> void:
		days[0] += 1
		if days[0] == 1:
			DayFlow.start_day()
	DayFlow.day_ended.connect(next_day)
	DayFlow.start_day()
	DayFlow.day_ended.disconnect(next_day)
	var expected := unclaimed_from(DaySchedule.OPENING)
	expected.append_array(unclaimed_from(DaySchedule.OPENING))
	assert_array(events).is_equal(expected)

func test_reset_stops_the_day() -> void:
	on_start[DaySchedule.SLOT_1PM] = func() -> void:
		DayFlow.claim_work("teller")
		DayFlow.hold(&"truck")
	DayFlow.start_day()
	DayFlow.skip_slot()
	DayFlow.reset()
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(DayFlow.is_held()).is_false()
	assert_bool(DayFlow.has_claimed("teller")).is_false()
	assert_object(DayFlow.current_slot()).is_null()
	# And the next day starts clean, without the pending skip.
	on_start.clear()
	events.clear()
	DayFlow.start_day()
	assert_array(events).is_equal(unclaimed_from(DaySchedule.OPENING))

# --- misuse warns and carries on -------------------------------------------------------

func test_misuse_warns_and_changes_nothing() -> void:
	# Before any day.
	assert_bool(DayFlow.claim_work("teller")).is_false()
	assert_bool(DayFlow.finish_work("teller")).is_false()
	assert_bool(DayFlow.hold(&"truck")).is_false()
	assert_bool(DayFlow.release(&"truck")).is_false()
	assert_bool(DayFlow.skip_slot()).is_false()
	assert_array(events).is_empty()

	claim_at(DaySchedule.SLOT_9AM, "teller")
	DayFlow.start_day()
	events.clear()
	# A second day while one runs, finishing unclaimed work, claiming or
	# holding twice, releasing an unknown hold.
	assert_bool(DayFlow.start_day()).is_false()
	assert_bool(DayFlow.finish_work("loan officer")).is_false()
	assert_bool(DayFlow.claim_work("teller")).is_false()
	assert_bool(DayFlow.hold(&"truck")).is_true()
	assert_bool(DayFlow.hold(&"truck")).is_false()
	assert_bool(DayFlow.release(&"regional visit")).is_false()
	assert_array(events).is_empty()
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.has_claimed("teller")).is_true()

	DayFlow.release(&"truck")
	DayFlow.finish_work("teller")
	assert_int(events.count("day ended")).is_equal(1)
	# After the day ended.
	events.clear()
	assert_bool(DayFlow.claim_work("teller")).is_false()
	assert_bool(DayFlow.finish_work("teller")).is_false()
	assert_bool(DayFlow.hold(&"truck")).is_false()
	assert_bool(DayFlow.release(&"truck")).is_false()
	assert_bool(DayFlow.skip_slot()).is_false()
	assert_array(events).is_empty()
