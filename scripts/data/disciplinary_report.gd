extends Resource
class_name DisciplinaryReport

## One written warning issued by the Branch Manager (see ReportManager).
## Built in code, like the other data resources — nothing is saved yet.

## 1-based position in the player's current run of reports (1, 2, 3).
@export var number: int = 0

## Which role's mistakes produced it — only TELLER for now (see
## ReportManager.REPORT_REASONS for where a Loan Officer reason would go).
@export var role: DecisionRecord.Role = DecisionRecord.Role.TELLER

## Player-facing reason, e.g. "Repeated transaction errors at the teller desk".
@export var reason: String = ""

## The individual mistakes behind it — for teller reports, the names of the
## customers whose transactions were done wrong.
@export var items: PackedStringArray = []

@export var timestamp: String = ""
