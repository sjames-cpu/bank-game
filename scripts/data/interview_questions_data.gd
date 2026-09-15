extends RefCounted
class_name InterviewQuestionsData

## Static provider for the interview mini-game's question set (2h).
## Kept separate from InterviewQuestion/InterviewAnswer (the data shape)
## so the actual question content can grow independently of it.

static func get_questions() -> Array[InterviewQuestion]:
	return [
		_question("Why do you want to work as a bank teller?", [
			_answer("I like the mix of customer service and detail-oriented work — I'm careful with numbers and enjoy helping people manage their money.", 3),
			_answer("I need steady, reliable work, and this role fits my schedule.", 1),
			_answer("Handling that much cash every day could come in handy if I ever needed extra money.", -5, true),
		]),
		_question("It's the end of a long line, and a customer who has been waiting a while is clearly frustrated. They're in a hurry and need an urgent deposit made before a deadline. How do you handle it?", [
			_answer("I'd acknowledge that the wait has been frustrating, apologize for that specifically, and get their deposit processed as quickly as I can.", 3),
			_answer("I'd apologize for the inconvenience and ask them to bear with me.", 1),
			_answer("I'd explain that we're short-staffed today, so there's not much I can do about the wait.", -2),
			_answer("People who come in acting like that don't really deserve to be rushed to the front.", -5, true),
		]),
		_question("A customer hands you a deposit slip that's missing information and an unsigned check, and asks you to just process it since they're in a hurry and will \"fix it later.\" What do you do?", [
			_answer("I'd explain I'm not able to process it as-is, and help them fill in the missing information and sign the check right there so it only takes a minute.", 3),
			_answer("I'd tell them to come back once everything is filled out and signed.", 1),
			_answer("I'd process it now and follow up with them next time they're in to get it corrected.", -2),
			_answer("I'd just sign the check myself so they're not held up.", -5, true),
		]),
		_question("You notice a coworker made an error with a customer's transaction. What do you do?", [
			_answer("Let my supervisor know what I saw so it can get corrected and looked into properly.", 3),
			_answer("Mention it to the coworker privately and see if they report it themselves.", 2),
			_answer("Stay out of it — it's not my drawer or my problem.", -2),
			_answer("Call it out in front of the customer so it's clear it wasn't my mistake.", -3),
		]),
		_question("You realize you made a mistake that negatively affected a customer's account. How do you react?", [
			_answer("Tell the customer right away, explain what happened and how I'll fix it, and report it to my supervisor.", 3),
			_answer("Quietly correct it myself without mentioning it to anyone.", -1),
			_answer("Wait to see if the customer or anyone else notices before saying anything.", -2),
			_answer("Explain to the customer that they must have made the error, not me.", -5, true),
		]),
		_question("A customer asks you to waive a fee or bend a bank policy as a personal favor. How do you respond?", [
			_answer("Explain the policy and why it's in place, and check with a supervisor if there's a legitimate exception available.", 3),
			_answer("Politely decline and explain I'm not able to make exceptions to policy.", 2),
			_answer("Go ahead and make the exception since it seems harmless.", -2),
			_answer("Make the exception, but ask them not to mention it to anyone.", -5, true),
		]),
		_question("In your view, what are the most important qualities of a bank teller?", [
			_answer("Accuracy and attention to detail, patience with customers, and clear communication — small mistakes can have a real impact on someone's money.", 3),
			_answer("Being fast, friendly, and good with people.", 1),
			_answer("I haven't really thought about it.", -1),
		]),
		_question("How do you stay focused and accurate during repetitive tasks, like counting cash or processing routine transactions?", [
			_answer("I follow the same consistent process every time — same order, same checks — regardless of how routine it feels, so I don't get complacent.", 3),
			_answer("I try to pay attention, though it can be hard to stay sharp some days.", 1),
			_answer("Tasks like that are simple enough to do without thinking too much about them.", -2),
		]),
		_question("How do you make sure you're protecting customer confidentiality when handling their account information?", [
			_answer("I only discuss account details with the verified account holder, keep documents and screens out of view of others, and never share information outside of work.", 3),
			_answer("I'm generally careful, but I might mention details to a coworker if it seems relevant to the situation.", -2),
			_answer("I don't see the harm in mentioning basic account details to friends or family if it comes up.", -3),
		]),
		_question("Why do anti-money-laundering (AML) rules and reporting requirements matter in a teller's role?", [
			_answer("Tellers are often the first to notice unusual patterns, like structuring deposits to avoid reporting thresholds — flagging that helps prevent the bank from being used for financial crime.", 3),
			_answer("They're mostly paperwork I follow because compliance requires it.", 0),
			_answer("As long as a transaction looks normal on the surface, it's not really my place to question it.", -2),
			_answer("If a customer asked me to split up a large deposit to stay under the reporting limit, I'd help them out since it's their money.", -5, true),
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
