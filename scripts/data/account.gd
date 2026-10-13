extends Resource
class_name Account

## A bank account: a customer name plus a balance, with mutation only
## allowed through deposit()/withdraw() so callers can't set an invalid
## balance directly. Being a Resource means this could later be saved
## to a .tres file to persist accounts between sessions — for now the
## teller screen just creates one in memory.
##
## Money is int cents (B3, see MoneyMath).

@export var customer_name: String = ""
@export var balance_cents: int = 0

## Phase 6j: true for an account auto-created for a spawned Teller queue
## customer (see CustomerQueue._get_or_create_customer_account()), false
## for the seeded demo account and anything opened via "Open New Account".
## Doesn't change how the account works — deposit()/withdraw() below don't
## care — it's purely a hint AccountManager.get_browsable_accounts() uses
## to keep the Teller screen's general dropdown from accumulating every
## customer who's ever been served.
@export var is_customer_account: bool = false

## True for an account auto-created for a customer in a staff-served line
## (NpcCustomerLine). Those accounts are a separate namespace: staff lines
## only ever reuse each other's accounts by name, and the player's line (and
## any other by-name lookup) never sees them — so staff transactions can't
## change the balance of a customer waiting in the player's line, even when
## the two share a name. See AccountManager.find_account_by_name().
@export var is_staff_line_account: bool = false

func deposit(amount_cents: int) -> void:
	if amount_cents <= 0:
		return
	balance_cents += amount_cents

func can_withdraw(amount_cents: int) -> bool:
	return amount_cents > 0 and amount_cents <= balance_cents

func withdraw(amount_cents: int) -> bool:
	if not can_withdraw(amount_cents):
		return false
	balance_cents -= amount_cents
	return true
