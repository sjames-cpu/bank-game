extends "res://tests/support/teller_room_suite.gd"

## Three staffed loan desks (ScheduleManager.LOAN_DESK_SLOTS, one
## NpcLoanDeskWorker each): all three are staffed and decide applications;
## clocking in at Loan Desk 1 sends its officer to the break room and back
## while Loan Desks 2 and 3 keep working; promotion locks Loan Desk 1 and
## keeps every desk staffed, and a demotion opens it again; vacancies and
## the Branch summary list each desk; old saves' "Loan Desk" becomes Loan
## Desk 1. (F2 is tested with F1, in b7_b8_unlock_test.gd.)

const SLOTS := ScheduleManager.LOAN_DESK_SLOTS

var lo: LoanOfficerScreen

func before_test() -> void:
	await super()
	lo = room.loan_officer_screen

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func worker_for(slot_name: String) -> NpcLoanDeskWorker:
	for worker in room.loan_desk_workers:
		if worker.slot_name == slot_name:
			return worker
	return null

func staff_records(slot_name: String) -> int:
	var count := 0
	for record in HistoryManager.records:
		if record.role == DecisionRecord.Role.STAFF and record.staff_slot == slot_name:
			count += 1
	return count

## Lets every loan worker reach its decision time and run one frame of
## _process() (the branch open, the tree running).
func one_decision_each() -> void:
	for worker in room.loan_desk_workers:
		worker._elapsed = 1000.0
	await frames(2)

func open_branch() -> void:
	GameClock.minutes = 10 * 60.0
	BusinessDay.stats_day = GameClock.day

# --- staffed and deciding ------------------------------------------------------------

func test_three_loan_desks_are_staffed_and_decide() -> void:
	assert_array(SLOTS).is_equal(["Loan Desk 1", "Loan Desk 2", "Loan Desk 3"])
	var names: Array[String] = []
	for slot_name in SLOTS:
		var member := ScheduleManager.get_assigned(slot_name)
		assert_object(member).override_failure_message("%s unstaffed" % slot_name).is_not_null()
		assert_str(member.role).is_equal("Loan Officer")
		assert_bool(names.has(member.staff_name)).is_false()
		names.append(member.staff_name)
		var npc: StaffNPC = room._staff_by_slot[slot_name]
		assert_int(npc.state).is_equal(StaffNPC.State.AT_DESK)
		assert_vector(npc.global_position).is_equal(room._desk_spot(slot_name))
		assert_object(worker_for(slot_name).staff_npc).is_same(npc)
	assert_array(names).is_equal(["Priya Anand", "Marcus Chen", "Sana Malik"])
	# Every desk is a slot of its own, and none is vacant.
	assert_array(ScheduleManager.vacant_slots()).is_empty()
	assert_str(ScheduleManager.role_for_slot("Loan Desk 3")).is_equal("Loan Officer")

	open_branch()
	await one_decision_each()
	for slot_name in SLOTS:
		assert_int(staff_records(slot_name)).override_failure_message("%s made no decision" % slot_name).is_equal(1)
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).contains("(Loan Desk 3)")
	assert_str(record.staff_name).is_equal("Sana Malik")
	# Closed: no decisions.
	GameClock.minutes = 18 * 60.0
	await one_decision_each()
	for slot_name in SLOTS:
		assert_int(staff_records(slot_name)).is_equal(1)

# --- the player's desk -----------------------------------------------------------------

func test_clocking_in_at_loan_desk_1_swaps_its_officer_out_and_back() -> void:
	open_branch()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_true()
	lo.close_button.pressed.emit()
	# Loan Desk 1's officer stops and heads for the break room...
	var npc_1: StaffNPC = room._staff_by_slot[ScheduleManager.SLOT_LOAN_DESK_1]
	assert_bool(room.loan_desk_worker.active).is_false()
	assert_int(npc_1.state).is_not_equal(StaffNPC.State.AT_DESK)
	assert_vector(npc_1._route.back() if not npc_1._route.is_empty() else npc_1.global_position).is_equal(room._break_spot_for(ScheduleManager.SLOT_LOAN_DESK_1))
	# ...while Loan Desks 2 and 3 keep working.
	for slot_name: String in [ScheduleManager.SLOT_LOAN_DESK_2, ScheduleManager.SLOT_LOAN_DESK_3]:
		assert_bool(worker_for(slot_name).active).is_true()
		assert_int((room._staff_by_slot[slot_name] as StaffNPC).state).is_equal(StaffNPC.State.AT_DESK)
	await one_decision_each()
	assert_int(staff_records(ScheduleManager.SLOT_LOAN_DESK_1)).is_equal(0)
	assert_int(staff_records(ScheduleManager.SLOT_LOAN_DESK_2)).is_equal(1)
	assert_int(staff_records(ScheduleManager.SLOT_LOAN_DESK_3)).is_equal(1)
	assert_str(room.describe_shift_status()).is_equal("On shift — Loan Desk 1 · 3 applications left")

	# Clock-out: back to the desk, and deciding again once there.
	room._on_loan_officer_desk_interacted()
	lo.applications_reviewed = LoanOfficerScreen.APPLICATIONS_PER_SHIFT
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()
	assert_bool(room.loan_desk_worker.active).is_true()
	assert_vector(npc_1._route.back()).is_equal(room._desk_spot(ScheduleManager.SLOT_LOAN_DESK_1))
	lo.shift_summary_done_button.pressed.emit()
	if lo.visible:
		lo.close_button.pressed.emit()
	npc_1.place_at(room._desk_spot(ScheduleManager.SLOT_LOAN_DESK_1), StaffNPC.State.AT_DESK) # skip the walk
	await one_decision_each()
	assert_int(staff_records(ScheduleManager.SLOT_LOAN_DESK_1)).is_equal(1)

func test_promotion_locks_loan_desk_1_and_demotion_opens_it() -> void:
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	var officer := ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_1).staff_name
	assert_str(room.interaction_prompt_text(room.loan_officer_desk)).is_equal("%s is working Loan Desk 1." % officer)
	room._on_loan_officer_desk_interacted()
	assert_bool(lo.visible).is_false()
	assert_bool(room.desk_notice.visible).is_true()
	assert_str(room.desk_notice_label.text).is_equal("%s is working Loan Desk 1.%s" % [officer, TellerRoom.MANAGER_DESK_REMINDER])
	# Every desk staffed for good, Teller Window 3 by the third teller.
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_3).staff_name).is_equal("Nina Ortiz")
	for slot_name in SLOTS:
		assert_object(ScheduleManager.get_assigned(slot_name)).is_not_null()
		assert_bool(worker_for(slot_name).active).is_true()
	assert_array(ScheduleManager.vacant_slots()).is_empty()
	# Clocking in (if it ever happened) wouldn't send anyone away.
	room._on_player_clocked_in(ScheduleManager.SLOT_LOAN_DESK_1)
	assert_bool(room.loan_desk_worker.active).is_true()

	RegionalManager._demote()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	assert_str(room.interaction_prompt_text(room.loan_officer_desk)).is_equal("E — Clock in (Loan Desk 1)")
	for slot_name in SLOTS:
		assert_object(ScheduleManager.get_assigned(slot_name)).is_not_null()

# --- the manager's view ------------------------------------------------------------------

func test_each_loan_desk_counts_in_vacancies_and_the_branch_summary() -> void:
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	open_branch()
	await one_decision_each()
	var records: Array[DecisionRecord] = []
	for record in HistoryManager.records:
		if record.role == DecisionRecord.Role.STAFF:
			records.append(record)
	var summary := BranchManagerScreen.branch_summary_text(records)
	for slot_name in SLOTS:
		assert_str(summary).contains("%s — %s: 1 decision" % [slot_name, ScheduleManager.get_assigned(slot_name).staff_name])
	assert_str(summary).contains("Teller Window 3 — Nina Ortiz")
	# Loan work isn't counted as staff-line customers.
	assert_int(RegionalManager.staff_work).is_equal(3)
	assert_int(RegionalManager.staff_line_served).is_equal(0)

	# A loan officer let go leaves their own desk vacant, for hiring and the
	# Regional Manager's vacant desk-hours.
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_3).staff_name)
	assert_array(ScheduleManager.vacant_slots()).is_equal([ScheduleManager.SLOT_LOAN_DESK_3])
	assert_array(HiringManager.vacancies()).is_equal([ScheduleManager.SLOT_LOAN_DESK_3])
	assert_str(HiringManager.candidates_for(ScheduleManager.SLOT_LOAN_DESK_3)[0].role).is_equal("Loan Officer")
	assert_bool(room._staff_by_slot.has(ScheduleManager.SLOT_LOAN_DESK_3)).is_false()
	RegionalManager.sample_vacancies()
	var vacant_before := RegionalManager.vacant_desk_minutes
	GameClock.minutes += 60.0
	RegionalManager.sample_vacancies()
	assert_float(RegionalManager.vacant_desk_minutes - vacant_before).is_equal_approx(60.0, 0.01)
	assert_str(BranchManagerScreen.branch_summary_text([])).contains("Loan Desk 3 — Unassigned")

# --- old saves --------------------------------------------------------------------------

func test_an_old_saves_loan_desk_becomes_loan_desk_1() -> void:
	SaveGame.restore({
		"schedule": {"schedule": {"Teller Window 1": "Derek Voss", "Teller Window 2": "Walter Higgins", "Loan Desk": "Marcus Chen"}},
		"hiring": {"rejected_slots": ["Loan Desk"]},
	})
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_1).staff_name).is_equal("Marcus Chen")
	# The new desks get the loan officers nobody had placed.
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_2).staff_name).is_equal("Priya Anand")
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_3).staff_name).is_equal("Sana Malik")
	assert_array(HiringManager.rejected_slots).is_equal([ScheduleManager.SLOT_LOAN_DESK_1])
	# Saved again, it's the current format.
	var saved := ScheduleManager.save_data()
	assert_int(saved["slots_version"]).is_equal(ScheduleManager.SLOTS_VERSION)
	assert_dict(saved["schedule"]).contains_keys(["Loan Desk 1", "Loan Desk 2", "Loan Desk 3"])

	# A current save keeps a vacant loan desk vacant.
	SaveGame.restore({"schedule": {"slots_version": ScheduleManager.SLOTS_VERSION, "schedule": {"Loan Desk 1": "Priya Anand", "Loan Desk 2": "Marcus Chen"}}})
	assert_object(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_3)).is_null()
	# Old staff records under "Loan Desk" still count as loan work.
	assert_bool(ScheduleManager.is_loan_slot("Loan Desk")).is_true()
	assert_bool(ScheduleManager.is_loan_slot("Teller Window 1")).is_false()
