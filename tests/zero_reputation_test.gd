extends "res://tests/support/teller_room_suite.gd"

## Reputation falling to 0 (ReputationManager.reputation_reached_zero): a
## Teller or Loan Officer gets one disciplinary report, a Branch Manager one
## regional warning (a third one demotes at that day's End of Day). It fires
## once per fall and again only after Reputation has recovered above
## LOW_REPUTATION_THRESHOLD; that state is saved. The HUD's low-reputation
## warning stays.

const ZERO_REASON := ReportManager.ZERO_REPUTATION_REASON

var letters: DisciplineLetterScreen
var eod: EndOfDayScreen

func before_test() -> void:
	await super()
	letters = room.letter_screen
	eod = room.end_of_day_screen

# --- helpers -------------------------------------------------------------------

func acknowledge_letters() -> void:
	while letters.visible and letters.action_button.text == "Acknowledge":
		letters.action_button.pressed.emit()

func set_clock(day: int, hour: int, minute: int) -> void:
	GameClock.day = day
	GameClock.minutes = hour * 60.0 + minute
	BusinessDay.stats_day = day

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

## A Perfect vault count, then clock-out and the summary closed.
func bm_clock_out(bm: BranchManagerScreen) -> void:
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

func drop_to_zero() -> void:
	ReputationManager.add_reputation(-ReputationManager.reputation - 5)

# --- Teller and Loan Officer -------------------------------------------------------

func test_a_teller_gets_one_report_when_reputation_reaches_zero() -> void:
	ReputationManager.add_reputation(-49)
	assert_int(ReportManager.get_report_count()).is_equal(0)
	assert_bool(letters.visible).is_false()

	ReputationManager.add_reputation(-1)
	assert_int(ReputationManager.reputation).is_equal(0)
	assert_int(ReportManager.get_report_count()).is_equal(1)
	var report: DisciplinaryReport = ReportManager.reports[0]
	assert_str(report.reason).is_equal(ZERO_REASON)
	assert_int(report.role).is_equal(DecisionRecord.Role.TELLER)
	assert_bool(report.items.is_empty()).is_true()
	# The usual written-warning letter, with no customers to list.
	assert_bool(letters.visible).is_true()
	assert_str(letters.title_label.text).is_equal("Written Warning — Report 1 of 3")
	assert_str(letters.from_label.text).is_equal("From: " + DisciplineLetterScreen.BRANCH_MANAGER_SENDER)
	assert_str(letters.body_label.text).contains("issued because customer satisfaction has fallen to zero: your Reputation is 0 out of 100.")
	assert_str(letters.body_label.text).not_contains("Customers affected")
	assert_str(letters.body_label.text).contains("This is report 1 of 3.")
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).is_equal("Written warning 1/3 from the Branch Manager: " + ZERO_REASON)
	acknowledge_letters()
	# The low-reputation warning stays up as before.
	room.hud.refresh()
	assert_bool(room.hud.low_reputation_warning_label.visible).is_true()
	assert_str(room.hud.reports_label.text).is_equal("Reports: 1 / 3")

func test_a_loan_officer_gets_one_report_in_their_role() -> void:
	XPManager.is_loan_officer_unlocked = true
	drop_to_zero()
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_int(ReportManager.reports[0].role).is_equal(DecisionRecord.Role.LOAN_OFFICER)
	assert_str(letters.title_label.text).is_equal("Written Warning — Report 1 of 3")
	assert_int(RegionalManager.warnings).is_equal(0)

## It counts like any other report: on probation it restarts the clean-shift
## count, and the last one ends the career, its letter listing it.
func test_a_zero_reputation_report_can_end_the_career() -> void:
	InterviewManager.is_on_probation = true
	for i in ReportManager.MISTAKES_PER_REPORT:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Customer %d" % i)
	acknowledge_letters()
	drop_to_zero()
	assert_bool(ReportManager.is_terminated).is_true()
	assert_str(letters.title_label.text).is_equal("Notice of Termination")
	assert_str(letters.body_label.text).contains("Report 1 — Repeated transaction errors at the teller desk: Customer 0, Customer 1")
	assert_str(letters.body_label.text).contains("Report 2 — " + ZERO_REASON)

# --- the re-arm rule ----------------------------------------------------------------

func test_it_fires_once_until_reputation_recovers_above_the_threshold() -> void:
	drop_to_zero()
	acknowledge_letters()
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_bool(ReputationManager.zero_armed).is_false()

	# Still at 0, or knocked down again: nothing more.
	ReputationManager.add_reputation(-3)
	ReputationManager.add_reputation(0)
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_bool(letters.visible).is_false()
	# Back up to the threshold isn't recovered.
	ReputationManager.add_reputation(ReputationManager.LOW_REPUTATION_THRESHOLD)
	assert_bool(ReputationManager.zero_armed).is_false()

	# Above it, falling to 0 again counts again.
	ReputationManager.add_reputation(ReputationManager.LOW_REPUTATION_THRESHOLD + 1 - ReputationManager.reputation)
	assert_int(ReputationManager.reputation).is_equal(ReputationManager.LOW_REPUTATION_THRESHOLD + 1)
	assert_bool(ReputationManager.zero_armed).is_true()
	drop_to_zero()
	assert_int(ReportManager.get_report_count()).is_equal(2)
	assert_str(letters.title_label.text).is_equal("Written Warning — Report 2 of 3")

func test_career_reset_rearms() -> void:
	drop_to_zero()
	assert_bool(ReputationManager.zero_armed).is_false()
	CareerReset.reset_all()
	assert_bool(ReputationManager.zero_armed).is_true()

# --- Branch Manager -------------------------------------------------------------------

func test_a_branch_manager_gets_a_regional_warning_instead() -> void:
	promote()
	drop_to_zero()
	assert_int(RegionalManager.warnings).is_equal(1)
	assert_int(ReportManager.get_report_count()).is_equal(0)
	assert_str(letters.title_label.text).is_equal("Regional Warning — 1 of 3")
	assert_str(letters.from_label.text).is_equal("From: Regional Manager")
	assert_str(letters.body_label.text).contains("Customer satisfaction at your branch has fallen to zero")
	assert_str(letters.body_label.text).contains("Regional warnings: 1 of 3. At 3 you'll return to the Loan Officer role.")
	acknowledge_letters()
	room.hud.refresh()
	assert_str(room.hud.regional_label.text).contains("Warnings 1/3")
	assert_bool(room.hud.low_reputation_warning_label.visible).is_true()

	# Once per fall here too.
	ReputationManager.add_reputation(-2)
	assert_int(RegionalManager.warnings).is_equal(1)
	ReputationManager.add_reputation(ReputationManager.LOW_REPUTATION_THRESHOLD + 1)
	drop_to_zero()
	assert_int(RegionalManager.warnings).is_equal(2)

## A third warning this way demotes at the End of Day, not mid-shift: the
## demotion letter comes before the summary, and there's no review.
func test_a_third_regional_warning_demotes_at_the_end_of_day() -> void:
	promote()
	set_clock(3, 12, 0)
	RegionalManager.warnings = 2
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters() # the orientation
	drop_to_zero()
	assert_str(letters.title_label.text).is_equal("Regional Warning — 3 of 3")
	assert_str(letters.body_label.text).contains("That is the limit: at the end of today you'll return to the Loan Officer role.")
	acknowledge_letters()
	# Still the manager for the rest of the day.
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_bool(bm.is_clocked_in()).is_true()
	assert_bool(RegionalManager.is_demotion_due()).is_true()
	bm_clock_out(bm)
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()

	# Saved with the demotion due.
	var career := SaveGame.capture()
	SaveGame.restore(career)
	assert_int(RegionalManager.warnings).is_equal(3)
	assert_bool(RegionalManager.is_demotion_due()).is_true()
	var reviews_before := HistoryManager.records.filter(func(r: DecisionRecord) -> bool: return r.description.begins_with("Regional review")).size()

	set_clock(3, 17, 30)
	room.show_end_of_day()
	assert_str(letters.title_label.text).is_equal("Notice of Demotion")
	acknowledge_letters()
	for i in 2:
		await get_tree().process_frame
	assert_bool(eod.is_summary_shown()).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_int(RegionalManager.warnings).is_equal(0)
	assert_bool(RegionalManager.is_demotion_due()).is_false()
	assert_int(HistoryManager.records.filter(func(r: DecisionRecord) -> bool: return r.description.begins_with("Regional review")).size()).is_equal(reviews_before)

## An Unsatisfactory review's Reputation cost can be what reaches 0: its
## warning counts, and the review demotes at once if that makes three.
func test_a_review_that_empties_reputation_can_demote() -> void:
	promote()
	RegionalManager.warnings = 1
	ReputationManager.reputation = 3
	set_clock(6, 17, 30)
	var result := RegionalManager.run_review() # no vault counts: Unsatisfactory
	assert_int(result["rating"]).is_equal(RegionalManager.Rating.UNSATISFACTORY)
	assert_int(ReputationManager.reputation).is_equal(0)
	assert_bool(result["demoted"]).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_str(letters.title_label.text).is_equal("Regional Warning — 3 of 3")
	letters.action_button.pressed.emit()
	assert_str(letters.title_label.text).starts_with("Branch Manager Review")
	letters.action_button.pressed.emit()
	assert_str(letters.title_label.text).is_equal("Notice of Demotion")
	acknowledge_letters()
	# Demoted, still at 0: no report for the same fall.
	assert_int(ReportManager.get_report_count()).is_equal(0)

# --- save and load ------------------------------------------------------------------

func test_the_rearm_state_is_saved_and_loaded() -> void:
	drop_to_zero()
	acknowledge_letters()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_bool(ReputationManager.zero_armed).is_true()
	SaveGame.restore(SaveGame.read().career)
	assert_int(ReputationManager.reputation).is_equal(0)
	assert_bool(ReputationManager.zero_armed).is_false()
	assert_int(ReportManager.get_report_count()).is_equal(1)
	# Loaded at 0 without having recovered: no second report.
	ReputationManager.add_reputation(-1)
	assert_int(ReportManager.get_report_count()).is_equal(1)

	# Recovered, saved armed, loaded armed.
	ReputationManager.add_reputation(20)
	assert_bool(SaveGame.save()).is_true()
	SaveGame.restore(SaveGame.read().career)
	assert_bool(ReputationManager.zero_armed).is_true()
	assert_bool(SaveGame.dict_of(SaveGame.read().career, "reputation")["zero_armed"]).is_true()
	drop_to_zero()
	assert_int(ReportManager.get_report_count()).is_equal(2)

## Saves from before the re-arm state: armed unless saved at 0.
func test_older_saves_default_the_rearm_state() -> void:
	ReputationManager.load_data({"reputation": 30})
	assert_bool(ReputationManager.zero_armed).is_true()
	ReputationManager.load_data({"reputation": 0})
	assert_bool(ReputationManager.zero_armed).is_false()
	ReputationManager.load_data({"reputation": 0, "zero_armed": "yes"})
	assert_bool(ReputationManager.zero_armed).is_false()
