extends RefCounted
class_name KycPolicy

## The bank's ID policy at the Player Teller Window ("know your customer"):
## who needs to show ID, how often a customer's ID has a problem, and the
## cards themselves. Presented in game as bank policy, not as any law.
##
## ID is required for a withdrawal (cash or card) and for opening an account;
## deposits don't need it. Staff windows and the ATM don't check ID (yet).
##
## Every roll here uses the line's own RandomNumberGenerator
## (CustomerQueue.kyc_rng), never the global one, so adding IDs didn't change
## any other random draw in a seeded run.

## Share of customers whose ID has a problem (about 1 in 7).
const ID_PROBLEM_CHANCE: float = 1.0 / 7.0

## How a problem ID's problem is picked: relative weights, so the mix can be
## tuned without touching the rate above.
const PROBLEM_WEIGHTS: Dictionary = {
	IdCard.Problem.EXPIRED: 3,
	IdCard.Problem.NAME_MISMATCH: 2,
	IdCard.Problem.WRONG_PORTRAIT: 2,
	IdCard.Problem.NO_ID: 1,
}

## Share of regular (non-complaint) customers who come to open an account
## with a first deposit (about 1 in 10).
const ACCOUNT_OPENING_CHANCE: float = 0.1

## A valid card expires 1 to 8 years after today; an expired one ran out 1 to
## 400 days ago.
const VALID_YEARS_MIN: int = 1
const VALID_YEARS_MAX: int = 8
const EXPIRED_DAYS_MIN: int = 1
const EXPIRED_DAYS_MAX: int = 400

## Card holders are 18 to 85 years old.
const AGE_MIN_YEARS: int = 18
const AGE_MAX_YEARS: int = 85

## Looks come in designs of this many (CustomerNPC.CUSTOMER_FRAME_SETS: a
## design and its three recolours), so a wrong portrait is always another
## design, not a recolour of the customer's own.
const LOOKS_PER_DESIGN: int = 4

const POLICY_TEXT: String = "Bank policy: withdrawals and new accounts need a valid photo ID — unexpired, in the account holder's name, with their photo. Deposits don't."
const REFUSAL_LINE: String = "I'm sorry, I can't process this without valid ID."

## Whether serving `customer` needs their ID checked first.
static func requires_id(customer: CustomerNPC) -> bool:
	if customer == null or customer.complaint != null:
		return false
	return customer.opens_account or customer.intent_type == ShiftTransaction.Type.WITHDRAWAL

## Rolls whether a card has a problem and, if so, which (see PROBLEM_WEIGHTS).
static func roll_problem(rng: RandomNumberGenerator, problem_chance: float) -> IdCard.Problem:
	if rng.randf() >= problem_chance:
		return IdCard.Problem.NONE
	var total := 0
	for weight: int in PROBLEM_WEIGHTS.values():
		total += weight
	var pick := rng.randi_range(1, total)
	for problem: IdCard.Problem in PROBLEM_WEIGHTS:
		var weight: int = PROBLEM_WEIGHTS[problem]
		pick -= weight
		if pick <= 0:
			return problem
	return IdCard.Problem.NONE

## The card for a customer named `holder` with look `look`, on `today`
## (epoch day), with `problem` built in.
static func issue_card(rng: RandomNumberGenerator, holder: String, look: int, today: int, problem: IdCard.Problem, look_count: int) -> IdCard:
	var card := IdCard.new()
	card.problem = problem
	if problem == IdCard.Problem.NO_ID:
		card.presented = false
		return card
	card.holder_name = holder
	card.portrait_look = look
	var age_days := rng.randi_range(AGE_MIN_YEARS * 365 + 1, AGE_MAX_YEARS * 365)
	card.date_of_birth = today - age_days
	card.id_number = "%s%07d" % [char(65 + rng.randi_range(0, 25)), rng.randi_range(0, 9999999)]
	card.expiry_date = today + rng.randi_range(VALID_YEARS_MIN * 365, VALID_YEARS_MAX * 365)
	match problem:
		IdCard.Problem.EXPIRED:
			card.expiry_date = today - rng.randi_range(EXPIRED_DAYS_MIN, EXPIRED_DAYS_MAX)
		IdCard.Problem.NAME_MISMATCH:
			card.holder_name = mismatched_name(rng, holder)
		IdCard.Problem.WRONG_PORTRAIT:
			card.portrait_look = other_design_look(rng, look, look_count)
	return card

## Someone else's name: the holder's first name with another surname from
## the customer name pool, so it takes a careful read to spot.
static func mismatched_name(rng: RandomNumberGenerator, holder: String) -> String:
	var first := holder.get_slice(" ", 0)
	var surnames: Array[String] = []
	for other in CustomerQueue.CUSTOMER_NAMES:
		var surname := other.substr(other.find(" ") + 1)
		if surname != holder.substr(holder.find(" ") + 1) and not surnames.has(surname):
			surnames.append(surname)
	return "%s %s" % [first, surnames[rng.randi_range(0, surnames.size() - 1)]]

## A look from a different design than `look`.
static func other_design_look(rng: RandomNumberGenerator, look: int, look_count: int) -> int:
	var others: Array[int] = []
	for candidate in look_count:
		if design_of(candidate) != design_of(look):
			others.append(candidate)
	return others[rng.randi_range(0, others.size() - 1)]

static func design_of(look: int) -> int:
	return floori(look / float(LOOKS_PER_DESIGN))
