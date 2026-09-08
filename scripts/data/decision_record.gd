extends Resource
class_name DecisionRecord

## A single graded decision — one Teller shift's ending drawer count, one
## Loan Officer application decision, or one Branch Manager review action
## (Phase 5d) — kept as its own typed record for HistoryManager the same
## way ShiftTransaction is kept for a shift's deposits/withdrawals.
##
## grade_label deliberately reuses the exact wording each flow already
## produces for the player (teller_screen.gd's Perfect/Minor/Major
## discrepancy buckets, LoanApplication.grade_description()'s wording,
## and "Justified"/"Unjustified" for Branch Manager overrides) rather than
## inventing yet another parallel grading vocabulary just for this log.
## It's a plain String rather than a shared enum since each role grades on
## its own unrelated scale — a record with no meaningful grade just
## leaves it empty.
##
## has_loan_context and the four fields below it are only populated for
## LOAN_OFFICER records (see HistoryManager.add_loan_record()) — they're
## what Phase 5d's Approvals screen needs to re-grade an override against
## the SAME risk_assessment the original decision was graded against,
## without keeping a live reference to the original LoanApplication
## (which gets reused/mutated as applications cycle through review
## screens — a frozen copy of just the fields that matter is safer than a
## reference that could go stale).

enum Role { TELLER, LOAN_OFFICER, BRANCH_MANAGER }

@export var role: Role
@export var description: String = ""
@export var grade_label: String = ""
@export var timestamp: String = ""

## Set once a Branch Manager has acted on this record (overridden a loan
## decision, or flagged a Teller entry for retraining) so the Approvals
## screen doesn't offer to act on the same entry twice. The original
## description/grade_label are never rewritten — this is the only field
## a review action ever changes on an existing record.
@export var reviewed: bool = false

@export var has_loan_context: bool = false
@export var risk_assessment: LoanApplication.RiskTier = LoanApplication.RiskTier.MEDIUM
@export var original_decision_type: LoanApplication.DecisionType = LoanApplication.DecisionType.NONE
@export var applicant_name: String = ""
@export var decision_amount: float = 0.0

static func role_label(role_value: Role) -> String:
	match role_value:
		Role.TELLER:
			return "Teller"
		Role.LOAN_OFFICER:
			return "Loan Officer"
		_:
			return "Branch Manager"
