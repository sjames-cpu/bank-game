extends GdUnitTestSuite

## Base for every suite that drives the real room (scenes/world/teller_room.tscn),
## whatever the role: a fresh room and a fresh career (CareerReset) per test,
## onboarding done, the global RNG and the loan desk's seed fixed so names,
## staff timing and mistakes are the same every run, and the random rolls
## that would make a test flaky (bad IDs, account openers, staff ID slips,
## a fake armored truck crew) switched off unless a test asks.
##
## The room saves the career (SaveGame), so every test points SaveGame at
## the test save files (TEST_PREFIX) and starts and ends without a save
## there: tests never read or write the real saves.
##
## Also here: the time-slot day (start_slots_day(), open_work_slot(),
## to_closing(), skip_to_slot(), continue_to_slot(), run_end_of_day(),
## go_to_next_day()), the vault door's witness (call_vault_witness(),
## reconcile_vault()) and the screen-fit checks (layout_problems(),
## controls_line_problems()).
##
## Role suites extend it: tests/support/teller/teller_suite.gd (the teller
## screen, its drawer and customers) and tests/support/loan/loan_suite.gd.
## Shared changes go here on a shared/ branch; each role adds its helpers to
## its own suite. Not a test suite itself (no test_ functions).

const TELLER_ROOM_SCENE := "res://scenes/world/teller_room.tscn"

const RNG_SEED := 20261012

## Test save files are named from this instead of SaveGame.REAL_PREFIX:
## "user://test_career_slot_<n>.json", and the old single save
## "user://test_career.json". Every test plays in Slot 1 (TEST_SAVE_PATH)
## unless it picks another.
const TEST_PREFIX := "user://test_career"

const TEST_SAVE_PATH := "user://test_career_slot_1.json"

## The Effects setting's file in tests (never the real one, EffectsSetting).
const TEST_SETTINGS_PATH := "user://test_settings.cfg"

var room: TellerRoom

var cq: CustomerQueue

func before_test() -> void:
	_holding_branch = false
	seed(RNG_SEED)
	# Each career's loan applicants come from a seed of its own (LoanDeskManager).
	LoanDeskManager.seed_source.seed = RNG_SEED
	use_test_save_path()
	# Effects Off unless a test turns them on (use_test_settings(true)), so
	# positions, outlines and zooms stay exactly where the checks expect them.
	use_test_settings(false)
	use_interview_setting(InterviewManager.INTERVIEW_ENABLED)
	CareerReset.reset_all()
	# Onboarding done unless a test asks (onboarding_test.gd).
	OnboardingManager.skip()
	fix_truck_rolls()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	cq = room.get_node("CustomerQueue")
	# Customers in these tests are spawned explicitly (spawn()).
	cq.spawn_timer.stop()
	_fix_id_rolls(cq)
	_fix_staff_id_rolls()

## Makes `new_room` (one a scene change loaded, e.g. from the slot screen)
## the room the helpers below drive, as before_test() does for the first. A
## new career's onboarding there is skipped unless `keep_onboarding`.
func adopt_room(new_room: TellerRoom, keep_onboarding: bool = false) -> void:
	room = new_room
	if not keep_onboarding:
		room.onboarding_flow.skip()
	cq = room.get_node("CustomerQueue")
	cq.spawn_timer.stop()
	_fix_id_rolls(cq)
	_fix_staff_id_rolls()

## The staff windows in tests: the same (every ID valid, no account
## openers), and staff who always check correctly, unless a test asks
## (staff_id_checks_test.gd sets the real chances).
func _fix_staff_id_rolls() -> void:
	for line in staff_lines():
		_fix_id_rolls(line)
		line.staff_id_slips = false

## Every staff-served teller line in the room.
func staff_lines() -> Array[NpcCustomerLine]:
	var lines: Array[NpcCustomerLine] = []
	for child in room.get_children():
		if child is NpcCustomerLine:
			lines.append(child as NpcCustomerLine)
	return lines

## The player's line in tests: every ID valid and nobody opening an account
## unless a test asks (kyc_test.gd sets the chances), with its own generator
## seeded so the cards are the same every run.
func _fix_id_rolls(line: CustomerQueue) -> void:
	line.kyc_rng.seed = RNG_SEED
	line.id_problem_chance = 0.0
	line.account_opening_chance = 0.0

## The armored truck in tests: the scheduled crew and good bags every time,
## unless a test asks (armored_truck_test.gd sets the chances), with its own
## generator seeded so crews and seals are the same every run.
func fix_truck_rolls() -> void:
	VaultManager.visit_rng.seed = RNG_SEED
	VaultManager.fake_crew_chance = 0.0
	VaultManager.shipment_problem_chance = 0.0

## A fresh, not yet added, teller room.
func instantiate_room() -> TellerRoom:
	var scene: PackedScene = load(TELLER_ROOM_SCENE)
	return scene.instantiate() as TellerRoom

func after_test() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var scene := get_tree().current_scene
	if is_instance_valid(room):
		room.free()
	# A test can change scene (e.g. termination -> interview); free that too.
	if is_instance_valid(scene) and scene != room:
		scene.free()
	room = null
	CareerReset.reset_all()
	use_test_save_path()
	use_test_settings(false)
	use_interview_setting(InterviewManager.INTERVIEW_ENABLED)
	# Let queue_free()'d nodes (rebuilt UI rows, re-placed staff) actually go
	# before gdUnit's orphan check.
	await get_tree().process_frame

## Points the Effects setting at the test settings file (TEST_SETTINGS_PATH),
## removes any file left there, and sets it On or Off for this test without
## writing it. The default for every test is Off.
func use_test_settings(effects_on: bool = false) -> void:
	EffectsSetting.use_file(TEST_SETTINGS_PATH)
	for leftover: String in [TEST_SETTINGS_PATH]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)
	EffectsSetting.set_on(effects_on, false)
	CharacterMotionDriver.clock = 0.0

## Points SaveGame at the test save files (TEST_PREFIX), plays Slot 1
## (TEST_SAVE_PATH), and removes every test save (all slots, the old single
## save, and the files SaveGame writes beside them).
func use_test_save_path() -> void:
	SaveGame.use_saves_named(TEST_PREFIX)
	# Opening the start screen allows the real saves; tests start without it.
	SaveGame.real_prefix = SaveGame.REAL_PREFIX
	SaveGame.real_save_allowed = false
	StartScreen.next_view = StartScreen.View.MAIN_MENU
	var files: Array[String] = [SaveGame.legacy_path()]
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		files.append(SaveGame.slot_path(slot))
	for file in files:
		for leftover: String in [file, file + ".tmp", file + ".bad"]:
			if FileAccess.file_exists(leftover):
				DirAccess.remove_absolute(leftover)

## Turns the hiring interview on or off for this test (the game reads
## InterviewManager.interview_enabled; the INTERVIEW_ENABLED switch is its
## default, restored before and after every test). Tests whose result
## depends on the interview set it explicitly, so they pass whichever way
## the switch is set.
func use_interview_setting(enabled: bool) -> void:
	InterviewManager.interview_enabled = enabled

## A day started at Opening that waits between slots
## (DayFlow.pause_between_slots), as the room runs it.
func start_slots_day() -> void:
	slot_day().start_day()

## The room's Regional visit (RegionalVisitSlot).
func regional_visit() -> RegionalVisitSlot:
	return room.get_node("RegionalVisitSlot")

## The room's SlotDayController (starting days, the doormat, F3).
func slot_day() -> SlotDayController:
	return room.get_node("SlotDayController")

## The room's time-slot pieces (placed by SlotWiring).
func slot_card() -> SlotTransitionCard:
	return room.get_node("SlotTransitionCard")

## A test's own hold on the current work slot (open_work_slot()), so it stays
## open with nobody's work in it; released by to_closing().
const TEST_HOLD: StringName = &"test keeps the branch open"

## Time slots: a work slot running, so the branch is open (customers arrive
## at the staff windows, staff loan desks take applicants), as at 9 AM. With
## nobody clocked in, Opening is skipped and the test holds the slot open
## (TEST_HOLD); a teller clocked in has the slot's batch (their line's
## timer stopped: tests bring their own customers). Does nothing with slots
## off.
func open_work_slot() -> void:
	if not DayFlow.is_running():
		_holding_branch = false
		slot_day().start_day()
	if DayFlow.current_slot().id == DaySchedule.OPENING and not DayFlow.is_between_slots():
		DayFlow.skip_slot()
	if DayFlow.is_between_slots():
		# A player on shift claims the slot with their own work; with nobody
		# on shift, the test holds it open.
		if not _holding_branch and not PlayerShift.is_on_shift():
			_holding_branch = DayFlow.hold(TEST_HOLD)
		DayFlow.continue_day()
	cq.spawn_timer.stop()

var _holding_branch: bool = false

## Time slots: the day moved on to Closing, as a player done with their work
## would: a work slot running is skipped (customers still waiting in the
## player's line leave), the rest gone home from on the card. Customers
## brought in before 9 AM stay in the line. Does nothing at Opening (it waits for the clock-in).
func to_closing() -> void:
	if _holding_branch:
		_holding_branch = false
		DayFlow.release(TEST_HOLD)
	for step in DaySchedule.count() * 2:
		if not DayFlow.is_running():
			return
		var slot := DayFlow.current_slot()
		if DayFlow.is_between_slots():
			if not DayFlow.go_home_early():
				DayFlow.continue_day()
		elif slot.id == DaySchedule.CLOSING or slot.id == DaySchedule.OPENING:
			return
		else:
			DayFlow.skip_slot()
			if not DayFlow.is_between_slots():
				return # held by an event: the test's assertions say so

## Time slots: after the clock-out, the lobby emptied (everyone still walking
## out leaves), any letters acknowledged, and the End of Day summary up.
func run_end_of_day() -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	for i in 4:
		await get_tree().process_frame
		while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
			room.letter_screen.action_button.pressed.emit()
	assert_bool(room.end_of_day_screen.is_summary_shown()).override_failure_message("no End of Day summary").is_true()

## Time slots: End of Day (run_end_of_day()), then "Start Day N+1" (through any
## weekend or holiday notice): the next day at Opening.
func go_to_next_day() -> void:
	await run_end_of_day()
	var eod := room.end_of_day_screen
	eod.next_day_button.pressed.emit()
	if eod.is_closure_shown():
		eod.next_day_button.pressed.emit()

## Time slots: the day moved on to slot `id`, skipping any work slot on the
## way (as the debug key does), the player's line timer stopped once there.
func skip_to_slot(id: StringName) -> void:
	for step in DaySchedule.count() * 2:
		if not DayFlow.is_running() or (DayFlow.current_slot().id == id and not DayFlow.is_between_slots()):
			break
		if DayFlow.is_between_slots():
			DayFlow.continue_day()
		else:
			DayFlow.skip_slot()
	cq.spawn_timer.stop()

## Between slots, Continue until `id` has started (or the day has ended).
func continue_to_slot(id: StringName) -> void:
	while DayFlow.is_running() and (DayFlow.is_between_slots() or DayFlow.current_slot().id != id):
		if not DayFlow.is_between_slots():
			return # stuck inside another slot: the test's assertions say so
		DayFlow.continue_day()

# --- the vault door (dual control) ---------------------------------------------

## The player at the vault door presses the interact key; the witness's walk
## is skipped (StaffNPC.finish_route()), so the vault opens at once when they
## come straight away. Returns the witness (null if nobody came). A witness
## still finishing a customer is left on their way (the phase stays FINISHING).
func call_vault_witness() -> StaffNPC:
	var teller: TellerScreen = room.get_node("UI/TellerScreen")
	if teller.visible:
		teller.close_button.pressed.emit()
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	var control := room.vault_control
	control._process(0.0)
	if control.phase == VaultDualControl.Phase.WALKING_IN:
		control.witness.finish_route()
	var witness := control.witness
	control._process(0.0)
	return witness

## The Branch Manager's vault reconciliation at the vault door, counted
## exactly, with the witness walked back; then back at the desk, the hub open.
func reconcile_vault() -> void:
	var bm := room.branch_manager_screen
	if bm.visible:
		bm.hide_screen()
	var witness := call_vault_witness()
	var vault := bm.vault_reconciliation_screen
	assert_bool(vault.is_visible_in_tree()).override_failure_message("the vault didn't open").is_true()
	var pieces := CashDenominations.fewest_pieces(VaultManager.expected_cents)
	for i in pieces.size():
		vault.quantity_inputs[i].value = pieces[i]
	vault.submit_button.pressed.emit()
	vault.close_button.pressed.emit()
	if is_instance_valid(witness):
		witness.finish_route()
	bm.show_screen()

## Height a centred, auto-sizing panel settles at for its designed width.
## (reset_size() would collapse autowrap labels to their minimum width and
## report a bogus height.) The game window is 648px tall.
func settled_height(panel: Control) -> float:
	var width := panel.offset_right - panel.offset_left
	var last := -1.0
	for i in 10:
		panel.size = Vector2(width, 0)
		await get_tree().process_frame
		await get_tree().process_frame
		if is_equal_approx(panel.size.y, last):
			break
		last = panel.size.y
	return panel.size.y

## The HUD column's left edge at 1152x648: screens stay left of it.
const HUD_COLUMN_LEFT: float = 952.0

## Room screens keep from the window's edges, so they never just scrape in.
const WINDOW_MARGIN: float = 8.0

## `panel` (a screen's content panel), laid out, sits inside the 1152x648
## window with a WINDOW_MARGIN to spare and left of the HUD column, and so does every visible control in
## it, each also inside the panel. Controls inside a ScrollContainer scroll
## within it, so the container stands for them. Returns the problems found
## (one line each), so a test can assert there are none.
func layout_problems(panel: Control) -> Array[String]:
	var window := Rect2(0, 0, 1152, 648).grow(-WINDOW_MARGIN)
	var problems: Array[String] = []
	var panel_rect := panel.get_global_rect()
	var checked: Array[Control] = [panel]
	for node in panel.find_children("*", "Control", true, false):
		checked.append(node as Control)
	for control in checked:
		if not control.is_visible_in_tree() or control.size.x <= 0.0 or control.size.y <= 0.0:
			continue
		if _scrolls_inside(control, panel):
			continue
		# Half a pixel of rounding either way.
		var rect := control.get_global_rect().grow(-0.5)
		var label := str(panel.get_path_to(control)) if control != panel else str(panel.name)
		if control != panel and not panel_rect.encloses(rect):
			problems.append("%s %s leaves the panel %s" % [label, rect, panel_rect])
		if not window.encloses(rect):
			problems.append("%s %s comes within %d px of the 1152x648 window's edge" % [label, rect, WINDOW_MARGIN])
		if rect.end.x > HUD_COLUMN_LEFT:
			problems.append("%s %s runs under the HUD column (x >= %d)" % [label, rect, HUD_COLUMN_LEFT])
	return problems

## `panel` (laid out) stays clear of the HUD's controls line in the
## bottom-left corner. Returns the problem, if any.
func controls_line_problems(panel: Control) -> Array[String]:
	var problems: Array[String] = []
	var controls := room.hud.controls_panel
	if controls.is_visible_in_tree() and panel.get_global_rect().grow(-0.5).intersects(controls.get_global_rect()):
		problems.append("%s %s runs under the controls line %s" % [panel.name, panel.get_global_rect(), controls.get_global_rect()])
	return problems

func _scrolls_inside(control: Control, panel: Control) -> bool:
	var node := control.get_parent()
	while node != null and node != panel:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false

## Career totals, for before/after deltas.
func totals() -> Vector3i:
	return Vector3i(ScoreManager.total_score, ReputationManager.reputation, XPManager.total_xp)
