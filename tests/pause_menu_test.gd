extends "res://tests/support/teller_room_suite.gd"

## The in-game pause menu (PauseMenu): Esc opens it (only while nothing else
## has the game paused) and pauses the game; Resume or Esc closes it. Back
## to Main Menu saves first off shift; on shift it asks first and saves
## nothing. Either way the slot is left and the career reset.

var menu: PauseMenu

func before_test() -> void:
	await super()
	menu = room.pause_menu

## The same event Esc sends (headless runs don't deliver real key presses).
func press_esc() -> void:
	var event := InputEventAction.new()
	event.action = PauseMenu.ACTION
	event.pressed = true
	menu._unhandled_input(event)

func await_scene_change() -> Node:
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().current_scene

func test_esc_is_bound_to_the_pause_menu() -> void:
	assert_bool(InputMap.has_action(PauseMenu.ACTION)).is_true()
	assert_str(InputPrompts.key_for(InputPrompts.PAUSE_MENU)).is_equal("Esc")
	var key := InputMap.action_get_events(PauseMenu.ACTION)[0] as InputEventKey
	assert_int(key.keycode).is_equal(KEY_ESCAPE)

func test_esc_opens_and_closes_the_menu() -> void:
	assert_bool(menu.visible).is_false()
	press_esc()
	assert_bool(menu.visible).is_true()
	assert_bool(menu.menu_panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(menu.resume_button.text).is_equal("Resume")
	assert_str(menu.main_menu_button.text).is_equal("Back to Main Menu")
	press_esc()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()

	press_esc()
	menu.resume_button.pressed.emit()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()

func test_esc_does_nothing_while_a_desk_screen_is_open() -> void:
	open_desk()
	assert_bool(get_tree().paused).is_true()
	press_esc()
	assert_bool(menu.visible).is_false()
	close_desk()
	assert_bool(get_tree().paused).is_false()

func test_back_to_main_menu_off_shift_saves_first() -> void:
	ScoreManager.add_shift_score(15)
	assert_bool(SaveGame.exists()).is_false()
	press_esc()
	menu.main_menu_button.pressed.emit()
	var scene := await await_scene_change()
	assert_object(scene).is_instanceof(StartScreen)
	var start := scene as StartScreen
	assert_bool(start.menu_panel.visible).is_true()
	# Saved to the slot being played, then that slot was left.
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read_slot(1).career, "score"), "total_score", -1)).is_equal(15)
	assert_int(SaveGame.current_slot).is_equal(0)
	assert_int(ScoreManager.total_score).is_equal(0)
	assert_bool(get_tree().paused).is_false()

func test_back_to_main_menu_on_shift_asks_and_saves_nothing() -> void:
	ScoreManager.add_shift_score(15)
	assert_bool(SaveGame.save()).is_true()
	var saved := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	clock_in()
	serve_correctly(spawn())
	assert_bool(room.is_player_on_shift()).is_true()

	press_esc()
	menu.main_menu_button.pressed.emit()
	assert_bool(menu.confirm_panel.visible).is_true()
	assert_bool(menu.menu_panel.visible).is_false()
	assert_str(menu.confirm_label.text).is_equal(PauseMenu.ON_SHIFT_TEXT)
	assert_str(menu.confirm_label.text).contains("loses everything since your last save")
	# Keep Playing goes back to the menu, still paused.
	menu.cancel_button.pressed.emit()
	assert_bool(menu.menu_panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(get_tree().current_scene).is_same(room)

	menu.main_menu_button.pressed.emit()
	menu.confirm_button.pressed.emit()
	var scene := await await_scene_change()
	assert_object(scene).is_instanceof(StartScreen)
	# The shift was never saved: the slot holds its last save.
	assert_str(FileAccess.get_file_as_string(TEST_SAVE_PATH)).is_equal(saved)
	assert_int(SaveGame.current_slot).is_equal(0)
	assert_int(ScoreManager.total_score).is_equal(0)
	assert_array(XPManager._desks_on_shift).is_empty()
	assert_bool(get_tree().paused).is_false()
