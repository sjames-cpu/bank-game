extends Resource
class_name IdCard

## The photo ID a customer in the player's line carries (KycPolicy issues
## it at spawn). What the card says is all the teller sees; `problem` is
## what's actually wrong with it, kept for grading and never shown.
##
## Dates are epoch days (BankCalendar), compared with the game's date, not
## the wall clock.

enum Problem { NONE, EXPIRED, NAME_MISMATCH, WRONG_PORTRAIT, NO_ID }

## False when the customer has no ID with them (Problem.NO_ID): the other
## fields are then empty.
@export var presented: bool = true
@export var holder_name: String = ""
@export var date_of_birth: int = 0
@export var id_number: String = ""
@export var expiry_date: int = 0
## Index into CustomerNPC.CUSTOMER_FRAME_SETS: whose face is on the card.
@export var portrait_look: int = 0
@export var problem: Problem = Problem.NONE

func is_valid() -> bool:
	return problem == Problem.NONE

## "5 Jan 2026", as printed on the card.
static func date_text(date: int) -> String:
	var c := BankCalendar.civil(date)
	return "%d %s %d" % [c.z, BankCalendar.MONTH_NAMES[c.y - 1].substr(0, 3), c.x]
