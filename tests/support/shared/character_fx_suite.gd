extends "res://tests/support/teller/teller_suite.gd"

## Shared by the tests of what the character effects (CharacterFx) actually
## LOOK like and how they MOVE (character_fx_look_test.gd,
## character_motion_test.gd): the six kinds of character, and the measurements
## of what their outline and shadow draw.
##
## What the look tests are about, not only that the nodes exist. Headless has no renderer to take pictures with, so these
## measure what the outline and the shadow draw: the rectangles the outline
## stamps (after any mirroring) and the points the shadow's oval is made of.
##
## The bug these exist for: a character facing left (a mirrored sprite) got a
## black, body-shaped copy a whole frame to its right, because the mirrored
## outline was drawn with a negative-width rectangle, which Godot anchors at
## its left edge. Nothing then drew outside a 1 px outline and the foot oval
## was the rule that was broken, so that is the rule tested, for every
## character type, facing, mirrored side view, animation frame and both zooms.

## Where the feet are: the shadow's oval may be anywhere in this box
## (frame-relative, the frame is 16x24 centred), and nothing else may draw
## outside the sprite's own rectangle grown by the 1 px outline.
const FOOT_AREA: Rect2 = Rect2(-8.0, 6.0, 16.0, 8.0)
const OUTLINE_STEPS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const EPSILON: float = 0.001

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

# --- the characters ----------------------------------------------------------------------

## One of every kind of character: the player, a customer, a staff member, a
## walk-in loan applicant, an armored truck guard and the Regional Manager.
func every_character_type() -> Dictionary[String, Node2D]:
	var characters: Dictionary[String, Node2D] = {}
	characters["player"] = room.player
	clock_in()
	characters["customer"] = spawn()
	characters["staff"] = room._staff_by_slot.values()[0]
	var applicant := (load("res://scenes/characters/loan_applicant_npc.tscn") as PackedScene).instantiate() as Node2D
	room.add_child(applicant)
	characters["applicant"] = applicant
	var guard := (load("res://scenes/characters/staff_npc.tscn") as PackedScene).instantiate() as StaffNPC
	var member := StaffMember.new()
	member.staff_name = "Guard"
	member.look = StaffLooks.GUARD_LOOKS[0]
	guard.setup(member)
	room.add_child(guard)
	characters["guard"] = guard
	# The Regional Manager: the same character class in the Regional Manager look. (No
	# promotion or Regional visit here: they move the day along, and the slot
	# card that follows pauses the game and so the motion.)
	var regional := (load("res://scenes/characters/staff_npc.tscn") as PackedScene).instantiate() as StaffNPC
	var visitor := StaffMember.new()
	visitor.staff_name = "Regional Manager"
	visitor.look = StaffLooks.REGIONAL_MANAGER_LOOK
	regional.setup(visitor)
	room.add_child(regional)
	characters["regional manager"] = regional
	get_tree().paused = false
	return characters

func sprite_of(character: Node2D) -> AnimatedSprite2D:
	return character.get_node("AnimatedSprite2D") as AnimatedSprite2D

func outline_of(character: Node2D) -> CharacterOutline:
	return character.get_node(NodePath(CharacterFx.OUTLINE_NODE)) as CharacterOutline

func shadow_of(character: Node2D) -> CharacterShadow:
	return character.get_node(NodePath(CharacterFx.SHADOW_NODE)) as CharacterShadow

func zoom_to(overview: bool) -> void:
	var camera := room.player.get_node("Camera2D") as RoomCamera
	camera.set_overview(overview)
	camera.finish_ease()

# --- the look rules ----------------------------------------------------------------------

func rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - EPSILON and inner.position.y >= outer.position.y - EPSILON and inner.end.x <= outer.end.x + EPSILON and inner.end.y <= outer.end.y + EPSILON

## Everything wrong with how `character`'s effects look in the sprite's
## current state: an empty list is a clean look.
func look_problems(character: Node2D, label: String) -> Array[String]:
	var problems: Array[String] = []
	var sprite := sprite_of(character)
	var outline := outline_of(character)
	var shadow := shadow_of(character)
	var frame := outline.sprite_rect()
	var rects := outline.drawn_rects()
	if rects.size() != 4:
		problems.append("%s: the outline draws %d rectangles, not its 4 one-pixel copies" % [label, rects.size()])
	# 1. The outline: only ever the sprite's own rectangle moved exactly 1 art pixel.
	var steps_seen: Array[Vector2] = []
	for rect in rects:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			problems.append("%s: an outline copy has no positive size %s" % [label, rect])
		if not rect.size.is_equal_approx(frame.size):
			problems.append("%s: an outline copy is %s, the sprite is %s" % [label, rect.size, frame.size])
		var step := rect.position - frame.position
		var matched := false
		for wanted in OUTLINE_STEPS:
			if step.is_equal_approx(wanted):
				matched = true
				steps_seen.append(wanted)
		if not matched:
			problems.append("%s: an outline copy is %s from the sprite, not exactly 1 px up, down, left or right (a detached or displaced copy)" % [label, step])
		if not rect_inside(rect, frame.grow(1.0)):
			problems.append("%s: an outline copy %s draws outside the sprite's frame %s plus 1 px" % [label, rect, frame])
	for wanted in OUTLINE_STEPS:
		if not steps_seen.has(wanted):
			problems.append("%s: no outline copy %s from the sprite" % [label, wanted])
	# 2. Mirroring maps the sprite's own rectangle onto itself.
	var mirrored_frame := outline.mirror_transform() * frame
	if not (mirrored_frame.position.is_equal_approx(frame.position) and mirrored_frame.size.is_equal_approx(frame.size)):
		problems.append("%s: mirroring moves the sprite's frame from %s to %s" % [label, frame, mirrored_frame])
	# 3. The shadow: a small oval in the foot area, nothing sprite-shaped.
	if shadow.get_child_count() != 0:
		problems.append("%s: the shadow has children (it must be a plain oval)" % label)
	var points := CharacterShadow.drawn_points()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
		if point.x < -8.0 - EPSILON or point.x > 8.0 + EPSILON or point.y < FOOT_AREA.position.y - EPSILON or point.y > FOOT_AREA.end.y + EPSILON:
			problems.append("%s: a shadow point %s is outside the foot area %s" % [label, point, FOOT_AREA])
	if bounds.size.x > 16.0 + EPSILON or bounds.size.y > 8.0 + EPSILON or bounds.size.x < bounds.size.y * 2.0:
		problems.append("%s: the shadow is %s, not a small flat oval at the feet" % [label, bounds.size])
	if not shadow.position.is_equal_approx(CharacterShadow.FEET):
		problems.append("%s: the shadow sits at %s, not the feet at %s" % [label, shadow.position, CharacterShadow.FEET])
	# 4. Together: nothing outside a 1 px outline plus the foot oval.
	var allowed := frame.grow(1.0)
	for rect in rects:
		if not rect_inside(rect, allowed):
			problems.append("%s: the outline draws outside a 1 px outline" % label)
	for point in points:
		var in_frame := allowed.has_point(point)
		var in_feet := FOOT_AREA.grow(0.01).has_point(point)
		if not (in_frame or in_feet):
			problems.append("%s: the shadow point %s is outside the frame and the foot area" % [label, point])
	# 5. Never a coloured tint of its own: the day/night tint multiplies it like the rest.
	if outline.modulate != Color.WHITE or outline.self_modulate != Color.WHITE or shadow.modulate != Color.WHITE:
		problems.append("%s: an effect carries a tint of its own" % label)
	if outline.get_child_count() != 0:
		problems.append("%s: the outline has children, it would outline them too" % label)
	if sprite.material != null or outline.material != null:
		problems.append("%s: a material changes how the character draws" % label)
	return problems

func assert_no_problems(problems: Array[String]) -> void:
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- motion ----------------------------------------------------------------------------------

func motion_of(character: Node2D) -> CharacterMotion:
	return character.get_node(NodePath(CharacterFx.MOTION_NODE)) as CharacterMotion

## Everything wrong with how `character` moves at this instant (empty: fine):
## the move is 0 or one whole pixel straight up or down, the sprite and its
## outline moved together by exactly that, and the shadow didn't move. On top
## of look_problems(), which has the outline still exactly four 1 px copies
## and nothing drawn outside a 1 px outline plus the foot oval.
func motion_problems(character: Node2D, label: String) -> Array[String]:
	var problems := look_problems(character, label)
	var motion := motion_of(character)
	var sprite := sprite_of(character)
	var outline := outline_of(character)
	var shadow := shadow_of(character)
	if motion.offset_y < -1 or motion.offset_y > 1:
		problems.append("%s: moved %d px, more than one whole pixel" % [label, motion.offset_y])
	if sprite.position != Vector2(0.0, float(motion.offset_y)):
		problems.append("%s: the sprite is at %s, not %d whole pixels from its place" % [label, sprite.position, motion.offset_y])
	# The outline is stamped from the sprite's own place: moved with it, to the pixel.
	var texture := outline.frame_texture()
	if texture != null:
		var expected := sprite.position + sprite.offset - texture.get_size() / 2.0
		if not outline.sprite_rect().position.is_equal_approx(expected):
			problems.append("%s: the outline's frame %s isn't where the sprite is %s" % [label, outline.sprite_rect().position, expected])
	if outline.position != Vector2.ZERO:
		problems.append("%s: the outline node itself moved to %s" % [label, outline.position])
	# What was last drawn is what the sprite is now: never a frame behind.
	if outline._sprite_position != sprite.position:
		problems.append("%s: the outline last drew the sprite at %s, it is at %s" % [label, outline._sprite_position, sprite.position])
	if not shadow.position.is_equal_approx(CharacterShadow.FEET):
		problems.append("%s: the shadow moved to %s" % [label, shadow.position])
	return problems
