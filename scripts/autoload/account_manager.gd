extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager/etc.
## (see ScoreManager for why an autoload is the right fit). Holds the single
## shared list of Account resources so ATM and Teller (and any future desk)
## all read and write the same customer data instead of each keeping its
## own local list — previously atm_screen.gd and teller_screen.gd each
## seeded and mutated a separate array, so a deposit made at one desk was
## invisible at the other.
##
## Like the other managers, this only lives in memory for now and resets
## if the game is closed. Persisting across full restarts would mean
## saving to a user:// file on change and loading it back in _ready().
##
## deposit()/withdraw() here are thin wrappers around Account's own
## deposit()/withdraw()/can_withdraw() (Fix 4) — callers are still
## responsible for their own pre-checks (amount validity, withdrawal
## limits, card decline, insufficient funds) exactly as before; this
## just gives the mutation a single place to emit accounts_changed from.

signal accounts_changed

var accounts: Array[Account] = []

func _ready() -> void:
	create_account("Johnathan Jamestar", 1000.0)

## Flat list, not keyed by name — customer names aren't guaranteed unique
## (see find_account_by_name() below), so index/reference is still how
## callers should track "the" account once they have one.
func get_accounts() -> Array[Account]:
	return accounts

func create_account(customer_name: String, starting_balance: float = 0.0) -> Account:
	var new_account := Account.new()
	new_account.customer_name = customer_name
	new_account.balance = starting_balance
	accounts.append(new_account)
	accounts_changed.emit()
	return new_account

## First match by customer_name, or null if none found. Names aren't
## guaranteed unique (two customers could share a name), so this is a
## convenience lookup, not a stand-in for an account number — callers that
## already hold an Account reference (e.g. via OptionButton selection)
## should keep using that reference directly.
func find_account_by_name(customer_name: String) -> Account:
	for existing_account in accounts:
		if existing_account.customer_name == customer_name:
			return existing_account
	return null

func deposit(account: Account, amount: float) -> void:
	account.deposit(amount)
	accounts_changed.emit()

func withdraw(account: Account, amount: float) -> bool:
	var success := account.withdraw(amount)
	if success:
		accounts_changed.emit()
	return success
