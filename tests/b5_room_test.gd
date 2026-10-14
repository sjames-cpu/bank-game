extends "res://tests/support/teller_room_suite.gd"

## B5: room-wide y-sorting, furniture collision footprints, NPC paths staying
## collision-free, and the entrance's outdoor tiles.

## Physics layer of the furniture footprints (teller_room.tscn).
const FURNITURE_LAYER := 16
const WALL_LAYER := 1
const GRID := 8.0

var player: CharacterBody2D

func before_test() -> void:
	await super()
	player = room.get_node("Player")
	for i in 2:
		await get_tree().physics_frame

func after_test() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)
	await super()

# --- helpers -------------------------------------------------------------------

## Every furniture footprint shape in the room.
func footprints() -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for node in room.find_children("Footprint", "StaticBody2D", true, false):
		shapes.append(node.get_node("CollisionShape2D"))
	return shapes

func shape_rect(shape: CollisionShape2D) -> Rect2:
	var size := (shape.shape as RectangleShape2D).size
	return Rect2(shape.global_position - size / 2.0, size)

## The footprint collision shape at `path` (under the room).
func footprint(path: String) -> CollisionShape2D:
	return room.get_node(path) as CollisionShape2D

func player_rect(at: Vector2) -> Rect2:
	return Rect2(at - Vector2(12, 12), Vector2(24, 24))

## Holds `action` for `frames` physics frames, as a player would.
func walk(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame

## The node that takes part in the room's y-sort for `item`: the item itself
## while every ancestor up to the room is y-sorted, otherwise the topmost
## non-y-sorted ancestor (drawn as one unit with everything under it).
func sort_unit(item: Node2D) -> Node2D:
	var unit := item
	var node := item.get_parent()
	while node != room:
		if not (node as CanvasItem).y_sort_enabled:
			unit = node
		node = node.get_parent()
	return unit

func sort_y(item: Node2D) -> float:
	return sort_unit(item).global_position.y

## True if `a` draws in front of `b` in the room's y-sort.
func draws_in_front(a: Node2D, b: Node2D) -> bool:
	return sort_y(a) > sort_y(b)

## Positions (on a GRID-px lattice) the player's body can occupy and reach
## from the spawn point, walking in GRID-px steps — a step smaller than any
## footprint or wall, so nothing can be tunnelled through.
func reachable_positions() -> Array[Vector2]:
	var space := player.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = (player.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.collision_mask = player.collision_mask
	var is_free := func(p: Vector2) -> bool:
		query.transform = Transform2D(0.0, p)
		return space.intersect_shape(query, 1).is_empty()
	var start := player.global_position
	var seen := {start: true}
	var frontier: Array[Vector2] = [start]
	var reached: Array[Vector2] = []
	while not frontier.is_empty():
		var p: Vector2 = frontier.pop_back()
		reached.append(p)
		for step: Vector2 in [Vector2(GRID, 0), Vector2(-GRID, 0), Vector2(0, GRID), Vector2(0, -GRID)]:
			var next: Vector2 = p + step
			if seen.has(next) or next.x < -64 or next.y < -64 or next.x > 832 or next.y > 832:
				continue
			seen[next] = true
			if is_free.call(next):
				frontier.append(next)
	return reached

func reaches(reached: Array[Vector2], area: Area2D) -> bool:
	var target := shape_rect(area.get_node("CollisionShape2D") as CollisionShape2D)
	for p in reached:
		if player_rect(p).intersects(target):
			return true
	return false

# --- collision -------------------------------------------------------------------

func test_furniture_footprints_are_solid_for_the_player_only() -> void:
	var shapes := footprints()
	assert_int(shapes.size()).is_equal(23)
	for shape in shapes:
		var body := shape.get_parent() as StaticBody2D
		assert_int(body.collision_layer).is_equal(FURNITURE_LAYER)
		# Footprint = the base of the sprite: same bottom edge, no taller
		# than half the sprite.
		var sprite := body.get_parent() as Sprite2D
		if sprite == null:
			sprite = body.get_parent().get_node("Sprite2D")
		var sprite_rect := sprite.get_rect()
		sprite_rect.position += sprite.global_position
		var rect := shape_rect(shape)
		assert_float(rect.end.y).is_equal_approx(sprite_rect.end.y, 0.01)
		assert_float(rect.size.y).is_less_equal(sprite_rect.size.y / 2.0)
		assert_float(rect.size.x).is_less_equal(sprite_rect.size.x)
	assert_int(player.collision_mask).is_equal(WALL_LAYER | FURNITURE_LAYER)
	# Customers and staff keep colliding with walls only.
	var customer := spawn()
	assert_int(customer.collision_mask).is_equal(WALL_LAYER)
	for npc in room.staff_layer.get_children():
		assert_int((npc as CharacterBody2D).collision_mask).is_equal(WALL_LAYER)

func test_player_cannot_walk_through_furniture() -> void:
	var cases: Dictionary[String, CollisionShape2D] = {
		"TellerDesk": footprint("TellerDesk/Footprint/CollisionShape2D"),
		"LoanOfficerDesk": footprint("LoanOfficerDesk/Footprint/CollisionShape2D"),
		"ATM": footprint("ATM/Footprint/CollisionShape2D"),
		"Couch3": footprint("Decor/Couch3/Footprint/CollisionShape2D"),
		"LoungePlantLeft": footprint("Decor/LoungePlantLeft/Footprint/CollisionShape2D"),
	}
	for label: String in cases:
		var rect := shape_rect(cases[label])
		# From below, walking up into it.
		player.global_position = Vector2(rect.get_center().x, rect.end.y + 40)
		await walk("move_up", 45)
		assert_float(player.global_position.y) \
			.override_failure_message("walked into %s from below (y %s)" % [label, player.global_position.y]) \
			.is_greater_equal(rect.end.y + 12 - 0.5)
		assert_float(player.global_position.y).is_less(rect.end.y + 14) # actually stopped at it

	# The teller counter from behind (the staff side) too.
	var counter := shape_rect(cases["TellerDesk"])
	player.global_position = Vector2(counter.get_center().x, counter.position.y - 30)
	await walk("move_down", 45)
	assert_float(player.global_position.y).is_less_equal(counter.position.y - 12 + 0.5)

func test_hidden_branch_manager_desk_is_not_solid_until_promotion() -> void:
	var shape: CollisionShape2D = room.get_node("BranchManagerDesk/Footprint/CollisionShape2D")
	assert_bool(shape.disabled).is_true()
	XPManager._grant_branch_manager()
	await get_tree().physics_frame
	assert_bool(shape.disabled).is_false()

# --- reachability --------------------------------------------------------------

func test_every_interactable_is_reachable_from_the_spawn_point() -> void:
	var reached := reachable_positions()
	for path: String in ["TellerDesk", "LoanOfficerDesk", "ATM"]:
		assert_bool(reaches(reached, room.get_node(path) as Area2D)) \
			.override_failure_message("%s can't be reached from the spawn point" % path).is_true()

	XPManager._grant_branch_manager()
	for i in 2:
		await get_tree().physics_frame
	reached = reachable_positions()
	for path: String in ["TellerDesk", "LoanOfficerDesk", "ATM", "BranchManagerDesk"]:
		assert_bool(reaches(reached, room.get_node(path) as Area2D)) \
			.override_failure_message("%s can't be reached after promotion" % path).is_true()

## The doorway is a doorstep: the player can stand on the doormat but the
## sidewalk outside is solid, so they can't leave the building.
func test_entrance_has_outdoor_tiles_and_keeps_the_player_inside() -> void:
	var tiles: RoomBuilder = room.get_node("Room")
	var bottom: int = tiles.ROOM_HEIGHT - 1
	for column: int in tiles.ENTRANCE_DOOR_COLUMNS:
		var cell := Vector2i(column, bottom)
		assert_int(tiles.get_cell_source_id(cell)).is_equal(tiles.OUTDOOR_SOURCE_ID)
		assert_vector(tiles.get_cell_atlas_coords(cell)).is_equal(tiles.DOORMAT)
	for x: int in tiles.ROOM_WIDTH:
		for y in range(tiles.ROOM_HEIGHT, tiles.ROOM_HEIGHT + tiles.OUTSIDE_ROWS):
			assert_vector(tiles.get_cell_atlas_coords(Vector2i(x, y))).is_equal(tiles.SIDEWALK)

	var wall_bottom := tiles.map_to_local(Vector2i(0, bottom)).y + 16.0
	var on_doormat := false
	for p in reachable_positions():
		assert_float(p.y + 12).override_failure_message("player can leave at %s" % p).is_less_equal(wall_bottom)
		if p.y + 12 > wall_bottom - 32.0:
			on_doormat = true
	assert_bool(on_doormat).is_true()

# --- draw order ------------------------------------------------------------------

func test_room_is_y_sorted_with_sort_origins_at_each_base() -> void:
	assert_bool(room.y_sort_enabled).is_true()
	# Every furniture sprite sorts on its own, at its bottom edge.
	var sprites := room.find_children("*", "Sprite2D", true, false)
	assert_int(sprites.size()).is_greater(20)
	for node in sprites:
		var sprite := node as Sprite2D
		assert_object(sort_unit(sprite)).is_same(sprite)
		assert_int(sprite.z_index).is_equal(0)
		var bottom := sprite.global_position.y + sprite.get_rect().end.y
		assert_float(sprite.global_position.y) \
			.override_failure_message("%s sorts at %s, its base is %s" % [sprite.get_path(), sprite.global_position.y, bottom]) \
			.is_equal_approx(bottom, 0.01)
	# Characters sort as themselves too.
	assert_object(sort_unit(player)).is_same(player)
	var customer := spawn()
	assert_object(sort_unit(customer)).is_same(customer)
	for npc: StaffNPC in room.staff_layer.get_children():
		assert_object(sort_unit(npc)).is_same(npc)

func test_player_draws_behind_a_desk_above_it_and_in_front_below_it() -> void:
	var counter: Sprite2D = room.get_node("TellerDesk/Sprite2D")
	var rect := shape_rect(footprint("TellerDesk/Footprint/CollisionShape2D"))

	# Above (behind the counter, as close as collision allows).
	player.global_position = Vector2(counter.global_position.x, rect.position.y - 30)
	await walk("move_down", 30)
	assert_bool(draws_in_front(player, counter)).is_false()

	# Below (in front of the counter, as close as collision allows).
	player.global_position = Vector2(counter.global_position.x, rect.end.y + 30)
	await walk("move_up", 30)
	assert_bool(draws_in_front(player, counter)).is_true()

	# Same rule for a tall item: the ATM.
	var atm: Sprite2D = room.get_node("ATM/Sprite2D")
	var atm_rect := shape_rect(footprint("ATM/Footprint/CollisionShape2D"))
	player.global_position = Vector2(atm.global_position.x, atm_rect.position.y - 30)
	await walk("move_down", 30)
	assert_bool(draws_in_front(player, atm)).is_false()
	assert_bool(player_rect(player.global_position).intersects(Rect2(atm.global_position + atm.get_rect().position, atm.get_rect().size))).is_true() # close behind it

func test_staff_draw_behind_their_counter_and_customers_in_front() -> void:
	for slot_name: String in [ScheduleManager.SLOT_TELLER_WINDOW_1, ScheduleManager.SLOT_TELLER_WINDOW_2, ScheduleManager.SLOT_LOAN_DESK]:
		var npc: StaffNPC = room._staff_by_slot[slot_name]
		var desk: Node2D = room._desk_for_slot[slot_name]
		var desk_sprite: Sprite2D = desk.get_node("Sprite2D")
		assert_bool(draws_in_front(npc, desk_sprite)).override_failure_message("%s draws over their counter" % slot_name).is_false()
		# ...and the counter's sprite covers their lower body.
		var sprite_rect := Rect2(desk_sprite.global_position + desk_sprite.get_rect().position, desk_sprite.get_rect().size)
		assert_bool(sprite_rect.has_point(npc.global_position + Vector2(0, 10))).is_true()

	var customer := spawn()
	customer.global_position = cq.queue_positions[0].global_position
	assert_bool(draws_in_front(customer, room.get_node("TellerDesk/Sprite2D") as Sprite2D)).is_true()

# --- NPC paths -------------------------------------------------------------------

## The player standing in a lane doesn't stop the line: customers walk
## through them to the counter spot (NPCs and the player never collide).
func test_customer_walks_through_a_player_standing_in_the_lane() -> void:
	clock_in()
	player.global_position = cq.queue_positions[1].global_position
	var customer := spawn()
	Engine.time_scale = 4.0
	for i in 300:
		await get_tree().physics_frame
		if customer.global_position.distance_to(cq.queue_positions[0].global_position) < 0.5:
			break
	assert_vector(customer.global_position).is_equal_approx(cq.queue_positions[0].global_position, Vector2(0.5, 0.5))
	assert_vector(player.global_position).is_equal(cq.queue_positions[1].global_position) # not pushed

	# Served, they leave down the exit corridor past furniture, unblocked.
	serve_correctly(customer)
	var exit := Vector2(cq.queue_positions[0].global_position.x + cq.exit_side_offset, cq.exit_y)
	for i in 600:
		await get_tree().physics_frame
		if not is_instance_valid(customer):
			break
	assert_bool(is_instance_valid(customer)).override_failure_message("customer never reached the exit %s" % exit).is_false()

## The Loan Desk's staff member still walks the full route to the break room
## and back with furniture in the way of nothing.
func test_staff_break_walk_still_completes() -> void:
	XPManager.add_shift_xp(50)
	var npc: StaffNPC = room._staff_by_slot[ScheduleManager.SLOT_LOAN_DESK]
	var desk_spot := npc.global_position
	var loan: LoanOfficerScreen = room.loan_officer_screen
	loan.show_screen()
	loan.clock_in_button.pressed.emit()
	loan.hide_screen()
	Engine.time_scale = 4.0
	for i in 900:
		await get_tree().physics_frame
		if npc.state == StaffNPC.State.ON_BREAK:
			break
	assert_int(npc.state).is_equal(StaffNPC.State.ON_BREAK)
	assert_vector(npc.global_position).is_equal(room._break_spot_for(ScheduleManager.SLOT_LOAN_DESK))

	# Clock-out via the shift's three decisions isn't needed: send them back.
	room._on_player_clocked_out(ScheduleManager.SLOT_LOAN_DESK)
	for i in 900:
		await get_tree().physics_frame
		if npc.state == StaffNPC.State.AT_DESK:
			break
	assert_int(npc.state).is_equal(StaffNPC.State.AT_DESK)
	assert_vector(npc.global_position).is_equal(desk_spot)
