extends "res://tests/support/teller_room_suite.gd"

## B2 (opening count): a Major opening count blocks the shift until a
## recount; still Major after TellerScreen.MAX_OPENING_RECOUNTS recounts, a
## supervisor signs off (Reputation penalty, logged). Minor starts the shift
## and logs the variance. The drawer always starts at the assigned float and
## the opening count never earns Score or XP.

const FLOAT := TellerScreen.STARTING_FLOAT_CENTS
## $1,000 short — well past DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS.
const MAJOR_TOTAL := FLOAT - 100000

# --- helpers -------------------------------------------------------------------

## Presses Clock In (or Recount Drawer) and submits `total` as the opening
## count; `minor` adds one $10 bill for a Minor count.
func opening_count(total: int, minor: bool = false) -> void:
	open_desk()
	ts.clock_in_button.pressed.emit()
	count_drawer(total, minor)

func variance_records() -> Array[DecisionRecord]:
	var found: Array[DecisionRecord] = []
	for record in HistoryManager.records:
		if record.role == DecisionRecord.Role.DRAWER_VARIANCE:
			found.append(record)
	return found

func is_clocked_in() -> bool:
	return ts.shift_state == TellerScreen.ShiftState.CLOCKED_IN

## Serves the shift's customers so clock-out is allowed, then clocks out and
## returns the summary's opening line.
func finish_shift_summary() -> String:
	close_desk()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		serve_correctly(spawn())
	assert_bool(clock_out()).is_true()
	return ts.shift_opening_count_label.text

# --- tests ------------------------------------------------------------------------

func test_perfect_opening_count_starts_the_shift_immediately() -> void:
	var start_totals := totals()
	opening_count(FLOAT)
	assert_bool(is_clocked_in()).is_true()
	assert_bool(ts.awaiting_opening_recount).is_false()
	assert_str(ts.clock_in_button.text).is_equal("Clock In")
	assert_bool(cq.spawn_timer.is_stopped()).is_false() # the line opened
	assert_array(variance_records()).is_empty()
	assert_object(totals()).is_equal(start_totals)
	assert_int(ts.shift_start_cents).is_equal(FLOAT)
	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Perfect")

func test_minor_opening_count_starts_the_shift_and_logs_the_variance() -> void:
	var start_totals := totals()
	opening_count(FLOAT, true)
	assert_bool(is_clocked_in()).is_true()
	assert_object(totals()).is_equal(start_totals) # not scored
	assert_int(ts.shift_start_cents).is_equal(FLOAT)

	var records := variance_records()
	assert_int(records.size()).is_equal(1)
	assert_str(records[0].grade_label).is_equal("Minor")
	assert_str(records[0].description).contains("$10.00")

	# For the record only: Approvals offers no action on it.
	var approvals: ApprovalsScreen = room.get_node("UI/BranchManagerScreen/ApprovalsScreen")
	approvals._populate_entries()
	var rows := approvals.entries_vbox.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_bool(rows.any(func(n: Node) -> bool: return n is Label and (n as Label).text.contains("Drawer Variance"))).is_true()
	assert_bool(rows.any(func(n: Node) -> bool: return n is Button)).is_false()

	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Minor")

func test_major_opening_count_blocks_the_shift_until_a_recount() -> void:
	var start_totals := totals()
	opening_count(MAJOR_TOTAL)
	assert_bool(is_clocked_in()).is_false()
	assert_bool(ts.awaiting_opening_recount).is_true()
	assert_bool(cq.spawn_timer.is_stopped()).is_true() # no customers yet
	assert_str(ts.drawer_count_screen.status_label.text).contains("Major Discrepancy")
	assert_str(ts.drawer_count_screen.status_label.text).contains("Recount required before your shift can start (recount 1 of 2).")
	assert_bool(ts.error_label.visible).is_true()
	assert_str(ts.error_label.text).contains("Major discrepancy ($-1000.00)")
	assert_bool(ts.clock_in_button.visible).is_true()
	assert_str(ts.clock_in_button.text).is_equal("Recount Drawer")
	assert_bool(ts.clock_out_button.visible).is_false()

	# Leaving the desk doesn't skip the recount.
	close_desk()
	open_desk()
	assert_bool(ts.awaiting_opening_recount).is_true()
	assert_str(ts.clock_in_button.text).is_equal("Recount Drawer")

	# Recount reopens the drawer count, titled as a recount.
	ts.clock_in_button.pressed.emit()
	assert_bool(ts.drawer_count_screen.visible).is_true()
	assert_str(ts.drawer_count_screen.title_label.text).is_equal("Recount Drawer (1 of 2)")
	count_drawer(FLOAT)
	assert_bool(is_clocked_in()).is_true()
	assert_bool(ts.awaiting_opening_recount).is_false()
	assert_str(ts.clock_in_button.text).is_equal("Clock In")
	assert_array(variance_records()).is_empty() # recount was Perfect
	assert_object(totals()).is_equal(start_totals)

	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Major, recounted once, then Perfect")

func test_minor_recount_starts_the_shift_and_logs() -> void:
	opening_count(MAJOR_TOTAL)
	opening_count(MAJOR_TOTAL)
	assert_bool(is_clocked_in()).is_false()
	assert_str(ts.drawer_count_screen.status_label.text).contains("(recount 2 of 2)")
	opening_count(FLOAT, true)
	assert_bool(is_clocked_in()).is_true()
	var records := variance_records()
	assert_int(records.size()).is_equal(1)
	assert_str(records[0].grade_label).is_equal("Minor")
	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Major, recounted twice, then Minor")

func test_three_major_counts_trigger_the_supervisor_sign_off() -> void:
	var start_totals := totals()
	opening_count(MAJOR_TOTAL)
	opening_count(MAJOR_TOTAL)
	assert_bool(is_clocked_in()).is_false()
	assert_array(variance_records()).is_empty()

	ts.clock_in_button.pressed.emit()
	assert_str(ts.drawer_count_screen.title_label.text).is_equal("Recount Drawer (2 of 2)")
	count_drawer(MAJOR_TOTAL)

	var notice := "Your supervisor verified the drawer at $3000.00 and signed off. The variance has been recorded."
	assert_bool(is_clocked_in()).is_true()
	assert_str(ts.drawer_count_screen.status_label.text).contains(notice)
	assert_bool(ts.feedback_label.visible).is_true()
	assert_str(ts.feedback_label.text).is_equal("%s (%+d Reputation)" % [notice, TellerScreen.OPENING_SIGN_OFF_REPUTATION])

	# Reputation penalty only — no Score or XP.
	assert_int(TellerScreen.OPENING_SIGN_OFF_REPUTATION).is_equal(-2)
	assert_object(totals()).is_equal(start_totals + Vector3i(0, TellerScreen.OPENING_SIGN_OFF_REPUTATION, 0))

	var records := variance_records()
	assert_int(records.size()).is_equal(1)
	assert_str(records[0].grade_label).is_equal("Signed off")
	assert_str(records[0].description).contains("$-1000.00")
	assert_str(records[0].description).contains("supervisor verified the drawer")

	# The drawer still starts at the float; closing expectations unchanged.
	assert_int(ts.shift_start_cents).is_equal(FLOAT)
	assert_int(ts._calculate_expected_ending_cents()).is_equal(FLOAT)

	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Major, recounted twice, signed off")

## The next shift's opening starts fresh, and the summary fits the 648px
## window with each kind of opening line (each a single line).
func test_next_shift_opens_fresh_and_summary_fits() -> void:
	for i in 3:
		opening_count(MAJOR_TOTAL)
	cq.spawn_timer.stop()
	finish_shift_summary()
	var one_line := ts.shift_total_transactions_label.get_line_height()
	assert_float(await settled_height(ts.shift_summary_panel)).is_less_equal(648.0)
	assert_int(ts.shift_opening_count_label.get_line_count()).is_equal(1)
	assert_float(ts.shift_opening_count_label.size.y).is_less_equal(one_line + 1.0)
	close_desk()

	opening_count(MAJOR_TOTAL)
	opening_count(MAJOR_TOTAL)
	opening_count(FLOAT, true)
	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Major, recounted twice, then Minor")
	assert_float(await settled_height(ts.shift_summary_panel)).is_less_equal(648.0)
	assert_float(ts.shift_opening_count_label.size.y).is_less_equal(one_line + 1.0)
	close_desk()

	opening_count(FLOAT)
	assert_bool(is_clocked_in()).is_true()
	cq.spawn_timer.stop()
	assert_str(finish_shift_summary()).is_equal("Opening count: Perfect")
