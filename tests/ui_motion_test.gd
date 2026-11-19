extends "res://tests/support/teller_room_suite.gd"

## Stage 2b, interface motion (UiMotionDriver, HudCounter, the HUD's slot-line
## crossfade): screens, letters and the transition card fade in and slide
## into place without ever delaying content or input, and end exactly at the
## layout they have without motion; closing or freeing mid-fade leaves
## nothing behind; it runs while the tree is paused; the HUD's numbers count
## and flash and end on the exact value; buttons give press and hover
## feedback; and with Effects Off all of it is instant. The shared test base
## runs with Effects Off, so every test here turns Effects On explicitly
## (effects_on()) and steps the driver by hand (it is set to `manual`).

var motion: UiMotionDriver
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	motion = room.ui_motion
	motion.manual = true
	motion.capture = _fake_capture

func after_test() -> void:
	get_tree().paused = false
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func effects_on() -> void:
	use_test_settings(true)

## What the window "last drew", so ghosts have something to crop.
func _fake_capture() -> Image:
	var image := Image.create_empty(1152, 648, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.5, 0.6))
	return image

## Waits until `screen_root`'s panels stop changing size (a letter's
## scrolling body fits itself over a few frames).
func settle(screen_root: Control) -> void:
	var last := layout_of(screen_root)
	for i in 12:
		await frames(1)
		var now := layout_of(screen_root)
		if now == last:
			return
		last = now

## A screen's panels: its children other than the Backdrop.
func panels_of(screen_root: Control) -> Array[Control]:
	var found: Array[Control] = []
	for child in screen_root.get_children():
		var control := child as Control
		if control != null and control.name != "Backdrop":
			found.append(control)
	return found

## Where each panel is (path -> global rect), for exact comparisons.
func layout_of(screen_root: Control) -> Dictionary[String, Rect2]:
	var layout: Dictionary[String, Rect2] = {}
	for panel in panels_of(screen_root):
		layout[str(panel.name)] = panel.get_global_rect()
	return layout

## Every panel inside the 648 px window and clear of the HUD column.
func motion_problems(screen_root: Control) -> Array[String]:
	var problems: Array[String] = []
	for panel in panels_of(screen_root):
		if not panel.visible:
			continue
		var rect := panel.get_global_rect()
		if rect.position.y < -0.5 or rect.end.y > 648.5:
			problems.append("%s %s leaves the 648 px window" % [panel.name, rect])
		if rect.end.x > HUD_COLUMN_LEFT + 0.5:
			problems.append("%s %s runs under the HUD column" % [panel.name, rect])
		if not is_equal_approx(rect.position.y, floorf(rect.position.y)) and not is_equal_approx(fposmod(rect.position.y, 1.0), 0.5):
			problems.append("%s sits at a fractional y %s" % [panel.name, rect.position.y])
	return problems

## The Regional review's letter, as the game writes it (run_review() once,
## then replayed, since a review uses up its window).
var regional_title: String = ""
var regional_body: String = ""

func capture_regional_review() -> void:
	for slot in ScheduleManager.get_desk_slots():
		var slot_name: String = slot["name"]
		var member := ScheduleManager.get_assigned(slot_name)
		if member != null:
			for i in 3:
				HistoryManager.add_staff_record(member.staff_name, slot_name, "Work %d" % i, "Mistake" if i == 0 else "Correct")
	GameClock.day = 6
	BusinessDay.stats_day = 6
	RegionalManager.run_review()
	regional_title = room.letter_screen.title_label.text
	regional_body = room.letter_screen.body_label.text
	room.letter_screen.dismiss_current()

## The Branch Manager's shift summary (the widest panel in the game), ready
## to show: promoted, clocked in, every desk's work in the books.
func prepare_branch_manager_summary() -> void:
	var bm := room.branch_manager_screen
	XPManager._grant_branch_manager()
	XPManager.has_seen_branch_orientation = true
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()
	for slot in ScheduleManager.get_desk_slots():
		var slot_name: String = slot["name"]
		var member := ScheduleManager.get_assigned(slot_name)
		if member != null:
			for i in 3:
				HistoryManager.add_staff_record(member.staff_name, slot_name, "Work %d" % i, "Mistake" if i == 0 else "Correct")
	bm.note_staff_vault_time("Walter Higgins", 6.0)
	bm.note_staff_vault_time("Marcus Chen", 4.0)
	bm._prepare_shift_summary()
	bm.visible = false

## The Teller's and the Loan Officer's own shift summaries, ready to show
## (each screen's ShiftSummaryPanel, filled in by its own _prepare_shift_summary()).
func prepare_role_summaries() -> void:
	GameClock.minutes = 10 * 60.0
	room.teller_screen.show_screen()
	room.teller_screen._prepare_shift_summary(STARTING_FLOAT_FOR_SUMMARY)
	room.teller_screen.visible = false
	XPManager.is_loan_officer_unlocked = true
	room.loan_officer_screen.show_screen()
	room.loan_officer_screen._prepare_shift_summary()
	room.loan_officer_screen.visible = false

const STARTING_FLOAT_FOR_SUMMARY: int = 305000

## The screens under test: each opens and closes itself, and says which
## Control is the screen's root.
func screen_cases() -> Dictionary[String, Dictionary]:
	var long_body := ""
	for i in 90:
		long_body += "Line %d of a very long letter that has to scroll inside its panel.\n" % i
	var cases: Dictionary[String, Dictionary] = {}
	cases["letter"] = {
		"root": room.letter_screen,
		"open": func() -> void: room.letter_screen.show_notice("Hello", "A short letter.", "The Bank", "OK", Callable()),
		"close": func() -> void: room.letter_screen.dismiss_current(),
	}
	cases["long letter"] = {
		"root": room.letter_screen,
		"open": func() -> void: room.letter_screen.show_notice("Long", long_body, "The Bank", "OK", Callable()),
		"close": func() -> void: room.letter_screen.dismiss_current(),
	}
	cases["regional review"] = {
		"root": room.letter_screen,
		"open": func() -> void: room.letter_screen.show_notice(regional_title, regional_body, "Regional Office", "Acknowledge", Callable()),
		"close": func() -> void: room.letter_screen.dismiss_current(),
	}
	cases["branch manager shift summary"] = {
		"root": room.branch_manager_screen,
		"open": func() -> void:
			room.branch_manager_screen.show_screen()
			(room.branch_manager_screen.get_node("Panel") as Control).visible = false
			(room.branch_manager_screen.get_node("ShiftSummaryPanel") as Control).visible = true,
		"close": func() -> void: room.branch_manager_screen.visible = false,
	}
	cases["teller shift summary"] = {
		"root": room.teller_screen,
		"open": func() -> void:
			room.teller_screen.show_screen()
			(room.teller_screen.get_node("Panel") as Control).visible = false
			(room.teller_screen.get_node("ShiftSummaryPanel") as Control).visible = true,
		"close": func() -> void: room.teller_screen.visible = false,
	}
	cases["loan officer shift summary"] = {
		"root": room.loan_officer_screen,
		"open": func() -> void:
			room.loan_officer_screen.show_screen()
			(room.loan_officer_screen.get_node("Panel") as Control).visible = false
			(room.loan_officer_screen.get_node("ShiftSummaryPanel") as Control).visible = true,
		"close": func() -> void: room.loan_officer_screen.visible = false,
	}
	cases["end of day"] = {
		"root": room.end_of_day_screen,
		"open": func() -> void: room.end_of_day_screen.show_summary({
			"day": 1, "shifts": 1, "date": BankCalendar.epoch_day(2026, 1, 5), "customers": 9, "customers_by_player": 3,
			"customers_by_staff": 6, "score": 12, "reputation": 2, "xp": 120, "after_cutoff": [],
			"loans": PackedStringArray(["Loans: 1 approved", "Loans: 1 countered", "Loans: 1 declined"]),
		}),
		"close": func() -> void: room.end_of_day_screen.visible = false,
	}
	cases["loan review"] = {
		"root": room.loan_officer_screen.loan_review_screen,
		"open": func() -> void:
			GameClock.minutes = 10 * 60.0
			XPManager.is_loan_officer_unlocked = true
			room._on_loan_officer_desk_interacted()
			room.loan_officer_screen.clock_in_button.pressed.emit()
			var application: LoanApplication = LoanApplicationsData.get_applications().filter(func(a: LoanApplication) -> bool: return a.applicant_name == "Angela Reyes")[0]
			LoanDeskManager.player_queue.push_front(application)
			room.loan_officer_screen.review_next_button.pressed.emit()
			var review := room.loan_officer_screen.loan_review_screen
			review.verify_documents_button.pressed.emit()
			review.run_credit_check_button.pressed.emit(),
		"close": func() -> void: room.loan_officer_screen.loan_review_screen.visible = false,
	}
	return cases

# --- fade and slide ---------------------------------------------------------------

func test_a_letter_fades_in_and_ends_exactly_at_its_no_motion_layout() -> void:
	var letter := room.letter_screen
	var open: Callable = screen_cases()["letter"]["open"]
	# The layout without motion (Effects Off, as the base runs).
	open.call()
	await frames(3)
	var expected := layout_of(letter)
	assert_float(letter.modulate.a).is_equal(1.0)
	letter.dismiss_current()
	await frames(2)
	# With motion: at the first frame it is faded out and lower, in the window.
	effects_on()
	open.call()
	assert_bool(letter.visible).is_true()
	assert_float(letter.modulate.a).is_less(0.5)
	await frames(3)
	var panel := letter.letter_panel
	assert_float(panel.get_global_rect().position.y).is_equal(expected["LetterPanel"].position.y + UiMotionDriver.SLIDE_PIXELS)
	# Its button works from the first frame: it is on screen, enabled, takes the mouse.
	assert_bool(letter.action_button.is_visible_in_tree()).is_true()
	assert_bool(letter.action_button.disabled).is_false()
	assert_int(letter.action_button.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(motion.is_animating()).is_true()
	motion.advance(UiMotionDriver.FADE_IN_SECONDS * 0.5)
	assert_float(letter.modulate.a).is_between(0.1, 0.99)
	motion.advance(UiMotionDriver.FADE_IN_SECONDS)
	await frames(3)
	assert_float(letter.modulate.a).is_equal(1.0)
	assert_dict(layout_of(letter)).is_equal(expected)
	assert_bool(motion.is_animating()).is_false()

func test_a_button_in_a_fading_screen_takes_a_click_on_the_first_frame() -> void:
	effects_on()
	var closed := [false]
	room.letter_screen.show_notice("Hello", "Body", "The Bank", "OK", func() -> void: closed[0] = true)
	await frames(2)
	var button := room.letter_screen.action_button
	var centre := button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = centre
	press.global_position = centre
	press.pressed = true
	var motion_event := InputEventMouseMotion.new()
	motion_event.position = centre
	motion_event.global_position = centre
	get_tree().root.push_input(motion_event)
	get_tree().root.push_input(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_tree().root.push_input(release)
	await frames(2)
	assert_bool(closed[0]).override_failure_message("the click on the fading letter's button did nothing").is_true()

## Opens the screen `case_name` with and without motion and checks it
## at every step (see the cases above).
func check_case(case_name: String) -> void:
	var cases := screen_cases()
	var case: Dictionary = cases[case_name]
	var root: Control = case["root"]
	var open: Callable = case["open"]
	var close: Callable = case["close"]
	# Without motion, three times. A letter's scrolling body fits itself
	# from where the last open left it and, as it is today, one pixel
	# taller or shorter on every other open (before this branch too), so
	# the reference is the second open and the motion run the fourth:
	# the same point in that two-step cycle.
	use_test_settings(false)
	var expected := layout_of(root)
	for run in 3:
		open.call()
		await frames(4)
		if case.has("fit"):
			await settled_height(root.get_node(str(case["fit"])) as Control)
		await settle(root)
		if run == 1:
			expected = layout_of(root)
		close.call()
		await frames(2)
	# With motion, stepped by hand.
	effects_on()
	open.call()
	await frames(4)
	if case.has("fit"):
		await settled_height(root.get_node(str(case["fit"])) as Control)
	var shown := panels_of(root).filter(func(panel: Control) -> bool: return panel.visible)
	assert_int(shown.size()).override_failure_message("%s shows no panel to measure" % case_name).is_greater(0)
	assert_array(motion_problems(root)).override_failure_message("%s at the start: %s" % [case_name, "\n".join(motion_problems(root))]).is_empty()
	var steps := 0
	while motion.is_animating() and steps < 40:
		motion.advance(0.01)
		await frames(1)
		steps += 1
		var problems := motion_problems(root)
		assert_array(problems).override_failure_message("%s step %d:\n%s" % [case_name, steps, "\n".join(problems)]).is_empty()
	assert_int(steps).override_failure_message("%s never finished" % case_name).is_less(40)
	assert_float(root.modulate.a).is_equal(1.0)
	await settle(root)
	assert_dict(layout_of(root)).override_failure_message("%s did not end at its no-motion layout: %s vs %s" % [case_name, expected, layout_of(root)]).is_equal(expected)
	close.call()
	motion.finish_all()
	await frames(2)

func test_letters_stay_in_the_window_at_every_step_and_end_at_their_layout() -> void:
	capture_regional_review()
	await frames(2)
	for case_name: String in ["letter", "long letter", "regional review"]:
		await check_case(case_name)

func test_the_end_of_day_summary_stays_in_the_window_at_every_step_and_ends_at_its_layout() -> void:
	await check_case("end of day")

func test_the_branch_manager_shift_summary_stays_in_the_window_at_every_step_and_ends_at_its_layout() -> void:
	prepare_branch_manager_summary()
	await frames(2)
	await check_case("branch manager shift summary")

func test_the_teller_shift_summary_stays_in_the_window_at_every_step_and_ends_at_its_layout() -> void:
	prepare_role_summaries()
	await frames(2)
	await check_case("teller shift summary")

func test_the_loan_officer_shift_summary_stays_in_the_window_at_every_step_and_ends_at_its_layout() -> void:
	prepare_role_summaries()
	await frames(2)
	await check_case("loan officer shift summary")

func test_the_loan_review_screen_stays_in_the_window_at_every_step_and_ends_at_its_layout() -> void:
	await check_case("loan review")

func test_the_scrolling_body_does_not_jump_during_the_fade() -> void:
	effects_on()
	var open: Callable = screen_cases()["long letter"]["open"]
	open.call()
	await frames(4)
	var scroll := room.letter_screen.body_scroll
	var maximum := scroll.get_v_scroll_bar().max_value
	assert_float(maximum).is_greater(scroll.get_v_scroll_bar().page)
	scroll.scroll_vertical = 120
	for i in 20:
		motion.advance(0.01)
		await frames(1)
		assert_int(scroll.scroll_vertical).is_equal(120)
		assert_float(scroll.get_v_scroll_bar().max_value).is_equal(maximum)

# --- closing, freeing, pausing -----------------------------------------------------

func test_closing_mid_fade_ends_cleanly_and_the_ghost_fades_away() -> void:
	effects_on()
	var letter := room.letter_screen
	var open: Callable = screen_cases()["letter"]["open"]
	open.call()
	await frames(3)
	var expected_x := letter.letter_panel.get_global_rect().position.x
	motion.advance(0.05)
	var lower := letter.letter_panel.get_global_rect().position.y
	letter.dismiss_current()
	# Hidden: at its own place and full alpha at once (nothing left shifted), a ghost fading out.
	assert_bool(letter.visible).is_false()
	assert_float(letter.modulate.a).is_equal(1.0)
	assert_float(letter.letter_panel.get_global_rect().position.x).is_equal(expected_x)
	assert_int(motion.ghost_count()).is_equal(1)
	motion.advance(UiMotionDriver.FADE_OUT_SECONDS * 0.5)
	assert_int(motion.ghost_count()).is_equal(1)
	motion.advance(UiMotionDriver.FADE_OUT_SECONDS)
	assert_int(motion.ghost_count()).is_equal(0)
	assert_bool(motion.is_animating()).is_false()
	assert_int(motion.ghost_node_count()).is_equal(0)
	# Opening it again puts it back where it started, not where the closed one was.
	open.call()
	await frames(3)
	motion.advance(1.0)
	await frames(2)
	assert_float(letter.letter_panel.get_global_rect().position.y).is_less(lower)

func test_reopening_during_the_ghost_removes_it() -> void:
	effects_on()
	var open: Callable = screen_cases()["letter"]["open"]
	open.call()
	await frames(3)
	motion.advance(1.0)
	room.letter_screen.dismiss_current()
	assert_int(motion.ghost_count()).is_equal(1)
	open.call()
	assert_int(motion.ghost_count()).is_equal(0)

func test_freeing_a_screen_mid_fade_leaks_nothing() -> void:
	effects_on()
	var units_before := motion.units.size()
	var screen: DisciplineLetterScreen = (load("res://scenes/ui/discipline_letter_screen.tscn") as PackedScene).instantiate()
	room.get_node("UI").add_child(screen)
	await frames(2)
	assert_int(motion.units.size()).is_equal(units_before + 1)
	screen.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	await frames(2)
	motion.advance(0.05)
	assert_bool(motion.is_animating()).is_true()
	screen.free()
	assert_int(motion.units.size()).is_equal(units_before)
	motion.advance(0.5)
	assert_bool(motion.is_animating()).is_false()
	assert_int(motion.ghost_node_count()).is_equal(0)

func test_the_motion_runs_while_the_tree_is_paused() -> void:
	effects_on()
	motion.manual = false
	var letter := room.letter_screen
	get_tree().paused = true
	letter.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	await frames(1)
	assert_float(letter.modulate.a).is_less(1.0)
	await get_tree().create_timer(0.5, true).timeout
	assert_float(letter.modulate.a).is_equal(1.0)
	assert_bool(motion.is_animating()).is_false()
	get_tree().paused = false

func test_the_driver_stops_processing_when_nothing_moves() -> void:
	effects_on()
	motion.manual = false
	assert_bool(motion.is_processing()).is_false()
	room.letter_screen.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	assert_bool(motion.is_processing()).is_true()
	await get_tree().create_timer(0.5, true).timeout
	assert_bool(motion.is_processing()).is_false()

# --- the transition card and the hint card ----------------------------------------------

func test_the_slot_transition_card_fades_in() -> void:
	effects_on()
	start_slots_day()
	clock_in()
	await frames(2)
	var card := slot_card()
	assert_bool(card.visible).is_true()
	var root := card.get_node("Root") as Control
	assert_float(root.modulate.a).is_less(1.0)
	var rect := card.card_panel.get_global_rect()
	assert_array(motion_problems(root)).is_empty()
	motion.advance(1.0)
	await frames(2)
	assert_float(root.modulate.a).is_equal(1.0)
	assert_float(card.card_panel.get_global_rect().position.y).is_less(rect.position.y + 0.1)
	assert_bool(card.continue_button.is_visible_in_tree()).is_true()
	assert_bool(card.continue_button.disabled).is_false()

func test_the_hint_card_fades_in_without_moving() -> void:
	effects_on()
	var hud := room.hud
	while hud.current_hint != -1:
		hud.dismiss_hint()
	await frames(2)
	motion.finish_all()
	var resting := hud.hint_panel.position
	hud._show_hint(HintManager.Hint.OPENING_HOURS)
	await frames(2)
	assert_float(hud.hint_panel.modulate.a).is_less(1.0)
	assert_vector(hud.hint_panel.position).is_equal(resting)
	motion.advance(1.0)
	assert_float(hud.hint_panel.modulate.a).is_equal(1.0)
	assert_vector(hud.hint_panel.position).is_equal(resting)

# --- HUD numbers ------------------------------------------------------------------------

func test_the_score_counts_up_with_a_green_flash_and_ends_exactly() -> void:
	effects_on()
	var hud := room.hud
	hud.refresh()
	ScoreManager.add_shift_score(100)
	hud.refresh()
	assert_str(hud.score_label.text).is_equal("Score: 0")
	hud.step_motion(0.1)
	var first := hud.score_counter.value()
	assert_int(first).is_between(1, 99)
	var tint := hud.score_label.self_modulate
	assert_float(tint.g).is_greater(tint.r)
	hud.step_motion(0.1)
	assert_int(hud.score_counter.value()).is_greater(first)
	hud.step_motion(0.5)
	assert_str(hud.score_label.text).is_equal("Score: 100")
	hud.step_motion(1.0)
	assert_str(hud.score_label.text).is_equal("Score: 100")
	assert_that(hud.score_label.self_modulate).is_equal(Color.WHITE)

func test_a_loss_counts_down_with_a_red_flash() -> void:
	effects_on()
	var hud := room.hud
	ScoreManager.add_shift_score(50)
	hud.refresh()
	hud.step_motion(2.0)
	ScoreManager.add_shift_score(-30)
	hud.refresh()
	hud.step_motion(0.1)
	assert_int(hud.score_counter.value()).is_between(21, 49)
	var tint := hud.score_label.self_modulate
	assert_float(tint.r).is_greater(tint.g)
	hud.step_motion(1.0)
	assert_str(hud.score_label.text).is_equal("Score: 20")

func test_a_change_mid_count_continues_from_what_is_shown() -> void:
	effects_on()
	var hud := room.hud
	hud.refresh()
	ReputationManager.add_reputation(40)
	hud.refresh()
	hud.step_motion(0.2)
	var shown := hud.reputation_counter.value()
	assert_int(shown).is_between(51, 89)
	# A new change to a lower value: carries on from `shown`, not from 50 or 90.
	ReputationManager.add_reputation(-60)
	hud.refresh()
	assert_int(hud.reputation_counter.value()).is_equal(shown)
	assert_int(hud.reputation_counter.target).is_equal(ReputationManager.reputation)
	var tint := hud.reputation_label.self_modulate
	assert_float(tint.r).is_greater(tint.g)
	hud.step_motion(0.1)
	assert_int(hud.reputation_counter.value()).is_less(shown)
	hud.step_motion(1.0)
	assert_str(hud.reputation_label.text).is_equal("Reputation: %d" % ReputationManager.reputation)

func test_xp_counts_and_ends_on_the_exact_value() -> void:
	effects_on()
	var hud := room.hud
	hud.refresh()
	XPManager.add_shift_xp(7)
	hud.refresh()
	hud.step_motion(0.4)
	assert_str(hud.xp_label.text).is_equal("XP: %d" % XPManager.total_xp)

func test_the_slot_line_crossfades_when_it_changes() -> void:
	effects_on()
	var hud := room.hud
	hud.refresh()
	hud._slot_text_changed("Customers: 0 / 2", "Customers: 1 / 2")
	hud.slot_label.text = "Customers: 1 / 2"
	hud.slot_label.visible = true
	hud.step_motion(0.0)
	assert_float(hud.slot_label.self_modulate.a).is_equal(0.0)
	var ghost := hud.slot_label.get_node("SlotGhost") as Label
	assert_str(ghost.text).is_equal("Customers: 0 / 2")
	assert_bool(ghost.visible).is_true()
	hud.step_motion(Hud.SLOT_FADE_SECONDS * 0.5)
	assert_float(hud.slot_label.self_modulate.a).is_between(0.2, 0.8)
	assert_float(ghost.modulate.a).is_between(0.2, 0.8)
	hud.step_motion(1.0)
	assert_float(hud.slot_label.self_modulate.a).is_equal(1.0)
	assert_bool(ghost.visible).is_false()

# --- buttons ---------------------------------------------------------------------------

func make_button() -> Button:
	var button := Button.new()
	button.text = "Press me"
	room.get_node("UI").add_child(button)
	await frames(1)
	return button

func test_hovering_brightens_a_button_and_leaving_restores_it() -> void:
	effects_on()
	var button := await make_button()
	button.mouse_entered.emit()
	motion.advance(UiMotionDriver.HOVER_SECONDS * 0.5)
	assert_float(button.self_modulate.r).is_between(1.0, UiMotionDriver.HOVER_BRIGHTNESS)
	motion.advance(1.0)
	assert_float(button.self_modulate.r).is_equal_approx(UiMotionDriver.HOVER_BRIGHTNESS, 0.001)
	assert_vector(button.scale).is_equal(Vector2.ONE)
	button.mouse_exited.emit()
	motion.advance(1.0)
	assert_that(button.self_modulate).is_equal(Color.WHITE)
	assert_bool(motion.is_animating()).is_false()
	button.queue_free()

func test_pressing_steps_the_label_down_one_pixel_and_never_moves_the_button() -> void:
	effects_on()
	var button := await make_button()
	var rect := button.get_global_rect()
	var normal := button.get_theme_stylebox(&"pressed")
	var top := normal.get_margin(SIDE_TOP)
	var bottom := normal.get_margin(SIDE_BOTTOM)
	var minimum := button.get_combined_minimum_size()
	button.button_down.emit()
	var pressed := button.get_theme_stylebox(&"pressed")
	assert_float(pressed.get_margin(SIDE_TOP)).is_equal(top + 1.0)
	assert_float(pressed.get_margin(SIDE_BOTTOM)).is_equal(bottom - 1.0)
	# Same size, same place, so the clickable area stays under the cursor; no scaling.
	assert_vector(button.get_combined_minimum_size()).is_equal(minimum)
	assert_that(button.get_global_rect()).is_equal(rect)
	assert_vector(button.scale).is_equal(Vector2.ONE)
	button.button_up.emit()
	assert_float(button.get_theme_stylebox(&"pressed").get_margin(SIDE_TOP)).is_equal(top)
	assert_bool(button.has_theme_stylebox_override(&"pressed")).is_false()
	button.queue_free()

func test_a_button_freed_mid_press_or_mid_hover_leaks_nothing() -> void:
	effects_on()
	var tracked := motion.tracked_button_count()
	var button := await make_button()
	assert_int(motion.tracked_button_count()).is_equal(tracked + 1)
	button.mouse_entered.emit()
	button.button_down.emit()
	assert_bool(motion.is_animating()).is_true()
	button.free()
	assert_int(motion.tracked_button_count()).is_equal(tracked)
	motion.advance(0.5)
	assert_bool(motion.is_animating()).is_false()

# --- Effects Off ---------------------------------------------------------------------------

func test_with_effects_off_everything_is_instant() -> void:
	use_test_settings(false)
	var letter := room.letter_screen
	letter.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	assert_float(letter.modulate.a).is_equal(1.0)
	assert_bool(motion.is_animating()).is_false()
	await frames(3)
	var expected := layout_of(letter)
	letter.dismiss_current()
	assert_int(motion.ghost_count()).is_equal(0)
	letter.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	await frames(3)
	assert_dict(layout_of(letter)).is_equal(expected)
	# Numbers.
	var hud := room.hud
	hud.refresh()
	ScoreManager.add_shift_score(80)
	hud.refresh()
	assert_str(hud.score_label.text).is_equal("Score: 80")
	assert_that(hud.score_label.self_modulate).is_equal(Color.WHITE)
	# Buttons.
	var button := await make_button()
	button.mouse_entered.emit()
	button.button_down.emit()
	assert_that(button.self_modulate).is_equal(Color.WHITE)
	assert_bool(button.has_theme_stylebox_override(&"pressed")).is_false()
	button.queue_free()

func test_turning_effects_off_mid_motion_finishes_everything_at_once() -> void:
	effects_on()
	var letter := room.letter_screen
	var hud := room.hud
	letter.show_notice("Hello", "Body", "The Bank", "OK", Callable())
	await frames(2)
	ScoreManager.add_shift_score(60)
	hud.refresh()
	motion.advance(0.05)
	hud.step_motion(0.05)
	assert_float(letter.modulate.a).is_less(1.0)
	EffectsSetting.set_on(false, false)
	motion.advance(0.0)
	hud.step_motion(0.0)
	assert_float(letter.modulate.a).is_equal(1.0)
	assert_bool(motion.is_animating()).is_false()
	assert_str(hud.score_label.text).is_equal("Score: 60")

func test_the_setting_stays_out_of_career_saves() -> void:
	var saved := JSON.stringify(SaveGame.capture())
	assert_str(saved).not_contains("effects")
	assert_str(saved).not_contains("ui_motion")
	assert_bool(EffectsSetting.is_real_file(EffectsSetting.path)).is_false()
