extends "res://tests/support/teller_room_suite.gd"

## The Loan Officer's work slots (LoanSlotAdapter): on a Loan Officer day
## each work slot brings one application and waits until it's decided
## (closing the review without deciding doesn't count); a full day is four;
## a skipped slot drops its application with no penalty; clocking out before
## Closing is refused; with slots off the old three per shift still holds;
## and on a Teller day the adapter does nothing.

var lo: LoanOfficerScreen
var review: LoanReviewScreen
var adapter: LoanSlotAdapter

func before_test() -> void:
	await super()
	lo = room.loan_officer_screen
	review = lo.loan_review_screen
	adapter = room.get_node("LoanSlotAdapter")
	# The staff desks' own walk-ins aren't part of these tests.
	for worker in room.loan_desk_workers:
		worker.active = false

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func loan_clock_in() -> void:
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()

## A Loan Officer day, clocked in at Opening, with 9 AM started.
func loan_day_at_9am() -> void:
	start_slots_day()
	loan_clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)

## Opens the next application at the desk and, if `decide`, approves it;
## then closes both screens.
func review_next(decide: bool = true) -> void:
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	if decide:
		review.approve_button.pressed.emit()
	review.close_button.pressed.emit()
	lo.hide_screen()

func test_each_slot_waits_for_its_application() -> void:
	loan_day_at_9am()
	assert_bool(adapter.is_claimed()).is_true()
	assert_int(lo.applications_left()).is_equal(1)
	await frames(3)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()
	# The applicant walks in for this slot's application.
	room._process(0.0)
	assert_bool(room.player_loan_seat().is_empty()).is_false()

	review_next()
	assert_int(lo.applications_reviewed).is_equal(1)
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_str(DayFlow.next_slot().id).is_equal(DaySchedule.SLOT_11AM)
	# Nothing more until the next slot.
	assert_int(lo.applications_left()).is_equal(0)

func test_closing_the_review_without_deciding_does_not_finish_the_slot() -> void:
	loan_day_at_9am()
	var pending := LoanDeskManager.current_player_application()
	review_next(false)
	await frames(3)
	assert_int(lo.applications_reviewed).is_equal(0)
	assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
	assert_bool(DayFlow.is_between_slots()).is_false()
	# The same application comes back, and deciding it ends the slot.
	assert_object(LoanDeskManager.current_player_application()).is_same(pending)
	review_next()
	await frames(2)
	assert_bool(DayFlow.is_between_slots()).is_true()

func test_a_full_day_is_four_applications() -> void:
	loan_day_at_9am()
	var slots: Array[StringName] = [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]
	for id in slots:
		continue_to_slot(id)
		assert_str(current_id()).is_equal(id)
		assert_int(lo.applications_left()).is_equal(1)
		review_next()
		await frames(2)
		assert_bool(DayFlow.is_between_slots()).override_failure_message("%s didn't end" % id).is_true()
	assert_int(lo.applications_reviewed).is_equal(4)
	continue_to_slot(DaySchedule.CLOSING)
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	# Nothing left, so the clock-out goes through at Closing.
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()

func test_a_skipped_slot_drops_its_application() -> void:
	loan_day_at_9am()
	room._process(0.0)
	var seat := room.player_loan_seat()
	assert_bool(seat.is_empty()).is_false()
	var waiting := seat.application
	var score := ScoreManager.total_score
	var reputation := ReputationManager.reputation
	DayFlow.skip_slot()
	assert_bool(DayFlow.is_between_slots()).is_true()
	assert_bool(adapter.is_claimed()).is_false()
	assert_int(lo.applications_left()).is_equal(0)
	assert_int(seat.phase).is_equal(LoanDeskSeat.Phase.LEAVING)
	# No penalty.
	assert_int(ScoreManager.total_score).is_equal(score)
	assert_int(ReputationManager.reputation).is_equal(reputation)
	# The next slot brings one again: the same applicant, still first.
	continue_to_slot(DaySchedule.SLOT_11AM)
	assert_int(lo.applications_left()).is_equal(1)
	assert_object(LoanDeskManager.current_player_application()).is_same(waiting)

func test_clocking_out_before_closing_is_refused() -> void:
	loan_day_at_9am()
	review_next()
	await frames(2)
	continue_to_slot(DaySchedule.SLOT_11AM)
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_true()
	assert_str(lo.error_label.text).is_equal("Can't clock out yet — %s." % ShiftSlotAdapter.CLOCK_OUT_REFUSED_TEXT)

func test_with_slots_off_three_applications_per_shift() -> void:
	GameClock.minutes = 10 * 60.0
	loan_clock_in()
	assert_int(lo.applications_per_shift).is_equal(LoanOfficerScreen.APPLICATIONS_PER_SHIFT)
	assert_int(lo.applications_left()).is_equal(3)
	for i in 2:
		review_next()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_true()
	assert_str(lo.error_label.text).is_equal("Can't clock out yet — 1 application still to review.")
	lo.hide_screen()
	review_next()
	assert_bool(lo.review_next_button.disabled).is_true()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()

func test_it_does_nothing_on_a_teller_day() -> void:
	start_slots_day()
	clock_in()
	continue_to_slot(DaySchedule.SLOT_9AM)
	assert_int(PlayerShift.role_today).is_equal(PlayerShift.Role.TELLER)
	assert_bool(adapter.is_claimed()).is_false()
	assert_int(lo.applications_per_shift).is_equal(0)
	assert_bool(DayFlow.has_claimed(adapter)).is_false()
