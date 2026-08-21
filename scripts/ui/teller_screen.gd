extends Control

## Teller desk task screen. Owns its own show/hide + pause behavior so
## callers (teller_room.gd) just say "show this" — they don't need to
## know that showing it also pauses the world.

@onready var main_panel: Panel = $Panel
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var deposit_button: Button = $Panel/VBox/DepositButton
@onready var withdraw_button: Button = $Panel/VBox/WithdrawButton
@onready var open_account_button: Button = $Panel/VBox/OpenAccountButton
@onready var clock_in_button: Button = $Panel/VBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ClockOutButton
@onready var amount_input: SpinBox = $Panel/VBox/AmountSpinBox
@onready var account_option_button: OptionButton = $Panel/VBox/AccountOptionButton
@onready var account_label: Label = $Panel/VBox/AccountLabel
@onready var balance_label: Label = $Panel/VBox/BalanceLabel
@onready var error_label: Label = $Panel/VBox/ErrorLabel

@onready var open_account_panel: Panel = $OpenAccountPanel
@onready var new_name_input: LineEdit = $OpenAccountPanel/VBox/NameLineEdit
@onready var new_balance_input: SpinBox = $OpenAccountPanel/VBox/StartingBalanceSpinBox
@onready var create_account_button: Button = $OpenAccountPanel/VBox/ButtonsHBox/CreateButton
@onready var cancel_account_button: Button = $OpenAccountPanel/VBox/ButtonsHBox/CancelButton
@onready var new_account_error_label: Label = $OpenAccountPanel/VBox/ErrorLabel

@onready var drawer_count_screen: DrawerCountScreen = $DrawerCountScreen

@onready var corner_total_score_label: Label = $TotalScoreLabel
@onready var corner_reputation_label: Label = $ReputationLabel
@onready var corner_xp_label: Label = $XPLabel
@onready var low_reputation_warning_label: Label = $LowReputationWarningLabel
@onready var loan_officer_unlocked_label: Label = $LoanOfficerUnlockedLabel

@onready var shift_summary_panel: Panel = $ShiftSummaryPanel
@onready var shift_start_time_label: Label = $ShiftSummaryPanel/VBox/StartTimeLabel
@onready var shift_end_time_label: Label = $ShiftSummaryPanel/VBox/EndTimeLabel
@onready var shift_total_transactions_label: Label = $ShiftSummaryPanel/VBox/TotalTransactionsLabel
@onready var shift_final_discrepancy_label: Label = $ShiftSummaryPanel/VBox/FinalDiscrepancyLabel
@onready var shift_score_label: Label = $ShiftSummaryPanel/VBox/ShiftScoreLabel
@onready var shift_total_score_label: Label = $ShiftSummaryPanel/VBox/TotalScoreLabel
@onready var shift_xp_label: Label = $ShiftSummaryPanel/VBox/ShiftXPLabel
@onready var shift_total_xp_label: Label = $ShiftSummaryPanel/VBox/TotalXPLabel
@onready var shift_reputation_label: Label = $ShiftSummaryPanel/VBox/ReputationLabel
@onready var shift_summary_done_button: Button = $ShiftSummaryPanel/VBox/DoneButton

## All accounts opened so far. A flat list (not keyed by name) because
## customer names aren't guaranteed unique — once accounts get a real
## account number, this is where a Dictionary[int, Account] keyed by
## that number would replace the linear-scan lookup.
var accounts: Array[Account] = []
var account: Account

## Shift state: just an enum plus a couple of timestamps/floats, not a
## dedicated state-machine class — there are only two states and one
## legal transition each way (clock in / clock out), both driven by the
## same drawer-count screen. DRAWER_COUNT_PURPOSE tells the shared
## count_submitted handler which transition to run, since both clock-in
## and clock-out route through the same screen and signal.
enum ShiftState { CLOCKED_OUT, CLOCKED_IN }
enum DrawerCountPurpose { NONE, STARTING, ENDING }

## The three buckets a clock-out discrepancy falls into. Score and
## Reputation both react to the same bucket, so this is computed once
## by _categorize_discrepancy() and handed to both, rather than each
## re-checking the discrepancy value against the thresholds itself.
enum DiscrepancyResult { PERFECT, MINOR, MAJOR }

const STARTING_EXPECTED_BALANCE: float = 50000.0

const PERFECT_COUNT_SCORE: int = 10
const MINOR_DISCREPANCY_SCORE: int = 5
const MAJOR_DISCREPANCY_SCORE: int = -5

const PERFECT_COUNT_REPUTATION: int = 2
const MINOR_DISCREPANCY_REPUTATION: int = 0
const MAJOR_DISCREPANCY_REPUTATION: int = -5

var shift_state: ShiftState = ShiftState.CLOCKED_OUT
var pending_drawer_count_purpose: DrawerCountPurpose = DrawerCountPurpose.NONE
var awaiting_summary_reveal: bool = false

var shift_start_time: String = ""
var shift_start_balance: float = 0.0

## Every deposit/withdrawal made since clock-in. This is the source of
## truth for both the clock-out "expected balance" math (starting
## balance + deposits - withdrawals) and, later, shift scoring — so it
## records each transaction individually rather than just running
## tallies, in case scoring ever needs to look at them one at a time.
var shift_transactions: Array[ShiftTransaction] = []

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	deposit_button.pressed.connect(_on_deposit_button_pressed)
	withdraw_button.pressed.connect(_on_withdraw_button_pressed)
	open_account_button.pressed.connect(_on_open_account_button_pressed)
	create_account_button.pressed.connect(_on_create_account_button_pressed)
	cancel_account_button.pressed.connect(_on_cancel_account_button_pressed)
	account_option_button.item_selected.connect(_on_account_option_selected)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)
	drawer_count_screen.count_submitted.connect(_on_drawer_count_submitted)
	drawer_count_screen.closed.connect(_on_drawer_count_screen_closed)
	ScoreManager.score_changed.connect(_on_total_score_changed)
	ReputationManager.reputation_changed.connect(_on_reputation_changed)
	XPManager.xp_changed.connect(_on_total_xp_changed)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)

	account = Account.new()
	account.customer_name = "Johnathan Jamestar"
	account.balance = 1000.0
	accounts.append(account)
	_refresh_account_list()
	_refresh_display()
	_update_shift_controls()
	_on_total_score_changed(ScoreManager.total_score)
	_on_reputation_changed(ReputationManager.reputation)
	_on_total_xp_changed(XPManager.total_xp)
	if XPManager.is_loan_officer_unlocked:
		_on_loan_officer_unlocked()

func show_screen() -> void:
	visible = true
	get_tree().paused = true
	_show_main_panel()

func hide_screen() -> void:
	visible = false
	get_tree().paused = false

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_deposit_button_pressed() -> void:
	var amount := amount_input.value
	if amount <= 0.0:
		error_label.text = "Enter a valid amount."
		error_label.visible = true
		return
	error_label.visible = false
	account.deposit(amount)
	_record_transaction(ShiftTransaction.Type.DEPOSIT, amount)
	_refresh_display()

func _on_withdraw_button_pressed() -> void:
	var amount := amount_input.value
	if amount <= 0.0:
		error_label.text = "Enter a valid amount."
		error_label.visible = true
		return
	if not account.can_withdraw(amount):
		error_label.text = "Insufficient funds."
		error_label.visible = true
		return
	error_label.visible = false
	account.withdraw(amount)
	_record_transaction(ShiftTransaction.Type.WITHDRAWAL, amount)
	_refresh_display()

func _refresh_display() -> void:
	account_label.text = account.customer_name
	balance_label.text = "Balance: $%.2f" % account.balance

func _show_main_panel() -> void:
	open_account_panel.visible = false
	shift_summary_panel.visible = false
	main_panel.visible = true

func _on_open_account_button_pressed() -> void:
	new_name_input.text = ""
	new_balance_input.value = 0.0
	new_account_error_label.visible = false
	main_panel.visible = false
	open_account_panel.visible = true

func _on_cancel_account_button_pressed() -> void:
	_show_main_panel()

func _on_create_account_button_pressed() -> void:
	var new_name := new_name_input.text.strip_edges()
	if new_name.is_empty():
		new_account_error_label.text = "Please enter a customer name."
		new_account_error_label.visible = true
		return

	var new_account := Account.new()
	new_account.customer_name = new_name
	new_account.balance = new_balance_input.value
	accounts.append(new_account)
	account = new_account

	error_label.visible = false
	_show_main_panel()
	_refresh_account_list()
	_refresh_display()

func _refresh_account_list() -> void:
	account_option_button.clear()
	for i in accounts.size():
		account_option_button.add_item(accounts[i].customer_name, i)
	account_option_button.select(accounts.find(account))

func _on_account_option_selected(index: int) -> void:
	account = accounts[index]
	_refresh_display()

func _update_shift_controls() -> void:
	var clocked_in := shift_state == ShiftState.CLOCKED_IN
	clock_in_button.visible = not clocked_in
	clock_out_button.visible = clocked_in
	deposit_button.disabled = not clocked_in
	withdraw_button.disabled = not clocked_in

func _record_transaction(type: ShiftTransaction.Type, amount: float) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	var transaction := ShiftTransaction.new()
	transaction.type = type
	transaction.amount = amount
	transaction.account_name = account.customer_name
	transaction.timestamp = Time.get_datetime_string_from_system()
	shift_transactions.append(transaction)

func _calculate_expected_ending_balance() -> float:
	var total_deposits := 0.0
	var total_withdrawals := 0.0
	for transaction in shift_transactions:
		if transaction.type == ShiftTransaction.Type.DEPOSIT:
			total_deposits += transaction.amount
		else:
			total_withdrawals += transaction.amount
	return shift_start_balance + total_deposits - total_withdrawals

func _on_clock_in_button_pressed() -> void:
	pending_drawer_count_purpose = DrawerCountPurpose.STARTING
	main_panel.visible = false
	drawer_count_screen.show_screen(STARTING_EXPECTED_BALANCE, "Starting Drawer Count")

func _on_clock_out_button_pressed() -> void:
	pending_drawer_count_purpose = DrawerCountPurpose.ENDING
	main_panel.visible = false
	drawer_count_screen.show_screen(_calculate_expected_ending_balance(), "Ending Drawer Count")

## Fires as soon as "Submit Count" is pressed on the drawer count screen
## — that screen is still open at this point, showing its own count
## results, so we just record the outcome here and let the player close
## it in their own time. pending_drawer_count_purpose is what tells us
## whether this was the clock-in count or the clock-out count, since
## both flow through this same signal.
func _on_drawer_count_submitted(total: float) -> void:
	match pending_drawer_count_purpose:
		DrawerCountPurpose.STARTING:
			_begin_shift(total)
		DrawerCountPurpose.ENDING:
			_prepare_shift_summary(total)
	pending_drawer_count_purpose = DrawerCountPurpose.NONE

## Fires when the player actually closes the drawer count screen —
## separate from count_submitted because the player may sit and look at
## the count results for a while first. What we reveal underneath
## depends on which shift transition just happened.
func _on_drawer_count_screen_closed() -> void:
	if awaiting_summary_reveal:
		awaiting_summary_reveal = false
		shift_summary_panel.visible = true
	else:
		_show_main_panel()

func _begin_shift(starting_total: float) -> void:
	shift_state = ShiftState.CLOCKED_IN
	shift_start_balance = starting_total
	shift_start_time = Time.get_datetime_string_from_system()
	shift_transactions.clear()
	_update_shift_controls()

## Same "Perfect Count!"/"Minor Discrepancy"/"Major Discrepancy" buckets
## DrawerCountScreen's status label shows, so this reuses its
## MINOR_DISCREPANCY_THRESHOLD constant rather than redefining the ±500
## cutoff a second time. Score and Reputation both derive from this one
## categorization instead of each re-checking the discrepancy value.
func _categorize_discrepancy(discrepancy: float) -> DiscrepancyResult:
	if discrepancy == 0.0:
		return DiscrepancyResult.PERFECT
	elif abs(discrepancy) <= DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD:
		return DiscrepancyResult.MINOR
	else:
		return DiscrepancyResult.MAJOR

func _calculate_shift_score(discrepancy_result: DiscrepancyResult) -> int:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return PERFECT_COUNT_SCORE
		DiscrepancyResult.MINOR:
			return MINOR_DISCREPANCY_SCORE
		_:
			return MAJOR_DISCREPANCY_SCORE

func _calculate_reputation_delta(discrepancy_result: DiscrepancyResult) -> int:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return PERFECT_COUNT_REPUTATION
		DiscrepancyResult.MINOR:
			return MINOR_DISCREPANCY_REPUTATION
		_:
			return MAJOR_DISCREPANCY_REPUTATION

func _prepare_shift_summary(ending_total: float) -> void:
	var expected := _calculate_expected_ending_balance()
	var discrepancy := ending_total - expected
	var shift_end_time := Time.get_datetime_string_from_system()
	var discrepancy_result := _categorize_discrepancy(discrepancy)
	var shift_score := _calculate_shift_score(discrepancy_result)
	var reputation_delta := _calculate_reputation_delta(discrepancy_result)

	shift_start_time_label.text = "Start Time: %s" % shift_start_time
	shift_end_time_label.text = "End Time: %s" % shift_end_time
	shift_total_transactions_label.text = "Total Transactions: %d" % shift_transactions.size()
	shift_final_discrepancy_label.text = "Final Discrepancy: $%.2f" % discrepancy
	shift_score_label.text = "Shift Score: %+d" % shift_score

	ScoreManager.add_shift_score(shift_score)
	shift_total_score_label.text = "Total Score: %d" % ScoreManager.total_score

	ReputationManager.add_reputation(reputation_delta)
	shift_reputation_label.text = "Reputation: %+d (now %d)" % [reputation_delta, ReputationManager.reputation]

	var shift_xp := shift_score * XPManager.XP_PER_SCORE_POINT
	XPManager.add_shift_xp(shift_score)
	shift_xp_label.text = "Shift XP: %+d" % shift_xp
	shift_total_xp_label.text = "Total XP: %d" % XPManager.total_xp

	shift_state = ShiftState.CLOCKED_OUT
	awaiting_summary_reveal = true
	_update_shift_controls()

func _on_shift_summary_done_pressed() -> void:
	_show_main_panel()

func _on_total_score_changed(new_total: int) -> void:
	corner_total_score_label.text = "Total Score: %d" % new_total

func _on_reputation_changed(new_reputation: int) -> void:
	corner_reputation_label.text = "Reputation: %d" % new_reputation
	low_reputation_warning_label.visible = new_reputation <= ReputationManager.LOW_REPUTATION_THRESHOLD

func _on_total_xp_changed(new_total: int) -> void:
	corner_xp_label.text = "XP: %d" % new_total

## Fires once, the first time XPManager's unlock condition is met — see
## XPManager.is_loan_officer_unlocked for why this never gets hidden
## again afterward.
func _on_loan_officer_unlocked() -> void:
	loan_officer_unlocked_label.visible = true
