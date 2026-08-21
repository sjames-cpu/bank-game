extends Resource
class_name Account

## A bank account: a customer name plus a balance, with mutation only
## allowed through deposit()/withdraw() so callers can't set an invalid
## balance directly. Being a Resource means this could later be saved
## to a .tres file to persist accounts between sessions — for now the
## teller screen just creates one in memory.

@export var customer_name: String = ""
@export var balance: float = 0.0

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
