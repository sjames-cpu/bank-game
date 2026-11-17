extends "res://tests/support/teller_room_suite.gd"

## Saves made before the slot system, or with the switch off, loaded into a
## time-slot day (tests/data/old_saves/, real careers written the way their
## version wrote them):
## - a version 1 save made part-way through a day (a clock-out at 2:15 PM)
##   replays that day from Opening, its day-only counters started again;
## - a version 1 save made at the End of Day summary (5 PM) shows that End
##   of Day again, without doing its work twice;
## - a version 1 save made during onboarding resumes it at Opening;
## - a version 1 save made at a mid-day promotion is a Branch Manager at
##   Opening, with no second promotion letter;
## - a version 2 save made mid-day with the switch off replays from Opening.
## Career progress always survives. With the switch off, each loads exactly
## as before.

const SAMPLES := "res://tests/data/old_saves/"

var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func sample_text(file_name: String) -> String:
	return FileAccess.get_file_as_string(SAMPLES + file_name)

func sample_career(file_name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(sample_text(file_name))
	var root: Dictionary = parsed
	return root["career"]

## The sample put in the test slot and loaded as the slot screen does: read,
## restored, and the room started.
func load_sample(file_name: String, keep_onboarding: bool = false) -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string(sample_text(file_name))
	file.close()
	var saved := SaveGame.read()
	assert_int(saved.status).override_failure_message("%s: read status %d" % [file_name, saved.status]).is_equal(SaveGame.Status.OK)
	room.free()
	SaveGame.restore(saved.career)
	var fresh := instantiate_room()
	get_tree().root.add_child(fresh)
	get_tree().current_scene = fresh
	adopt_room(fresh, keep_onboarding)
	eod = room.end_of_day_screen
	await frames(1)

func balance_of(account_name: String) -> int:
	for account in AccountManager.accounts:
		if account.customer_name == account_name:
			return account.balance_cents
	return -1

# --- with slots on -------------------------------------------------------------------------

func test_a_mid_day_save_replays_its_day_from_opening() -> void:
	use_slots_setting(true)
	var career := sample_career("v1_mid_day.json")
	var vault := SaveGame.int_of(SaveGame.dict_of(career, "vault"), "expected_cents", -1)
	await load_sample("v1_mid_day.json")
	# Day 3 from Opening.
	assert_bool(DayFlow.is_running()).is_true()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(GameClock.day).is_equal(3)
	assert_str(GameClock.time_text()).is_equal("8:30 AM")
	assert_bool(eod.visible).is_false()
	# Career progress kept.
	assert_int(XPManager.total_xp).is_equal(820)
	assert_int(ScoreManager.total_score).is_equal(82)
	assert_int(ReputationManager.reputation).is_equal(57)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_int(balance_of("Priya Shah")).is_equal(125000)
	assert_int(VaultManager.expected_cents).is_equal(vault)
	assert_int(BusinessDay.stats_day).is_equal(3)
	# Day-only counters start again; real money stays.
	assert_int(BusinessDay.customers_served_by_player).is_equal(0)
	assert_int(BusinessDay.customers_served_by_staff).is_equal(0)
	assert_int(BusinessDay.shifts_completed).is_equal(0)
	assert_int(BusinessDay.score_at_start).is_equal(82)
	assert_int(BusinessDay.reputation_at_start).is_equal(57)
	assert_int(BusinessDay.xp_at_start).is_equal(820)
	assert_int(BusinessDay.staff_net_cash_cents).is_equal(41250)
	# The replayed day runs to its End of Day, once.
	clock_in()
	DayFlow.go_home_early()
	assert_bool(clock_out()).is_true()
	close_desk()
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 3")
	assert_int(VaultManager.last_closed_day).is_equal(3)
	assert_bool(SaveGame.read_day_ended(SaveGame.read().career)).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "business_day"), "customers_served_by_player", -1)).is_equal(0)

func test_an_end_of_day_save_shows_that_end_of_day_again_once() -> void:
	use_slots_setting(true)
	var career := sample_career("v1_end_of_day.json")
	var vault := SaveGame.int_of(SaveGame.dict_of(career, "vault"), "expected_cents", -1)
	await load_sample("v1_end_of_day.json")
	assert_bool(DayFlow.end_of_day_due).is_true()
	assert_bool(DayFlow.is_running()).is_false()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 4")
	# Its work isn't done again: the vault and the loans had closed Day 4.
	assert_int(VaultManager.expected_cents).is_equal(vault)
	assert_int(VaultManager.last_closed_day).is_equal(4)
	assert_int(LoanBookManager.last_closed_day).is_equal(4)
	# Today's figures stay (the day had ended).
	assert_int(BusinessDay.customers_served_by_player).is_equal(8)
	assert_int(XPManager.total_xp).is_equal(900)
	eod.next_day_button.pressed.emit()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(GameClock.day).is_equal(5)

func test_an_onboarding_save_resumes_onboarding_at_opening() -> void:
	use_slots_setting(true)
	await load_sample("v1_onboarding.json", true)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(OnboardingManager.step).is_equal(OnboardingManager.Step.CONTRACT)
	assert_bool(room.letter_screen.visible).is_true()
	assert_str(room.letter_screen.title_label.text).is_equal(OnboardingData.CONTRACT_TITLE)

func test_a_promotion_save_is_a_branch_manager_at_opening() -> void:
	use_slots_setting(true)
	var promoted := [0]
	var on_promoted := func() -> void: promoted[0] += 1
	XPManager.branch_manager_unlocked.connect(on_promoted)
	await load_sample("v1_promotion.json")
	await frames(2)
	XPManager.branch_manager_unlocked.disconnect(on_promoted)
	assert_int(promoted[0]).is_equal(0)
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_int(XPManager.total_xp).is_equal(1600)
	assert_int(GameClock.day).is_equal(9)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(room.letter_screen.visible and room.letter_screen.title_label.text == "Letter of Promotion").is_false()
	assert_bool(room.branch_manager_desk.visible).is_true()
	# The day works as a Branch Manager's.
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.BRANCH_MANAGER)

func test_a_switch_off_mid_day_save_replays_from_opening() -> void:
	use_slots_setting(true)
	await load_sample("v2_switch_off_mid_day.json")
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(GameClock.day).is_equal(2)
	assert_int(ScoreManager.total_score).is_equal(15)
	assert_int(BusinessDay.customers_served_by_player).is_equal(0)

func test_the_slot_screen_says_where_each_save_picks_up() -> void:
	use_slots_setting(true)
	assert_str(StartScreen.game_date_of(sample_career("v1_mid_day.json"))).ends_with("· " + StartScreen.DAY_START_TEXT)
	assert_str(StartScreen.game_date_of(sample_career("v1_end_of_day.json"))).ends_with("· " + StartScreen.DAY_ENDED_TEXT)

# --- every sample ------------------------------------------------------------------------------

func test_every_sample_reads_ok() -> void:
	for file_name: String in DirAccess.get_files_at(SAMPLES):
		if not file_name.ends_with(".json"):
			continue
		assert_int(SaveGame.read_file(SAMPLES + file_name).status).override_failure_message(file_name).is_equal(SaveGame.Status.OK)
