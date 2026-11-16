extends "res://tests/support/teller_room_suite.gd"

## Starting the real day with time slots on (teller_room.start_slots_day()):
## when the room loads and at "Start Day N+1", never twice and never
## straight from an End of Day; a save made at End of Day shows that End of
## Day again (a stopgap); the doormat sends going home to the card; and a
## Branch Manager's day runs to its End of Day without sticking.

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

## The room loaded again (as from the slot screen) with the current setting.
func reload_room() -> void:
	room.free()
	var fresh := instantiate_room()
	get_tree().root.add_child(fresh)
	get_tree().current_scene = fresh
	adopt_room(fresh)
	eod = room.end_of_day_screen
	await frames(1)

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

## A Teller day straight to Closing (going home at the first card), then
## clocked out: its End of Day is up.
func teller_day_to_end_of_day() -> void:
	start_slots_day()
	clock_in()
	DayFlow.go_home_early()
	assert_bool(clock_out()).is_true()
	close_desk()
	await frames(2)

# --- when the day starts -----------------------------------------------------------------

func test_the_day_starts_when_the_room_loads() -> void:
	use_slots_setting(true)
	await reload_room()
	assert_bool(DayFlow.is_running()).is_true()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(DayFlow.pause_between_slots).is_true()
	assert_str(GameClock.time_text()).is_equal("8:30 AM")

func test_with_slots_off_no_day_starts() -> void:
	await reload_room()
	assert_bool(DayFlow.is_running()).is_false()
	room.start_slots_day()
	assert_bool(DayFlow.is_running()).is_false()

func test_a_day_never_starts_twice() -> void:
	start_slots_day()
	clock_in()
	assert_bool(DayFlow.is_between_slots()).is_true()
	room.start_slots_day()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_9AM)

func test_start_day_n_plus_1_starts_the_next_day_and_nothing_else_does() -> void:
	await teller_day_to_end_of_day()
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(DayFlow.is_running()).is_false()
	# Waiting on the summary starts nothing.
	room.start_slots_day()
	await frames(3)
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(eod.is_summary_shown()).is_true()

	eod.next_day_button.pressed.emit()
	assert_int(BusinessDay.stats_day).is_equal(2)
	assert_bool(DayFlow.is_running()).is_true()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(DayFlow.end_of_day_due).is_false()
	await frames(3)
	assert_bool(eod.visible).is_false()
	# Day 2 waits for the clock-in like Day 1.
	assert_str(current_id()).is_equal(DaySchedule.OPENING)

func test_a_save_made_at_end_of_day_shows_that_end_of_day_again() -> void:
	# The summary saves with the clock at 5 PM (business_day_test.gd).
	GameClock.minutes = BusinessDay.CLOSE_MINUTES
	use_slots_setting(true)
	await reload_room()
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(DayFlow.end_of_day_due).is_true()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	eod.next_day_button.pressed.emit()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(GameClock.day).is_equal(2)

# --- going home ------------------------------------------------------------------------

func test_the_doormat_points_to_the_card() -> void:
	start_slots_day()
	room._on_exit_door_interacted()
	assert_bool(eod.visible).is_false()
	assert_bool(room.desk_notice.visible).is_true()
	assert_str(room.desk_notice_label.text).is_equal(TellerRoom.GO_HOME_BETWEEN_SLOTS_TEXT)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)

func test_business_day_going_home_goes_through_dayflow() -> void:
	start_slots_day()
	clock_in()
	BusinessDay.go_home_early()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	assert_float(GameClock.minutes).is_equal(BusinessDay.CLOSE_MINUTES)

# --- other roles until session 2b -------------------------------------------------------

func test_a_branch_manager_day_runs_to_its_end_of_day() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	start_slots_day()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_true()
	bm.hide_screen()
	acknowledge_letters() # the orientation letter
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.BRANCH_MANAGER)
	# Each work slot rushes through, a card each, to Closing.
	var cards := 0
	while DayFlow.is_between_slots():
		await frames(1)
		assert_bool(room.slot_card.visible).is_true()
		cards += 1
		room.slot_card.continue_button.pressed.emit()
	assert_int(cards).is_equal(5)
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(2)
	assert_bool(eod.visible).is_false()
	reconcile_vault()
	bm.clock_out_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_false()
	bm.hide_screen()
	acknowledge_letters()
	await frames(3)
	assert_bool(eod.is_summary_shown()).is_true()
