extends Resource
class_name StaffReviewItem

## One piece of NPC staff work waiting for the Branch Manager's review (see
## StaffReviewManager): a teller-window mistake or a loan decision that
## wasn't graded BEST. Built in code, like the other data resources.
##
## The item keeps a frozen copy of what the manager needs to judge it —
## never a live CustomerNPC/LoanApplication reference, since customers are
## freed and applications are reused — plus the hidden facts (mistake kind,
## loan grade) that decide its severity. Those hidden facts are only shown
## to the manager after they've acted (StaffReviewScreen).

enum Kind { TELLER, LOAN }

## How serious the work was, decided when the item is queued. A MINOR item
## can still be judged as REPEATED_MINOR at decision time (see
## StaffReviewManager.effective_severity()), so this is the base severity.
enum Severity { SERIOUS, MINOR, ACCEPTABLE, REPEATED_MINOR }

## NpcCustomerLine's four mistake kinds.
enum TellerMistake { AMOUNT_SHORT, AMOUNT_OVER, WRONG_TYPE, WRONG_ACCOUNT }

@export var kind: Kind = Kind.TELLER
@export var severity: Severity = Severity.MINOR
@export var staff_name: String = ""
@export var staff_slot: String = ""
@export var timestamp: String = ""

## --- Teller items ---
@export var customer_name: String = ""
@export var request_type: ShiftTransaction.Type = ShiftTransaction.Type.DEPOSIT
## The customer's requested amount, int cents (B3).
@export var request_amount_cents: int = 0
@export var teller_mistake: TellerMistake = TellerMistake.AMOUNT_SHORT
## What the staff member actually did wrong, e.g. "came up $30 short".
@export var mistake_detail: String = ""

## --- Loan items ---
@export var applicant_name: String = ""
@export var requested_amount: float = 0.0
@export var loan_purpose: String = ""
@export var credit_score: int = 0
@export var annual_income: float = 0.0
@export var monthly_debt_payments: float = 0.0
## The underwriting worksheet's values (LoanApplication), frozen at the
## decision. An item from a save before the worksheet has has_worksheet
## false and none of them (its old DTI and loan-to-income are dropped).
@export var has_worksheet: bool = false
@export var monthly_housing_payment: float = 0.0
@export var replaces_housing: bool = false
@export var new_payment: float = 0.0
@export var term_months: int = 0
@export var annual_rate: float = 0.0
@export var front_end_dti: float = 0.0
@export var total_dti: float = 0.0
@export var employment_months: int = 0
@export var affordable_amount: float = 0.0
@export var decision: LoanApplication.DecisionType = LoanApplication.DecisionType.NONE
@export var decision_amount: float = 0.0
## Hidden until the manager has decided.
@export var grade: LoanApplication.Grade = LoanApplication.Grade.PARTIAL
