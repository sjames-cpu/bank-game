extends Resource
class_name ComplaintResponse

## One response choice for a CustomerComplaint (Phase 6c). Mirrors
## InterviewAnswer's shape exactly, except score here is a Reputation
## delta rather than an interview point — see
## teller_screen.gd's _on_complaint_response_selected() for where it's
## applied via ReputationManager.add_reputation().

@export var text: String = ""
@export var score: int = 0
