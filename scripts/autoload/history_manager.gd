extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/
## XPManager (see ScoreManager for why an autoload is the right fit).
## Holds a running in-memory log of graded Teller and Loan Officer
## decisions (see DecisionRecord) for the eventual Branch Manager role
## (Phase 5) to review — nothing reads this yet, but the log needs to
## start accumulating as soon as decisions happen, not once a viewer
## exists for it.
##
## Like the other managers, this only lives in memory for now and resets
## if the game is closed. Persisting across full restarts would mean
## saving to a user:// file on change and loading it back in _ready().

var records: Array[DecisionRecord] = []

func add_record(role: DecisionRecord.Role, description: String, grade_label: String = "") -> DecisionRecord:
	var record := DecisionRecord.new()
	record.role = role
	record.description = description
	record.grade_label = grade_label
	record.timestamp = Time.get_datetime_string_from_system()
	records.append(record)
	return record

## Same as add_record(), plus the structured loan context (Phase 5d's
## Approvals screen needs to re-grade an override against the exact same
## risk_assessment the original decision was graded against — see
## DecisionRecord's doc comment for why that's kept as plain fields
## rather than a LoanApplication reference).
func add_loan_record(description: String, grade_label: String, risk_assessment: LoanApplication.RiskTier, decision_type: LoanApplication.DecisionType, applicant_name: String, decision_amount: float) -> DecisionRecord:
	var record := add_record(DecisionRecord.Role.LOAN_OFFICER, description, grade_label)
	record.has_loan_context = true
	record.risk_assessment = risk_assessment
	record.original_decision_type = decision_type
	record.applicant_name = applicant_name
	record.decision_amount = decision_amount
	return record
