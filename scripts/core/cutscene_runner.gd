extends Node

## Autoload singleton (Cutscenes): the one shared cutscene player every role
## uses (ROLE_BOUNDARIES.md). A role keeps its scene files under
## scenes/cutscenes/<role>/ (format: CutsceneScene) and plays one with
##
##   var result := await Cutscenes.play("res://scenes/cutscenes/teller/opening.json")
##
## and gets back {"skipped": bool, "choices": {name: 0 or 1}} (plus "errors"
## if the scene didn't pass its check, when nothing is shown). What happens
## next is the role's to decide (for example DayFlow.skip_slot()).
##
## While a scene plays:
## - the game is paused, like any screen (customers' patience and the
##   timers stop), and the player's screen is drawn above everything;
## - the current slot is held (DayFlow.hold(HOLD_REASON)), released at the
##   end, so the day can't move on underneath it;
## - Enter, Space or a click moves on from a line; a choice waits for one of
##   its two buttons;
## - Esc (SKIP_ACTION) or the Skip button asks "Skip this scene?" (the scene
##   stays paused while asking): Yes ends it at once, every choice not yet
##   answered taking its default; No carries on where it was.
## Characters stand still on the cutscene screen (walking isn't supported in
## version 1).

signal finished(result: Dictionary)
## Each step as it starts (tests, and anything that wants to follow along).
signal step_started(index: int, type: String)

const HOLD_REASON: StringName = &"cutscene"
const SKIP_ACTION: StringName = &"skip_cutscene"
const SKIP_CONFIRM_TEXT: String = "Skip this scene?"

## The view (a CanvasLayer built in code) and where it stands now.
var view: CutsceneView = null
var _scene: CutsceneScene = null
var _index: int = -1
var _choices: Dictionary = {}
var _paused_by_self: bool = false
var _holding: bool = false
## Seconds left in a "wait" or "fade" step (-1 when not timing one).
var _time_left: float = -1.0
var _fade_from: float = 0.0
var _fade_to: float = 0.0
var _fade_seconds: float = 0.0
var _confirming: bool = false
## The result of the last scene that finished (what finished gave).
var last_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_playing() -> bool:
	return _scene != null

## Plays the scene in `path` and returns its result (see the class doc).
func play(path: String) -> Dictionary:
	var scene := CutsceneScene.load_file(path)
	if not scene.is_valid():
		for error in scene.errors:
			push_warning("Cutscene not played: %s" % error)
		return {"skipped": false, "choices": {}, "errors": scene.errors}
	if not start(scene):
		return {"skipped": false, "choices": {}, "errors": PackedStringArray(["another cutscene is playing"])}
	# A scene of instant steps only (show, hide, a 0-second fade) has already
	# finished.
	if not is_playing():
		return last_result
	var result: Dictionary = await finished
	return result

## Starts a checked scene without waiting for it (finished gives the
## result). False if it can't start: not valid, or one is already playing.
func start(scene: CutsceneScene) -> bool:
	if is_playing() or not scene.is_valid():
		return false
	_scene = scene
	_choices = {}
	_confirming = false
	_paused_by_self = not get_tree().paused
	get_tree().paused = true
	_holding = DayFlow.is_running() and DayFlow.hold(HOLD_REASON)
	view = CutsceneView.new()
	view.name = "CutsceneView"
	add_child(view)
	view.next_pressed.connect(advance)
	view.option_chosen.connect(choose)
	view.skip_pressed.connect(request_skip)
	view.skip_answered.connect(answer_skip)
	_index = -1
	_next_step()
	return true

## The step on screen now (-1 when nothing plays).
func current_index() -> int:
	return _index if is_playing() else -1

func current_type() -> String:
	if not is_playing() or _index < 0 or _index >= _scene.steps.size():
		return ""
	return str(_scene.steps[_index]["type"])

## Moves on from the line on screen (Enter, Space, a click, the Next button).
func advance() -> void:
	if is_playing() and not _confirming and current_type() == "say":
		_next_step()

## Answers the choice on screen with option `option` (0 or 1).
func choose(option: int) -> void:
	if not is_playing() or _confirming or current_type() != "choice":
		return
	_choices[_scene.steps[_index]["choice"]] = clampi(option, 0, 1)
	_next_step()

## Esc or Skip: asks "Skip this scene?" (the scene waits meanwhile).
func request_skip() -> void:
	if is_playing() and not _confirming:
		_confirming = true
		view.show_skip_confirm(SKIP_CONFIRM_TEXT)

## The answer to "Skip this scene?": Yes ends it, No carries on.
func answer_skip(yes: bool) -> void:
	if not is_playing() or not _confirming:
		return
	_confirming = false
	view.hide_skip_confirm()
	if yes:
		_finish(true)

func is_confirming_skip() -> bool:
	return _confirming

## Ends the scene at once, without asking, as a skip (nothing if none plays).
func stop() -> void:
	if is_playing():
		_finish(true)

func _input(event: InputEvent) -> void:
	if not is_playing():
		return
	if event.is_action_pressed(SKIP_ACTION) and not event.is_echo():
		if _confirming:
			answer_skip(false)
		else:
			request_skip()
		get_viewport().set_input_as_handled()
	elif not _confirming and current_type() == "say" and (event.is_action_pressed(&"ui_accept") or _is_click(event)):
		advance()
		get_viewport().set_input_as_handled()

static func _is_click(event: InputEvent) -> bool:
	var mouse := event as InputEventMouseButton
	return mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT

func _process(delta: float) -> void:
	if not is_playing() or _confirming or _time_left < 0.0:
		return
	_time_left -= delta
	if current_type() == "fade":
		var done := 1.0 if _fade_seconds <= 0.0 else clampf(1.0 - _time_left / _fade_seconds, 0.0, 1.0)
		view.set_fade(lerpf(_fade_from, _fade_to, done))
	if _time_left <= 0.0:
		_time_left = -1.0
		_next_step()

func _next_step() -> void:
	_index += 1
	if _index >= _scene.steps.size():
		_finish(false)
		return
	var step := _scene.steps[_index]
	var type: String = step["type"]
	step_started.emit(_index, type)
	match type:
		"say":
			view.show_line(str(step.get("speaker", "")), str(step["say"]))
		"show":
			view.show_character(str(step["show"]), str(step["side"]))
			_next_step()
		"hide":
			view.hide_character(str(step["hide"]))
			_next_step()
		"fade":
			view.hide_dialogue()
			_fade_seconds = step["seconds"]
			_fade_from = view.fade_alpha()
			_fade_to = 1.0 if step["fade"] == "out" else 0.0
			_time_left = _fade_seconds
			if _fade_seconds <= 0.0:
				view.set_fade(_fade_to)
				_time_left = -1.0
				_next_step()
		"wait":
			view.hide_dialogue()
			_time_left = step["wait"]
		"choice":
			var options: Array = step["options"]
			view.show_choice(str(step["prompt"]), str(options[0]), str(options[1]))

func _finish(skipped: bool) -> void:
	var result_choices := _scene.choice_defaults()
	result_choices.merge(_choices, true)
	var result := {"skipped": skipped, "choices": result_choices}
	_scene = null
	_index = -1
	_time_left = -1.0
	_confirming = false
	if is_instance_valid(view):
		view.queue_free()
	view = null
	if _holding:
		_holding = false
		if DayFlow.is_running():
			DayFlow.release(HOLD_REASON)
	if _paused_by_self:
		_paused_by_self = false
		get_tree().paused = false
	last_result = result
	finished.emit(result)
