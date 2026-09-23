extends Control
class_name TellerScreen

## Teller desk task screen. Owns its own show/hide + pause behavior so
## callers (teller_room.gd) just say "show this" — they don't need to
## know that showing it also pauses the world.
##
## Each shift's ending drawer count also logs a DecisionRecord to
## HistoryManager for the eventual Branch Manager review (Phase 5) —
## see _prepare_shift_summary().
##
## class_name added (Phase 5e) purely so vault_reconciliation_screen.gd
## can reference PERFECT_COUNT_SCORE/etc. directly — the same
## cross-file constant reuse this screen already does with
## DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD below — rather than
## duplicating the point table a second time.

@onready var main_panel: PanelContainer = $Panel
@onready var close_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/CloseButton
@onready var deposit_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/DepositButton
@onready var withdraw_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/WithdrawButton
@onready var open_account_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/OpenAccountButton
@onready var clock_in_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ClockOutButton
@onready var amount_input: SpinBox = $Panel/VBox/ActionsSection/ActionsVBox/AmountSpinBox
@onready var account_option_button: OptionButton = $Panel/VBox/AccountSection/AccountVBox/AccountOptionButton
@onready var serving_status_label: Label = $Panel/VBox/ServingSection/ServingVBox/ServingStatusLabel
@onready var payment_method_label: Label = $Panel/VBox/ServingSection/ServingVBox/PaymentMethodLabel
@onready var customer_dialogue_panel: PanelContainer = $Panel/VBox/ServingSection/ServingVBox/CustomerDialoguePanel
@onready var customer_dialogue_label: Label = $Panel/VBox/ServingSection/ServingVBox/CustomerDialoguePanel/CustomerDialogueLabel
@onready var account_label: Label = $Panel/VBox/AccountSection/AccountVBox/AccountLabel
@onready var balance_label: Label = $Panel/VBox/AccountSection/AccountVBox/BalanceLabel
@onready var error_label: Label = $Panel/VBox/ActionsSection/ActionsVBox/ErrorLabel

@onready var complaint_panel: PanelContainer = $ComplaintPanel
@onready var complaint_label: Label = $ComplaintPanel/VBox/ComplaintLabel
@onready var complaint_responses_container: VBoxContainer = $ComplaintPanel/VBox/ResponsesVBox
@onready var complaint_later_button: Button = $ComplaintPanel/VBox/LaterButton

@onready var open_account_panel: Panel = $OpenAccountPanel
@onready var new_name_input: LineEdit = $OpenAccountPanel/VBox/NameLineEdit
@onready var new_balance_input: SpinBox = $OpenAccountPanel/VBox/StartingBalanceSpinBox
@onready var create_account_button: Button = $OpenAccountPanel/VBox/ButtonsHBox/CreateButton
@onready var cancel_account_button: Button = $OpenAccountPanel/VBox/ButtonsHBox/CancelButton
@onready var new_account_error_label: Label = $OpenAccountPanel/VBox/ErrorLabel

@onready var drawer_count_screen: DrawerCountScreen = $DrawerCountScreen

@onready var corner_total_score_label: Label = $ScoreHudPanel/VBox/TotalScoreLabel
@onready var corner_reputation_label: Label = $ScoreHudPanel/VBox/ReputationLabel
@onready var corner_xp_label: Label = $ScoreHudPanel/VBox/XPLabel
@onready var low_reputation_warning_label: Label = $LowReputationWarningLabel
@onready var loan_officer_unlocked_label: Label = $LoanOfficerUnlockedLabel
@onready var branch_manager_unlocked_label: Label = $BranchManagerUnlockedLabel

@onready var shift_summary_panel: PanelContainer = $ShiftSummaryPanel
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

signal shift_clocked_in
signal shift_clocked_out

## Emitted right after a deposit or withdrawal actually succeeds (not on
## the validation-error early-returns below). teller_room.gd listens for
## this (see _on_teller_transaction_completed()) to decide when the
## front-of-queue customer has been served: serving is "did a transaction
## for them," not "the player closed the screen for any reason," so
## checking a balance or clocking in/out doesn't silently remove a waiting
## customer.
signal transaction_completed

## Phase 6i: emitted whenever the player closes this screen (currently only
## via the Close button — see hide_screen()). teller_room.gd listens for
## this to trigger a served customer's farewell + walk-away sequence at the
## right moment: after their transaction (transaction_completed, above) but
## not until the player actually leaves the desk.
signal screen_closed

## The account currently selected in account_option_button. Account data
## itself lives in AccountManager (shared with the ATM) — see
## _refresh_account_list()/_on_account_option_selected().
var account: Account

## Whoever set_serving_customer() was last called with (null if nobody's
## waiting) — kept so deposit/withdraw know which payment method to apply
## (Phase 6e), since account selection isn't otherwise tied to the
## customer currently being served.
var _serving_customer: CustomerNPC = null

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

## Minimum real time (Time.get_ticks_msec(), unaffected by pause) a shift
## must stay clocked in before clocking out is allowed — without this, an
## instant clock-in/clock-out with a matching drawer count was a free
## Score/XP farm completely decoupled from actually serving anyone. 45s is
## long enough that a customer spawn (every 20s, see CustomerQueue) has a
## real chance to land before a shift can end, short enough to not feel
## like an artificial waiting room. First-pass value, tune after
## playtesting.
const MIN_SHIFT_DURATION_SECONDS: float = 45.0

const PERFECT_COUNT_SCORE: int = 10
const MINOR_DISCREPANCY_SCORE: int = 5
const MAJOR_DISCREPANCY_SCORE: int = -5

const PERFECT_COUNT_REPUTATION: int = 2
const MINOR_DISCREPANCY_REPUTATION: int = 0
const MAJOR_DISCREPANCY_REPUTATION: int = -5

## Phase 6e: small chance a card transaction is declined, checked at
## deposit/withdraw time — same Score/Reputation/XP either way, this just
## blocks the transaction from applying (see _on_deposit_button_pressed()/
## _on_withdraw_button_pressed()). Cash transactions never decline this
## way — only the existing insufficient-funds check applies to them.
const CARD_DECLINE_CHANCE: float = 0.1

## How long Deposit/Withdraw stay disabled after a card decline. Without
## this, a 10% decline chance is trivial to just re-roll by spamming the
## button — a brief lockout makes a decline read as "wait a moment,"
## consistent with what a real declined-card retry feels like, rather than
## a rapid-fire error message.
const CARD_DECLINE_COOLDOWN_SECONDS: float = 1.5

var shift_state: ShiftState = ShiftState.CLOCKED_OUT
var pending_drawer_count_purpose: DrawerCountPurpose = DrawerCountPurpose.NONE
var awaiting_summary_reveal: bool = false

## True for CARD_DECLINE_COOLDOWN_SECONDS after a card decline — see
## _start_card_decline_cooldown(). Folded into _update_shift_controls()'s
## deposit/withdraw disabled check rather than set directly, so a clock-out
## that happens to land mid-cooldown doesn't get overridden back to enabled
## when the cooldown timer finishes.
var _card_decline_on_cooldown: bool = false

var shift_start_time: String = ""
var shift_start_balance: float = 0.0

## Real-time clock-in timestamp for MIN_SHIFT_DURATION_SECONDS, separate
## from shift_start_time above (a display-only formatted string) since
## measuring elapsed time from a formatted datetime string isn't reliable.
var _shift_start_ticks_msec: int = 0

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
	complaint_later_button.pressed.connect(_on_complaint_later_button_pressed)
	account_option_button.item_selected.connect(_on_account_option_selected)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)
	drawer_count_screen.count_submitted.connect(_on_drawer_count_submitted)
	drawer_count_screen.closed.connect(_on_drawer_count_screen_closed)
	CurrencySpinBoxFormat.apply(amount_input)
	CurrencySpinBoxFormat.apply(new_balance_input)
	ScoreManager.score_changed.connect(_on_total_score_changed)
	ReputationManager.reputation_changed.connect(_on_reputation_changed)
	XPManager.xp_changed.connect(_on_total_xp_changed)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)

	account = AccountManager.get_accounts()[0]
	_refresh_account_list()
	_refresh_display()
	_update_shift_controls()
	_on_total_score_changed(ScoreManager.total_score)
	_on_reputation_changed(ReputationManager.reputation)
	_on_total_xp_changed(XPManager.total_xp)
	if XPManager.is_loan_officer_unlocked:
		_on_loan_officer_unlocked()
	if XPManager.is_branch_manager_unlocked:
		_on_branch_manager_unlocked()

## serving_customer is whoever teller_room.gd found at the front of the
## queue at interaction time (null if nobody's waiting) — purely for the
## "Serving: X" / "No customer waiting." display below; this screen doesn't
## otherwise know or care about the queue.
##
## Phase 6c: an unresolved complaint customer gets the complaint panel
## instead of the normal main panel — see _show_complaint_panel().
func show_screen(serving_customer: CustomerNPC = null) -> void:
	set_serving_customer(serving_customer)
	visible = true
	get_tree().paused = true

	## Accounts are shared with the ATM via AccountManager, so a deposit/
	## withdrawal/new account made there since this screen was last shown
	## needs to be reflected here immediately.
	_refresh_account_list()
	_refresh_display()

	if serving_customer != null and serving_customer.complaint != null and not serving_customer.complaint_resolved:
		_show_complaint_panel(serving_customer)
	else:
		_show_main_panel()

## Also called by teller_room.gd right after a served customer is popped
## from the queue, so the labels reflect that service is done rather than
## still naming/quoting someone who already left. The dialogue line was
## assigned once, at spawn (see CustomerQueue._spawn_customer()) — this just
## displays whatever the customer was already carrying, it never rerolls it.
##
## Phase 6h: also switches the selected account to this customer's own one
## (set at spawn, see CustomerQueue._get_or_create_customer_account()) so
## the dropdown/balance shown while serving them is theirs, not whatever
## account happened to be selected before — show_screen() calls
## _refresh_account_list()/_refresh_display() right after this, which is
## what actually reflects the switch in the UI.
func set_serving_customer(customer: CustomerNPC) -> void:
	_serving_customer = customer
	if customer != null:
		serving_status_label.text = "Serving: %s" % customer.display_name
		payment_method_label.visible = true
		payment_method_label.text = "Payment Method: %s" % _payment_method_display_name(customer.payment_method)
		customer_dialogue_panel.visible = customer.dialogue_line != null
		if customer.dialogue_line != null:
			customer_dialogue_label.text = "\"%s\"" % customer.dialogue_line.text
		if customer.account != null:
			account = customer.account
	else:
		serving_status_label.text = "No customer waiting."
		payment_method_label.visible = false
		customer_dialogue_panel.visible = false

func _payment_method_display_name(payment_method: ShiftTransaction.PaymentMethod) -> String:
	if payment_method == ShiftTransaction.PaymentMethod.CARD:
		return "Card"
	return "Cash"

func hide_screen() -> void:
	visible = false
	get_tree().paused = false
	screen_closed.emit()

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_deposit_button_pressed() -> void:
	var amount := amount_input.value
	if amount <= 0.0:
		error_label.text = "Enter a valid amount."
		error_label.visible = true
		return
	if _current_payment_method() == ShiftTransaction.PaymentMethod.CARD and randf() < CARD_DECLINE_CHANCE:
		_start_card_decline_cooldown()
		return
	error_label.visible = false
	AccountManager.deposit(account, amount)
	_record_transaction(ShiftTransaction.Type.DEPOSIT, amount)
	_refresh_display()
	transaction_completed.emit()

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
	if _current_payment_method() == ShiftTransaction.PaymentMethod.CARD and randf() < CARD_DECLINE_CHANCE:
		_start_card_decline_cooldown()
		return
	error_label.visible = false
	AccountManager.withdraw(account, amount)
	_record_transaction(ShiftTransaction.Type.WITHDRAWAL, amount)
	_refresh_display()
	transaction_completed.emit()

## Disables Deposit/Withdraw for CARD_DECLINE_COOLDOWN_SECONDS instead of
## just showing an error — otherwise the 10% decline chance is trivial to
## re-roll by spamming the button, which reads as broken/spammy rather
## than an actual declined card.
func _start_card_decline_cooldown() -> void:
	error_label.text = "Card Declined. Please wait a moment before retrying."
	error_label.visible = true
	_card_decline_on_cooldown = true
	_update_shift_controls()
	get_tree().create_timer(CARD_DECLINE_COOLDOWN_SECONDS).timeout.connect(_on_card_decline_cooldown_finished)

## Goes through _update_shift_controls() rather than setting
## deposit_button/withdraw_button.disabled directly, so a shift that ended
## while this cooldown was still running (clock-out mid-cooldown) doesn't
## get its buttons incorrectly re-enabled here.
func _on_card_decline_cooldown_finished() -> void:
	_card_decline_on_cooldown = false
	_update_shift_controls()

## The customer currently being served determines payment method for
## whatever deposit/withdraw the teller performs next — account selection
## isn't otherwise linked to who's being served (see _serving_customer's
## doc comment). No customer waiting defaults to Cash, matching the
## pre-6e behavior for every transaction.
func _current_payment_method() -> ShiftTransaction.PaymentMethod:
	if _serving_customer != null:
		return _serving_customer.payment_method
	return ShiftTransaction.PaymentMethod.CASH

func _refresh_display() -> void:
	account_label.text = account.customer_name
	balance_label.text = "Balance: $%.2f" % account.balance

func _show_main_panel() -> void:
	complaint_panel.visible = false
	open_account_panel.visible = false
	shift_summary_panel.visible = false
	main_panel.visible = true

## Shows customer's complaint text and their response options, replacing
## the main panel until the player picks one (see
## _on_complaint_response_selected()) or defers it via the Later button
## (see _on_complaint_later_button_pressed()). Buttons are built fresh
## each time, the same throwaway-Button-per-choice pattern
## interview_screen.gd uses for its answer choices.
func _show_complaint_panel(customer: CustomerNPC) -> void:
	main_panel.visible = false
	open_account_panel.visible = false
	shift_summary_panel.visible = false
	complaint_panel.visible = true

	complaint_label.text = customer.complaint.complaint_text
	for child in complaint_responses_container.get_children():
		child.queue_free()
	for response in customer.complaint.responses:
		var button := Button.new()
		button.text = response.text
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_on_complaint_response_selected.bind(customer, response))
		complaint_responses_container.add_child(button)

## Reputation-only consequence, per Phase 6c scope — no Score/XP change.
## Logged to HistoryManager the same way _prepare_shift_summary() logs a
## drawer count, just under a complaint-flavored description/grade label.
func _on_complaint_response_selected(customer: CustomerNPC, response: ComplaintResponse) -> void:
	ReputationManager.add_reputation(response.score)
	var grade_label := _complaint_grade_label(response.score)
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"Complaint: \"%s\" — response: \"%s\"" % [customer.complaint.complaint_text, response.text],
		grade_label
	)
	customer.complaint_resolved = true
	_show_main_panel()

## Backs out of the complaint panel without resolving it — no reputation
## change, no HistoryManager entry. complaint_resolved stays false, so
## this same customer's complaint panel shows again the next time they're
## served, the same as closing the whole screen without doing a
## transaction doesn't silently drop them from the queue (see
## teller_room.gd).
func _on_complaint_later_button_pressed() -> void:
	_show_main_panel()

## Same "grade in a word" vocabulary _discrepancy_result_label() uses for
## drawer counts, just keyed off response score sign rather than a
## discrepancy bucket.
func _complaint_grade_label(score: int) -> String:
	if score > 0:
		return "Great"
	elif score == 0:
		return "Neutral"
	else:
		return "Poor"

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

	account = AccountManager.create_account(new_name, new_balance_input.value)

	error_label.visible = false
	_show_main_panel()
	_refresh_account_list()
	_refresh_display()

## Phase 6j: lists AccountManager.get_browsable_accounts() rather than
## get_accounts() — the demo account plus anything opened via "Open New
## Account," not every auto-created Teller queue customer account (see
## Account.is_customer_account) — so this dropdown stays a short, stable
## list instead of growing with every customer served over a session.
## _browsable_accounts is cached so _on_account_option_selected() below
## indexes into the exact same list this just populated the dropdown
## from. While a customer is being served, `account` is their own
## (non-browsable) account — select() below then finds no match (-1),
## which just leaves the dropdown showing no selection; the served
## customer's name/balance are still shown correctly via _refresh_display(),
## driven by `account` directly rather than by dropdown selection.
var _browsable_accounts: Array[Account] = []

func _refresh_account_list() -> void:
	_browsable_accounts = AccountManager.get_browsable_accounts()
	account_option_button.clear()
	for i in _browsable_accounts.size():
		account_option_button.add_item(_browsable_accounts[i].customer_name, i)
	account_option_button.select(_browsable_accounts.find(account))

func _on_account_option_selected(index: int) -> void:
	account = _browsable_accounts[index]
	_refresh_display()

func _update_shift_controls() -> void:
	var clocked_in := shift_state == ShiftState.CLOCKED_IN
	clock_in_button.visible = not clocked_in
	clock_out_button.visible = clocked_in
	deposit_button.disabled = not clocked_in or _card_decline_on_cooldown
	withdraw_button.disabled = not clocked_in or _card_decline_on_cooldown

func _record_transaction(type: ShiftTransaction.Type, amount: float) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	var transaction := ShiftTransaction.new()
	transaction.type = type
	transaction.amount = amount
	transaction.account_name = account.customer_name
	transaction.timestamp = Time.get_datetime_string_from_system()
	transaction.payment_method = _current_payment_method()
	shift_transactions.append(transaction)

## Card transactions are excluded here (Phase 6e) — no physical cash
## changed hands, so they shouldn't shift what the drawer count is
## expected to hold. They still count toward
## shift_total_transactions_label's total below and still applied to the
## account balance in _on_deposit_button_pressed()/
## _on_withdraw_button_pressed() — only this drawer math skips them.
func _calculate_expected_ending_balance() -> float:
	var total_deposits := 0.0
	var total_withdrawals := 0.0
	for transaction in shift_transactions:
		if transaction.payment_method != ShiftTransaction.PaymentMethod.CASH:
			continue
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
	var elapsed_seconds := (Time.get_ticks_msec() - _shift_start_ticks_msec) / 1000.0
	if elapsed_seconds < MIN_SHIFT_DURATION_SECONDS:
		error_label.text = "Shift just started — come back later."
		error_label.visible = true
		return
	error_label.visible = false
	pending_drawer_count_purpose = DrawerCountPurpose.ENDING
	main_panel.visible = false
	drawer_count_screen.show_screen(_calculate_expected_ending_balance(), "Ending Drawer Count")

## Fires as soon as "Submit Count" is pressed on the drawer count screen
## — that screen is still open at this point, showing its own count
## results, so we just record the outcome here and let the player close
## it in their own time. pending_drawer_count_purpose is what tells us
## whether this was the clock-in count or the clock-out count, since
## both flow through this same signal.
##
## pending_drawer_count_purpose doubles as this handler's one-shot
## consumption guard: it's set to NONE the moment a submitted count has
## been acted on, and the guard below is what makes that explicit —
## DrawerCountScreen doesn't disable its own Submit button, so nothing
## stops the player clicking it again on the same still-open screen; this
## is what keeps a repeat click from re-running _begin_shift()/
## _prepare_shift_summary() (and reapplying Score/Reputation/XP) a second
## time for the same count.
func _on_drawer_count_submitted(total: float) -> void:
	if pending_drawer_count_purpose == DrawerCountPurpose.NONE:
		return
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
	_shift_start_ticks_msec = Time.get_ticks_msec()
	shift_transactions.clear()
	_card_decline_on_cooldown = false
	_update_shift_controls()
	shift_clocked_in.emit()

## Same "Perfect Count!"/"Minor Discrepancy"/"Major Discrepancy" buckets
## DrawerCountScreen's status label shows, so this reuses its
## MINOR_DISCREPANCY_THRESHOLD constant rather than redefining the ±500
## cutoff a second time. Score and Reputation both derive from this one
## categorization instead of each re-checking the discrepancy value.
## excess_bills is how many more bills the player entered in the ending
## count than the minimum possible for that total (see DrawerCountScreen.
## get_excess_bill_count()) — a correct total no longer grades Perfect on
## its own if the bill breakdown behind it is implausible.
func _categorize_discrepancy(discrepancy: float, excess_bills: int) -> DiscrepancyResult:
	if discrepancy == 0.0 and excess_bills <= DrawerCountScreen.PERFECT_BILL_COUNT_TOLERANCE:
		return DiscrepancyResult.PERFECT
	elif abs(discrepancy) <= DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD and excess_bills <= DrawerCountScreen.MINOR_BILL_COUNT_TOLERANCE:
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

## Short label for HistoryManager — same Perfect/Minor/Major vocabulary
## DrawerCountScreen's status label and this screen's own scoring already
## use, just without the "Count"/"Discrepancy" suffix.
func _discrepancy_result_label(discrepancy_result: DiscrepancyResult) -> String:
	match discrepancy_result:
		DiscrepancyResult.PERFECT:
			return "Perfect"
		DiscrepancyResult.MINOR:
			return "Minor"
		_:
			return "Major"

func _prepare_shift_summary(ending_total: float) -> void:
	var expected := _calculate_expected_ending_balance()
	var discrepancy := ending_total - expected
	var shift_end_time := Time.get_datetime_string_from_system()
	var discrepancy_result := _categorize_discrepancy(discrepancy, drawer_count_screen.get_excess_bill_count())
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

	var discrepancy_label := _discrepancy_result_label(discrepancy_result)
	HistoryManager.add_record(DecisionRecord.Role.TELLER, "Drawer count: %s (discrepancy $%.2f)" % [discrepancy_label, discrepancy], discrepancy_label)

	shift_state = ShiftState.CLOCKED_OUT
	awaiting_summary_reveal = true
	_update_shift_controls()
	shift_clocked_out.emit()

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

## Same reasoning as _on_loan_officer_unlocked() above, one tier up.
func _on_branch_manager_unlocked() -> void:
	branch_manager_unlocked_label.visible = true
