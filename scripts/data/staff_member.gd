extends Resource
class_name StaffMember

## A hireable staff member who can be scheduled into a role (Phase 5c).
## Built in code (see staff_roster_data.gd) rather than loaded from .tres
## files, the same way Account/InterviewQuestion/LoanApplication are —
## there's no save/load need for this data yet.
##
## skill/reliability/speed/customer_service are independent 1-10 ratings
## rather than a single combined "quality" score, so a later scheduling
## system can weigh them differently per role (e.g. Teller shifts caring
## more about speed and customer_service, Loan Officer reviews caring more
## about skill and reliability) instead of just picking whoever's "best."

@export var staff_name: String = ""

## The role this staff member would be scheduled into — "Teller" or
## "Loan Officer" today, matching the role names DecisionRecord.role_label
## produces. A String rather than an enum shared with DecisionRecord.Role
## since staffing (who *could* work a role) and a logged decision's role
## are separate concerns that just happen to use the same vocabulary.
@export var role: String = ""

@export var skill: int = 5
@export var reliability: int = 5
@export var speed: int = 5
@export var customer_service: int = 5

## 1-2 sentences of flavor text giving the staff member personality,
## reflecting their stat profile (e.g. a fast-but-unreliable staffer reads
## as "quick but cuts corners" rather than just a bar chart of numbers).
@export var flavor_text: String = ""

## --- How stats drive NPC work (NpcCustomerLine / NpcLoanDeskWorker) ---
## All 1-10 stats map linearly; first-pass values, tune after playtesting.

const SERVICE_SECONDS_SLOWEST: float = 10.0 # speed 1
const SERVICE_SECONDS_FASTEST: float = 4.0  # speed 10
## Fixing a mistake takes this fraction of a normal service on top.
const MISTAKE_FIX_TIME_FACTOR: float = 0.5
const MISTAKE_CHANCE_BEST: float = 0.02  # weaker of skill/reliability = 10
const MISTAKE_CHANCE_WORST: float = 0.20 # weaker of skill/reliability = 1
const LOAN_SECONDS_SLOWEST: float = 40.0 # speed 1
const LOAN_SECONDS_FASTEST: float = 15.0 # speed 10

static func _stat_t(value: int) -> float:
	return clampf((value - 1) / 9.0, 0.0, 1.0)

## Seconds to serve one teller customer: 10s at speed 1 down to 4s at 10.
func service_seconds() -> float:
	return lerpf(SERVICE_SECONDS_SLOWEST, SERVICE_SECONDS_FASTEST, _stat_t(speed))

func mistake_fix_seconds() -> float:
	return service_seconds() * MISTAKE_FIX_TIME_FACTOR

## Chance a transaction goes wrong: 2% + 18% x (10 - weaker of skill and
## reliability) / 9 — i.e. driven by the weaker of the two, since either a
## knowledge gap or a lapse in care causes errors. 2% (both 10) .. 20% (1).
func mistake_chance() -> float:
	return lerpf(MISTAKE_CHANCE_BEST, MISTAKE_CHANCE_WORST, 1.0 - _stat_t(mini(skill, reliability)))

## Seconds between background loan decisions: 40s at speed 1 down to 15s.
func loan_decision_seconds() -> float:
	return lerpf(LOAN_SECONDS_SLOWEST, LOAN_SECONDS_FASTEST, _stat_t(speed))

## Chance a loan decision is the correct call for the application's risk:
## skill / 10.
func loan_correct_chance() -> float:
	return skill / 10.0
