extends Control
class_name ATMScreen

## Self-service ATM screen (Phase 6f) — lets the player manage a bank
## account as a customer, independent of the Teller/Loan Officer/Branch
## Manager job roles and their shift state. teller_room.gd opens this
## unconditionally off atm.gd's interacted signal, no unlock/clock-in
## check at all (see that file).
##
## Deposit/withdraw reuse Account's deposit()/withdraw()/can_withdraw()
## rules directly (Fix 4) so a self-service transaction is never more
## permissive than a teller-assisted one — see _on_withdraw_button_pressed().
##
## Reads/writes accounts through AccountManager, the same shared ledger
## TellerScreen uses — so an account opened or modified at either desk is
## immediately consistent at the other. The demo account is seeded once,
## in AccountManager itself, not here.
##
## No account-opening here at all, unlike TellerScreen — real ATMs only
## work with existing accounts; opening one requires a teller to verify
## ID and paperwork in person.
##
## No drawer/vault interaction at all — real ATMs are restocked and
## balanced separately from a teller's drawer, so this never touches
## DrawerCountScreen or vault reconciliation math.
##
## Manages its own pause state defensively, same pattern as
## drawer_count_screen.gd/loan_review_screen.gd (_paused_by_self tracks
## whether *this* screen was the one that paused, so hide_screen() never
## unpauses a tree something else still needs paused).

## Real ATMs cap how much cash a single withdrawal can dispense, unlike an
## in-person teller who can hand over any amount the drawer holds. Deposits
## aren't capped — envelope/check deposits don't have the same physical
## cash-dispensing constraint.
const ATM_WITHDRAWAL_LIMIT: float = 500.0

@onready var account_option_button: OptionButton = $Panel/VBox/AccountSection/AccountVBox/AccountOptionButton
@onready var account_label: Label = $Panel/VBox/AccountSection/AccountVBox/AccountLabel
@onready var balance_label: Label = $Panel/VBox/AccountSection/AccountVBox/BalanceLabel
@onready var amount_input: SpinBox = $Panel/VBox/ActionsSection/ActionsVBox/AmountSpinBox
@onready var deposit_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/DepositButton
@onready var withdraw_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/WithdrawButton
@onready var error_label: Label = $Panel/VBox/ActionsSection/ActionsVBox/ErrorLabel
@onready var close_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/CloseButton

var account: Account = null
var _paused_by_self: bool = false

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	deposit_button.pressed.connect(_on_deposit_button_pressed)
	withdraw_button.pressed.connect(_on_withdraw_button_pressed)
	account_option_button.item_selected.connect(_on_account_option_selected)
	CurrencySpinBoxFormat.apply(amount_input)

	_refresh_account_list()
	_refresh_display()

func show_screen() -> void:
	visible = true

	## Accounts are shared with TellerScreen via AccountManager, so a
	## deposit/withdrawal/new account made at the teller desk since this
	## screen was last shown needs to be reflected here immediately.
	_refresh_account_list()
	_refresh_display()

	_paused_by_self = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false

	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

func _on_close_button_pressed() -> void:
	hide_screen()

## No amount ceiling here, unlike withdraw below — see ATM_WITHDRAWAL_LIMIT's
## doc comment for why deposits aren't capped.
func _on_deposit_button_pressed() -> void:
	if account == null:
		return
	var amount := amount_input.value
	if amount <= 0.0:
		error_label.text = "Enter a valid amount."
		error_label.visible = true
		return
	error_label.visible = false
	AccountManager.deposit(account, amount)
	_refresh_display()

func _on_withdraw_button_pressed() -> void:
	if account == null:
		return
	var amount := amount_input.value
	if amount <= 0.0:
		error_label.text = "Enter a valid amount."
		error_label.visible = true
		return
	if amount > ATM_WITHDRAWAL_LIMIT:
		error_label.text = "ATM withdrawal limit is $%.2f." % ATM_WITHDRAWAL_LIMIT
		error_label.visible = true
		return
	if not account.can_withdraw(amount):
		error_label.text = "Insufficient funds."
		error_label.visible = true
		return
	error_label.visible = false
	AccountManager.withdraw(account, amount)
	_refresh_display()

## Balance is just always on display next to whichever account is
## selected — same "Check Balance" UX teller_screen.gd already uses,
## rather than a separate button/action for it. No account selected (the
## account list came back empty) shows a message instead of a blank name
## and balance — this can only happen if AccountManager has never
## seeded/created any account at all.
func _refresh_display() -> void:
	if account == null:
		account_label.text = "No accounts found — visit a teller to open an account."
		balance_label.text = ""
		deposit_button.disabled = true
		withdraw_button.disabled = true
		return
	deposit_button.disabled = false
	withdraw_button.disabled = false
	account_label.text = account.customer_name
	balance_label.text = "Balance: $%.2f" % account.balance

## No account-opening path here (see class doc comment) — this only ever
## selects among AccountManager's existing accounts, never creates one.
func _refresh_account_list() -> void:
	var accounts := AccountManager.get_accounts()
	account_option_button.clear()
	if accounts.is_empty():
		account_option_button.disabled = true
		account = null
		return
	account_option_button.disabled = false
	for i in accounts.size():
		account_option_button.add_item(accounts[i].customer_name, i)
	if account == null or not accounts.has(account):
		account = accounts[0]
	account_option_button.select(accounts.find(account))

func _on_account_option_selected(index: int) -> void:
	account = AccountManager.get_accounts()[index]
	_refresh_display()
