extends "res://tests/support/teller_room_suite.gd"

## The shared cutscene player (Cutscenes) in the room: steps play in order,
## the game is paused and the current slot held while a scene plays, a choice
## comes back in the result, and Esc asks "Skip this scene?" (Yes skips with
## every choice at its default, No carries on, the scene waiting meanwhile).

const DUMMY := "res://tests/data/cutscenes/dummy.json"

## What `finished` gave, once a scene has ended (empty until then).
var result: Dictionary = {}
## Each step's type as it started.
var started: Array[String] = []

func after_test() -> void:
	Cutscenes.stop()
	if Cutscenes.finished.is_connected(_on_finished):
		Cutscenes.finished.disconnect(_on_finished)
	if Cutscenes.step_started.is_connected(_on_step_started):
		Cutscenes.step_started.disconnect(_on_step_started)
	await super.after_test()

func _on_finished(scene_result: Dictionary) -> void:
	result = scene_result

func _on_step_started(_index: int, type: String) -> void:
	started.append(type)

## Starts `text` (a scene's JSON, or the dummy scene), following it.
func start_scene(text: String = "") -> void:
	result = {}
	started = []
	Cutscenes.finished.connect(_on_finished)
	Cutscenes.step_started.connect(_on_step_started)
	var scene := CutsceneScene.load_file(DUMMY) if text == "" else CutsceneScene.parse(text, "test.json")
	assert_bool(Cutscenes.start(scene)).is_true()

## Frames go by until the scene reaches a step of `type` (or ends, for "").
func run_until(type: String) -> void:
	for i in 600:
		if Cutscenes.current_type() == type:
			return
		await get_tree().process_frame
	fail("the scene never reached a \"%s\" step (on \"%s\")" % [type, Cutscenes.current_type()])

func press_escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_tree().root.push_input(key)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	get_tree().root.push_input(release)

func test_the_steps_play_in_order_and_the_choice_comes_back() -> void:
	start_scene()
	assert_bool(get_tree().paused).is_true()
	assert_str(Cutscenes.current_type()).is_equal("say")
	assert_str(Cutscenes.view.speaker_label.text).is_equal("Walter")
	assert_str(Cutscenes.view.line_label.text).is_equal("Good morning. Ready to open?")
	assert_array(Cutscenes.view.characters.keys()).contains_exactly_in_any_order(["staff_01", "player"])
	Cutscenes.advance()
	await run_until("choice")
	assert_bool(Cutscenes.view.choice_panel.visible).is_true()
	assert_str(Cutscenes.view.option_buttons[1].text).is_equal("Not yet")
	Cutscenes.view.option_buttons[0].pressed.emit()
	await run_until("say")
	assert_float(Cutscenes.view.fade_alpha()).is_equal_approx(0.0, 0.01)
	assert_array(Cutscenes.view.characters.keys()).contains_exactly(["player"])
	assert_str(Cutscenes.view.line_label.text).is_equal("Let's begin.")
	Cutscenes.view.next_button.pressed.emit()
	assert_array(started).is_equal(["show", "show", "say", "wait", "choice", "fade", "fade", "hide", "say"])
	assert_dict(result).is_equal({"skipped": false, "choices": {"ready": 0}})
	assert_bool(Cutscenes.is_playing()).is_false()
	assert_bool(get_tree().paused).is_false()

func test_skipping_returns_every_choice_at_its_default() -> void:
	start_scene()
	Cutscenes.request_skip()
	assert_bool(Cutscenes.view.confirm_panel.visible).is_true()
	assert_str(Cutscenes.view.confirm_label.text).is_equal("Skip this scene?")
	Cutscenes.view.yes_button.pressed.emit()
	assert_dict(result).is_equal({"skipped": true, "choices": {"ready": 1}})
	assert_bool(Cutscenes.is_playing()).is_false()
	assert_object(Cutscenes.view).is_null()
	assert_bool(get_tree().paused).is_false()

func test_skipping_at_a_choice_does_not_get_stuck() -> void:
	start_scene()
	Cutscenes.advance()
	await run_until("choice")
	press_escape()
	assert_bool(Cutscenes.is_confirming_skip()).is_true()
	# The choice can't be answered underneath the question.
	Cutscenes.choose(0)
	assert_str(Cutscenes.current_type()).is_equal("choice")
	Cutscenes.answer_skip(true)
	assert_dict(result).is_equal({"skipped": true, "choices": {"ready": 1}})
	# Another scene can start straight away.
	Cutscenes.finished.disconnect(_on_finished)
	Cutscenes.step_started.disconnect(_on_step_started)
	start_scene()
	assert_bool(Cutscenes.is_playing()).is_true()

func test_escape_asks_first_and_no_carries_on_where_it_was() -> void:
	start_scene()
	press_escape()
	assert_bool(Cutscenes.is_confirming_skip()).is_true()
	assert_bool(Cutscenes.view.no_button.has_focus()).is_true()
	# Enter, Space and clicks don't move the line on while asking.
	Cutscenes.advance()
	assert_str(Cutscenes.current_type()).is_equal("say")
	press_escape() # Esc again is No.
	assert_bool(Cutscenes.is_confirming_skip()).is_false()
	assert_bool(Cutscenes.view.confirm_panel.visible).is_false()
	assert_str(Cutscenes.view.line_label.text).is_equal("Good morning. Ready to open?")
	Cutscenes.request_skip()
	Cutscenes.view.no_button.pressed.emit()
	assert_bool(Cutscenes.is_playing()).is_true()
	assert_dict(result).is_empty()

func test_the_scene_waits_while_asking() -> void:
	start_scene("{\"steps\": [{\"wait\": 0.1}, {\"say\": \"After the wait.\"}]}")
	assert_str(Cutscenes.current_type()).is_equal("wait")
	Cutscenes.request_skip()
	# Twice the wait goes by (a timer would stop: the game is paused).
	var until := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert_str(Cutscenes.current_type()).is_equal("wait")
	assert_bool(get_tree().paused).is_true()
	Cutscenes.answer_skip(false)
	await run_until("say")
	assert_str(Cutscenes.view.line_label.text).is_equal("After the wait.")

func test_the_current_slot_is_held_until_the_scene_ends() -> void:
	start_slots_day()
	assert_str(DayFlow.current_slot().id).is_equal(DaySchedule.OPENING)
	start_scene()
	DayFlow.skip_slot()
	# The skip waits for the scene.
	assert_bool(DayFlow.is_skip_requested()).is_true()
	assert_str(DayFlow.current_slot().id).is_equal(DaySchedule.OPENING)
	assert_bool(DayFlow.is_between_slots()).is_false()
	Cutscenes.stop()
	assert_bool(DayFlow.is_held()).is_false()
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_a_scene_outside_a_day_holds_nothing() -> void:
	DayFlow.reset()
	start_scene()
	Cutscenes.stop()
	assert_bool(result["skipped"]).is_true()
	assert_bool(DayFlow.is_running()).is_false()

func test_a_game_already_paused_stays_paused() -> void:
	get_tree().paused = true
	start_scene()
	Cutscenes.stop()
	assert_bool(get_tree().paused).is_true()

func test_a_broken_scene_plays_nothing() -> void:
	var played := await Cutscenes.play("res://tests/data/cutscenes/nothing_here.json")
	assert_bool(played.has("errors")).is_true()
	assert_bool(Cutscenes.is_playing()).is_false()
	assert_bool(get_tree().paused).is_false()

func test_a_scene_of_instant_steps_returns_at_once() -> void:
	var path := "user://test_instant_cutscene.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"steps\": [{\"show\": \"player\", \"side\": \"left\"}, {\"hide\": \"player\"}]}")
	file.close()
	var played := await Cutscenes.play(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_dict(played).is_equal({"skipped": false, "choices": {}})
	assert_bool(get_tree().paused).is_false()

func test_the_screen_fits_beside_the_hud() -> void:
	start_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	var view := Cutscenes.view
	assert_array(layout_problems(view.dialogue_panel)).is_empty()
	assert_array(controls_line_problems(view.dialogue_panel)).is_empty()
	Cutscenes.advance()
	await run_until("choice")
	await get_tree().process_frame
	assert_array(layout_problems(view.choice_panel)).is_empty()
	assert_array(controls_line_problems(view.choice_panel)).is_empty()
	Cutscenes.request_skip()
	await get_tree().process_frame
	assert_array(layout_problems(view.confirm_panel)).is_empty()
	# The characters stand clear of the HUD column and above the box.
	for character: String in view.characters:
		var sprite: AnimatedSprite2D = view.characters[character]
		var half_width := 8.0 * CutsceneView.CHARACTER_SCALE
		assert_float(sprite.position.x + half_width).is_less(HUD_COLUMN_LEFT)
