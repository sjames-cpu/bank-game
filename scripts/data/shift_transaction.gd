extends Resource
class_name ShiftTransaction

## A single deposit/withdrawal made during a shift. Kept as its own
## typed record (rather than folding straight into a running total)
## because shift scoring will eventually need to look at the individual
## transactions themselves — e.g. flagging suspiciously large ones,
## crediting per-transaction accuracy — not just the net effect.

enum Type { DEPOSIT, WITHDRAWAL }

@export var type: Type
@export var amount: float = 0.0
@export var account_name: String = ""
@export var timestamp: String = ""
