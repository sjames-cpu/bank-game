extends Resource
class_name StaffCandidate

## An applicant for a vacant desk (NPC coworkers, step 5; see HiringManager).
## Built in code, like the other data resources, and saved with the career.
##
## The four stats are hidden from the Branch Manager until the candidate is
## hired (HiringScreen never shows them before that): the manager judges only
## the background line and the interview answers. The answers are chosen when
## the candidate is generated (HiringManager.pick_answer()), so they're the
## same however often the manager re-reads them, and questions_asked is how
## far the interview has got.

@export var staff_name: String = ""
## "Teller" or "Loan Officer", the vacant desk's StaffMember.role.
@export var role: String = ""
## One line, e.g. "2 years at a credit union". Says nothing about the stats.
@export var background: String = ""

## Same 1-10 scale as StaffRosterData.
@export var skill: int = 5
@export var reliability: int = 5
@export var speed: int = 5
@export var customer_service: int = 5

## Indices into InterviewQuestionsData.get_questions(), and the answer
## index this candidate gives to each (same order).
@export var question_indices: PackedInt32Array = []
@export var answer_indices: PackedInt32Array = []
## Questions asked so far, 0 to question_indices.size().
@export var questions_asked: int = 0

## How well they'd work the vacant desk, from the stats its formulas use
## (StaffMember). A teller's mistakes come from the weaker of skill and
## reliability (mistake_chance()) and their service time from speed; a loan
## officer's decisions come from skill (loan_correct_chance()) and their pace
## from speed. Customer service drives neither. Hiring is graded by which of
## a vacancy's three candidates rates highest (HiringManager).
func rating() -> float:
	if role == "Loan Officer":
		return (skill + speed) / 2.0
	return (mini(skill, reliability) + speed) / 2.0

## The stats rating() reads for this role.
func role_stats() -> Array[int]:
	if role == "Loan Officer":
		return [skill, speed]
	return [skill, reliability, speed]

## How well this candidate answers interview questions: their rating()
## pulled down halfway towards their weakest role stat, so the weakness that
## matters at the desk shows in the answers (a weak teller's reliability, a
## weak loan officer's skill) even when their other stats look fine.
func answer_aptitude() -> float:
	var weakest: int = role_stats().min()
	return (rating() + weakest) / 2.0

func question(i: int) -> InterviewQuestion:
	return InterviewQuestionsData.get_questions()[question_indices[i]]

func answer(i: int) -> InterviewAnswer:
	return question(i).answers[answer_indices[i]]

## The first instant-reject answer this candidate gives, or null. Counts
## whether or not the manager has asked that question yet.
func red_flag_answer() -> InterviewAnswer:
	for i in question_indices.size():
		if answer(i).is_instant_reject:
			return answer(i)
	return null

func is_interview_finished() -> bool:
	return questions_asked >= question_indices.size()

## The staff member they become when hired, with their stats as they were
## and their background as the roster's flavor text.
func to_staff_member() -> StaffMember:
	var member := StaffMember.new()
	member.staff_name = staff_name
	member.role = role
	member.skill = skill
	member.reliability = reliability
	member.speed = speed
	member.customer_service = customer_service
	member.flavor_text = background
	return member
