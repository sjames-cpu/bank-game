extends "res://tests/support/teller_room_suite.gd"

## B4: the always-on HUD (hud.gd), the interaction prompt, the first-run
## hints (HintManager) and the player's spawn point.

const Hint := HintManager.Hint

var hud: Hud
var player: CharacterBody2D
var letters: DisciplineLetterScreen

func before_test() -> void:
	await super()
	_bind_room()

func _bind_room() -> void:
	hud = room.get_node("HUD")
	player = room.get_node("Player")
	letters = room.get_node("UI/DisciplineLetterScreen")

# --- helpers -------------------------------------------------------------------

## Puts the player just in front of (below) `node` and lets physics register
## the overlap, then a frame so the room refreshes the prompt.
## Steps back to the spawn point first, so the desk's area always sees a
## fresh entry.
func stand_at(node: Node2D) -> void:
	player.global_position = Vector2(384, 624)
	for i in 2:
		await get_tree().physics_frame
	player.global_position = node.global_position + Vector2(0, 30)
	await settle()

func unlock_loan_officer() -> void:
	XPManager.add_shift_xp(ceili(float(XPManager.XP_UNLOCK_THRESHOLD) / XPManager.XP_PER_SCORE_POINT))

func settle() -> void:
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

func prompt() -> String:
	return hud.prompt_label.text if hud.prompt_panel.visible else ""

func press_interact(desk: Area2D) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.pressed = true
	desk._unhandled_input(event)

func acknowledge_letters() -> void:
	while letters.visible:
		letters.action_button.pressed.emit()

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

func dismiss_all_hints() -> void:
	while hud.current_hint != -1:
		hud.hint_dismiss_button.pressed.emit()

## Serves a full shift's customers (the per-shift cap) so clock-out is allowed.
func serve_whole_shift() -> void:
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		serve_correctly(spawn())

func staff_name(slot_name: String) -> String:
	return ScheduleManager.get_assigned(slot_name).staff_name

# --- HUD -------------------------------------------------------------------------

func test_hud_shows_career_values_with_no_screen_open() -> void:
	await settle()
	assert_bool(hud.visible).is_true()
	assert_bool(hud.stats_panel.is_visible_in_tree()).is_true()
	assert_str(hud.role_label.text).is_equal("Role: Teller")
	assert_str(hud.score_label.text).is_equal("Score: 0")
	assert_str(hud.reputation_label.text).is_equal("Reputation: 50")
	assert_str(hud.xp_label.text).is_equal("XP: 0")
	assert_str(hud.reports_label.text).is_equal("Reports: 0 / 3")
	assert_str(hud.shift_label.text).is_equal("Off shift")

	ScoreManager.add_shift_score(7)
	ReputationManager.add_reputation(-4)
	XPManager.add_shift_xp(3)
	await settle()
	assert_str(hud.score_label.text).is_equal("Score: 7")
	assert_str(hud.reputation_label.text).is_equal("Reputation: 46")
	assert_str(hud.xp_label.text).is_equal("XP: 30")

func test_hud_stays_visible_and_live_while_the_teller_screen_is_open() -> void:
	clock_in()
	open_desk()
	await settle()
	assert_bool(get_tree().paused).is_true()
	assert_bool(hud.visible).is_true()
	assert_bool(hud.stats_panel.is_visible_in_tree()).is_true()
	assert_str(hud.shift_label.text).is_equal("On shift — Player Teller Window · 4 customers left")
	close_desk()

	var customer := spawn()
	open_desk()
	deposit(customer.intent_amount_cents / 100.0)
	complete()
	await settle()
	# Still open (paused), already showing the graded request.
	assert_bool(ts.visible).is_true()
	assert_str(hud.score_label.text).is_equal("Score: %d" % TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE)
	assert_str(hud.xp_label.text).is_equal("XP: %d" % (TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(hud.shift_label.text).is_equal("On shift — Player Teller Window · 3 customers left")
	close_desk()

func test_hud_shift_status_for_loan_desk_and_branch_manager_office() -> void:
	XPManager.add_shift_xp(50)
	var loan: LoanOfficerScreen = room.loan_officer_screen
	loan.show_screen()
	loan.clock_in_button.pressed.emit()
	await settle()
	assert_str(hud.shift_label.text).is_equal("On shift — Loan Desk · 3 applications left")
	loan.hide_screen()

	promote()
	var bm: BranchManagerScreen = room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters() # orientation
	await settle()
	assert_str(hud.shift_label.text).contains("Branch Manager office · vault not reconciled yet")

func test_hud_role_and_reports_follow_the_career() -> void:
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "A")
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "B")
	await settle()
	assert_str(hud.reports_label.text).is_equal("Reports: 1 / 3")

	unlock_loan_officer()
	await settle()
	assert_str(hud.role_label.text).is_equal("Role: Loan Officer")

	promote()
	await settle()
	assert_str(hud.role_label.text).is_equal("Role: Branch Manager")
	assert_str(hud.reports_label.text).is_equal("Reports: n/a (manager)")

func test_hud_hides_behind_the_termination_letter_only() -> void:
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "A")
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "B")
	await settle()
	assert_bool(letters.visible).is_true() # written warning
	assert_bool(hud.visible).is_true()
	acknowledge_letters()

	for i in 4:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "C%d" % i)
	await settle()
	assert_bool(letters.is_full_screen_letter_shown()).is_true()
	assert_bool(hud.visible).is_false()

## The HUD column (stats + a hint) sits right of every centred screen, letter,
## summary and notice in the 1152px-wide window — checked against each panel
## the room's UI layer can show, the Branch Manager summary with real content.
## The permanent controls line: key names from the InputMap, always shown,
## inside the 648px window and clear of the HUD column, every centred screen
## panel and letters, at either zoom.
func test_controls_line_names_the_keys_and_overlaps_nothing() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	await settle()
	assert_str(hud.controls_label.text).is_equal("E — interact · Z — zoom")
	assert_str(hud.controls_label.text).is_equal(Hud.controls_text())
	assert_bool(hud.controls_panel.is_visible_in_tree()).is_true()

	# The tallest the HUD column gets: a hint and every notification.
	hud._show_hint(Hint.BRANCH_MANAGER_UNLOCKED)
	hud.show_unlock_notification(hud.loan_officer_unlocked_label)
	hud.show_unlock_notification(hud.branch_manager_unlocked_label)
	ReputationManager.add_reputation(-100)
	# Every centred screen panel at once, and the long orientation letter.
	var ui: CanvasLayer = room.get_node("UI")
	var panels: Array[Control] = []
	for node in ui.find_children("*", "Control", true, false):
		var control := node as Control
		if (control is Panel or control is PanelContainer) and control.anchor_left == 0.5:
			panels.append(control)
	for panel in panels:
		var node: Node = panel
		while node != ui:
			(node as CanvasItem).visible = true
			node = node.get_parent()
	XPManager.has_seen_branch_orientation = false
	letters.show_branch_orientation_once()
	assert_int(panels.size()).is_greater(15)
	assert_bool(panels.has(letters.letter_panel)).is_true()
	for zoom: float in [RoomCamera.FOLLOW_ZOOM, RoomCamera.OVERVIEW_ZOOM]:
		room.camera.set_overview(zoom == RoomCamera.OVERVIEW_ZOOM)
		await settle()
		var controls := hud.controls_panel.get_global_rect()
		assert_bool(Rect2(0, 0, 1152, 648).encloses(controls)).override_failure_message("controls %s leave the window" % controls).is_true()
		var column := (hud.get_node("RightColumn") as Control).get_global_rect()
		assert_bool(controls.intersects(column)).override_failure_message("controls %s overlap the HUD column %s" % [controls, column]).is_false()
		for panel in panels:
			var rect := panel.get_global_rect()
			assert_bool(controls.intersects(rect)).override_failure_message("controls %s overlap %s (%s) at %sx" % [controls, panel.get_path(), rect, zoom]).is_false()
	get_tree().root.size = window_before

func test_hud_column_never_overlaps_a_screen_panel() -> void:
	assert_int(int(get_tree().root.get_visible_rect().size.x)).is_equal(1152)
	assert_int(hud.layer).is_greater((room.get_node("UI") as CanvasLayer).layer)
	promote()
	var bm: BranchManagerScreen = room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()
	bm._prepare_shift_summary()
	dismiss_all_hints()
	hud._show_hint(Hint.BRANCH_MANAGER_UNLOCKED) # the longest hint text
	# Every notification up at once: the tallest the column gets.
	hud.show_unlock_notification(hud.loan_officer_unlocked_label)
	hud.show_unlock_notification(hud.branch_manager_unlocked_label)
	ReputationManager.add_reputation(-100)
	acknowledge_letters()

	var ui: CanvasLayer = room.get_node("UI")
	var panels: Array[Control] = []
	for node in ui.find_children("*", "Control", true, false):
		var control := node as Control
		if (control is Panel or control is PanelContainer) and control.anchor_left == 0.5:
			panels.append(control)
	assert_int(panels.size()).is_greater(15)
	for panel in panels:
		var node: Node = panel
		while node != ui:
			(node as CanvasItem).visible = true
			node = node.get_parent()
	await settle()

	var column: Rect2 = (hud.get_node("RightColumn") as Control).get_global_rect()
	assert_bool(hud.hint_panel.visible).is_true()
	for label: Label in [hud.low_reputation_warning_label, hud.loan_officer_unlocked_label, hud.branch_manager_unlocked_label]:
		assert_bool(label.is_visible_in_tree()).is_true()
	for panel in panels:
		var rect := panel.get_global_rect()
		assert_bool(rect.intersects(column)) \
			.override_failure_message("%s (%s) overlaps the HUD column %s" % [panel.get_path(), rect, column]) \
			.is_false()
	# And the column itself fits in the 648px window.
	assert_float(column.end.y).is_less(648.0)

func test_notifications_show_on_the_hud_with_no_screen_open() -> void:
	await settle()
	assert_bool(ts.visible).is_false()
	assert_bool(hud.notification_panel.visible).is_false()

	ReputationManager.add_reputation(-ReputationManager.reputation)
	await settle()
	assert_bool(hud.notification_panel.is_visible_in_tree()).is_true()
	assert_bool(hud.low_reputation_warning_label.visible).is_true()
	assert_str(hud.low_reputation_warning_label.text).is_equal("Reputation critically low!")
	ReputationManager.add_reputation(50)
	await settle()
	assert_bool(hud.low_reputation_warning_label.visible).is_false()
	assert_bool(hud.notification_panel.visible).is_false()

	unlock_loan_officer()
	await settle()
	assert_bool(hud.loan_officer_unlocked_label.visible).is_true()
	assert_str(hud.loan_officer_unlocked_label.text).is_equal("Loan Officer role unlocked!")
	assert_bool(hud.branch_manager_unlocked_label.visible).is_false()

	promote()
	await settle()
	# Stacked, not replaced.
	assert_bool(hud.loan_officer_unlocked_label.visible).is_true()
	assert_bool(hud.branch_manager_unlocked_label.visible).is_true()
	assert_str(hud.branch_manager_unlocked_label.text).is_equal("Branch Manager role unlocked!")

	# Still up behind an open desk screen.
	room.branch_manager_screen.show_screen()
	await settle()
	assert_bool(hud.branch_manager_unlocked_label.is_visible_in_tree()).is_true()
	room.branch_manager_screen.hide_screen()

	# Unlock notifications go after their time (unlock_notification_test.gd
	# covers the timing).
	for tween: Tween in hud.unlock_tweens.values():
		tween.custom_step(Hud.UNLOCK_NOTIFICATION_SECONDS + Hud.UNLOCK_FADE_SECONDS + 0.1)
	await settle()
	assert_bool(hud.notification_panel.visible).is_false()

# --- interaction prompt --------------------------------------------------------------

## The prompt (in screen space) sits below `desk`, clear of the player standing
## there and of every staff member's name label.
func assert_prompt_clear_of_labels(desk: Node2D) -> void:
	var canvas := room.get_viewport().get_canvas_transform()
	var prompt_rect := hud.prompt_panel.get_global_rect()
	assert_bool(hud.prompt_panel.visible).is_true()
	assert_float(prompt_rect.position.y).is_greater((canvas * desk.global_position).y)
	var player_sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	var frame := player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, 0).get_size()
	var player_rect := canvas * Rect2(player.global_position - frame / 2.0, frame)
	assert_bool(prompt_rect.intersects(player_rect)) 		.override_failure_message("prompt %s covers the player %s" % [prompt_rect, player_rect]).is_false()
	var labels := 0
	for npc in room.staff_layer.get_children():
		var name_label: Label = npc.get_node("NameLabel")
		var label_rect := canvas * name_label.get_global_rect()
		labels += 1
		assert_bool(prompt_rect.intersects(label_rect)) 			.override_failure_message("prompt %s covers %s's name label %s" % [prompt_rect, name_label.text, label_rect]).is_false()
	assert_int(labels).is_greater(2)

func test_prompt_sits_below_the_desk_clear_of_name_labels() -> void:
	await stand_at(room.teller_desk) # next to Teller Window 1's staff member
	assert_prompt_clear_of_labels(room.teller_desk)
	await stand_at(room.loan_officer_desk) # staffed, locked
	assert_prompt_clear_of_labels(room.loan_officer_desk)
	await stand_at(room.atm)
	assert_prompt_clear_of_labels(room.atm)

	promote()
	dismiss_all_hints()
	await stand_at(room.teller_desk) # now Teller Window 3, staffed
	assert_prompt_clear_of_labels(room.teller_desk)
	await stand_at(room.loan_officer_desk)
	assert_prompt_clear_of_labels(room.loan_officer_desk)
	await stand_at(room.branch_manager_desk)
	assert_prompt_clear_of_labels(room.branch_manager_desk)

	# The gap is in room pixels, so it holds with the camera zoomed in.
	(player.get_node("Camera2D") as Camera2D).zoom = Vector2(2, 2)
	await stand_at(room.teller_desk)
	assert_prompt_clear_of_labels(room.teller_desk)

func test_prompt_key_matches_the_input_map() -> void:
	assert_bool(InputMap.has_action(InputPrompts.INTERACT)).is_true()
	var event := InputEventKey.new()
	event.keycode = KEY_E
	assert_bool(InputMap.action_has_event(InputPrompts.INTERACT, event)).is_true()
	assert_str(InputPrompts.key_for(InputPrompts.INTERACT)).is_equal("E")

	var fired := [0]
	room.teller_desk.interacted.connect(func() -> void: fired[0] += 1)
	await stand_at(room.teller_desk)
	assert_str(prompt()).starts_with("E — ")
	press_interact(room.teller_desk)
	assert_int(fired[0]).is_equal(1)
	close_desk()

	# The arrival hint names WASD and the arrow keys: both are bound to movement.
	var movement := {
		"move_up": [KEY_W, KEY_UP], "move_left": [KEY_A, KEY_LEFT],
		"move_down": [KEY_S, KEY_DOWN], "move_right": [KEY_D, KEY_RIGHT],
	}
	for action: String in movement:
		var bound: Array = []
		for e in InputMap.action_get_events(action):
			bound.append((e as InputEventKey).physical_keycode)
		for key: int in movement[action]:
			assert_array(bound).contains([key])

func test_prompt_at_the_player_teller_window_follows_the_shift() -> void:
	await settle()
	assert_str(prompt()).is_equal("") # at the spawn point, nothing in range

	await stand_at(room.teller_desk)
	assert_str(prompt()).is_equal("E — Clock in (Player Teller Window)")

	clock_in()
	await settle()
	assert_str(prompt()).is_equal("E — Serve customers (Player Teller Window)")

	open_desk()
	await settle()
	assert_bool(hud.prompt_panel.visible).is_false() # hidden behind an open screen
	close_desk()

	serve_whole_shift()
	await settle()
	assert_str(prompt()).is_equal("E — Clock out (Player Teller Window)")

func test_prompt_explains_the_locked_loan_desk() -> void:
	await stand_at(room.loan_officer_desk)
	assert_str(prompt()).is_equal("Loan Desk — unlocks at 500 XP and 40 Reputation")
	press_interact(room.loan_officer_desk)
	assert_bool(room.loan_officer_screen.visible).is_false()

	unlock_loan_officer()
	await settle()
	assert_str(prompt()).is_equal("E — Clock in (Loan Desk)")
	press_interact(room.loan_officer_desk)
	assert_bool(room.loan_officer_screen.visible).is_true()
	room.loan_officer_screen.clock_in_button.pressed.emit()
	room.loan_officer_screen.hide_screen()
	await settle()
	assert_str(prompt()).is_equal("E — Review applications (Loan Desk)")

func test_prompt_after_promotion_names_the_staff_and_the_office() -> void:
	await stand_at(room.branch_manager_desk)
	assert_str(prompt()).is_equal("") # hidden desk before promotion

	promote()
	dismiss_all_hints()
	await stand_at(room.branch_manager_desk)
	assert_str(prompt()).is_equal("E — Branch Manager desk")

	await stand_at(room.teller_desk)
	var window_staff := staff_name(ScheduleManager.SLOT_TELLER_WINDOW_3)
	assert_str(prompt()).is_equal("%s is working this window." % window_staff)
	# The notice on pressing E is unchanged.
	press_interact(room.teller_desk)
	assert_str(room.desk_notice_label.text).is_equal("%s is working this window. As Branch Manager, your desk is in the office." % window_staff)

	await stand_at(room.loan_officer_desk)
	assert_str(prompt()).is_equal("%s is working the Loan Desk." % staff_name(ScheduleManager.SLOT_LOAN_DESK))

func test_prompt_at_the_atm() -> void:
	await stand_at(room.atm)
	assert_str(prompt()).is_equal("E — Use ATM")
	player.global_position = Vector2(384, 624)
	await settle()
	assert_bool(hud.prompt_panel.visible).is_false()

# --- first-run hints -------------------------------------------------------------------

func test_arrival_hint_shows_once_per_career() -> void:
	await settle()
	assert_int(hud.current_hint).is_equal(Hint.ARRIVAL)
	assert_bool(hud.hint_panel.is_visible_in_tree()).is_true()
	assert_str(hud.hint_label.text).is_equal("Walk with WASD or the arrow keys. Go to your teller window and press E to clock in. Press Z to zoom out and see the whole branch.")
	assert_int(hud.hint_dismiss_button.focus_mode).is_equal(Control.FOCUS_NONE)
	hud.hint_dismiss_button.pressed.emit()
	assert_bool(hud.hint_panel.visible).is_false()

	# Same career, room loaded again: no repeat.
	await reload_room(false)
	assert_int(hud.current_hint).is_equal(-1)
	assert_bool(hud.hint_panel.visible).is_false()

	# New career: shown again.
	await reload_room(true)
	assert_int(hud.current_hint).is_equal(Hint.ARRIVAL)

func reload_room(new_career: bool) -> void:
	room.free()
	if new_career:
		CareerReset.reset_all()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	ts = room.get_node("UI/TellerScreen")
	cq = room.get_node("CustomerQueue")
	cq.spawn_timer.stop()
	_bind_room()
	await settle()

func test_first_customer_hint_shows_once() -> void:
	dismiss_all_hints()
	clock_in()
	assert_int(hud.current_hint).is_equal(-1)

	var first := spawn()
	open_desk()
	assert_int(hud.current_hint).is_equal(Hint.FIRST_CUSTOMER)
	assert_str(hud.hint_label.text).is_equal("Do what the customer asks, then press Complete Transaction.")
	close_desk()
	serve_correctly(first)
	hud.hint_dismiss_button.pressed.emit()

	spawn()
	open_desk()
	assert_int(hud.current_hint).is_equal(-1)
	close_desk()

func test_first_customer_hint_waits_for_a_regular_customer() -> void:
	dismiss_all_hints()
	clock_in()
	var complainer := spawn()
	complainer.complaint = CustomerComplaintsData.get_complaints()[0]
	open_desk()
	assert_int(hud.current_hint).is_equal(-1)
	assert_bool(HintManager.has_shown(Hint.FIRST_CUSTOMER)).is_false()
	close_desk()

func test_first_clock_out_hint_shows_once() -> void:
	dismiss_all_hints()
	clock_in()
	serve_whole_shift()
	dismiss_all_hints() # the first-customer hint
	assert_bool(clock_out()).is_true()
	assert_int(hud.current_hint).is_equal(Hint.FIRST_CLOCK_OUT)
	assert_str(hud.hint_label.text).is_equal("Count the drawer to finish your shift.")
	close_desk()
	hud.hint_dismiss_button.pressed.emit()

	clock_in()
	serve_whole_shift()
	assert_bool(clock_out()).is_true()
	# (The Loan Officer unlock lands during this second shift, so its hint may be up.)
	assert_int(hud.current_hint).is_not_equal(Hint.FIRST_CLOCK_OUT)
	assert_array(hud._hint_queue).not_contains([Hint.FIRST_CLOCK_OUT])
	close_desk()

func test_unlock_hints_show_once_and_queue() -> void:
	dismiss_all_hints()
	unlock_loan_officer()
	assert_int(hud.current_hint).is_equal(Hint.LOAN_OFFICER_UNLOCKED)
	assert_str(hud.hint_label.text).contains("Loan Desk")

	promote() # while the Loan Officer hint is still up: queued behind it
	assert_int(hud.current_hint).is_equal(Hint.LOAN_OFFICER_UNLOCKED)
	hud.hint_dismiss_button.pressed.emit()
	assert_int(hud.current_hint).is_equal(Hint.BRANCH_MANAGER_UNLOCKED)
	assert_str(hud.hint_label.text).contains("Manager's Office")
	hud.hint_dismiss_button.pressed.emit()
	assert_int(hud.current_hint).is_equal(-1)

	assert_bool(hud.show_hint_once(Hint.LOAN_OFFICER_UNLOCKED)).is_false()
	assert_bool(hud.show_hint_once(Hint.BRANCH_MANAGER_UNLOCKED)).is_false()
	assert_bool(hud.hint_panel.visible).is_false()

func test_hints_reset_with_the_career() -> void:
	for hint: Hint in Hint.values():
		HintManager.mark_shown(hint)
	CareerReset.reset_all()
	for hint: Hint in Hint.values():
		assert_bool(HintManager.has_shown(hint)).is_false()

# --- spawn point -------------------------------------------------------------------------

## (384, 624) is just inside the entrance gap (tile columns 11-12 of the bottom
## wall), on open floor, clear of the furniture, the customer lanes and their
## exit corridors, and out of range of every desk.
func test_player_spawns_inside_the_entrance_clear_of_furniture_and_lanes() -> void:
	await settle()
	var spawn_point := player.global_position
	assert_vector(spawn_point).is_equal(Vector2(384, 624))
	var player_rect := Rect2(spawn_point - Vector2(12, 12), Vector2(24, 24))

	var tiles: RoomBuilder = room.get_node("Room")
	var cell := tiles.local_to_map(spawn_point)
	var tile := tiles.get_cell_atlas_coords(cell)
	assert_bool(tile in [tiles.WALL_LOBBY, tiles.WALL_OFFICE]).is_false()
	var entrance := tiles.map_to_local(Vector2i(tiles.ENTRANCE_DOOR_COLUMNS[0], tiles.ROOM_HEIGHT - 1)).lerp(
		tiles.map_to_local(Vector2i(tiles.ENTRANCE_DOOR_COLUMNS[-1], tiles.ROOM_HEIGHT - 1)), 0.5)
	assert_float(spawn_point.distance_to(entrance)).is_less_equal(3 * 32.0)

	for node in room.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		var rect := sprite.get_rect()
		rect.position += sprite.global_position
		assert_bool(rect.intersects(player_rect)) \
			.override_failure_message("spawn overlaps %s" % sprite.get_path()).is_false()

	for line: CustomerQueue in [room.customer_queue, room.window1_npc_line, room.window2_line, room.window3_line]:
		var front := line.queue_positions[0].global_position
		var lane := Rect2(front, Vector2.ZERO).expand(line.spawn_point.global_position).grow(16)
		var corridor_x := front.x + line.exit_side_offset
		var corridor := Rect2(Vector2(corridor_x, front.y), Vector2.ZERO).expand(Vector2(corridor_x, line.exit_y)).grow(16)
		assert_bool(lane.intersects(player_rect)).override_failure_message("spawn in %s's lane" % line.name).is_false()
		assert_bool(corridor.intersects(player_rect)).override_failure_message("spawn in %s's exit corridor" % line.name).is_false()

	assert_object(room.interactable_in_range()).is_null()
