extends RefCounted
class_name OnboardingData

## The onboarding at the start of every career (OnboardingManager): the
## background check letter, the employment contract and the four compliance
## training lessons. Presented as the bank's own policy, not as any law.
##
## Every figure comes from the constant the game grades with (the drawer
## limit, report limits, Reputation for complaints, the complaint replies
## themselves), so the training can't drift from the rules;
## onboarding_test.gd checks each quiz answer against them.

const SENDER: String = "Human Resources"

const BACKGROUND_CHECK_TITLE: String = "Background Check Cleared"
const CONTRACT_TITLE: String = "Employment Contract"
const AGREE_BUTTON_TEXT: String = "I agree"

## The complaint quizzed in the last lesson (CustomerComplaintsData).
const QUIZ_COMPLAINT: String = "I've been waiting forever, this is unacceptable."

static func background_check_body() -> String:
	return "Welcome to the branch.\n\nYour background check has cleared: your identity, employment history and references have been verified, as bank policy requires for everyone who handles customer cash.\n\nNext comes your employment contract, then a short compliance training before your first shift."

## The contract for the career as it stands: a Teller, on probation or not.
static func contract_body() -> String:
	var limit := ReportManager.report_limit()
	var lines: PackedStringArray = [
		"Position: Teller, at the Player Teller Window.",
		"Hours: the branch is open 9:00 AM to 5:00 PM on business days. You may clock in from 8:30 AM for the opening drawer count, and not after 4:30 PM.",
	]
	if InterviewManager.is_on_probation:
		lines.append("Probation: you are hired on probation. While it lasts, %d reports end your employment instead of the usual %d. %d teller shifts in a row without a report complete it." % [
			InterviewManager.PROBATION_REPORTS_FOR_TERMINATION, ReportManager.REPORTS_FOR_TERMINATION, InterviewManager.PROBATION_CLEAN_SHIFTS,
		])
	lines.append("Conduct: every %d customers served wrongly lead to a written warning (a report), and so does customer satisfaction (Reputation) falling to zero. Serving a customer on a bad ID counts as two mistakes at once." % ReportManager.MISTAKES_PER_REPORT)
	lines.append("Dismissal: %d reports end your employment with the branch." % limit)
	lines.append("By pressing \"%s\" you accept these terms." % AGREE_BUTTON_TEXT)
	return "\n\n".join(lines)

static func lessons() -> Array[TrainingLesson]:
	return [_id_lesson(), _drawer_lesson(), _vault_lesson(), _privacy_lesson()]

static func _id_lesson() -> TrainingLesson:
	var lesson := _lesson("ID checks", "Bank policy: withdrawals (cash or card) and opening an account need a valid photo ID. Deposits don't.\nCheck the ID before you do anything else: the name must match the customer, the photo must be theirs, and it must not have expired.\nIf anything is wrong, or they have no ID, refuse service. Serving someone on a bad ID is a serious mistake; refusing a valid ID turns away a genuine customer.")
	lesson.questions = [
		_question("A customer wants to deposit $200 in cash. Do you need to see their ID?",
			["Yes, for every transaction", "No, deposits don't need ID", "Only for deposits over $100"], 1,
			"Deposits don't need ID. Withdrawals and new accounts do."),
		_question("A customer's ID expired last month, and they want to withdraw $100. What do you do?",
			["Withdraw it: the name and photo match", "Refuse service", "Withdraw half and ask them to come back"], 1,
			"An expired ID isn't valid ID, so refuse service. Serving on a bad ID is a serious mistake."),
	]
	return lesson

static func _drawer_lesson() -> TrainingLesson:
	var float_text := LoanApplication.dollars(TellerScreen.STARTING_FLOAT_CENTS / 100.0)
	var max_text := LoanApplication.dollars(TellerScreen.DRAWER_MAX_CENTS / 100.0)
	var min_text := LoanApplication.dollars(TellerScreen.DRAWER_MIN_CENTS / 100.0)
	var lesson := _lesson("Your drawer limit", "You start each shift with a %s float. Bank policy caps the cash in a teller drawer at %s, so less money is at risk; under %s is too little to serve customers.\nCard payments don't touch the drawer, but cash deposits build it up. When it's over the limit, take the excess to the vault door and send it to the vault.\nGoing over during a shift is only a warning. Clocking out over the limit is a procedure mistake." % [float_text, max_text, min_text])
	lesson.questions = [
		_question("What's the most cash a teller drawer may hold?",
			[float_text, max_text, "$5,000"], 1,
			"The limit is %s. %s is the float you start with." % [max_text, float_text]),
		_question("Your drawer reaches $3,600 in the middle of a shift. When must the excess go to the vault?",
			["At once: the shift stops until it's done", "Before you clock out", "At the end of the week"], 1,
			"Going over mid-shift is only a warning, but clocking out over the limit is a procedure mistake."),
	]
	return lesson

static func _vault_lesson() -> TrainingLesson:
	var key := InputPrompts.key_for(InputPrompts.INTERACT)
	var lesson := _lesson("Dual control at the vault", "Bank policy: nobody opens the vault alone. Every vault action (sending cash from your drawer, taking cash out, the manager's vault count) needs two people: you and one witness.\nWhile you're on shift, press %s at the vault door in the Vault room and a free coworker walks over to witness. If everyone is busy, the teller with the shortest line comes once they've finished their customer. Their window waits while they're with you, so be quick.\nIf no one is free, the vault stays shut until someone is." % key)
	lesson.questions = [
		_question("How many people must be at the vault for a transfer?",
			["Just you, if you're on shift", "Two: you and one witness", "Three: you, a witness and the manager"], 1,
			"Dual control means two people: you and one witness."),
		_question("No one is free to witness. What happens?",
			["You open the vault alone this once", "The vault stays shut until someone is free", "A customer can witness instead"], 1,
			"No vault action happens with one person. Wait until a coworker is free."),
	]
	return lesson

static func _privacy_lesson() -> TrainingLesson:
	var lesson := _lesson("Privacy and complaints", "Each customer's account is private. Use only the customer's own account, and never share one customer's details with another. A transaction on someone else's account is a mistake: reverse it, then do it on the right account.\nSome customers come with a complaint. Stay calm, acknowledge how they feel and offer to help: that wins back their trust (+%d Reputation). A purely procedural reply changes nothing; a dismissive or defensive one costs Reputation (%d)." % [best_complaint_score(), worst_complaint_score()])
	var replies := quiz_complaint_replies()
	lesson.questions = [
		_question("You did a withdrawal on the wrong customer's account. What do you do?",
			["Leave it: the amount was right", "Reverse it, then do it on the customer's own account", "Tell the customer whose account you used"], 1,
			"Only the customer's own account may be used. Reverse the mistake, do it on the right account, and keep the other customer's details private."),
		_question("A customer says: \"%s\" Which reply is best?" % QUIZ_COMPLAINT,
			[replies[0].text, replies[1].text, replies[2].text], 1,
			"Acknowledge the wait and help right away: a calm, apologetic reply wins back their trust."),
	]
	return lesson

## The quizzed complaint's replies: procedural, best, dismissive (the quiz
## shuffles them). Only their text is shown, never their Reputation points.
static func quiz_complaint_replies() -> Array[ComplaintResponse]:
	for complaint in CustomerComplaintsData.get_complaints():
		if complaint.complaint_text == QUIZ_COMPLAINT:
			var sorted := complaint.responses.duplicate()
			sorted.sort_custom(func(a: ComplaintResponse, b: ComplaintResponse) -> bool: return a.score > b.score)
			var ordered: Array[ComplaintResponse] = [sorted[1], sorted[0], sorted[2]]
			return ordered
	return []

static func best_complaint_score() -> int:
	var best := 0
	for complaint in CustomerComplaintsData.get_complaints():
		for response in complaint.responses:
			best = maxi(best, response.score)
	return best

static func worst_complaint_score() -> int:
	var worst := 0
	for complaint in CustomerComplaintsData.get_complaints():
		for response in complaint.responses:
			worst = mini(worst, response.score)
	return worst

static func _lesson(title: String, text: String) -> TrainingLesson:
	var lesson := TrainingLesson.new()
	lesson.title = title
	lesson.text = text
	return lesson

static func _question(question: String, answers: Array[String], correct: int, explanation: String) -> TrainingQuestion:
	var item := TrainingQuestion.new()
	item.question = question
	item.answers = PackedStringArray(answers)
	item.correct = correct
	item.explanation = explanation
	return item
