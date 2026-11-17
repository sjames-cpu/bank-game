extends "res://tests/support/teller_room_suite.gd"

## The Regional visit and the review's time measures on the time-slot day:
## on a review day the Regional Manager walks in when the 11 AM slot starts
## and out when it ends or is skipped, without holding it; vacant desks
## still count two desk-hours per work slot (the clock jumps at each slot's
## start), eight for a whole day; and a vault witness's time away is counted
## from unpaused seconds, since the clock stands still inside a slot.

var manager: ManagerSlotAdapter
var bm: BranchManagerScreen

func before_test() -> void:
	await super()
	manager = room.get_node("ManagerSlotAdapter")
	bm = room.branch_manager_screen
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

## A Branch Manager's day started and clocked in (between Opening and 9 AM).
func manager_day() -> void:
	start_slots_day()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()

## Today is the Regional review day.
func make_review_day() -> void:
	var day := RegionalManager.next_review_day()
	GameClock.day = day
	BusinessDay.stats_day = day
	assert_bool(RegionalManager.is_review_day()).is_true()

# --- the Regional visit ---------------------------------------------------------------------

func test_the_regional_manager_visits_in_the_11_am_slot() -> void:
	promote()
	make_review_day()
	manager_day()
	continue_to_slot(DaySchedule.SLOT_9AM)
	await frames(2)
	assert_object(room.regional_visitor).is_null()
	manager.end_slot()
	continue_to_slot(DaySchedule.SLOT_11AM)
	# In from the entrance (not placed at the spot), and the slot isn't held.
	var visitor := room.regional_visitor
	assert_object(visitor).is_not_null()
	assert_vector(visitor.global_position).is_equal(TellerRoom.VISIT_ENTRANCE)
	assert_bool(DayFlow.is_held()).is_false()
	visitor.finish_route()
	assert_vector(visitor.global_position).is_equal(TellerRoom.VISIT_ROUTE[-1])
	await frames(3)
	assert_object(room.regional_visitor).is_same(visitor)
	# The slot ends as usual, and they walk out.
	manager.end_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_int(visitor.state).is_equal(StaffNPC.State.WALKING)
	visitor.finish_route()
	await frames(1)
	assert_bool(is_instance_valid(visitor)).is_false()
	assert_object(room.regional_visitor).is_null()
	# Not again today.
	manager.end_slot()
	continue_to_slot(DaySchedule.SLOT_1PM)
	assert_object(room.regional_visitor).is_null()

func test_a_skipped_11_am_slot_sends_them_out() -> void:
	promote()
	make_review_day()
	manager_day()
	continue_to_slot(DaySchedule.SLOT_9AM)
	manager.end_slot()
	continue_to_slot(DaySchedule.SLOT_11AM)
	var visitor := room.regional_visitor
	assert_object(visitor).is_not_null()
	DayFlow.skip_slot()
	assert_int(visitor.state).is_equal(StaffNPC.State.WALKING)

func test_no_visit_on_other_days() -> void:
	promote()
	assert_bool(RegionalManager.is_review_day()).is_false()
	manager_day()
	continue_to_slot(DaySchedule.SLOT_9AM)
	manager.end_slot()
	continue_to_slot(DaySchedule.SLOT_11AM)
	assert_object(room.regional_visitor).is_null()

# --- vacant desks ------------------------------------------------------------------------

func test_a_vacant_desk_counts_two_desk_hours_per_work_slot() -> void:
	promote()
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_2).staff_name)
	var vacant := ScheduleManager.vacant_slots().size()
	assert_int(vacant).is_equal(1)
	manager_day()
	await frames(1)
	var start := RegionalManager.vacant_desk_minutes
	continue_to_slot(DaySchedule.SLOT_9AM)
	await frames(2)
	# Inside a slot the clock stands still: nothing more.
	assert_float(RegionalManager.vacant_desk_minutes).is_equal_approx(start, 0.01)
	manager.end_slot()
	continue_to_slot(DaySchedule.SLOT_11AM)
	await frames(1)
	assert_float(RegionalManager.vacant_desk_minutes - start).is_equal_approx(120.0 * vacant, 0.01)
	# Going home: the rest of the day counts too, 8 desk-hours in all.
	manager.end_slot()
	DayFlow.go_home_early()
	await frames(1)
	assert_float(RegionalManager.vacant_desk_minutes - start).is_equal_approx(480.0 * vacant, 0.01)

# --- the vault witness's time away --------------------------------------------------------

func test_a_witness_s_time_away_counts_unpaused_seconds() -> void:
	promote()
	manager_day()
	continue_to_slot(DaySchedule.SLOT_9AM)
	var control := room.vault_control
	var witness := call_vault_witness()
	assert_object(witness).is_not_null()
	var vault := bm.vault_reconciliation_screen
	assert_bool(vault.is_visible_in_tree()).is_true()
	# 4 unpaused seconds away: 6 game minutes at the clock's usual rate,
	# though the clock itself doesn't move inside the slot.
	var minutes_before := GameClock.minutes
	control._process(4.0)
	vault.close_button.pressed.emit()
	witness.finish_route()
	assert_float(GameClock.minutes).is_equal(minutes_before)
	assert_float(bm.shift_vault_minutes[witness.staff.staff_name]).is_equal_approx(4.0 * GameClock.GAME_MINUTES_PER_SECOND, 0.01)
