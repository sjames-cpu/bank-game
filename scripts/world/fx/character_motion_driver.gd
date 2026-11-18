extends Node
class_name CharacterMotionDriver

## The one place time passes for the world's small motions: every
## CharacterMotion is stepped here, in one pass, from one shared clock, and
## so are the speech lines' pop-ins (WorldText.pop()). No tween per
## character and nothing allocated per frame.
##
## Not an autoload. The characters register themselves in a static list; a
## driver node is added under the scene tree's root when the first one
## registers and frees itself when the last one is gone. It is a normal
## (pausable) node, so while a desk screen, the pause menu or a letter has
## the tree paused, the motion holds exactly where it is.
##
## advance() does the work and is also what tests call to step time by hand.

## Every character with motion, in the tree now.
static var motions: Array[CharacterMotion] = []

## The shared clock, in seconds of unpaused game time.
static var clock: float = 0.0

## Speech lines popping in right now (WorldText).
static var popping: Array[Label] = []

static var _driver: CharacterMotionDriver = null

static func register(motion: CharacterMotion) -> void:
	motions.append(motion)
	_ensure_driver(motion.get_tree())

static func unregister(motion: CharacterMotion) -> void:
	motions.erase(motion)

static func _ensure_driver(tree: SceneTree) -> void:
	if is_instance_valid(_driver):
		return
	_driver = CharacterMotionDriver.new()
	_driver.name = "CharacterMotionDriver"
	# The tree is often in the middle of adding nodes: wait a moment.
	tree.root.add_child.call_deferred(_driver)

## Whether a driver exists (tests: nothing is left behind once the last
## character is gone).
static func has_driver() -> bool:
	return is_instance_valid(_driver)

## Steps every character and every pop by `delta` seconds, in one pass.
static func advance(delta: float) -> void:
	clock += delta
	var effects_on := EffectsSetting.is_on()
	for motion in motions:
		motion.step(clock, delta, effects_on)
	var i := popping.size() - 1
	while i >= 0:
		var label := popping[i]
		if not is_instance_valid(label) or WorldText.step_pop(label, delta, effects_on):
			popping.remove_at(i)
		i -= 1

## Effects were just turned off: stop everything that moves now, without
## waiting for the next step (the pause menu has the tree paused).
static func apply_setting() -> void:
	if EffectsSetting.is_on():
		return
	for motion in motions:
		motion.stop()
	for label in popping:
		if is_instance_valid(label):
			WorldText.finish_pop(label)
	popping.clear()

func _process(delta: float) -> void:
	if motions.is_empty() and popping.is_empty():
		# Nobody left to move: go (a new character brings a new driver).
		_driver = null
		queue_free()
		return
	advance(delta)

func _exit_tree() -> void:
	if _driver == self:
		_driver = null
