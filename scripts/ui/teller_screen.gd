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
## DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS below — rather than
## duplicating the point table a second time.

@onready var main_panel: PanelContainer = $Panel
## Action buttons share rows (Deposit/Withdraw/Reverse, then Open Account/
## Clock In-Out/Close) rather than stacking one per row: stacked, the main
## panel was already taller than the 648px viewport while serving a
## customer with a dialogue line, before Reverse and the feedback line
## were added on top.
@onready var close_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ShiftButtonsHBox/CloseButton
@onready var deposit_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/TransactionButtonsHBox/DepositButton
@onready var withdraw_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/TransactionButtonsHBox/WithdrawButton
@onready var open_account_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ShiftButtonsHBox/OpenAccountButton
@onready var clock_in_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ShiftButtonsHBox/ClockInButton
@onready var clock_out_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/ShiftButtonsHBox/ClockOutButton
@onready var amount_input: SpinBox = $Panel/VBox/ActionsSection/ActionsVBox/AmountSpinBox
@onready var account_option_button: OptionButton = $Panel/VBox/AccountSection/AccountVBox/AccountOptionButton
@onready var serving_status_label: Label = $Panel/VBox/ServingSection/ServingVBox/ServingStatusLabel
@onready var customer_dialogue_panel: PanelContainer = $Panel/VBox/ServingSection/ServingVBox/CustomerDialoguePanel
@onready var customer_dialogue_label: Label = $Panel/VBox/ServingSection/ServingVBox/CustomerDialoguePanel/CustomerDialogueLabel
@onready var respond_complaint_button: Button = $Panel/VBox/ServingSection/ServingVBox/RespondComplaintButton
## Check ID shares the Complete Transaction row, and Refuse Service sits on
## the ID card itself, so the ID checks add no row to the main panel.
@onready var check_id_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/CompleteRowHBox/CheckIdButton
@onready var refuse_service_button: Button = $IdCardPanel/VBox/RefuseServiceButton

## The customer's photo ID (Check ID), beside the main panel rather than in
## it, so it adds nothing to the panel's height.
@onready var id_card_panel: PanelContainer = $IdCardPanel
@onready var id_window_portrait: TextureRect = $IdCardPanel/VBox/PortraitsHBox/WindowVBox/WindowPortrait
@onready var id_card_portrait: TextureRect = $IdCardPanel/VBox/PortraitsHBox/CardVBox/CardPortrait
@onready var id_no_id_label: Label = $IdCardPanel/VBox/PortraitsHBox/CardVBox/NoIdLabel
@onready var id_name_label: Label = $IdCardPanel/VBox/DetailsGrid/NameValue
@onready var id_dob_label: Label = $IdCardPanel/VBox/DetailsGrid/DobValue
@onready var id_number_label: Label = $IdCardPanel/VBox/DetailsGrid/NumberValue
@onready var id_expiry_label: Label = $IdCardPanel/VBox/DetailsGrid/ExpiryValue
@onready var id_today_label: Label = $IdCardPanel/VBox/TodayLabel
@onready var id_policy_label: Label = $IdCardPanel/VBox/PolicyLabel
@onready var feedback_label: Label = $Panel/VBox/ActionsSection/ActionsVBox/FeedbackLabel
## "After cutoff — posts Tue 6 Jan", from 2:00 PM (BusinessDay.cutoff_text()).
@onready var cutoff_label: Label = $Panel/VBox/ActionsSection/ActionsVBox/CutoffLabel
@onready var reverse_transaction_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/TransactionButtonsHBox/ReverseTransactionButton
## Own row under the transaction buttons (with Check ID): Deposit/Withdraw/
## Reverse already fill the 420px panel, and a fourth button there would
## squash all of them.
@onready var complete_transaction_button: Button = $Panel/VBox/ActionsSection/ActionsVBox/CompleteRowHBox/CompleteTransactionButton
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

## The drawer's cash, its limits and transfers with the vault, in a narrow
## panel right of the main one (clear of the HUD column), shown with the
## main panel while clocked in. Beside the main panel rather than in it, so
## the main panel keeps its height.
@onready var drawer_panel: PanelContainer = $DrawerPanel
@onready var drawer_cash_label: Label = $DrawerPanel/VBox/CashLabel
@onready var drawer_limits_label: Label = $DrawerPanel/VBox/LimitsLabel
@onready var drawer_warning_label: Label = $DrawerPanel/VBox/WarningLabel
@onready var transfer_input: SpinBox = $DrawerPanel/VBox/TransferSpinBox
@onready var send_to_vault_button: Button = $DrawerPanel/VBox/SendButton
@onready var get_from_vault_button: Button = $DrawerPanel/VBox/GetButton
@onready var transfer_receipt_label: Label = $DrawerPanel/VBox/ReceiptLabel

## Score/Reputation/XP/Reports and the low-reputation/role-unlocked
## notifications are on the room's always-on HUD (hud.gd).

@onready var shift_summary_panel: PanelContainer = $ShiftSummaryPanel
@onready var shift_start_time_label: Label = $ShiftSummaryPanel/VBox/StartTimeLabel
@onready var shift_end_time_label: Label = $ShiftSummaryPanel/VBox/EndTimeLabel
## Side by side so the summary keeps room for the opening-count line within
## the 648px window.
@onready var shift_total_transactions_label: Label = $ShiftSummaryPanel/VBox/DrawerTotalsHBox/TotalTransactionsLabel
@onready var shift_final_discrepancy_label: Label = $ShiftSummaryPanel/VBox/DrawerTotalsHBox/FinalDiscrepancyLabel
@onready var shift_opening_count_label: Label = $ShiftSummaryPanel/VBox/OpeningCountLabel
## Any drawer-limit breach (drawer_limit_summary()), shown only when there
## was one. Vault transfers go on the opening-count line.
@onready var shift_drawer_limit_label: Label = $ShiftSummaryPanel/VBox/DrawerLimitLabel
@onready var shift_score_label: Label = $ShiftSummaryPanel/VBox/ShiftScoreLabel
@onready var shift_total_score_label: Label = $ShiftSummaryPanel/VBox/TotalsHBox/TotalScoreLabel
@onready var shift_xp_label: Label = $ShiftSummaryPanel/VBox/DrawerPointsHBox/ShiftXPLabel
@onready var shift_total_xp_label: Label = $ShiftSummaryPanel/VBox/TotalsHBox/TotalXPLabel
@onready var shift_reputation_label: Label = $ShiftSummaryPanel/VBox/DrawerPointsHBox/ReputationLabel
@onready var shift_total_reputation_label: Label = $ShiftSummaryPanel/VBox/StandingHBox/TotalReputationLabel
@onready var shift_total_reports_label: Label = $ShiftSummaryPanel/VBox/StandingHBox/TotalReportsLabel
@onready var shift_customer_results_label: Label = $ShiftSummaryPanel/VBox/CustomerResultsLabel
@onready var shift_customer_points_label: Label = $ShiftSummaryPanel/VBox/CustomerPointsLabel
## Drawer + Customers for this shift, so the two sections visibly add up.
@onready var shift_net_label: Label = $ShiftSummaryPanel/VBox/ShiftNetLabel
@onready var shift_summary_done_button: Button = $ShiftSummaryPanel/VBox/DoneButton

signal shift_clocked_in
signal shift_clocked_out

## Clock-out passed its gate and the ending drawer count is opening —
## teller_room.gd shows the first clock-out hint off this.
signal ending_count_started

## Emitted when Complete Transaction (or closing the screen, which completes
## any open transactions) finds the net effect of this visit's transactions
## on a regular customer's own account matches their request — first try,
## or once a mistake has been fixed. teller_room.gd listens for this to
## serve them (pop them from the queue): serving is "their request got
## done," not "the player closed the screen" or "any transaction happened,"
## so checking a balance, clocking in/out, or a wrong transaction doesn't
## remove them from the line.
signal customer_request_satisfied(customer: CustomerNPC)

## Emitted from hide_screen() when the player closes the screen with the
## serving customer's request still wrong. teller_room.gd pops them from the
## queue and sends them off with an upset farewell.
signal customer_left_unfixed(customer: CustomerNPC)

## Phase 6i: emitted whenever the player closes this screen (currently only
## via the Close button — see hide_screen()). teller_room.gd listens for
## this to trigger served customers' farewell + walk-away sequence at the
## right moment: after their request was done but not until the player
## actually leaves the desk.
signal screen_closed

## Emitted once the player picks a response to the serving customer's
## complaint. Resolving the complaint IS serving a complaint customer (they
## have no deposit/withdraw request), so teller_room.gd listens for this to
## pop them from the queue the same way customer_request_satisfied does for
## a regular customer.
signal complaint_resolved(customer: CustomerNPC)

## Emitted when the drawer's cash goes over DRAWER_MAX_CENTS during a shift
## (each time it crosses, not while it stays over). teller_room.gd shows
## the one-time drawer-limit hint off this.
signal drawer_went_over_limit

## Emitted when the player refuses service to the serving customer (Refuse
## Service, after checking their ID). teller_room.gd sends them off
## (CustomerNPC.farewell_line) and moves on to whoever's next.
signal customer_refused(customer: CustomerNPC)

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

## Every deposit/withdrawal made while serving _serving_customer (a regular,
## non-complaint customer), oldest first, as {account, type, amount,
## shift_transaction} — the net effect on the customer's own account is
## what decides whether their request is satisfied, and the last entry is
## what Reverse Transaction undoes. Cleared whenever the serving customer
## changes (see set_serving_customer()).
var _customer_transactions: Array[Dictionary] = []

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

## The drawer's assigned starting float, $3,000.00: a typical teller
## drawer, and enough for any shift. Four customers (CustomerQueue.
## CUSTOMERS_PER_SHIFT_CAP) can withdraw at most $500 each (INTENT_MAX_CENTS),
## $2,000 in all, so the drawer always covers its customers with $1,000 to
## spare. Like every amount the teller handles here (balances, transactions,
## requests, drawer totals), int cents (B3, see MoneyMath) — dollars only on
## entry (the SpinBoxes) and for display (MoneyMath.format()).
const STARTING_FLOAT_CENTS: int = 300000

## What the float is made of, one count per CashDenominations entry ($100 to
## the penny): mostly $20s, the note customers ask for most; tens, fives and
## ones for making up amounts and change; a few $100s and $50s; and two rolls
## of each coin (80 quarters, 100 dimes, 80 nickels, 100 pennies: $35).
## 5x$100 + 6x$50 + 75x$20 + 40x$10 + 45x$5 + 40x$1 + $35 = $3,000.00. The
## drawer counts allow for a drawer this full of small pieces (see
## drawer_plausible_pieces()).
const STARTING_FLOAT_MIX: Array[int] = [5, 6, 75, 40, 45, 40, 80, 100, 80, 100]

const PERFECT_COUNT_SCORE: int = 10
const MINOR_DISCREPANCY_SCORE: int = 5
const MAJOR_DISCREPANCY_SCORE: int = -5

const PERFECT_COUNT_REPUTATION: int = 2
const MINOR_DISCREPANCY_REPUTATION: int = 0
const MAJOR_DISCREPANCY_REPUTATION: int = -5

## Grading for a customer's request, applied once at Complete Transaction
## (see _grade_request()). Customers are the main score (B2): one correct
## request earns half a Perfect count, so a shift's four
## (CustomerQueue.CUSTOMERS_PER_SHIFT_CAP) are worth twice the drawer, and
## the drawer bonus itself only pays in proportion to customers served (see
## _scale_drawer_bonus()). The wrong-request penalty matches an abandoned
## customer's Score cost (ABANDONMENT_SCORE_PENALTY, teller_room.gd), and
## its Reputation hit matches abandoning too (-2) — still below a dismissive
## complaint response (-3) or a Major count (-5). XP follows the reward
## only, per the B6 spec: a wrong request costs Score and Reputation but
## doesn't take XP away.
const CUSTOMER_REQUEST_CORRECT_SCORE: int = 5
const CUSTOMER_REQUEST_CORRECT_REPUTATION: int = 0
const CUSTOMER_REQUEST_WRONG_SCORE: int = -3
const CUSTOMER_REQUEST_WRONG_REPUTATION: int = -2

## Extra Reputation hit, on top of CUSTOMER_REQUEST_WRONG_REPUTATION, when a
## mistake is left unfixed and the customer walks out with their account
## still wrong. Matches a dismissive complaint response (-3,
## customer_complaints_data.gd) — a customer leaving visibly wronged is at
## least that bad — and brings an unfixed mistake's total to -5, the same as
## a Major drawer discrepancy. A fixed mistake stays at -2.
const CUSTOMER_LEFT_UNFIXED_REPUTATION: int = -3

## ID checks (KycPolicy), graded once per customer whose request needs ID
## (a withdrawal or a new account), at their first Complete Transaction or at
## Refuse Service:
## - valid ID checked first, request done: the usual correct-request reward;
## - bad ID refused: the same reward, "Good catch";
## - request done on a bad ID (checked or not): a serious mistake, worth
##   KYC_BAD_ID_ACCEPTED_MISTAKES mistakes toward reports (so a written warning
##   at once), and more Score and Reputation than a wrong request (the account
##   holder's money went to someone else);
## - request done without checking a valid ID first: a procedure mistake,
##   one mistake toward reports, a wrong request's Score but no Reputation
##   (the customer never noticed);
## - valid ID refused: the customer leaves upset, like an unfixed mistake's
##   walk-out (-3 Reputation) plus a wrong request's Score; not a mistake
##   toward reports.
## XP follows positive Score only, as for requests.
const KYC_BAD_ID_CAUGHT_SCORE: int = 5
const KYC_BAD_ID_CAUGHT_REPUTATION: int = 0
const KYC_BAD_ID_ACCEPTED_SCORE: int = -8
const KYC_BAD_ID_ACCEPTED_REPUTATION: int = -3
const KYC_BAD_ID_ACCEPTED_MISTAKES: int = 2
const KYC_CHECK_SKIPPED_SCORE: int = -3
const KYC_CHECK_SKIPPED_REPUTATION: int = 0
const KYC_CHECK_SKIPPED_MISTAKES: int = 1
const KYC_VALID_ID_REFUSED_SCORE: int = -3
const KYC_VALID_ID_REFUSED_REPUTATION: int = -3

## Drawer limits: bank policy keeps a teller's cash between these, so less
## is at risk at the window (over) and withdrawals can still be paid (under).
## The maximum is set so that, with the $3,000 float and the player's line
## as it is (4 customers, $20-$500 requests, half paying by card, a fifth
## complaints), the drawer goes over it in about one shift in four: a
## simulation of those customers puts it over $3,350 at some point in 25% of
## shifts (21% still over at clock-out); over $4,000 in under 1%. Customers
## alone can't take the drawer under the minimum (4 x $500 out of $3,000
## leaves exactly $1,000), so "low" means too much was sent to the vault.
const DRAWER_MAX_CENTS: int = 335000
const DRAWER_MIN_CENTS: int = 100000
const DRAWER_OVER_LIMIT_TEXT: String = "Drawer over limit — send excess cash to the vault"
const DRAWER_LOW_TEXT: String = "Drawer low — get cash from the vault"

## Clocking out with the drawer over DRAWER_MAX_CENTS: a procedure mistake,
## weighted like an ID check skipped (KYC_CHECK_SKIPPED_*). Going over during
## the shift is only a warning.
const DRAWER_OVER_AT_CLOCK_OUT_SCORE: int = -3
const DRAWER_OVER_AT_CLOCK_OUT_MISTAKES: int = 1

const FEEDBACK_GOOD_COLOR: Color = Color(0.3, 1, 0.3, 1)
const FEEDBACK_BAD_COLOR: Color = Color(1, 0.3, 0.3, 1)
const FEEDBACK_NEUTRAL_COLOR: Color = Color(1, 1, 1, 1)

## Opening count (B2): a Major opening count doesn't start the shift — the
## teller recounts, up to MAX_OPENING_RECOUNTS times. Still Major after that,
## a supervisor verifies the drawer at the assigned float and signs off,
## at OPENING_SIGN_OFF_REPUTATION: the same as an abandoned customer or a
## wrong request, below a Major closing count (-5), since the supervisor
## found the float intact — no money was actually missing. No Score or XP
## either way (the closing count grades the drawer).
const MAX_OPENING_RECOUNTS: int = 2
const OPENING_SIGN_OFF_REPUTATION: int = -2

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

## Every opening count submitted for the shift being opened, in order (the
## first count, then any recounts) — cleared when a fresh clock-in starts.
var _opening_results: Array[DiscrepancyResult] = []
## True while a Major opening count is waiting for a recount (Clock In reads
## "Recount Drawer" meanwhile).
var awaiting_opening_recount: bool = false
var _opening_signed_off: bool = false

## Always the assigned float (STARTING_FLOAT_CENTS), never the
## player's opening count — see _begin_shift().
var shift_start_cents: int = 0

## Per-shift customer-service tallies for the shift summary, kept separate
## from the drawer count's points so the summary can show where each came
## from. Points include every customer-driven consequence: graded requests
## (_grade_request()), complaint responses
## (_on_complaint_response_selected()) and abandonments
## (note_customer_abandoned()). Reset in _begin_shift().
var _customers_correct: int = 0
var _mistakes_fixed: int = 0
var _mistakes_unfixed: int = 0
var _complaints_resolved: int = 0
var _customers_abandoned: int = 0
var _customer_score: int = 0
var _customer_reputation: int = 0
var _customer_xp: int = 0
## ID checks this shift: customers whose ID was checked, bad IDs refused,
## requests done without checking first, requests done on a bad ID, and
## valid IDs refused.
var _ids_checked: int = 0
var _bad_ids_caught: int = 0
var _id_checks_skipped: int = 0
var _bad_ids_accepted: int = 0
var _valid_ids_refused: int = 0
## Requests done right but graded as an ID mistake (no correct reward).
var _served_despite_id_mistake: int = 0

## Cash moved between the drawer and the vault this shift (int cents), and
## the drawer-limit record: whether it went over DRAWER_MAX_CENTS at any
## point, whether it was still over at clock-out, and whether it's over
## right now (to notice each crossing).
var _sent_to_vault_cents: int = 0
var _received_from_vault_cents: int = 0
var _went_over_limit: bool = false
var _over_limit_at_clock_out: bool = false
var _drawer_over: bool = false

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
	send_to_vault_button.pressed.connect(_on_send_to_vault_pressed)
	get_from_vault_button.pressed.connect(_on_get_from_vault_pressed)
	drawer_limits_label.text = "Min %s · Max %s" % [MoneyMath.format(DRAWER_MIN_CENTS, true), MoneyMath.format(DRAWER_MAX_CENTS, true)]
	check_id_button.pressed.connect(_on_check_id_button_pressed)
	refuse_service_button.pressed.connect(_on_refuse_service_button_pressed)
	id_policy_label.text = KycPolicy.POLICY_TEXT
	reverse_transaction_button.pressed.connect(_on_reverse_transaction_button_pressed)
	complete_transaction_button.pressed.connect(_on_complete_transaction_button_pressed)
	account_option_button.item_selected.connect(_on_account_option_selected)
	clock_in_button.pressed.connect(_on_clock_in_button_pressed)
	clock_out_button.pressed.connect(_on_clock_out_button_pressed)
	shift_summary_done_button.pressed.connect(_on_shift_summary_done_pressed)
	drawer_count_screen.count_submitted.connect(_on_drawer_count_submitted)
	drawer_count_screen.closed.connect(_on_drawer_count_screen_closed)
	CurrencySpinBoxFormat.apply(amount_input)
	CurrencySpinBoxFormat.apply(new_balance_input)

	account = AccountManager.get_accounts()[0]
	_refresh_account_list()
	_refresh_display()
	_update_shift_controls()

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
	if customer != _serving_customer:
		_customer_transactions.clear()
		id_card_panel.visible = false
	_serving_customer = customer
	if customer != null:
		# Payment method shares the status line (it used to have its own) to
		# leave room for the Complete Transaction row within 648px.
		serving_status_label.text = "Serving: %s · Paying by %s" % [customer.display_name, _payment_method_display_name(customer.payment_method)]
		if customer.account != null:
			account = customer.account
	else:
		serving_status_label.text = "No customer waiting."
		# B6 gap 1: nobody at the desk, so don't leave `account` on the last
		# customer's account — a deposit now would hit it ungraded. Reached
		# only once that customer has left the desk: served (open
		# transactions are graded first, at Complete or on close), left
		# upset, abandoned, or cleared at clock-out.
		_reset_account_selection()
	_refresh_customer_dialogue()
	respond_complaint_button.visible = _has_unresolved_complaint(customer)

## A customer with a pending mistake says what's wrong (correction_line)
## instead of their original request line.
func _refresh_customer_dialogue() -> void:
	var customer := _serving_customer
	var text := ""
	if is_instance_valid(customer):
		if customer.correction_line != "":
			text = customer.correction_line
		elif customer.dialogue_line != null:
			text = customer.dialogue_line.text
	customer_dialogue_panel.visible = text != ""
	customer_dialogue_label.text = "\"%s\"" % text
	_update_customer_buttons()

## Reverse and Complete only apply to a regular customer being served on
## shift; both need at least one of this visit's transactions still standing.
func _update_customer_buttons() -> void:
	var serving_request := shift_state == ShiftState.CLOCKED_IN and _is_serving_regular_customer()
	reverse_transaction_button.visible = serving_request and not _customer_transactions.is_empty()
	complete_transaction_button.visible = serving_request
	complete_transaction_button.disabled = _customer_transactions.is_empty()
	# Any regular customer's ID can be looked at; service can be refused only
	# for a request that needs ID, once it has been checked.
	check_id_button.visible = serving_request and _serving_customer.id_card != null
	refuse_service_button.visible = serving_request and KycPolicy.requires_id(_serving_customer) and _serving_customer.id_checked

func _is_serving_regular_customer() -> bool:
	return is_instance_valid(_serving_customer) and _serving_customer.complaint == null

## True while the serving regular customer was graded wrong at Complete and
## hasn't been fixed yet — a fixed (satisfied) customer is served and moves
## off _serving_customer immediately, so was_mistake alone is enough here.
func _has_pending_mistake() -> bool:
	return _is_serving_regular_customer() and _serving_customer.was_mistake

## True while the serving customer has transactions waiting for Complete
## Transaction. teller_room.gd's clock-out gate names them separately.
func has_uncompleted_transactions() -> bool:
	return _is_serving_regular_customer() and not _customer_transactions.is_empty()

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

## Closing with transactions made but not completed counts as completing
## them (graded here); if the request is still wrong — or a flagged mistake
## was left with everything reversed — the customer gives up and leaves
## upset (see _leave_unfixed()). Closing with no transactions made and no
## mistake flagged leaves the customer waiting in line.
func hide_screen() -> void:
	if has_uncompleted_transactions():
		_complete_transaction(true)
	if _has_pending_mistake():
		_leave_unfixed(_serving_customer)
	id_card_panel.visible = false
	visible = false
	get_tree().paused = false
	screen_closed.emit()

## The original B6 penalty was already applied on the first wrong Complete;
## this adds CUSTOMER_LEFT_UNFIXED_REPUTATION for walking out wronged.
func _leave_unfixed(customer: CustomerNPC) -> void:
	ReputationManager.add_reputation(CUSTOMER_LEFT_UNFIXED_REPUTATION)
	_mistakes_unfixed += 1
	_customer_reputation += CUSTOMER_LEFT_UNFIXED_REPUTATION
	customer.left_upset = true
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"%s left without their transaction being fixed" % customer.display_name,
		"Unfixed"
	)
	_customer_transactions.clear()
	customer_left_unfixed.emit(customer)

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_deposit_button_pressed() -> void:
	# The SpinBox holds dollars; converted to cents once, here.
	var amount_cents := MoneyMath.to_cents(amount_input.value)
	if amount_cents <= 0:
		_show_error("Enter a valid amount.")
		return
	if _current_payment_method() == ShiftTransaction.PaymentMethod.CARD and randf() < CARD_DECLINE_CHANCE:
		_start_card_decline_cooldown()
		return
	error_label.visible = false
	AccountManager.deposit(account, amount_cents)
	var shift_transaction := _record_transaction(ShiftTransaction.Type.DEPOSIT, amount_cents)
	_refresh_display()
	_on_customer_transaction(ShiftTransaction.Type.DEPOSIT, amount_cents, shift_transaction)

func _on_withdraw_button_pressed() -> void:
	var amount_cents := MoneyMath.to_cents(amount_input.value)
	if amount_cents <= 0:
		_show_error("Enter a valid amount.")
		return
	if not account.can_withdraw(amount_cents):
		_show_error("Insufficient funds.")
		return
	# Cash comes out of the drawer, which can't pay out more than it holds
	# (a card withdrawal doesn't touch it).
	if _current_payment_method() == ShiftTransaction.PaymentMethod.CASH and shift_state == ShiftState.CLOCKED_IN and amount_cents > drawer_cash_cents():
		_show_error("Not enough cash in the drawer (%s)." % MoneyMath.format(drawer_cash_cents()))
		return
	if _current_payment_method() == ShiftTransaction.PaymentMethod.CARD and randf() < CARD_DECLINE_CHANCE:
		_start_card_decline_cooldown()
		return
	error_label.visible = false
	AccountManager.withdraw(account, amount_cents)
	var shift_transaction := _record_transaction(ShiftTransaction.Type.WITHDRAWAL, amount_cents)
	_refresh_display()
	_on_customer_transaction(ShiftTransaction.Type.WITHDRAWAL, amount_cents, shift_transaction)

## Every deposit/withdrawal made while serving a regular (non-complaint)
## customer counts toward their request, but nothing is graded until
## Complete Transaction (see _complete_transaction()) — so a request done in
## several steps ($200 + $300 for a $500 deposit) is fine as long as the
## result is right. Complaint customers have no request to compare against
## and are handled by resolving the complaint (see
## _on_complaint_response_selected()).
func _on_customer_transaction(type: ShiftTransaction.Type, amount_cents: int, shift_transaction: ShiftTransaction) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	if not _is_serving_regular_customer():
		return
	_note_id_requiring_action(_serving_customer)
	_customer_transactions.append({
		"account": account,
		"type": type,
		"amount_cents": amount_cents,
		"shift_transaction": shift_transaction,
	})
	_show_feedback("%s %s %s %s's account. Press Complete Transaction when done." % [_past_tense_label(type).capitalize(), MoneyMath.format(amount_cents, true), _account_preposition(type), account.customer_name], FEEDBACK_NEUTRAL_COLOR)
	_update_customer_buttons()

func _on_complete_transaction_button_pressed() -> void:
	if has_uncompleted_transactions():
		_complete_transaction(false)

# --- ID checks (KycPolicy) ------------------------------------------------------

## The teller is about to act on `customer`'s request (a transaction, or
## opening their account): policy says check ID first, when it's needed.
## Checking afterwards doesn't undo a skipped check.
func _note_id_requiring_action(customer: CustomerNPC) -> void:
	if KycPolicy.requires_id(customer) and not customer.id_checked:
		customer.id_check_skipped = true

## Check ID: shows the serving customer's card beside the panel, next to
## how they look at the window.
func _on_check_id_button_pressed() -> void:
	var customer := _serving_customer
	if not _is_serving_regular_customer() or customer.id_card == null:
		return
	if not customer.id_checked:
		customer.id_checked = true
		if shift_state == ShiftState.CLOCKED_IN:
			_ids_checked += 1
	_show_id_card(customer)
	_update_customer_buttons()

func _show_id_card(customer: CustomerNPC) -> void:
	var card := customer.id_card
	id_window_portrait.texture = CustomerNPC.portrait_of(customer.look_index)
	id_card_portrait.visible = card.presented
	id_no_id_label.visible = not card.presented
	if card.presented:
		id_card_portrait.texture = CustomerNPC.portrait_of(card.portrait_look)
		id_name_label.text = card.holder_name
		id_dob_label.text = IdCard.date_text(card.date_of_birth)
		id_number_label.text = card.id_number
		id_expiry_label.text = IdCard.date_text(card.expiry_date)
	else:
		id_no_id_label.text = "No ID"
		for label: Label in [id_name_label, id_dob_label, id_number_label, id_expiry_label]:
			label.text = "—"
	var today := GameClock.today_date()
	id_today_label.text = "Today: %s · Customer: %s" % [IdCard.date_text(today), customer.display_name]
	if not card.presented:
		id_today_label.text += "\n\"Sorry, I don't have my ID with me.\""
	id_card_panel.visible = true

## Refuse Service ("I'm sorry, I can't process this without valid ID."):
## only for a request that needs ID, once the ID has been checked, and with
## nothing done for this visit still standing (reverse it first). Graded on
## whether the ID really was bad (see the KYC_* constants).
func _on_refuse_service_button_pressed() -> void:
	var customer := _serving_customer
	if not _is_serving_regular_customer() or not KycPolicy.requires_id(customer) or not customer.id_checked:
		return
	if not _customer_transactions.is_empty():
		_show_error("Reverse this visit's transactions before refusing service.")
		return
	customer.kyc_graded = true
	var valid := customer.id_card.is_valid()
	var score_delta := KYC_VALID_ID_REFUSED_SCORE if valid else KYC_BAD_ID_CAUGHT_SCORE
	var reputation_delta := KYC_VALID_ID_REFUSED_REPUTATION if valid else KYC_BAD_ID_CAUGHT_REPUTATION
	var points := _apply_points(score_delta, reputation_delta)
	var said := "You: \"%s\"" % KycPolicy.REFUSAL_LINE
	if valid:
		_valid_ids_refused += 1
		customer.left_upset = true
		customer.farewell_line = CustomerNPC.REFUSED_VALID_ID_LINES.pick_random()
		_show_feedback("%s — but %s's ID was valid, so they leave upset. (%s)" % [said, customer.display_name, points], FEEDBACK_BAD_COLOR)
		HistoryManager.add_record(DecisionRecord.Role.TELLER, "Refused %s service on a valid ID" % customer.display_name, "Refused (valid ID)")
	else:
		_bad_ids_caught += 1
		customer.farewell_line = CustomerNPC.REFUSED_BAD_ID_LINES.pick_random()
		_show_feedback("%s — Good catch: %s. (%s)" % [said, id_problem_text(customer), points], FEEDBACK_GOOD_COLOR)
		HistoryManager.add_record(DecisionRecord.Role.TELLER, "Refused %s service: %s" % [customer.display_name, id_problem_text(customer)], "Good catch")
	id_card_panel.visible = false
	customer.correction_line = ""
	customer_refused.emit(customer)

## What's wrong with `customer`'s ID, for feedback ("" when nothing is).
func id_problem_text(customer: CustomerNPC) -> String:
	var card := customer.id_card
	match card.problem:
		IdCard.Problem.EXPIRED:
			return "the ID expired %s" % IdCard.date_text(card.expiry_date)
		IdCard.Problem.NAME_MISMATCH:
			return "the ID is in another name"
		IdCard.Problem.WRONG_PORTRAIT:
			return "the photo is someone else's"
		IdCard.Problem.NO_ID:
			return "there was no ID"
	return ""

## Grades the ID part of `customer`'s request once, at their first Complete
## Transaction: a bad ID (checked or not) is a serious mistake, a valid one
## not checked first a procedure mistake. Returns the feedback for a
## mistake, or "" when the ID part was fine (or not needed, or already
## graded): the correct-request reward then goes ahead as usual.
func _grade_kyc(customer: CustomerNPC) -> String:
	if customer.kyc_graded or not KycPolicy.requires_id(customer) or customer.id_card == null:
		return ""
	customer.kyc_graded = true
	if customer.id_check_skipped:
		_id_checks_skipped += 1
	if not customer.id_card.is_valid():
		_bad_ids_accepted += 1
		var points := _apply_points(KYC_BAD_ID_ACCEPTED_SCORE, KYC_BAD_ID_ACCEPTED_REPUTATION)
		for i in KYC_BAD_ID_ACCEPTED_MISTAKES:
			ReportManager.record_mistake(DecisionRecord.Role.TELLER, "%s (invalid ID)" % customer.display_name)
		HistoryManager.add_record(DecisionRecord.Role.TELLER, "Served %s on an invalid ID: %s" % [customer.display_name, id_problem_text(customer)], "Serious (ID)")
		return "Serious ID breach: %s. Policy: no valid ID, no service. (%s, %d mistakes)" % [id_problem_text(customer), points, KYC_BAD_ID_ACCEPTED_MISTAKES]
	if customer.id_check_skipped:
		var points := _apply_points(KYC_CHECK_SKIPPED_SCORE, KYC_CHECK_SKIPPED_REPUTATION)
		for i in KYC_CHECK_SKIPPED_MISTAKES:
			ReportManager.record_mistake(DecisionRecord.Role.TELLER, "%s (ID not checked)" % customer.display_name)
		HistoryManager.add_record(DecisionRecord.Role.TELLER, "Served %s without checking ID first" % customer.display_name, "Procedure (ID)")
		return "Procedure mistake: bank policy is ID first for withdrawals and new accounts, to protect customers. (%s)" % points
	return ""

## Applies a Score and Reputation change from serving a customer, tallies it
## for the shift summary, and returns it as text ("+5 Score, -3 Reputation").
## XP follows positive Score only.
func _apply_points(score_delta: int, reputation_delta: int) -> String:
	ScoreManager.add_shift_score(score_delta)
	if reputation_delta != 0:
		ReputationManager.add_reputation(reputation_delta)
	var xp_delta := 0
	if score_delta > 0:
		XPManager.add_shift_xp(score_delta)
		xp_delta = score_delta * XPManager.XP_PER_SCORE_POINT
	_customer_score += score_delta
	_customer_reputation += reputation_delta
	_customer_xp += xp_delta
	return _points_text(score_delta, reputation_delta)

func _points_text(score_delta: int, reputation_delta: int) -> String:
	var points := "%+d Score" % score_delta
	if reputation_delta != 0:
		points += ", %+d Reputation" % reputation_delta
	return points

## Grades the serving customer's request against this visit's transactions.
## Right: the correct-request reward (or, after an earlier wrong Complete,
## counted as fixed with no further change) and the customer is served.
## Wrong: the first time, the mistake penalty (once per customer, counted
## toward reports); either way the customer stays at the desk saying what's
## wrong (correction_line) until a later Complete finds it right. A fixed
## mistake still counts as a mistake (was_mistake stays set). closing is
## true when hide_screen() completes on the player's behalf.
##
## A request that needs ID also has its ID part graded at the first Complete
## (_grade_kyc()): a mistake there replaces the correct-request reward, and
## is added to a wrong request's penalty.
func _complete_transaction(closing: bool) -> void:
	var customer := _serving_customer
	var kyc_message := _grade_kyc(customer)
	if _is_request_satisfied(customer):
		if customer.was_mistake:
			_mistakes_fixed += 1
			HistoryManager.add_record(DecisionRecord.Role.TELLER, "Fixed %s's request: %s" % [customer.display_name, _describe_visit_transactions(customer)], "Fixed")
			_show_feedback("Fixed — %s's account now matches their request." % customer.display_name, FEEDBACK_NEUTRAL_COLOR)
		elif kyc_message == "":
			_grade_request(customer, true)
		else:
			_served_despite_id_mistake += 1
			_show_feedback("Request done. %s" % kyc_message, FEEDBACK_BAD_COLOR)
		_complete_customer_request(customer)
		return

	if not customer.was_mistake:
		customer.was_mistake = true
		_grade_request(customer, false)
		# Counted once per mistaken customer, fixed or not — every
		# ReportManager.MISTAKES_PER_REPORT of these becomes a report.
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, customer.display_name)
	elif not closing:
		_show_feedback("Still not right — %s is still waiting for a correction." % customer.display_name, FEEDBACK_BAD_COLOR)
	if kyc_message != "":
		# A wrong request and an ID mistake at once: the request part kept
		# short (the customer says what's wrong), so both fit the panel.
		_show_feedback("Not right (%s). %s" % [_points_text(CUSTOMER_REQUEST_WRONG_SCORE, CUSTOMER_REQUEST_WRONG_REPUTATION), kyc_message], FEEDBACK_BAD_COLOR)
	customer.correction_line = _describe_mistake(customer)
	_refresh_customer_dialogue()

## Undoes the serving customer's most recent transaction: reverts the
## account balance and removes it from shift_transactions, so the drawer's
## expected cash goes back too. Only ever reaches transactions made for the
## customer currently being served (_customer_transactions is cleared
## whenever that changes). Nothing is graded here — that waits for Complete
## Transaction.
func _on_reverse_transaction_button_pressed() -> void:
	if not has_uncompleted_transactions():
		return
	var entry: Dictionary = _customer_transactions.pop_back()
	var entry_account: Account = entry["account"]
	var entry_cents: int = entry["amount_cents"]
	var entry_type: ShiftTransaction.Type = entry["type"]
	if entry_type == ShiftTransaction.Type.DEPOSIT:
		if not AccountManager.withdraw(entry_account, entry_cents):
			_customer_transactions.append(entry)
			_show_error("Can't reverse — the account no longer holds that deposit.")
			return
	else:
		AccountManager.deposit(entry_account, entry_cents)
	var entry_shift_transaction: ShiftTransaction = entry["shift_transaction"]
	if entry_shift_transaction != null:
		shift_transactions.erase(entry_shift_transaction)
	error_label.visible = false
	_refresh_display()
	_show_feedback("Reversed: %s %s %s %s's account." % [_past_tense_label(entry_type), MoneyMath.format(entry_cents, true), _account_preposition(entry_type), entry_account.customer_name], FEEDBACK_NEUTRAL_COLOR)
	_update_customer_buttons()

func _complete_customer_request(customer: CustomerNPC) -> void:
	customer.correction_line = ""
	_customer_transactions.clear()
	_update_customer_buttons()
	customer_request_satisfied.emit(customer)

## Net signed effect (in cents) of this visit's transactions on the
## customer's own account — deposits positive, withdrawals negative.
func _net_own_account_cents(customer: CustomerNPC) -> int:
	var net := 0
	for entry in _customer_transactions:
		if entry["account"] != customer.account:
			continue
		var cents: int = entry["amount_cents"]
		net += cents if entry["type"] == ShiftTransaction.Type.DEPOSIT else -cents
	return net

func _requested_cents(customer: CustomerNPC) -> int:
	var cents := customer.intent_amount_cents
	return cents if customer.intent_type == ShiftTransaction.Type.DEPOSIT else -cents

## Satisfied only when the customer's own account shows the requested net
## change AND nothing this visit did to another account on their behalf is
## still standing — a stray wrong-account transaction has to be reversed
## (Reverse Transaction), not just compensated for on the right account.
func _is_request_satisfied(customer: CustomerNPC) -> bool:
	return _net_own_account_cents(customer) == _requested_cents(customer) and _stray_transactions(customer).is_empty()

## This visit's transactions that hit an account other than the customer's.
func _stray_transactions(customer: CustomerNPC) -> Array[Dictionary]:
	var stray: Array[Dictionary] = []
	for entry in _customer_transactions:
		if entry["account"] != customer.account:
			stray.append(entry)
	return stray

## What the customer says about the current (unsatisfied) state of their
## request: wrong account if the latest transaction hit someone else's
## account, wrong type if their own account moved the opposite way, too
## little / too much otherwise, and — once their own account is right — a
## reminder about any wrong-account transaction still not reversed. An
## empty string (after reversing everything) falls back to their original
## request line.
func _describe_mistake(customer: CustomerNPC) -> String:
	if _customer_transactions.is_empty():
		return ""
	if customer.opens_account and customer.account == null:
		return "I still need an account opened in my name — %s." % customer.display_name
	var last: Dictionary = _customer_transactions[-1]
	if last["account"] != customer.account:
		return "That's not my account — I'm %s." % customer.display_name

	var asked := absi(_requested_cents(customer))
	var net := _net_own_account_cents(customer)
	var deposit_intent := customer.intent_type == ShiftTransaction.Type.DEPOSIT
	if (net > 0 and not deposit_intent) or (net < 0 and deposit_intent):
		var other := ShiftTransaction.Type.WITHDRAWAL if deposit_intent else ShiftTransaction.Type.DEPOSIT
		return "I wanted to %s %s, not %s it." % [_verb_label(customer.intent_type), _money(asked), _verb_label(other)]

	if net == _requested_cents(customer):
		return _describe_stray(customer)

	var done := absi(net)
	if deposit_intent:
		if done < asked:
			return "I gave you %s, but you only deposited %s. Please add the other %s." % [_money(asked), _money(done), _money(asked - done)]
		return "I only gave you %s, but you put in %s." % [_money(asked), _money(done)]
	if done < asked:
		return "I asked for %s, you only gave me %s." % [_money(asked), _money(done)]
	return "You gave me %s — I only asked for %s." % [_money(done), _money(asked)]

## Own account is right, but a wrong-account transaction is still standing.
func _describe_stray(customer: CustomerNPC) -> String:
	var deposited := 0
	var withdrawn := 0
	for entry in _stray_transactions(customer):
		var cents: int = entry["amount_cents"]
		if entry["type"] == ShiftTransaction.Type.DEPOSIT:
			deposited += cents
		else:
			withdrawn += cents
	if deposited > 0 and withdrawn == 0:
		return "Thanks — but my %s is still sitting in someone else's account." % _money(deposited)
	if withdrawn > 0 and deposited == 0:
		return "Thanks — but that %s came out of someone else's account, and it's still missing from theirs." % _money(withdrawn)
	return "Thanks — but you still need to undo what you did to someone else's account."

## What customers say about amounts: "$500", or "$12.34" with cents.
func _money(cents: int) -> String:
	return MoneyMath.format(cents, true)

## The B6 grade for a customer's first Complete Transaction: a correct
## request earns the reward; a wrong one takes the mistake penalty — once per
## customer, however many further wrong attempts follow.
func _grade_request(customer: CustomerNPC, correct: bool) -> void:
	var score_delta := CUSTOMER_REQUEST_CORRECT_SCORE if correct else CUSTOMER_REQUEST_WRONG_SCORE
	var reputation_delta := CUSTOMER_REQUEST_CORRECT_REPUTATION if correct else CUSTOMER_REQUEST_WRONG_REPUTATION
	var points := _apply_points(score_delta, reputation_delta)
	if correct:
		_customers_correct += 1

	var asked := _describe_request(customer)
	var did := _describe_visit_transactions(customer)
	var message: String
	if correct:
		message = "Correct — %s as requested. (%s)" % [asked, points]
	else:
		message = "Not right — customer asked to %s; you %s. (%s)" % [asked, did, points]
	_show_feedback(message, FEEDBACK_GOOD_COLOR if correct else FEEDBACK_BAD_COLOR)

	var grade_label := "Correct" if correct else "Incorrect"
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"Served %s: asked to %s, teller %s" % [customer.display_name, asked, did],
		grade_label
	)

## "deposit $200", or "open an account with $200".
func _describe_request(customer: CustomerNPC) -> String:
	if customer.opens_account:
		return "open an account with %s" % _money(customer.intent_amount_cents)
	return "%s %s" % [_verb_label(customer.intent_type), _money(customer.intent_amount_cents)]

## This visit's transactions in order, e.g. "deposited $200, deposited $300"
## — with the account named on any that hit someone else's.
func _describe_visit_transactions(customer: CustomerNPC) -> String:
	var parts: PackedStringArray = []
	for entry in _customer_transactions:
		var entry_type: ShiftTransaction.Type = entry["type"]
		var entry_account: Account = entry["account"]
		var entry_cents: int = entry["amount_cents"]
		var part := "%s %s" % [_past_tense_label(entry_type), _money(entry_cents)]
		if entry_account != customer.account:
			part += " %s %s's account" % [_account_preposition(entry_type), entry_account.customer_name]
		parts.append(part)
	return ", ".join(parts)

func _verb_label(type: ShiftTransaction.Type) -> String:
	return "deposit" if type == ShiftTransaction.Type.DEPOSIT else "withdraw"

func _past_tense_label(type: ShiftTransaction.Type) -> String:
	return "deposited" if type == ShiftTransaction.Type.DEPOSIT else "withdrew"

func _account_preposition(type: ShiftTransaction.Type) -> String:
	return "into" if type == ShiftTransaction.Type.DEPOSIT else "from"

## Feedback and errors share one spot: whichever was shown last replaces the
## other, so the panel never stacks both (it has to fit the 648px window
## alongside a customer's correction line and the Complete row).
func _show_feedback(text: String, color: Color) -> void:
	error_label.visible = false
	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.visible = true

func _show_error(text: String) -> void:
	feedback_label.visible = false
	error_label.text = text
	error_label.visible = true

## Disables Deposit/Withdraw for CARD_DECLINE_COOLDOWN_SECONDS instead of
## just showing an error — otherwise the 10% decline chance is trivial to
## re-roll by spamming the button, which reads as broken/spammy rather
## than an actual declined card.
func _start_card_decline_cooldown() -> void:
	_show_error("Card Declined. Please wait a moment before retrying.")
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
	cutoff_label.text = BusinessDay.cutoff_text()
	cutoff_label.visible = cutoff_label.text != ""
	account_label.text = account.customer_name
	balance_label.text = "Balance: %s" % MoneyMath.format(account.balance_cents)
	_refresh_drawer()

# --- the drawer and the vault -----------------------------------------------------

## The drawer panel shows with the main panel while clocked in (checked each
## frame, so every panel switch is covered).
func _process(_delta: float) -> void:
	drawer_panel.visible = visible and main_panel.visible and shift_state == ShiftState.CLOCKED_IN

## The drawer's cash and its limit warning. A crossing over the maximum is
## noted for the shift summary and announced (drawer_went_over_limit) for the
## one-time hint; staying over isn't announced again.
func _refresh_drawer() -> void:
	var cash := drawer_cash_cents()
	drawer_cash_label.text = "Cash: %s" % MoneyMath.format(cash)
	drawer_warning_label.text = drawer_limit_warning()
	drawer_warning_label.visible = drawer_warning_label.text != ""
	if shift_state != ShiftState.CLOCKED_IN:
		return
	var over := cash > DRAWER_MAX_CENTS
	if over and not _drawer_over:
		_went_over_limit = true
		drawer_went_over_limit.emit()
	_drawer_over = over

## DRAWER_OVER_LIMIT_TEXT, DRAWER_LOW_TEXT, or "" within the limits (and off
## shift, when there's no drawer).
func drawer_limit_warning() -> String:
	if shift_state != ShiftState.CLOCKED_IN:
		return ""
	var cash := drawer_cash_cents()
	if cash > DRAWER_MAX_CENTS:
		return DRAWER_OVER_LIMIT_TEXT
	if cash < DRAWER_MIN_CENTS:
		return DRAWER_LOW_TEXT
	return ""

## Send to Vault: sells whole dollars of the drawer's cash to the vault.
func _on_send_to_vault_pressed() -> void:
	var cents := _transfer_amount_cents()
	if cents <= 0:
		return
	if cents > drawer_cash_cents():
		_show_error("The drawer only holds %s." % MoneyMath.format(drawer_cash_cents()))
		return
	VaultManager.receive_from_drawer(cents)
	_sent_to_vault_cents += cents
	_finish_transfer("Sold %s to the vault" % MoneyMath.format(cents, true))

## Get Cash from Vault: buys whole dollars of cash from the vault.
func _on_get_from_vault_pressed() -> void:
	var cents := _transfer_amount_cents()
	if cents <= 0:
		return
	if not VaultManager.pay_to_drawer(cents):
		_show_error("The vault only holds %s." % MoneyMath.format(VaultManager.expected_cents))
		return
	_received_from_vault_cents += cents
	_finish_transfer("Bought %s from the vault" % MoneyMath.format(cents, true))

## The transfer amount: whole dollars, as cents. Only on shift.
func _transfer_amount_cents() -> int:
	if shift_state != ShiftState.CLOCKED_IN:
		return 0
	var cents := roundi(transfer_input.value) * 100
	if cents <= 0:
		_show_error("Enter a whole-dollar amount to transfer.")
	return cents

## Logged to history, with a receipt line on the drawer panel.
func _finish_transfer(receipt: String) -> void:
	error_label.visible = false
	HistoryManager.add_record(DecisionRecord.Role.TELLER, receipt, "Vault transfer")
	transfer_receipt_label.text = receipt
	transfer_receipt_label.visible = true
	transfer_input.value = 0
	_refresh_drawer()

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
	id_card_panel.visible = false
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
## it has applied the Score and Reputation penalties itself — this only
## tallies them for the shift summary (this screen doesn't otherwise see the
## queue).
func note_customer_abandoned(score_delta: int, reputation_delta: int) -> void:
	if shift_state != ShiftState.CLOCKED_IN:
		return
	_customers_abandoned += 1
	_customer_score += score_delta
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

	var starting_cents := MoneyMath.to_cents(new_balance_input.value)
	if _is_opening_for_customer():
		_open_customer_account(new_name, starting_cents)
		return
	account = AccountManager.create_account(new_name, starting_cents)

	error_label.visible = false
	_show_main_panel()
	_refresh_account_list()
	_refresh_display()

## Serving, on shift, a customer who came to open an account and doesn't
## have one yet.
func _is_opening_for_customer() -> bool:
	return shift_state == ShiftState.CLOCKED_IN and _is_serving_regular_customer() and _serving_customer.opens_account and _serving_customer.account == null

## Opens an account for the serving account-opening customer. It's theirs
## when it's in their name (letter case and spaces aside); a starting deposit
## is taken like a deposit (into the drawer, and counted towards their
## request at Complete Transaction). Opening it is an ID-requiring action.
func _open_customer_account(new_name: String, starting_cents: int) -> void:
	var customer := _serving_customer
	_note_id_requiring_action(customer)
	var opened := AccountManager.create_account(new_name, 0)
	if new_name.to_lower() == customer.display_name.to_lower():
		opened.is_customer_account = true
		customer.account = opened
	account = opened
	error_label.visible = false
	_show_main_panel()
	_refresh_account_list()
	_refresh_display()
	_show_feedback("Opened an account for %s. Make their first deposit, then press Complete Transaction." % new_name, FEEDBACK_NEUTRAL_COLOR)
	if starting_cents > 0:
		AccountManager.deposit(account, starting_cents)
		var shift_transaction := _record_transaction(ShiftTransaction.Type.DEPOSIT, starting_cents)
		_refresh_display()
		_on_customer_transaction(ShiftTransaction.Type.DEPOSIT, starting_cents, shift_transaction)

## Phase 6j: lists AccountManager.get_browsable_accounts() rather than
## get_accounts() — the demo account plus anything opened via "Open New
## Account," not every auto-created Teller queue customer account (see
## Account.is_customer_account) — so this dropdown stays a short, stable
## list instead of growing with every customer served over a session.
## _browsable_accounts is cached so _on_account_option_selected() below
## indexes into the exact same list this just populated the dropdown
## from. While a customer is being served, their own (otherwise
## non-browsable) account is listed first, so a teller who switched to the
## wrong account can switch back to fix the mistake.
var _browsable_accounts: Array[Account] = []

func _refresh_account_list() -> void:
	_browsable_accounts = AccountManager.get_browsable_accounts()
	if is_instance_valid(_serving_customer) and _serving_customer.account != null and not _browsable_accounts.has(_serving_customer.account):
		_browsable_accounts.insert(0, _serving_customer.account)
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
	clock_in_button.text = "Recount Drawer" if awaiting_opening_recount else "Clock In"
	clock_out_button.visible = clocked_in
	deposit_button.disabled = not clocked_in or _card_decline_on_cooldown
	withdraw_button.disabled = not clocked_in or _card_decline_on_cooldown
	_update_customer_buttons()

## Returns the recorded transaction (so Reverse Transaction can remove it
## again), or null when clocked out and nothing was recorded.
func _record_transaction(type: ShiftTransaction.Type, amount_cents: int) -> ShiftTransaction:
	if shift_state != ShiftState.CLOCKED_IN:
		return null
	var transaction := ShiftTransaction.new()
	transaction.type = type
	transaction.amount_cents = amount_cents
	transaction.account_name = account.customer_name
	transaction.timestamp = GameClock.timestamp()
	transaction.payment_method = _current_payment_method()
	transaction.posting_day = BusinessDay.posting_day()
	shift_transactions.append(transaction)
	return transaction

## The cash in the drawer right now: the float plus cash deposits minus
## cash withdrawals so far this shift, minus cash sold to the vault plus
## cash bought from it.
func drawer_cash_cents() -> int:
	return _calculate_expected_ending_cents()

## Card transactions are excluded here (Phase 6e) — no physical cash
## changed hands, so they shouldn't shift what the drawer count is
## expected to hold. They still count toward
## shift_total_transactions_label's total below and still applied to the
## account balance in _on_deposit_button_pressed()/
## _on_withdraw_button_pressed() — only this drawer math skips them. Vault
## transfers are cash, so they count.
func _calculate_expected_ending_cents() -> int:
	var total_deposits := 0
	var total_withdrawals := 0
	for transaction in shift_transactions:
		if transaction.payment_method != ShiftTransaction.PaymentMethod.CASH:
			continue
		if transaction.type == ShiftTransaction.Type.DEPOSIT:
			total_deposits += transaction.amount_cents
		else:
			total_withdrawals += transaction.amount_cents
	return shift_start_cents + total_deposits - total_withdrawals - _sent_to_vault_cents + _received_from_vault_cents

## Also the Recount button: while awaiting_opening_recount, the same button
## (relabelled) reopens the count for the same opening.
func _on_clock_in_button_pressed() -> void:
	# No new shifts after BusinessDay.LAST_CLOCK_IN (a recount of a shift
	# already being opened is fine).
	if not awaiting_opening_recount and not BusinessDay.can_start_shift():
		error_label.text = BusinessDay.CLOCK_IN_REFUSED_TEXT
		error_label.visible = true
		return
	error_label.visible = false
	var title := "Starting Drawer Count"
	if awaiting_opening_recount:
		title = "Recount Drawer (%d of %d)" % [_opening_results.size(), MAX_OPENING_RECOUNTS]
	else:
		_opening_results.clear()
		_opening_signed_off = false
	pending_drawer_count_purpose = DrawerCountPurpose.STARTING
	main_panel.visible = false
	id_card_panel.visible = false
	drawer_count_screen.show_screen(STARTING_FLOAT_CENTS, title, drawer_plausible_pieces(STARTING_FLOAT_CENTS))

## How many pieces a drawer holding `expected_cents` plausibly has, for the
## count's excess-piece check (DrawerCountScreen.get_excess_bill_count()):
## the starting float's pieces (STARTING_FLOAT_MIX), plus the fewest pieces
## for any net cash taken in since. Counting the float as it came, or with
## the fewest pieces, both stay Perfect; a count padded with hundreds of
## extra coins still doesn't.
static func drawer_plausible_pieces(expected_cents: int) -> int:
	var taken_in := maxi(0, expected_cents - STARTING_FLOAT_CENTS)
	return CashDenominations.piece_count(STARTING_FLOAT_MIX) + CashDenominations.piece_count(CashDenominations.fewest_pieces(taken_in))

## Gated on work, not time: a shift can only end once every customer it
## brings has been handled (see remaining_shift_work). The old 45-second
## wall-clock minimum could be waited out inside this paused screen while
## no customers spawned, which made an empty shift a free Perfect count.
func _on_clock_out_button_pressed() -> void:
	var remaining: String = remaining_shift_work.call() if remaining_shift_work.is_valid() else ""
	if remaining != "":
		_show_error("Can't clock out yet — %s." % remaining)
		return
	error_label.visible = false
	_check_drawer_limit_at_clock_out()
	pending_drawer_count_purpose = DrawerCountPurpose.ENDING
	main_panel.visible = false
	id_card_panel.visible = false
	var expected_cents := _calculate_expected_ending_cents()
	drawer_count_screen.show_screen(expected_cents, "Ending Drawer Count", drawer_plausible_pieces(expected_cents))
	ending_count_started.emit()

## Clocking out with the drawer over DRAWER_MAX_CENTS is a procedure mistake
## (once per shift: the count can be backed out of and Clock Out pressed
## again). Explained in the shift summary.
func _check_drawer_limit_at_clock_out() -> void:
	if _over_limit_at_clock_out or drawer_cash_cents() <= DRAWER_MAX_CENTS:
		return
	_over_limit_at_clock_out = true
	ScoreManager.add_shift_score(DRAWER_OVER_AT_CLOCK_OUT_SCORE)
	for i in DRAWER_OVER_AT_CLOCK_OUT_MISTAKES:
		ReportManager.record_mistake(DecisionRecord.Role.TELLER, "Drawer over limit at clock-out")
	HistoryManager.add_record(DecisionRecord.Role.TELLER, "Clocked out with the drawer over its limit (%s, limit %s)" % [MoneyMath.format(drawer_cash_cents()), MoneyMath.format(DRAWER_MAX_CENTS)], "Procedure (drawer)")

## The summary's vault transfers, e.g. "Vault: sold $1000 · bought $0"
## (on the opening-count line), or "" with none.
func vault_transfers_summary() -> String:
	if _sent_to_vault_cents == 0 and _received_from_vault_cents == 0:
		return ""
	return "Vault: sold %s · bought %s" % [MoneyMath.format(_sent_to_vault_cents, true), MoneyMath.format(_received_from_vault_cents, true)]

## The summary's drawer-limit line, or "" when the drawer stayed within its
## limits.
func drawer_limit_summary() -> String:
	if _over_limit_at_clock_out:
		return "Over the drawer limit at clock-out: procedure mistake (%+d Score). Limits keep less cash at risk." % DRAWER_OVER_AT_CLOCK_OUT_SCORE
	if _went_over_limit:
		return "Went over the drawer limit (warning only)"
	return ""

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
func _on_drawer_count_submitted(total_cents: int) -> void:
	if pending_drawer_count_purpose == DrawerCountPurpose.NONE:
		return
	match pending_drawer_count_purpose:
		DrawerCountPurpose.STARTING:
			_on_opening_count_submitted(total_cents)
		DrawerCountPurpose.ENDING:
			_prepare_shift_summary(total_cents)
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

## Grades an opening count (first count or recount). Perfect starts the
## shift; Minor starts it and logs the variance; Major asks for a recount,
## and after MAX_OPENING_RECOUNTS still-Major recounts a supervisor signs off
## (Reputation penalty, logged) and the shift starts. The drawer's true
## starting cash is the assigned float in every case — see _begin_shift().
func _on_opening_count_submitted(total_cents: int) -> void:
	var cents := total_cents - STARTING_FLOAT_CENTS
	var result := _categorize_discrepancy(cents, drawer_count_screen.get_excess_bill_count())
	_opening_results.append(result)
	var variance := MoneyMath.format(cents)
	var float_text := MoneyMath.format(STARTING_FLOAT_CENTS)
	match result:
		DiscrepancyResult.PERFECT:
			_show_feedback("Opening count: Perfect — not scored. Drawer starts at its assigned %s float." % float_text, FEEDBACK_GOOD_COLOR)
			_begin_shift()
		DiscrepancyResult.MINOR:
			_log_opening_variance("Minor", "Opening count: Minor variance (%s) against the %s float" % [variance, float_text])
			_show_feedback("Opening count: Minor (discrepancy %s) — logged, not scored. Drawer starts at its assigned %s float." % [variance, float_text], FEEDBACK_BAD_COLOR)
			_begin_shift()
		_:
			var recounts_used := _opening_results.size() - 1
			if recounts_used < MAX_OPENING_RECOUNTS:
				awaiting_opening_recount = true
				var note := "Recount required before your shift can start (recount %d of %d)." % [recounts_used + 1, MAX_OPENING_RECOUNTS]
				drawer_count_screen.append_status_note(note)
				_show_error("Opening count: Major discrepancy (%s). %s" % [variance, note])
				_update_shift_controls()
				return
			_sign_off_opening(variance)

## Still Major after every recount: the supervisor verifies the drawer at
## the assigned float and signs off; the variance is recorded.
func _sign_off_opening(variance: String) -> void:
	_opening_signed_off = true
	ReputationManager.add_reputation(OPENING_SIGN_OFF_REPUTATION)
	var float_text := MoneyMath.format(STARTING_FLOAT_CENTS)
	_log_opening_variance("Signed off", "Opening count: Major variance (%s) after %d recounts; supervisor verified the drawer at %s and signed off" % [variance, MAX_OPENING_RECOUNTS, float_text])
	var notice := "Your supervisor verified the drawer at %s and signed off. The variance has been recorded." % float_text
	drawer_count_screen.append_status_note(notice)
	_show_feedback("%s (%+d Reputation)" % [notice, OPENING_SIGN_OFF_REPUTATION], FEEDBACK_BAD_COLOR)
	_begin_shift()

## Logged for the record only — DRAWER_VARIANCE is never actionable in
## approvals.
func _log_opening_variance(grade_label: String, description: String) -> void:
	HistoryManager.add_record(DecisionRecord.Role.DRAWER_VARIANCE, description, grade_label)

## The shift summary's opening line, e.g. "Opening count: Major, recounted
## once, then Perfect". Kept to one line of the summary.
func opening_count_summary() -> String:
	if _opening_results.is_empty():
		return "Opening count: —"
	var text := "Opening count: %s" % _discrepancy_result_label(_opening_results[0])
	var recounts := _opening_results.size() - 1
	if recounts == 0:
		return text
	text += ", recounted %s, " % ("once" if recounts == 1 else "twice")
	if _opening_signed_off:
		return text + "signed off"
	return text + "then %s" % _discrepancy_result_label(_opening_results[-1])

## The drawer's true starting cash is always the assigned float — the
## player's opening count is graded against it (see
## _on_opening_count_submitted()), but never adopted as shift_start_cents,
## so a wrong opening entry can't shift what the closing count is expected to
## hold. No points are awarded for the opening count: the closing count
## already grades the drawer, and scoring both would double-count it.
func _begin_shift() -> void:
	awaiting_opening_recount = false
	shift_state = ShiftState.CLOCKED_IN
	shift_start_cents = STARTING_FLOAT_CENTS
	shift_start_time = GameClock.timestamp()
	shift_transactions.clear()
	_customers_correct = 0
	_mistakes_fixed = 0
	_mistakes_unfixed = 0
	_complaints_resolved = 0
	_customers_abandoned = 0
	_customer_score = 0
	_customer_reputation = 0
	_customer_xp = 0
	_ids_checked = 0
	_bad_ids_caught = 0
	_id_checks_skipped = 0
	_bad_ids_accepted = 0
	_valid_ids_refused = 0
	_served_despite_id_mistake = 0
	_sent_to_vault_cents = 0
	_received_from_vault_cents = 0
	_went_over_limit = false
	_over_limit_at_clock_out = false
	_drawer_over = false
	transfer_receipt_label.visible = false

	_card_decline_on_cooldown = false
	_update_shift_controls()
	shift_clocked_in.emit()

## Same "Perfect Count!"/"Minor Discrepancy"/"Major Discrepancy" buckets
## DrawerCountScreen's status label shows, so this reuses its
## MINOR_DISCREPANCY_THRESHOLD_CENTS constant rather than redefining the $50
## cutoff a second time. Score and Reputation both derive from this one
## categorization instead of each re-checking the discrepancy value.
## excess_bills is how many more bills the player entered in the ending
## count than the minimum possible for that total (see DrawerCountScreen.
## get_excess_bill_count()) — a correct total no longer grades Perfect on
## its own if the bill breakdown behind it is implausible.
func _categorize_discrepancy(discrepancy_cents: int, excess_bills: int) -> DiscrepancyResult:
	if discrepancy_cents == 0 and excess_bills <= DrawerCountScreen.PERFECT_BILL_COUNT_TOLERANCE:
		return DiscrepancyResult.PERFECT
	elif absi(discrepancy_cents) <= DrawerCountScreen.MINOR_DISCREPANCY_THRESHOLD_CENTS and excess_bills <= DrawerCountScreen.MINOR_BILL_COUNT_TOLERANCE:
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

## B2: a Perfect/Minor closing count only pays in proportion to the shift's
## customers actually served, and nothing if none were — so ignoring every
## customer and counting the untouched drawer earns nothing. A Major
## penalty (negative) is never scaled down.
func _scale_drawer_bonus(points: int, served: int, shift_customers: int) -> int:
	if points <= 0:
		return points
	if served == 0 or shift_customers == 0:
		return 0
	return roundi(float(points) * served / shift_customers)

## Served = request done (correctly, fixed, or despite an ID mistake),
## complaint resolved, or a bad ID rightly refused.
func _customers_served() -> int:
	return _customers_correct + _mistakes_fixed + _complaints_resolved + _bad_ids_caught + _served_despite_id_mistake

## Every customer this shift brought — the clock-out gate guarantees each
## one has been served, left unfixed, refused on a valid ID, or abandoned
## by now.
func _shift_customer_count() -> int:
	return _customers_served() + _mistakes_unfixed + _customers_abandoned + _valid_ids_refused

## The summary's ID line, e.g. "ID checks: 3 checked · 1 bad ID caught · 0
## skipped", plus bad IDs accepted and valid IDs refused when there were any.
func id_checks_summary() -> String:
	var text := "ID checks: %d checked · %d bad ID%s caught · %d skipped" % [_ids_checked, _bad_ids_caught, "" if _bad_ids_caught == 1 else "s", _id_checks_skipped]
	if _bad_ids_accepted > 0:
		text += " · %d bad ID%s accepted" % [_bad_ids_accepted, "" if _bad_ids_accepted == 1 else "s"]
	if _valid_ids_refused > 0:
		text += " · %d valid ID%s refused" % [_valid_ids_refused, "" if _valid_ids_refused == 1 else "s"]
	return text

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

func _prepare_shift_summary(ending_total_cents: int) -> void:
	var discrepancy_cents := ending_total_cents - _calculate_expected_ending_cents()
	var shift_end_time := GameClock.timestamp()
	var discrepancy_result := _categorize_discrepancy(discrepancy_cents, drawer_count_screen.get_excess_bill_count())
	var served := _customers_served()
	var shift_customers := _shift_customer_count()
	var shift_score := _scale_drawer_bonus(_calculate_shift_score(discrepancy_result), served, shift_customers)
	var reputation_delta := _scale_drawer_bonus(_calculate_reputation_delta(discrepancy_result), served, shift_customers)

	shift_start_time_label.text = "Start Time: %s" % shift_start_time
	shift_end_time_label.text = "End Time: %s" % shift_end_time
	shift_total_transactions_label.text = "Total Transactions: %d" % shift_transactions.size()
	shift_final_discrepancy_label.text = "Final Discrepancy: %s" % MoneyMath.format(discrepancy_cents)
	shift_opening_count_label.text = opening_count_summary()
	if vault_transfers_summary() != "":
		shift_opening_count_label.text += " · " + vault_transfers_summary()
	shift_drawer_limit_label.text = drawer_limit_summary()
	shift_drawer_limit_label.visible = shift_drawer_limit_label.text != ""
	shift_score_label.text = "Score: %+d" % shift_score
	if discrepancy_result != DiscrepancyResult.MAJOR:
		shift_score_label.text += " (%s, %d of %d customers served)" % [_discrepancy_result_label(discrepancy_result), served, shift_customers]

	ScoreManager.add_shift_score(shift_score)
	shift_total_score_label.text = "Total Score: %d" % ScoreManager.total_score

	ReputationManager.add_reputation(reputation_delta)
	shift_reputation_label.text = "Reputation: %+d" % reputation_delta
	shift_total_reputation_label.text = "Reputation: %d" % ReputationManager.reputation
	shift_total_reports_label.text = ReportManager.status_text()

	var shift_xp := shift_score * XPManager.XP_PER_SCORE_POINT
	XPManager.add_shift_xp(shift_score)
	shift_xp_label.text = "XP: %+d" % shift_xp
	shift_total_xp_label.text = "Total XP: %d" % XPManager.total_xp

	## Drawer lines above sit under the summary's "Drawer Count" header;
	## these sit under "Customers" — already applied as each happened, so
	## shown here for the breakdown only, not re-applied.
	shift_customer_results_label.text = "Served correctly: %d\nMistakes fixed: %d · Left unfixed: %d\nComplaints resolved: %d · Abandoned: %d\n%s" % [_customers_correct, _mistakes_fixed, _mistakes_unfixed, _complaints_resolved, _customers_abandoned, id_checks_summary()]
	shift_customer_points_label.text = "Score %+d · Reputation %+d · XP %+d" % [_customer_score, _customer_reputation, _customer_xp]
	var limit_score := DRAWER_OVER_AT_CLOCK_OUT_SCORE if _over_limit_at_clock_out else 0
	shift_net_label.text = "This shift: Score %+d · Reputation %+d · XP %+d" % [shift_score + _customer_score + limit_score, reputation_delta + _customer_reputation, shift_xp + _customer_xp]

	var discrepancy_label := _discrepancy_result_label(discrepancy_result)
	HistoryManager.add_record(DecisionRecord.Role.TELLER, "Drawer count: %s (discrepancy %s)" % [discrepancy_label, MoneyMath.format(discrepancy_cents)], discrepancy_label)

	BusinessDay.note_after_cutoff(shift_transactions)
	shift_state = ShiftState.CLOCKED_OUT
	awaiting_summary_reveal = true
	_update_shift_controls()
	_reset_account_selection()
	shift_clocked_out.emit()

## Called whenever nobody is being served (set_serving_customer(null)) and
## at clock-out, which ends any service (teller_room.gd clears the serving
## customer off shift_clocked_out): don't leave `account` pointing at the
## last served customer's own account — fall back to the first browsable
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
