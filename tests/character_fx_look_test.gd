extends "res://tests/support/teller/teller_suite.gd"

## What the character effects (CharacterFx) actually LOOK like, not only that
## the nodes exist. Headless has no renderer to take pictures with, so these
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
	XPManager._grant_branch_manager()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	regional_visit().start_visit()
	characters["regional manager"] = regional_visit().visitor
	return characters

func sprite_of(character: Node2D) -> AnimatedSprite2D:
	return character.get_node("AnimatedSprite2D") as AnimatedSprite2D

func outline_of(character: Node2D) -> CharacterOutline:
	return character.get_node(NodePath(CharacterFx.OUTLINE_NODE)) as CharacterOutline

func shadow_of(character: Node2D) -> CharacterShadow:
	return character.get_node(NodePath(CharacterFx.SHADOW_NODE)) as CharacterShadow

func zoom_to(overview: bool) -> void:
	(room.player.get_node("Camera2D") as RoomCamera).set_overview(overview)

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

# --- every character, facing, flip and frame, both zooms --------------------------------------

func test_the_effects_never_draw_outside_a_one_pixel_outline_and_the_foot_oval() -> void:
	var characters := every_character_type()
	var problems: Array[String] = []
	var checked := 0
	for overview: bool in [false, true]:
		zoom_to(overview)
		for kind: String in characters:
			var character := characters[kind]
			var sprite := sprite_of(character)
			for animation: StringName in sprite.sprite_frames.get_animation_names():
				for frame in sprite.sprite_frames.get_frame_count(animation):
					for flipped: bool in [false, true]:
						sprite.animation = animation
						sprite.frame = frame
						sprite.flip_h = flipped
						var label := "%s %s frame %d %s at %s" % [kind, animation, frame, "mirrored" if flipped else "normal", "1x" if overview else "2x"]
						problems.append_array(look_problems(character, label))
						checked += 1
	zoom_to(false)
	assert_int(checked).is_greater(200)
	assert_no_problems(problems)

func test_a_character_facing_left_has_no_displaced_dark_copy() -> void:
	# The reported bug, exactly: a mirrored side view (walking left).
	var outline := outline_of(room.player)
	var sprite := sprite_of(room.player)
	sprite.animation = &"walk_side"
	sprite.frame = 0
	sprite.flip_h = true
	var frame := outline.sprite_rect()
	for rect in outline.drawn_rects():
		assert_float(absf(rect.get_center().x - frame.get_center().x)).is_less_equal(1.0 + EPSILON)
		assert_float(absf(rect.get_center().y - frame.get_center().y)).is_less_equal(1.0 + EPSILON)
	var combined := Rect2(outline.drawn_rects()[0].position, Vector2.ZERO)
	for rect in outline.drawn_rects():
		combined = combined.merge(rect)
	# The four copies together are the frame plus a 1 px border, not two figures.
	assert_vector(combined.size).is_equal_approx(frame.size + Vector2(2, 2), Vector2(EPSILON, EPSILON))

func test_the_mirrored_drawing_is_not_a_negative_width_rectangle() -> void:
	# What caused the bug: every rectangle the outline stamps has a positive size,
	# whichever way the character faces; mirroring is a transform, not a flipped rect.
	for kind: Node2D in every_character_type().values():
		var outline := outline_of(kind)
		for flipped: bool in [false, true]:
			sprite_of(kind).flip_h = flipped
			for rect in outline.copy_rects():
				assert_float(rect.size.x).is_greater(0.0)
				assert_float(rect.size.y).is_greater(0.0)
			assert_bool(outline.mirror_transform() == Transform2D.IDENTITY).is_equal(not flipped)

func test_the_effects_are_the_same_at_both_zooms() -> void:
	var outline := outline_of(room.player)
	sprite_of(room.player).flip_h = true
	zoom_to(false)
	var at_2x := outline.drawn_rects()
	var shadow_2x := CharacterShadow.drawn_points()
	zoom_to(true)
	var at_1x := outline.drawn_rects()
	assert_int(at_1x.size()).is_equal(at_2x.size())
	for i in at_2x.size():
		assert_bool(at_1x[i].is_equal_approx(at_2x[i])).is_true()
	assert_array(CharacterShadow.drawn_points()).is_equal(shadow_2x)
	zoom_to(false)

# --- a character whose art fails to load -------------------------------------------------------

func test_a_character_whose_frames_fail_to_load_shows_a_warning_not_a_black_silhouette() -> void:
	var characters := every_character_type()
	for kind: String in characters:
		var character := characters[kind]
		var sprite := sprite_of(character)
		var outline := outline_of(character)
		var original_frames := sprite.sprite_frames
		assert_bool(outline.is_missing()).override_failure_message("%s starts out missing its art" % kind).is_false()
		for flipped: bool in [false, true]:
			sprite.flip_h = flipped
			# No frames at all, frames with nothing in them, a frame with no texture.
			for broken: String in ["no frames", "empty frames", "no texture"]:
				sprite.sprite_frames = original_frames
				match broken:
					"no frames":
						sprite.sprite_frames = null
					"empty frames":
						sprite.sprite_frames = SpriteFrames.new()
					"no texture":
						var hollow := SpriteFrames.new()
						hollow.add_frame(&"default", null)
						sprite.sprite_frames = hollow
				var label := "%s (%s, %s)" % [kind, broken, "mirrored" if flipped else "normal"]
				assert_bool(outline.is_missing()).override_failure_message("%s: not reported missing" % label).is_true()
				var rects := outline.drawn_rects()
				assert_int(rects.size()).override_failure_message("%s: should draw one warning box" % label).is_equal(1)
				assert_vector(rects[0].size).is_equal(CharacterOutline.MISSING_SIZE)
				# The warning is visible (a magenta box) and sits on the character, not beside it.
				assert_float(CharacterOutline.MISSING_LINE.a).is_equal(1.0)
				assert_float(CharacterOutline.MISSING_LINE.r).is_greater(0.9)
				assert_float(CharacterOutline.MISSING_LINE.g).is_less(0.1)
				assert_bool(rect_inside(rects[0], Rect2(-8, -12, 16, 24).grow(0.5))).override_failure_message("%s: the warning box %s is off the character" % [label, rects[0]]).is_true()
				# The oval is still just an oval.
				assert_int(shadow_of(character).get_child_count()).is_equal(0)
		sprite.sprite_frames = original_frames
		sprite.animation = &"idle_down"
		sprite.frame = 0
		assert_bool(outline.is_missing()).override_failure_message("%s: still missing once the art is back" % kind).is_false()

# --- the other things drawn near a character -------------------------------------------------

func test_the_impatience_bubble_and_labels_are_never_outlined_or_shadowed() -> void:
	clock_in()
	var customer := spawn()
	var outline := outline_of(customer)
	assert_int(outline.get_child_count()).is_equal(0)
	assert_int(shadow_of(customer).get_child_count()).is_equal(0)
	for child in customer.get_children():
		if child is PatienceIndicator:
			assert_object(child.get_parent()).is_same(customer)
			assert_bool(child.is_ancestor_of(outline)).is_false()
	for npc: StaffNPC in room._staff_by_slot.values():
		var label := npc.get_node_or_null("NameLabel")
		if label != null:
			assert_bool(outline_of(npc).is_ancestor_of(label)).is_false()

func test_the_day_and_night_tints_do_not_change_what_the_effects_draw() -> void:
	var player := room.player
	var sprite := sprite_of(player)
	var outline := outline_of(player)
	# The player's own script resets the pose each physics frame, so it is set again
	# right before every measurement.
	sprite.animation = &"walk_side"
	sprite.frame = 1
	sprite.flip_h = true
	var rects_before := outline.drawn_rects()
	var shadow_before := CharacterShadow.drawn_points()
	for minutes: float in [3.0 * 60.0, 6.5 * 60.0, 12.0 * 60.0, 17.0 * 60.0, 20.0 * 60.0]:
		GameClock.minutes = minutes
		await frames(2)
		sprite.animation = &"walk_side"
		sprite.frame = 1
		sprite.flip_h = true
		var rects_after := outline.drawn_rects()
		assert_int(rects_after.size()).is_equal(rects_before.size())
		for i in rects_before.size():
			assert_bool(rects_after[i].is_equal_approx(rects_before[i])).override_failure_message("the outline moved at %s minutes" % minutes).is_true()
		assert_array(CharacterShadow.drawn_points()).is_equal(shadow_before)
		assert_that(outline.modulate).is_equal(Color.WHITE)
		assert_that(shadow_of(player).modulate).is_equal(Color.WHITE)

func test_the_outline_redraws_in_the_frame_the_sprite_changes() -> void:
	# It used to look at the sprite once per frame and so lag a frame behind.
	var sprite := sprite_of(room.player)
	var outline := outline_of(room.player)
	sprite.animation = &"walk_side"
	sprite.frame = 0
	var requests_before := outline.redraw_requests
	sprite.frame = 1
	assert_int(outline.redraw_requests).override_failure_message("the outline didn't redraw when the sprite's frame changed").is_greater(requests_before)
	requests_before = outline.redraw_requests
	sprite.animation = &"walk_down"
	assert_int(outline.redraw_requests).override_failure_message("the outline didn't redraw when the animation changed").is_greater(requests_before)
