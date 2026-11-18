extends RefCounted
class_name CutsceneScene

## A cutscene scene file (JSON) loaded and checked for the shared cutscene
## player (Cutscenes). A scene is an object with a "steps" list; each step is
## an object with exactly one of these step types:
##
##   {"say": "Good morning.", "speaker": "Walter"}   a line (speaker optional)
##   {"show": "staff_01", "side": "left"}            a character steps in
##   {"hide": "staff_01"}                            a character on screen leaves
##   {"fade": "out", "seconds": 0.5}                 to black ("out") or back ("in")
##   {"wait": 0.5}                                   a pause, in seconds
##   {"choice": "answer", "prompt": "Ready?",
##    "options": ["Yes", "Not yet"], "default": 1}   two options; the answer
##                                                   (0 or 1) is returned under
##                                                   "answer", "default" if skipped
##
## Characters are the game's own character art (KNOWN_CHARACTERS). Problems
## are collected in `errors`, each naming the file and the step in plain
## English; a scene with any error isn't played.

const STEP_TYPES: Array[String] = ["say", "show", "hide", "fade", "wait", "choice"]
const SIDES: Array[String] = ["left", "right"]
const FADES: Array[String] = ["in", "out"]
const DEFAULT_FADE_SECONDS: float = 0.5

## Every character a scene may show: the player, the staff looks, the
## Regional Manager, the armored truck's guards and the customer looks.
const KNOWN_CHARACTERS: Array[String] = [
	"player",
	"staff_01", "staff_02", "staff_03", "staff_04", "staff_05",
	"staff_06", "staff_07", "staff_08", "staff_09", "staff_10",
	"regional_manager", "guard_1", "guard_2",
	"customer_a", "customer_a2", "customer_a3", "customer_a4",
	"customer_b", "customer_b2", "customer_b3", "customer_b4",
	"customer_c", "customer_c2", "customer_c3", "customer_c4",
]

## Where the scene came from (named in every error).
var path: String = ""
## The checked steps, each with its "type" added.
var steps: Array[Dictionary] = []
var errors: PackedStringArray = []

## The scene in `file_path`, checked.
static func load_file(file_path: String) -> CutsceneScene:
	if not FileAccess.file_exists(file_path):
		var missing := CutsceneScene.new()
		missing.path = file_path
		missing._error("the file doesn't exist")
		return missing
	return parse(FileAccess.get_file_as_string(file_path), file_path)

## A scene from JSON `text` (named `file_path` in errors), checked.
static func parse(text: String, file_path: String) -> CutsceneScene:
	var scene := CutsceneScene.new()
	scene.path = file_path
	var json := JSON.new()
	if json.parse(text) != OK:
		scene._error("isn't valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
		return scene
	scene._check(json.data)
	return scene

## The character art for `character` (one of KNOWN_CHARACTERS).
static func frames_for(character: String) -> SpriteFrames:
	return load("res://assets/sprites/%s_frames.tres" % character) as SpriteFrames

func is_valid() -> bool:
	return errors.is_empty()

## The choice keys in the scene, with their defaults: what a skip returns
## for choices not yet answered.
func choice_defaults() -> Dictionary:
	var defaults := {}
	for step in steps:
		if step["type"] == "choice":
			defaults[step["choice"]] = step["default"]
	return defaults

func _error(message: String, step: int = -1) -> void:
	var where := "" if step < 0 else "step %d: " % (step + 1)
	errors.append("%s: %s%s" % [path, where, message])

func _check(data: Variant) -> void:
	if not data is Dictionary:
		_error("must be an object with a \"steps\" list")
		return
	var root: Dictionary = data
	var list: Variant = root.get("steps")
	if not list is Array:
		_error("needs a \"steps\" list")
		return
	var raw_steps: Array = list
	if raw_steps.is_empty():
		_error("its \"steps\" list is empty")
		return
	var on_screen: Array[String] = []
	var choice_keys: Array[String] = []
	for i in raw_steps.size():
		var raw: Variant = raw_steps[i]
		if not raw is Dictionary:
			_error("must be an object, like {\"say\": \"...\"}", i)
			continue
		var step: Dictionary = raw
		var types: Array[String] = []
		for type in STEP_TYPES:
			if step.has(type):
				types.append(type)
		if types.is_empty():
			_error("unknown step type (keys: %s); use one of %s" % [", ".join(PackedStringArray(step.keys())), ", ".join(PackedStringArray(STEP_TYPES))], i)
			continue
		if types.size() > 1:
			_error("has more than one step type (%s); use one per step" % ", ".join(PackedStringArray(types)), i)
			continue
		var checked := step.duplicate(true)
		checked["type"] = types[0]
		if _check_step(types[0], checked, i, on_screen, choice_keys):
			steps.append(checked)

## Checks one step (adding defaults); false if it has a problem.
func _check_step(type: String, step: Dictionary, i: int, on_screen: Array[String], choice_keys: Array[String]) -> bool:
	match type:
		"say":
			if not _is_text(step.get("say")):
				_error("\"say\" needs the line's text", i)
				return false
			if step.has("speaker") and not step.get("speaker") is String:
				_error("\"speaker\" must be text", i)
				return false
		"show":
			var character: Variant = step.get("show")
			if not character is String or not KNOWN_CHARACTERS.has(character):
				_error("unknown character \"%s\"; use one of %s" % [str(character), ", ".join(PackedStringArray(KNOWN_CHARACTERS))], i)
				return false
			var side: Variant = step.get("side")
			if not side is String or not SIDES.has(side):
				_error("\"show\" needs \"side\": \"left\" or \"right\"", i)
				return false
			var shown: String = character
			if on_screen.has(shown):
				_error("shows \"%s\", who is already on screen" % shown, i)
				return false
			on_screen.append(shown)
		"hide":
			var character: Variant = step.get("hide")
			if not character is String or not on_screen.has(character):
				_error("hides \"%s\", who isn't on screen" % str(character), i)
				return false
			var hidden: String = character
			on_screen.erase(hidden)
		"fade":
			var direction: Variant = step.get("fade")
			if not direction is String or not FADES.has(direction):
				_error("\"fade\" must be \"in\" or \"out\"", i)
				return false
			if step.has("seconds") and not _is_seconds(step.get("seconds")):
				_error("\"seconds\" must be a number of seconds", i)
				return false
			step["seconds"] = _number(step.get("seconds", DEFAULT_FADE_SECONDS))
		"wait":
			if not _is_seconds(step.get("wait")) or _number(step.get("wait")) <= 0.0:
				_error("\"wait\" must be a number of seconds above 0", i)
				return false
			step["wait"] = _number(step.get("wait"))
		"choice":
			if not _is_text(step.get("choice")):
				_error("\"choice\" needs a name for its answer", i)
				return false
			var key: String = step.get("choice")
			if choice_keys.has(key):
				_error("the choice name \"%s\" is used twice" % key, i)
				return false
			if not _is_text(step.get("prompt")):
				_error("the choice needs a \"prompt\"", i)
				return false
			var options_value: Variant = step.get("options")
			var options: Array = options_value if options_value is Array else []
			if options.size() != 2 or not _is_text(options[0]) or not _is_text(options[1]):
				_error("the choice needs \"options\": a list of exactly 2 texts", i)
				return false
			var default: Variant = step.get("default")
			var picked := _number(default)
			if picked != 0.0 and picked != 1.0:
				_error("the choice needs a valid \"default\": 0 or 1 (the option a skip picks)", i)
				return false
			step["default"] = 0 if picked == 0.0 else 1
			choice_keys.append(key)
	return true

static func _is_text(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	return text.strip_edges() != ""

static func _is_seconds(value: Variant) -> bool:
	return _number(value) >= 0.0

## `value` as a number, or -1 if it isn't one (JSON numbers come back as
## floats; tests may hand in ints).
static func _number(value: Variant) -> float:
	if value is int:
		var whole: int = value
		return whole
	if value is float:
		var real: float = value
		return real
	return -1.0
