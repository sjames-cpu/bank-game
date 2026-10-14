extends "res://tests/support/teller_room_suite.gd"

## The room camera (RoomCamera): 2x follow view by default, clamped to the
## room, a 1x overview on the toggle_overview key (Z), world text that stays
## readable and crisp at both zooms (WorldText), and a UI that zoom never
## touches.

const WINDOW := Vector2i(1152, 648)

var camera: RoomCamera
var player: PlayerMovement
var hud: Hud
var _window_size_before: Vector2i

func before_test() -> void:
	# Measure what a player sees: the game's 1152x648 window, not the
	# headless default.
	_window_size_before = get_tree().root.size
	get_tree().root.size = WINDOW
	await super()
	camera = room.camera
	player = room.player
	hud = room.hud
	await get_tree().process_frame

func after_test() -> void:
	get_tree().root.size = _window_size_before
	await super()

# --- helpers -------------------------------------------------------------------

## Puts the player at `world_position` and snaps the camera straight there
## (no smoothing), as if they'd been standing there a while.
func place_player(world_position: Vector2) -> void:
	player.global_position = world_position
	camera.force_update_scroll()
	camera.reset_smoothing()
	camera.force_update_scroll()

## Steps back to the spawn point, then stands just below `desk` so its area
## sees a fresh entry, and lets the room place the prompt.
func stand_at(desk: Node2D) -> void:
	place_player(Vector2(384, 624))
	for i in 2:
		await get_tree().physics_frame
	place_player(desk.global_position + Vector2(0, 30))
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

## `world_rect` on screen at the current camera.
func to_screen(world_rect: Rect2) -> Rect2:
	var canvas := get_viewport().get_canvas_transform()
	return Rect2(canvas * world_rect.position, world_rect.size * canvas.get_scale())

func player_screen_rect() -> Rect2:
	return to_screen(Rect2(player.global_position - Vector2(8, 12), Vector2(16, 24)))

## On-screen font size of a world label, and how many screen pixels each of
## its texels covers (1.0 = crisp).
func screen_font_px(label: Label) -> float:
	return label.get_theme_font_size("font_size") * texel_scale(label)

func texel_scale(label: Label) -> float:
	return label.get_global_transform_with_canvas().get_scale().y

## The label's bottom-centre point relative to its character (where
## WorldText anchors it), and where its 1x design puts that point.
func anchor_of(label: Label) -> Vector2:
	return label.position + Vector2(label.size.x / 2.0, label.size.y) * label.scale

func design_anchor(label: Label) -> Vector2:
	var design: Rect2 = label.get_meta(WorldText.META_RECT)
	return Vector2(design.get_center().x, design.end.y)

func every_zoom() -> Array[float]:
	return [RoomCamera.FOLLOW_ZOOM, RoomCamera.OVERVIEW_ZOOM]

# --- zoom and bounds -------------------------------------------------------------

func test_default_zoom_is_2x_following_the_player() -> void:
	assert_vector(camera.zoom).is_equal(Vector2(2, 2))
	assert_bool(camera.is_overview).is_false()
	assert_bool(camera.position_smoothing_enabled).is_true()
	assert_object(camera.get_parent()).is_same(player)
	assert_vector(Vector2(get_viewport().get_visible_rect().size)).is_equal(Vector2(WINDOW))

func test_the_camera_stays_inside_the_room_everywhere() -> void:
	var bounds := room.room_bounds()
	# The room and the sidewalk outside it: 24 x 24 tiles of 32px.
	assert_object(bounds).is_equal(Rect2(0, 0, 768, 768))
	var tile := 32.0
	for zoom in every_zoom():
		camera.set_overview(zoom == RoomCamera.OVERVIEW_ZOOM)
		for tx in 24:
			for ty in 23:
				place_player(Vector2((tx + 0.5) * tile, (ty + 0.5) * tile))
				var view := camera.visible_world_rect()
				var where := "zoom %s at tile (%d, %d): view %s" % [zoom, tx, ty, view]
				# Vertically the view always fits inside the room.
				assert_bool(view.position.y >= bounds.position.y - 0.5 and view.end.y <= bounds.end.y + 0.5).override_failure_message(where).is_true()
				if view.size.x <= bounds.size.x:
					# 2x: no empty space past the walls either side.
					assert_bool(view.position.x >= bounds.position.x - 0.5 and view.end.x <= bounds.end.x + 0.5).override_failure_message(where).is_true()
				else:
					# 1x is wider than the room: the room sits in the middle.
					assert_float(view.get_center().x).override_failure_message(where).is_equal_approx(bounds.get_center().x, 1.0)

func test_the_toggle_switches_to_the_overview_and_back() -> void:
	assert_str(InputPrompts.key_for(InputPrompts.OVERVIEW)).is_equal("Z")
	var zooms: Array[float] = []
	camera.zoom_changed.connect(func(factor: float) -> void: zooms.append(factor))
	# While walking.
	Input.action_press("move_right")
	for expected: float in [RoomCamera.OVERVIEW_ZOOM, RoomCamera.FOLLOW_ZOOM, RoomCamera.OVERVIEW_ZOOM]:
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_Z
			key.pressed = pressed
			get_viewport().push_input(key)
		await get_tree().process_frame
		assert_float(camera.zoom.x).is_equal(expected)
	Input.action_release("move_right")
	assert_array(zooms).is_equal([1.0, 2.0, 1.0])
	assert_bool(camera.is_overview).is_true()
	# Key repeat doesn't flicker it.
	var held := InputEventKey.new()
	held.keycode = KEY_Z
	held.pressed = true
	held.echo = true
	get_viewport().push_input(held)
	assert_bool(camera.is_overview).is_true()

func test_the_arrival_hint_names_the_overview_key() -> void:
	assert_str(HintManager.text_for(HintManager.Hint.ARRIVAL)).contains("Press Z to zoom out")

# --- world text --------------------------------------------------------------------

func test_world_text_stays_readable_and_crisp_at_both_zooms() -> void:
	var npc: StaffNPC = room._staff_by_slot.values()[0]
	npc.say("All set — have a nice day!")
	clock_in()
	var customer := spawn()
	customer.say("Withdraw $200, please.")
	var labels: Array[Label] = [
		npc.get_node("NameLabel") as Label,
		npc.get_node("SpeechLabel") as Label,
		customer.get_node("FarewellLabel") as Label,
	]
	for zoom in every_zoom():
		camera.set_overview(zoom == RoomCamera.OVERVIEW_ZOOM)
		await get_tree().process_frame
		for i in labels.size():
			var label := labels[i]
			var where := "%s at %sx" % [label.name, zoom]
			# Drawn one texel per screen pixel: crisp, not magnified.
			assert_float(texel_scale(label)).override_failure_message(where).is_equal_approx(1.0, 0.001)
			# 11-12px at 1x, 14-15px at 2x: readable, never doubled.
			var font_px := screen_font_px(label)
			assert_float(font_px).override_failure_message("%s: %spx" % [where, font_px]).is_between(10.0, 15.0)
			# A sensible size on screen.
			var on_screen := to_screen(Rect2(label.global_position, label.size * label.get_global_transform().get_scale()))
			assert_float(on_screen.size.x).override_failure_message(where).is_less_equal(200.0)
			assert_float(on_screen.size.y).override_failure_message(where).is_less_equal(90.0)
			# Still in the same place above the character.
			assert_vector(anchor_of(label)).override_failure_message(where).is_equal_approx(design_anchor(label), Vector2(0.5, 0.5))
	# Text grows a little with the characters at 2x, but stays smaller relative
	# to them than at 1x.
	camera.set_overview(false)
	var at_2x := screen_font_px(labels[0])
	camera.set_overview(true)
	var at_1x := screen_font_px(labels[0])
	assert_float(at_2x).is_greater(at_1x)
	assert_float(at_2x).is_less(at_1x * 2.0)

func test_new_staff_and_customers_get_the_current_zoom() -> void:
	camera.set_overview(true)
	clock_in()
	var customer := spawn()
	assert_float(texel_scale(customer.get_node("FarewellLabel") as Label)).is_equal_approx(1.0, 0.001)
	ScheduleManager.confirm_schedule(ScheduleManager.schedule) # re-places every StaffNPC
	await get_tree().process_frame
	var npc: StaffNPC = room._staff_by_slot.values()[0]
	assert_float(texel_scale(npc.get_node("NameLabel") as Label)).is_equal_approx(1.0, 0.001)
	assert_float(screen_font_px(npc.get_node("NameLabel") as Label)).is_equal_approx(11.0, 0.5)

# --- prompt and desks -------------------------------------------------------------------

func test_the_prompt_never_covers_the_player() -> void:
	XPManager._grant_branch_manager()
	var letters := room.letter_screen
	while letters.visible:
		letters.action_button.pressed.emit()
	for zoom in every_zoom():
		camera.set_overview(zoom == RoomCamera.OVERVIEW_ZOOM)
		for desk: Interactable in [room.teller_desk, room.loan_officer_desk, room.branch_manager_desk, room.atm]:
			await stand_at(desk)
			assert_object(room.interactable_in_range()).is_same(desk)
			assert_bool(hud.prompt_panel.visible).is_true()
			var prompt_rect := hud.prompt_panel.get_global_rect()
			assert_bool(prompt_rect.intersects(player_screen_rect())) \
				.override_failure_message("%s at %sx: prompt %s covers the player %s" % [desk.name, zoom, prompt_rect, player_screen_rect()]) \
				.is_false()
			# And it's on screen.
			assert_bool(get_viewport().get_visible_rect().encloses(prompt_rect)).override_failure_message("%s at %sx" % [desk.name, zoom]).is_true()

func test_standing_at_a_desk_shows_the_desk_counter_and_line() -> void:
	var lines := {
		room.teller_desk: room.customer_queue,
		room.get_node("TellerWindow1"): room.window1_npc_line,
		room.get_node("TellerWindow2"): room.window2_line,
	}
	for desk: Node2D in [room.teller_desk, room.get_node("TellerWindow1"), room.get_node("TellerWindow2"), room.loan_officer_desk, room.atm]:
		place_player(desk.global_position + Vector2(0, 30))
		var view := camera.visible_world_rect()
		assert_bool(view.has_point(desk.global_position)).override_failure_message("%s off screen" % desk.name).is_true()
		var spot := desk.get_node_or_null("StaffSpot") as Node2D
		if spot != null:
			assert_bool(view.has_point(spot.global_position)).override_failure_message("%s counter spot off screen" % desk.name).is_true()
		if lines.has(desk):
			var line: CustomerQueue = lines[desk]
			var front := line.queue_positions[0].global_position
			assert_bool(view.has_point(front)).override_failure_message("%s front of the line %s off screen %s" % [desk.name, front, view]).is_true()

# --- the UI doesn't zoom ----------------------------------------------------------------

func test_ui_layers_are_unaffected_by_zoom() -> void:
	room.teller_screen.show_screen(null)
	room.letter_screen._on_probation_completed()
	for i in 4:
		await get_tree().process_frame
	var controls: Array[Control] = [
		hud.get_node("RightColumn/StatsPanel") as Control,
		room.teller_screen.get_node("Panel") as Control,
		room.letter_screen.letter_panel,
	]
	var rects: Array[Rect2] = []
	for control in controls:
		rects.append(control.get_global_rect())
	camera.set_overview(true)
	for i in 4:
		await get_tree().process_frame
	for i in controls.size():
		assert_object(controls[i].get_global_rect()).override_failure_message(str(controls[i].get_path())).is_equal(rects[i])
	# The day/night tint is a colour, not a transform: zoom leaves it alone.
	var tint := room.get_node_or_null("DayNightCycle") as CanvasModulate
	if tint != null:
		var colour := tint.color
		camera.set_overview(false)
		assert_object(tint.color).is_equal(colour)
