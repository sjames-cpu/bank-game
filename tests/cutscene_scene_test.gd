extends GdUnitTestSuite

## The cutscene checker (CutsceneScene): every scene file in the game passes
## it, and a broken scene is caught with a plain-English message naming the
## file and the step.

const SCENES_DIR := "res://scenes/cutscenes"
const DUMMY := "res://tests/data/cutscenes/dummy.json"

## Every .json file under `dir`, in its subfolders too.
func json_files_under(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "json":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(json_files_under(dir.path_join(sub)))
	return found

## Passes with no scene files yet: each one found must check out.
func test_every_scene_file_in_the_game_checks_out() -> void:
	var files := json_files_under(SCENES_DIR)
	files.append(DUMMY)
	var problems: PackedStringArray = []
	for file in files:
		problems.append_array(CutsceneScene.load_file(file).errors)
	assert_array(Array(problems)).override_failure_message(
		"These cutscene files have problems:\n" + "\n".join(problems)).is_empty()

func test_the_dummy_scene_reads_as_written() -> void:
	var scene := CutsceneScene.load_file(DUMMY)
	assert_bool(scene.is_valid()).is_true()
	var types: Array[String] = []
	for step in scene.steps:
		types.append(str(step["type"]))
	assert_array(types).is_equal(["show", "show", "say", "wait", "choice", "fade", "fade", "hide", "say"])
	assert_dict(scene.choice_defaults()).is_equal({"ready": 1})

## The one error `text` gives (as scene "x.json").
func error_of(text: String) -> String:
	var scene := CutsceneScene.parse(text, "x.json")
	assert_int(scene.errors.size()).override_failure_message("expected one error, got: %s" % ", ".join(scene.errors)).is_equal(1)
	return scene.errors[0] if not scene.errors.is_empty() else ""

func test_bad_json_names_the_file() -> void:
	assert_str(error_of("{\"steps\": [")).starts_with("x.json: isn't valid JSON (line ")

func test_a_scene_needs_a_steps_list() -> void:
	assert_str(error_of("[1, 2]")).is_equal("x.json: must be an object with a \"steps\" list")
	assert_str(error_of("{\"lines\": []}")).is_equal("x.json: needs a \"steps\" list")
	assert_str(error_of("{\"steps\": []}")).is_equal("x.json: its \"steps\" list is empty")

func test_an_unknown_step_type_names_the_step() -> void:
	assert_str(error_of("{\"steps\": [{\"say\": \"Hi\"}, {\"dance\": true}]}")) \
		.is_equal("x.json: step 2: unknown step type (keys: dance); use one of say, show, hide, fade, wait, choice")

func test_an_unknown_character_names_the_step() -> void:
	assert_str(error_of("{\"steps\": [{\"show\": \"staff_11\", \"side\": \"left\"}]}")) \
		.starts_with("x.json: step 1: unknown character \"staff_11\"; use one of player, staff_01")

func test_a_choice_needs_a_valid_default() -> void:
	var expected := "x.json: step 1: the choice needs a valid \"default\": 0 or 1 (the option a skip picks)"
	var choice := "{\"steps\": [{\"choice\": \"a\", \"prompt\": \"Ready?\", \"options\": [\"Yes\", \"No\"]%s}]}"
	assert_str(error_of(choice % "")).is_equal(expected)
	assert_str(error_of(choice % ", \"default\": 2")).is_equal(expected)
	assert_str(error_of(choice % ", \"default\": \"Yes\"")).is_equal(expected)
	assert_bool(CutsceneScene.parse(choice % ", \"default\": 1", "x.json").is_valid()).is_true()

func test_missing_fields_are_named() -> void:
	assert_str(error_of("{\"steps\": [{\"say\": \"\"}]}")).is_equal("x.json: step 1: \"say\" needs the line's text")
	assert_str(error_of("{\"steps\": [{\"show\": \"player\"}]}")).is_equal("x.json: step 1: \"show\" needs \"side\": \"left\" or \"right\"")
	assert_str(error_of("{\"steps\": [{\"choice\": \"a\", \"options\": [\"Yes\", \"No\"], \"default\": 0}]}")) \
		.is_equal("x.json: step 1: the choice needs a \"prompt\"")
	assert_str(error_of("{\"steps\": [{\"choice\": \"a\", \"prompt\": \"?\", \"options\": [\"Yes\"], \"default\": 0}]}")) \
		.is_equal("x.json: step 1: the choice needs \"options\": a list of exactly 2 texts")
	assert_str(error_of("{\"steps\": [{\"wait\": 0}]}")).is_equal("x.json: step 1: \"wait\" must be a number of seconds above 0")
	assert_str(error_of("{\"steps\": [{\"fade\": \"sideways\"}]}")).is_equal("x.json: step 1: \"fade\" must be \"in\" or \"out\"")

func test_who_is_on_screen_is_followed() -> void:
	assert_str(error_of("{\"steps\": [{\"hide\": \"player\"}]}")).is_equal("x.json: step 1: hides \"player\", who isn't on screen")
	assert_str(error_of("{\"steps\": [{\"show\": \"player\", \"side\": \"left\"}, {\"show\": \"player\", \"side\": \"right\"}]}")) \
		.is_equal("x.json: step 2: shows \"player\", who is already on screen")

func test_one_type_per_step_and_unique_choice_names() -> void:
	assert_str(error_of("{\"steps\": [{\"say\": \"Hi\", \"wait\": 1}]}")) \
		.is_equal("x.json: step 1: has more than one step type (say, wait); use one per step")
	var choice := "{\"choice\": \"a\", \"prompt\": \"?\", \"options\": [\"Yes\", \"No\"], \"default\": 0}"
	assert_str(error_of("{\"steps\": [%s, %s]}" % [choice, choice])).is_equal("x.json: step 2: the choice name \"a\" is used twice")

func test_a_missing_file_says_so() -> void:
	var scene := CutsceneScene.load_file("res://tests/data/cutscenes/nothing_here.json")
	assert_array(Array(scene.errors)).is_equal(["res://tests/data/cutscenes/nothing_here.json: the file doesn't exist"])

func test_every_problem_in_a_scene_is_listed() -> void:
	var scene := CutsceneScene.parse("{\"steps\": [{\"say\": \"Hi\"}, {\"show\": \"nobody\", \"side\": \"left\"}, {\"wait\": -1}]}", "x.json")
	assert_int(scene.errors.size()).is_equal(2)
	assert_str(scene.errors[0]).starts_with("x.json: step 2: ")
	assert_str(scene.errors[1]).starts_with("x.json: step 3: ")
