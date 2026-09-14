extends RefCounted
class_name CustomerComplaintsData

## Static provider for the Teller desk's complaint scenario pool (Phase
## 6c). Kept separate from CustomerComplaint/ComplaintResponse (the data
## shape) so scenario content can grow independently, mirroring
## InterviewQuestionsData/CustomerDialogueData.
##
## Response scores are modest Reputation deltas (Reputation only — no
## Score/XP consequence, see teller_screen.gd): +2 for an
## apologetic/helpful response, 0 for a neutral/procedural one, -3 for a
## dismissive/defensive one. Every scenario below follows that same
## three-tier shape.

static func get_complaints() -> Array[CustomerComplaint]:
	return [
		_complaint("You charged me a fee I wasn't told about, and I want it explained.", [
			_response("I'm sorry about that — let me walk you through exactly where it came from and see what I can do.", 2),
			_response("Let me pull up your account and check the fee schedule for you.", 0),
			_response("That fee is standard, it's listed in your account terms.", -3),
		]),
		_complaint("I've been waiting forever, this is ridiculous.", [
			_response("I'm sorry for the wait, thank you for your patience — let's get you taken care of right away.", 2),
			_response("We've been busy today, but I can help you now.", 0),
			_response("It hasn't been that long. Let's just get this done.", -3),
		]),
		_complaint("Your last teller was rude to me and I almost left.", [
			_response("I'm really sorry to hear that, that's not how we want you treated — let me make this visit right.", 2),
			_response("I'll pass that along to a manager. What can I help you with today?", 0),
			_response("I'm sure it wasn't as bad as you think. What do you need?", -3),
		]),
		_complaint("I was told my transfer would clear yesterday and it still hasn't.", [
			_response("I apologize for the delay — let me look into it right now and give you a clear answer.", 2),
			_response("Transfers can take a bit longer sometimes. Let me check the status for you.", 0),
			_response("That's not really something I handle. You'll have to wait it out.", -3),
		]),
		_complaint("Nobody explained the account's minimum balance requirement before I got charged for it.", [
			_response("That's on us for not explaining it clearly — let me go over it now and see about reversing the charge.", 2),
			_response("I can explain the requirement now so it doesn't happen again.", 0),
			_response("That information is in the account disclosure you signed.", -3),
		]),
		_complaint("I've called three times this week and nobody has called me back.", [
			_response("I'm sorry you've had to chase this down — let's solve it here so you don't have to call again.", 2),
			_response("Let me see what's in our notes and pick up where things left off.", 0),
			_response("I can't speak to what other people did. What's the issue?", -3),
		]),
	]

static func _complaint(text: String, responses: Array[ComplaintResponse]) -> CustomerComplaint:
	var complaint := CustomerComplaint.new()
	complaint.complaint_text = text
	complaint.responses = responses
	return complaint

static func _response(text: String, score: int) -> ComplaintResponse:
	var response := ComplaintResponse.new()
	response.text = text
	response.score = score
	return response
