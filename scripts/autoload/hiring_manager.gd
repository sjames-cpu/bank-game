extends Node

## Autoload singleton — the Branch Manager hires staff for empty desks (NPC
## coworkers, step 5). Same in-memory pattern as StaffReviewManager, saved
## with the career (save_data()/load_data(), see SaveGame).
##
## - Vacancies: once the player is Branch Manager, every desk with nobody
##   assigned (a terminated staff member's, or one left empty on the
##   schedule) is a vacancy (ScheduleManager.vacant_slots()).
## - Candidates: CANDIDATES_PER_VACANCY per vacancy, for that desk's role,
##   generated the first time the vacancy is looked at and at each Branch
##   Manager clock-in (begin_shift()). One is strong, one average and one has
##   a weakness in the stat that matters most at the desk (a teller's
##   reliability, a loan officer's skill) that only shows in their interview
##   answers; their order is shuffled. Names come from StaffCandidatesData.
##   They're ranked by StaffCandidate.rating(), which reads only the stats
##   the desk's formulas use.
## - Interview: QUESTIONS_PER_INTERVIEW questions from the player's own
##   interview (InterviewQuestionsData), the same for all of a vacancy's
##   candidates, with at least one that has an instant-reject answer. Each
##   candidate's answers are picked from their hidden stats (pick_answer())
##   when they're generated; the manager reveals them one question at a time
##   (ask_next_question()) and sees only the questions and answers.
## - Decision: hire() one candidate, graded against the other two
##   (grade()), or reject_all(), which leaves the desk empty until new
##   candidates arrive at the next clock-in.
##
## Hired staff join ScheduleManager's roster (ScheduleManager.hire_staff())
## and work with the same formulas as everyone else (StaffMember).

signal candidates_changed
## After every hire, with hire()'s result.
signal staff_hired(result: Dictionary)

enum Verdict { BEST, MIDDLE, WEAKEST, RED_FLAG }

const CANDIDATES_PER_VACANCY: int = 3
const QUESTIONS_PER_INTERVIEW: int = 3

## Points for the manager (proposed 2026-10-14). A hire is one judgment like a
## staff review (StaffReviewManager: +3 fair call, -3 / -1 unfair report)
## but a bigger, longer-lasting one, so roughly double, and below an
## Approvals override's +/-5 only for the middle and weakest picks. XP
## follows Score (x10) for positive Score only, as in staff review.
const BEST_HIRE_SCORE: int = 6
const BEST_HIRE_REPUTATION: int = 1
const MIDDLE_HIRE_SCORE: int = 1
const MIDDLE_HIRE_REPUTATION: int = 0
const WEAKEST_HIRE_SCORE: int = -4
const WEAKEST_HIRE_REPUTATION: int = -1
## Hiring someone who gave an instant-reject answer, whatever their stats.
const RED_FLAG_HIRE_SCORE: int = -6
const RED_FLAG_HIRE_REPUTATION: int = -2

## Hidden stat ranges for the three candidate profiles (1-10, like the
## roster). The ranges are chosen so role ratings never overlap: strong >= 7,
## average 5-6, weak <= 3.5 (StaffCandidate.rating()).
const STRONG_STAT_RANGE: Vector2i = Vector2i(7, 9)
const AVERAGE_STAT_RANGE: Vector2i = Vector2i(5, 6)
## The weak candidate's weakness is the stat that matters most at the desk:
## a teller's reliability (StaffMember.mistake_chance() takes the weaker of
## skill and reliability), a loan officer's skill
## (StaffMember.loan_correct_chance()). The other of the two looks fine
## (WEAK_COVER_RANGE); speed and customer service are below average.
const WEAKNESS_RANGE: Vector2i = Vector2i(1, 2)
const WEAK_COVER_RANGE: Vector2i = Vector2i(5, 7)
const WEAK_OTHER_RANGE: Vector2i = Vector2i(3, 5)

## Answer choice: a candidate's answer_aptitude() plus up to +/-ANSWER_NOISE
## picks the best answer at BEST_ANSWER_APTITUDE or above, the second-best
## at SECOND_ANSWER_APTITUDE or above, otherwise the third-best (instant-
## reject answers aside; a question with fewer answers uses its last one).
const ANSWER_NOISE: float = 1.0
const BEST_ANSWER_APTITUDE: float = 7.0
const SECOND_ANSWER_APTITUDE: float = 4.5
## At or below this reliability a candidate may give a question's
## instant-reject answer, with RED_FLAG_CHANCE per question that has one.
const RED_FLAG_RELIABILITY: int = 2
const RED_FLAG_CHANCE: float = 0.5

## slot name -> Array[StaffCandidate], for vacancies that have candidates.
var candidates: Dictionary = {}

## Vacancies whose candidates were all rejected this shift: no new ones
## until the next clock-in (begin_shift()).
var rejected_slots: Array[String] = []

func reset() -> void:
	candidates.clear()
	rejected_slots.clear()
	candidates_changed.emit()

# --- vacancies and candidates ---------------------------------------------------

## The vacant desks, once the player is Branch Manager; none before.
func vacancies() -> Array[String]:
	if not XPManager.is_branch_manager_unlocked:
		return []
	return ScheduleManager.vacant_slots()

## Whether a hire for `slot_name` is allowed right now: it's a vacancy and
## the roster has room.
func can_hire(slot_name: String) -> bool:
	return vacancies().has(slot_name) and ScheduleManager.has_room_to_hire()

## The candidates for vacancy `slot_name`, generated if it has none yet.
## Empty if it isn't a vacancy, the roster is full, or this shift's
## candidates were rejected.
func candidates_for(slot_name: String) -> Array[StaffCandidate]:
	_drop_filled_vacancies()
	if not can_hire(slot_name) or rejected_slots.has(slot_name):
		return []
	if not candidates.has(slot_name):
		candidates[slot_name] = generate_candidates(ScheduleManager.role_for_slot(slot_name))
		candidates_changed.emit()
	var list: Array[StaffCandidate] = candidates[slot_name]
	return list

## Branch Manager clock-in: rejected vacancies get new candidates, and every
## vacancy has candidates waiting.
func begin_shift() -> void:
	rejected_slots.clear()
	for slot_name in vacancies():
		candidates_for(slot_name)

## Candidates for a desk that has been filled some other way (e.g. by
## scheduling) are no longer needed.
func _drop_filled_vacancies() -> void:
	var vacant := vacancies()
	for slot_name: String in candidates.keys():
		if not vacant.has(slot_name):
			candidates.erase(slot_name)
	for slot_name: String in rejected_slots.duplicate():
		if not vacant.has(slot_name):
			rejected_slots.erase(slot_name)

## CANDIDATES_PER_VACANCY candidates for `role`, one per profile, in random
## order, with distinct new names and one shared set of questions.
func generate_candidates(role: String) -> Array[StaffCandidate]:
	var questions := pick_questions()
	var names := _available_names()
	names.shuffle()
	var backgrounds := StaffCandidatesData.backgrounds_for(role).duplicate()
	backgrounds.shuffle()
	var generated: Array[StaffCandidate] = []
	for profile: String in ["strong", "average", "weak"]:
		var candidate := StaffCandidate.new()
		candidate.role = role
		if names.is_empty():
			candidate.staff_name = "Applicant %d" % (generated.size() + 1)
		else:
			candidate.staff_name = names.pop_back()
		candidate.background = backgrounds[generated.size() % backgrounds.size()]
		_roll_stats(candidate, profile)
		candidate.question_indices = questions
		var answers: PackedInt32Array = []
		for index in questions:
			answers.append(pick_answer(InterviewQuestionsData.get_questions()[index], candidate))
		candidate.answer_indices = answers
		generated.append(candidate)
	generated.shuffle()
	return generated

func _roll_stats(candidate: StaffCandidate, profile: String) -> void:
	match profile:
		"strong":
			candidate.skill = _roll(STRONG_STAT_RANGE)
			candidate.reliability = _roll(STRONG_STAT_RANGE)
			candidate.speed = _roll(STRONG_STAT_RANGE)
			candidate.customer_service = _roll(STRONG_STAT_RANGE)
		"average":
			candidate.skill = _roll(AVERAGE_STAT_RANGE)
			candidate.reliability = _roll(AVERAGE_STAT_RANGE)
			candidate.speed = _roll(AVERAGE_STAT_RANGE)
			candidate.customer_service = _roll(AVERAGE_STAT_RANGE)
		_:
			if candidate.role == "Loan Officer":
				candidate.skill = _roll(WEAKNESS_RANGE)
				candidate.reliability = _roll(WEAK_COVER_RANGE)
			else:
				candidate.skill = _roll(WEAK_COVER_RANGE)
				candidate.reliability = _roll(WEAKNESS_RANGE)
			candidate.speed = _roll(WEAK_OTHER_RANGE)
			candidate.customer_service = _roll(WEAK_OTHER_RANGE)

func _roll(stat_range: Vector2i) -> int:
	return randi_range(stat_range.x, stat_range.y)

## Candidate-pool names not used by any roster member (past or present) or
## any waiting candidate.
func _available_names() -> Array[String]:
	var taken: Array[String] = []
	for list: Array[StaffCandidate] in candidates.values():
		for candidate in list:
			taken.append(candidate.staff_name)
	var available: Array[String] = []
	for candidate_name in StaffCandidatesData.CANDIDATE_NAMES:
		if not taken.has(candidate_name) and not ScheduleManager.is_known_staff_name(candidate_name):
			available.append(candidate_name)
	return available

## QUESTIONS_PER_INTERVIEW distinct question indices, at least one of them a
## question with an instant-reject answer (so a red flag can show).
func pick_questions() -> PackedInt32Array:
	var questions := InterviewQuestionsData.get_questions()
	var with_red_flag: Array[int] = []
	var others: Array[int] = []
	for i in questions.size():
		if _has_instant_reject(questions[i]):
			with_red_flag.append(i)
		else:
			others.append(i)
	with_red_flag.shuffle()
	var chosen: Array[int] = []
	if not with_red_flag.is_empty():
		var first: int = with_red_flag.pop_back()
		chosen.append(first)
	var rest: Array[int] = with_red_flag.duplicate()
	rest.append_array(others)
	rest.shuffle()
	while chosen.size() < mini(QUESTIONS_PER_INTERVIEW, questions.size()):
		var index: int = rest.pop_back()
		chosen.append(index)
	chosen.sort()
	return PackedInt32Array(chosen)

func _has_instant_reject(question: InterviewQuestion) -> bool:
	for answer in question.answers:
		if answer.is_instant_reject:
			return true
	return false

## The answer index `candidate` gives to `question` (see the constants).
func pick_answer(question: InterviewQuestion, candidate: StaffCandidate) -> int:
	var ranked: Array[int] = []
	var red_flags: Array[int] = []
	for i in question.answers.size():
		if question.answers[i].is_instant_reject:
			red_flags.append(i)
		else:
			ranked.append(i)
	if candidate.reliability <= RED_FLAG_RELIABILITY and not red_flags.is_empty() and randf() < RED_FLAG_CHANCE:
		return red_flags[0]
	ranked.sort_custom(func(a: int, b: int) -> bool: return question.answers[a].score > question.answers[b].score)
	var aptitude := candidate.answer_aptitude() + randf_range(-ANSWER_NOISE, ANSWER_NOISE)
	var rank := 2
	if aptitude >= BEST_ANSWER_APTITUDE:
		rank = 0
	elif aptitude >= SECOND_ANSWER_APTITUDE:
		rank = 1
	return ranked[mini(rank, ranked.size() - 1)]

# --- interview -------------------------------------------------------------------

## Reveals `candidate`'s next answer. False once all questions are asked.
func ask_next_question(candidate: StaffCandidate) -> bool:
	if candidate.is_interview_finished():
		return false
	candidate.questions_asked += 1
	candidates_changed.emit()
	return true

# --- decisions -------------------------------------------------------------------

## How hiring `candidate` from `field` (the vacancy's candidates) rates: a
## red-flag answer first, then by rating among the three.
func grade(candidate: StaffCandidate, field: Array[StaffCandidate]) -> Verdict:
	if candidate.red_flag_answer() != null:
		return Verdict.RED_FLAG
	var better := 0
	var worse := 0
	for other in field:
		if other.rating() > candidate.rating():
			better += 1
		elif other.rating() < candidate.rating():
			worse += 1
	if better == 0:
		return Verdict.BEST
	if worse == 0:
		return Verdict.WEAKEST
	return Verdict.MIDDLE

func score_for(verdict: Verdict) -> int:
	match verdict:
		Verdict.BEST:
			return BEST_HIRE_SCORE
		Verdict.MIDDLE:
			return MIDDLE_HIRE_SCORE
		Verdict.WEAKEST:
			return WEAKEST_HIRE_SCORE
		_:
			return RED_FLAG_HIRE_SCORE

func reputation_for(verdict: Verdict) -> int:
	match verdict:
		Verdict.BEST:
			return BEST_HIRE_REPUTATION
		Verdict.MIDDLE:
			return MIDDLE_HIRE_REPUTATION
		Verdict.WEAKEST:
			return WEAKEST_HIRE_REPUTATION
		_:
			return RED_FLAG_HIRE_REPUTATION

## The manager's feedback after a hire, naming what the answers showed and
## what it means at this desk (the same role ranking as grade()).
func feedback_for(verdict: Verdict, candidate: StaffCandidate, field: Array[StaffCandidate]) -> String:
	var lending := candidate.role == "Loan Officer"
	match verdict:
		Verdict.BEST:
			if lending:
				return "Good hire — their answers showed strong judgment, and they'll make sound loan decisions at a good pace."
			return "Good hire — their answers showed strong judgment, and they'll be quick and careful at the window."
		Verdict.MIDDLE:
			var desk := "the Loan Desk" if lending else "the window"
			for other in field:
				if grade(other, field) == Verdict.BEST:
					return "Fair hire — sensible answers, but %s was the stronger candidate for %s." % [other.staff_name, desk]
			return "Fair hire — sensible answers, but there was a stronger candidate for %s." % desk
		Verdict.WEAKEST:
			if lending:
				return "Weak hire — their answers showed the poorest judgment of the three. Expect weaker loan decisions."
			return "Weak hire — theirs were the least careful answers of the three. Expect more slips at the window."
		_:
			return "Risky hire — they said: \"%s\"" % candidate.red_flag_answer().text

## Hires `candidate` for vacancy `slot_name`: they join the roster at that
## desk (whose line then opens), the manager is scored, and the vacancy's
## candidates are cleared. Returns {verdict, score, reputation, xp, feedback,
## member, slot}, or {} if the hire isn't allowed (not a vacancy, roster
## full, or not one of this vacancy's candidates).
func hire(slot_name: String, candidate: StaffCandidate) -> Dictionary:
	var field := candidates_for(slot_name)
	if not field.has(candidate):
		return {}
	var member := candidate.to_staff_member()
	if not ScheduleManager.hire_staff(member, slot_name):
		return {}
	var verdict := grade(candidate, field)
	var score := score_for(verdict)
	var reputation := reputation_for(verdict)
	var feedback := feedback_for(verdict, candidate, field)
	candidates.erase(slot_name)
	if score != 0:
		ScoreManager.add_shift_score(score)
	if reputation != 0:
		ReputationManager.add_reputation(reputation)
	var xp := 0
	if score > 0:
		XPManager.add_shift_xp(score)
		xp = score * XPManager.XP_PER_SCORE_POINT
	HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER,
		"Hired %s (%s) for %s — %s" % [member.staff_name, member.role, slot_name, feedback],
		verdict_label(verdict)
	)
	candidates_changed.emit()
	var result := {
		"verdict": verdict,
		"score": score,
		"reputation": reputation,
		"xp": xp,
		"feedback": feedback,
		"member": member,
		"slot": slot_name,
	}
	staff_hired.emit(result)
	return result

## Turns down every candidate for `slot_name`; new ones come at the next
## clock-in. No points either way.
func reject_all(slot_name: String) -> void:
	if not candidates.has(slot_name):
		return
	candidates.erase(slot_name)
	if not rejected_slots.has(slot_name):
		rejected_slots.append(slot_name)
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Rejected every candidate for %s" % slot_name, "Rejected")
	candidates_changed.emit()

func verdict_label(verdict: Verdict) -> String:
	match verdict:
		Verdict.BEST:
			return "Good hire"
		Verdict.MIDDLE:
			return "Fair hire"
		Verdict.WEAKEST:
			return "Weak hire"
		_:
			return "Risky hire"

# --- save and load ---------------------------------------------------------------

func save_data() -> Dictionary:
	var saved := {}
	for slot_name: String in candidates:
		var list: Array[StaffCandidate] = candidates[slot_name]
		var entries: Array = []
		for candidate in list:
			entries.append(SaveGame.resource_to_dict(candidate))
		saved[slot_name] = entries
	return {"candidates": saved, "rejected_slots": rejected_slots.duplicate()}

## A vacancy's candidates load only as a complete, valid set (the right
## number, known questions and answers, progress in range); otherwise new
## ones are generated when the vacancy is next looked at. Loaded after
## ScheduleManager, so the desk slots are known.
func load_data(data: Dictionary) -> void:
	candidates.clear()
	rejected_slots.clear()
	var slot_names: Array[String] = []
	for slot in ScheduleManager.get_desk_slots():
		slot_names.append(slot["name"])
	# An old save's "Loan Desk" vacancy is Loan Desk 1's.
	var saved := {}
	var saved_candidates := SaveGame.dict_of(data, "candidates")
	for key: Variant in saved_candidates:
		if key is String:
			var saved_slot: String = key
			saved[ScheduleManager.current_slot_name(saved_slot)] = saved_candidates[saved_slot]
	for slot_name in slot_names:
		var list: Array[StaffCandidate] = []
		for entry in SaveGame.dicts_of(SaveGame.array_of(saved, slot_name)):
			var candidate := StaffCandidate.new()
			SaveGame.fill_resource(candidate, entry)
			if _is_valid(candidate):
				list.append(candidate)
		if list.size() == CANDIDATES_PER_VACANCY:
			candidates[slot_name] = list
	for saved_slot in SaveGame.strings_of(SaveGame.array_of(data, "rejected_slots")):
		var slot_name := ScheduleManager.current_slot_name(saved_slot)
		if slot_names.has(slot_name) and not rejected_slots.has(slot_name):
			rejected_slots.append(slot_name)
	candidates_changed.emit()

func _is_valid(candidate: StaffCandidate) -> bool:
	if candidate.staff_name == "" or candidate.question_indices.size() != candidate.answer_indices.size():
		return false
	if candidate.questions_asked < 0 or candidate.questions_asked > candidate.question_indices.size():
		return false
	var questions := InterviewQuestionsData.get_questions()
	for i in candidate.question_indices.size():
		var question_index := candidate.question_indices[i]
		if question_index < 0 or question_index >= questions.size():
			return false
		var answer_index := candidate.answer_indices[i]
		if answer_index < 0 or answer_index >= questions[question_index].answers.size():
			return false
	return true
