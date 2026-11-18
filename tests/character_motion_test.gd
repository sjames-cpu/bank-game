extends "res://tests/support/shared/character_fx_suite.gd"

## The characters' small motion (CharacterMotion, stepped by
## CharacterMotionDriver): breathing while they stand, a dip when they stop, a
## faster rhythm while staff serve. These measure what is drawn at every point
## of the cycles, as character_fx_look_test.gd does: the outline stays exactly
## four 1 px copies, the sprite and its outline move together by whole art
## pixels, the shadow never moves, and nothing draws outside a 1 px outline
## plus the foot oval, for the player, a customer, a staff member, an
## applicant, a guard and the Regional Manager, at both zooms. Tests run with
## Effects Off by default (the shared test base); these turn them on.

const STEP: float = 0.02

func effects_on() -> void:
	use_test_settings(true)

## Lets every character finish any settling from being placed (a character put
## in place counts as having moved), so the cycles start from rest.
func warm_up() -> void:
	for i in roundi(0.4 / STEP):
		CharacterMotionDriver.advance(STEP)

## Steps the shared clock by hand, `seconds` long in STEP steps, checking every
## character at every step. Returns what went wrong; `seen` collects each
## character's offsets by kind.
func run_cycle(characters: Dictionary[String, Node2D], seconds: float, label: String, seen: Dictionary[String, Array]) -> Array[String]:
	var problems: Array[String] = []
	var steps := roundi(seconds / STEP)
	for i in steps:
		CharacterMotionDriver.advance(STEP)
		for kind in characters:
			var offset := motion_of(characters[kind]).offset_y
			if not seen.has(kind):
				seen[kind] = []
			seen[kind].append(offset)
			problems.append_array(motion_problems(characters[kind], "%s %s at t=%.2f" % [kind, label, CharacterMotionDriver.clock]))
	return problems

# --- idle, settle and serving cycles, every character, both zooms ---------------------------------

func test_idle_breathing_stays_crisp_for_every_character_at_both_zooms() -> void:
	effects_on()
	var characters := every_character_type()
	warm_up()
	var problems: Array[String] = []
	var seen: Dictionary[String, Array] = {}
	for overview: bool in [false, true]:
		zoom_to(overview)
		# Two full breathing cycles.
		problems.append_array(run_cycle(characters, CharacterMotion.BREATH_PERIOD * 2.0, "idle at %s" % ("1x" if overview else "2x"), seen))
	zoom_to(false)
	assert_no_problems(problems)
	for kind in characters:
		var offsets: Array = seen[kind]
		assert_bool(offsets.has(-1)).override_failure_message("%s never rose a pixel" % kind).is_true()
		assert_bool(offsets.has(0)).override_failure_message("%s never rested" % kind).is_true()
		for offset: int in offsets:
			assert_bool(offset == -1 or offset == 0).override_failure_message("%s moved %d while idle" % [kind, offset]).is_true()

func test_a_step_lasts_about_one_point_two_seconds() -> void:
	effects_on()
	var player := room.player
	var motion := motion_of(player)
	warm_up()
	var changes: Array[float] = []
	var last := motion.offset_y
	for i in roundi(CharacterMotion.BREATH_PERIOD * 3.0 / STEP):
		CharacterMotionDriver.advance(STEP)
		if motion.offset_y != last:
			changes.append(CharacterMotionDriver.clock)
			last = motion.offset_y
	assert_int(changes.size()).is_greater_equal(4)
	for i in range(1, changes.size()):
		assert_float(changes[i] - changes[i - 1]).is_between(CharacterMotion.BREATH_STEP_SECONDS - 0.05, CharacterMotion.BREATH_STEP_SECONDS + 0.05)

func test_settling_when_a_character_stops_is_a_brief_one_pixel_dip() -> void:
	effects_on()
	var characters := every_character_type()
	var problems: Array[String] = []
	for kind in characters:
		var character := characters[kind]
		var motion := motion_of(character)
		# It walks (its place changes each step), then stands.
		for i in 5:
			character.global_position += Vector2(3.0, 0.0)
			CharacterMotionDriver.advance(STEP)
			problems.append_array(motion_problems(character, "%s walking" % kind))
			assert_int(motion.offset_y).override_failure_message("%s bobbed while walking" % kind).is_equal(0)
		var dips := 0
		var dip_seconds := 0.0
		for i in roundi(0.5 / STEP):
			CharacterMotionDriver.advance(STEP)
			problems.append_array(motion_problems(character, "%s settling t=%d" % [kind, i]))
			if motion.offset_y == 1:
				dips += 1
				dip_seconds += STEP
		assert_int(dips).override_failure_message("%s never settled" % kind).is_greater(0)
		assert_float(dip_seconds).override_failure_message("%s's dip lasted %.2f s" % [kind, dip_seconds]).is_between(CharacterMotion.SETTLE_SECONDS - 0.05, CharacterMotion.SETTLE_SECONDS + 0.06)
	assert_no_problems(problems)

func test_staff_serving_move_in_a_faster_rhythm_and_rest_when_not_serving() -> void:
	effects_on()
	var line := room.window1_npc_line
	var staff: StaffNPC = line.staff_npc
	var customer := (load("res://scenes/characters/customer_npc.tscn") as PackedScene).instantiate() as CustomerNPC
	assert_bool(staff.is_working()).is_false()
	warm_up()
	var idle_changes := count_changes(staff, CharacterMotion.BREATH_PERIOD * 2.0)
	line._serving = customer
	assert_bool(staff.is_working()).is_true()
	var problems: Array[String] = []
	var working_changes := 0
	var last := motion_of(staff).offset_y
	for i in roundi(CharacterMotion.BREATH_PERIOD * 2.0 / STEP):
		CharacterMotionDriver.advance(STEP)
		problems.append_array(motion_problems(staff, "serving staff"))
		if motion_of(staff).offset_y != last:
			working_changes += 1
			last = motion_of(staff).offset_y
	line._serving = null
	customer.free()
	assert_no_problems(problems)
	# About 5 times as fast.
	assert_int(working_changes).is_greater(idle_changes * 3)
	assert_bool(staff.is_working()).is_false()

## How many times `character`'s move changes over `seconds`.
func count_changes(character: Node2D, seconds: float) -> int:
	var changes := 0
	var last := motion_of(character).offset_y
	for i in roundi(seconds / STEP):
		CharacterMotionDriver.advance(STEP)
		if motion_of(character).offset_y != last:
			changes += 1
			last = motion_of(character).offset_y
	return changes

func test_a_loan_desk_worker_with_an_applicant_seated_is_working() -> void:
	effects_on()
	var worker: NpcLoanDeskWorker = room.loan_desk_workers[1]
	var staff := worker.staff_npc
	assert_object(staff).is_not_null()
	assert_object(staff.work_source).is_same(worker)
	assert_bool(staff.is_working()).is_false()
	var seat := worker.seat
	var phase_before := seat.phase
	seat.phase = LoanDeskSeat.Phase.SEATED
	assert_bool(staff.is_working()).is_true()
	seat.phase = phase_before
	assert_bool(staff.is_working()).is_false()

func test_staff_away_from_their_desk_are_not_working() -> void:
	effects_on()
	var line := room.window1_npc_line
	var staff: StaffNPC = line.staff_npc
	var customer := (load("res://scenes/characters/customer_npc.tscn") as PackedScene).instantiate() as CustomerNPC
	line._serving = customer
	staff.state = StaffNPC.State.ON_BREAK
	assert_bool(staff.is_working()).is_false()
	staff.state = StaffNPC.State.AT_DESK
	line._serving = null
	customer.free()

# --- phases -------------------------------------------------------------------------------------

func test_every_character_has_its_own_phase_so_a_crowd_never_moves_in_lockstep() -> void:
	effects_on()
	var characters := every_character_type()
	var phases: Array[float] = []
	for kind in characters:
		phases.append(motion_of(characters[kind]).phase)
	for i in phases.size():
		for j in range(i + 1, phases.size()):
			var gap := absf(phases[i] - phases[j])
			gap = minf(gap, CharacterMotion.BREATH_PERIOD - gap)
			assert_float(gap).override_failure_message("two characters share a phase (%s and %s)" % [phases[i], phases[j]]).is_greater(0.05)
	# And so at some moment they are not all in the same position.
	var disagreed := false
	for i in roundi(CharacterMotion.BREATH_PERIOD / STEP):
		CharacterMotionDriver.advance(STEP)
		var first := motion_of(characters["player"]).offset_y
		for kind in characters:
			if motion_of(characters[kind]).offset_y != first:
				disagreed = true
	assert_bool(disagreed).is_true()

# --- Effects Off ---------------------------------------------------------------------------------

func test_with_effects_off_nothing_moves() -> void:
	use_test_settings(false)
	var characters := every_character_type()
	warm_up()
	var problems: Array[String] = []
	var seen: Dictionary[String, Array] = {}
	problems.append_array(run_cycle(characters, CharacterMotion.BREATH_PERIOD * 2.0, "off", seen))
	for kind in characters:
		var character := characters[kind]
		# Even a character that walks and stops doesn't settle.
		for i in 4:
			character.global_position += Vector2(3.0, 0.0)
			CharacterMotionDriver.advance(STEP)
		for i in 10:
			CharacterMotionDriver.advance(STEP)
			assert_int(motion_of(character).offset_y).is_equal(0)
		for offset: int in seen[kind]:
			assert_int(offset).override_failure_message("%s moved with effects off" % kind).is_equal(0)
	assert_no_problems(problems)

func test_turning_effects_off_stops_the_motion_at_once() -> void:
	effects_on()
	var player := room.player
	var motion := motion_of(player)
	var guard := 0
	while motion.offset_y == 0 and guard < 200:
		CharacterMotionDriver.advance(STEP)
		guard += 1
	assert_int(motion.offset_y).is_equal(-1)
	# The pause menu's button: no waiting for the next step.
	EffectsSetting.set_on(false, false)
	assert_int(motion.offset_y).is_equal(0)
	assert_vector(sprite_of(player).position).is_equal(Vector2.ZERO)
	assert_bool(motion_problems(player, "player").is_empty()).is_true()

# --- pausing and stepping time ----------------------------------------------------------------------

func test_pausing_the_game_freezes_the_motion_exactly_where_it_is() -> void:
	effects_on()
	var characters := every_character_type()
	await frames(2)
	var offsets: Dictionary[String, int] = {}
	for kind in characters:
		offsets[kind] = motion_of(characters[kind]).offset_y
	var clock_then := CharacterMotionDriver.clock
	get_tree().paused = true
	await frames(40)
	assert_float(CharacterMotionDriver.clock).is_equal(clock_then)
	for kind in characters:
		assert_int(motion_of(characters[kind]).offset_y).is_equal(offsets[kind])
	get_tree().paused = false
	await frames(4)
	assert_float(CharacterMotionDriver.clock).is_greater(clock_then)

func test_stepping_no_time_changes_nothing() -> void:
	effects_on()
	var characters := every_character_type()
	for i in 10:
		CharacterMotionDriver.advance(STEP)
	var offsets: Dictionary[String, int] = {}
	for kind in characters:
		offsets[kind] = motion_of(characters[kind]).offset_y
	var clock_then := CharacterMotionDriver.clock
	for i in 20:
		CharacterMotionDriver.advance(0.0)
	assert_float(CharacterMotionDriver.clock).is_equal(clock_then)
	for kind in characters:
		assert_int(motion_of(characters[kind]).offset_y).is_equal(offsets[kind])

# --- nothing left behind ----------------------------------------------------------------------------

## Every node in the game right now.
func node_count() -> int:
	var count: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	return roundi(count)

func test_no_node_is_left_behind_by_a_busy_stretch_of_characters() -> void:
	effects_on()
	clock_in()
	await frames(3)
	var nodes_before := node_count()
	var motions_before := CharacterMotionDriver.motions.size()
	var crowd: Array[Node2D] = []
	for i in 12:
		if i < 2:
			crowd.append(spawn())
		var staff_customer := (load("res://scenes/characters/customer_npc.tscn") as PackedScene).instantiate() as CustomerNPC
		room.add_child(staff_customer)
		crowd.append(staff_customer)
		staff_customer.say("Hello")
	for i in 150:
		CharacterMotionDriver.advance(STEP)
	assert_int(CharacterMotionDriver.motions.size()).is_equal(motions_before + crowd.size())
	for character in crowd:
		character.free()
	cq.queue.clear()
	await frames(3)
	assert_int(CharacterMotionDriver.motions.size()).is_equal(motions_before)
	assert_int(CharacterMotionDriver.popping.size()).is_equal(0)
	assert_int(node_count()).is_equal(nodes_before)

func test_the_driver_and_every_motion_go_with_the_room() -> void:
	effects_on()
	var characters := every_character_type()
	assert_int(CharacterMotionDriver.motions.size()).is_greater_equal(characters.size())
	await frames(2)
	assert_bool(CharacterMotionDriver.has_driver()).is_true()
	room.free()
	room = null
	# The start screen unpauses whatever the room left paused, as the real game does.
	get_tree().paused = false
	await frames(3)
	assert_int(CharacterMotionDriver.motions.size()).is_equal(0)
	assert_int(CharacterMotionDriver.popping.size()).is_equal(0)
	assert_bool(CharacterMotionDriver.has_driver()).override_failure_message("the driver is still there with nobody to drive").is_false()

func test_the_shadow_and_outline_stay_children_and_the_motion_is_one_more() -> void:
	var character := room.player
	assert_object(motion_of(character)).is_not_null()
	assert_bool(motion_of(character).get_parent() == character).is_true()
	# One shared driver for the whole world, not one per character.
	await frames(2)
	assert_int(get_tree().root.find_children("*", "CharacterMotionDriver", false, false).size()).is_equal(1)
