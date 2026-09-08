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
