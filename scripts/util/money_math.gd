extends RefCounted
class_name MoneyMath

## Money the player handles (account balances, transactions, customer
## requests, drawer/vault/ATM amounts) is stored as int cents end to end
## (B3): floats can't represent most cent values exactly, so summing a
## shift's transactions in dollars drifted and could fail an exact Perfect
## count. Dollars only appear at the edges: to_cents() once when a value is
## entered (a SpinBox), and format() whenever an amount is shown.
##
## Loan application figures are deliberately not cents — see
## LoanApplication: they're whole-dollar figures for judgement, never cash
## that moves through an account or drawer.

## Dollars (a SpinBox value or a whole-dollar constant) to cents, rounded to
## the nearest cent.
static func to_cents(amount: float) -> int:
	return roundi(amount * 100.0)

## How every cash amount is shown: "$1234.50", "$-10.00" — the same text
## "$%.2f" gave for dollar floats. drop_whole_cents (for what people say,
## like a customer's request) shows a whole-dollar amount as "$500" and any
## other as "$12.34", so cents are never hidden.
static func format(cents: int, drop_whole_cents: bool = false) -> String:
	var sign := "-" if cents < 0 else ""
	var magnitude := absi(cents)
	@warning_ignore("integer_division")
	var dollars := magnitude / 100
	var remainder := magnitude % 100
	if drop_whole_cents and remainder == 0:
		return "$%s%d" % [sign, dollars]
	return "$%s%d.%02d" % [sign, dollars, remainder]
