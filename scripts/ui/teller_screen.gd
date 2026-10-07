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
@onready var respond_complaint_button: Button = $Panel/VBox/ServingSection/ServingVBox/RespondComplaintButton
@onready var feedback_label: Label = $Panel/VBox/ActionsSection/ActionsVBox/FeedbackLabel
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
## Warning/unlock labels live in a top-left VBox stack rather than being
## pinned top-center: the main Panel is centered and already fills the full
## viewport height, so anything anchored above it lands on its title. The
## stack sits in the empty margin left of the panel (mirroring ScoreHudPanel
## on the right) and the VBox keeps multiple visible labels from colliding.
@onready var low_reputation_warning_label: Label = $NotificationStack/LowReputationWarningLabel
@onready var loan_officer_unlocked_label: Label = $NotificationStack/LoanOfficerUnlockedLabel
@onready var branch_manager_unlocked_label: Label = $NotificationStack/BranchManagerUnlockedLabel

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
@onready var shift_total_reputation_label: Label = $ShiftSummaryPanel/VBox/TotalReputationLabel
@onready var shift_customer_results_label: Label = $ShiftSummaryPanel/VBox/CustomerResultsLabel
@onready var shift_customer_points_label: Label = $ShiftSummaryPanel/VBox/CustomerPointsLabel
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

## Emitted once the player picks a response to the serving customer's
## complaint. Resolving the complaint IS serving a complaint customer (they
## have no deposit/withdraw request), so teller_room.gd listens for this to
## pop them from the queue the same way transaction_completed does for a
## regular customer.
signal complaint_resolved(customer: CustomerNPC)

## Set by teller_room.gd: returns a short description of this shift's
## remaining customer work (e.g. "2 customers still waiting"), or "" once
## every customer this shift has been handled. This screen doesn't know
## about the queue itself, so clock-out asks through this instead. Left
## unset (e.g. the screen run standalone), clock-out isn't gated.
var remaining_shift_work: Callable

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

const PERFECT_COUNT_SCORE: int = 10
const MINOR_DISCREPANCY_SCORE: int = 5
const MAJOR_DISCREPANCY_SCORE: int = -5

const PERFECT_COUNT_REPUTATION: int = 2
const MINOR_DISCREPANCY_REPUTATION: int = 0
const MAJOR_DISCREPANCY_REPUTATION: int = -5

## Grading for the transaction performed for a customer's stated request
## (see _grade_customer_transaction()). Pitched well below the drawer
## count's +10/+5/-5: a shift has up to CustomerQueue.CUSTOMERS_PER_SHIFT_CAP
## (4) of these, so four correct requests (+8) roughly match one Perfect
## count rather than dwarfing it. A wrong request costs more than a right
## one earns (same asymmetry as Minor +5 vs Major -5 relative to Perfect),
## and its Reputation hit matches a customer abandoning the line (-2,
## teller_room.gd) — still below a dismissive complaint response (-3) or a
## Major count (-5). XP follows the reward only, per the B6 spec: a wrong
## request costs Score and Reputation but doesn't take XP away.
const CUSTOMER_REQUEST_CORRECT_SCORE: int = 2
const CUSTOMER_REQUEST_CORRECT_REPUTATION: int = 0
const CUSTOMER_REQUEST_WRONG_SCORE: int = -3
const CUSTOMER_REQUEST_WRONG_REPUTATION: int = -2

const FEEDBACK_GOOD_COLOR: Color = Color(0.3, 1, 0.3, 1)
const FEEDBACK_BAD_COLOR: Color = Color(1, 0.3, 0.3, 1)
const FEEDBACK_NEUTRAL_COLOR: Color = Color(1, 1, 1, 1)

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

## Always the assigned float (STARTING_EXPECTED_BALANCE), never the
## player's opening count — see _begin_shift().
var shift_start_balance: float = 0.0

## Per-shift customer-service tallies for the shift summary, kept separate
## from the drawer count's points so the summary can show where each came
## from. Points include every customer-driven consequence: graded requests
## (_grade_customer_transaction()), complaint responses
## (_on_complaint_response_selected()) and abandonments
## (note_customer_abandoned()). Reset in _begin_shift().
var _customers_correct: int = 0
var _customers_incorrect: int = 0
var _complaints_resolved: int = 0
var _customers_abandoned: int = 0
var _customer_score: int = 0
var _customer_reputation: int = 0
var _customer_xp: int = 0

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
	respond_complaint_button.pressed.connect(_on_respond_complaint_button_pressed)
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
	feedback_label.visible = false
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
	respond_complaint_button.visible = _has_unresolved_complaint(customer)

## Called by teller_room.gd mid-visit once the current customer has been
## handled, so the screen moves straight on to whoever's next in line (or
## "No customer waiting." if nobody is) without the player closing and
## reopening it. Stays on the main panel either way so the just-shown
## transaction feedback remains visible — a complaint customer can be
## responded to from there via respond_complaint_button.
func advance_to_customer(customer: CustomerNPC) -> void:
	set_serving_customer(customer)
	_refresh_account_list()
	_refresh_display()

func _has_unresolved_complaint(customer: CustomerNPC) -> bool:
	return is_instance_valid(customer) and customer.complaint != null and not customer.complaint_resolved

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
	_grade_customer_transaction(ShiftTransaction.Type.DEPOSIT, amount)
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
	_grade_customer_transaction(ShiftTransaction.Type.WITHDRAWAL, amount)
	transaction_completed.emit()

## The first deposit/withdrawal made while serving a regular (non-complaint)
## customer is their transaction — teller_room.gd moves on to the next
## customer as soon as transaction_completed fires, so there's never a
## second one to grade for the same customer. A wrong transaction isn't
## blocked (it already went through above); it's graded here instead.
## Complaint customers have no request to compare against and are handled
## by resolving the complaint (see _on_complaint_response_selected()).
func _grade_customer_transaction(type: ShiftTransaction.Type, amount: float) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	if not is_instance_valid(_serving_customer) or _serving_customer.complaint != null:
		return
	var customer := _serving_customer
	var type_ok := type == customer.intent_type
	var amount_ok := MoneyMath.to_cents(amount) == MoneyMath.to_cents(customer.intent_amount)
	var account_ok := account == customer.account
	var correct := type_ok and amount_ok and account_ok

	var score_delta := CUSTOMER_REQUEST_CORRECT_SCORE if correct else CUSTOMER_REQUEST_WRONG_SCORE
	var reputation_delta := CUSTOMER_REQUEST_CORRECT_REPUTATION if correct else CUSTOMER_REQUEST_WRONG_REPUTATION
	ScoreManager.add_shift_score(score_delta)
	if reputation_delta != 0:
		ReputationManager.add_reputation(reputation_delta)
	var xp_delta := 0
	if score_delta > 0:
		XPManager.add_shift_xp(score_delta)
		xp_delta = score_delta * XPManager.XP_PER_SCORE_POINT
	if correct:
		_customers_correct += 1
	else:
		_customers_incorrect += 1
	_customer_score += score_delta
	_customer_reputation += reputation_delta
	_customer_xp += xp_delta

	var did := "%s $%.0f" % [_past_tense_label(type), amount]
	var points := "%+d Score" % score_delta
	if reputation_delta != 0:
		points += ", %+d Reputation" % reputation_delta
	var message: String
	if correct:
		message = "Correct — %s as requested. (%s)" % [did, points]
	else:
		var asked := "%s $%.0f" % [_verb_label(customer.intent_type), customer.intent_amount]
		var you_did := "you " + did
		if not account_ok:
			asked += " %s their own account" % _account_preposition(customer.intent_type)
			you_did += " %s %s's account" % [_account_preposition(type), account.customer_name]
		message = "Customer asked to %s — %s. (%s)" % [asked, you_did, points]
	_show_feedback(message, FEEDBACK_GOOD_COLOR if correct else FEEDBACK_BAD_COLOR)

	var grade_label := "Correct" if correct else "Incorrect"
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"Served %s: asked to %s $%.0f, teller %s $%.0f%s" % [
			customer.display_name, _verb_label(customer.intent_type), customer.intent_amount,
			_past_tense_label(type), amount,
			"" if account_ok else " (on %s's account)" % account.customer_name,
		],
		grade_label
	)

func _verb_label(type: ShiftTransaction.Type) -> String:
	return "deposit" if type == ShiftTransaction.Type.DEPOSIT else "withdraw"

func _past_tense_label(type: ShiftTransaction.Type) -> String:
	return "deposited" if type == ShiftTransaction.Type.DEPOSIT else "withdrew"

func _account_preposition(type: ShiftTransaction.Type) -> String:
	return "into" if type == ShiftTransaction.Type.DEPOSIT else "from"

func _show_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.visible = true

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
	if is_instance_valid(_serving_customer):
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
	if shift_state == ShiftState.CLOCKED_IN:
		_complaints_resolved += 1
		_customer_reputation += response.score
	_show_main_panel()
	_show_feedback("Complaint handled (%s, %+d Reputation)." % [grade_label, response.score], FEEDBACK_GOOD_COLOR if response.score > 0 else (FEEDBACK_NEUTRAL_COLOR if response.score == 0 else FEEDBACK_BAD_COLOR))
	complaint_resolved.emit(customer)

## Backs out of the complaint panel without resolving it — no reputation
## change, no HistoryManager entry. complaint_resolved stays false, so
## the customer stays in line and respond_complaint_button (or reopening
## the screen) brings the complaint back up, the same as closing the whole
## screen without doing anything doesn't silently drop them from the queue
## (see teller_room.gd).
func _on_complaint_later_button_pressed() -> void:
	_show_main_panel()

## Called by teller_room.gd when a queued customer abandons the line, after
## it has applied the Reputation penalty itself — this only tallies it for
## the shift summary (this screen doesn't otherwise see the queue).
func note_customer_abandoned(reputation_delta: int) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	_customers_abandoned += 1
	_customer_reputation += reputation_delta

func _on_respond_complaint_button_pressed() -> void:
	if _has_unresolved_complaint(_serving_customer):
		_show_complaint_panel(_serving_customer)

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

## Gated on work, not time: a shift can only end once every customer it
## brings has been handled (see remaining_shift_work). The old 45-second
## wall-clock minimum could be waited out inside this paused screen while
## no customers spawned, which made an empty shift a free Perfect count.
func _on_clock_out_button_pressed() -> void:
	var remaining: String = remaining_shift_work.call() if remaining_shift_work.is_valid() else ""
	if remaining != "":
		error_label.text = "Can't clock out yet — %s." % remaining
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

## The drawer's true starting cash is always the assigned float — the
## player's opening count is graded against it (and the result shown), but
## never adopted as shift_start_balance, so a wrong opening entry can't
## shift what the closing count is expected to hold. No points are awarded
## for the opening count: the closing count already grades the drawer, and
## scoring both would double-count it.
func _begin_shift(starting_total: float) -> void:
	shift_state = ShiftState.CLOCKED_IN
	shift_start_balance = STARTING_EXPECTED_BALANCE
	shift_start_time = Time.get_datetime_string_from_system()
	shift_transactions.clear()
	_customers_correct = 0
	_customers_incorrect = 0
	_complaints_resolved = 0
	_customers_abandoned = 0
	_customer_score = 0
	_customer_reputation = 0
	_customer_xp = 0

	var opening_cents := MoneyMath.to_cents(starting_total) - MoneyMath.to_cents(STARTING_EXPECTED_BALANCE)
	var opening_result := _categorize_discrepancy(opening_cents, drawer_count_screen.get_excess_bill_count())
	_show_feedback(
		"Opening count: %s (discrepancy $%.2f) — not scored. Drawer starts at its assigned $%.2f float." % [_discrepancy_result_label(opening_result), opening_cents / 100.0, STARTING_EXPECTED_BALANCE],
		FEEDBACK_GOOD_COLOR if opening_result == DiscrepancyResult.PERFECT else FEEDBACK_BAD_COLOR
	)

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
##
## discrepancy_cents is integer cents rather than float dollars — see
## MoneyMath for why.
func _categorize_discrepancy(discrepancy_cents: int, excess_bills: int) -> DiscrepancyResult:
	if discrepancy_cents == 0 and excess_bills <= DrawerCountScreen.PERFECT_BILL_COUNT_TOLERANCE:
		return DiscrepancyResult.PERFECT
	elif absi(discrepancy_cents) <= MoneyMath.to_cents(DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD) and excess_bills <= DrawerCountScreen.MINOR_BILL_COUNT_TOLERANCE:
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
	var discrepancy_cents := MoneyMath.to_cents(ending_total) - MoneyMath.to_cents(expected)
	var discrepancy := discrepancy_cents / 100.0
	var shift_end_time := Time.get_datetime_string_from_system()
	var discrepancy_result := _categorize_discrepancy(discrepancy_cents, drawer_count_screen.get_excess_bill_count())
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
	shift_reputation_label.text = "Reputation: %+d" % reputation_delta
	shift_total_reputation_label.text = "Reputation: %d" % ReputationManager.reputation

	var shift_xp := shift_score * XPManager.XP_PER_SCORE_POINT
	XPManager.add_shift_xp(shift_score)
	shift_xp_label.text = "Shift XP: %+d" % shift_xp
	shift_total_xp_label.text = "Total XP: %d" % XPManager.total_xp

	## Drawer lines above sit under the summary's "Drawer Count" header;
	## these sit under "Customers" — already applied as each happened, so
	## shown here for the breakdown only, not re-applied.
	shift_customer_results_label.text = "Served correctly: %d · Incorrectly: %d\nComplaints resolved: %d · Abandoned: %d" % [_customers_correct, _customers_incorrect, _complaints_resolved, _customers_abandoned]
	shift_customer_points_label.text = "Score %+d · Reputation %+d · XP %+d" % [_customer_score, _customer_reputation, _customer_xp]

	var discrepancy_label := _discrepancy_result_label(discrepancy_result)
	HistoryManager.add_record(DecisionRecord.Role.TELLER, "Drawer count: %s (discrepancy $%.2f)" % [discrepancy_label, discrepancy], discrepancy_label)

	shift_state = ShiftState.CLOCKED_OUT
	awaiting_summary_reveal = true
	_update_shift_controls()
	_reset_account_selection()
	shift_clocked_out.emit()

## Clock-out ends any service (teller_room.gd clears the serving customer
## off shift_clocked_out), so don't leave `account` pointing at the last
## served customer's own account — fall back to the first browsable
## account, the same default _ready() starts from. `account` is never left
## null since _refresh_display()/deposit/withdraw all read it directly.
func _reset_account_selection() -> void:
	if account != null and not account.is_customer_account:
		return
	account = AccountManager.get_browsable_accounts()[0]
	_refresh_account_list()
	_refresh_display()

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
