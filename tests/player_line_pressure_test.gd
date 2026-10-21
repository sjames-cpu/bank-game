extends "res://tests/support/teller_room_suite.gd"

## Staffing reaches the player's line: customers choosing a line come to the
## Player Teller Window sooner when the staff windows are closed or their
## lines are long (teller_room.staff_window_pressure(),
## NpcCustomerLine.crowding(), CustomerQueue.arrival_pressure). A fully,
## well staffed branch keeps the usual 20 s gap; the gap never drops below
## 10 s; the 4-customer shift cap still holds.

const NORMAL := 20.0
const SHORTEST := 10.0

var w1: NpcCustomerLine
var w2: NpcCustomerLine

func before_test() -> void:
	await super()
	w1 = room.window1_npc_line
	w2 = room.window2_line
	# Staff-line arrivals are added by hand here.
	for line: NpcCustomerLine in [w1, w2]:
		line.spawn_timer.stop()

## `count` customers in a staff line (the first one at the window).
func fill(line: NpcCustomerLine, count: int) -> void:
	for i in count:
		line._spawn_customer()

func close_window(slot_name: String) -> void:
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(slot_name).staff_name)

## The gap the player's line starts next, from a real arrival tick.
func next_gap() -> float:
	cq._on_spawn_timer_timeout()
	var gap := cq.spawn_timer.wait_time
	cq.spawn_timer.stop()
	return gap

func test_a_fully_and_well_staffed_branch_keeps_the_usual_pace() -> void:
	assert_float(cq.spawn_interval).is_equal(NORMAL)
	assert_bool(w1.active and w2.active).is_true()
	# Empty lines, and each window busy with one customer and nobody behind.
	assert_float(room.staff_window_pressure()).is_equal(0.0)
	assert_float(next_gap()).is_equal(NORMAL)
	fill(w1, 1)
	fill(w2, 1)
	assert_float(room.staff_window_pressure()).is_equal(0.0)
	cq.start_shift()
	assert_float(cq.spawn_timer.wait_time).is_equal(NORMAL)
	cq.spawn_timer.stop()
	assert_float(next_gap()).is_equal(NORMAL)

func test_a_closed_staff_window_brings_customers_sooner() -> void:
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_1)
	assert_bool(w1.active).is_false()
	assert_float(w1.crowding()).is_equal(1.0)
	assert_float(room.staff_window_pressure()).is_equal(0.5)
	assert_float(next_gap()).is_equal(15.0)
	cq.start_shift()
	assert_float(cq.spawn_timer.wait_time).is_equal(15.0)
	cq.spawn_timer.stop()

	# Both closed: the shortest gap.
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_float(room.staff_window_pressure()).is_equal(1.0)
	assert_float(next_gap()).is_equal(SHORTEST)

func test_long_staff_lines_bring_customers_sooner() -> void:
	# One waiting behind the customer at Teller Window 1: half full.
	fill(w1, 2)
	assert_float(w1.crowding()).is_equal(0.5)
	assert_float(room.staff_window_pressure()).is_equal(0.25)
	assert_float(next_gap()).is_equal(17.5)
	# Teller Window 1 full.
	fill(w1, 1)
	assert_float(w1.crowding()).is_equal(1.0)
	assert_float(next_gap()).is_equal(15.0)
	# Both full: as if both were closed.
	fill(w2, 3)
	assert_float(next_gap()).is_equal(SHORTEST)
	# A slow teller's line clearing brings the usual pace back.
	for line: NpcCustomerLine in [w1, w2]:
		while not line.queue.is_empty():
			line.send_customer_off(line.serve_front_customer())
	assert_float(next_gap()).is_equal(NORMAL)

func test_the_gap_stays_within_its_limits() -> void:
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_1)
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_float(next_gap()).is_equal(SHORTEST)
	cq.arrival_pressure = func() -> float: return 5.0
	assert_float(next_gap()).is_equal(SHORTEST)
	cq.arrival_pressure = func() -> float: return -1.0
	assert_float(next_gap()).is_equal(NORMAL)
	cq.arrival_pressure = Callable()
	assert_float(next_gap()).is_equal(NORMAL)

## Under the most pressure the player's line still brings 4 customers a
## shift, waits for room in the line, and only in opening hours.
func test_the_shift_cap_and_opening_hours_still_hold() -> void:
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_1)
	close_window(ScheduleManager.SLOT_TELLER_WINDOW_2)
	GameClock.minutes = 10 * 60.0
	clock_in()
	assert_int(cq.get_customers_left_to_spawn()).is_equal(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP)
	var arrivals := 0
	for tick in 12:
		var waiting := cq.queue.size()
		assert_float(next_gap()).is_equal(SHORTEST)
		if cq.queue.size() > waiting:
			arrivals += 1
		# Served straight away, so the line always has room.
		if not cq.queue.is_empty():
			cq.send_customer_off(cq.serve_front_customer())
	assert_int(arrivals).is_equal(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP)
	assert_int(cq.get_customers_left_to_spawn()).is_equal(0)

	# Closed hours: no arrivals at all, however busy the branch.
	cq.start_shift()
	cq.spawn_timer.stop()
	GameClock.minutes = 17 * 60.0 + 30.0
	for tick in 3:
		next_gap()
	assert_bool(cq.queue.is_empty()).is_true()
	assert_int(cq.get_customers_left_to_spawn()).is_equal(CustomerQueue.CUSTOMERS_PER_SHIFT_CAP)
