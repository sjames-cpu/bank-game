extends Resource
class_name Account

## A bank account: a customer name plus a balance, with mutation only
## allowed through deposit()/withdraw() so callers can't set an invalid
## balance directly. Being a Resource means this could later be saved
## to a .tres file to persist accounts between sessions — for now the
## teller screen just creates one in memory.

@export var customer_name: String = ""
@export var balance: float = 0.0

## Phase 6j: true for an account auto-created for a spawned Teller queue
## customer (see CustomerQueue._get_or_create_customer_account()), false
## for the seeded demo account and anything opened via "Open New Account".
## Doesn't change how the account works — deposit()/withdraw() below don't
## care — it's purely a hint AccountManager.get_browsable_accounts() uses
## to keep the Teller screen's general dropdown from accumulating every
## customer who's ever been served.
@export var is_customer_account: bool = false

func deposit(amount: float) -> void:
	if amount <= 0.0:
		return
	balance += amount

func can_withdraw(amount: float) -> bool:
	return amount > 0.0 and amount <= balance

func withdraw(amount: float) -> bool:
	if not can_withdraw(amount):
		return false
	balance -= amount
	return true
