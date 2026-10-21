extends "res://tests/support/teller_room_suite.gd"

## B7: the F1 debug unlock only works in debug builds; so does F2, which
## unlocks Loan Officer only.
## B8: a role unlock that needs XP and Reputation fires when Reputation is
## the last threshold crossed — not only on the next XP gain.

func _press_f1() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F1
	event.pressed = true
	room._unhandled_input(event)

func test_f1_does_nothing_in_a_release_build() -> void:
	room.debug_cheats_enabled = false
	var start_totals := totals()
	_press_f1()
	assert_vector(totals()).is_equal(start_totals)
	assert_bool(XPManager.is_loan_officer_unlocked).is_false()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()

func test_f1_unlocks_in_a_debug_build() -> void:
	room.debug_cheats_enabled = true
	_press_f1()
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()

func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.pressed = true
	room._unhandled_input(event)

func test_f2_does_nothing_in_a_release_build() -> void:
	room.debug_cheats_enabled = false
	var start_totals := totals()
	_press_f2()
	assert_vector(totals()).is_equal(start_totals)
	assert_bool(XPManager.is_loan_officer_unlocked).is_false()

func test_f2_unlocks_only_loan_officer() -> void:
	room.debug_cheats_enabled = true
	_press_f2()
	assert_int(XPManager.total_xp).is_equal(XPManager.XP_UNLOCK_THRESHOLD)
	assert_int(ReputationManager.reputation).is_equal(TellerRoom.DEBUG_LOAN_OFFICER_REPUTATION)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	# Pressed again, or with more already, it never lowers anything.
	_press_f2()
	assert_int(XPManager.total_xp).is_equal(XPManager.XP_UNLOCK_THRESHOLD)

func test_f2_never_lowers_progress_or_promotes() -> void:
	room.debug_cheats_enabled = true
	XPManager.total_xp = 1600
	ReputationManager.reputation = 55
	_press_f2()
	assert_int(XPManager.total_xp).is_equal(1600)
	assert_int(ReputationManager.reputation).is_equal(55)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	ReputationManager.reputation = 20
	_press_f2()
	assert_int(ReputationManager.reputation).is_equal(TellerRoom.DEBUG_LOAN_OFFICER_REPUTATION)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()

func test_reputation_rise_alone_unlocks_loan_officer() -> void:
	ReputationManager.add_reputation(XPManager.REPUTATION_UNLOCK_FLOOR - 1 - ReputationManager.reputation)
	XPManager.add_shift_xp(ceili(float(XPManager.XP_UNLOCK_THRESHOLD) / XPManager.XP_PER_SCORE_POINT))
	assert_int(XPManager.total_xp).is_equal(XPManager.XP_UNLOCK_THRESHOLD)
	assert_bool(XPManager.is_loan_officer_unlocked).is_false()

	var signal_monitor := monitor_signals(XPManager, false)
	ReputationManager.add_reputation(1)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	# gdUnit's is_emitted() is a coroutine at runtime; its declared type isn't.
	@warning_ignore("redundant_await")
	await assert_signal(signal_monitor).is_emitted("loan_officer_unlocked")

func test_reputation_rise_alone_unlocks_branch_manager() -> void:
	XPManager.add_shift_xp(ceili(float(XPManager.XP_UNLOCK_THRESHOLD_BRANCH_MANAGER) / XPManager.XP_PER_SCORE_POINT))
	assert_int(ReputationManager.reputation).is_less(XPManager.REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	ReputationManager.add_reputation(XPManager.REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER - ReputationManager.reputation)
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
