extends "res://tests/support/loan/loan_suite.gd"

## Part 4 of multi-day loan applications: the edge cases. Promotion closes
## every open file quietly and a demotion starts clean; a returned file left
## undecided 15 business days is closed quietly (after the Loan Officer day
## rule, which still comes first); the first shift's teaching cases and going
## home early; every request and every returned decision uses exactly one slot
## application; old saves and a career that never requests a file; and the
## demo helpers (the debug keys) with a file pending.

const PAY_STUB := LoanRequirements.Item.PAY_STUB
const STATEMENT := LoanRequirements.Item.BANK_STATEMENT
const PHOTO_ID := LoanRequirements.Item.PHOTO_ID

const LOAN := PlayerShift.Role.LOAN_OFFICER
const TELLER := PlayerShift.Role.TELLER

const OLD_SAVES := "res://tests/data/old_saves/"
const MAIN_SECTIONS := "res://tests/data/loan/loan_sections_on_main.json"

var lo: LoanOfficerScreen
var review: LoanReviewScreen

func before_test() -> void:
	await super()
	lo = room.loan_officer_screen
	review = lo.loan_review_screen
	for worker in room.loan_desk_workers:
		worker.active = false

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func loan_day_at_9am() -> void:
	start_slots_day()
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()
	lo.hide_screen()
	continue_to_slot(DaySchedule.SLOT_9AM)

## A generated applicant with documents fine except `missing` (the pay stub, the
## statement and the ID), a Personal loan with a clean history.
func filed_application(missing: Array[int]) -> LoanApplication:
	var application := LoanDeskManager.generate_application()
	application.loan_purpose = "Personal"
	application.collateral_kind = LoanApplication.Collateral.NONE
	application.late_30_days = 0
	application.late_60_days = 0
	application.late_90_days = 0
	application.collections = 0
	application.documents_issued = true
	application.doc_problem = LoanApplication.DocProblem.NONE
	application.id_problem = IdCard.Problem.NONE
	application.id_presented = true
	application.has_pay_stub = not missing.has(PAY_STUB)
	application.has_statement = not missing.has(STATEMENT)
	if missing.has(PHOTO_ID):
		application.id_presented = false
		application.id_problem = IdCard.Problem.NO_ID
	if missing.has(PAY_STUB):
		application.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	elif missing.has(STATEMENT):
		application.doc_problem = LoanApplication.DocProblem.MISSING_STATEMENT
	return application

func request_file(application: LoanApplication, items: Array[int], returns_on: int) -> LoanFile:
	var file := LoanRole.request_documents(application, items)
	assert_object(file).is_not_null()
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = returns_on
	file.quality = LoanFile.Quality.COMPLETE
	file.short_item = -1
	file.wrong_item = -1
	return file

func note_roles(role: PlayerShift.Role, days: Array[int]) -> void:
	for day in days:
		LoanRole.note_role(day, role)

func score_and_reputation() -> Vector2i:
	return Vector2i(ScoreManager.total_score, ReputationManager.reputation)

func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

## Loan decisions in the history (what Approvals can override): the
## promotion's own entry is not one of them.
func loan_history_records() -> int:
	var count := 0
	for record in HistoryManager.records:
		if record.role == DecisionRecord.Role.LOAN_OFFICER:
			count += 1
	return count

func open_desk() -> void:
	room._on_loan_officer_desk_interacted()
	lo.review_next_button.pressed.emit()

## Puts `application` first in the pile (which stays three) and opens it.
func open_on_desk(application: LoanApplication) -> void:
	LoanDeskManager.current_player_application()
	LoanDeskManager.player_queue[0] = application
	open_desk()
	assert_object(review.current_application()).is_same(application)

func go_home_from_the_loan_desk() -> void:
	to_closing()
	room._on_loan_officer_desk_interacted()
	lo.clock_out_button.pressed.emit()
	lo.shift_summary_done_button.pressed.emit()
	lo.hide_screen()

## What the saved loan sections of a career that never requests a file are:
## the Loan Officer's role section, the pile and the loan book, through JSON.
## The same steps were run on main (before this feature) to make
## tests/data/loan/loan_sections_on_main.json.
func loan_sections_of_a_career_with_no_files() -> String:
	CareerReset.reset_all()
	LoanDeskManager.seed_source.seed = 424242
	CareerReset.reset_all()
	GameClock.day = 4
	LoanDeskManager.player_queue.clear()
	var first := LoanDeskManager.current_player_application()
	LoanDeskManager.player_decided(first)
	LoanDeskManager.generate_application()
	LoanBookManager.book_loan("Test Borrower", "Auto", 12000.0, LoanApplication.RiskTier.LOW, true, true, "You")
	var career := SaveGame.capture()
	var roles := SaveGame.dict_of(career, "roles")
	var sections := {
		"roles_loan": SaveGame.dict_of(roles, "loan"),
		"loan_desk": SaveGame.dict_of(career, "loan_desk"),
		"loan_book": SaveGame.dict_of(career, "loan_book"),
	}
	return JSON.stringify(sections, "\t", true, true)

# --- promotion ---------------------------------------------------------------------

func test_a_promotion_closes_every_open_file_quietly() -> void:
	GameClock.day = 5
	var waiting := filed_application([PAY_STUB])
	waiting.applicant_name = "Ben Hart"
	request_file(waiting, [PAY_STUB] as Array[int], 9)
	var back := filed_application([STATEMENT])
	back.applicant_name = "Ana Lopez"
	request_file(back, [STATEMENT] as Array[int], 5)
	note_roles(LOAN, [6, 7])
	assert_int(LoanRole.pipeline.files.size()).is_equal(2)
	var loan_records := loan_history_records()
	var book := LoanBookManager.book.size()
	var seen := LoanBookManager.stat(LoanBookManager.period_stats, "good_seen")
	var turned := LoanBookManager.stat(LoanBookManager.period_stats, "turned_away")
	var start := score_and_reputation()
	var xp := XPManager.total_xp
	XPManager._grant_branch_manager()
	acknowledge_letters()
	# Closed: nothing waiting, no role days, the names free again.
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_dict(LoanRole.role_days).is_empty()
	assert_bool(LoanDeskManager.names_taken().has("Ben Hart")).is_false()
	assert_bool(LoanDeskManager.names_taken().has("Ana Lopez")).is_false()
	# Quietly: no penalty, no history record (so nothing in Approvals), no booking.
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(XPManager.total_xp).is_equal(xp)
	assert_int(loan_history_records()).is_equal(loan_records)
	for record in HistoryManager.records:
		assert_str(record.description).not_contains("Ben Hart")
		assert_str(record.description).not_contains("Ana Lopez")
	assert_int(LoanBookManager.book.size()).is_equal(book)
	assert_float(LoanBookManager.stat(LoanBookManager.period_stats, "good_seen")).is_equal(seen)
	assert_float(LoanBookManager.stat(LoanBookManager.period_stats, "turned_away")).is_equal(turned)
	# The waiting list is gone with the desk.
	assert_array(Array(LoanOfficerScreen.files_rows(GameClock.day))).is_empty()
	lo.show_screen()
	assert_bool(lo.files_vbox.visible).is_false()
	# And that day's End of Day says so.
	assert_array(Array(LoanBookManager.summary_lines(true))).is_equal(["Open loan files were passed to your staff"])

func test_a_promotion_with_no_open_files_says_nothing() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	assert_array(Array(LoanBookManager.summary_lines(true))).is_empty()
	var roles := SaveGame.dict_of(SaveGame.capture(), "roles")
	assert_dict(SaveGame.dict_of(roles, "loan")).is_empty()

func test_nothing_from_the_pipeline_runs_after_a_promotion() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var start := score_and_reputation()
	# Even a file that turns up (a save from before the promotion), overdue by
	# the old rule, is closed quietly: no penalty, no withdrawal.
	LoanRole.pipeline.files.append(file)
	GameClock.day = 9
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_vector(score_and_reputation()).is_equal(start)
	assert_array(LoanRole.pipeline.log_withdrawn).is_empty()
	# Later days: nothing at all, and nothing noted or recorded.
	GameClock.day = 12
	assert_array(LoanRole.start_of_day()).is_empty()
	LoanRole.note_role(12, PlayerShift.Role.BRANCH_MANAGER)
	assert_dict(LoanRole.role_days).is_empty()
	assert_vector(score_and_reputation()).is_equal(start)

func test_a_promotion_granted_at_a_clock_out_saves_no_files() -> void:
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 9)
	note_roles(LOAN, [6])
	XPManager._grant_branch_manager()
	acknowledge_letters()
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	SaveGame.restore(career)
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_dict(LoanRole.role_days).is_empty()

# --- demotion ----------------------------------------------------------------------

func test_a_demotion_starts_clean_and_cannot_revive_files_or_role_days() -> void:
	GameClock.day = 5
	request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	XPManager._grant_branch_manager()
	acknowledge_letters()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	# Anything that finds its way back in while a Branch Manager (stray state)
	# goes with the demotion too.
	LoanRole.pipeline.files.append(request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 6))
	LoanRole.role_days[7] = PlayerShift.Role.LOAN_OFFICER
	XPManager.demote_branch_manager()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_dict(LoanRole.role_days).is_empty()
	# Back as a Loan Officer on day 20: the old role days can't count.
	GameClock.day = 20
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 22)
	note_roles(LOAN, [8, 9, 10])
	assert_bool(LoanRole.role_days.has(8)).is_false()
	assert_int(file.loan_officer_days_since_return(23, LoanRole.role_days)).is_equal(0)
	# The clock starts from the days since: three Loan Officer days after the
	# return, then the penalty applies again (not a Branch Manager any more).
	note_roles(LOAN, [23, 24, 25])
	var start := score_and_reputation()
	GameClock.day = 25
	assert_array(LoanRole.start_of_day()).is_empty()
	GameClock.day = 26
	assert_array(LoanRole.start_of_day()).has_size(1)
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))

func test_the_numbers_of_the_new_expiry_are_in_the_loan_config() -> void:
	assert_int(LoanConfig.ABANDONED_AFTER_DAYS).is_equal(15)

# --- absolute expiry ----------------------------------------------------------------

func test_a_returned_file_is_abandoned_fifteen_days_after_it_came_back() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	assert_bool(file.is_abandoned(19)).is_false()
	assert_bool(file.is_abandoned(20)).is_true()
	assert_bool(file.is_abandoned(200)).is_true()
	# Not while it hasn't come back.
	var out := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], 30)
	assert_bool(out.is_abandoned(29)).is_false()

func test_a_file_parked_by_a_teller_only_player_is_closed_quietly_at_fifteen_days() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	application.applicant_name = "Dee Ford"
	var file := request_file(application, [PAY_STUB] as Array[int], 5)
	# Fourteen Teller days: not a Loan Officer day among them.
	for day in range(6, 20):
		note_roles(TELLER, [day])
	var start := score_and_reputation()
	var xp := XPManager.total_xp
	for day in range(5, 20):
		GameClock.day = day
		assert_array(LoanRole.start_of_day()).override_failure_message("day %d" % day).is_empty()
		assert_object(LoanRole.pipeline.file_for(application)).override_failure_message("gone at day %d" % day).is_same(file)
	GameClock.day = 20
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_object(LoanRole.pipeline.file_for(application)).is_null()
	# No penalty of any kind, and the End of Day says what happened.
	assert_vector(score_and_reputation()).is_equal(start)
	assert_int(XPManager.total_xp).is_equal(xp)
	assert_array(LoanRole.pipeline.log_withdrawn).is_empty()
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Files left undecided too long were closed: Dee Ford"])
	# The place is free again.
	for index in 3:
		assert_object(LoanRole.request_documents(filed_application([PAY_STUB]), [PAY_STUB] as Array[int])).is_not_null()

func test_a_file_that_used_its_loan_officer_days_is_withdrawn_with_the_penalty_first() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	application.applicant_name = "Eli Park"
	var file := request_file(application, [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7, 8])
	# Opening skipped from day 5 to day 20 (the rule is a function of the days):
	# both rules apply; the penalty comes first.
	var start := score_and_reputation()
	GameClock.day = 20
	assert_array(LoanRole.start_of_day()).is_equal([file])
	assert_vector(score_and_reputation() - start).is_equal(Vector2i(LoanConfig.WITHDRAWN_SCORE, LoanConfig.WITHDRAWN_REPUTATION))
	assert_array(LoanRole.pipeline.log_abandoned).is_empty()
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Files withdrawn, not decided in time: Eli Park (-2 Score, -1 Reputation)"])

func test_a_file_with_only_two_loan_officer_days_is_closed_quietly_at_fifteen() -> void:
	GameClock.day = 5
	var file := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5)
	note_roles(LOAN, [6, 7])
	for day in range(8, 20):
		note_roles(TELLER, [day])
	var start := score_and_reputation()
	for day in range(5, 20):
		GameClock.day = day
		assert_array(LoanRole.start_of_day()).is_empty()
	assert_bool(LoanRole.pipeline.files.has(file)).is_true()
	GameClock.day = 20
	assert_array(LoanRole.start_of_day()).is_empty()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_vector(score_and_reputation()).is_equal(start)

func test_the_abandoned_files_line_survives_a_save_and_a_reload() -> void:
	GameClock.day = 5
	var application := filed_application([PAY_STUB])
	application.applicant_name = "Dee Ford"
	request_file(application, [PAY_STUB] as Array[int], 5)
	GameClock.day = 20
	LoanRole.start_of_day()
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	SaveGame.restore(career)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Files left undecided too long were closed: Dee Ford"])

# --- the first shift, and going home early --------------------------------------------

func test_the_three_teaching_cases_never_show_the_request_button() -> void:
	loan_day_at_9am()
	var first_slots: Array[StringName] = [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM]
	for slot in first_slots:
		continue_to_slot(slot)
		var teaching := LoanDeskManager.current_player_application()
		assert_bool(LoanApplicationsData.is_teaching_case(teaching.applicant_name)).is_true()
		open_desk()
		assert_bool(review.request_button.visible).is_false()
		assert_str(review.request_note_label.text).is_equal(LoanReviewScreen.REQUEST_TEACHING_TEXT)
		review.verify_documents_button.pressed.emit()
		assert_bool(review.request_button.visible).is_false()
		review.run_credit_check_button.pressed.emit()
		review.approve_button.pressed.emit()
		review.close_button.pressed.emit()
		lo.hide_screen()
		await frames(3)
	# The fourth is generated: now there is a button.
	continue_to_slot(DaySchedule.SLOT_3PM)
	var fourth := LoanDeskManager.current_player_application()
	assert_bool(LoanApplicationsData.is_teaching_case(fourth.applicant_name)).is_false()
	open_desk()
	assert_bool(review.request_button.visible).is_true()

func test_a_request_made_before_going_home_early_is_saved_by_end_of_day() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	application.applicant_name = "Fay Cole"
	open_on_desk(application)
	review.verify_documents_button.pressed.emit()
	review.request_button.pressed.emit()
	review.request_checks[PAY_STUB].button_pressed = true
	review.confirm_request_button.pressed.emit()
	review.close_button.pressed.emit()
	lo.hide_screen()
	await frames(3)
	# Home early, clocked out, End of Day (which saves).
	go_home_from_the_loan_desk()
	await run_end_of_day()
	var saved := SaveGame.read_file(TEST_SAVE_PATH)
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	var roles := SaveGame.dict_of(saved.career, "roles")
	var loan := SaveGame.dict_of(roles, "loan")
	var pipeline := SaveGame.dict_of(loan, LoanRole.PIPELINE_KEY)
	var files := SaveGame.dicts_of(SaveGame.array_of(pipeline, "files"))
	assert_int(files.size()).is_equal(1)
	assert_str(SaveGame.string_of(SaveGame.dict_of(files[0], "application"), "applicant_name", "")).is_equal("Fay Cole")
	# Loading it gives the file back, and that day's role with it.
	CareerReset.reset_all()
	SaveGame.restore(saved.career)
	assert_int(LoanRole.pipeline.files.size()).is_equal(1)
	assert_str(LoanRole.pipeline.files[0].application.applicant_name).is_equal("Fay Cole")
	assert_int(LoanRole.role_days[GameClock.day]).is_equal(PlayerShift.Role.LOAN_OFFICER)

func test_going_home_early_skips_the_work_slot_without_losing_a_returned_file() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB] as Array[int], GameClock.day)
	room._process(0.0)
	assert_bool(room.player_loan_seat().is_empty()).is_false()
	assert_object(room.player_loan_seat().application).is_same(application)
	# Home early: the 9 AM slot is skipped, the applicant sent away, the file kept.
	var start := score_and_reputation()
	go_home_from_the_loan_desk()
	assert_bool(room.player_loan_seat().is_empty() or room.player_loan_seat().phase == LoanDeskSeat.Phase.LEAVING).is_true()
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	assert_array(LoanRole.pipeline.returned_files(GameClock.day)).is_equal([file])
	await run_end_of_day()
	assert_vector(score_and_reputation()).is_equal(start)
	assert_object(LoanDeskManager.current_player_application()).is_same(application)
	# The next day it is still there, back, and no penalty has been charged.
	var day := GameClock.day
	assert_int(LoanRole.role_days[day]).is_equal(PlayerShift.Role.LOAN_OFFICER)
	room.end_of_day_screen.next_day_button.pressed.emit()
	if room.end_of_day_screen.is_closure_shown():
		room.end_of_day_screen.next_day_button.pressed.emit()
	assert_int(GameClock.day).is_greater(day)
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	assert_vector(score_and_reputation()).is_equal(start)

# --- slot rules ---------------------------------------------------------------------

func test_every_request_and_every_returned_decision_uses_exactly_one_slot_application() -> void:
	# The strings the HUD and the card show don't change.
	assert_str(LoanSlotAdapter.STATUS_TEXT % [0, 1]).is_equal("Application: 0 / 1")
	assert_str(LoanSlotAdapter.REPORT_TEXT % 2).is_equal("Applications decided: 2")
	loan_day_at_9am()
	var adapter := loan_slot_adapter()
	# A file back today: it is the 9 AM slot's application; and a second one back
	# the same day waits for the next slot.
	var first_back := request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], GameClock.day)
	var second_back := request_file(filed_application([STATEMENT]), [STATEMENT] as Array[int], GameClock.day)
	var slots: Array[StringName] = [DaySchedule.SLOT_9AM, DaySchedule.SLOT_11AM, DaySchedule.SLOT_1PM, DaySchedule.SLOT_3PM]
	var names: Array[String] = ["9 AM", "11 AM", "1 PM", "3 PM"]
	for index in 4:
		continue_to_slot(slots[index])
		assert_str(adapter.status_text()).is_equal("Application: 0 / 1")
		assert_int(lo.applications_left()).is_equal(1)
		var reviewed_at_start := lo.applications_reviewed
		if index == 2:
			# A generated applicant (the pile starts with the teaching cases).
			LoanDeskManager.current_player_application()
			LoanDeskManager.player_queue[0] = filed_application([PAY_STUB])
		var on_desk := LoanDeskManager.current_player_application()
		open_desk()
		review.verify_documents_button.pressed.emit()
		match index:
			0, 1:
				# The returned files, one in each slot (decided).
				assert_bool(on_desk == first_back.application or on_desk == second_back.application).is_true()
				review.run_credit_check_button.pressed.emit()
				review.approve_button.pressed.emit()
			2:
				# A request on a new applicant.
				review.request_button.pressed.emit()
				review.request_checks[PAY_STUB].button_pressed = true
				review.confirm_request_button.pressed.emit()
			3:
				# A returned decision again: the file asked for in the 1 PM slot, made back.
				review.run_credit_check_button.pressed.emit()
				review.approve_button.pressed.emit()
		# Exactly one slot application used, whatever it was, and no more offered.
		assert_int(lo.applications_reviewed - reviewed_at_start).is_equal(1)
		assert_int(lo.applications_left()).is_equal(0)
		assert_bool(lo.review_next_button.disabled).is_true()
		assert_str(adapter.status_text()).is_equal("Application: 1 / 1")
		review.close_button.pressed.emit()
		lo.hide_screen()
		await frames(3)
		assert_bool(DayFlow.is_between_slots()).override_failure_message("%s slot didn't end" % names[index]).is_true()
		assert_str(slot_card().done_label.text).is_equal("%s slot done\nApplications decided: 1" % names[index])
		if index == 2:
			# Make the new file come back for the last slot.
			var asked := LoanRole.pipeline.files[0]
			asked.timing = LoanFile.Timing.ON_TIME
			asked.return_day = GameClock.day
	assert_int(lo.applications_reviewed).is_equal(4)

# --- old saves and a career that never requests a file --------------------------------------

func test_every_old_save_loads_with_no_files_and_no_role_days() -> void:
	var loaded := 0
	for file_name in DirAccess.get_files_at(OLD_SAVES):
		if not file_name.ends_with(".json"):
			continue
		var saved := SaveGame.read_file(OLD_SAVES + file_name)
		assert_int(saved.status).override_failure_message(file_name).is_equal(SaveGame.Status.OK)
		# Something left over from another career must not survive the load.
		LoanRole.pipeline.files.append(request_file(filed_application([PAY_STUB]), [PAY_STUB] as Array[int], 5))
		LoanRole.role_days[3] = PlayerShift.Role.LOAN_OFFICER
		SaveGame.restore(saved.career)
		assert_bool(LoanRole.pipeline.is_empty()).override_failure_message(file_name).is_true()
		assert_int(LoanRole.pipeline.next_file_number).override_failure_message(file_name).is_equal(1)
		assert_dict(LoanRole.role_days).override_failure_message(file_name).is_empty()
		assert_dict(LoanRole.save_data()).override_failure_message(file_name).is_empty()
		loaded += 1
	assert_int(loaded).is_greater_equal(5)

func test_a_career_that_never_requests_a_file_saves_what_main_saved() -> void:
	var expected := FileAccess.get_file_as_string(MAIN_SECTIONS).replace("
", "
")
	assert_str(expected).is_not_empty()
	var now := loan_sections_of_a_career_with_no_files()
	assert_str(now).is_equal(expected)
	# And the role section itself is exactly what it always was: empty.
	assert_dict(LoanRole.save_data()).is_empty()

# --- the demo helpers -------------------------------------------------------------------

func test_the_real_loan_debug_keys_are_reserved_and_do_nothing_yet() -> void:
	assert_str(DebugKeys.LOAN_1).is_equal("debug_loan_1")
	assert_str(DebugKeys.LOAN_2).is_equal("debug_loan_2")
	assert_int(DebugKeys.RESERVED[DebugKeys.LOAN_1]).is_equal(KEY_F9)
	assert_int(DebugKeys.RESERVED[DebugKeys.LOAN_2]).is_equal(KEY_F10)
	assert_bool(InputMap.has_action(DebugKeys.LOAN_1)).is_true()
	assert_bool(InputMap.has_action(DebugKeys.LOAN_2)).is_true()

func test_f2_and_f3_leave_a_pending_file_alone_and_f1_passes_it_to_the_staff() -> void:
	loan_day_at_9am()
	var application := filed_application([PAY_STUB])
	var file := request_file(application, [PAY_STUB] as Array[int], GameClock.day + 3)
	var shape := file.save_data()
	# F2: Loan Officer unlock only (XP and Reputation raised, never lowered).
	room.apply_debug_key(TellerRoom.DEBUG_LOAN_OFFICER_KEY)
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	assert_dict(file.save_data()).is_equal(shape)
	# F3: skips the running slot; the file is untouched.
	assert_bool(slot_day().debug_skip_slot()).is_true()
	assert_object(LoanRole.pipeline.file_for(application)).is_same(file)
	assert_dict(file.save_data()).is_equal(shape)
	# F1 promotes (through the normal checks, held until clock-out when on
	# shift): once granted, the open files go to the staff quietly.
	room.apply_debug_key(TellerRoom.DEBUG_UNLOCK_KEY)
	XPManager._grant_branch_manager()
	acknowledge_letters()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_array(Array(LoanBookManager.summary_lines(true))).is_equal(["Open loan files were passed to your staff"])
