extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/
## XPManager (see ScoreManager for why an autoload is the right fit).
## Holds a running in-memory log of graded decisions (see DecisionRecord):
## the player's Teller and Loan Officer work, which the Branch Manager's
## Approvals screen reviews; disciplinary reports and drawer variances
## (record only); Branch Manager actions; and NPC staff work (capped at
## MAX_STAFF_RECORDS, announced via staff_record_added for the Branch
## Manager shift summary).
##
## Saved with the career (save_data()/load_data(), see SaveGame).

var records: Array[DecisionRecord] = []

## New career after termination — see CareerReset.
func reset() -> void:
	records.clear()
	_staff_record_count = 0

func save_data() -> Dictionary:
	var saved: Array = []
	for record in records:
		saved.append(SaveGame.resource_to_dict(record))
	return {"records": saved}

## Keeps the staff-record cap: if a save holds more than MAX_STAFF_RECORDS
## staff records, only the newest are kept.
func load_data(data: Dictionary) -> void:
	records.clear()
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "records")):
		var record := DecisionRecord.new()
		SaveGame.fill_resource(record, entry)
		records.append(record)
	var staff_records := records.filter(func(record: DecisionRecord) -> bool: return record.role == DecisionRecord.Role.STAFF)
	for i in maxi(0, staff_records.size() - MAX_STAFF_RECORDS):
		records.erase(staff_records[i])
	_staff_record_count = mini(staff_records.size(), MAX_STAFF_RECORDS)

func add_record(role: DecisionRecord.Role, description: String, grade_label: String = "") -> DecisionRecord:
	var record := DecisionRecord.new()
	record.role = role
	record.description = description
	record.grade_label = grade_label
	record.timestamp = GameClock.timestamp()
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
## grade_label is "Correct" or "Mistake"; id_check is a teller's ID check.
func add_staff_record(staff_name: String, slot_name: String, description: String, grade_label: String, id_check: KycPolicy.StaffCheck = KycPolicy.StaffCheck.NOT_NEEDED) -> DecisionRecord:
	var record := add_record(DecisionRecord.Role.STAFF, description, grade_label)
	record.staff_name = staff_name
	record.staff_slot = slot_name
	record.staff_id_check = id_check
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
