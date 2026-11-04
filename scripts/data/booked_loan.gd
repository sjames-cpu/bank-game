extends Resource
class_name BookedLoan

## One loan in the branch's loan book (LoanBookManager): who borrowed, how
## much, at what risk, whether their documents checked out, who made it, and
## how it turns out. The outcome is rolled when the loan is booked (from the
## risk and the documents only, never the borrower's name or look) and plays
## out over the following business days: a payment going late on late_day,
## then catching up or defaulting on resolve_day; a loan paid on time
## resolves quietly at the end. Saved field by field (SaveGame).

enum Outcome { ON_TIME, LATE, DEFAULT }
## BOOKED: nothing has happened yet; LATE_REPORTED: the late payment has
## been reported (resolved loans leave the book).
enum Stage { BOOKED, LATE_REPORTED }

@export var loan_id: int = 0
@export var borrower: String = ""
@export var purpose: String = ""
@export var amount: float = 0.0
@export var risk_tier: LoanApplication.RiskTier = LoanApplication.RiskTier.LOW
@export var documents_ok: bool = true
## "You", or the staff member who made it.
@export var made_by: String = ""
@export var by_player: bool = false
@export var made_day: int = 0
@export var outcome: Outcome = Outcome.ON_TIME
## The business day a payment goes late (LATE and DEFAULT), and how many
## calendar days late it's reported as.
@export var late_day: int = 0
@export var days_late: int = 0
## The business day the outcome is settled: paid on time through the
## settling period, caught up, or defaulted.
@export var resolve_day: int = 0
## Written off on a default (whole dollars).
@export var loss: float = 0.0
@export var stage: Stage = Stage.BOOKED

## "Maria Chen's auto loan".
func label() -> String:
	return "%s's %s loan" % [borrower, purpose.to_lower()]
