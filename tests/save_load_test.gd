extends "res://tests/support/teller_room_suite.gd"

## Save and load (SaveGame, start_screen.gd): a round trip restores every
## saved value, a hire saves, the room saves at clock-outs, promotions and
## the orientation letter, Continue lands off shift in the room, unreadable saves fall back
## to a new game, and termination and New Game delete the save. Every test
## uses TEST_SAVE_PATH (see teller_room_suite.gd), never the real save.

const START_SCREEN := "res://scenes/ui/start_screen.tscn"
const INTERVIEW_SCENE := "res://scenes/ui/interview_screen.tscn"

var letters: DisciplineLetterScreen

func before_test() -> void:
	await super()
	letters = room.get_node("UI/DisciplineLetterScreen")

# --- helpers -------------------------------------------------------------------

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

func roster_member(staff_name: String) -> StaffMember:
	for member in StaffRosterData.get_staff():
		if member.staff_name == staff_name:
			return member
	return null

## Replaces the room with the start screen, as launching the game would.
func open_start_screen() -> StartScreen:
	if is_instance_valid(room):
		room.free()
	var screen: StartScreen = (load(START_SCREEN) as PackedScene).instantiate()
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen
	await get_tree().process_frame
	return screen

## Waits for a change_scene_to_file() and returns the new scene. A new room
## becomes `room`, so after_test() frees it.
func await_scene_change() -> Node:
	await get_tree().process_frame
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene is TellerRoom:
		room = scene
	return scene

func write_save_text(text: String) -> void:
	var file := FileAccess.open(SaveGame.path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

## A career with a non-default value in everything the save holds.
func build_full_career() -> void:
	ScoreManager.add_shift_score(137)
	ReputationManager.add_reputation(13)
	XPManager.total_xp = 1234
	XPManager.is_loan_officer_unlocked = true
	XPManager.is_branch_manager_promotion_pending = true
	XPManager.has_seen_branch_orientation = true

	InterviewManager.is_on_probation = true

	# One report (and its letter), plus one mistake not yet rolled into one.
	for i in ReportManager.MISTAKES_PER_REPORT + 1:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Customer %d" % i)
	acknowledge_letters()
	ReportManager.reports_cleared_on_promotion = 2
	# Set after the report, which starts the count over.
	InterviewManager.probation_clean_shifts = 2

	var teller := HistoryManager.add_record(DecisionRecord.Role.TELLER, "Drawer count: Minor", "Minor")
	teller.reviewed = true
	HistoryManager.add_loan_record("Loan decision", "BEST", LoanApplication.RiskTier.HIGH, LoanApplication.DecisionType.COUNTER_OFFER, "Avery Stone", 12345.67)
	HistoryManager.add_staff_record("Derek Voss", ScheduleManager.SLOT_TELLER_WINDOW_1, "Deposit $40", "Mistake")
	HistoryManager.add_record(DecisionRecord.Role.DRAWER_VARIANCE, "Opening count off by $10", "Minor")
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Override", "Justified")

	AccountManager.deposit(AccountManager.get_accounts()[0], 2550)
	AccountManager.create_account("Rosa Diaz", 123456)
	var customer := AccountManager.create_account("Sam Chen", 4210)
	customer.is_customer_account = true
	var staff_line := AccountManager.create_account("Sam Chen", 990)
	staff_line.is_customer_account = true
	staff_line.is_staff_line_account = true

	ScheduleManager.open_teller_window_3()
	ScheduleManager.dismiss_staff("Walter Higgins")
	ScheduleManager.confirm_schedule({
		ScheduleManager.SLOT_TELLER_WINDOW_1: roster_member("Nina Ortiz"),
		ScheduleManager.SLOT_TELLER_WINDOW_3: roster_member("Derek Voss"),
		ScheduleManager.SLOT_LOAN_DESK_1: roster_member("Sana Malik"),
	})

	var teller_item := StaffReviewItem.new()
	teller_item.kind = StaffReviewItem.Kind.TELLER
	teller_item.severity = StaffReviewItem.Severity.SERIOUS
	teller_item.staff_name = "Derek Voss"
	teller_item.staff_slot = ScheduleManager.SLOT_TELLER_WINDOW_3
	teller_item.timestamp = "Day 2, 9:30 AM"
	teller_item.customer_name = "Sam Chen"
	teller_item.request_type = ShiftTransaction.Type.WITHDRAWAL
	teller_item.request_amount_cents = 20000
	teller_item.teller_mistake = StaffReviewItem.TellerMistake.WRONG_ACCOUNT
	teller_item.mistake_detail = "used the wrong account"
	var loan_item := StaffReviewItem.new()
	loan_item.kind = StaffReviewItem.Kind.LOAN
	loan_item.severity = StaffReviewItem.Severity.ACCEPTABLE
	loan_item.staff_name = "Sana Malik"
	loan_item.staff_slot = ScheduleManager.SLOT_LOAN_DESK_1
	loan_item.timestamp = "Day 2, 9:31 AM"
	loan_item.applicant_name = "Avery Stone"
	loan_item.requested_amount = 25000.5
	loan_item.loan_purpose = "Car"
	loan_item.credit_score = 702
	loan_item.annual_income = 61234.25
	loan_item.monthly_debt_payments = 812.4
	loan_item.debt_to_income = 0.1592
	loan_item.loan_to_income = 0.408
	loan_item.decision = LoanApplication.DecisionType.COUNTER_OFFER
	loan_item.decision_amount = 20000.75
	loan_item.grade = LoanApplication.Grade.PARTIAL
	StaffReviewManager.queue.append(teller_item)
	StaffReviewManager.queue.append(loan_item)
	StaffReviewManager.staff_reports["Derek Voss"] = PackedStringArray(["late", "short"])
	StaffReviewManager.staff_feedbacks["Nina Ortiz"] = 2

	# Day 3, 10:42 AM and a bit (the clock keeps fractions of a minute).
	GameClock.day = 3
	GameClock.minutes = 642.75
	HintManager.mark_shown(HintManager.Hint.FIRST_CLOCK_OUT)
	HintManager.mark_shown(HintManager.Hint.LOAN_OFFICER_UNLOCKED)

	# Hiring: a hire, a vacancy's candidates part-way through their
	# interviews, and a rejected vacancy.
	var hire := StaffCandidate.new()
	hire.staff_name = "Harper Quinn"
	hire.role = "Teller"
	hire.background = "2 years as a teller at a credit union"
	hire.skill = 8
	hire.reliability = 7
	hire.speed = 9
	hire.customer_service = 6
	assert_bool(ScheduleManager.hire_staff(hire.to_staff_member(), ScheduleManager.SLOT_TELLER_WINDOW_2)).is_true()
	var waiting := HiringManager.generate_candidates("Loan Officer")
	waiting[0].questions_asked = 3
	waiting[2].questions_asked = 1
	HiringManager.candidates[ScheduleManager.SLOT_LOAN_DESK_1] = waiting
	HiringManager.rejected_slots.append(ScheduleManager.SLOT_TELLER_WINDOW_1)

	# The Regional Manager: warnings, a demotion's XP target and the review
	# window's data (this career isn't a Branch Manager right now, so it has
	# no window open).
	XPManager.repromotion_xp_target = 2100
	RegionalManager.warnings = 2
	RegionalManager.counted_through_day = 2
	RegionalManager.vault_by_day[2] = VaultReconciliationScreen.DiscrepancyResult.MINOR
	RegionalManager.serious_reviewed = 3
	RegionalManager.serious_ignored = 1
	RegionalManager.serious_excused = 1
	RegionalManager.reviews = 5
	RegionalManager.unfair_reports = 2
	RegionalManager.staff_work = 30
	RegionalManager.staff_mistakes = 4
	RegionalManager.staff_line_served = 25
	RegionalManager.staff_line_abandoned = 2
	RegionalManager.vacant_desk_minutes = 75.5
	RegionalManager.hire_verdicts.assign([HiringManager.Verdict.MIDDLE])

# --- round trip ------------------------------------------------------------------

func test_save_then_load_restores_every_saved_value() -> void:
	build_full_career()
	var saved_career := SaveGame.capture()
	assert_bool(SaveGame.save()).is_true()

	CareerReset.reset_all()
	assert_dict(SaveGame.capture()).is_not_equal(saved_career)

	var result := SaveGame.read()
	assert_int(result.status).is_equal(SaveGame.Status.OK)
	SaveGame.restore(result.career)
	# capture() reads every saved field, every exported property of the saved
	# resources included, so this compares all of them.
	assert_dict(SaveGame.capture()).is_equal(saved_career)

	# And the live state, field by field where it matters most.
	assert_int(ScoreManager.total_score).is_equal(137)
	assert_int(ReputationManager.reputation).is_equal(ReputationManager.STARTING_REPUTATION + 13)
	assert_int(XPManager.total_xp).is_equal(1234)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_bool(XPManager.is_branch_manager_promotion_pending).is_true()
	assert_bool(XPManager.has_seen_branch_orientation).is_true()
	assert_bool(InterviewManager.is_on_probation).is_true()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(2)
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_array(Array(ReportManager.reports[0].items)).is_equal(["Customer 0", "Customer 1"])
	var pending: PackedStringArray = ReportManager._pending_mistakes[DecisionRecord.Role.TELLER]
	assert_array(Array(pending)).is_equal(["Customer 2"])
	assert_bool(ReportManager.is_exempt).is_false()
	assert_int(ReportManager.reports_cleared_on_promotion).is_equal(2)
	var loan_record: DecisionRecord = HistoryManager.records.filter(func(r: DecisionRecord) -> bool: return r.has_loan_context)[0]
	assert_float(loan_record.decision_amount).is_equal(12345.67)
	assert_int(loan_record.risk_assessment).is_equal(LoanApplication.RiskTier.HIGH)
	assert_int(HistoryManager._staff_record_count).is_equal(1)
	assert_int(AccountManager.get_accounts()[0].balance_cents).is_equal(AccountManager.DEMO_ACCOUNT_START_CENTS + 2550)
	assert_object(AccountManager.find_account_by_name("Sam Chen", true)).is_not_null()
	assert_int(AccountManager.find_account_by_name("Sam Chen", true).balance_cents).is_equal(990)
	assert_int(AccountManager.find_account_by_name("Sam Chen").balance_cents).is_equal(4210)
	assert_bool(ScheduleManager.is_teller_window_3_open).is_true()
	assert_array(ScheduleManager.dismissed_staff).is_equal(["Walter Higgins"])
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).staff_name).is_equal("Nina Ortiz")
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).staff_name).is_equal("Harper Quinn")
	assert_int(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).speed).is_equal(9)
	# Their uniform look, chosen when hired.
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).look).is_equal(StaffLooks.HIRE_LOOKS[0])
	assert_int(ScheduleManager.hired_staff.size()).is_equal(1)
	var waiting: Array[StaffCandidate] = HiringManager.candidates[ScheduleManager.SLOT_LOAN_DESK_1]
	assert_int(waiting.size()).is_equal(3)
	assert_int(waiting[0].questions_asked).is_equal(3)
	assert_int(waiting[2].questions_asked).is_equal(1)
	assert_array(HiringManager.rejected_slots).is_equal([ScheduleManager.SLOT_TELLER_WINDOW_1])
	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_3).staff_name).is_equal("Derek Voss")
	assert_int(StaffReviewManager.queue.size()).is_equal(2)
	assert_float(StaffReviewManager.queue[1].annual_income).is_equal(61234.25)
	assert_int(StaffReviewManager.reports_for("Derek Voss")).is_equal(2)
	assert_int(StaffReviewManager.feedbacks_for("Nina Ortiz")).is_equal(2)
	assert_bool(HintManager.has_shown(HintManager.Hint.FIRST_CLOCK_OUT)).is_true()
	assert_int(GameClock.day).is_equal(3)
	assert_float(GameClock.minutes).is_equal(642.75)
	assert_str(GameClock.hud_text()).is_equal("Wed, Day 3 · 10:42 AM")
	assert_bool(HintManager.has_shown(HintManager.Hint.FIRST_CUSTOMER)).is_false()
	assert_int(XPManager.repromotion_xp_target).is_equal(2100)
	assert_int(RegionalManager.warnings).is_equal(2)
	assert_int(RegionalManager.vault_by_day[2]).is_equal(VaultReconciliationScreen.DiscrepancyResult.MINOR)
	assert_float(RegionalManager.vacant_desk_minutes).is_equal(75.5)

## Game time builds up from frame deltas, so it can be any float; a value
## the JSON parser can't read back exactly once made a CI round trip fail
## (510.06136363636364 came back as 510.0613636363637). Both clock-driven
## floats must survive a real save whatever they are.
func test_clock_driven_times_survive_the_save_exactly() -> void:
	XPManager._grant_branch_manager() # the review window holds vacant_desk_minutes
	acknowledge_letters()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var values: Array[float] = [510.06136363636364, 1e-9, 0.1 + 0.2]
	for i in 200:
		values.append(rng.randf_range(0.0, GameClock.MINUTES_PER_DAY - 1.0))
	for value in values:
		GameClock.minutes = value
		RegionalManager.vacant_desk_minutes = value * 3.7
		var saved_career := SaveGame.capture()
		assert_bool(SaveGame.save()).is_true()
		SaveGame.restore(SaveGame.read().career)
		assert_dict(SaveGame.capture()).override_failure_message("%s didn't survive the save" % value).is_equal(saved_career)
		# Within a game second of the live value.
		assert_float(GameClock.minutes).is_equal_approx(value, 1.0 / 60.0)

func test_saved_resources_cover_every_exported_field() -> void:
	# A field added to a saved resource must reach the file without changes
	# to SaveGame: every exported property is written.
	for resource: Resource in [Account.new(), DecisionRecord.new(), DisciplinaryReport.new(), StaffReviewItem.new(), StaffMember.new(), StaffCandidate.new()]:
		var saved := SaveGame.resource_to_dict(resource)
		var script: Script = resource.get_script()
		for property in resource.get_property_list():
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				assert_bool(saved.has(property["name"])).override_failure_message("%s.%s isn't saved" % [script.get_global_name(), property["name"]]).is_true()

func test_staff_record_cap_holds_on_load() -> void:
	var career := {"history": {"records": []}}
	var records: Array = career["history"]["records"]
	for i in HistoryManager.MAX_STAFF_RECORDS + 5:
		records.append({"role": DecisionRecord.Role.STAFF, "description": "Staff %d" % i})
	records.append({"role": DecisionRecord.Role.TELLER, "description": "Teller"})
	SaveGame.restore(career)
	assert_int(HistoryManager.records.size()).is_equal(HistoryManager.MAX_STAFF_RECORDS + 1)
	assert_str(HistoryManager.records[0].description).is_equal("Staff 5") # oldest 5 dropped
	assert_int(HistoryManager._staff_record_count).is_equal(HistoryManager.MAX_STAFF_RECORDS)

func test_save_file_is_versioned_json() -> void:
	assert_bool(SaveGame.save()).is_true()
	assert_str(SaveGame.path).is_equal(TEST_SAVE_PATH)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	assert_int(SaveGame.int_of(data, "format_version", -1)).is_equal(SaveGame.FORMAT_VERSION)
	assert_bool(data["career"] is Dictionary).is_true()
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH + ".tmp")).is_false()

# --- the real save is the real game's only -----------------------------------------

func test_only_the_real_game_writes_the_real_save() -> void:
	# The real save path is a stand-in here, so even a broken guard can't touch
	# the player's career; the real one is user://career.json.
	assert_str(SaveGame.real_path).is_equal("user://career.json")
	var stand_in := "user://test_real_career_guard.json"
	SaveGame.real_path = stand_in
	SaveGame.path = stand_in
	for leftover: String in [stand_in, stand_in + ".tmp", stand_in + ".bad"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)

	# Outside the real game flow, nothing writes, deletes or moves it.
	assert_bool(SaveGame.real_save_allowed).is_false()
	assert_bool(SaveGame.save()).is_false()
	assert_bool(FileAccess.file_exists(stand_in)).is_false()
	write_save_text("{\"format_version\": 1, \"career\": {}}")
	SaveGame.delete()
	assert_bool(FileAccess.file_exists(stand_in)).is_true()
	SaveGame.set_aside()
	assert_bool(FileAccess.file_exists(stand_in)).is_true()
	assert_bool(FileAccess.file_exists(stand_in + ".bad")).is_false()
	# A clock-out in the room doesn't write it either.
	clock_in()
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	assert_str(FileAccess.get_file_as_string(stand_in)).is_equal("{\"format_version\": 1, \"career\": {}}")

	# Any other path is fine (the tests' own, a scratch script's).
	SaveGame.path = TEST_SAVE_PATH
	assert_bool(SaveGame.save()).is_true()

	# The start screen starts the real game: from then on it may.
	SaveGame.path = stand_in
	await open_start_screen()
	assert_bool(SaveGame.real_save_allowed).is_true()
	assert_bool(SaveGame.save()).is_true()
	assert_bool(SaveGame.read().status == SaveGame.Status.OK).is_true()
	SaveGame.delete()
	assert_bool(FileAccess.file_exists(stand_in)).is_false()

# --- when the room saves -------------------------------------------------------------

func test_teller_clock_out_saves() -> void:
	clock_in()
	assert_bool(SaveGame.exists()).is_false()
	serve_correctly(spawn())
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP - 1:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	assert_bool(SaveGame.exists()).is_true()
	var saved := SaveGame.read()
	assert_int(SaveGame.int_of(SaveGame.dict_of(saved.career, "score"), "total_score", -999)).is_equal(ScoreManager.total_score)

func test_loan_desk_clock_out_saves() -> void:
	XPManager.is_loan_officer_unlocked = true
	var lo := room.loan_officer_screen
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_false()
	lo.applications_reviewed = LoanOfficerScreen.APPLICATIONS_PER_SHIFT
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()
	assert_bool(SaveGame.exists()).is_true()

func test_promotion_orientation_and_branch_manager_clock_out_save() -> void:
	XPManager._grant_branch_manager()
	assert_bool(SaveGame.exists()).is_true()
	assert_bool(SaveGame.dict_of(SaveGame.read().career, "xp")["is_branch_manager_unlocked"]).is_true()
	acknowledge_letters()

	SaveGame.delete()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_true() # the orientation letter
	assert_bool(SaveGame.dict_of(SaveGame.read().career, "xp")["has_seen_branch_orientation"]).is_true()
	acknowledge_letters()

	SaveGame.delete()
	bm.vault_reconciliation_button.pressed.emit()
	var vault := bm.vault_reconciliation_screen
	var remaining := VaultReconciliationScreen.EXPECTED_VAULT_CENTS
	for i in VaultReconciliationScreen.DENOMINATION_CENTS.size():
		var denom := VaultReconciliationScreen.DENOMINATION_CENTS[i]
		vault.quantity_inputs[i].value = floori(float(remaining) / denom)
		remaining -= floori(float(remaining) / denom) * denom
	vault.submit_button.pressed.emit()
	vault.close_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_false() # nothing saved mid-shift
	bm.clock_out_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_false()
	assert_bool(SaveGame.exists()).is_true()

## Replaces the room with the interview and ends it with `score` points.
func finish_interview(score: int) -> InterviewScreen:
	room.free()
	var interview: InterviewScreen = (load(INTERVIEW_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(interview)
	get_tree().current_scene = interview
	await get_tree().process_frame
	interview.running_score = score
	interview._finish_interview()
	return interview

func test_rejection_saves_nothing() -> void:
	var interview: InterviewScreen = await finish_interview(InterviewManager.PROBATION_THRESHOLD - 1)
	assert_int(interview.last_outcome).is_equal(InterviewManager.Outcome.REJECTED)
	assert_bool(SaveGame.exists()).is_false()

func test_being_hired_saves() -> void:
	var interview: InterviewScreen = await finish_interview(InterviewManager.HIRE_THRESHOLD)
	assert_int(interview.last_outcome).is_equal(InterviewManager.Outcome.HIRED)
	assert_bool(SaveGame.exists()).is_true()
	assert_bool(SaveGame.dict_of(SaveGame.read().career, "interview")["is_on_probation"]).is_false()

func test_quitting_after_a_probation_hire_continues_on_probation() -> void:
	var interview: InterviewScreen = await finish_interview(InterviewManager.PROBATION_THRESHOLD)
	assert_int(interview.last_outcome).is_equal(InterviewManager.Outcome.HIRED_ON_PROBATION)
	# Saved before "Start Shift" is even pressed: quit right here.
	assert_bool(SaveGame.exists()).is_true()
	CareerReset.reset_all()

	# Relaunch: the start screen continues the career rather than offering the
	# interview again, and the probation comes with it.
	interview.free()
	var screen: StartScreen = await open_start_screen()
	assert_bool(screen.menu_panel.visible).is_true()
	screen.continue_button.pressed.emit()
	var scene := await await_scene_change()
	assert_object(scene).is_instanceof(TellerRoom)
	assert_bool(InterviewManager.is_on_probation).is_true()
	assert_int(InterviewManager.probation_clean_shifts).is_equal(0)
	assert_int(InterviewManager.report_limit()).is_equal(InterviewManager.PROBATION_REPORTS_FOR_TERMINATION)
	assert_str(room.describe_shift_status()).is_equal("Off shift")

# --- start screen -----------------------------------------------------------------

func test_no_save_goes_straight_to_the_interview() -> void:
	assert_str(str(ProjectSettings.get_setting("application/run/main_scene"))).is_equal(START_SCREEN)
	await open_start_screen()
	var scene := await await_scene_change()
	assert_str(scene.scene_file_path).is_equal(INTERVIEW_SCENE)

func test_continue_lands_off_shift_in_the_room() -> void:
	ScoreManager.add_shift_score(42)
	XPManager.is_loan_officer_unlocked = true
	HintManager.mark_shown(HintManager.Hint.FIRST_CUSTOMER)
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()

	var screen: StartScreen = await open_start_screen()
	assert_bool(screen.menu_panel.visible).is_true()
	assert_bool(screen.continue_button.visible).is_true()
	assert_str(screen.summary_label.text).contains("Loan Officer · Score 42")
	screen.continue_button.pressed.emit()
	var scene := await await_scene_change()
	assert_object(scene).is_instanceof(TellerRoom)

	assert_int(ScoreManager.total_score).is_equal(42)
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_str(room.describe_shift_status()).is_equal("Off shift")
	assert_int(room.teller_screen.shift_state).is_equal(TellerScreen.ShiftState.CLOCKED_OUT)
	assert_bool(room.loan_officer_screen.is_clocked_in()).is_false()
	assert_array(XPManager._desks_on_shift).is_empty()
	assert_bool(get_tree().paused).is_false()
	# The arrival hint was seen in the saved career, so it isn't shown again.
	assert_int(room.hud.current_hint).is_equal(-1)
	# Continue doesn't save by itself; the next clock-out will.
	assert_bool(SaveGame.exists()).is_true()

func test_continue_restores_a_branch_managers_branch() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	StaffReviewManager.staff_reports["Derek Voss"] = PackedStringArray(["a", "b", "c"])
	assert_bool(StaffReviewManager.terminate("Derek Voss")).is_true()
	acknowledge_letters()
	ScheduleManager.confirm_schedule({
		ScheduleManager.SLOT_TELLER_WINDOW_1: roster_member("Nina Ortiz"),
		ScheduleManager.SLOT_LOAN_DESK_1: roster_member("Marcus Chen"),
	})
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()

	var screen: StartScreen = await open_start_screen()
	assert_str(screen.summary_label.text).contains("Branch Manager")
	screen.continue_button.pressed.emit()
	await await_scene_change()

	assert_bool(room.branch_manager_desk.visible).is_true()
	assert_bool(ScheduleManager.is_dismissed("Derek Voss")).is_true()
	assert_array(room._staff_by_slot.keys()).contains_exactly_in_any_order([ScheduleManager.SLOT_TELLER_WINDOW_1, ScheduleManager.SLOT_LOAN_DESK_1])
	assert_str(room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_1].staff.staff_name).is_equal("Nina Ortiz")
	# No promotion letter again: the career already had it.
	assert_bool(room.letter_screen.visible).is_false()
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal(TellerRoom.UNASSIGNED_DESK_TEXT)

# --- unreadable saves -------------------------------------------------------------

func test_unreadable_saves_are_reported() -> void:
	var cases := {
		"{not json": SaveGame.Status.CORRUPT,
		"": SaveGame.Status.CORRUPT,
		"[1, 2, 3]": SaveGame.Status.CORRUPT,
		"{\"career\": {}}": SaveGame.Status.CORRUPT,
		"{\"format_version\": \"1\", \"career\": {}}": SaveGame.Status.CORRUPT,
		"{\"format_version\": 1, \"career\": []}": SaveGame.Status.CORRUPT,
		"{\"format_version\": 2, \"career\": {}}": SaveGame.Status.WRONG_VERSION,
		"{\"format_version\": 0}": SaveGame.Status.WRONG_VERSION,
		"{\"format_version\": 1, \"career\": {}}": SaveGame.Status.OK,
	}
	for text: String in cases:
		write_save_text(text)
		assert_int(SaveGame.read().status).override_failure_message("read of %s" % text).is_equal(cases[text])
	SaveGame.delete()
	assert_int(SaveGame.read().status).is_equal(SaveGame.Status.MISSING)

func test_corrupt_save_falls_back_to_a_new_game() -> void:
	write_save_text("{\"format_version\": 1, \"career\": {\"score\": ")
	ScoreManager.add_shift_score(10)
	var screen: StartScreen = await open_start_screen()
	assert_bool(screen.message_panel.visible).is_true()
	assert_bool(screen.menu_panel.visible).is_false()
	assert_str(screen.message_label.text).is_equal(StartScreen.CORRUPT_MESSAGE)
	screen.message_ok_button.pressed.emit()
	var scene := await await_scene_change()
	assert_str(scene.scene_file_path).is_equal(INTERVIEW_SCENE)
	assert_int(ScoreManager.total_score).is_equal(0)
	# Set aside, so the new career's first save doesn't overwrite it.
	assert_bool(SaveGame.exists()).is_false()
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH + ".bad")).is_true()

func test_wrong_version_falls_back_to_a_new_game() -> void:
	write_save_text(JSON.stringify({"format_version": SaveGame.FORMAT_VERSION + 1, "career": {"score": {"total_score": 99}}}))
	var screen: StartScreen = await open_start_screen()
	assert_str(screen.message_label.text).is_equal(StartScreen.WRONG_VERSION_MESSAGE)
	screen.message_ok_button.pressed.emit()
	var scene := await await_scene_change()
	assert_str(scene.scene_file_path).is_equal(INTERVIEW_SCENE)
	assert_int(ScoreManager.total_score).is_equal(0)
	assert_bool(SaveGame.exists()).is_false()

func test_mistyped_values_load_as_new_game_defaults() -> void:
	CareerReset.reset_all()
	var fresh := SaveGame.capture()
	SaveGame.restore({
		"score": "lots",
		"reputation": {"reputation": "high"},
		"xp": [],
		"interview": null,
		"reports": {"reports": "none", "pending_mistakes": {"0": 5, "x": ["a"]}, "is_exempt": 1},
		"history": {"records": [1, "two", null]},
		"accounts": {"accounts": 3},
		"schedule": {"schedule": "everyone", "dismissed_staff": "all", "is_teller_window_3_open": "yes"},
		"staff_review": {"queue": {}, "staff_reports": {"Derek Voss": "bad"}, "staff_feedbacks": {"Nina Ortiz": "two"}},
		"hints": {"shown": ["ARRIVAL", 99, -1]},
	})
	assert_dict(SaveGame.capture()).is_equal(fresh)

	# Inside a saved resource, a mistyped field keeps its default and the rest load.
	SaveGame.restore({"accounts": {"accounts": [{"customer_name": 7, "balance_cents": 500}, {"customer_name": "Rosa", "balance_cents": "x"}]}})
	assert_int(AccountManager.get_accounts().size()).is_equal(2)
	assert_str(AccountManager.get_accounts()[0].customer_name).is_equal("")
	assert_int(AccountManager.get_accounts()[0].balance_cents).is_equal(500)
	assert_str(AccountManager.get_accounts()[1].customer_name).is_equal("Rosa")
	assert_int(AccountManager.get_accounts()[1].balance_cents).is_equal(0)

	# An unknown desk or staff member in a schedule leaves that desk unassigned
	# (a current save: an older one also fills Loan Desks 2 and 3).
	SaveGame.restore({"schedule": {"slots_version": ScheduleManager.SLOTS_VERSION, "schedule": {ScheduleManager.SLOT_TELLER_WINDOW_1: 42, "Nowhere": "Derek Voss", ScheduleManager.SLOT_LOAN_DESK_1: "Nobody"}}})
	assert_dict(ScheduleManager.schedule).is_empty()

# --- deleting the save --------------------------------------------------------------

func test_termination_deletes_the_save() -> void:
	assert_bool(SaveGame.save()).is_true()
	for i in ReportManager.MISTAKES_PER_REPORT * ReportManager.REPORTS_FOR_TERMINATION:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Customer %d" % i)
		acknowledge_letters()
	assert_bool(ReportManager.is_terminated).is_true()
	assert_str(letters.action_button.text).is_equal("Apply for a new job")
	# Deleted as soon as the letter comes up, and never saved again.
	assert_bool(SaveGame.exists()).is_false()
	assert_bool(SaveGame.save()).is_false()
	assert_bool(SaveGame.exists()).is_false()

	# "Apply for a new job" deletes it too (here, one written behind its back).
	write_save_text("{}")
	letters.action_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_false()
	var scene := await await_scene_change()
	assert_str(scene.scene_file_path).is_equal(INTERVIEW_SCENE)

func test_new_game_asks_then_deletes_the_save() -> void:
	ScoreManager.add_shift_score(25)
	assert_bool(SaveGame.save()).is_true()
	var screen: StartScreen = await open_start_screen()

	screen.new_game_button.pressed.emit()
	assert_bool(screen.confirm_panel.visible).is_true()
	assert_bool(screen.menu_panel.visible).is_false()
	screen.cancel_button.pressed.emit()
	assert_bool(screen.menu_panel.visible).is_true()
	assert_bool(SaveGame.exists()).is_true()

	screen.new_game_button.pressed.emit()
	screen.confirm_button.pressed.emit()
	assert_bool(SaveGame.exists()).is_false()
	var scene := await await_scene_change()
	assert_str(scene.scene_file_path).is_equal(INTERVIEW_SCENE)
	assert_int(ScoreManager.total_score).is_equal(0)
