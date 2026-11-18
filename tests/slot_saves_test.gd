extends "res://tests/support/teller_room_suite.gd"

## Saving on a time-slot day (SlotSavePolicy, DayFlow's day_ended flag):
## a career is saved only at the start of a day (Start Day N+1, onboarding,
## the orientation letter) and once it has ended (End of Day), never inside
## the day (a clock-out at Closing, a promotion granted there, a save asked
## for mid-day). A save whose day had ended loads into that End of Day again,
## once; any other loads into that day from Opening. A promotion day that's
## replayed gives one promotion and one letter each time.

const PROMOTION_TITLE := "Letter of Promotion"

var eod: EndOfDayScreen
var letters: DisciplineLetterScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen
	letters = room.letter_screen
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

## The room loaded again from the current save, as the slot screen does.
func load_saved_career(keep_onboarding: bool = false) -> void:
	var saved := SaveGame.read()
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	get_tree().paused = false
	room.free()
	SaveGame.restore(saved.career)
	var fresh := instantiate_room()
	get_tree().root.add_child(fresh)
	get_tree().current_scene = fresh
	adopt_room(fresh, keep_onboarding)
	eod = room.end_of_day_screen
	letters = room.letter_screen
	await frames(1)

func saved_day_ended() -> bool:
	return SaveGame.read_day_ended(SaveGame.read().career)

## A Teller day straight to Closing (going home at the first card), clocked
## out; the lobby emptied so End of Day can come.
func teller_day_to_closing_clock_out() -> void:
	start_slots_day()
	clock_in()
	DayFlow.go_home_early()
	assert_bool(clock_out()).is_true()
	close_desk()

func empty_lobby() -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()

# --- when it may save -----------------------------------------------------------------------

func test_the_policy() -> void:
	assert_bool(SlotSavePolicy.may_save()).is_true() # Opening, before the clock-in
	start_slots_day()
	assert_bool(SlotSavePolicy.may_save()).is_true() # Opening
	clock_in()
	assert_bool(SlotSavePolicy.may_save()).is_true() # Opening done, before 9 AM
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_bool(SlotSavePolicy.may_save()).is_false() # a work slot
	DayFlow.skip_slot()
	assert_bool(SlotSavePolicy.may_save()).is_false() # between slots
	DayFlow.go_home_early()
	assert_bool(SlotSavePolicy.may_save()).is_false() # Closing, on shift
	assert_bool(clock_out()).is_true()
	close_desk()
	assert_bool(SlotSavePolicy.may_save()).is_true() # the day has ended

func test_nothing_is_saved_mid_day() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	SaveGame.delete()
	room.save_career()
	assert_bool(SaveGame.exists()).is_false()

func test_the_closing_clock_out_does_not_save_but_end_of_day_does() -> void:
	start_slots_day()
	clock_in()
	DayFlow.go_home_early()
	SaveGame.delete()
	assert_bool(clock_out()).is_true()
	close_desk()
	# The clock-out itself saved nothing (the day ends with it, and End of
	# Day saves).
	assert_bool(SaveGame.exists()).is_false()
	empty_lobby()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(SaveGame.exists()).is_true()
	assert_bool(saved_day_ended()).is_true()

func test_start_day_n_plus_1_saves_the_new_days_start() -> void:
	teller_day_to_closing_clock_out()
	empty_lobby()
	await frames(2)
	SaveGame.delete()
	eod.next_day_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_true()
	assert_bool(saved_day_ended()).is_false()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "clock"), "day", -1)).is_equal(2)

func test_onboarding_saves_its_steps_at_opening() -> void:
	OnboardingManager.reset()
	SaveGame.delete()
	room.save_career() # the career's first save, as a new game makes
	await load_saved_career(true)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_bool(letters.visible).is_true()
	SaveGame.delete()
	letters.action_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "onboarding"), "step", -1)).is_equal(OnboardingManager.Step.CONTRACT)
	assert_bool(saved_day_ended()).is_false()

func test_the_orientation_letter_saves_at_opening() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	start_slots_day()
	SaveGame.delete()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	assert_bool(SaveGame.exists()).is_true()
	assert_bool(SaveGame.bool_of(SaveGame.dict_of(SaveGame.read().career, "xp"), "has_seen_branch_orientation", false)).is_true()

# --- loading ---------------------------------------------------------------------------------

func test_a_day_that_ended_loads_into_its_end_of_day_once() -> void:
	teller_day_to_closing_clock_out()
	empty_lobby()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	var vault := VaultManager.expected_cents
	var closed := VaultManager.last_closed_day
	var score := ScoreManager.total_score
	await load_saved_career()
	assert_bool(DayFlow.end_of_day_due).is_true()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	# The End of Day's work isn't done twice.
	assert_int(VaultManager.expected_cents).is_equal(vault)
	assert_int(VaultManager.last_closed_day).is_equal(closed)
	assert_int(ScoreManager.total_score).is_equal(score)
	eod.next_day_button.pressed.emit()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_int(GameClock.day).is_equal(2)

func test_a_day_that_had_not_ended_loads_into_opening() -> void:
	start_slots_day()
	room.save_career()
	assert_bool(saved_day_ended()).is_false()
	await load_saved_career()
	assert_bool(DayFlow.is_running()).is_true()
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	assert_str(GameClock.time_text()).is_equal("8:30 AM")
	assert_bool(eod.visible).is_false()

# --- a promotion -------------------------------------------------------------------------------

var promotions: int = 0

func _on_promoted() -> void:
	promotions += 1

## A Teller day that earns the promotion: XP mid-shift (held until the
## clock-out), the clock-out at Closing, then its letter. Returns how many
## promotion letters were shown.
func play_promotion_day() -> int:
	start_slots_day()
	clock_in()
	XPManager.add_shift_xp(5)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	continue_to_slot(DaySchedule.SLOT_9AM)
	DayFlow.skip_slot()
	DayFlow.go_home_early()
	assert_bool(clock_out()).is_true()
	close_desk()
	var shown := 0
	while letters.visible:
		if letters.title_label.text == PROMOTION_TITLE:
			shown += 1
		letters.action_button.pressed.emit()
	return shown

func test_a_replayed_promotion_day_gives_one_letter_and_one_promotion() -> void:
	XPManager.is_loan_officer_unlocked = true
	XPManager.total_xp = XPManager.XP_UNLOCK_THRESHOLD_BRANCH_MANAGER - 10
	ReputationManager.reputation = XPManager.REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER
	room.save_career() # the start of the day's save
	XPManager.branch_manager_unlocked.connect(_on_promoted)
	assert_int(play_promotion_day()).is_equal(1)
	assert_int(promotions).is_equal(1)
	# Promoted at Closing, before End of Day: nothing saved yet.
	assert_bool(SaveGame.bool_of(SaveGame.dict_of(SaveGame.read().career, "xp"), "is_branch_manager_unlocked", true)).is_false()

	# Quit before End of Day: the day replays from its start.
	await load_saved_career()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_int(play_promotion_day()).is_equal(1)
	assert_int(promotions).is_equal(2) # one in each play of the day

	# This time End of Day comes and saves the Branch Manager.
	empty_lobby()
	await frames(2)
	acknowledge_letters()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(saved_day_ended()).is_true()
	await load_saved_career()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	await frames(3)
	# Loaded: no promotion again, and no second letter.
	assert_int(promotions).is_equal(2)
	assert_bool(letters.visible and letters.title_label.text == PROMOTION_TITLE).is_false()
	XPManager.branch_manager_unlocked.disconnect(_on_promoted)
