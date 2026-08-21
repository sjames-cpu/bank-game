extends RefCounted
class_name InterviewQuestionsData

## Static provider for the interview mini-game's question set (2h).
## Kept separate from InterviewQuestion/InterviewAnswer (the data shape)
## so the actual question content can grow independently of it.

static func get_questions() -> Array[InterviewQuestion]:
	return [
		_question("Why do you want to work as a bank teller?", [
			_answer("I enjoy helping customers and I'm detail-oriented with numbers.", 3),
			_answer("I need a steady paycheck and this job was hiring.", 1),
			_answer("Banks keep a lot of cash around, so it seemed convenient.", -3),
		]),
		_question("A customer's drawer count comes up short at the end of your shift. What do you do?", [
			_answer("Report the discrepancy immediately and document exactly what happened.", 3),
			_answer("Recount everything to look for the error before reporting it.", 2),
			_answer("Cover the shortfall with my own cash so it doesn't show up as a discrepancy.", -2),
			_answer("Adjust the paperwork so the numbers match, no discrepancy needed.", -5, true),
		]),
		_question("A regular customer asks you to waive a fee as a personal favor, no questions asked. How do you respond?", [
			_answer("Explain the fee policy and that I can't waive it without authorization.", 3),
			_answer("Offer to check with a supervisor to see if an exception applies.", 2),
			_answer("Waive it since they're a good customer.", -2),
			_answer("Waive it, but tell them to keep it between us.", -3),
		]),
		_question("A customer is yelling at you over a mistake that wasn't your fault. How do you respond?", [
			_answer("Stay calm, listen fully, and work toward a resolution.", 3),
			_answer("Apologize for the inconvenience and bring in a manager if it escalates.", 2),
			_answer("Match their tone so they know I won't be pushed around.", -3),
			_answer("Tell them to calm down or take their business elsewhere.", -2),
		]),
		_question("You notice a coworker pocketing cash from their own drawer. What do you do?", [
			_answer("Report it to a manager.", 3),
			_answer("Talk to them directly first, then report it if it happens again.", 1),
			_answer("Stay out of it — it's not my drawer.", -2),
			_answer("Ask them to cut me in since I already noticed.", -5, true),
		]),
		_question("Tell me about a time you made a mistake at a previous job. How did you handle it?", [
			_answer("I owned up to it, fixed what I could, and changed my process going forward.", 3),
			_answer("I quietly fixed it without telling anyone.", -1),
			_answer("I don't think I've made a mistake worth mentioning.", 0),
		]),
		_question("How do you stay accurate when counting large amounts of cash quickly?", [
			_answer("I count carefully and double-check every time, even under pressure.", 3),
			_answer("I use consistent habits — same denomination order, same stacking — every count.", 2),
			_answer("I estimate when I'm fairly confident; it's usually close enough.", -2),
			_answer("Speed matters more than being exact down to the dollar.", -3),
		]),
		_question("This job sometimes means telling a customer \"no\" — for example, declining a withdrawal that would overdraw their account. How do you feel about that?", [
			_answer("That's part of the job — I'd explain the policy clearly and offer alternatives.", 3),
			_answer("I'd do it, even though I don't love confrontation.", 1),
			_answer("I'd probably approve it anyway and hope it works out.", -3),
		]),
		_question("Do you have any questions for us?", [
			_answer("Yes — what does a typical growth path look like for a teller here?", 2),
			_answer("No, I think you've covered everything I wanted to know.", 0),
			_answer("Not really, I just need a job.", -1),
			_answer("Are you even qualified to be interviewing me?", -5, true),
		]),
	]

static func _question(text: String, answers: Array[InterviewAnswer]) -> InterviewQuestion:
	var question := InterviewQuestion.new()
	question.question_text = text
	question.answers = answers
	return question

static func _answer(text: String, score: int, is_instant_reject: bool = false) -> InterviewAnswer:
	var answer := InterviewAnswer.new()
	answer.text = text
	answer.score = score
	answer.is_instant_reject = is_instant_reject
	return answer
