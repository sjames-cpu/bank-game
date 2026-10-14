extends "res://tests/support/teller_room_suite.gd"

## The shared letter screen (discipline_letter_screen.gd) stays within the
## window: a long body scrolls inside the panel with the title, sender and
## button always visible, and a short letter stays compact.

const WINDOW_HEIGHT := 648.0

var letters: DisciplineLetterScreen

func before_test() -> void:
	await super()
	letters = room.letter_screen

# --- helpers -------------------------------------------------------------------

## Lets the letter's containers lay out (it processes while paused).
func settle_letter() -> void:
	for i in 5:
		await get_tree().process_frame

func acknowledge_all() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

## The viewport the letter is centred in (taller than the game's 648px
## window in a headless test run; the height limit is still the window's).
func window_rect() -> Rect2:
	return get_viewport().get_visible_rect()

func panel_rect() -> Rect2:
	return letters.letter_panel.get_global_rect()

func body_scrolls() -> bool:
	var bar := letters.body_scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0

## The letter panel is within the window, at most MAX_HEIGHT_SHARE of it,
## centred, with its title, sender and button fully inside it.
func assert_letter_fits(what: String) -> void:
	var rect := panel_rect()
	assert_bool(window_rect().encloses(rect)).override_failure_message("%s: panel %s leaves the window" % [what, rect]).is_true()
	# At most MAX_HEIGHT_SHARE of the 648px window, so centred in it there's
	# a clear margin above and below.
	assert_float(rect.size.y).override_failure_message("%s: panel is %.0f px tall" % [what, rect.size.y]).is_less_equal(WINDOW_HEIGHT * DisciplineLetterScreen.MAX_HEIGHT_SHARE + 1.0)
	assert_float((WINDOW_HEIGHT - rect.size.y) / 2.0).is_greater_equal(80.0)
	assert_float(absf(rect.get_center().y - window_rect().get_center().y)).override_failure_message("%s: not centred" % what).is_less_equal(1.0)
	for control: Control in [letters.title_label, letters.from_label, letters.action_button]:
		assert_bool(rect.encloses(control.get_global_rect())).override_failure_message("%s: %s isn't inside the panel" % [what, control.name]).is_true()
		assert_bool(control.is_visible_in_tree()).is_true()

# --- letters --------------------------------------------------------------------

func test_a_long_letter_scrolls_with_its_button_in_view() -> void:
	assert_bool(letters.show_branch_orientation_once()).is_true()
	await settle_letter()
	assert_letter_fits("orientation")
	# The body is longer than the room it has, so it scrolls.
	assert_bool(body_scrolls()).is_true()
	assert_float(letters.body_label.get_combined_minimum_size().y).is_greater(letters.body_scroll.size.y)
	assert_int(letters.body_scroll.scroll_vertical).is_equal(0)

	# Mouse wheel over the body scrolls it. Events go in as real GUI input,
	# in viewport coordinates (the headless window isn't the viewport's size).
	var centre := letters.body_scroll.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = pressed
		wheel.position = centre
		wheel.global_position = centre
		get_viewport().push_input(wheel, true)
	await settle_letter()
	var after_wheel := letters.body_scroll.scroll_vertical
	assert_int(after_wheel).is_greater(0)

	# So does dragging the text up with the mouse.
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(0, -30)
	drag.position = centre
	drag.global_position = centre
	get_viewport().push_input(drag, true)
	await settle_letter()
	assert_int(letters.body_scroll.scroll_vertical).is_greater(after_wheel)

	# Scrolled to the end, the button is still in place.
	letters.body_scroll.scroll_vertical = 100000
	await settle_letter()
	assert_letter_fits("orientation, scrolled")
	assert_int(letters.body_scroll.scroll_vertical).is_greater(0)

	# The next letter starts at the top again.
	letters.action_button.pressed.emit()
	letters._on_probation_completed()
	await settle_letter()
	assert_int(letters.body_scroll.scroll_vertical).is_equal(0)

func test_a_short_letter_stays_compact() -> void:
	# After a long letter, so it has to shrink back.
	letters.show_branch_orientation_once()
	await settle_letter()
	var long_height := panel_rect().size.y
	letters.action_button.pressed.emit()

	letters._on_probation_completed()
	await settle_letter()
	assert_letter_fits("probation complete")
	assert_bool(body_scrolls()).is_false()
	var short_height := panel_rect().size.y
	assert_float(short_height).is_less(long_height - 100.0)
	assert_float(short_height).is_less(WINDOW_HEIGHT * 0.5)
	# The scroll area is exactly the body's height: all of it shows.
	assert_float(letters.body_scroll.size.y).is_equal_approx(letters.body_label.get_combined_minimum_size().y, 1.0)

func test_every_letter_fits_the_window() -> void:
	# Written warning.
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Alex Rivera")
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Sam Chen")
	await settle_letter()
	assert_str(letters.title_label.text).starts_with("Written Warning")
	assert_letter_fits("written warning")
	acknowledge_all()

	# Probation complete.
	letters._on_probation_completed()
	await settle_letter()
	assert_letter_fits("probation complete")
	acknowledge_all()

	# Promotion, then the orientation on the first Branch Manager clock-in.
	ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Jordan Blake")
	XPManager._grant_branch_manager()
	await settle_letter()
	assert_str(letters.title_label.text).is_equal("Letter of Promotion")
	assert_letter_fits("promotion")
	acknowledge_all()
	room.branch_manager_screen.show_screen()
	room.branch_manager_screen.clock_in_button.pressed.emit()
	await settle_letter()
	assert_str(letters.title_label.text).is_equal("Welcome to Branch Management")
	assert_letter_fits("orientation")
	acknowledge_all()

	# A staff termination, with a long list of reasons.
	var reasons: PackedStringArray = []
	for i in 12:
		reasons.append("wrong account on Customer %d's $200 deposit, caught after the customer had left the branch" % i)
	letters._on_staff_terminated("Walter Higgins", reasons)
	await settle_letter()
	assert_str(letters.title_label.text).contains("Walter Higgins")
	assert_letter_fits("staff termination")
	assert_bool(body_scrolls()).is_true()
	acknowledge_all()
	room.branch_manager_screen.hide_screen()

	# The player's termination (full-screen backdrop, same panel).
	var reports: Array[DisciplinaryReport] = []
	for i in 3:
		var report := DisciplinaryReport.new()
		report.number = i + 1
		report.reason = ReportManager.REPORT_REASONS[DecisionRecord.Role.TELLER]
		report.items = PackedStringArray(["Customer %d" % i, "Customer %d" % (i + 10)])
		reports.append(report)
	letters._on_termination_issued(reports)
	await settle_letter()
	assert_str(letters.action_button.text).is_equal("Apply for a new job")
	assert_letter_fits("termination")

# --- the orientation letter ------------------------------------------------------------

## Promotes the player (clicking away the promotion letter) and clocks in at
## the Branch Manager desk.
func promote_and_clock_in() -> void:
	XPManager._grant_branch_manager()
	acknowledge_all()
	room.branch_manager_screen.show_screen()
	room.branch_manager_screen.clock_in_button.pressed.emit()

func test_the_orientation_letter_shows_once_per_career() -> void:
	promote_and_clock_in()
	assert_bool(letters.visible).is_true()
	assert_str(letters.title_label.text).is_equal("Welcome to Branch Management")
	assert_bool(XPManager.has_seen_branch_orientation).is_true()
	acknowledge_all()

	# The next Branch Manager shift in the same career: no letter.
	var bm := room.branch_manager_screen
	bm._prepare_shift_summary()
	assert_bool(bm.is_clocked_in()).is_false()
	bm.clock_in_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_true()
	assert_bool(letters.visible).is_false()
	assert_bool(letters.show_branch_orientation_once()).is_false()

func test_the_orientation_letter_returns_in_a_new_career() -> void:
	promote_and_clock_in()
	assert_str(letters.title_label.text).is_equal("Welcome to Branch Management")
	acknowledge_all()

	# Fired and hired again: a new career, in a fresh room.
	CareerReset.reset_all()
	assert_bool(XPManager.has_seen_branch_orientation).is_false()
	room.free()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	letters = room.letter_screen

	promote_and_clock_in()
	assert_bool(letters.visible).is_true()
	assert_str(letters.title_label.text).is_equal("Welcome to Branch Management")
