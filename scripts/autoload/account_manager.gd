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
##
## Amounts are int cents (B3, see MoneyMath).

signal accounts_changed

var accounts: Array[Account] = []

## The seeded demo account's starting balance ($1,000.00).
const DEMO_ACCOUNT_START_CENTS: int = 100000

func _ready() -> void:
	_create_default_accounts()

func _create_default_accounts() -> void:
	create_account("Johnathan Jamestar", DEMO_ACCOUNT_START_CENTS)

## New career after termination — see CareerReset. Drops every customer and
## player-opened account and restores the demo account to its starting
## balance.
func reset() -> void:
	accounts.clear()
	_create_default_accounts()
	accounts_changed.emit()

## Flat list, not keyed by name — customer names aren't guaranteed unique
## (see find_account_by_name() below), so index/reference is still how
## callers should track "the" account once they have one.
func get_accounts() -> Array[Account]:
	return accounts

## Phase 6j: same list as get_accounts(), minus anything flagged
## is_customer_account — for UI that lets the player browse/pick an
## account (currently just the Teller screen's dropdown when no customer
## is being served) without it accumulating every auto-created customer
## account over a play session. Accounts created for queue customers still
## live in `accounts` and still work normally (see Account.
## is_customer_account) — this is purely a filtered view for that one UI.
func get_browsable_accounts() -> Array[Account]:
	var browsable: Array[Account] = []
	for existing_account in accounts:
		if not existing_account.is_customer_account:
			browsable.append(existing_account)
	return browsable

func create_account(customer_name: String, starting_balance_cents: int = 0) -> Account:
	var new_account := Account.new()
	new_account.customer_name = customer_name
	new_account.balance_cents = starting_balance_cents
	accounts.append(new_account)
	accounts_changed.emit()
	return new_account

## First match by customer_name, or null if none found. Names aren't
## guaranteed unique (two customers could share a name), so this is a
## convenience lookup, not a stand-in for an account number — callers that
## already hold an Account reference (e.g. via OptionButton selection)
## should keep using that reference directly.
##
## staff_line picks the namespace: false (the default, used by the player's
## line) never matches a staff-line account, and true (NpcCustomerLine)
## only matches staff-line accounts — see Account.is_staff_line_account.
func find_account_by_name(customer_name: String, staff_line: bool = false) -> Account:
	for existing_account in accounts:
		if existing_account.customer_name == customer_name and existing_account.is_staff_line_account == staff_line:
			return existing_account
	return null

func deposit(account: Account, amount_cents: int) -> void:
	account.deposit(amount_cents)
	accounts_changed.emit()

func withdraw(account: Account, amount_cents: int) -> bool:
	var success := account.withdraw(amount_cents)
	if success:
		accounts_changed.emit()
	return success
