extends Resource
class_name ShiftTransaction

## A single deposit/withdrawal made during a shift. Kept as its own
## typed record (rather than folding straight into a running total)
## because shift scoring will eventually need to look at the individual
## transactions themselves — e.g. flagging suspiciously large ones,
## crediting per-transaction accuracy — not just the net effect.

enum Type { DEPOSIT, WITHDRAWAL }

## Phase 6e: whether this transaction moved physical drawer cash or not.
## Card transactions still apply to the account balance the same way a
## cash one does (see teller_screen.gd's deposit/withdraw handlers) but
## are excluded from _calculate_expected_ending_balance()'s drawer math,
## since no physical cash changed hands.
enum PaymentMethod { CASH, CARD }

@export var type: Type
@export var amount: float = 0.0
@export var account_name: String = ""
@export var timestamp: String = ""
@export var payment_method: PaymentMethod = PaymentMethod.CASH
