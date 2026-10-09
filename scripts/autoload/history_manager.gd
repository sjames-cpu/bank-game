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

## New career after termination — see CareerReset.
func reset() -> void:
	records.clear()
	_staff_record_count = 0

func add_record(role: DecisionRecord.Role, description: String, grade_label: String = "") -> DecisionRecord:
	var record := DecisionRecord.new()
	record.role = role
	record.description = description
	record.grade_label = grade_label
	record.timestamp = Time.get_datetime_string_from_system()
	records.append(record)
	return record

## Staff records arrive continuously (every NPC transaction and loan
## decision), so only the most recent MAX_STAFF_RECORDS are kept; the
## oldest staff record is dropped when a new one would exceed it. Every
## other role's records stay uncapped.
const MAX_STAFF_RECORDS: int = 200

var _staff_record_count: int = 0

## Emitted for every new staff record, before any capping — lets the Branch
## Manager shift summary tally a whole shift's staff work even if the cap
## drops older records meanwhile.
signal staff_record_added(record: DecisionRecord)

## An NPC coworker's transaction or loan decision at desk `slot_name`.
## grade_label is "Correct" or "Mistake".
func add_staff_record(staff_name: String, slot_name: String, description: String, grade_label: String) -> DecisionRecord:
	var record := add_record(DecisionRecord.Role.STAFF, description, grade_label)
	record.staff_name = staff_name
	record.staff_slot = slot_name
	staff_record_added.emit(record)
	_staff_record_count += 1
	if _staff_record_count > MAX_STAFF_RECORDS:
		for i in records.size():
			if records[i].role == DecisionRecord.Role.STAFF:
				records.remove_at(i)
				_staff_record_count -= 1
				break
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
