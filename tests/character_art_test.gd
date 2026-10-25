extends "res://tests/support/teller_room_suite.gd"

## The character sprite pass (ART.md): every SpriteFrames keeps the in-house
## format, staff wear their own uniform look instead of a tint and badge,
## customers come in every look, and impatience shows in a bubble above the
## customer while their sprite keeps its colours.

const SPRITES_DIR := "res://assets/sprites/"
const DIRECTIONS: Array[String] = ["down", "up", "side"]

# --- helpers -------------------------------------------------------------------

## Every SpriteFrames resource in assets/sprites, by path.
func all_frames_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(SPRITES_DIR):
		if file.ends_with("_frames.tres"):
			paths.append(SPRITES_DIR + file)
	paths.sort()
	return paths

## The first idle frame facing down, as an Image read from the PNG itself.
func down_idle_image(frames: SpriteFrames) -> Image:
	var atlas_frame := frames.get_frame_texture("idle_down", 0) as AtlasTexture
	var image := Image.load_from_file(ProjectSettings.globalize_path(atlas_frame.atlas.resource_path))
	return image.get_region(Rect2i(atlas_frame.region))

func images_equal(a: Image, b: Image) -> bool:
	return a.get_data() == b.get_data()

## The distinct opaque colours in an image.
func colours_of(image: Image) -> Array[Color]:
	var colours: Array[Color] = []
	for y in image.get_height():
		for x in image.get_width():
			var colour := image.get_pixel(x, y)
			if colour.a > 0.0 and not colours.has(colour):
				colours.append(colour)
	return colours

func new_customer() -> CustomerNPC:
	var customer: CustomerNPC = (load("res://scenes/characters/customer_npc.tscn") as PackedScene).instantiate()
	room.add_child(customer)
	return customer

func sprite_of(node: Node) -> AnimatedSprite2D:
	return node.get_node("AnimatedSprite2D") as AnimatedSprite2D

# --- format --------------------------------------------------------------------

func test_every_sprite_frames_has_the_full_format() -> void:
	var paths := all_frames_paths()
	# player, 12 customer looks, 10 staff looks, the Regional Manager, the two
	# armored truck guards.
	assert_int(paths.size()).is_equal(1 + 12 + 10 + 1 + 2)
	for path in paths:
		var frames: SpriteFrames = load(path)
		var names := Array(frames.get_animation_names())
		names.sort()
		assert_array(names).override_failure_message("%s animations" % path).is_equal(["idle_down", "idle_side", "idle_up", "walk_down", "walk_side", "walk_up"])
		for direction in DIRECTIONS:
			for kind: String in ["idle", "walk"]:
				var animation := "%s_%s" % [kind, direction]
				assert_int(frames.get_frame_count(animation)).override_failure_message("%s %s" % [path, animation]).is_equal(2 if kind == "idle" else 4)
				assert_float(frames.get_animation_speed(animation)).is_equal(2.0 if kind == "idle" else 8.0)
				assert_bool(frames.get_animation_loop(animation)).is_true()
				for i in frames.get_frame_count(animation):
					var texture := frames.get_frame_texture(animation, i)
					assert_vector(texture.get_size()).override_failure_message("%s %s %d" % [path, animation, i]).is_equal(Vector2(16, 24))
					var atlas_frame := texture as AtlasTexture
					assert_str(atlas_frame.atlas.resource_path).ends_with("_%s.png" % direction)

# --- staff ---------------------------------------------------------------------

func test_staff_wear_their_look_with_no_tint_or_badge() -> void:
	assert_int(room._staff_by_slot.size()).is_greater(0)
	for npc: StaffNPC in room._staff_by_slot.values():
		var sprite := sprite_of(npc)
		assert_object(npc.get_node_or_null("Badge")).is_null()
		assert_bool(sprite.modulate == Color.WHITE).is_true()
		assert_bool(sprite.self_modulate == Color.WHITE).is_true()
		assert_bool(npc.modulate == Color.WHITE).is_true()
		assert_str(sprite.sprite_frames.resource_path).is_equal(StaffLooks.frames_path(npc.staff.look))
	# No customer art on staff any more.
	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/staff_npc.tscn")
	assert_str(scene_text).not_contains("customer_")
	assert_str(scene_text).not_contains("Badge")

func test_each_roster_member_has_a_distinct_look() -> void:
	var roster := StaffRosterData.get_staff()
	var looks: Array[String] = []
	var images: Array[Image] = []
	for member in roster:
		assert_bool(StaffLooks.ROSTER_LOOKS.has(member.look)).is_true()
		assert_bool(looks.has(member.look)).override_failure_message("%s shares a look" % member.staff_name).is_false()
		looks.append(member.look)
		images.append(down_idle_image(StaffLooks.frames_for(member.look)))
	for i in images.size():
		for j in range(i + 1, images.size()):
			# Different pixels and a different palette (hair and/or skin).
			assert_bool(images_equal(images[i], images[j])).is_false()
			assert_array(colours_of(images[i])).override_failure_message("%s and %s look alike" % [roster[i].staff_name, roster[j].staff_name]).is_not_equal(colours_of(images[j]))

func test_the_uniform_is_unlike_the_players_suit() -> void:
	var player_colours := colours_of(down_idle_image(load("res://assets/sprites/player_frames.tres") as SpriteFrames))
	var blazer := Color8(0x2d, 0x51, 0x96)
	var player_suit := Color8(0x1e, 0x1e, 0x26)
	assert_bool(player_colours.has(player_suit)).is_true()
	for look in StaffLooks.all_looks():
		var colours := colours_of(down_idle_image(StaffLooks.frames_for(look)))
		assert_bool(colours.has(blazer)).override_failure_message(look).is_true()
		assert_bool(colours.has(player_suit)).override_failure_message(look).is_false()
	# The blazer is clearly blue, the suit near-black.
	assert_float(blazer.b - blazer.r).is_greater(0.3)
	assert_float(player_suit.b - player_suit.r).is_less(0.05)

func test_the_regional_manager_looks_like_neither_staff_nor_player() -> void:
	var look := StaffLooks.REGIONAL_MANAGER_LOOK
	assert_bool(StaffLooks.all_looks().has(look)).is_false()
	var frames := StaffLooks.frames_for(look)
	assert_str(frames.resource_path).is_equal(StaffLooks.frames_path(look))
	var colours := colours_of(down_idle_image(frames))
	# No uniform blazer or name tag, and not the player's near-black suit.
	for colour: Color in [Color8(0x2d, 0x51, 0x96), Color8(0xe8, 0xc5, 0x47), Color8(0x1e, 0x1e, 0x26)]:
		assert_bool(colours.has(colour)).override_failure_message("has %s" % colour).is_false()
	# A grey suit and silver hair instead.
	assert_bool(colours.has(Color8(0x6b, 0x71, 0x7e))).is_true()
	assert_bool(colours.has(Color8(0xd4, 0xd4, 0xd4))).is_true()

func test_the_armored_guards_wear_their_own_uniform() -> void:
	var seen: Array = []
	for look in StaffLooks.GUARD_LOOKS:
		assert_bool(StaffLooks.all_looks().has(look)).is_false()
		var frames := StaffLooks.frames_for(look)
		assert_str(frames.resource_path).is_equal(StaffLooks.frames_path(look))
		var colours := colours_of(down_idle_image(frames))
		# No staff blazer or name tag, no Regional Manager grey, no player suit.
		for colour: Color in [Color8(0x2d, 0x51, 0x96), Color8(0xe8, 0xc5, 0x47), Color8(0x6b, 0x71, 0x7e), Color8(0x1e, 0x1e, 0x26)]:
			assert_bool(colours.has(colour)).override_failure_message("%s has %s" % [look, colour]).is_false()
		# The olive jacket and the silver badge.
		assert_bool(colours.has(Color8(0x4b, 0x5a, 0x33))).override_failure_message(look).is_true()
		assert_bool(colours.has(Color8(0xc9, 0xce, 0xd6))).override_failure_message(look).is_true()
		seen.append(colours)
	# The two guards look different from each other.
	assert_bool(seen[0] == seen[1]).is_false()

func test_hired_staff_get_a_hire_look_that_is_saved() -> void:
	XPManager._grant_branch_manager()
	var letters: DisciplineLetterScreen = room.get_node("UI/DisciplineLetterScreen")
	while letters.visible:
		letters.action_button.pressed.emit()
	# One hire: the first hire look, worn at their desk.
	var vacated := ScheduleManager.schedule.duplicate()
	vacated.erase(ScheduleManager.SLOT_TELLER_WINDOW_2)
	ScheduleManager.confirm_schedule(vacated)
	var pick := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)[0]
	assert_dict(HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, pick)).is_not_empty()
	var member := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_str(member.look).is_equal(StaffLooks.HIRE_LOOKS[0])
	assert_str(sprite_of(room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_2]).sprite_frames.resource_path).is_equal(StaffLooks.frames_path(member.look))
	# Letting them go frees their look and their place on the roster.
	ScheduleManager.dismiss_staff(member.staff_name)

	# Two hires at once wear different looks, and the looks survive a save.
	var two := ScheduleManager.schedule.duplicate()
	two.erase(ScheduleManager.SLOT_TELLER_WINDOW_1)
	two.erase(ScheduleManager.SLOT_TELLER_WINDOW_2)
	ScheduleManager.confirm_schedule(two)
	HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_1, HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_1)[0])
	HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)[0])
	var look_1 := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).look
	var look_2 := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).look
	assert_str(look_1).is_not_equal(look_2)
	var saved_career := SaveGame.capture()
	CareerReset.reset_all()
	SaveGame.restore(saved_career)
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).look).is_equal(look_1)
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).look).is_equal(look_2)

func test_an_unknown_look_falls_back_to_the_uniform() -> void:
	assert_str(StaffLooks.frames_for("no_such_look").resource_path).is_equal(StaffLooks.frames_path(StaffLooks.FALLBACK_LOOK))
	assert_str(StaffLooks.frames_for("").resource_path).is_equal(StaffLooks.frames_path(StaffLooks.FALLBACK_LOOK))

# --- customers -----------------------------------------------------------------

func test_customers_spawn_in_every_look() -> void:
	# Every customer sheet on disk is in the pool, and only those.
	var pool: Array[String] = []
	for frames in CustomerNPC.CUSTOMER_FRAME_SETS:
		pool.append(frames.resource_path)
	var on_disk: Array[String] = []
	for path in all_frames_paths():
		if path.get_file().begins_with("customer_"):
			on_disk.append(path)
	pool.sort()
	assert_array(pool).is_equal(on_disk)
	assert_int(pool.size()).is_between(9, 12)

	var seen: Array[String] = []
	for i in 150:
		var customer := new_customer()
		var path := sprite_of(customer).sprite_frames.resource_path
		if not seen.has(path):
			seen.append(path)
		customer.free()
	seen.sort()
	assert_array(seen).is_equal(pool)

func test_customer_skin_tones_vary() -> void:
	# The pool covers light to deep skin: count distinct skin colours in the
	# hands (the bottom-left hand pixel of the down idle frame).
	var skins: Array[Color] = []
	for frames in CustomerNPC.CUSTOMER_FRAME_SETS:
		var hand := down_idle_image(frames).get_pixel(1, 16)
		if not skins.has(hand):
			skins.append(hand)
	assert_int(skins.size()).is_greater_equal(8)
	var lightest := 0.0
	var deepest := 1.0
	for skin in skins:
		lightest = maxf(lightest, skin.get_luminance())
		deepest = minf(deepest, skin.get_luminance())
	assert_float(lightest - deepest).is_greater(0.4)

# --- impatience ------------------------------------------------------------------

func test_impatience_shows_a_bubble_and_never_tints_the_sprite() -> void:
	var customer := new_customer()
	var sprite := sprite_of(customer)
	var bubble := customer.patience_indicator
	var stages := {
		0.0: PatienceIndicator.Stage.HIDDEN,
		PatienceIndicator.WAITING_FROM: PatienceIndicator.Stage.WAITING,
		PatienceIndicator.IMPATIENT_FROM: PatienceIndicator.Stage.IMPATIENT,
		PatienceIndicator.LEAVING_FROM: PatienceIndicator.Stage.LEAVING,
	}
	for share: float in stages:
		customer.wait_seconds = (share + 0.001) * CustomerNPC.WAIT_ABANDON_SECONDS
		customer._process(0.0)
		assert_int(bubble.stage).is_equal(stages[share])
		assert_bool(bubble.visible).is_equal(stages[share] != PatienceIndicator.Stage.HIDDEN)
		assert_bool(sprite.modulate == Color.WHITE).is_true()
		assert_bool(sprite.self_modulate == Color.WHITE).is_true()
	# Above their head, drawn over the room.
	assert_float(bubble.position.y).is_less(-12.0)
	assert_int(bubble.z_index).is_greater(0)
	# Being served puts it away.
	customer.stop_waiting()
	assert_bool(bubble.visible).is_false()
	assert_bool(sprite.modulate == Color.WHITE).is_true()
	customer.free()

func test_a_waiting_line_customer_shows_the_bubble() -> void:
	clock_in()
	var customer := spawn()
	var bubble := customer.patience_indicator
	assert_bool(bubble.visible).is_false()
	customer.wait_seconds = 0.9 * CustomerNPC.WAIT_ABANDON_SECONDS
	await get_tree().process_frame
	assert_int(bubble.stage).is_equal(PatienceIndicator.Stage.LEAVING)
	assert_bool(bubble.is_visible_in_tree()).is_true()
	assert_bool(sprite_of(customer).modulate == Color.WHITE).is_true()
