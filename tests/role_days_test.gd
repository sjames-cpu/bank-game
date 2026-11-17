extends "res://tests/support/teller_room_suite.gd"

## Whole days with time slots on, played through the room as the player
## would, for the roles after the Teller (teller_day_test.gd has the
## Teller's): a Loan Officer's day (an application in each work slot, the
## clock-out at Closing, End of Day once), a Branch Manager's day (the
## armored truck holding 9 AM, "End this slot" in each work slot, the vault
## at Closing, End of Day once), and a Regional review day (the visit at
## 11 AM, the review's letter before the summary).

const STRAP := VaultManager.STRAP_CENTS

var eod: EndOfDayScreen
var card: SlotTransitionCard
var manager: ManagerSlotAdapter
var bm: BranchManagerScreen
var lo: LoanOfficerScreen
var skipped: Array[StringName] = []
var clean_slots: Array[StringName] = []

func before_test() -> void:
	await super()
	eod = room.end_of_day_screen
	card = room.slot_card
	manager = room.get_node("ManagerSlotAdapter")
	bm = room.branch_manager_screen
	lo = room.loan_officer_screen
	skipped.clear()
	clean_slots.clear()
	DayFlow.slot_skipped.connect(_on_slot_skipped)
	manager.clean_slot_rewarded.connect(_on_clean_slot)
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func after_test() -> void:
	DayFlow.slot_skipped.disconnect(_on_slot_skipped)
	await super()

func _on_slot_skipped(slot: DaySlot) -> void:
	skipped.append(slot.id)

func _on_clean_slot(slot: DaySlot) -> void:
	clean_slots.append(slot.id)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func current_id() -> StringName:
	return DayFlow.current_slot().id

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

const WORK_SLOTS: Array[StringName] = [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]

## Continue on the card that's up, as the player would.
func press_continue() -> void:
	await frames(1)
	assert_bool(card.visible).override_failure_message("no card is up").is_true()
	card.continue_button.pressed.emit()

## After the clock-out: the lobby empties (everyone still walking out
## leaves), then End of Day comes, once.
func end_of_day_once(day: int) -> void:
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)
	acknowledge_letters()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day %d" % day)
	assert_int(VaultManager.last_closed_day).is_equal(day)
	assert_int(LoanBookManager.last_closed_day).is_equal(day)
	assert_bool(SaveGame.exists()).is_true()
	# Once: nothing more happens while the summary waits.
	SaveGame.delete()
	await frames(5)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(DayFlow.is_running()).is_false()
	assert_bool(SaveGame.exists()).is_false()

# --- a Loan Officer's day --------------------------------------------------------------------

func test_a_full_loan_officer_day() -> void:
	# The staff desks' own walk-ins aren't part of this day.
	for worker in room.loan_desk_workers:
		worker.active = false
	XPManager.is_loan_officer_unlocked = true
	start_slots_day()
	await frames(2)
	assert_str(current_id()).is_equal(DaySchedule.OPENING)
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	await press_continue()
	var review := lo.loan_review_screen
	for id in WORK_SLOTS:
		assert_str(current_id()).is_equal(id)
		# The slot's applicant walks in and sits down.
		room._process(0.0)
		var seat := room.player_loan_seat()
		assert_bool(seat.is_empty()).is_false()
		room._on_loan_officer_desk_interacted()
		lo.review_next_button.pressed.emit()
		review.verify_documents_button.pressed.emit()
		review.run_credit_check_button.pressed.emit()
		review.approve_button.pressed.emit()
		review.close_button.pressed.emit()
		lo.hide_screen()
		seat.finish_leaving()
		await press_continue()
	assert_int(lo.applications_reviewed).is_equal(4)
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(2)
	assert_bool(eod.visible).is_false()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()
	assert_str(lo.shift_applications_reviewed_label.text).is_equal("Applications Reviewed: 4")
	lo.hide_screen()
	assert_array(skipped).is_empty()
	await end_of_day_once(1)

# --- a Branch Manager's day ------------------------------------------------------------------

## Promoted, with cash ordered for today so the armored truck comes.
func manager_career(day: int) -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	GameClock.day = day
	BusinessDay.stats_day = day
	assert_str(VaultManager.place_order(5 * STRAP, day - 1)).is_empty()

## Received at the vault door with a witness: crew checked, bags signed for.
func receive_the_truck() -> void:
	for guard: StaffNPC in room.armored_visit.guards.duplicate():
		guard.finish_route()
	assert_bool(room.armored_visit.is_waiting()).is_true()
	var witness := call_vault_witness()
	assert_object(witness).is_not_null()
	var screen := room.armored_truck_screen
	assert_bool(screen.visible).is_true()
	screen.accept_crew_button.pressed.emit()
	screen.sign_button.pressed.emit()
	screen.close_button.pressed.emit()
	witness.finish_route()

## A Branch Manager's whole day: clock in, the truck and "End this slot" at
## 9 AM, "End this slot" in each other work slot (calling `at_slot` first in
## each, if given), the vault and the clock-out at Closing.
func play_manager_day(at_slot: Callable = Callable()) -> void:
	start_slots_day()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	bm.hide_screen()
	acknowledge_letters()
	await press_continue()
	for id in WORK_SLOTS:
		assert_str(current_id()).is_equal(id)
		if at_slot.is_valid():
			await at_slot.call(id)
		if id == DaySchedule.SLOT_9AM:
			# The truck holds 9 AM: "End this slot" first, then the truck.
			manager.bar.end_button.pressed.emit()
			await frames(2)
			assert_str(current_id()).is_equal(DaySchedule.SLOT_9AM)
			assert_bool(DayFlow.is_between_slots()).is_false()
			receive_the_truck()
		else:
			await frames(1)
			assert_bool(manager.bar.visible).is_true()
			manager.bar.end_button.pressed.emit()
		await frames(2)
		await press_continue()
	assert_str(current_id()).is_equal(DaySchedule.CLOSING)
	await frames(2)
	assert_bool(eod.visible).is_false()
	reconcile_vault()
	bm.clock_out_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_false()
	bm.hide_screen()

func test_a_full_branch_manager_day() -> void:
	manager_career(3)
	var vault_before := VaultManager.expected_cents
	await play_manager_day()
	assert_array(skipped).is_empty()
	assert_array(clean_slots).is_equal(WORK_SLOTS)
	# The truck's cash reached the vault (the staff windows' net comes later,
	# at the close).
	assert_bool(VaultManager.has_visit_due(3)).is_false()
	assert_int(VaultManager.expected_cents - vault_before).is_equal(5 * STRAP)
	await end_of_day_once(3)

func test_a_regional_review_day() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var day := RegionalManager.next_review_day()
	manager_career_on(day)
	var reviews: Array[Dictionary] = []
	var on_review := func(result: Dictionary) -> void: reviews.append(result)
	RegionalManager.review_completed.connect(on_review)
	var visited: Array[StringName] = []
	await play_manager_day(func(id: StringName) -> void:
		# Here, and not on their way out.
		if is_instance_valid(room.regional_visitor) and not room._visitor_leaving:
			visited.append(id))
	# The visit came in the 11 AM slot only.
	assert_array(visited).is_equal([DaySchedule.SLOT_11AM])
	# End of Day: the review's letter first, then the summary.
	for line: CustomerQueue in [cq, room.window1_npc_line, room.window2_line, room.window3_line]:
		line.clear_lobby()
	await frames(2)
	assert_int(reviews.size()).is_equal(1)
	assert_bool(room.letter_screen.visible).is_true()
	assert_str(room.letter_screen.from_label.text).is_equal("From: Regional Manager")
	assert_bool(eod.visible).is_false()
	RegionalManager.review_completed.disconnect(on_review)
	await end_of_day_once(day)

## Today is `day`, with cash ordered for it (already promoted).
func manager_career_on(day: int) -> void:
	GameClock.day = day
	BusinessDay.stats_day = day
	assert_str(VaultManager.place_order(5 * STRAP, day - 1)).is_empty()
