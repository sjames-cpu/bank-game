extends "res://tests/support/teller_room_suite.gd"

## The art visibility pass (world-space effects only): character shadows and
## outlines (CharacterFx), the pulsing highlight on what E would do
## (InteractableHighlight), the attention markers over desks and doors
## (AttentionMarker), the zone tints and signs (RoomZones, WallSign), the
## floating Score/XP/Reputation numbers (FeedbackFloaters), the 1x overview
## hiding the clutter, and no node left behind.

const CHARACTER_SCENES: Array[String] = [
	"res://scenes/characters/customer_npc.tscn",
	"res://scenes/characters/staff_npc.tscn",
	"res://scenes/characters/loan_applicant_npc.tscn",
]

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

## The player is at `desk` (and nowhere else), and the room has looked.
func stand_at(desk: Interactable) -> void:
	for each in room._interactables():
		each.player_in_range = false
	if desk != null:
		desk.player_in_range = true
	room._process(0.0)

func highlight_shown(desk: Interactable) -> bool:
	return desk.highlight.is_shown()

# --- shadows and outlines -------------------------------------------------------------

func assert_has_fx(character: Node2D) -> void:
	assert_bool(CharacterFx.has_fx(character)).override_failure_message("%s has no shadow and outline" % character.name).is_true()
	var sprite: AnimatedSprite2D = character.get_node("AnimatedSprite2D")
	var shadow := character.get_node(NodePath(CharacterFx.SHADOW_NODE))
	var outline := character.get_node(NodePath(CharacterFx.OUTLINE_NODE))
	# Behind the sprite, and the sprite itself is untouched (no material).
	assert_int(shadow.get_index()).is_less(outline.get_index())
	assert_int(outline.get_index()).is_less(sprite.get_index())
	assert_object(sprite.material).is_null()
	assert_bool(character.is_in_group(CharacterFx.GROUP)).is_true()

func test_the_player_has_a_shadow_and_an_outline() -> void:
	assert_has_fx(room.player)

func test_every_staff_member_the_regional_manager_and_guards_have_them() -> void:
	assert_bool(room._staff_by_slot.is_empty()).is_false()
	for npc: StaffNPC in room._staff_by_slot.values():
		assert_has_fx(npc)
	promote()
	room._start_regional_visit()
	assert_has_fx(room.regional_visitor)
	var guard := (load("res://scenes/characters/staff_npc.tscn") as PackedScene).instantiate() as StaffNPC
	var member := StaffMember.new()
	member.staff_name = "Guard"
	member.look = StaffLooks.GUARD_LOOKS[0]
	guard.setup(member)
	room.add_child(guard)
	assert_has_fx(guard)

func test_customers_and_applicants_have_them_including_ones_created_later() -> void:
	clock_in()
	for i in 3:
		assert_has_fx(spawn())
	for path in CHARACTER_SCENES:
		var character := (load(path) as PackedScene).instantiate() as Node2D
		room.add_child(character)
		assert_has_fx(character)
	# Staff lines' customers, spawned by the room itself, too.
	room.window1_npc_line._spawn_customer()
	for child in room.window1_npc_line.get_children():
		if child is CustomerNPC:
			assert_has_fx(child as CustomerNPC)

func test_the_outline_follows_the_sprites_flip_and_frame() -> void:
	var customer := spawn()
	var outline := customer.get_node(NodePath(CharacterFx.OUTLINE_NODE)) as CharacterOutline
	var sprite := customer.get_node("AnimatedSprite2D") as AnimatedSprite2D
	outline._process(0.0)
	sprite.flip_h = true
	sprite.play(&"walk_side")
	outline._process(0.0)
	assert_bool(outline._flipped).is_true()
	assert_str(String(outline._animation)).is_equal("walk_side")

func test_the_shadow_and_outline_are_freed_with_the_character() -> void:
	var customer := spawn()
	var shadow := customer.get_node(NodePath(CharacterFx.SHADOW_NODE))
	var outline := customer.get_node(NodePath(CharacterFx.OUTLINE_NODE))
	customer.free()
	assert_bool(is_instance_valid(shadow)).is_false()
	assert_bool(is_instance_valid(outline)).is_false()

# --- highlights ------------------------------------------------------------------------

func test_the_teller_window_glows_only_in_range() -> void:
	stand_at(room.teller_desk)
	assert_object(room.highlighted).is_same(room.teller_desk)
	assert_bool(highlight_shown(room.teller_desk)).is_true()
	for other in room._interactables():
		if other != room.teller_desk:
			assert_bool(highlight_shown(other)).is_false()
	stand_at(null)
	assert_object(room.highlighted).is_null()
	assert_bool(highlight_shown(room.teller_desk)).is_false()

func test_a_locked_loan_desk_gets_no_highlight() -> void:
	XPManager.is_loan_officer_unlocked = false
	stand_at(room.loan_officer_desk)
	assert_bool(room.interaction_prompt_text(room.loan_officer_desk).begins_with("E — ")).is_false()
	assert_bool(highlight_shown(room.loan_officer_desk)).is_false()
	XPManager.is_loan_officer_unlocked = true
	stand_at(room.loan_officer_desk)
	assert_bool(highlight_shown(room.loan_officer_desk)).is_true()

func test_a_staffed_window_after_promotion_gets_no_highlight() -> void:
	promote()
	stand_at(room.teller_desk)
	# After promotion the window is staffed: "<name> is working this window."
	assert_bool(highlight_shown(room.teller_desk)).is_false()
	stand_at(room.loan_officer_desk)
	assert_bool(highlight_shown(room.loan_officer_desk)).is_false()

func test_a_covered_window_gets_no_highlight() -> void:
	XPManager.is_loan_officer_unlocked = true
	GameClock.minutes = 10 * 60.0
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.close_button.pressed.emit()
	assert_bool(room.is_window_covered()).is_true()
	stand_at(room.teller_desk)
	assert_bool(highlight_shown(room.teller_desk)).is_false()

func test_the_manager_desk_atm_and_doormat() -> void:
	promote()
	stand_at(room.branch_manager_desk)
	assert_bool(highlight_shown(room.branch_manager_desk)).is_true()
	stand_at(room.atm)
	assert_bool(highlight_shown(room.atm)).is_true()
	stand_at(room.exit_door)
	assert_bool(highlight_shown(room.exit_door)).is_true()

func test_the_doormat_does_not_glow_while_on_shift() -> void:
	clock_in()
	stand_at(room.exit_door)
	assert_str(room.interaction_prompt_text(room.exit_door)).is_equal("Clock out before you go home")
	assert_bool(highlight_shown(room.exit_door)).is_false()

func test_the_vault_door_glows_only_when_e_opens_it() -> void:
	stand_at(room.vault_door)
	assert_bool(highlight_shown(room.vault_door)).is_false() # off shift
	clock_in()
	stand_at(room.vault_door)
	assert_bool(highlight_shown(room.vault_door)).is_true()

func test_a_highlight_hides_behind_a_desk_screen_and_idles_when_unwanted() -> void:
	stand_at(room.teller_desk)
	var highlight := room.teller_desk.highlight
	highlight._process(0.0)
	assert_bool(highlight.visible).is_true()
	get_tree().paused = true
	highlight._process(0.0)
	assert_bool(highlight.visible).is_false()
	get_tree().paused = false
	stand_at(null)
	assert_bool(highlight.is_processing()).is_false()
	assert_bool(room.atm.highlight.is_processing()).is_false()

# --- attention markers -------------------------------------------------------------------

func marker(place: StringName) -> AttentionMarker:
	return room.attention_markers[place]

func test_the_teller_marker_follows_the_waiting_customer() -> void:
	room._process(0.0)
	assert_bool(marker(&"teller").active).is_false()
	clock_in()
	room._process(0.0)
	assert_bool(marker(&"teller").active).is_false() # nobody yet
	var customer := spawn()
	room._process(0.0)
	assert_bool(marker(&"teller").active).is_true()
	assert_int(marker(&"teller").kind).is_equal(AttentionMarker.Kind.CUSTOMER)
	serve_correctly(customer)
	room._process(0.0)
	assert_bool(marker(&"teller").active).is_false()

func test_the_vault_marker_shows_the_drawer_over_its_limit() -> void:
	clock_in()
	room._process(0.0)
	assert_bool(marker(&"vault").active).is_false()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 500.0))
	assert_str(ts.drawer_limit_warning()).is_equal(TellerScreen.DRAWER_OVER_LIMIT_TEXT)
	room._process(0.0)
	assert_bool(marker(&"vault").active).is_true()
	assert_int(marker(&"vault").kind).is_equal(AttentionMarker.Kind.DOLLAR)
	send_excess_to_vault()
	room._process(0.0)
	assert_bool(marker(&"vault").active).is_false()

func test_the_vault_marker_shows_the_armored_truck_for_the_manager() -> void:
	promote()
	assert_str(VaultManager.place_order(5 * VaultManager.STRAP_CENTS, 3)).is_empty()
	GameClock.day = 4
	BusinessDay.stats_day = 4
	GameClock.minutes = ArmoredTruckVisit.ARRIVAL_MINUTES
	await frames(2)
	for guard: StaffNPC in room.armored_visit.guards.duplicate():
		guard.finish_route()
	assert_bool(room.armored_visit.is_waiting()).is_true()
	room._process(0.0)
	assert_bool(marker(&"vault").active).is_true()
	assert_int(marker(&"vault").kind).is_equal(AttentionMarker.Kind.TRUCK)
	room.armored_visit.phase = ArmoredTruckVisit.Phase.IDLE
	room._process(0.0)
	assert_bool(marker(&"vault").active).is_false()

func test_the_loan_marker_follows_the_seated_applicant() -> void:
	for worker in room.loan_desk_workers:
		worker.active = false
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.close_button.pressed.emit()
	room._process(0.0)
	var seat := room.player_loan_seat()
	assert_bool(marker(&"loan").active).is_false() # walking in
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.WALKING_IN)
	seat.applicant.finish_route()
	room._process(0.0)
	assert_bool(seat.is_seated()).is_true()
	assert_bool(marker(&"loan").active).is_true()
	assert_int(marker(&"loan").kind).is_equal(AttentionMarker.Kind.DOCUMENT)
	seat.send_off("Goodbye.")
	room._process(0.0)
	assert_bool(marker(&"loan").active).is_false()

func test_the_manager_marker_follows_the_staff_review_queue() -> void:
	promote()
	room._process(0.0)
	assert_bool(marker(&"manager").active).is_false()
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	customer.display_name = "Sam Chen"
	customer.intent_type = ShiftTransaction.Type.DEPOSIT
	customer.intent_amount_cents = 20000
	var staff_member := StaffRosterData.get_staff()[0]
	StaffReviewManager.add_teller_mistake(staff_member, ScheduleManager.SLOT_TELLER_WINDOW_1, customer, StaffReviewItem.TellerMistake.WRONG_ACCOUNT, "detail")
	room._process(0.0)
	assert_bool(marker(&"manager").active).is_true()
	assert_int(marker(&"manager").kind).is_equal(AttentionMarker.Kind.EXCLAMATION)
	StaffReviewManager.queue.clear()
	room._process(0.0)
	assert_bool(marker(&"manager").active).is_false()

func test_markers_keep_their_size_on_screen_at_both_zooms() -> void:
	var m := marker(&"teller")
	room.camera.set_overview(false)
	assert_vector(m.scale * 8.0 * room.camera.zoom_factor()).is_equal_approx(Vector2(16, 16), Vector2(0.01, 0.01))
	room.camera.set_overview(true)
	assert_vector(m.scale * 8.0 * room.camera.zoom_factor()).is_equal_approx(Vector2(16, 16), Vector2(0.01, 0.01))

# --- zones and signs ---------------------------------------------------------------------

func test_the_four_zones_have_a_faint_floor_tint_and_a_sign() -> void:
	var names: Array[String] = []
	for zone in RoomZones.ZONES:
		var zone_name: String = zone["name"]
		names.append(zone_name)
		var tint: Color = zone["tint"]
		assert_float(tint.a).is_less_equal(0.2)
		# On the floor, never on the outer walls.
		var tiles: Rect2i = zone["tiles"]
		assert_int(tiles.position.x).is_greater_equal(1)
		assert_int(tiles.end.x).is_less_equal(RoomBuilder.ROOM_WIDTH - 1)
		assert_int(tiles.end.y).is_less_equal(RoomBuilder.ROOM_HEIGHT - 1)
	assert_array(names).contains_exactly(["VAULT", "MANAGER", "LOANS", "TELLERS"])
	assert_object(room.zones).is_not_null()
	assert_object(room.zones.get_parent()).is_same(room.room_layer)
	var sign_texts: Array[String] = []
	for sign_node in room.wall_signs:
		sign_texts.append(sign_node.text)
		assert_bool(sign_node.label.is_in_group(WorldText.GROUP)).is_true()
	assert_array(sign_texts).contains_exactly(["VAULT", "MANAGER", "LOANS", "TELLERS"])

func test_signs_stay_crisp_at_both_zooms() -> void:
	var sign_node := room.wall_signs[0]
	for overview: bool in [false, true]:
		room.camera.set_overview(overview)
		assert_float(absf(sign_node.label.get_global_transform_with_canvas().get_scale().y - 1.0)).is_less(0.01)

# --- floating numbers ---------------------------------------------------------------------

func newest_cluster() -> FeedbackFloaters.Cluster:
	return room.feedback._clusters[-1]

func test_a_gain_floats_up_in_green_and_a_loss_in_red() -> void:
	ScoreManager.add_shift_score(5)
	var cluster := newest_cluster()
	assert_str(cluster.lines["Score"].text).is_equal("+5 Score")
	assert_object(cluster.lines["Score"].get_theme_color("font_color")).is_equal(FeedbackFloaters.GAIN)
	cluster.age = 1.0
	ScoreManager.add_shift_score(-3)
	assert_str(newest_cluster().lines["Score"].text).is_equal("-3 Score")
	assert_object(newest_cluster().lines["Score"].get_theme_color("font_color")).is_equal(FeedbackFloaters.LOSS)

func test_a_label_rises_fades_and_frees_itself() -> void:
	ScoreManager.add_shift_score(5)
	var cluster := newest_cluster()
	var label: Label = cluster.lines["Score"]
	var start := cluster.position.y
	cluster.advance(0.3)
	var early := cluster.position.y
	assert_float(early).is_less(start)
	assert_float(cluster.modulate.a).is_equal(1.0)
	cluster.advance(0.5)
	assert_float(cluster.position.y).is_less(early)
	assert_float(cluster.modulate.a).is_less(1.0)
	cluster.advance(FeedbackFloaters.LIFETIME)
	await frames(2)
	assert_bool(is_instance_valid(cluster)).is_false()
	assert_bool(is_instance_valid(label)).is_false()
	assert_int(room.feedback.live_cluster_count()).is_equal(0)

func test_changes_that_arrive_together_cluster_instead_of_overlapping() -> void:
	ScoreManager.add_shift_score(5) # also moves XP
	ReputationManager.add_reputation(2)
	assert_int(room.feedback.live_cluster_count()).is_equal(1)
	var cluster := newest_cluster()
	assert_bool(cluster.lines.has("Score")).is_true()
	assert_bool(cluster.lines.has("Reputation")).is_true()
	var ys: Array[float] = []
	for label: Label in cluster.lines.values():
		var design: Rect2 = label.get_meta(WorldText.META_RECT)
		ys.append(design.end.y)
	ys.sort()
	for i in range(1, ys.size()):
		assert_float(ys[i] - ys[i - 1]).is_greater_equal(FeedbackFloaters.LINE_HEIGHT - 0.01)
	# Two changes to one statistic add up on its line.
	ScoreManager.add_shift_score(3)
	assert_str(cluster.lines["Score"].text).is_equal("+8 Score")

func test_floating_labels_run_while_a_desk_screen_pauses_the_game() -> void:
	get_tree().paused = true
	ScoreManager.add_shift_score(5)
	var cluster := newest_cluster()
	var age_before := cluster.age
	await frames(3)
	assert_float(cluster.age).is_greater(age_before)
	get_tree().paused = false

func test_the_overview_hides_highlights_and_floaters_but_keeps_markers_and_signs() -> void:
	clock_in()
	spawn()
	stand_at(room.teller_desk)
	assert_bool(highlight_shown(room.teller_desk)).is_true()
	assert_bool(room.feedback.visible).is_true()
	room.camera.set_overview(true)
	assert_bool(highlight_shown(room.teller_desk)).is_false()
	assert_bool(room.feedback.visible).is_false()
	assert_bool(marker(&"teller").active).is_true()
	assert_bool(marker(&"teller").is_visible_in_tree()).is_true()
	for sign_node in room.wall_signs:
		assert_bool(sign_node.is_visible_in_tree()).is_true()
	room.camera.set_overview(false)
	assert_bool(highlight_shown(room.teller_desk)).is_true()
	assert_bool(room.feedback.visible).is_true()

# --- nothing left behind ------------------------------------------------------------------

## How many nodes of each class are under `root`.
func node_census(root: Node) -> Dictionary:
	var counts := {}
	for node in root.find_children("*", "", true, false):
		var key := "%s (%s)" % [node.get_class(), node.get_parent().name]
		var seen: int = counts.get(key, 0)
		counts[key] = seen + 1
	return counts

func census_difference(earlier: Dictionary, later: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key: String in later:
		var now: int = later[key]
		var was: int = earlier.get(key, 0)
		var extra: int = now - was
		if extra > 0:
			lines.append("%s +%d" % [key, extra])
	return ", ".join(lines)

func test_no_node_is_left_behind_after_a_busy_day() -> void:
	await frames(3)
	var lines: Array[CustomerQueue] = [cq]
	lines.append_array(staff_lines())
	# The staff loan desks' walk-in applicants are characters in flight, not leftovers: stop them.
	for worker in room.loan_desk_workers:
		worker.active = false
	room._clear_loan_seats()
	await frames(2)
	var baseline := get_tree().get_node_count()
	var census_before := node_census(room)
	clock_in()
	for i in 4:
		serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 20.0))
		room._on_teller_screen_closed()
	Engine.time_scale = 8.0
	for i in 240:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	send_excess_to_vault()
	for line in lines:
		line.spawn_timer.stop()
		line.clear_lobby()
	room._clear_loan_seats()
	for i in 6:
		ScoreManager.add_shift_score(1)
		ReputationManager.add_reputation(1)
		for cluster in room.feedback._clusters:
			if is_instance_valid(cluster):
				cluster.advance(FeedbackFloaters.LIFETIME)
	await frames(4)
	assert_int(room.feedback.live_cluster_count()).is_equal(0)
	# Every shadow and outline belongs to a character that still exists.
	var fx_characters := get_tree().get_nodes_in_group(CharacterFx.GROUP)
	assert_int(room.find_children("*", "CharacterShadow", true, false).size()).is_equal(fx_characters.size())
	assert_int(room.find_children("*", "CharacterOutline", true, false).size()).is_equal(fx_characters.size())
	for node in fx_characters:
		assert_bool(node is CustomerNPC).override_failure_message("a customer was left behind").is_false()
	assert_int(get_tree().get_node_count()).override_failure_message("nodes left behind: " + census_difference(census_before, node_census(room))).is_less_equal(baseline)
