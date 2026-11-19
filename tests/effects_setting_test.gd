extends "res://tests/support/shared/room_suite.gd"

## The "Effects: On / Off" setting (EffectsSetting and the pause menu's
## button): On by default, kept in a small settings file of its own, never in a
## career save or a save slot, and held to the same guard as the saves (only
## the real game flow may write the real file). Tests and scratch scripts
## point it at files of their own; the shared test base does, with Effects Off.

func test_the_shared_test_base_runs_with_effects_off_and_its_own_file() -> void:
	assert_bool(EffectsSetting.is_on()).is_false()
	assert_str(EffectsSetting.path).is_equal(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_real_file(EffectsSetting.path)).is_false()

func test_effects_are_on_by_default_when_there_is_no_file() -> void:
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(FileAccess.file_exists(TEST_SETTINGS_PATH)).is_false()
	assert_bool(EffectsSetting.is_on()).is_true()

func test_the_setting_is_kept_in_its_own_file_and_read_back() -> void:
	EffectsSetting.set_on(false)
	assert_bool(FileAccess.file_exists(TEST_SETTINGS_PATH)).is_true()
	# A fresh read of the file (as at the next launch).
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_on()).is_false()
	EffectsSetting.set_on(true)
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_on()).is_true()

func test_a_setting_that_is_not_saved_leaves_no_file() -> void:
	EffectsSetting.set_on(true, false)
	assert_bool(FileAccess.file_exists(TEST_SETTINGS_PATH)).is_false()

func test_a_damaged_or_odd_file_falls_back_to_on() -> void:
	var file := FileAccess.open(TEST_SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("this is not a settings file {{{")
	file.close()
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_on()).is_true()
	file = FileAccess.open(TEST_SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("[effects]\non=\"maybe\"\n")
	file.close()
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_on()).is_true()

# --- never in a career save -----------------------------------------------------------------------

func test_the_setting_never_touches_a_career_save() -> void:
	# A real career in the test slot, saved.
	assert_bool(SaveGame.save()).is_true()
	var before_bytes := FileAccess.get_file_as_bytes(TEST_SAVE_PATH)
	assert_int(before_bytes.size()).is_greater(0)
	EffectsSetting.set_on(false)
	EffectsSetting.set_on(true)
	EffectsSetting.set_on(false)
	assert_array(FileAccess.get_file_as_bytes(TEST_SAVE_PATH)).is_equal(before_bytes)
	# The save has no trace of it, and the settings file has no career in it.
	var saved := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	assert_bool(saved.contains("effects")).is_false()
	var settings_text := FileAccess.get_file_as_string(TEST_SETTINGS_PATH)
	assert_bool(settings_text.contains("score")).is_false()
	assert_bool(settings_text.contains("career")).is_false()
	# Not the same file as any save slot.
	assert_str(EffectsSetting.path).is_not_equal(TEST_SAVE_PATH)
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		assert_str(EffectsSetting.REAL_PATH).is_not_equal(SaveGame.slot_path(slot))
		assert_str(EffectsSetting.REAL_PATH).is_not_equal("%s_slot_%d.json" % [SaveGame.REAL_PREFIX, slot])

func test_a_save_never_writes_the_setting_and_a_new_career_keeps_it() -> void:
	EffectsSetting.set_on(false)
	assert_bool(SaveGame.save()).is_true()
	assert_bool(EffectsSetting.is_on()).is_false()
	CareerReset.reset_all()
	assert_bool(EffectsSetting.is_on()).override_failure_message("a new career changed the setting").is_false()
	EffectsSetting.set_on(true)
	CareerReset.reset_all()
	assert_bool(EffectsSetting.is_on()).is_true()
	# Loading a career doesn't change it either.
	SaveGame.save()
	EffectsSetting.set_on(false, false)
	var result := SaveGame.read()
	assert_object(result).is_not_null()
	assert_bool(EffectsSetting.is_on()).is_false()

# --- the guard --------------------------------------------------------------------------------------

func test_the_real_settings_file_is_refused_outside_the_real_game_flow() -> void:
	assert_bool(SaveGame.real_save_allowed).is_false()
	var real_before := FileAccess.file_exists(EffectsSetting.REAL_PATH)
	var bytes_before := FileAccess.get_file_as_bytes(EffectsSetting.REAL_PATH) if real_before else PackedByteArray()
	EffectsSetting.path = EffectsSetting.REAL_PATH
	assert_bool(EffectsSetting.save()).override_failure_message("wrote the real settings file").is_false()
	EffectsSetting.set_on(false)
	assert_bool(EffectsSetting.is_on()).is_false()
	# Nothing was written, or changed.
	assert_bool(FileAccess.file_exists(EffectsSetting.REAL_PATH)).is_equal(real_before)
	if real_before:
		assert_array(FileAccess.get_file_as_bytes(EffectsSetting.REAL_PATH)).is_equal(bytes_before)
	use_test_settings(false)

func test_another_spelling_of_the_real_file_is_still_real() -> void:
	assert_bool(EffectsSetting.is_real_file(EffectsSetting.REAL_PATH)).is_true()
	assert_bool(EffectsSetting.is_real_file("user://./settings.cfg")).is_true()
	assert_bool(EffectsSetting.is_real_file(ProjectSettings.globalize_path(EffectsSetting.REAL_PATH))).is_true()
	assert_bool(EffectsSetting.is_real_file("user://scratch_shots_settings.cfg")).is_false()
	assert_bool(EffectsSetting.is_real_file(TEST_SETTINGS_PATH)).is_false()

func test_the_real_game_flow_may_write_the_real_file() -> void:
	# Only asks the guard: nothing is written to the real file here.
	EffectsSetting.path = EffectsSetting.REAL_PATH
	assert_bool(EffectsSetting._may_write()).is_false()
	SaveGame.real_save_allowed = true
	assert_bool(EffectsSetting._may_write()).is_true()
	SaveGame.real_save_allowed = false
	use_test_settings(false)

func test_a_scratch_or_test_file_may_always_be_written() -> void:
	EffectsSetting.use_file("user://scratch_shots_settings.cfg")
	assert_bool(EffectsSetting._may_write()).is_true()
	assert_bool(SaveGame.real_save_allowed).is_false()
	use_test_settings(false)

# --- the pause menu's button -------------------------------------------------------------------------

func test_the_pause_menu_toggles_the_setting_and_keeps_it() -> void:
	var menu := room.pause_menu
	EffectsSetting.set_on(true, false)
	menu.open()
	assert_str(menu.effects_button.text).is_equal("Effects: On")
	menu.effects_button.pressed.emit()
	assert_str(menu.effects_button.text).is_equal("Effects: Off")
	assert_bool(EffectsSetting.is_on()).is_false()
	# Kept in the settings file (the test one here).
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	assert_bool(EffectsSetting.is_on()).is_false()
	menu.resume()
	menu.open()
	assert_str(menu.effects_button.text).is_equal("Effects: Off")
	menu.effects_button.pressed.emit()
	assert_str(menu.effects_button.text).is_equal("Effects: On")
	assert_bool(EffectsSetting.is_on()).is_true()
	menu.resume()

func test_the_pause_menu_still_fits_with_its_new_button() -> void:
	var menu := room.pause_menu
	menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	# Measured by its own size (the headless window is taller than the game's):
	# inside the 1152x648 window with the usual margin to spare, and every
	# button inside the panel.
	var panel := menu.menu_panel
	assert_float(panel.size.y).is_less_equal(648.0 - 2.0 * WINDOW_MARGIN)
	assert_float(panel.size.x).is_less_equal(1152.0 - 2.0 * WINDOW_MARGIN)
	for button: Button in [menu.resume_button, menu.effects_button, menu.main_menu_button]:
		assert_bool(button.visible).is_true()
		assert_bool(panel.get_global_rect().encloses(button.get_global_rect())).override_failure_message("%s is outside the panel" % button.text).is_true()
	menu.resume()
