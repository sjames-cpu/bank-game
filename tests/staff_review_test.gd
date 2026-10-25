extends "res://tests/support/teller_room_suite.gd"

## NPC coworkers, step 4: the Branch Manager reviews and disciplines staff
## (StaffReviewManager, StaffReviewScreen, branch_manager_screen.gd).

const Severity := StaffReviewItem.Severity
const Action := StaffReviewManager.Action
const Mistake := StaffReviewItem.TellerMistake

var letters: DisciplineLetterScreen
var bm: BranchManagerScreen

func before_test() -> void:
	await super()
	letters = room.get_node("UI/DisciplineLetterScreen")
	bm = room.branch_manager_screen

# --- helpers -------------------------------------------------------------------

## Makes the player Branch Manager (the review queue only collects from then
## on) and clicks away the promotion letter.
func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

func acknowledge_letters() -> void:
	while letters.visible:
		letters.action_button.pressed.emit()

func staff(staff_name: String) -> StaffMember:
	for member in StaffRosterData.get_staff():
		if member.staff_name == staff_name:
			return member
	return null

func teller_item(mistake: Mistake, staff_name: String = "Derek Voss") -> StaffReviewItem:
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	customer.display_name = "Sam Chen"
	customer.intent_type = ShiftTransaction.Type.DEPOSIT
	customer.intent_amount_cents = 20000
	return StaffReviewManager.add_teller_mistake(staff(staff_name), ScheduleManager.SLOT_TELLER_WINDOW_1, customer, mistake, "test detail")

func loan_item(grade: LoanApplication.Grade, staff_name: String = "Priya Anand") -> StaffReviewItem:
	var application := LoanApplicationsData.get_applications()[0]
	application.decision = LoanApplication.DecisionType.APPROVE
	application.decision_amount = application.requested_amount
	return StaffReviewManager.add_loan_decision(staff(staff_name), ScheduleManager.SLOT_LOAN_DESK_1, application, grade)

## An item of each base severity (REPEATED_MINOR is set up by giving the
## staff member two feedbacks first).
func item_of(severity: Severity) -> StaffReviewItem:
	match severity:
		Severity.SERIOUS:
			return teller_item(Mistake.WRONG_ACCOUNT)
		Severity.MINOR:
			return teller_item(Mistake.AMOUNT_SHORT)
		Severity.ACCEPTABLE:
			return loan_item(LoanApplication.Grade.PARTIAL)
		_:
			StaffReviewManager.staff_feedbacks["Derek Voss"] = StaffReviewManager.FEEDBACKS_BEFORE_REPEAT
			return teller_item(Mistake.WRONG_TYPE)

# --- queue entry ---------------------------------------------------------------

func test_nothing_is_queued_before_promotion() -> void:
	assert_object(teller_item(Mistake.WRONG_ACCOUNT)).is_null()
	assert_object(loan_item(LoanApplication.Grade.WORST)).is_null()
	assert_int(StaffReviewManager.queue.size()).is_equal(0)

func test_items_enter_the_queue_with_the_right_severity() -> void:
	promote()
	assert_int(teller_item(Mistake.WRONG_ACCOUNT).severity).is_equal(Severity.SERIOUS)
	assert_int(teller_item(Mistake.AMOUNT_SHORT).severity).is_equal(Severity.MINOR)
	assert_int(teller_item(Mistake.AMOUNT_OVER).severity).is_equal(Severity.MINOR)
	assert_int(teller_item(Mistake.WRONG_TYPE).severity).is_equal(Severity.MINOR)
	assert_int(loan_item(LoanApplication.Grade.WORST).severity).is_equal(Severity.SERIOUS)
	assert_int(loan_item(LoanApplication.Grade.PARTIAL).severity).is_equal(Severity.ACCEPTABLE)
	assert_int(loan_item(LoanApplication.Grade.BAD).severity).is_equal(Severity.MINOR)
	assert_object(loan_item(LoanApplication.Grade.BEST)).is_null()
	assert_int(StaffReviewManager.queue.size()).is_equal(7)

## The real teller-window hook: a staff mistake is queued with the kind the
## line actually picked; a correct service queues nothing.
func test_staff_teller_mistakes_are_queued_by_the_line() -> void:
	promote()
	var line: NpcCustomerLine = room.get_node("Window1NpcLine")
	line.spawn_timer.stop()
	for i in 8:
		line._spawn_customer()
		var customer: CustomerNPC = line.queue[0]
		var mistake := i % 2 == 0
		line._start_service(customer)
		line._mistake_pending = mistake
		if mistake:
			line._reveal_mistake()
		var kind := line._mistake_kind
		line._complete_service()
		if mistake:
			var item: StaffReviewItem = StaffReviewManager.queue[-1]
			assert_str(item.customer_name).is_equal(customer.display_name)
			assert_int(item.teller_mistake).is_equal(kind)
			assert_int(item.severity).is_equal(Severity.SERIOUS if kind == Mistake.WRONG_ACCOUNT else Severity.MINOR)
	assert_int(StaffReviewManager.queue.size()).is_equal(4)

## The real loan-desk hook: only decisions not graded BEST are queued, and
## the queue isn't subject to HistoryManager's staff-record cap.
func test_only_non_best_loan_decisions_are_queued_and_never_dropped() -> void:
	promote()
	var worker: NpcLoanDeskWorker = room.get_node("LoanDeskWorker")
	var not_best := [0]
	worker.decision_made.connect(func(_a: LoanApplication, _s: StaffMember, correct: bool) -> void:
		if not correct:
			not_best[0] += 1)
	for i in HistoryManager.MAX_STAFF_RECORDS + 50:
		worker.decide_next()
	assert_int(not_best[0]).is_greater(0)
	assert_int(StaffReviewManager.queue.size()).is_equal(not_best[0])
	for item in StaffReviewManager.queue:
		assert_int(item.grade).is_not_equal(LoanApplication.Grade.BEST)

# --- decisions ---------------------------------------------------------------

## [severity, action, fair, score, reputation, xp, reports added, feedbacks added]
func _matrix() -> Array:
	var fair := StaffReviewManager.FAIR_CALL_SCORE
	return [
		[Severity.SERIOUS, Action.REPORT, true, fair, 0, fair * 10, 1, 0],
		[Severity.SERIOUS, Action.FEEDBACK, false, 0, StaffReviewManager.FEEDBACK_ON_SERIOUS_REPUTATION, 0, 0, 1],
		[Severity.SERIOUS, Action.EXCUSE, false, 0, StaffReviewManager.EXCUSED_SERIOUS_REPUTATION, 0, 0, 0],
		[Severity.MINOR, Action.REPORT, false, StaffReviewManager.UNFAIR_REPORT_SCORE, StaffReviewManager.UNFAIR_REPORT_REPUTATION, 0, 1, 0],
		[Severity.MINOR, Action.FEEDBACK, true, fair, 0, fair * 10, 0, 1],
		[Severity.MINOR, Action.EXCUSE, false, 0, 0, 0, 0, 0],
		[Severity.ACCEPTABLE, Action.REPORT, false, StaffReviewManager.UNFAIR_REPORT_SCORE, StaffReviewManager.UNFAIR_REPORT_REPUTATION, 0, 1, 0],
		[Severity.ACCEPTABLE, Action.FEEDBACK, false, 0, 0, 0, 0, 1],
		[Severity.ACCEPTABLE, Action.EXCUSE, true, fair, 0, fair * 10, 0, 0],
		[Severity.REPEATED_MINOR, Action.REPORT, true, fair, 0, fair * 10, 1, 0],
		[Severity.REPEATED_MINOR, Action.FEEDBACK, false, 0, 0, 0, 0, 1],
		[Severity.REPEATED_MINOR, Action.EXCUSE, false, 0, 0, 0, 0, 0],
	]

func test_each_action_for_each_severity() -> void:
	promote()
	for row: Array in _matrix():
		CareerReset.reset_all()
		XPManager._grant_branch_manager()
		acknowledge_letters()
		var severity: Severity = row[0]
		var action: Action = row[1]
		var score_delta: int = row[3]
		var reputation_delta: int = row[4]
		var xp_delta: int = row[5]
		var expected_delta := Vector3i(score_delta, reputation_delta, xp_delta)
		var item := item_of(severity)
		var staff_name := item.staff_name
		var reports_before := StaffReviewManager.reports_for(staff_name)
		var feedbacks_before := StaffReviewManager.feedbacks_for(staff_name)
		var start_totals := totals()
		var history_before := HistoryManager.records.size()
		var result := StaffReviewManager.decide(item, action)
		var label := "%s + %s" % [StaffReviewManager.severity_label(severity), StaffReviewManager.action_label(action)]
		assert_int(result["severity"]).override_failure_message(label).is_equal(row[0])
		assert_bool(result["fair"]).override_failure_message(label).is_equal(row[2])
		assert_vector(totals() - start_totals).override_failure_message(label).is_equal(expected_delta)
		assert_int(StaffReviewManager.reports_for(staff_name) - reports_before).override_failure_message(label).is_equal(row[6])
		assert_int(StaffReviewManager.feedbacks_for(staff_name) - feedbacks_before).override_failure_message(label).is_equal(row[7])
		assert_bool(StaffReviewManager.queue.has(item)).override_failure_message(label).is_false()
		var record: DecisionRecord = HistoryManager.records[history_before]
		assert_int(record.role).override_failure_message(label).is_equal(DecisionRecord.Role.BRANCH_MANAGER)
		var verdict := "Fair"
		if not row[2]:
			if row[1] == Action.REPORT:
				verdict = "Too harsh"
			elif row[0] == Severity.ACCEPTABLE:
				verdict = "Not needed"
			else:
				verdict = "Too lenient"
		assert_str(result["verdict"]).override_failure_message(label).is_equal(verdict)
		assert_str(result["explanation"]).override_failure_message(label).starts_with(verdict + " — ")

## For a serious item: Issue Report > Give Feedback > Excuse.
func test_serious_item_outcomes_are_ordered() -> void:
	promote()
	assert_int(StaffReviewManager.FEEDBACK_ON_SERIOUS_REPUTATION).is_equal(-1)
	var outcomes: Array[int] = []
	for action: Action in [Action.REPORT, Action.FEEDBACK, Action.EXCUSE]:
		var start_totals := totals()
		var result := StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT, "Walter Higgins"), action)
		var delta := totals() - start_totals
		# One number per outcome: Score and Reputation weighed equally.
		outcomes.append(delta.x + delta.y)
		if action == Action.FEEDBACK:
			assert_str(result["explanation"]).starts_with("Too lenient — ")
	assert_int(outcomes[0]).is_greater(outcomes[1])
	assert_int(outcomes[1]).is_greater(outcomes[2])

func test_explanations_name_the_call() -> void:
	promote()
	assert_str(StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)["explanation"]).is_equal("Fair — sending money to the wrong account is a serious error.")
	assert_str(StaffReviewManager.decide(loan_item(LoanApplication.Grade.PARTIAL), Action.REPORT)["explanation"]).is_equal("Too harsh — this was a reasonable lending call, not a mistake.")

func test_minor_becomes_reportable_after_two_feedbacks() -> void:
	promote()
	for i in StaffReviewManager.FEEDBACKS_BEFORE_REPEAT:
		var minor := teller_item(Mistake.AMOUNT_OVER)
		assert_int(StaffReviewManager.effective_severity(minor)).is_equal(Severity.MINOR)
		assert_bool(StaffReviewManager.decide(minor, Action.FEEDBACK)["fair"]).is_true()
	var third := teller_item(Mistake.AMOUNT_SHORT)
	assert_int(third.severity).is_equal(Severity.MINOR)
	assert_int(StaffReviewManager.effective_severity(third)).is_equal(Severity.REPEATED_MINOR)
	var result := StaffReviewManager.decide(third, Action.REPORT)
	assert_bool(result["fair"]).is_true()
	assert_int(StaffReviewManager.reports_for("Derek Voss")).is_equal(1)
	# Another staff member's minor slip is still just minor.
	assert_int(StaffReviewManager.effective_severity(teller_item(Mistake.AMOUNT_SHORT, "Nina Ortiz"))).is_equal(Severity.MINOR)

# --- clock-out -------------------------------------------------------------------

func _bm_clock_in() -> void:
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters() # first-shift orientation

func _bm_clock_out() -> void:
	reconcile_vault()
	bm.clock_out_button.pressed.emit()

func test_ignored_serious_items_are_penalised_at_clock_out() -> void:
	promote()
	_bm_clock_in()
	var serious_a := teller_item(Mistake.WRONG_ACCOUNT)
	var serious_b := loan_item(LoanApplication.Grade.WORST)
	var minor := teller_item(Mistake.WRONG_TYPE)
	var acceptable := loan_item(LoanApplication.Grade.PARTIAL)
	# One serious item reviewed fairly through the screen.
	bm.review_staff_button.pressed.emit()
	var screen: StaffReviewScreen = bm.staff_review_screen
	assert_object(screen.current_item()).is_same(serious_a)
	screen.report_button.pressed.emit()
	screen.close_button.pressed.emit()

	var reputation_before := ReputationManager.reputation
	_bm_clock_out()
	assert_bool(bm.shift_summary_panel.visible).is_true()
	# serious_b ignored; the vault's Perfect count adds its own Reputation.
	var vault_reputation := TellerScreen.PERFECT_COUNT_REPUTATION
	assert_int(ReputationManager.reputation - reputation_before).is_equal(StaffReviewManager.IGNORED_SERIOUS_REPUTATION + vault_reputation)
	assert_bool(StaffReviewManager.queue.has(serious_b)).is_false()
	assert_bool(StaffReviewManager.queue.has(minor)).is_true()
	assert_bool(StaffReviewManager.queue.has(acceptable)).is_true()
	var ignored_records := HistoryManager.records.filter(func(r: DecisionRecord) -> bool: return r.grade_label == "Ignored")
	assert_int(ignored_records.size()).is_equal(1)
	var summary: String = bm.shift_staff_review_label.text
	assert_str(summary).contains("Reviewed: 1\nFair calls: 1\nUnfair reports: 0")
	assert_str(summary).contains("Serious ignored: 1 (still waiting: 2)")
	assert_str(summary).contains("Score %+d · Reputation %+d · XP %+d" % [StaffReviewManager.FAIR_CALL_SCORE, StaffReviewManager.IGNORED_SERIOUS_REPUTATION, StaffReviewManager.FAIR_CALL_SCORE * 10])

# --- termination ----------------------------------------------------------------

func _terminate_buttons(screen: StaffReviewScreen) -> Array[String]:
	var names: Array[String] = []
	for child in screen.terminate_vbox.get_children():
		if not child.is_queued_for_deletion():
			names.append((child as Button).text)
	return names

func test_terminate_appears_only_at_three_reports() -> void:
	promote()
	_bm_clock_in()
	var screen: StaffReviewScreen = bm.staff_review_screen
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		teller_item(Mistake.WRONG_ACCOUNT)
	teller_item(Mistake.WRONG_ACCOUNT, "Nina Ortiz")
	bm.review_staff_button.pressed.emit()
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		assert_array(_terminate_buttons(screen)).is_empty()
		assert_bool(StaffReviewManager.can_terminate("Derek Voss")).is_false()
		assert_str(screen.current_item().staff_name).is_equal("Derek Voss")
		screen.report_button.pressed.emit()
	assert_array(_terminate_buttons(screen)).contains_exactly(["Terminate Employment — Derek Voss (3 reports)"])
	# One report for Nina isn't enough.
	screen.report_button.pressed.emit()
	assert_array(_terminate_buttons(screen)).contains_exactly(["Terminate Employment — Derek Voss (3 reports)"])

func test_termination_empties_the_desk_and_the_schedule() -> void:
	promote()
	var line: NpcCustomerLine = room.get_node("Window1NpcLine")
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).staff_name).is_equal("Derek Voss")
	assert_bool(line.active).is_true()
	line.spawn_timer.stop()
	line._spawn_customer()
	line._spawn_customer()
	var waiting: Array[CustomerNPC] = line.queue.duplicate()
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
	var leftover := teller_item(Mistake.AMOUNT_SHORT)

	_bm_clock_in()
	bm.review_staff_button.pressed.emit()
	var screen: StaffReviewScreen = bm.staff_review_screen
	(screen.terminate_vbox.get_child(0) as Button).pressed.emit()

	# Letter signed by the Branch Manager.
	assert_bool(letters.visible).is_true()
	assert_str(letters.title_label.text).is_equal("Notice of Termination — Derek Voss")
	assert_str(letters.from_label.text).is_equal("From: Branch Manager")
	assert_str(letters.body_label.text).contains("To: Derek Voss")
	acknowledge_letters()

	# Gone from the roster, the schedule and the desk.
	assert_object(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1)).is_null()
	assert_bool(ScheduleManager.get_roster().any(func(m: StaffMember) -> bool: return m.staff_name == "Derek Voss")).is_false()
	assert_bool(room._staff_by_slot.has(ScheduleManager.SLOT_TELLER_WINDOW_1)).is_false()
	assert_bool(StaffReviewManager.queue.has(leftover)).is_false()
	# Line closed: no new customers, waiting customers walked out.
	assert_bool(line.active).is_false()
	assert_bool(line.spawn_timer.is_stopped()).is_true()
	assert_int(line.queue.size()).is_equal(0)
	for customer in waiting:
		assert_bool(customer._leaving).is_true()
	line._on_spawn_timer_timeout()
	assert_int(line.queue.size()).is_equal(0)
	assert_array(_terminate_buttons(screen)).is_empty()
	var no_records: Array[DecisionRecord] = []
	assert_str(BranchManagerScreen.branch_summary_text(no_records)).contains("Teller Window 1 — Unassigned")

	# The schedule screen lists neither him nor any report-less ghost.
	var scheduling: StaffSchedulingScreen = bm.staff_scheduling_screen
	screen.close_button.pressed.emit()
	bm.schedule_staff_button.pressed.emit()
	for child in scheduling.roster_vbox.get_children():
		if child is Label:
			assert_str((child as Label).text).not_contains("Derek Voss")
	for button in scheduling._slot_option_buttons:
		for i in button.item_count:
			assert_str(button.get_item_text(i)).is_not_equal("Derek Voss")
	assert_str(scheduling._slot_option_buttons[0].get_item_text(scheduling._slot_option_buttons[0].selected)).is_equal("Unassigned")

func test_schedule_screen_shows_staff_reports() -> void:
	promote()
	StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
	_bm_clock_in()
	bm.schedule_staff_button.pressed.emit()
	var texts: Array[String] = []
	for child in bm.staff_scheduling_screen.roster_vbox.get_children():
		if child is Label and not child.is_queued_for_deletion():
			texts.append((child as Label).text)
	assert_bool(texts.any(func(t: String) -> bool: return t.begins_with("Derek Voss (Teller) — Reports: 1 / 3"))).is_true()
	assert_bool(texts.any(func(t: String) -> bool: return t.begins_with("Nina Ortiz (Teller) — Reports: 0 / 3"))).is_true()

func test_career_reset_restores_everything() -> void:
	promote()
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
	StaffReviewManager.decide(teller_item(Mistake.AMOUNT_SHORT, "Nina Ortiz"), Action.FEEDBACK)
	teller_item(Mistake.AMOUNT_SHORT, "Nina Ortiz")
	StaffReviewManager.terminate("Derek Voss")
	acknowledge_letters()
	assert_int(ScheduleManager.get_roster().size()).is_equal(StaffRosterData.get_staff().size() - 1)

	CareerReset.reset_all()
	assert_int(StaffReviewManager.queue.size()).is_equal(0)
	assert_int(StaffReviewManager.reports_for("Derek Voss")).is_equal(0)
	assert_int(StaffReviewManager.feedbacks_for("Nina Ortiz")).is_equal(0)
	assert_int(ScheduleManager.get_roster().size()).is_equal(StaffRosterData.get_staff().size())
	assert_array(ScheduleManager.dismissed_staff).is_empty()
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).staff_name).is_equal("Derek Voss")

# --- screen -----------------------------------------------------------------------

func test_loan_details_hide_the_grade_until_decided() -> void:
	promote()
	var item := loan_item(LoanApplication.Grade.WORST)
	var details := StaffReviewScreen.details_text(item)
	for hidden: String in ["risk", "Risky", "Correct", "Serious", "grade", "Graded"]:
		assert_str(details).not_contains(hidden)
	for shown: String in ["Credit score", "Income $", "Debts $", "New payment $", "Front-end DTI", "Total DTI", "Affordable at 36%", "Decision: Approve"]:
		assert_str(details).contains(shown)
	assert_str(details).not_contains("Loan-to-income")
	_bm_clock_in()
	bm.review_staff_button.pressed.emit()
	var screen: StaffReviewScreen = bm.staff_review_screen
	assert_bool(screen.result_label.visible).is_false()
	assert_str(screen.record_label.text).is_equal("Reports: 0 / 3 · Feedbacks: 0")
	screen.report_button.pressed.emit()
	assert_bool(screen.result_label.visible).is_true()
	assert_str(screen.result_label.text).starts_with("Priya Anand (Serious): Fair")
	assert_str(screen.result_label.text).contains("Graded: Risky call")

func test_review_screen_and_summary_fit_the_window() -> void:
	promote()
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
	for i in StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION:
		StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT, "Nina Ortiz"), Action.REPORT)
	loan_item(LoanApplication.Grade.PARTIAL)
	loan_item(LoanApplication.Grade.WORST)
	_bm_clock_in()
	bm.review_staff_button.pressed.emit()
	var screen: StaffReviewScreen = bm.staff_review_screen
	screen.report_button.pressed.emit() # result line + two Terminate buttons + the next loan item
	var panel: Control = screen.get_node("Panel")
	assert_float(await settled_height(panel)).is_less_equal(648.0)
	screen.close_button.pressed.emit()
	_bm_clock_out()
	assert_float(await settled_height(bm.shift_summary_panel)).is_less_equal(648.0)
