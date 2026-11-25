extends StaffNPC
class_name LoanApplicantNPC

## A loan applicant walking in to a loan desk, sitting in front of it and
## leaving after the decision (LoanDeskSeat). Walks waypoint routes like a
## staff member (StaffNPC), but looks like a customer
## (CustomerNPC.CUSTOMER_FRAME_SETS, the application's applicant_look) and
## has no name tag. Collides with walls only, like customers.

## What they say on sitting down, by loan purpose (presented as the
## applicant's own words; nothing about who they are).
const PURPOSE_LINES: Dictionary = {
	"Auto": ["I'm hoping to finance a car.", "I need a loan for a new car.", "My old car finally gave out."],
	"Home": ["I've found a house I'd love to buy.", "I'm looking for a mortgage on a home.", "I'd like a mortgage for a new place."],
	"Personal": ["I'd like to consolidate some bills.", "I need a loan for some home repairs.", "I'm hoping to cover some big bills."],
	"Business": ["I'm expanding my business.", "My shop needs new equipment.", "My business needs funds for more stock."],
}

## On leaving, by how it went.
const APPROVED_LINES: Array[String] = ["Wonderful, thank you!", "That's great news, thanks!"]
const COUNTER_LINES: Array[String] = ["Hmm, I'll think about that offer.", "Less than I hoped. I'll consider it."]
const REJECTED_LINES: Array[String] = ["Oh. That's disappointing.", "I see. Thanks anyway."]
const UNVERIFIED_LINES: Array[String] = ["I'll come back with the right papers.", "Fine. I'll sort my documents out."]
## Asked to bring more documents (a request, not yet a decision).
const REQUEST_LINES: Array[String] = ["I'll bring those in as soon as I can.", "Okay, I'll get those papers together."]
## On sitting down with the documents they were asked for: as asked, with
## something still missing, and late.
const RETURN_LINES: Array[String] = ["Here are the documents you asked for.", "I've brought the papers you asked for."]
const RETURN_INCOMPLETE_LINES: Array[String] = ["I couldn't find everything, but this is what I have.", "This is most of it. I'm still looking for the rest."]
const RETURN_LATE_LINES: Array[String] = ["Sorry I'm late. Here are the documents.", "Sorry for the wait. Here are your documents."]
## On sitting down for their closing; and on leaving after it was funded, and
## after it was stopped (pleased, or disappointed and confused).
const CLOSING_LINES: Array[String] = ["I'm here to sign for my loan.", "I'm here to finish my loan paperwork.", "Hello, I'm here to close on my loan."]
const CLOSING_FUNDED_LINES: Array[String] = ["Wonderful, it's all done. Thank you!", "Great, thank you so much!"]
const CLOSING_STOPPED_LINES: Array[String] = ["Wait, what? I don't understand.", "Oh no. What went wrong?", "That's disappointing. I'll look into it."]
## Sent away before being seen (the desk changed hands).
const SENT_AWAY_LINE: String = "I'll come back another time."

var look: int = 0

func _ready() -> void:
	super()
	_name_label.visible = false
	_apply_look()

## Their look, before or after being added to the tree.
func set_look(index: int) -> void:
	look = clampi(index, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)
	if is_node_ready():
		_apply_look()

func _apply_look() -> void:
	_sprite.sprite_frames = CustomerNPC.CUSTOMER_FRAME_SETS[look]
	_sprite.play(&"idle_down")

## What they say on sitting down: what the loan is for, or, for a file
## whose documents are back (LoanRole.pipeline), that they have brought them.
static func arrival_line(application: LoanApplication, pick: int) -> String:
	if LoanRole.closings.closing_for(application) != null:
		return CLOSING_LINES[absi(pick) % CLOSING_LINES.size()]
	var file := LoanRole.pipeline.file_for(application)
	if file != null and file.has_returned(GameClock.day):
		var lines := RETURN_LINES
		if file.quality == LoanFile.Quality.INCOMPLETE:
			lines = RETURN_INCOMPLETE_LINES
		elif file.timing == LoanFile.Timing.LATE:
			lines = RETURN_LATE_LINES
		return lines[absi(pick) % lines.size()]
	return purpose_line(application.loan_purpose, pick)

static func purpose_line(purpose: String, pick: int) -> String:
	var lines: Array = PURPOSE_LINES.get(purpose, ["I'd like to apply for a loan."])
	var line: String = lines[absi(pick) % lines.size()]
	return line

## How they react to `application`'s decision.
static func reaction_line(application: LoanApplication, pick: int) -> String:
	match LoanRole.closings.outcome_for(application):
		LoanClosings.Outcome.FUNDED:
			return CLOSING_FUNDED_LINES[absi(pick) % CLOSING_FUNDED_LINES.size()]
		LoanClosings.Outcome.STOPPED:
			return CLOSING_STOPPED_LINES[absi(pick) % CLOSING_STOPPED_LINES.size()]
	var lines: Array[String] = REJECTED_LINES
	match application.decision:
		LoanApplication.DecisionType.NONE:
			lines = REQUEST_LINES
		LoanApplication.DecisionType.APPROVE:
			lines = APPROVED_LINES
		LoanApplication.DecisionType.COUNTER_OFFER:
			lines = COUNTER_LINES
		LoanApplication.DecisionType.REJECT:
			lines = REJECTED_LINES if application.documents_check_out() else UNVERIFIED_LINES
	return lines[absi(pick) % lines.size()]
