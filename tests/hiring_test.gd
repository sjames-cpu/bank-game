extends "res://tests/support/teller_room_suite.gd"

## NPC coworkers, step 5: the Branch Manager interviews and hires staff for
## vacant desks (HiringManager, HiringScreen, branch_manager_screen.gd).

const Verdict := HiringManager.Verdict

var letters: DisciplineLetterScreen
var bm: BranchManagerScreen
var hiring: HiringScreen

func before_test() -> void:
	await super()
	letters = room.get_node("UI/DisciplineLetterScreen")
	bm = room.branch_manager_screen
	hiring = bm.hiring_screen

# --- helpers -------------------------------------------------------------------

func acknowledge_letters() -> void:
	while letters.visible:
		letters.action_button.pressed.emit()

## Branch Manager, clocked in at the hub (letters clicked away).
func promote_and_clock_in() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()

## Leaves `slot_name` empty on the schedule, as the manager could.
func vacate(slot_name: String) -> void:
	var new_schedule := ScheduleManager.schedule.duplicate()
	new_schedule.erase(slot_name)
	ScheduleManager.confirm_schedule(new_schedule)

func candidate(skill: int, reliability: int, speed: int, customer_service: int, role: String = "Teller") -> StaffCandidate:
	var made := StaffCandidate.new()
	made.staff_name = "Test %d%d%d%d" % [skill, reliability, speed, customer_service]
	made.role = role
	made.skill = skill
	made.reliability = reliability
	made.speed = speed
	made.customer_service = customer_service
	return made

## Every visible label's text under `node`.
func visible_text(node: Node) -> String:
	var text := ""
	for child in node.find_children("*", "Label", true, false):
		var label := child as Label
		if label.is_visible_in_tree():
			text += label.text + "\n"
	for child in node.find_children("*", "Button", true, false):
		var button := child as Button
		if button.is_visible_in_tree():
			text += button.text + "\n"
	return text

func roster_member(staff_name: String) -> StaffMember:
	for member in ScheduleManager.get_roster():
		if member.staff_name == staff_name:
			return member
	return null

func open_hiring() -> void:
	bm.hire_staff_button.pressed.emit()
	assert_bool(hiring.visible).is_true()

## The vacancy's candidate with the given verdict.
func candidate_with(slot_name: String, verdict: Verdict) -> StaffCandidate:
	var field := HiringManager.candidates_for(slot_name)
	for each in field:
		if HiringManager.grade(each, field) == verdict:
			return each
	return null

# --- vacancies and the button --------------------------------------------------

func test_hire_button_appears_only_with_a_vacancy() -> void:
	# Not a manager: no vacancies, even with an empty desk.
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_array(HiringManager.vacancies()).is_empty()

	ScheduleManager.reset()
	promote_and_clock_in()
	# Every desk staffed (Teller Window 3 too): nothing to hire for.
	assert_array(ScheduleManager.vacant_slots()).is_empty()
	bm._show_main_panel()
	assert_bool(bm.hire_staff_button.visible).is_false()

	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	bm._show_main_panel()
	assert_bool(bm.hire_staff_button.visible).is_true()
	assert_bool(bm.hire_staff_button.disabled).is_false()
	assert_str(bm.hire_staff_button.text).is_equal("Hire Staff — Teller Window 2, Loan Desk 1")

	# Off shift it shows, but can't be used.
	bm._prepare_shift_summary()
	assert_bool(bm.hire_staff_button.visible).is_true()
	assert_bool(bm.hire_staff_button.disabled).is_true()

func test_a_terminated_staff_members_desk_is_a_vacancy() -> void:
	promote_and_clock_in()
	var slot := ScheduleManager.slot_of("Derek Voss")
	StaffReviewManager.staff_reports["Derek Voss"] = PackedStringArray(["a", "b", "c"])
	assert_bool(StaffReviewManager.terminate("Derek Voss")).is_true()
	acknowledge_letters()
	assert_array(HiringManager.vacancies()).contains_exactly([slot])
	bm._show_main_panel()
	assert_str(bm.hire_staff_button.text).contains(slot)

# --- candidates ------------------------------------------------------------------

func test_candidates_match_the_role_and_differ() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	var taken: Array[String] = []
	for slot_name: String in [ScheduleManager.SLOT_TELLER_WINDOW_2, ScheduleManager.SLOT_LOAN_DESK_1]:
		var field := HiringManager.candidates_for(slot_name)
		assert_int(field.size()).is_equal(HiringManager.CANDIDATES_PER_VACANCY)
		var ratings: Array[float] = []
		var lending := slot_name == ScheduleManager.SLOT_LOAN_DESK_1
		for each in field:
			assert_str(each.role).is_equal(ScheduleManager.role_for_slot(slot_name))
			assert_bool(StaffCandidatesData.CANDIDATE_NAMES.has(each.staff_name)).is_true()
			assert_bool(CustomerQueue.CUSTOMER_NAMES.has(each.staff_name)).is_false()
			assert_bool(ScheduleManager.is_known_staff_name(each.staff_name)).is_false()
			assert_bool(taken.has(each.staff_name)).is_false()
			taken.append(each.staff_name)
			assert_str(each.background).is_not_empty()
			assert_bool(StaffCandidatesData.backgrounds_for(each.role).has(each.background)).is_true()
			for stat: int in [each.skill, each.reliability, each.speed, each.customer_service]:
				assert_int(stat).is_between(1, 10)
			ratings.append(each.rating())
			# Same questions for the whole field, at least one with a red flag.
			assert_array(Array(each.question_indices)).is_equal(Array(field[0].question_indices))
			assert_int(each.question_indices.size()).is_equal(HiringManager.QUESTIONS_PER_INTERVIEW)
		ratings.sort()
		# Strong >= 7, average 5-6, weak <= 3.5 on the desk's own stats.
		assert_float(ratings[0]).is_less_equal(3.5)
		assert_float(ratings[1]).is_between(5.0, 6.0)
		assert_float(ratings[2]).is_greater_equal(7.0)

		var weak := candidate_with(slot_name, Verdict.WEAKEST)
		if weak == null:
			weak = candidate_with(slot_name, Verdict.RED_FLAG)
		var weak_member := weak.to_staff_member()
		var strong_member := candidate_with(slot_name, Verdict.BEST).to_staff_member()
		if lending:
			# Weak where the loan formula looks: skill. Reliability looks fine.
			assert_int(weak.skill).is_less_equal(2)
			assert_int(weak.reliability).is_greater_equal(5)
			assert_float(weak_member.loan_correct_chance()).is_less(strong_member.loan_correct_chance())
			assert_float(weak_member.loan_decision_seconds()).is_greater(strong_member.loan_decision_seconds())
		else:
			# Weak where the teller formula looks: reliability. Skill looks fine.
			assert_int(weak.reliability).is_less_equal(HiringManager.RED_FLAG_RELIABILITY)
			assert_int(weak.skill).is_greater_equal(5)
			assert_float(weak_member.mistake_chance()).is_greater(strong_member.mistake_chance())
			assert_float(weak_member.service_seconds()).is_greater(strong_member.service_seconds())
		var has_red_flag_question := false
		for i in field[0].question_indices.size():
			has_red_flag_question = has_red_flag_question or HiringManager._has_instant_reject(field[0].question(i))
		assert_bool(has_red_flag_question).is_true()

func test_answers_track_hidden_stats() -> void:
	_check_answers_track_stats({"strong": candidate(8, 8, 8, 8), "average": candidate(5, 6, 5, 6), "weak": candidate(6, 2, 4, 4)})
	# A weak loan officer (low skill, fine reliability) shows it too.
	_check_answers_track_stats({"strong": candidate(8, 8, 8, 8, "Loan Officer"), "average": candidate(5, 6, 5, 6, "Loan Officer"), "weak": candidate(2, 7, 4, 4, "Loan Officer")})
	# Only the desk's stats count: a loan candidate's reliability doesn't
	# change their answers, a teller candidate's does.
	assert_float(candidate(8, 2, 8, 8, "Loan Officer").answer_aptitude()).is_equal(candidate(8, 9, 8, 8, "Loan Officer").answer_aptitude())
	assert_float(candidate(8, 2, 8, 8).answer_aptitude()).is_less(candidate(8, 9, 8, 8).answer_aptitude())

## Average answer score falls from strong to average to weak, and the strong
## candidate gives the best answer to every question.
func _check_answers_track_stats(profiles: Dictionary) -> void:
	var questions := InterviewQuestionsData.get_questions()
	var averages := {}
	for profile: String in profiles:
		var who: StaffCandidate = profiles[profile]
		var total := 0
		var count := 0
		for trial in 30:
			for question in questions:
				total += question.answers[HiringManager.pick_answer(question, who)].score
				count += 1
		averages[profile] = float(total) / count
	var strong_average: float = averages["strong"]
	var middle_average: float = averages["average"]
	var weak_average: float = averages["weak"]
	assert_float(strong_average).is_greater(middle_average)
	assert_float(middle_average).is_greater(weak_average)
	# A strong candidate gives the best answer to every question.
	var strong: StaffCandidate = profiles["strong"]
	for question in questions:
		var best := -999
		for answer in question.answers:
			best = maxi(best, answer.score)
		assert_int(question.answers[HiringManager.pick_answer(question, strong)].score).is_equal(best)

func test_red_flags_only_come_from_low_reliability() -> void:
	var questions := InterviewQuestionsData.get_questions()
	var red_flags := 0
	for trial in 20:
		for question in questions:
			if question.answers[HiringManager.pick_answer(question, candidate(7, 1, 5, 5))].is_instant_reject:
				red_flags += 1
			assert_bool(question.answers[HiringManager.pick_answer(question, candidate(1, 3, 1, 1))].is_instant_reject).is_false()
			assert_bool(question.answers[HiringManager.pick_answer(question, candidate(9, 9, 9, 9))].is_instant_reject).is_false()
	assert_int(red_flags).is_greater(0)
	# And generated fields produce them: some weak candidate shows one.
	promote_and_clock_in()
	var shown := 0
	for trial in 20:
		for each in HiringManager.generate_candidates("Teller"):
			if each.red_flag_answer() != null:
				assert_int(each.reliability).is_less_equal(HiringManager.RED_FLAG_RELIABILITY)
				shown += 1
	assert_int(shown).is_greater(0)

# --- the screen ------------------------------------------------------------------

func test_interview_shows_answers_but_never_stats() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	bm._show_main_panel()
	open_hiring()
	var field := hiring.current_candidates()
	assert_int(hiring.candidates_hbox.get_child_count()).is_equal(3)

	# Interview all three, every question.
	for i in field.size():
		hiring.select_candidate(i)
		assert_str(hiring.transcript_label.text).is_equal("Not interviewed yet.")
		for q in HiringManager.QUESTIONS_PER_INTERVIEW:
			hiring.ask_button.pressed.emit()
		assert_bool(hiring.ask_button.disabled).is_true()
		var each := field[i]
		for q in HiringManager.QUESTIONS_PER_INTERVIEW:
			assert_str(hiring.transcript_label.text).contains(each.question(q).question_text)
			assert_str(hiring.transcript_label.text).contains(each.answer(q).text)
		var shown := visible_text(hiring)
		for word: String in ["Skill", "Reliability", "Speed", "Customer Service", "Score", "XP"]:
			assert_str(shown).not_contains(word)
		assert_str(shown).contains(each.background)
	assert_int(field[0].questions_asked).is_equal(HiringManager.QUESTIONS_PER_INTERVIEW)

	# Hiring reveals the stats on the card.
	hiring.select_candidate(0)
	var hired := field[0]
	hiring.hire_button.pressed.emit()
	assert_bool(hiring.hired_card.visible).is_true()
	assert_str(hiring.hired_label.text).contains("Hired: %s" % hired.staff_name)
	assert_str(hiring.hired_label.text).contains("Skill %d · Reliability %d · Speed %d · Customer Service %d" % [hired.skill, hired.reliability, hired.speed, hired.customer_service])
	assert_str(hiring.feedback_label.text).contains(HiringManager.feedback_for(HiringManager.grade(hired, field), hired, field))

func test_hiring_fills_the_desk_and_the_line_serves_customers() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_bool(room.window2_line.active).is_false()
	var hired := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)[1]
	var result := HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, hired)
	assert_dict(result).is_not_empty()

	var member := ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_str(member.staff_name).is_equal(hired.staff_name)
	assert_int(member.reliability).is_equal(hired.reliability)
	assert_bool(ScheduleManager.get_roster().has(member)).is_true()
	assert_array(HiringManager.vacancies()).is_empty()
	assert_bool(HiringManager.candidates.has(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_false()
	assert_str(room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_2].staff.staff_name).is_equal(hired.staff_name)
	assert_bool(room.window2_line.active).is_true()

	# They serve customers like anyone else.
	bm.hide_screen()
	var served := [0]
	room.window2_line.customer_served.connect(func(_c: CustomerNPC, staff: StaffMember, _m: bool) -> void:
		if staff.staff_name == hired.staff_name:
			served[0] += 1)
	Engine.time_scale = 8.0
	var frames := 0
	while served[0] < 2 and frames < 3000:
		await get_tree().physics_frame
		frames += 1
	assert_int(served[0]).is_greater_equal(2)
	var records := HistoryManager.records.filter(func(r: DecisionRecord) -> bool: return r.staff_name == hired.staff_name)
	assert_int(records.size()).is_greater_equal(2)

## Over many decisions at the real Loan Desk, the weakest hire of a field
## (low skill) gets far fewer right than the best one.
func test_a_weak_loan_hire_makes_worse_loan_decisions() -> void:
	promote_and_clock_in()
	bm.hide_screen()
	var rates := {}
	for verdict: Verdict in [Verdict.WEAKEST, Verdict.BEST]:
		vacate(ScheduleManager.SLOT_LOAN_DESK_1)
		var pick := candidate_with(ScheduleManager.SLOT_LOAN_DESK_1, verdict)
		assert_object(pick).is_not_null()
		var result := HiringManager.hire(ScheduleManager.SLOT_LOAN_DESK_1, pick)
		assert_int(result["verdict"]).is_equal(verdict)
		# The feedback speaks to the Loan Desk.
		assert_str(result["feedback"]).contains("loan decisions")
		var worker := room.loan_desk_worker
		assert_str(worker.staff_npc.staff.staff_name).is_equal(pick.staff_name)
		var correct := [0]
		var on_decision := func(_application: LoanApplication, _staff: StaffMember, right: bool) -> void:
			if right:
				correct[0] += 1
		worker.decision_made.connect(on_decision)
		var decisions := 300
		for i in decisions:
			worker.decide_next()
		worker.decision_made.disconnect(on_decision)
		var correct_count: int = correct[0]
		rates[verdict] = float(correct_count) / decisions
		ScheduleManager.dismiss_staff(pick.staff_name)
	var weak_rate: float = rates[Verdict.WEAKEST]
	var strong_rate: float = rates[Verdict.BEST]
	# Skill 1-2 vs 7-9: roughly 15% vs 80% right.
	assert_float(weak_rate).is_less(0.3)
	assert_float(strong_rate).is_greater(0.6)
	assert_float(strong_rate - weak_rate).is_greater(0.4)

func test_a_loan_desk_hire_works_the_loan_desk() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	var hired := HiringManager.candidates_for(ScheduleManager.SLOT_LOAN_DESK_1)[0]
	assert_str(hired.role).is_equal("Loan Officer")
	assert_dict(HiringManager.hire(ScheduleManager.SLOT_LOAN_DESK_1, hired)).is_not_empty()
	assert_str(room.loan_desk_worker.staff_npc.staff.staff_name).is_equal(hired.staff_name)

# --- scoring ----------------------------------------------------------------------

func test_scoring_table() -> void:
	assert_int(HiringManager.score_for(Verdict.BEST)).is_equal(6)
	assert_int(HiringManager.reputation_for(Verdict.BEST)).is_equal(1)
	assert_int(HiringManager.score_for(Verdict.MIDDLE)).is_equal(1)
	assert_int(HiringManager.reputation_for(Verdict.MIDDLE)).is_equal(0)
	assert_int(HiringManager.score_for(Verdict.WEAKEST)).is_equal(-4)
	assert_int(HiringManager.reputation_for(Verdict.WEAKEST)).is_equal(-1)
	assert_int(HiringManager.score_for(Verdict.RED_FLAG)).is_equal(-6)
	assert_int(HiringManager.reputation_for(Verdict.RED_FLAG)).is_equal(-2)

	# Applied for real, one hire per verdict, each against a fresh field.
	promote_and_clock_in()
	var questions := InterviewQuestionsData.get_questions()
	var red_flag_question := -1
	var red_flag_answer := -1
	for q in questions.size():
		for i in questions[q].answers.size():
			if red_flag_question == -1 and questions[q].answers[i].is_instant_reject:
				red_flag_question = q
				red_flag_answer = i
	var expected := {
		Verdict.BEST: [6, 1, 60, "Good hire — their answers showed strong judgment, and they'll be quick and careful at the window."],
		Verdict.MIDDLE: [1, 0, 10, "Fair hire — sensible answers, but"],
		Verdict.WEAKEST: [-4, -1, 0, "Weak hire — theirs were the least careful answers of the three. Expect more slips at the window."],
		Verdict.RED_FLAG: [-6, -2, 0, "Risky hire — they said: \"%s\"" % InterviewQuestionsData.get_questions()[red_flag_question].answers[red_flag_answer].text],
	}
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	for verdict: Verdict in expected:
		var field := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
		var pick: StaffCandidate
		if verdict == Verdict.RED_FLAG:
			# The weakest, made to give the red-flag answer.
			pick = candidate_with(ScheduleManager.SLOT_TELLER_WINDOW_2, Verdict.WEAKEST)
			if pick == null:
				pick = candidate_with(ScheduleManager.SLOT_TELLER_WINDOW_2, Verdict.RED_FLAG)
			pick.question_indices = PackedInt32Array([red_flag_question])
			pick.answer_indices = PackedInt32Array([red_flag_answer])
		else:
			# Clean answers, so only the ranking decides.
			for each in field:
				each.question_indices = PackedInt32Array([0])
				each.answer_indices = PackedInt32Array([0])
			pick = candidate_with(ScheduleManager.SLOT_TELLER_WINDOW_2, verdict)
		var totals_before := totals()
		var result := HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, pick)
		var want: Array = expected[verdict]
		assert_int(result["verdict"]).is_equal(verdict)
		assert_int(result["score"]).is_equal(want[0])
		assert_int(result["reputation"]).is_equal(want[1])
		assert_int(result["xp"]).is_equal(want[2])
		var feedback_start: String = want[3]
		assert_str(result["feedback"]).starts_with(feedback_start)
		var totals_after := totals()
		assert_int(totals_after.x - totals_before.x).is_equal(want[0])
		assert_int(totals_after.y - totals_before.y).is_equal(want[1])
		assert_int(totals_after.z - totals_before.z).is_equal(want[2])
		var record: DecisionRecord = HistoryManager.records[-1]
		assert_int(record.role).is_equal(DecisionRecord.Role.BRANCH_MANAGER)
		assert_str(record.grade_label).is_equal(HiringManager.verdict_label(verdict))
		# Let them go again, so the roster stays below its maximum and the
		# desk is vacant for the next round.
		ScheduleManager.dismiss_staff(pick.staff_name)

func test_hire_points_reach_the_shift_summary() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	bm._show_main_panel()
	open_hiring()
	var pick := candidate_with(ScheduleManager.SLOT_TELLER_WINDOW_2, Verdict.BEST)
	hiring.select_candidate(hiring.current_candidates().find(pick))
	hiring.hire_button.pressed.emit()
	assert_int(bm.shift_score_total).is_equal(HiringManager.BEST_HIRE_SCORE)
	assert_int(bm.actions_completed).is_equal(1)
	hiring.close_button.pressed.emit()
	assert_bool(bm.main_panel.visible).is_true()
	assert_bool(bm.hire_staff_button.visible).is_false()

# --- limits --------------------------------------------------------------------------

func test_only_vacancies_can_be_filled() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	var field := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
	# A staffed desk has no candidates and takes no hire.
	assert_array(HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_1)).is_empty()
	assert_dict(HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_1, field[0])).is_empty()
	assert_bool(ScheduleManager.hire_staff(field[0].to_staff_member(), ScheduleManager.SLOT_TELLER_WINDOW_1)).is_false()
	# Filling the vacancy from the schedule drops its candidates.
	var refilled := ScheduleManager.schedule.duplicate()
	refilled[ScheduleManager.SLOT_TELLER_WINDOW_2] = roster_member("Walter Higgins")
	ScheduleManager.confirm_schedule(refilled)
	assert_array(HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_empty()
	assert_bool(HiringManager.candidates.has(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_false()
	assert_int(ScheduleManager.hired_staff.size()).is_equal(0)

func test_roster_stops_at_its_maximum() -> void:
	promote_and_clock_in()
	# Fill the roster to the maximum with hires, freeing a desk for each.
	while ScheduleManager.has_room_to_hire():
		vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
		var field := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
		assert_dict(HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, field[0])).is_not_empty()
	assert_int(ScheduleManager.get_roster().size()).is_equal(ScheduleManager.MAX_ROSTER_SIZE)

	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_array(HiringManager.vacancies()).contains([ScheduleManager.SLOT_TELLER_WINDOW_2])
	assert_bool(HiringManager.can_hire(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_false()
	assert_array(HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_empty()
	bm._show_main_panel()
	open_hiring()
	assert_str(hiring.message_label.text).contains("most it can employ")
	assert_bool(hiring.actions_hbox.visible).is_false()

# --- reject all ------------------------------------------------------------------------

func test_reject_all_brings_new_candidates_next_clock_in() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	bm._show_main_panel()
	open_hiring()
	var first_names: Array[String] = []
	for each in hiring.current_candidates():
		first_names.append(each.staff_name)
	var score_before := ScoreManager.total_score
	hiring.reject_all_button.pressed.emit()
	assert_int(ScoreManager.total_score).is_equal(score_before)
	assert_bool(hiring.actions_hbox.visible).is_false()
	assert_str(hiring.message_label.text).contains("next clock-in")
	assert_array(HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_empty()
	# Still a vacancy; the button stays.
	hiring.close_button.pressed.emit()
	assert_bool(bm.hire_staff_button.visible).is_true()

	# Same shift, reopening: still nobody.
	open_hiring()
	assert_bool(hiring.actions_hbox.visible).is_false()
	hiring.close_button.pressed.emit()

	# Next shift: a new field.
	bm._prepare_shift_summary()
	bm.clock_in_button.pressed.emit()
	# Generated at clock-in, before anyone opens the screen.
	assert_bool(HiringManager.candidates.has(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_true()
	var field := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_int(field.size()).is_equal(HiringManager.CANDIDATES_PER_VACANCY)
	var same := 0
	for each in field:
		if first_names.has(each.staff_name):
			same += 1
	assert_int(same).is_less(HiringManager.CANDIDATES_PER_VACANCY)
	assert_int(field[0].questions_asked).is_equal(0)

# --- career reset and save/load ------------------------------------------------------------

func test_career_reset_restores_the_original_roster() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)[0])
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	HiringManager.candidates_for(ScheduleManager.SLOT_LOAN_DESK_1)
	CareerReset.reset_all()
	assert_int(ScheduleManager.hired_staff.size()).is_equal(0)
	assert_int(ScheduleManager.get_roster().size()).is_equal(StaffRosterData.get_staff().size())
	assert_dict(HiringManager.candidates).is_empty()
	assert_array(HiringManager.rejected_slots).is_empty()

func test_hiring_round_trips_through_a_save() -> void:
	promote_and_clock_in()
	# A hire, a vacancy with candidates part-way through their interviews,
	# and a rejected vacancy.
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	var hired := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)[2]
	HiringManager.hire(ScheduleManager.SLOT_TELLER_WINDOW_2, hired)
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	var field := HiringManager.candidates_for(ScheduleManager.SLOT_LOAN_DESK_1)
	HiringManager.ask_next_question(field[0])
	HiringManager.ask_next_question(field[0])
	HiringManager.ask_next_question(field[1])
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_3)
	HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_3)
	HiringManager.reject_all(ScheduleManager.SLOT_TELLER_WINDOW_3)

	var saved_career := SaveGame.capture()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_dict(SaveGame.capture()).is_equal(saved_career)

	assert_str(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).staff_name).is_equal(hired.staff_name)
	assert_int(ScheduleManager.get_assigned(ScheduleManager.SLOT_TELLER_WINDOW_2).speed).is_equal(hired.speed)
	var loaded: Array[StaffCandidate] = HiringManager.candidates[ScheduleManager.SLOT_LOAN_DESK_1]
	assert_int(loaded.size()).is_equal(3)
	assert_str(loaded[0].staff_name).is_equal(field[0].staff_name)
	assert_int(loaded[0].questions_asked).is_equal(2)
	assert_int(loaded[1].questions_asked).is_equal(1)
	assert_int(loaded[0].reliability).is_equal(field[0].reliability)
	assert_array(Array(loaded[0].answer_indices)).is_equal(Array(field[0].answer_indices))
	assert_array(HiringManager.rejected_slots).contains_exactly([ScheduleManager.SLOT_TELLER_WINDOW_3])

	# In a fresh room the hire is at their desk and their line is open.
	room.free()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	assert_str(room._staff_by_slot[ScheduleManager.SLOT_TELLER_WINDOW_2].staff.staff_name).is_equal(hired.staff_name)
	assert_bool(room.window2_line.active).is_true()

func test_damaged_candidates_are_dropped_on_load() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	var field := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
	var career := SaveGame.capture()
	var entries: Array = career["hiring"]["candidates"][ScheduleManager.SLOT_TELLER_WINDOW_2]
	var damaged: Dictionary = entries[0]
	damaged["answer_indices"] = [99, 0, 0]
	SaveGame.restore(career)
	assert_bool(HiringManager.candidates.has(ScheduleManager.SLOT_TELLER_WINDOW_2)).is_false()
	# A fresh field is generated when it's next looked at.
	var fresh := HiringManager.candidates_for(ScheduleManager.SLOT_TELLER_WINDOW_2)
	assert_int(fresh.size()).is_equal(3)
	assert_bool(fresh[0] == field[0]).is_false()

func test_hiring_screen_fits_the_window() -> void:
	promote_and_clock_in()
	vacate(ScheduleManager.SLOT_TELLER_WINDOW_2)
	vacate(ScheduleManager.SLOT_LOAN_DESK_1)
	bm._show_main_panel()
	assert_float(await settled_height(bm.main_panel)).is_less_equal(648.0)
	open_hiring()
	var panel: Control = hiring.get_node("Panel")
	for q in HiringManager.QUESTIONS_PER_INTERVIEW:
		hiring.ask_button.pressed.emit()
	assert_float(await settled_height(panel)).is_less_equal(648.0)
	hiring.hire_button.pressed.emit()
	assert_float(await settled_height(panel)).is_less_equal(648.0)
	# The card stands in for the next vacancy until Continue.
	assert_bool(hiring.candidate_section.visible).is_false()
	hiring.continue_button.pressed.emit()
	assert_bool(hiring.hired_card.visible).is_false()
	assert_str(hiring.current_vacancy()).is_equal(ScheduleManager.SLOT_LOAN_DESK_1)
	assert_bool(hiring.candidate_section.visible).is_true()
	assert_float(await settled_height(panel)).is_less_equal(648.0)
