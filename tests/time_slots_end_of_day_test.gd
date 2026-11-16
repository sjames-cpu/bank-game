extends "res://tests/support/teller_room_suite.gd"

## End of Day with time slots on: it comes when DayFlow's day ends
## (day_ended), not when the clock shows 5 PM, through the room's usual End
## of Day (teller_room.show_end_of_day()), in the usual order: the vault and
## the loan book close, the Regional review's letter, then the summary, then
## the save. Once per day, and the mark that it's due never outlives its day.

var eod: EndOfDayScreen
var letters: DisciplineLetterScreen

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen
	letters = room.letter_screen
	use_slots_setting(true)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

## A day nobody works: Opening (which waits for a clock-in,
## ShiftSlotAdapter) is skipped, so the rest of the day runs straight through
## to day_ended with nobody on shift.
func run_unworked_day() -> void:
	DayFlow.start_day()
	if DayFlow.is_running() and DayFlow.current_slot().id == DaySchedule.OPENING:
		DayFlow.skip_slot()

func _hold_closing(slot: DaySlot) -> void:
	if slot.id == DaySchedule.CLOSING:
		DayFlow.hold(&"test holds Closing")

# --- the End of Day comes from day_ended -----------------------------------------------

func test_the_end_of_day_comes_when_the_day_ends() -> void:
	await frames(2)
	assert_bool(eod.visible).is_false()
	# Nobody works today, so the day runs straight through to day_ended.
	run_unworked_day()
	assert_bool(DayFlow.end_of_day_due).is_true()
	assert_str(GameClock.time_text()).is_equal("5:00 PM")
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 1")
	# The usual End of Day: the vault's and the loans' day closed, and saved.
	assert_int(VaultManager.last_closed_day).is_equal(1)
	assert_int(LoanBookManager.last_closed_day).is_equal(1)
	assert_bool(SaveGame.exists()).is_true()
	assert_int(SaveGame.int_of(SaveGame.dict_of(SaveGame.read().career, "business_day"), "stats_day", -1)).is_equal(1)

func test_5_pm_alone_does_not_end_the_day() -> void:
	# Closing has started (the clock shows 5:00 PM) but something holds it.
	DayFlow.slot_started.connect(_hold_closing)
	run_unworked_day()
	DayFlow.slot_started.disconnect(_hold_closing)
	assert_float(GameClock.minutes).is_equal(BusinessDay.CLOSE_MINUTES)
	assert_bool(BusinessDay.doors_closed()).is_true()
	await frames(3)
	assert_bool(eod.visible).is_false()
	assert_int(VaultManager.last_closed_day).is_equal(0)

	# Released: day_ended, and the End of Day.
	DayFlow.release(&"test holds Closing")
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()

func test_the_review_letter_comes_after_the_vault_and_loans_and_before_the_summary() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var day := RegionalManager.next_review_day()
	GameClock.day = day
	BusinessDay.stats_day = day
	var at_review: Dictionary = {}
	var reviews := [0]
	var on_review := func(_result: Dictionary) -> void:
		reviews[0] += 1
		at_review["vault"] = VaultManager.last_closed_day
		at_review["loans"] = LoanBookManager.last_closed_day
		at_review["summary"] = eod.visible
	RegionalManager.review_completed.connect(on_review)

	run_unworked_day()
	await frames(2)
	# The review ran after the vault's and loans' day closed, before the summary.
	assert_int(reviews[0]).is_equal(1)
	assert_dict(at_review).is_equal({"vault": day, "loans": day, "summary": false})
	assert_bool(letters.visible).is_true()
	assert_str(letters.from_label.text).is_equal("From: Regional Manager")
	assert_bool(eod.visible).is_false()

	# Acknowledged: the summary, saved, and still one review.
	SaveGame.delete()
	acknowledge_letters()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day %d" % day)
	assert_bool(SaveGame.exists()).is_true()
	await frames(3)
	assert_int(reviews[0]).is_equal(1)
	RegionalManager.review_completed.disconnect(on_review)

# --- once per day ---------------------------------------------------------------------

func test_the_end_of_day_runs_once_and_the_next_day_clears_the_mark() -> void:
	run_unworked_day()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	await frames(3)
	assert_bool(eod.is_summary_shown()).is_true()

	# "Start Day 2": the mark goes, so the summary doesn't come back.
	eod.next_day_button.pressed.emit()
	assert_bool(DayFlow.end_of_day_due).is_false()
	assert_bool(BusinessDay.is_day_over()).is_false()
	assert_int(BusinessDay.stats_day).is_equal(2)
	await frames(3)
	assert_bool(eod.visible).is_false()
	assert_int(VaultManager.last_closed_day).is_equal(1)

func test_a_new_day_and_a_new_career_clear_the_mark() -> void:
	run_unworked_day()
	assert_bool(DayFlow.end_of_day_due).is_true()
	# A new day in DayFlow (held at Opening so it doesn't run through).
	var hold_opening := func(slot: DaySlot) -> void:
		if slot.id == DaySchedule.OPENING:
			DayFlow.hold(&"test holds Opening")
	DayFlow.slot_started.connect(hold_opening)
	DayFlow.start_day()
	DayFlow.slot_started.disconnect(hold_opening)
	assert_bool(DayFlow.end_of_day_due).is_false()
	assert_bool(BusinessDay.is_day_over()).is_false()

	# A new career (CareerReset, as on the start screen).
	DayFlow.reset()
	run_unworked_day()
	assert_bool(DayFlow.end_of_day_due).is_true()
	CareerReset.reset_all()
	assert_bool(DayFlow.end_of_day_due).is_false()
	assert_bool(DayFlow.is_running()).is_false()

func test_with_slots_off_dayflow_never_ends_the_business_day() -> void:
	use_slots_setting(false)
	DayFlow.start_day()
	assert_bool(DayFlow.end_of_day_due).is_false()
	assert_bool(BusinessDay.is_day_over()).is_false()
	await frames(3)
	assert_bool(eod.visible).is_false()
