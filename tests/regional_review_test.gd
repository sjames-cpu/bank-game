extends "res://tests/support/teller_room_suite.gd"

## The Regional Manager's review of the Branch Manager (RegionalManager):
## reviews every 5 days as Branch Manager, at that day's End of Day before
## the summary; the rating's weights for a well-run week, a neglected week
## of going home early and a week of unfair reports; each rating's
## consequences; demotion at 3 regional warnings (closing the review queue)
## and promotion again; the
## review-day visit; the HUD line; save, load and reset.

const Rating := RegionalManager.Rating
const Severity := StaffReviewItem.Severity
const Action := StaffReviewManager.Action
const Mistake := StaffReviewItem.TellerMistake
const Vault := VaultReconciliationScreen.DiscrepancyResult

var letters: DisciplineLetterScreen
var bm: BranchManagerScreen
var eod: EndOfDayScreen
## Every review result since the test started.
var reviews: Array[Dictionary] = []

func before_test() -> void:
	await super()
	letters = room.letter_screen
	bm = room.branch_manager_screen
	eod = room.end_of_day_screen
	reviews.clear()
	RegionalManager.review_completed.connect(_on_review_completed)

func after_test() -> void:
	RegionalManager.review_completed.disconnect(_on_review_completed)
	await super()

func _on_review_completed(result: Dictionary) -> void:
	reviews.append(result)

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Sets the clock, with the business day following it.
func set_clock(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

## Branch Manager from today (the promotion letter clicked away).
func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

func staff(staff_name: String) -> StaffMember:
	for member in ScheduleManager.get_roster():
		if member.staff_name == staff_name:
			return member
	return null

## A staff teller mistake in the review queue (stamped now).
func teller_item(mistake: Mistake, staff_name: String = "Derek Voss") -> StaffReviewItem:
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	customer.display_name = "Sam Chen"
	customer.intent_type = ShiftTransaction.Type.DEPOSIT
	customer.intent_amount_cents = 20000
	return StaffReviewManager.add_teller_mistake(staff(staff_name), ScheduleManager.SLOT_TELLER_WINDOW_1, customer, mistake, "test detail")

## `count` pieces of staff teller work at Teller Window 1, `wrong` of them mistakes.
func staff_work(count: int, wrong: int) -> void:
	for i in count:
		HistoryManager.add_staff_record("Derek Voss", ScheduleManager.SLOT_TELLER_WINDOW_1, "Deposit $20", "Mistake" if i < wrong else "Correct")

func bm_clock_in() -> void:
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters() # the first shift's orientation

## A Perfect vault count, then clock-out and the summary closed.
func bm_clock_out() -> void:
	bm.vault_reconciliation_button.pressed.emit()
	var vault := bm.vault_reconciliation_screen
	var remaining := VaultReconciliationScreen.EXPECTED_VAULT_CENTS
	for i in VaultReconciliationScreen.DENOMINATION_CENTS.size():
		var denom := VaultReconciliationScreen.DENOMINATION_CENTS[i]
		vault.quantity_inputs[i].value = floori(float(remaining) / denom)
		remaining -= floori(float(remaining) / denom) * denom
	vault.submit_button.pressed.emit()
	vault.close_button.pressed.emit()
	bm.clock_out_button.pressed.emit()
	bm.shift_summary_done_button.pressed.emit()
	bm.hide_screen()

## Off shift: the doormat, "Go home", then whatever comes (a review's letters,
## then the summary), and on to the next morning.
func go_home_and_start_next_day() -> void:
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	acknowledge_letters()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	eod.next_day_button.pressed.emit()

## A working day as Branch Manager: clock in at noon, do `work`, reconcile the
## vault (Perfect), clock out and go home.
func work_day(day: int, work: Callable) -> void:
	set_clock(day, 12, 0)
	bm_clock_in()
	work.call()
	bm_clock_out()
	await go_home_and_start_next_day()

func area_of(result: Dictionary, key: String) -> Dictionary:
	var areas: Array = result["areas"]
	for entry: Variant in areas:
		var area: Dictionary = entry
		if area["key"] == key:
			return area
	return {}

# --- schedule ---------------------------------------------------------------------

func test_reviews_come_every_5_days_as_branch_manager() -> void:
	# Two days as a Loan Officer don't count.
	await go_home_and_start_next_day()
	await go_home_and_start_next_day()
	assert_int(RegionalManager.next_review_day()).is_equal(0)
	assert_str(RegionalManager.status_text()).is_equal("")
	# Promoted on Day 3: the first review is at the end of its 5th full day.
	promote()
	assert_int(RegionalManager.next_review_day()).is_equal(8)
	for day in range(3, 8):
		assert_int(BusinessDay.stats_day).is_equal(day)
		await go_home_and_start_next_day()
		assert_array(reviews).override_failure_message("reviewed on Day %d" % day).is_empty()

	# Day 8: the review letter comes before the summary.
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	assert_int(reviews.size()).is_equal(1)
	assert_bool(letters.visible).is_true()
	assert_bool(eod.visible).is_false()
	assert_str(letters.title_label.text).is_equal("Branch Manager Review — Days 4-8")
	assert_str(letters.from_label.text).is_equal("From: Regional Manager")
	assert_str(letters.body_label.text).contains("Rating: Unsatisfactory")
	acknowledge_letters()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()
	assert_str(eod.summary_title_label.text).is_equal("End of Day 8")
	eod.next_day_button.pressed.emit()

	# Then every 5 days.
	assert_int(RegionalManager.next_review_day()).is_equal(13)
	for day in range(9, 13):
		await go_home_and_start_next_day()
	assert_int(reviews.size()).is_equal(1)
	await go_home_and_start_next_day()
	assert_int(reviews.size()).is_equal(2)
	assert_int(reviews[1]["first_day"]).is_equal(9)
	assert_int(reviews[1]["last_day"]).is_equal(13)
	assert_int(RegionalManager.next_review_day()).is_equal(18)

# --- ratings -------------------------------------------------------------------------

func test_a_well_run_week_exceeds_expectations() -> void:
	promote()
	var start := totals()
	# Days 2-6: a shift every day with a Perfect vault, every serious error
	# reported, and a steady team.
	for day in range(2, 7):
		await work_day(day, func() -> void:
			StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
			staff_work(10, 0 if day > 2 else 1)
		)
	assert_int(reviews.size()).is_equal(1)
	var result := reviews[0]
	assert_int(result["rating"]).is_equal(Rating.EXCEEDS)
	assert_float(result["score"]).is_equal_approx(100.0, 0.01)
	assert_str(area_of(result, RegionalManager.AREA_VAULT)["detail"]).is_equal("Reconciled on 5 of 5 days (5 Perfect).")
	assert_str(area_of(result, RegionalManager.AREA_IGNORED)["detail"]).is_equal("5 serious errors: 5 reviewed, 0 left unreviewed.")
	assert_bool(area_of(result, RegionalManager.AREA_HIRING)["rated"]).is_false()
	# The bonus came on top of the week's own points.
	assert_int(result["score_change"]).is_equal(RegionalManager.EXCEEDS_SCORE)
	assert_int(result["reputation_change"]).is_equal(RegionalManager.EXCEEDS_REPUTATION)
	assert_int(totals().x - start.x).is_greater_equal(RegionalManager.EXCEEDS_SCORE)
	assert_int(RegionalManager.warnings).is_equal(0)

func test_a_neglected_week_of_going_home_early_is_unsatisfactory() -> void:
	promote()
	# Two serious errors come up, and the manager goes home every morning
	# without working: no vault counts, nothing reviewed.
	await go_home_and_start_next_day() # the promotion day
	set_clock(3, 8, 30)
	teller_item(Mistake.WRONG_ACCOUNT)
	teller_item(Mistake.WRONG_ACCOUNT, "Nina Ortiz")
	for day in range(2, 7):
		set_clock(day, 8, 30)
		await go_home_and_start_next_day()
	assert_int(reviews.size()).is_equal(1)
	var result := reviews[0]
	# Vault 0 (25%), serious errors 2 unreviewed = 50 (20%), vacancies 100
	# (5%); nothing else to rate: (0 + 1000 + 500) / 50 = 30.
	assert_float(area_of(result, RegionalManager.AREA_VAULT)["score"]).is_equal(0.0)
	assert_str(area_of(result, RegionalManager.AREA_VAULT)["detail"]).is_equal("Reconciled on 0 of 5 days; 5 days with no count.")
	assert_float(area_of(result, RegionalManager.AREA_IGNORED)["score"]).is_equal(50.0)
	assert_bool(area_of(result, RegionalManager.AREA_UNFAIR)["rated"]).is_false()
	assert_float(result["score"]).is_equal_approx(30.0, 0.01)
	assert_int(result["rating"]).is_equal(Rating.UNSATISFACTORY)
	assert_int(result["reputation_change"]).is_equal(RegionalManager.UNSATISFACTORY_REPUTATION)
	assert_int(RegionalManager.warnings).is_equal(1)

func test_a_week_of_unfair_reports_needs_improvement() -> void:
	promote()
	# Like the well-run week, but on three days a minor slip is reported too.
	for day in range(2, 7):
		await work_day(day, func() -> void:
			StaffReviewManager.decide(teller_item(Mistake.WRONG_ACCOUNT), Action.REPORT)
			if day <= 4:
				StaffReviewManager.decide(teller_item(Mistake.AMOUNT_SHORT, "Nina Ortiz"), Action.REPORT)
			staff_work(10, 0)
		)
	var result := reviews[0]
	var unfair := area_of(result, RegionalManager.AREA_UNFAIR)
	assert_str(unfair["detail"]).is_equal("8 reviews, 3 unfair reports.")
	assert_float(unfair["score"]).is_equal(0.0)
	# Everything else perfect: (100 x 70 + 0 x 25) / 95 = 73.7.
	assert_float(result["score"]).is_equal_approx(7000.0 / 95.0, 0.01)
	assert_int(result["rating"]).is_equal(Rating.NEEDS_IMPROVEMENT)
	assert_int(RegionalManager.warnings).is_equal(1)

func test_each_area_follows_its_weights() -> void:
	promote()
	set_clock(2, 12, 0)
	RegionalManager.note_vault_result(Vault.MINOR)
	set_clock(3, 12, 0)
	RegionalManager.note_vault_result(Vault.MAJOR)
	RegionalManager.note_vault_result(Vault.PERFECT) # the day's best counts
	RegionalManager.serious_reviewed = 2
	RegionalManager.serious_excused = 1
	RegionalManager.serious_ignored = 1
	RegionalManager.reviews = 4
	RegionalManager.unfair_reports = 1
	RegionalManager.staff_work = 40
	RegionalManager.staff_mistakes = 10 # 25%: halfway from 10% to 40%
	RegionalManager.staff_line_served = 18
	RegionalManager.staff_line_abandoned = 2 # 10% of 20: 60
	RegionalManager.vacant_desk_minutes = 240.0 # 4 desk-hours: 90
	RegionalManager.hire_verdicts.assign([HiringManager.Verdict.BEST, HiringManager.Verdict.WEAKEST])
	var result := RegionalManager.evaluate()
	var expected: Dictionary[String, float] = {
		RegionalManager.AREA_VAULT: (70.0 + 100.0) / 5.0,
		RegionalManager.AREA_IGNORED: 75.0,
		RegionalManager.AREA_UNFAIR: 60.0,
		RegionalManager.AREA_EXCUSED: 50.0,
		RegionalManager.AREA_MISTAKES: 50.0,
		RegionalManager.AREA_ABANDONED: 60.0,
		RegionalManager.AREA_VACANCY: 90.0,
		RegionalManager.AREA_HIRING: 60.0,
	}
	var weighted := 0.0
	for key: String in expected:
		var area := area_of(result, key)
		assert_bool(area["rated"]).is_true()
		assert_float(area["score"]).override_failure_message(key).is_equal_approx(expected[key], 0.01)
		weighted += expected[key] * RegionalManager.AREA_WEIGHTS[key]
	assert_float(result["score"]).is_equal_approx(weighted / 100.0, 0.01)
	# The weights add up to 100, and the bands sit where documented.
	var total := 0
	for key: String in RegionalManager.AREA_WEIGHTS:
		total += RegionalManager.AREA_WEIGHTS[key]
	assert_int(total).is_equal(100)
	assert_int(RegionalManager.rating_for(92.0)).is_equal(Rating.EXCEEDS)
	assert_int(RegionalManager.rating_for(91.9)).is_equal(Rating.MEETS)
	assert_int(RegionalManager.rating_for(80.0)).is_equal(Rating.MEETS)
	assert_int(RegionalManager.rating_for(79.9)).is_equal(Rating.NEEDS_IMPROVEMENT)
	assert_int(RegionalManager.rating_for(50.0)).is_equal(Rating.NEEDS_IMPROVEMENT)
	assert_int(RegionalManager.rating_for(49.9)).is_equal(Rating.UNSATISFACTORY)

func test_the_review_collects_from_the_branch() -> void:
	promote()
	set_clock(2, 12, 0)
	bm_clock_in()
	# Reviewed (an unfair report), left to be ignored at clock-out, and a
	# vault count: all through the Branch Manager's own screens.
	StaffReviewManager.decide(teller_item(Mistake.AMOUNT_SHORT), Action.REPORT)
	teller_item(Mistake.WRONG_ACCOUNT, "Nina Ortiz")
	bm_clock_out()
	assert_int(RegionalManager.vault_by_day[2]).is_equal(Vault.PERFECT)
	assert_int(RegionalManager.reviews).is_equal(1)
	assert_int(RegionalManager.unfair_reports).is_equal(1)
	assert_int(RegionalManager.serious_ignored).is_equal(1)
	# Staff work, a customer giving up at a staffed window, and a hire.
	staff_work(3, 1)
	var customer: CustomerNPC = auto_free(CustomerNPC.new())
	room.window1_npc_line.customer_abandoned.emit(customer)
	HiringManager.staff_hired.emit({"verdict": HiringManager.Verdict.MIDDLE})
	assert_int(RegionalManager.staff_work).is_equal(3)
	assert_int(RegionalManager.staff_mistakes).is_equal(1)
	assert_int(RegionalManager.staff_line_served).is_equal(3)
	assert_int(RegionalManager.staff_line_abandoned).is_equal(1)
	assert_array(RegionalManager.hire_verdicts).is_equal([HiringManager.Verdict.MIDDLE])
	# A vacant desk counts during opening hours only, including hours skipped
	# by going home.
	ScheduleManager.dismiss_staff(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_1).staff_name)
	set_clock(3, 8, 0)
	RegionalManager.sample_vacancies()
	set_clock(3, 11, 0)
	RegionalManager.sample_vacancies()
	assert_float(RegionalManager.vacant_desk_minutes).is_equal_approx(120.0, 0.01)
	BusinessDay.go_home_early()
	RegionalManager.sample_vacancies()
	assert_float(RegionalManager.vacant_desk_minutes).is_equal_approx(480.0, 0.01)
	# Nothing is collected before a promotion.
	RegionalManager.reset()
	XPManager.is_branch_manager_unlocked = false
	staff_work(5, 5)
	assert_int(RegionalManager.staff_work).is_equal(0)

# --- consequences ---------------------------------------------------------------------

func consequence_of(rating: Rating, warnings_before: int) -> Dictionary:
	RegionalManager.warnings = warnings_before
	var result := {"rating": rating}
	RegionalManager.apply_consequences(result)
	return result

func test_each_rating_has_its_consequence() -> void:
	promote()
	var start := totals()
	var exceeds := consequence_of(Rating.EXCEEDS, 2)
	assert_int(RegionalManager.warnings).is_equal(1)
	assert_vector(totals() - start).is_equal(Vector3i(15, 3, 150))
	assert_int(exceeds["xp_change"]).is_equal(150)

	start = totals()
	consequence_of(Rating.MEETS, 1)
	assert_int(RegionalManager.warnings).is_equal(1)
	assert_vector(totals() - start).is_equal(Vector3i.ZERO)

	consequence_of(Rating.NEEDS_IMPROVEMENT, 1)
	assert_int(RegionalManager.warnings).is_equal(2)
	assert_vector(totals() - start).is_equal(Vector3i.ZERO)

	consequence_of(Rating.UNSATISFACTORY, 0)
	assert_int(RegionalManager.warnings).is_equal(1)
	assert_vector(totals() - start).is_equal(Vector3i(0, -5, 0))

func test_exceeds_removes_a_warning_but_never_below_none() -> void:
	promote()
	consequence_of(Rating.EXCEEDS, 1)
	assert_int(RegionalManager.warnings).is_equal(0)
	var result := consequence_of(Rating.EXCEEDS, 0)
	assert_int(RegionalManager.warnings).is_equal(0)
	result["first_day"] = 2
	result["last_day"] = 6
	result["score"] = 95.0
	result["areas"] = []
	assert_str(RegionalManager.review_body(result)).contains("You have no regional warnings to remove.")
	result["warnings_before"] = 1
	assert_str(RegionalManager.review_body(result)).contains("One regional warning has been removed.")

func test_the_review_letter_breaks_down_each_area() -> void:
	promote()
	set_clock(6, 8, 30)
	RegionalManager.warnings = 1
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	var body := letters.body_label.text
	assert_str(body).contains("This is your review for your last 5 days as Branch Manager (Days 2-6).")
	assert_str(body).contains("Rating: Unsatisfactory (17 / 100)")
	assert_str(body).contains("Vault reconciliation — 0/100 (weight 25%)")
	assert_str(body).contains("To improve: reconcile the vault every day, even on a short one.")
	assert_str(body).contains("Vacant desks — 100/100 (weight 5%)")
	assert_str(body).contains("Well done: no desk stood empty.")
	assert_str(body).contains("Hiring — not rated")
	assert_str(body).contains("This review adds a regional warning and costs 5 Reputation.")
	assert_str(body).contains("Regional warnings: 2 of 3. At 3 you'll return to the Loan Officer role.")
	# A long letter scrolls inside the shared panel.
	await frames(3)
	assert_float(letters.letter_panel.size.y).is_less_equal(letters.max_panel_height() + 1.0)

# --- demotion -------------------------------------------------------------------------

func test_three_warnings_demote_to_loan_officer() -> void:
	promote()
	assert_bool(ScheduleManager.is_teller_window_3_open).is_true()
	var window_3_staff := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_3)
	assert_object(window_3_staff).is_not_null()
	StaffReviewManager.staff_reports["Derek Voss"] = PackedStringArray(["late"])
	var roster_before := ScheduleManager.get_roster().size()
	RegionalManager.warnings = 2
	XPManager.total_xp = 1800

	# An Unsatisfactory review on Day 6 is the third warning.
	set_clock(6, 8, 30)
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	assert_str(letters.title_label.text).is_equal("Branch Manager Review — Days 2-6")
	assert_str(letters.body_label.text).contains("Regional warnings: 3 of 3. That is the limit")
	letters.action_button.pressed.emit()
	assert_str(letters.title_label.text).is_equal("Notice of Demotion")
	assert_str(letters.from_label.text).is_equal("From: Regional Manager")
	assert_str(letters.body_label.text).contains("To be promoted again you'll need 500 more XP (2300 in total) and Reputation of at least 60.")
	letters.action_button.pressed.emit()
	await frames(2)
	assert_bool(eod.is_summary_shown()).is_true()

	# A Loan Officer again.
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_int(XPManager.repromotion_xp_target).is_equal(2300)
	assert_str(Hud.role_name()).is_equal("Loan Officer")
	assert_int(RegionalManager.warnings).is_equal(0)
	assert_int(RegionalManager.next_review_day()).is_equal(0)
	# Teller Window 3 is gone, its staff member back on the roster unassigned.
	assert_bool(ScheduleManager.is_teller_window_3_open).is_false()
	assert_object(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_3)).is_null()
	assert_str(ScheduleManager.slot_of(window_3_staff.staff_name)).is_equal("")
	assert_bool(room._staff_by_slot.has(ScheduleManager.SLOT_TELLER_WINDOW_3)).is_false()
	assert_bool(room.window3_line.active).is_false()
	assert_bool(ScheduleManager.vacant_slots().is_empty()).is_true()
	# Staff, hires and staff reports stay.
	assert_int(ScheduleManager.get_roster().size()).is_equal(roster_before)
	assert_int(StaffReviewManager.reports_for("Derek Voss")).is_equal(1)
	# The Branch Manager desk hides; the player's desks are theirs again.
	assert_bool(room.branch_manager_desk.visible).is_false()
	assert_bool(room.branch_manager_desk.monitoring).is_false()
	eod.next_day_button.pressed.emit()
	assert_str(room.interaction_prompt_text(room.teller_desk)).is_equal("E — Clock in (Player Teller Window)")
	assert_str(room.interaction_prompt_text(room.loan_officer_desk)).is_equal("E — Clock in (Loan Desk)")
	room._on_teller_desk_interacted()
	assert_bool(ts.visible).is_true()
	close_desk()
	room._on_loan_officer_desk_interacted()
	assert_bool(room.loan_officer_screen.visible).is_true()
	room.loan_officer_screen.close_button.pressed.emit()
	# Reports apply again, from none.
	assert_bool(ReportManager.is_exempt).is_false()
	assert_str(ReportManager.status_text()).is_equal("Reports: 0 / 3")
	for i in ReportManager.MISTAKES_PER_REPORT:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Customer %d" % i)
	assert_int(ReportManager.get_report_count()).is_equal(1)
	acknowledge_letters()
	# Saved demoted.
	var saved := SaveGame.read().career
	assert_bool(SaveGame.bool_of(SaveGame.dict_of(saved, "xp"), "is_branch_manager_unlocked", true)).is_false()

func test_promotion_again_needs_500_more_xp_and_reputation_60() -> void:
	promote()
	set_clock(2, 12, 0)
	bm_clock_in() # sees the orientation
	bm_clock_out()
	XPManager.total_xp = 1600
	ReputationManager.reputation = 70
	RegionalManager._demote()
	acknowledge_letters()
	assert_int(XPManager.repromotion_xp_target).is_equal(2100)
	assert_int(XPManager.branch_manager_xp_required()).is_equal(2100)

	# 490 more XP isn't enough.
	XPManager.add_shift_xp(49)
	assert_int(XPManager.total_xp).is_equal(2090)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	# 500 more is, but not below Reputation 60.
	ReputationManager.reputation = 59
	XPManager.add_shift_xp(1)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	ReputationManager.add_reputation(1)
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()

	# The usual promotion: its letter, Teller Window 3, a new review window,
	# and no second orientation.
	assert_str(letters.title_label.text).is_equal("Letter of Promotion")
	acknowledge_letters()
	assert_bool(ScheduleManager.is_teller_window_3_open).is_true()
	assert_bool(room.branch_manager_desk.visible).is_true()
	assert_bool(ReportManager.is_exempt).is_true()
	assert_int(RegionalManager.next_review_day()).is_equal(7)
	assert_int(RegionalManager.warnings).is_equal(0)
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	assert_bool(bm.is_clocked_in()).is_true()
	assert_bool(letters.visible).is_false()

func records_graded(grade_label: String) -> Array[DecisionRecord]:
	var found: Array[DecisionRecord] = []
	for record in HistoryManager.records:
		if record.grade_label == grade_label:
			found.append(record)
	return found

func test_demotion_closes_waiting_review_items_without_penalty() -> void:
	promote()
	set_clock(2, 12, 0)
	bm_clock_in()
	teller_item(Mistake.WRONG_ACCOUNT) # serious
	teller_item(Mistake.AMOUNT_SHORT) # minor
	bm_clock_out() # the serious one is closed as ignored; the minor one waits
	assert_int(records_graded("Ignored").size()).is_equal(1)
	teller_item(Mistake.WRONG_ACCOUNT, "Walter Higgins") # waiting, serious
	assert_int(StaffReviewManager.queue.size()).is_equal(2)
	var reputation_before := ReputationManager.reputation
	var score_before := ScoreManager.total_score

	RegionalManager._demote()
	acknowledge_letters()
	# Closed, logged, and nothing lost for them.
	assert_bool(StaffReviewManager.queue.is_empty()).is_true()
	var closed := records_graded("Closed at demotion")
	assert_int(closed.size()).is_equal(2)
	assert_str(closed[0].description).contains("Derek Voss")
	assert_str(closed[1].description).contains("Walter Higgins")
	assert_int(ReputationManager.reputation).is_equal(reputation_before)
	assert_int(ScoreManager.total_score).is_equal(score_before)

	# Promoted again: the first clock-out has nothing from before to answer for.
	XPManager._grant_branch_manager()
	acknowledge_letters()
	set_clock(3, 12, 0)
	bm_clock_in()
	bm_clock_out()
	assert_int(records_graded("Ignored").size()).is_equal(1)
	assert_int(RegionalManager.serious_waiting()).is_equal(0)
	assert_int(RegionalManager.serious_ignored).is_equal(0)

# --- the visit -------------------------------------------------------------------------

func test_the_regional_manager_visits_on_review_day() -> void:
	promote()
	# Not on an ordinary day.
	set_clock(5, 10, 0)
	await frames(2)
	assert_object(room.regional_visitor).is_null()

	# Review day: nobody before mid-morning.
	set_clock(6, 9, 59)
	await frames(2)
	assert_object(room.regional_visitor).is_null()
	set_clock(6, 10, 0)
	await frames(1)
	var visitor := room.regional_visitor
	assert_object(visitor).is_not_null()
	assert_str((visitor.get_node("NameLabel") as Label).text).is_equal("Regional Manager")
	var sprite: AnimatedSprite2D = visitor.get_node("AnimatedSprite2D")
	assert_str(sprite.sprite_frames.resource_path).is_equal(StaffLooks.frames_path(StaffLooks.REGIONAL_MANAGER_LOOK))
	assert_bool(visitor.global_position.distance_to(TellerRoom.VISIT_ENTRANCE) < 8.0).is_true()

	# Walks in and stands outside the Manager's Office, facing it.
	Engine.time_scale = 4.0
	var waited := 0
	while visitor.state == StaffNPC.State.WALKING and waited < 600:
		await get_tree().physics_frame
		waited += 1
	await get_tree().physics_frame # standing still from here
	assert_vector(visitor.global_position).is_equal(TellerRoom.VISIT_ROUTE[-1])
	assert_str(sprite.animation).is_equal("idle_up")
	assert_str((visitor.get_node("SpeechLabel") as Label).text).is_equal(TellerRoom.VISIT_GREETING)
	assert_object(room.regional_visitor).is_same(visitor)

	# 11:30: walks back out and is gone, and doesn't come back that day.
	set_clock(6, 11, 30)
	waited = 0
	while is_instance_valid(visitor) and waited < 600:
		await get_tree().physics_frame
		waited += 1
	Engine.time_scale = 1.0
	assert_bool(is_instance_valid(visitor)).is_false()
	assert_object(room.regional_visitor).is_null()
	set_clock(6, 10, 30)
	await frames(2)
	assert_object(room.regional_visitor).is_null()

func test_a_visit_already_under_way_and_going_home() -> void:
	promote()
	# A room that comes into a visit part-way finds them standing there.
	set_clock(6, 10, 45)
	await frames(1)
	assert_vector(room.regional_visitor.global_position).is_equal(TellerRoom.VISIT_ROUTE[-1])
	# Going home ends the visit along with the day.
	var visitor := room.regional_visitor
	room._on_exit_door_interacted()
	eod.go_home_button.pressed.emit()
	assert_object(room.regional_visitor).is_null()
	await frames(1)
	assert_bool(is_instance_valid(visitor)).is_false()

# --- HUD ------------------------------------------------------------------------------

func test_hud_shows_the_next_review_and_warnings() -> void:
	room.hud.refresh()
	assert_bool(room.hud.regional_label.visible).is_false()
	promote()
	RegionalManager.warnings = 1
	room.hud.refresh()
	assert_bool(room.hud.regional_label.visible).is_true()
	assert_str(room.hud.regional_label.text).is_equal("Next review: Day 6 · Warnings 1/3")
	# It takes the place of "Reports: n/a (manager)".
	assert_bool(room.hud.reports_label.visible).is_false()
	RegionalManager._demote()
	acknowledge_letters()
	room.hud.refresh()
	assert_bool(room.hud.regional_label.visible).is_false()
	assert_bool(room.hud.reports_label.visible).is_true()

# --- save, load and reset --------------------------------------------------------------

func test_save_and_load_keep_the_review() -> void:
	promote()
	set_clock(4, 12, 0)
	RegionalManager.warnings = 2
	RegionalManager.note_vault_result(Vault.MINOR)
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
	RegionalManager.hire_verdicts.assign([HiringManager.Verdict.RED_FLAG])
	get_tree().paused = true # hold the clock and the vacancy count still
	var saved := RegionalManager.save_data()
	var evaluation := RegionalManager.evaluate()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_dict(RegionalManager.save_data()).is_not_equal(saved)
	SaveGame.restore(SaveGame.read().career)
	assert_dict(RegionalManager.save_data()).is_equal(saved)
	assert_dict(RegionalManager.evaluate()).is_equal(evaluation)
	assert_str(RegionalManager.status_text()).is_equal("Next review: Day 6 · Warnings 2/3")

	# The demotion's XP target too.
	get_tree().paused = false
	XPManager.total_xp = 1700
	RegionalManager._demote()
	acknowledge_letters()
	get_tree().paused = true
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_int(XPManager.repromotion_xp_target).is_equal(2200)
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_int(RegionalManager.next_review_day()).is_equal(0)

func test_a_branch_manager_from_an_older_save_gets_a_review_window() -> void:
	SaveGame.restore({"xp": {"total_xp": 1600, "is_loan_officer_unlocked": true, "is_branch_manager_unlocked": true}, "clock": {"day": 9, "minutes": 600.0}})
	assert_int(RegionalManager.next_review_day()).is_equal(14)
	assert_int(RegionalManager.warnings).is_equal(0)

func test_career_reset_clears_the_review() -> void:
	promote()
	RegionalManager.warnings = 2
	RegionalManager.staff_work = 12
	RegionalManager.note_vault_result(Vault.PERFECT)
	XPManager.repromotion_xp_target = 2500
	CareerReset.reset_all()
	assert_int(RegionalManager.warnings).is_equal(0)
	assert_int(RegionalManager.window_first_day).is_equal(0)
	assert_int(RegionalManager.staff_work).is_equal(0)
	assert_bool(RegionalManager.vault_by_day.is_empty()).is_true()
	assert_int(XPManager.repromotion_xp_target).is_equal(0)
	assert_str(RegionalManager.status_text()).is_equal("")
