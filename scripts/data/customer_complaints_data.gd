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
		_complaint("You charged me a fee nobody told me about, and I want it explained.", [
			_response("That's frustrating when a fee comes out of nowhere — let me pull up exactly where it came from and see whether we can get it refunded or waived.", 2),
			_response("Let me pull up your account and go over the fee schedule with you.", 0),
			_response("That fee's listed in your account terms — it's on you to have read them.", -3),
		]),
		_complaint("I've been waiting forever, this is unacceptable.", [
			_response("You're right, that's too long to wait — thank you for sticking with it. Let's get you taken care of right now.", 2),
			_response("I understand. Let's get started so we can wrap this up quickly.", 0),
			_response("We've been slammed all day, there's only so much I can do.", -3),
		]),
		_complaint("Your last teller was rude to me and I almost switched banks over it.", [
			_response("I'm genuinely sorry that happened — that's not how we want any customer treated. I'll make a note of it so it gets looked into, and let's make sure today goes right.", 2),
			_response("I'll let a manager know about that. What can I help you with today?", 0),
			_response("I'm sure it wasn't as bad as you think. What do you need?", -3),
		]),
		_complaint("My balance doesn't match what I expected — I think something's wrong.", [
			_response("Let's not assume anything's off on your end — I'll go through your recent transactions with you right now and figure out exactly what happened.", 2),
			_response("Let me pull up your transaction history and take a look.", 0),
			_response("Most of the time this just turns out to be a purchase or pending charge the customer forgot about.", -3),
		]),
		_complaint("This transaction was fraudulent and I need it reversed right now.", [
			_response("I hear you, and I want to get this fixed — a disputed transaction like this has to go through our fraud team. Let me get you connected with them right now so it doesn't fall through the cracks.", 2),
			_response("I can flag this for our fraud team to look into.", 0),
			_response("That's not something I handle here.", -3),
		]),
		_complaint("I need to close my father's account — he passed away last week and I don't know where to start.", [
			_response("I'm so sorry for your loss. Let's take this one step at a time — I'll walk you through exactly what we'll need and handle it at whatever pace works for you.", 2),
			_response("I can help with that. I'll need a death certificate and proof you're the executor to get started.", 0),
			_response("I just need the paperwork to process this — do you have the death certificate and executor documents with you?", -3),
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
