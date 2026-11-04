extends "res://tests/support/teller_room_suite.gd"

## The career's loan applicants in the room (LoanDeskManager): the first Loan
## Officer shift works the three teaching cases, clear to borderline, then
## every application is generated; an application closed undecided stays on
## top; staff desks draw generated applicants too; no name repeats within a
## business day; and the pile (pending and queued) survives a save, with the
## career's generator carrying on exactly where it left off.

var lo: LoanOfficerScreen
var review: LoanReviewScreen

func before_test() -> void:
	await super()
	lo = room.loan_officer_screen
	review = lo.loan_review_screen

# --- helpers -------------------------------------------------------------------

func sample_names() -> Array[String]:
	var names: Array[String] = []
	for application in LoanApplicationsData.get_applications():
		names.append(application.applicant_name)
	return names

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

## Opens the next application, runs the credit check and makes the right
## call for it (a counter-offer at what they can afford, below the request,
## as a staff officer would; a denial naming up to two real weak points).
## Returns it.
func decide_next_correctly() -> LoanApplication:
	lo.review_next_button.pressed.emit()
	var application := review.current_application()
	review.run_credit_check_button.pressed.emit()
	match application.correct_decision():
		LoanApplication.DecisionType.APPROVE:
			review.approve_button.pressed.emit()
		LoanApplication.DecisionType.COUNTER_OFFER:
			review.counter_offer_button.pressed.emit()
			review.counter_offer_amount_spinbox.value = NpcLoanDeskWorker._decision_amount(application, LoanApplication.DecisionType.COUNTER_OFFER)
			review.submit_counter_offer_button.pressed.emit()
		_:
			review.reject_button.pressed.emit()
			var weak := application.weak_points()
			for i in mini(2, weak.size()):
				review.reason_checks[weak[i]].button_pressed = true
			review.submit_denial_button.pressed.emit()
	review.close_button.pressed.emit()
	return application

func clock_out_at_loan_desk() -> void:
	lo.clock_out_button.pressed.emit()
	assert_bool(lo.is_clocked_in()).is_false()
	lo.shift_summary_done_button.pressed.emit()

# --- the first shift ------------------------------------------------------------

func test_the_first_shift_works_the_teaching_cases_then_applicants_are_generated() -> void:
	clock_in_at_loan_desk()
	var tiers: Array[LoanApplication.RiskTier] = []
	var start := totals()
	for expected in LoanApplicationsData.TEACHING_CASE_NAMES:
		var application := decide_next_correctly()
		assert_str(application.applicant_name).is_equal(expected)
		# Their portrait is shown.
		assert_object(review.applicant_portrait.texture).is_same(CustomerNPC.portrait_of(application.applicant_look))
		tiers.append(application.risk_assessment)
		assert_str(review.decision_status_label.text).contains("Correct call")
	# Clear to borderline: a safe loan, a risky one, then a counter-offer.
	assert_array(tiers).is_equal([LoanApplication.RiskTier.LOW, LoanApplication.RiskTier.HIGH, LoanApplication.RiskTier.MEDIUM])
	assert_int((totals() - start).x).is_greater(0)
	clock_out_at_loan_desk()

	# Every shift after that: generated applicants, built for the tier the
	# worksheet gives them.
	var names := sample_names()
	for shift in 3:
		lo.clock_in_button.pressed.emit()
		for i in LoanOfficerScreen.APPLICATIONS_PER_SHIFT:
			var application := decide_next_correctly()
			assert_bool(names.has(application.applicant_name)).override_failure_message(application.applicant_name).is_false()
			assert_int(application.calculate_risk_assessment()).is_equal(application.risk_tier)
			assert_str(review.decision_status_label.text).contains("Correct call")
		clock_out_at_loan_desk()

## A new career always starts on the teaching cases, even after another
## career has worked past them.
func test_a_new_career_starts_on_the_teaching_cases_again() -> void:
	clock_in_at_loan_desk()
	for i in 3:
		decide_next_correctly()
	assert_bool(sample_names().has(LoanDeskManager.player_queue[0].applicant_name)).is_false()
	CareerReset.reset_all()
	var names: Array[String] = []
	for application in LoanDeskManager.player_queue:
		names.append(application.applicant_name)
	assert_array(names).is_equal(LoanApplicationsData.TEACHING_CASE_NAMES)

func test_an_application_closed_undecided_stays_on_top() -> void:
	clock_in_at_loan_desk()
	lo.review_next_button.pressed.emit()
	var first := review.current_application()
	review.run_credit_check_button.pressed.emit()
	review.close_button.pressed.emit()
	assert_int(lo.applications_reviewed).is_equal(0)
	lo.review_next_button.pressed.emit()
	assert_object(review.current_application()).is_same(first)
	# Shown fresh: the credit check to run again.
	assert_bool(review.run_credit_check_button.visible).is_true()
	assert_bool(review.decision_hbox.visible).is_false()
	assert_int(LoanDeskManager.player_queue.size()).is_equal(LoanOfficerScreen.APPLICATIONS_PER_SHIFT)

# --- staff desks and names -----------------------------------------------------------

## The staff desks decide generated applicants, and nobody, player or staff,
## sees a name twice in a business day. The next day names may come round
## again, but never one waiting in the player's pile.
func test_no_name_repeats_within_a_business_day() -> void:
	var seen := {}
	var on_decision := func(application: LoanApplication, _staff: StaffMember, _correct: bool) -> void:
		assert_bool(seen.has(application.applicant_name)).override_failure_message("%s twice on Day %d" % [application.applicant_name, GameClock.day]).is_false()
		seen[application.applicant_name] = true
	for worker in room.loan_desk_workers:
		worker.decision_made.connect(on_decision)
	var samples := sample_names()
	for day in 3:
		seen.clear()
		# The pile's names are today's too once they're on the desk.
		for application in LoanDeskManager.player_queue:
			seen[application.applicant_name] = true
		# A busy day: far more applicants than three desks decide.
		for i in 80:
			for worker in room.loan_desk_workers:
				worker.decide_next()
		assert_int(seen.size()).is_equal(80 * room.loan_desk_workers.size() + LoanDeskManager.player_queue.size())
		for staff_name: String in seen:
			if not LoanApplicationsData.TEACHING_CASE_NAMES.has(staff_name):
				assert_bool(samples.has(staff_name)).is_false()
		GameClock.day += 1

func test_applicants_come_from_the_careers_seed() -> void:
	var seed_value := LoanDeskManager.career_seed
	var first: Array[Dictionary] = []
	for i in 5:
		first.append(SaveGame.resource_to_dict(LoanDeskManager.generate_application()))
	# The same seed from the start gives the same applicants...
	LoanDeskManager.reset()
	LoanDeskManager.career_seed = seed_value
	for i in 5:
		assert_dict(SaveGame.resource_to_dict(LoanDeskManager.generate_application())).is_equal(first[i])
	# ...and another career's seed others.
	LoanDeskManager.reset()
	assert_int(LoanDeskManager.career_seed).is_not_equal(seed_value)
	var different := 0
	for i in 5:
		if SaveGame.resource_to_dict(LoanDeskManager.generate_application()) != first[i]:
			different += 1
	assert_int(different).is_equal(5)

# --- save and load ------------------------------------------------------------------

## The pending application and those queued are saved; after loading, the
## pending one is back on top, the queue follows in order, and the career's
## generator carries on with the same applicants it would have made.
func test_the_pile_survives_save_and_load() -> void:
	clock_in_at_loan_desk()
	for i in 3:
		decide_next_correctly()
	# One generated application opened and closed undecided: pending.
	lo.review_next_button.pressed.emit()
	var pending := review.current_application()
	review.close_button.pressed.emit()
	# The staff desks have drawn a few too.
	for i in 4:
		room.loan_desk_worker.decide_next()
	var saved_pile: Array[Dictionary] = []
	for application in LoanDeskManager.player_queue:
		saved_pile.append(SaveGame.resource_to_dict(application))
	var saved_state := LoanDeskManager.save_data()
	assert_bool(SaveGame.save()).is_true()
	# What comes next without loading.
	var next_without_load := SaveGame.resource_to_dict(LoanDeskManager.generate_application())

	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(LoanDeskManager.save_data()).is_equal(saved_state)
	var loaded_pile: Array[Dictionary] = []
	for application in LoanDeskManager.player_queue:
		loaded_pile.append(SaveGame.resource_to_dict(application))
	assert_array(loaded_pile).is_equal(saved_pile)
	assert_str(LoanDeskManager.player_queue[0].applicant_name).is_equal(pending.applicant_name)
	assert_dict(SaveGame.resource_to_dict(LoanDeskManager.generate_application())).is_equal(next_without_load)

	# Loaded into a fresh room, the desk opens on the pending application.
	room.free()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	lo = room.loan_officer_screen
	review = lo.loan_review_screen
	clock_in_at_loan_desk()
	lo.review_next_button.pressed.emit()
	assert_str(review.current_application().applicant_name).is_equal(pending.applicant_name)
	assert_float(review.current_application().requested_amount).is_equal(pending.requested_amount)

## A save from before generated applicants: a career that hadn't reached
## Loan Officer still gets the teaching cases; one that had gets generated
## applicants.
func test_an_older_save_without_a_pile() -> void:
	SaveGame.restore({"xp": {"total_xp": 100}})
	assert_str(LoanDeskManager.player_queue[0].applicant_name).is_equal(LoanApplicationsData.TEACHING_CASE_NAMES[0])
	SaveGame.restore({"xp": {"total_xp": 600, "is_loan_officer_unlocked": true}})
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	assert_bool(LoanDeskManager.player_queue.is_empty()).is_true()
	var first := LoanDeskManager.current_player_application()
	assert_bool(sample_names().has(first.applicant_name)).is_false()
	assert_int(LoanDeskManager.player_queue.size()).is_equal(LoanOfficerScreen.APPLICATIONS_PER_SHIFT)
