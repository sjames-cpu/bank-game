extends RefCounted
class_name MoneyMath

## Money is stored as float dollars throughout (Account.balance,
## ShiftTransaction.amount, drawer totals), but floats can't represent most
## cent values exactly — summing a shift's transactions can leave a
## correctly-counted drawer a hair off its expected balance, which then
## fails an `== 0.0` Perfect check. Discrepancy checks compare in integer
## cents via to_cents() instead, so a correct count is always exactly 0.

static func to_cents(amount: float) -> int:
	return roundi(amount * 100.0)
