extends "res://tests/support/teller_room_suite.gd"

## Every screen that lists desks or staff fits the 1152x648 window with a
## Branch Manager's six desks (Teller Windows 1-3, Loan Desks 1-3): its
## panel and every visible control in it lie inside the panel, inside the
## window and left of the HUD column (layout_problems()). Covers Staff
## Scheduling, the Branch Manager hub and shift summary, Staff Review,
## Hiring and the Regional review letter.

var bm: BranchManagerScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	bm = room.branch_manager_screen
	XPManager._grant_branch_manager()
	acknowledge_letters()
	XPManager.has_seen_branch_orientation = true

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func assert_fits(panel: Control) -> void:
	await frames(4)
	var problems := layout_problems(panel)
	assert_array(problems).override_failure_message("%s:\n%s" % [panel.get_path(), "\n".join(problems)]).is_empty()

## A day's work at every desk, as the shift summary would list it.
func staff_work_everywhere() -> void:
	for slot in ScheduleManager.get_desk_slots():
		var slot_name: String = slot["name"]
		var member := ScheduleManager.get_assigned(slot_name)
		if member == null:
			continue
		for i in 3:
			HistoryManager.add_staff_record(member.staff_name, slot_name, "Work %d" % i, "Mistake" if i == 0 else "Correct")

func teller_mistake() -> void:
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	customer.display_name = "Sam Chen"
	customer.intent_type = ShiftTransaction.Type.DEPOSIT
	customer.intent_amount_cents = 20000
	var staff := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1)
	StaffReviewManager.add_teller_mistake(staff, ScheduleManager.SLOT_TELLER_WINDOW_1, customer, StaffReviewItem.TellerMistake.WRONG_ACCOUNT, "used the wrong account")

func open_hub() -> void:
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()

# --- the screens --------------------------------------------------------------------

func test_staff_scheduling_fits() -> void:
	assert_int(ScheduleManager.get_desk_slots().size()).is_equal(6)
	open_hub()
	var scheduling := bm.staff_scheduling_screen
	scheduling.show_screen()
	await assert_fits(scheduling.get_node("Panel") as Control)
	# After confirming, with its status line showing.
	scheduling.confirm_button.pressed.emit()
	assert_bool(scheduling.status_label.visible).is_true()
	await assert_fits(scheduling.get_node("Panel") as Control)

func test_the_branch_manager_hub_and_summary_fit() -> void:
	# A vacancy shows the Hire Staff button too: the hub at its fullest.
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_3).staff_name)
	open_hub()
	assert_bool(bm.hire_staff_button.visible).is_true()
	await assert_fits(bm.get_node("Panel") as Control)
	staff_work_everywhere()
	teller_mistake()
	bm._prepare_shift_summary()
	var summary: Control = bm.get_node("ShiftSummaryPanel")
	(bm.get_node("Panel") as Control).visible = false
	summary.visible = true
	await assert_fits(summary)

func test_staff_review_fits() -> void:
	teller_mistake()
	open_hub()
	bm.staff_review_screen.show_screen()
	await assert_fits(bm.staff_review_screen.get_node("Panel") as Control)

func test_hiring_fits() -> void:
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_LOAN_DESK_2).staff_name)
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_3).staff_name)
	open_hub()
	bm.hiring_screen.show_screen()
	await assert_fits(bm.hiring_screen.get_node("Panel") as Control)

func test_the_regional_review_letter_fits() -> void:
	staff_work_everywhere()
	GameClock.day = 6
	BusinessDay.stats_day = 6
	RegionalManager.run_review()
	assert_bool(room.letter_screen.visible).is_true()
	await assert_fits(room.letter_screen.letter_panel)
