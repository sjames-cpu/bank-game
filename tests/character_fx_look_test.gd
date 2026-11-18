extends "res://tests/support/shared/character_fx_suite.gd"

## What the character effects (CharacterFx) actually LOOK like (see
## character_fx_suite.gd for the measurements): for every character type,
## facing, mirrored side view, animation frame and both zooms, the outline is
## exactly four 1 px copies and the shadow a small oval at the feet. The
## bug these exist for: a character facing left got a black, body-shaped copy
## a whole frame to its right (a negative-width rectangle in the outline).

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
