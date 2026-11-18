extends GdUnitTestSuite

## The reserved debug keys (DebugKeys): each is in the input map on its key,
## and no key is bound to two things, except Esc, which the pause menu and
## the cutscene player share on purpose (a cutscene pauses the game, which
## keeps the pause menu shut).

func keycodes_of(action: StringName) -> Array[int]:
	var found: Array[int] = []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			found.append(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return found

func test_each_reserved_key_is_in_the_input_map() -> void:
	for action: StringName in DebugKeys.RESERVED:
		assert_bool(InputMap.has_action(action)).override_failure_message("%s isn't in the input map" % action).is_true()
		assert_array(keycodes_of(action)).is_equal([DebugKeys.RESERVED[action]])

func test_no_key_does_two_things() -> void:
	# The room reads F1 and F2 as keys, not actions.
	var taken := {KEY_F1: "F1 (debug unlock)", KEY_F2: "F2 (debug Loan Officer)"}
	var clashes: Array[String] = []
	for action in InputMap.get_actions():
		# Godot's own ui_ actions, and Esc's second, intended use.
		if str(action).begins_with("ui_") or action == Cutscenes.SKIP_ACTION:
			continue
		for keycode in keycodes_of(action):
			if taken.has(keycode):
				clashes.append("%s and %s both use %s" % [taken[keycode], action, OS.get_keycode_string(keycode)])
			taken[keycode] = str(action)
	assert_array(clashes).is_empty()

func test_escape_is_shared_only_by_the_pause_menu_and_cutscenes() -> void:
	assert_array(keycodes_of(&"pause_menu")).is_equal([KEY_ESCAPE])
	assert_array(keycodes_of(Cutscenes.SKIP_ACTION)).is_equal([KEY_ESCAPE])
