extends "res://tests/support/teller_room_suite.gd"

## The rest of what the player sees with time slots on: the day/night tint
## fades between slots instead of jumping (DayNightCycle.SLOT_FADE_SECONDS),
## the doormat points to the card for going home early, and the pause menu's
## Back to Main Menu warns that leaving mid-day restarts the day from
## Opening (decision 10). With slots off, all three are as before.

const DayNightCycle := preload("res://scripts/world/day_night_cycle.gd")

var tint: CanvasModulate
var menu: PauseMenu
var window_before: Vector2i

func before_test() -> void:
	await super()
	tint = room.get_node("DayNightCycle")
	menu = room.pause_menu
	window_before = get_tree().root.size

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func press_esc() -> void:
	var event := InputEventAction.new()
	event.action = PauseMenu.ACTION
	event.pressed = true
	menu._unhandled_input(event)

# --- the tint ------------------------------------------------------------------------------

func test_the_tint_fades_into_closing() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	await frames(1)
	assert_object(tint.color).is_equal(DayNightCycle.DAY)
	# Straight to Closing: the clock jumps from 9 AM to 5 PM.
	DayFlow.skip_slot()
	DayFlow.go_home_early()
	assert_float(GameClock.minutes).is_equal(BusinessDay.CLOSE_MINUTES)
	tint._process(DayNightCycle.SLOT_FADE_SECONDS / 2.0)
	# Halfway: neither the old colour nor the new one yet.
	assert_object(tint.color).is_not_equal(DayNightCycle.DAY)
	assert_object(tint.color).is_not_equal(DayNightCycle.LATE_AFTERNOON)
	assert_float(tint.color.b).is_between(DayNightCycle.LATE_AFTERNOON.b, DayNightCycle.DAY.b)
	tint._process(DayNightCycle.SLOT_FADE_SECONDS)
	assert_object(tint.color).is_equal(DayNightCycle.LATE_AFTERNOON)

# --- the doormat -----------------------------------------------------------------------------

func test_the_doormat_prompt_points_to_the_card() -> void:
	start_slots_day()
	assert_str(room.interaction_prompt_text(room.exit_door)).is_equal(TellerRoom.GO_HOME_SLOTS_PROMPT)

# --- the pause menu ------------------------------------------------------------------------

func test_leaving_mid_day_warns_the_day_restarts_from_opening() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	SaveGame.delete()
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH)).is_false()
	press_esc()
	menu.main_menu_button.pressed.emit()
	assert_bool(menu.confirm_panel.visible).is_true()
	assert_str(menu.confirm_label.text).is_equal(PauseMenu.MID_DAY_TEXT)
	assert_str(menu.confirm_label.text).contains("restarts from Opening")
	assert_str(menu.confirm_button.text).is_equal(PauseMenu.MID_DAY_CONFIRM_TEXT)
	menu.cancel_button.pressed.emit()
	assert_bool(menu.menu_panel.visible).is_true()
	# Leaving saves nothing.
	menu.main_menu_button.pressed.emit()
	menu.confirm_button.pressed.emit()
	await frames(2)
	assert_object(get_tree().current_scene).is_instanceof(StartScreen)
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH)).is_false()

## Clocked out at Closing, the day has ended (DayFlow.day_ended): leaving
## now loses nothing, since it's saved as an ended day.
func test_after_the_closing_clock_out_nothing_is_lost() -> void:
	start_slots_day()
	clock_in()
	DayFlow.go_home_early()
	assert_str(menu.leave_warning()).is_equal(PauseMenu.MID_DAY_TEXT)
	assert_bool(clock_out()).is_true()
	close_desk()
	assert_bool(DayFlow.end_of_day_due).is_true()
	assert_str(menu.leave_warning()).is_empty()

func test_at_opening_before_the_clock_in_nothing_is_lost() -> void:
	start_slots_day()
	assert_str(menu.leave_warning()).is_empty()

func test_the_warning_fits_the_screen() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	start_slots_day()
	clock_in()
	press_esc()
	menu.main_menu_button.pressed.emit()
	await frames(2)
	assert_array(layout_problems(menu.confirm_panel)).is_empty()
	menu.cancel_button.pressed.emit()
	menu.resume()
