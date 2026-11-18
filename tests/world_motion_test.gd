extends "res://tests/support/shared/character_fx_suite.gd"

## The rest of the world's motion (stage 2a): the bubbles popping in and
## pulsing (PatienceIndicator, WorldText's speech lines), the camera easing
## between 2x and 1x (RoomCamera), and the soft glows on the ATM and the vault
## door while they're in use (UseGlow). The shared test base runs with Effects
## Off; these turn them on, and check Off too.

func effects_on() -> void:
	use_test_settings(true)

func make_bubble() -> PatienceIndicator:
	var bubble := PatienceIndicator.new()
	bubble.position = Vector2(0.0, -20.0)
	room.add_child(bubble)
	return bubble

# --- the impatience bubble -----------------------------------------------------------------------

func test_the_impatience_bubble_pops_in_by_whole_pixels_and_finishes() -> void:
	effects_on()
	var bubble := make_bubble()
	var rest := bubble.position.y
	bubble.set_urgency(0.5)
	assert_int(bubble.stage).is_equal(PatienceIndicator.Stage.WAITING)
	assert_bool(bubble.is_animating()).is_true()
	assert_int(bubble.pop_offset()).is_equal(PatienceIndicator.POP_PIXELS)
	var seen: Array[int] = []
	for i in 14:
		bubble._process(0.02)
		var lowered := bubble.position.y - rest
		assert_float(lowered).is_equal(float(bubble.pop_offset()))
		assert_float(lowered).is_equal(floorf(lowered))
		assert_bool(lowered >= 0.0 and lowered <= 2.0).is_true()
		if seen.is_empty() or seen[-1] != bubble.pop_offset():
			seen.append(bubble.pop_offset())
	# 2, then 1, then 0: rising, never going back down.
	assert_array(seen).is_equal([2, 1, 0])
	bubble._process(0.3)
	assert_bool(bubble.is_animating()).is_false()
	assert_float(bubble.position.y).is_equal(rest)
	assert_that(bubble.modulate).is_equal(Color.WHITE)
	assert_bool(bubble.is_processing()).is_false()

func test_the_bubble_pulses_when_the_stage_changes_and_does_not_pop_again() -> void:
	effects_on()
	var bubble := make_bubble()
	var rest := bubble.position.y
	bubble.set_urgency(0.5)
	bubble._process(0.5)
	assert_bool(bubble.is_animating()).is_false()
	bubble.set_urgency(0.7)
	assert_int(bubble.stage).is_equal(PatienceIndicator.Stage.IMPATIENT)
	assert_bool(bubble.is_animating()).is_true()
	assert_int(bubble.pop_offset()).override_failure_message("a stage change shouldn't pop the bubble again").is_equal(0)
	assert_float(bubble.position.y).is_equal(rest)
	# A brightening that fades back to white.
	assert_float(bubble.modulate.r).is_greater(1.2)
	bubble._process(0.12)
	var midway := bubble.modulate.r
	assert_float(midway).is_between(1.0, PatienceIndicator.PULSE_COLOUR.r)
	bubble._process(0.2)
	assert_that(bubble.modulate).is_equal(Color.WHITE)
	assert_bool(bubble.is_animating()).is_false()

func test_the_bubble_just_snaps_with_effects_off() -> void:
	use_test_settings(false)
	var bubble := make_bubble()
	var rest := bubble.position.y
	bubble.set_urgency(0.5)
	assert_bool(bubble.visible).is_true()
	assert_bool(bubble.is_animating()).is_false()
	assert_float(bubble.position.y).is_equal(rest)
	assert_that(bubble.modulate).is_equal(Color.WHITE)
	bubble.set_urgency(0.9)
	assert_bool(bubble.is_animating()).is_false()
	assert_that(bubble.modulate).is_equal(Color.WHITE)

func test_the_bubble_stops_where_it_is_while_the_game_is_paused() -> void:
	effects_on()
	var bubble := make_bubble()
	bubble.set_urgency(0.5)
	bubble._process(0.06)
	var lowered := bubble.pop_offset()
	get_tree().paused = true
	await frames(30)
	assert_int(bubble.pop_offset()).is_equal(lowered)
	assert_bool(bubble.is_animating()).is_true()
	get_tree().paused = false
	await frames(30)
	assert_bool(bubble.is_animating()).is_false()

func test_turning_effects_off_finishes_a_bubble_at_once() -> void:
	effects_on()
	var bubble := make_bubble()
	bubble.set_urgency(0.5)
	use_test_settings(false)
	bubble._process(0.01)
	assert_bool(bubble.is_animating()).is_false()
	assert_int(bubble.pop_offset()).is_equal(0)

# --- speech lines -----------------------------------------------------------------------------------

func test_a_speech_line_pops_in_by_whole_pixels_and_settles() -> void:
	effects_on()
	var staff: StaffNPC = room.window1_npc_line.staff_npc
	var label: Label = staff.get_node("SpeechLabel")
	label.visible = false
	CharacterMotionDriver.popping.clear()
	staff.say("Hi! How can I help?")
	assert_bool(CharacterMotionDriver.popping.has(label)).is_true()
	assert_int(WorldText.pop_offset(label)).is_equal(WorldText.POP_PIXELS)
	var rest_y := label.position.y - float(WorldText.POP_PIXELS)
	var seen: Array[int] = []
	for i in 12:
		CharacterMotionDriver.advance(0.02)
		var lowered := label.position.y - rest_y
		assert_float(lowered).is_equal_approx(float(WorldText.pop_offset(label)), 0.001)
		if seen.is_empty() or seen[-1] != WorldText.pop_offset(label):
			seen.append(WorldText.pop_offset(label))
	assert_array(seen).is_equal([2, 1, 0])
	assert_bool(CharacterMotionDriver.popping.has(label)).is_false()
	assert_float(label.position.y).is_equal_approx(rest_y, 0.001)

func test_a_customers_line_pops_too_and_a_hidden_line_never_does() -> void:
	effects_on()
	clock_in()
	var customer := spawn()
	var label: Label = customer.get_node("FarewellLabel")
	assert_bool(CharacterMotionDriver.popping.has(label)).is_false()
	customer.say("Deposit $500, please.")
	assert_bool(CharacterMotionDriver.popping.has(label)).is_true()
	for i in 12:
		CharacterMotionDriver.advance(0.02)
	assert_bool(CharacterMotionDriver.popping.has(label)).is_false()
	assert_int(WorldText.pop_offset(label)).is_equal(0)

func test_a_speech_line_just_appears_with_effects_off() -> void:
	use_test_settings(false)
	var staff: StaffNPC = room.window1_npc_line.staff_npc
	var label: Label = staff.get_node("SpeechLabel")
	label.visible = false
	staff.say("Hi!")
	assert_bool(label.visible).is_true()
	assert_bool(CharacterMotionDriver.popping.has(label)).is_false()
	assert_int(WorldText.pop_offset(label)).is_equal(0)

func test_a_pop_never_leaves_a_line_lowered_when_effects_go_off() -> void:
	effects_on()
	var staff: StaffNPC = room.window1_npc_line.staff_npc
	var label: Label = staff.get_node("SpeechLabel")
	label.visible = false
	staff.say("Hi!")
	assert_int(WorldText.pop_offset(label)).is_equal(2)
	EffectsSetting.set_on(false, false)
	assert_int(WorldText.pop_offset(label)).is_equal(0)
	assert_bool(CharacterMotionDriver.popping.has(label)).is_false()

# --- the camera ---------------------------------------------------------------------------------------

## The limits the room clamp should give at this zoom (RoomCamera._update_limits()).
func expected_limits(camera: RoomCamera) -> Rect2i:
	var bounds := camera.room_bounds
	var view := camera.get_viewport_rect().size / camera.zoom
	var centre := bounds.get_center()
	var left := floori(bounds.position.x) if view.x <= bounds.size.x else floori(centre.x - view.x / 2.0)
	var right := ceili(bounds.end.x) if view.x <= bounds.size.x else ceili(centre.x + view.x / 2.0)
	var top := floori(bounds.position.y) if view.y <= bounds.size.y else floori(centre.y - view.y / 2.0)
	var bottom := ceili(bounds.end.y) if view.y <= bounds.size.y else ceili(centre.y + view.y / 2.0)
	return Rect2i(left, top, right - left, bottom - top)

func limits_of(camera: RoomCamera) -> Rect2i:
	return Rect2i(camera.limit_left, camera.limit_top, camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)

func test_the_zoom_toggle_eases_between_2x_and_1x_and_ends_exactly() -> void:
	effects_on()
	var camera := room.camera
	var zoom_events: Array[float] = []
	camera.zoom_changed.connect(func(factor: float) -> void: zoom_events.append(factor))
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	camera.toggle_overview()
	# The state is the overview straight away; the zoom is on its way.
	assert_bool(camera.is_overview).is_true()
	assert_bool(camera.is_easing()).is_true()
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	assert_int(zoom_events.size()).is_equal(0)
	var zooms: Array[float] = []
	var guard := 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		zooms.append(camera.zoom.x)
		# The clamp to the room holds at every step.
		assert_object(limits_of(camera)).is_equal(expected_limits(camera))
		guard += 1
	assert_bool(camera.is_easing()).is_false()
	assert_vector(camera.zoom).is_equal(Vector2(1, 1))
	assert_array(zoom_events).is_equal([1.0])
	assert_int(zooms.size()).is_greater(3)
	# Falling the whole way from 2 to 1, never outside it, never going back.
	for i in zooms.size():
		assert_bool(zooms[i] >= 1.0 and zooms[i] <= 2.0).is_true()
		if i > 0:
			assert_bool(zooms[i] <= zooms[i - 1] + 0.0001).is_true()
	# And back.
	camera.toggle_overview()
	guard = 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		guard += 1
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	assert_bool(camera.is_overview).is_false()
	assert_array(zoom_events).is_equal([1.0, 2.0])
	assert_object(limits_of(camera)).is_equal(expected_limits(camera))

func test_the_view_stays_inside_the_room_all_the_way_through_the_ease() -> void:
	effects_on()
	var camera := room.camera
	room.player.position = Vector2(60, 120)
	camera.reset_smoothing()
	camera.toggle_overview()
	var guard := 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		var view := camera.visible_world_rect()
		var bounds := camera.room_bounds
		# On an axis where the view fits inside the room it never shows past it.
		if view.size.y <= bounds.size.y:
			assert_bool(view.position.y >= bounds.position.y - 1.0 and view.end.y <= bounds.end.y + 1.0).override_failure_message("the view %s left the room %s" % [view, bounds]).is_true()
		if view.size.x <= bounds.size.x:
			assert_bool(view.position.x >= bounds.position.x - 1.0 and view.end.x <= bounds.end.x + 1.0).override_failure_message("the view %s left the room %s" % [view, bounds]).is_true()
		guard += 1
	assert_vector(camera.zoom).is_equal(Vector2(1, 1))

func test_the_overview_hides_highlights_and_numbers_only_when_the_ease_ends() -> void:
	effects_on()
	var camera := room.camera
	var highlight: InteractableHighlight = room._interactables()[0].highlight
	assert_bool(highlight.in_overview).is_false()
	camera.toggle_overview()
	await frames(2)
	assert_bool(camera.is_easing()).is_true()
	assert_bool(highlight.in_overview).override_failure_message("switched before the ease ended").is_false()
	var guard := 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		guard += 1
	assert_bool(highlight.in_overview).is_true()
	assert_bool(room.feedback.visible).is_false()
	camera.toggle_overview()
	guard = 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		guard += 1
	assert_bool(highlight.in_overview).is_false()
	assert_bool(room.feedback.visible).is_true()

func test_toggling_again_mid_ease_turns_around_and_still_ends_exactly() -> void:
	effects_on()
	var camera := room.camera
	camera.toggle_overview()
	await frames(4)
	assert_bool(camera.is_easing()).is_true()
	camera.toggle_overview()
	var guard := 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		guard += 1
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	assert_bool(camera.is_overview).is_false()

func test_with_effects_off_the_camera_jumps_at_once() -> void:
	use_test_settings(false)
	var camera := room.camera
	var zoom_events: Array[float] = []
	camera.zoom_changed.connect(func(factor: float) -> void: zoom_events.append(factor))
	camera.toggle_overview()
	assert_vector(camera.zoom).is_equal(Vector2(1, 1))
	assert_bool(camera.is_easing()).is_false()
	assert_array(zoom_events).is_equal([1.0])
	assert_object(limits_of(camera)).is_equal(expected_limits(camera))
	camera.toggle_overview()
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	assert_array(zoom_events).is_equal([1.0, 2.0])

func test_turning_effects_off_mid_ease_arrives_at_once() -> void:
	effects_on()
	var camera := room.camera
	camera.toggle_overview()
	await frames(3)
	assert_bool(camera.is_easing()).is_true()
	use_test_settings(false)
	await frames(2)
	assert_bool(camera.is_easing()).is_false()
	assert_vector(camera.zoom).is_equal(Vector2(1, 1))

func test_the_ease_holds_while_the_game_is_paused() -> void:
	effects_on()
	var camera := room.camera
	camera.toggle_overview()
	await frames(3)
	var factor := camera.zoom.x
	get_tree().paused = true
	await frames(30)
	assert_float(camera.zoom.x).is_equal(factor)
	get_tree().paused = false
	var guard := 0
	while camera.is_easing() and guard < 200:
		await frames(1)
		guard += 1
	assert_vector(camera.zoom).is_equal(Vector2(1, 1))

# --- glows ---------------------------------------------------------------------------------------------

func test_the_atm_glows_while_its_screen_is_open() -> void:
	effects_on()
	var glow := room.use_glows[&"atm"]
	assert_bool(glow.is_shown()).is_false()
	assert_bool(glow.visible).is_false()
	assert_bool(glow.is_processing()).is_false()
	room.atm_screen.visible = true
	assert_bool(room.atm_in_use()).is_true()
	assert_bool(glow.is_shown()).is_true()
	assert_bool(glow.visible).is_true()
	assert_bool(glow.is_processing()).is_true()
	room.atm_screen.visible = false
	assert_bool(glow.is_shown()).is_false()
	assert_bool(glow.visible).is_false()
	assert_bool(glow.is_processing()).is_false()

func test_the_vault_door_glows_for_the_witness_the_screen_and_the_truck() -> void:
	effects_on()
	var glow := room.use_glows[&"vault"]
	assert_bool(glow.is_shown()).is_false()
	# The vault's screen.
	room.vault_transfer_screen.visible = true
	assert_bool(glow.is_shown()).is_true()
	room.vault_transfer_screen.visible = false
	assert_bool(glow.is_shown()).is_false()
	# The armored truck's crew here, from walking in until they begin to leave.
	for phase: ArmoredTruckVisit.Phase in [ArmoredTruckVisit.Phase.WALKING_IN, ArmoredTruckVisit.Phase.WAITING, ArmoredTruckVisit.Phase.BEING_RECEIVED]:
		room.armored_visit.phase = phase
		room.update_use_glows()
		assert_bool(glow.is_shown()).override_failure_message("no glow for the truck in phase %s" % phase).is_true()
	for phase: ArmoredTruckVisit.Phase in [ArmoredTruckVisit.Phase.IDLE, ArmoredTruckVisit.Phase.LEAVING]:
		room.armored_visit.phase = phase
		room.update_use_glows()
		assert_bool(glow.is_shown()).override_failure_message("a glow for the truck in phase %s" % phase).is_false()
	# The witness walking over.
	clock_in()
	call_vault_witness()
	assert_bool(room.vault_control.is_busy()).is_true()
	room.update_use_glows()
	assert_bool(glow.is_shown()).is_true()
	room.vault_transfer_screen.visible = false
	room.vault_control.finish()
	room.update_use_glows()
	assert_bool(glow.is_shown()).is_false()

func test_the_doormat_never_glows() -> void:
	effects_on()
	# Only the ATM and the vault door have in-use glows; the doormat's E only
	# explains (on a slot day it says going home is on the card).
	assert_int(room.use_glows.size()).is_equal(2)
	assert_bool(room.use_glows.has(&"doormat")).is_false()
	assert_object(room.exit_door.get_node_or_null("UseGlow")).is_null()
	for glow: UseGlow in room.use_glows.values():
		assert_object(glow.source).is_not_null()

func test_a_glow_is_steady_with_effects_off_and_pulses_with_them_on() -> void:
	use_test_settings(false)
	var glow := room.use_glows[&"atm"]
	room.atm_screen.visible = true
	glow._process(0.0)
	assert_float(glow.modulate.a).is_equal_approx(UseGlow.STEADY_ALPHA, 0.0001)
	glow._process(0.5)
	assert_float(glow.modulate.a).is_equal_approx(UseGlow.STEADY_ALPHA, 0.0001)
	effects_on()
	glow._process(0.0)
	assert_float(glow.modulate.a).is_between(UseGlow.MIN_ALPHA, 1.0)
	room.atm_screen.visible = false

func test_a_glow_is_drawn_in_whole_pixels_behind_the_machine() -> void:
	for ring in UseGlow.RINGS:
		assert_float(ring.x).is_equal(floorf(ring.x))
		assert_bool(ring.x >= 1.0 and ring.x <= 2.0).is_true()
	for direction in UseGlow.DIRECTIONS:
		assert_bool(absf(direction.x) <= 1.0 and absf(direction.y) <= 1.0).is_true()
	for glow: UseGlow in room.use_glows.values():
		assert_bool(glow.show_behind_parent).is_true()
		assert_bool(glow.get_parent() is Sprite2D).is_true()

func test_a_glow_shows_while_the_game_is_paused_because_its_screen_pauses_it() -> void:
	effects_on()
	var glow := room.use_glows[&"atm"]
	room.atm_screen.visible = true
	get_tree().paused = true
	await frames(3)
	assert_bool(glow.visible).is_true()
	get_tree().paused = false
	room.atm_screen.visible = false

func test_highlights_and_markers_hold_steady_with_effects_off() -> void:
	use_test_settings(false)
	var desk: Interactable = room.teller_desk
	var highlight := desk.highlight
	highlight.set_wanted(true)
	highlight._process(0.0)
	var alpha := highlight.modulate.a
	assert_float(alpha).is_equal_approx(InteractableHighlight.STEADY_ALPHA, 0.0001)
	highlight._process(0.4)
	assert_float(highlight.modulate.a).is_equal(alpha)
	highlight.set_wanted(false)
	var marker: AttentionMarker = room.attention_markers[&"teller"]
	marker.set_active(true)
	var rest := marker.position.y
	marker._process(0.0)
	assert_float(marker.position.y).is_equal(rest)
	marker.set_active(false)
