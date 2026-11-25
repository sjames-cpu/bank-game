extends Control
class_name LoanReviewScreen

## Loan review task screen: an underwriting worksheet (HANDOFF.md Phase 3).
## Works the player's pile of applications (LoanDeskManager: the first
## shift's teaching cases, then generated applicants), first to last. The
## left column shows the application, with the applicant's portrait; "Run
## Credit Check" fills in the worksheet on the right (monthly income,
## housing, existing debt payments, the new loan's payment at its purpose's
## term and the rate offered for the credit band (and why), front-end and
## total DTI, credit score band, employment and the amount affordable at a
## healthy total DTI), each ratio with a one-line explanation, and pulls the
## credit report into a third column beside it (CreditReport.rows(), each
## item explained, then the policy). No risk tier or approve/reject hint is
## ever shown.
## The decision — Approve, Reject (with 1-2 stated reasons) or Counter-Offer
## (an amount, with the affordable amount as a reference) — is gated behind
## the credit check and graded against risk_assessment (see
## LoanApplication.grade_decision() and grade_denial_reasons()), applying
## the resulting Score/Reputation/XP the same add_shift_score() /
## add_reputation() / add_shift_xp() way teller_screen.gd does.
##
## Each decision also logs a DecisionRecord to HistoryManager for the
## Branch Manager's Approvals — see _history_description().
##
## loan_officer_screen.gd instances this screen once and calls show_screen()
## once per application in the shift: decision_graded lets it tally a
## running shift total, and closed (emitted from hide_screen()) tells it
## when to advance. closed carries whether the current application was
## actually decided — an application closed undecided stays current.
##
## Manages its own pause state defensively (_paused_by_self tracks whether
## *this* screen was the one that paused), like drawer_count_screen.gd.

@onready var main_panel: PanelContainer = $Panel
@onready var applicant_portrait: TextureRect = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ApplicantHBox/ApplicantPortrait
@onready var applicant_name_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ApplicantHBox/NameVBox/ApplicantNameLabel
@onready var requested_amount_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ApplicantHBox/NameVBox/RequestedAmountLabel
@onready var terms_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/TermsLabel
@onready var credit_score_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/CreditScoreLabel
## The form's purchase price, vehicle price or business collateral (hidden
## for an unsecured loan).
@onready var collateral_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/CollateralLabel
@onready var annual_income_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/AnnualIncomeLabel
@onready var housing_payment_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/HousingPaymentLabel
@onready var existing_debt_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ExistingDebtLabel
@onready var employment_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/EmploymentLabel
@onready var verify_documents_button: Button = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/ChecksHBox/VerifyDocumentsButton
@onready var run_credit_check_button: Button = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/ChecksHBox/RunCreditCheckButton
@onready var decision_hbox: HBoxContainer = $Panel/VBox/Columns/LeftVBox/DecisionHBox
@onready var approve_button: Button = $Panel/VBox/Columns/LeftVBox/DecisionHBox/ApproveButton
@onready var reject_button: Button = $Panel/VBox/Columns/LeftVBox/DecisionHBox/RejectButton
@onready var counter_offer_button: Button = $Panel/VBox/Columns/LeftVBox/DecisionHBox/CounterOfferButton
@onready var counter_offer_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox
@onready var counter_offer_reference_label: Label = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferReferenceLabel
## What the counter-offer on the spin box implies: the down payment it means
## (or its share of business collateral).
@onready var counter_offer_down_label: Label = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferDownLabel
@onready var counter_offer_amount_spinbox: SpinBox = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/CounterOfferAmountSpinBox
@onready var submit_counter_offer_button: Button = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/SubmitCounterOfferButton
@onready var cancel_counter_offer_button: Button = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/CancelCounterOfferButton
@onready var reasons_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/ReasonsVBox
@onready var reason_checks_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonChecks
@onready var submit_denial_button: Button = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonsHBox/SubmitDenialButton
@onready var cancel_denial_button: Button = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonsHBox/CancelDenialButton
@onready var decision_status_label: Label = $Panel/VBox/Columns/LeftVBox/DecisionStatusLabel
## Request more documents (LoanRequirements, LoanPipeline): the button and its
## one-line note (why it is off, or why there is none) sit under the decisions;
## the checklist takes the decisions' place while it is open.
@onready var request_row: VBoxContainer = $Panel/VBox/Columns/LeftVBox/RequestRow
@onready var request_button: Button = $Panel/VBox/Columns/LeftVBox/RequestRow/RequestButton
@onready var request_note_label: Label = $Panel/VBox/Columns/LeftVBox/RequestRow/RequestNoteLabel
@onready var request_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/RequestVBox
@onready var request_checks_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/RequestVBox/RequestChecks
@onready var confirm_request_button: Button = $Panel/VBox/Columns/LeftVBox/RequestVBox/RequestButtonsHBox/ConfirmRequestButton
@onready var cancel_request_button: Button = $Panel/VBox/Columns/LeftVBox/RequestVBox/RequestButtonsHBox/CancelRequestButton
@onready var worksheet_placeholder_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetPlaceholderLabel
@onready var worksheet_rows_vbox: VBoxContainer = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetRows
@onready var worksheet_title_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetTitleLabel
## After the credit check the worksheet has two tabs (WorksheetTab): its
## payments, and the collateral (value, down payment, LTV, mortgage
## insurance), so both keep readable text in one column.
@onready var worksheet_tabs: TabBar = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetTabs
@onready var collateral_rows_vbox: VBoxContainer = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/CollateralRows
@onready var documents_vbox: VBoxContainer = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox
@onready var id_portrait: TextureRect = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/IdHBox/IdPortrait
@onready var id_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/IdHBox/IdLabel
@onready var stub_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/StubLabel
@onready var statement_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/StatementLabel
## Papers brought back on request (the appraisal, the proof of the down
## payment, the letter): hidden until there are any.
@onready var papers_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/PapersLabel
@onready var documents_policy_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/DocumentsPolicyLabel
@onready var credit_report_placeholder_label: Label = $Panel/VBox/Columns/CreditReportSection/CreditReportVBox/CreditReportPlaceholderLabel
@onready var credit_report_rows_vbox: VBoxContainer = $Panel/VBox/Columns/CreditReportSection/CreditReportVBox/CreditReportRows
@onready var credit_report_policy_label: Label = $Panel/VBox/Columns/CreditReportSection/CreditReportVBox/CreditReportPolicyLabel
## Beside the title, so three columns fit the window's height.
@onready var close_button: Button = $Panel/VBox/TitleHBox/CloseButton

signal decision_graded(score_delta: int, reputation_delta: int, xp_delta: int)
signal closed(was_decided: bool)
## An application is on screen (the room seats its applicant at the desk).
signal application_shown(application: LoanApplication)
## A decision was recorded on `application` (its applicant reacts and leaves).
signal decision_recorded(application: LoanApplication)

const WORKSHEET_TITLE: String = "Underwriting Worksheet"
const DOCUMENTS_TITLE: String = "Documents"
const SHOW_WORKSHEET_TEXT: String = "Show Worksheet"
const SHOW_DOCUMENTS_TEXT: String = "Show Documents"
const VERIFY_TEXT: String = "Verify Documents"
const CREDIT_CHECK_TEXT: String = "Run Credit Check"

## Why Request More Documents is off, or not offered (one line each).
const REQUEST_VERIFY_FIRST_TEXT: String = "Verify the documents first."
const REQUEST_FULL_TEXT: String = "Three files are already waiting for documents."
const REQUEST_TWICE_TEXT: String = "This file has already asked for documents twice."
const REQUEST_STILL_OUT_TEXT: String = "This applicant is still bringing documents."
const REQUEST_TEACHING_TEXT: String = "Asking for more documents starts after these practice applications."
## Shown when a request is refused at the moment it is confirmed (something
## changed since the checklist opened).
const REQUEST_REFUSED_TEXT: String = "Request not sent: %s"
const REQUEST_NO_ITEMS_TEXT: String = "Tick at least one document."

enum WorksheetTab { PAYMENTS, COLLATERAL }
const TAB_TITLES: Array[String] = ["Payments", "Collateral"]

## Whether the current application's documents were looked at (Verify
## Documents) and its credit check run, each before the decision.
var documents_verified: bool = false
var credit_checked: bool = false

## Explanation lines under the worksheet's figures: smaller than body text.
const EXPLANATION_FONT_SIZE: int = 12
## The denial reasons' checkboxes and the decision's feedback: a size below
## body text, so the screen stays clear of the controls line at its tallest.
const COMPACT_FONT_SIZE: int = 13

var _paused_by_self: bool = false
var _current_application: LoanApplication = null

## One CheckBox per LoanApplication.DenialReason, indexed by the reason's
## value (listed on screen in LoanApplication.DENIAL_REASON_ORDER).
var reason_checks: Array[CheckBox] = []

## One CheckBox per item of the request checklist shown now (only the items
## that apply to this application), by LoanRequirements.Item.
var request_checks: Dictionary[int, CheckBox] = {}

## Whether _record_decision() has run for _current_application yet — reset
## each time a new application is displayed, set once a decision is
## recorded. Read by hide_screen() so closed can tell the shift loop
## whether this application was decided or skipped.
var _decision_made_for_current: bool = false

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	run_credit_check_button.pressed.connect(_on_run_credit_check_button_pressed)
	verify_documents_button.pressed.connect(_on_verify_documents_button_pressed)
	approve_button.pressed.connect(_on_approve_button_pressed)
	reject_button.pressed.connect(_on_reject_button_pressed)
	counter_offer_button.pressed.connect(_on_counter_offer_button_pressed)
	submit_counter_offer_button.pressed.connect(_on_submit_counter_offer_button_pressed)
	cancel_counter_offer_button.pressed.connect(_on_cancel_counter_offer_button_pressed)
	submit_denial_button.pressed.connect(_on_submit_denial_button_pressed)
	request_button.pressed.connect(_on_request_button_pressed)
	confirm_request_button.pressed.connect(_on_confirm_request_button_pressed)
	cancel_request_button.pressed.connect(_on_cancel_request_button_pressed)
	request_note_label.add_theme_font_size_override("font_size", EXPLANATION_FONT_SIZE)
	# The request row follows what else is open in the decision area.
	for watched: Control in [counter_offer_vbox, reasons_vbox, request_vbox]:
		watched.visibility_changed.connect(_refresh_request)
	cancel_denial_button.pressed.connect(_on_cancel_denial_button_pressed)
	decision_status_label.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	terms_label.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	for title in TAB_TITLES:
		worksheet_tabs.add_tab(title)
	worksheet_tabs.tab_changed.connect(_on_worksheet_tab_changed)
	counter_offer_amount_spinbox.value_changed.connect(_on_counter_offer_amount_changed)
	counter_offer_down_label.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	reason_checks.resize(LoanApplication.DenialReason.size())
	for reason: LoanApplication.DenialReason in LoanApplication.DENIAL_REASON_ORDER:
		var check := _compact_check(LoanApplication.denial_reason_label(reason))
		check.toggled.connect(_on_reason_toggled.bind(check))
		reason_checks_vbox.add_child(check)
		reason_checks[reason] = check

## A checkbox in the compact style the denial reasons and the request
## checklist share: the theme's button panel would make each row twice as
## tall, and a size below body text keeps the screen clear of the controls
## line at its tallest.
func _compact_check(text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	var compact := StyleBoxEmpty.new()
	compact.content_margin_left = 4.0
	compact.content_margin_top = 0.0
	compact.content_margin_bottom = 0.0
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		check.add_theme_stylebox_override(style, compact)
	check.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	return check

func show_screen() -> void:
	_display_next_application()
	visible = true

	_paused_by_self = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false

	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

	closed.emit(_decision_made_for_current)

## The application on screen (null before the first show_screen()).
func current_application() -> LoanApplication:
	return _current_application

## The first application in the player's pile (LoanDeskManager). One closed
## without a decision stays first — it's shown again (from a fresh,
## un-credit-checked state) next time rather than skipped, so only an actual
## Approve/Reject/Counter-Offer moves on to the next applicant.
func _display_next_application() -> void:
	var application := LoanDeskManager.current_player_application()
	_current_application = application
	_decision_made_for_current = false

	# Computed here (not shown) so it's available as soon as this applicant
	# is current — see risk_assessment on LoanApplication.
	application.risk_assessment = application.calculate_risk_assessment()

	applicant_portrait.texture = CustomerNPC.portrait_of(clampi(application.applicant_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1))
	applicant_name_label.text = application.applicant_name
	requested_amount_label.text = "Requested: %s %s loan" % [LoanApplication.dollars(application.requested_amount), application.loan_purpose.to_lower()]
	terms_label.text = terms_text(application)
	collateral_label.text = form_collateral_text(application)
	collateral_label.visible = collateral_label.text != ""
	credit_score_label.text = "Credit score: %d" % application.credit_score
	annual_income_label.text = stated_income_text(application)
	housing_payment_label.text = "Housing (rent or mortgage): %s/mo" % LoanApplication.dollars(application.monthly_housing_payment)
	existing_debt_label.text = "Existing debt: %s balance · %s/mo" % [LoanApplication.dollars(application.existing_debt), LoanApplication.dollars(application.monthly_debt_payments)]
	employment_label.text = "Employment: %s" % LoanApplication.employment_text(application.employment_months)

	documents_verified = false
	credit_checked = false
	verify_documents_button.text = VERIFY_TEXT
	run_credit_check_button.text = CREDIT_CHECK_TEXT
	run_credit_check_button.visible = true
	worksheet_title_label.text = WORKSHEET_TITLE
	worksheet_placeholder_label.visible = true
	documents_vbox.visible = false
	_clear_worksheet()
	_clear_credit_report()
	worksheet_tabs.visible = false
	worksheet_tabs.current_tab = WorksheetTab.PAYMENTS
	worksheet_title_label.visible = true
	decision_hbox.visible = false
	counter_offer_vbox.visible = false
	reasons_vbox.visible = false
	decision_status_label.visible = false
	request_vbox.visible = false
	_refresh_request()
	application_shown.emit(application)

## The application form's income: "Stated income: $72,000 a year ($6,000/mo)".
static func stated_income_text(application: LoanApplication) -> String:
	return "Stated income: %s a year (%s/mo)" % [LoanApplication.dollars(application.annual_income), LoanApplication.dollars(application.monthly_income())]

## The documents as shown, one entry each: the photo ID, the pay stub, the
## bank statement, then today's date and the policy. Never says what's wrong.
static func documents_rows(application: LoanApplication) -> PackedStringArray:
	var id_text := "Photo ID: none provided."
	if application.id_presented:
		id_text = "Photo ID\nName: %s\nID no. %s · Expires %s" % [application.id_holder_name, application.id_number, IdCard.date_text(application.id_expiry_date)]
	var stub_text := "Pay stub: none provided."
	if application.has_pay_stub:
		stub_text = "Pay stub — %s\nName: %s\nGross pay this month: %s · Net pay: %s" % [
			application.stub_employer, application.stub_name,
			LoanApplication.dollars(application.stub_monthly_gross), LoanApplication.dollars(application.stub_monthly_net),
		]
	var statement_text := "Bank statement: none provided."
	if application.has_statement:
		var deposits: PackedStringArray = []
		for deposit in application.statement_deposits:
			deposits.append(LoanApplication.dollars(deposit))
		statement_text = "Bank statement (last month)\nAccount holder: %s\nPayroll deposits: %s = %s" % [
			application.statement_name, " + ".join(deposits), LoanApplication.dollars(application.statement_total()),
		]
	var policy := "Today: %s. %s" % [IdCard.date_text(GameClock.today_date()), LoanApplication.DOCUMENTS_POLICY_TEXT]
	return PackedStringArray([id_text, stub_text, statement_text, policy])

func _fill_documents(application: LoanApplication) -> void:
	var rows := documents_rows(application)
	id_portrait.visible = application.id_presented
	if application.id_presented:
		id_portrait.texture = CustomerNPC.portrait_of(clampi(application.id_portrait_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1))
	id_label.text = rows[0]
	stub_label.text = rows[1]
	statement_label.text = rows[2]
	documents_policy_label.text = rows[3]
	var papers := LoanReturn.papers_lines(application)
	papers_label.text = "\n".join(papers)
	papers_label.visible = not papers.is_empty()
	# Papers brought back take the policy paragraph's place (the date stays,
	# for checking an ID's expiry), so the screen is no taller than without them.
	if not papers.is_empty():
		documents_policy_label.text = "Today: %s." % IdCard.date_text(GameClock.today_date())

## The documents as shown (for tests).
func documents_text() -> String:
	var parts: Array[String] = [id_label.text, stub_label.text, statement_label.text]
	if papers_label.visible:
		parts.append(papers_label.text)
	parts.append(documents_policy_label.text)
	return "\n".join(parts)

## Verify Documents: the right column shows the documents, beside the
## application form's stated income on the left. Looking at them is what
## counts as verifying (grade_documents()).
func _on_verify_documents_button_pressed() -> void:
	if _current_application == null:
		return
	documents_verified = true
	_fill_documents(_current_application)
	_show_documents_view(true)
	_refresh_request()

func _show_documents_view(show_documents: bool) -> void:
	documents_vbox.visible = show_documents
	var tab := worksheet_tabs.current_tab
	worksheet_rows_vbox.visible = not show_documents and tab == WorksheetTab.PAYMENTS
	collateral_rows_vbox.visible = not show_documents and credit_checked and tab == WorksheetTab.COLLATERAL
	worksheet_placeholder_label.visible = not show_documents and not credit_checked
	# The worksheet's tabs name it once the credit check has filled it.
	worksheet_tabs.visible = not show_documents and credit_checked
	worksheet_title_label.visible = not worksheet_tabs.visible
	worksheet_title_label.text = DOCUMENTS_TITLE if show_documents else WORKSHEET_TITLE
	verify_documents_button.text = VERIFY_TEXT if not documents_verified else SHOW_DOCUMENTS_TEXT
	if credit_checked:
		run_credit_check_button.text = SHOW_WORKSHEET_TEXT

## "60 months at 7.00% · up to $75,000" (the bank's term and rate
## for the purpose; one line, so the screen keeps its height).
static func terms_text(application: LoanApplication) -> String:
	return "%d months at %.2f%% · up to %s" % [
		application.term_months(), application.annual_rate() * 100.0, LoanApplication.dollars(application.policy_maximum()),
	]

## The worksheet as [label, value, explanation] rows (explanation may be
## empty). Shown after the credit check; never names the hidden verdict.
static func worksheet_rows(application: LoanApplication) -> Array[PackedStringArray]:
	var housing := LoanApplication.dollars(application.housing_payment_after_loan())
	if application.replaces_housing():
		housing += " (new mortgage; replaces %s)" % LoanApplication.dollars(application.monthly_housing_payment)
	var payment := "%s (%d months)" % [LoanApplication.dollars(application.new_loan_payment()), application.term_months()]
	var insurance := application.mortgage_insurance()
	var payment_note := ""
	if insurance > 0.0:
		payment = "%s (%d months, with %s mortgage insurance)" % [LoanApplication.dollars(application.new_loan_payment()), application.term_months(), LoanApplication.dollars(insurance)]
		payment_note = "Mortgage insurance: over 80% LTV; see Collateral."
	var rows: Array[PackedStringArray] = [
		PackedStringArray(["Monthly income", LoanApplication.dollars(application.monthly_income()), ""]),
		PackedStringArray(["Housing payment", housing, ""]),
		PackedStringArray(["Existing debt payments", LoanApplication.dollars(application.monthly_debt_payments), ""]),
		PackedStringArray(["Rate offered", "%.2f%%" % (application.annual_rate() * 100.0), application.rate_reason()]),
		PackedStringArray(["New loan payment", payment, payment_note]),
		PackedStringArray(["Front-end DTI", LoanApplication.percent(application.front_end_dti()), "Housing ÷ income: the share of pay that goes on housing."]),
		PackedStringArray(["Total DTI", LoanApplication.percent(application.total_dti()), "Housing + debts + new payment ÷ income. Policy guide: about 36% healthy, 43% stretched, 50% high."]),
		PackedStringArray(["Employment", LoanApplication.employment_text(application.employment_months), "Policy looks for two years in the same line of work."]),
		PackedStringArray(["Affordable at 36% total DTI", LoanApplication.dollars(application.affordable_amount()), "The largest loan keeping total DTI at a healthy 36%."]),
	]
	return rows

func _clear_worksheet() -> void:
	for box: VBoxContainer in [worksheet_rows_vbox, collateral_rows_vbox]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()

func _fill_worksheet(application: LoanApplication) -> void:
	_clear_worksheet()
	_add_rows(worksheet_rows_vbox, worksheet_rows(application))
	_add_rows(collateral_rows_vbox, collateral_rows(application))

## The Collateral tab as [label, value, explanation] rows: the value behind
## the loan, the down payment, the loan-to-value against the purpose's guide
## bands, and (a home) mortgage insurance. Facts and policy, never the
## verdict.
static func collateral_rows(application: LoanApplication) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	if not application.is_secured():
		var what := "a personal loan" if application.loan_purpose == "Personal" else "nothing pledged"
		rows.append(PackedStringArray(["Collateral", "None (unsecured: %s)" % what, "Nothing to sell if the loan isn't repaid, so a default loses most of it."]))
		return rows
	var bands: Array = LoanApplication.LTV_BANDS.get(application.loan_purpose, [])
	var healthy: float = bands[0]
	var stretched: float = bands[1]
	var guide := "Policy guide: up to %s %s, over %s high." % [LoanApplication.percent(healthy), "normal" if application.loan_purpose == "Auto" else "healthy", LoanApplication.percent(stretched)]
	match application.collateral_kind:
		LoanApplication.Collateral.HOUSE:
			rows.append(PackedStringArray(["Purchase price", LoanApplication.dollars(application.purchase_price), ""]))
			var appraisal := LoanApplication.dollars(application.collateral_value)
			if application.has_appraisal_gap():
				appraisal += " (below the price)"
			rows.append(PackedStringArray(["Appraised value", appraisal, "An independent valuation; the bank lends against the lower of price and appraisal."]))
		LoanApplication.Collateral.VEHICLE:
			rows.append(PackedStringArray(["Vehicle price", LoanApplication.dollars(application.purchase_price), "The car secures the loan; its price is its value."]))
		_:
			var kind := LoanApplication.collateral_name(application.collateral_kind)
			rows.append(PackedStringArray(["Collateral", "%s worth %s" % [kind.left(1).to_upper() + kind.substr(1), LoanApplication.dollars(application.collateral_value)], "Pledged against the loan; sold to recover it if the loan isn't repaid."]))
	if application.has_down_payment():
		rows.append(PackedStringArray(["Down payment", application.down_payment_text(), "Price minus the loan: the buyer's own money in."]))
	rows.append(PackedStringArray(["Loan-to-value", LoanApplication.percent(application.loan_to_value()), "Loan ÷ %s. %s" % ["the lower of price and appraisal" if application.collateral_kind == LoanApplication.Collateral.HOUSE else "the value", guide]]))
	if application.replaces_housing():
		var insurance := application.mortgage_insurance()
		var value := "None (80% LTV or less)"
		if insurance > 0.0:
			value = "%s/mo (%.2f%% a year)" % [LoanApplication.dollars(insurance), LoanApplication.mortgage_insurance_rate(application.loan_to_value()) * 100.0]
		rows.append(PackedStringArray(["Mortgage insurance", value, "Over 80% LTV the borrower pays it, in the housing payment: 0.30% a year up to 85%, 0.50% to 90%, 0.75% to 95%, 1.00% above."]))
	return rows

## The form's line about what the loan buys or is secured by: "Purchase
## price: $340,000", "Vehicle price: $32,000", "Collateral offered:
## equipment"; empty when unsecured.
static func form_collateral_text(application: LoanApplication) -> String:
	if not application.is_secured():
		return ""
	match application.collateral_kind:
		LoanApplication.Collateral.HOUSE:
			return "Purchase price: %s" % LoanApplication.dollars(application.purchase_price)
		LoanApplication.Collateral.VEHICLE:
			return "Vehicle price: %s" % LoanApplication.dollars(application.purchase_price)
		_:
			return "Collateral offered: %s" % LoanApplication.collateral_name(application.collateral_kind)

## The Collateral tab's text as shown (for tests).
func collateral_text() -> String:
	return _box_text(collateral_rows_vbox)

func _on_worksheet_tab_changed(_tab: int) -> void:
	_show_documents_view(false)

## [label, value, explanation] rows as labels: the line, then its muted
## explanation (if any).
static func _add_rows(box: VBoxContainer, rows: Array[PackedStringArray], font_size: int = 0) -> void:
	for row in rows:
		var line := Label.new()
		line.text = "%s: %s" % [row[0], row[1]]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if font_size > 0:
			line.add_theme_font_size_override("font_size", font_size)
		box.add_child(line)
		if row[2] != "":
			var explanation := Label.new()
			explanation.theme_type_variation = &"MutedLabel"
			explanation.add_theme_font_size_override("font_size", EXPLANATION_FONT_SIZE)
			explanation.text = row[2]
			explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(explanation)

## The worksheet's text as shown, one line per label (for tests).
func worksheet_text() -> String:
	return _box_text(worksheet_rows_vbox)

static func _box_text(box: VBoxContainer) -> String:
	var lines: PackedStringArray = []
	for child in box.get_children():
		lines.append((child as Label).text)
	return "\n".join(lines)

# --- the credit report -----------------------------------------------------------------

func _clear_credit_report() -> void:
	for child in credit_report_rows_vbox.get_children():
		credit_report_rows_vbox.remove_child(child)
		child.queue_free()
	credit_report_placeholder_label.visible = true
	credit_report_policy_label.visible = false

## Pulled with the credit check, beside the worksheet: the report's facts and
## what each means, then the policy. Never the verdict.
func _fill_credit_report(application: LoanApplication) -> void:
	_clear_credit_report()
	credit_report_placeholder_label.visible = false
	var rows: Array[PackedStringArray] = [PackedStringArray(["Credit score", "%d — %s" % [application.credit_score, LoanApplication.credit_score_band(application.credit_score)], ""])]
	rows.append_array(CreditReport.rows(application))
	_add_rows(credit_report_rows_vbox, rows, COMPACT_FONT_SIZE)
	credit_report_policy_label.text = CreditReport.POLICY_TEXT
	credit_report_policy_label.visible = true

## The credit report's text as shown, one line per label, with the policy
## (for tests).
func credit_report_text() -> String:
	var text := _box_text(credit_report_rows_vbox)
	if credit_report_policy_label.visible:
		text += "\n" + credit_report_policy_label.text
	return text

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_run_credit_check_button_pressed() -> void:
	if _current_application == null:
		return

	var application := _current_application
	var first := not credit_checked
	credit_checked = true
	credit_score_label.text = "Credit score: %d — %s" % [application.credit_score, LoanApplication.credit_score_band(application.credit_score)]
	if first:
		_fill_worksheet(application)
		_fill_credit_report(application)
		worksheet_tabs.current_tab = WorksheetTab.PAYMENTS
	_show_documents_view(false)

	# Decisions are gated behind having run the credit check first, so the
	# player can't decide blind (and kept hidden while a decision's options
	# are open).
	if first:
		decision_hbox.visible = true

func _on_approve_button_pressed() -> void:
	_record_decision(LoanApplication.DecisionType.APPROVE, _current_application.requested_amount, "Approved at %s" % LoanApplication.dollars(_current_application.requested_amount))

func _on_reject_button_pressed() -> void:
	decision_hbox.visible = false
	for check in reason_checks:
		check.set_pressed_no_signal(false)
	submit_denial_button.disabled = true
	reasons_vbox.visible = true

func _on_counter_offer_button_pressed() -> void:
	decision_hbox.visible = false
	counter_offer_reference_label.text = "Affordable at 36%% total DTI: %s" % LoanApplication.dollars(_current_application.affordable_amount())
	counter_offer_amount_spinbox.value = _current_application.requested_amount
	_on_counter_offer_amount_changed(counter_offer_amount_spinbox.value)
	counter_offer_vbox.visible = true

## The down payment (or share of collateral) the amount on the spin box
## implies, so a smaller loan reads as asking for more down.
func _on_counter_offer_amount_changed(amount: float) -> void:
	if _current_application == null:
		return
	counter_offer_down_label.text = _current_application.counter_offer_collateral_line(amount)
	counter_offer_down_label.visible = counter_offer_down_label.text != ""

func _on_submit_counter_offer_button_pressed() -> void:
	var amount := counter_offer_amount_spinbox.value
	_record_decision(LoanApplication.DecisionType.COUNTER_OFFER, amount, "Counter-offered at %s" % LoanApplication.dollars(amount))

func _on_cancel_counter_offer_button_pressed() -> void:
	counter_offer_vbox.visible = false
	decision_hbox.visible = true

## At most MAX_DENIAL_REASONS can be ticked: a third is unticked again.
func _on_reason_toggled(pressed: bool, check: CheckBox) -> void:
	if pressed and selected_reasons().size() > LoanApplication.MAX_DENIAL_REASONS:
		check.set_pressed_no_signal(false)
	submit_denial_button.disabled = selected_reasons().is_empty()

## The ticked reasons, in their listed order.
func selected_reasons() -> Array[LoanApplication.DenialReason]:
	var reasons: Array[LoanApplication.DenialReason] = []
	for reason in LoanApplication.DENIAL_REASON_ORDER:
		if reason_checks[reason].button_pressed:
			reasons.append(reason)
	return reasons

func _on_submit_denial_button_pressed() -> void:
	var reasons := selected_reasons()
	if reasons.is_empty():
		return
	_record_decision(LoanApplication.DecisionType.REJECT, 0.0, "Rejected", reasons)

func _on_cancel_denial_button_pressed() -> void:
	reasons_vbox.visible = false
	decision_hbox.visible = true

# --- request more documents ---------------------------------------------------------

## Why a request can't be made on `application` now, one line, or "" if it
## can: the documents not looked at yet, three files already open, or this
## file's own limit (twice) or wait (the applicant is still out).
static func request_block_reason(application: LoanApplication, verified: bool, today: int) -> String:
	if not verified:
		return REQUEST_VERIFY_FIRST_TEXT
	var probe: Array[int] = [LoanRequirements.Item.PAY_STUB]
	var refusal := LoanRole.pipeline.refusal_for(application, probe, today)
	return "" if refusal == LoanPipeline.Refusal.NONE else request_refusal_text(refusal)

## Why `refusal` (LoanPipeline.refusal_for()) stops a request, one line.
static func request_refusal_text(refusal: LoanPipeline.Refusal) -> String:
	match refusal:
		LoanPipeline.Refusal.FULL:
			return REQUEST_FULL_TEXT
		LoanPipeline.Refusal.TOO_MANY_REQUESTS:
			return REQUEST_TWICE_TEXT
		LoanPipeline.Refusal.STILL_OUT:
			return REQUEST_STILL_OUT_TEXT
	return REQUEST_NO_ITEMS_TEXT

## The request row: shown while nothing else is open in the decision area
## and the application isn't decided; the button off with its reason, or, on
## a teaching case, not offered at all and a line saying why.
func _refresh_request() -> void:
	var application := _current_application
	var other_open := counter_offer_vbox.visible or reasons_vbox.visible or request_vbox.visible
	request_row.visible = application != null and not _decision_made_for_current and not other_open
	if application == null:
		return
	var teaching := LoanApplicationsData.is_teaching_case(application.applicant_name)
	var reason := REQUEST_TEACHING_TEXT if teaching else request_block_reason(application, documents_verified, GameClock.day)
	request_button.visible = not teaching
	request_button.disabled = reason != ""
	request_note_label.text = reason
	request_note_label.visible = reason != ""

func _on_request_button_pressed() -> void:
	if _current_application == null or request_button.disabled:
		return
	for child in request_checks_vbox.get_children():
		request_checks_vbox.remove_child(child)
		child.queue_free()
	request_checks.clear()
	# Only the documents that matter for this application.
	for item in LoanRequirements.all_items():
		if LoanRequirements.applies(_current_application, item):
			var check := _compact_check(LoanRequirements.label(item))
			check.toggled.connect(_on_request_item_toggled)
			request_checks_vbox.add_child(check)
			request_checks[item] = check
	confirm_request_button.disabled = true
	decision_hbox.visible = false
	# A refusal's message from an earlier try goes.
	decision_status_label.visible = false
	request_vbox.visible = true

func _on_request_item_toggled(_pressed: bool) -> void:
	confirm_request_button.disabled = request_ticked_items().is_empty()

## The ticked items, in checklist order.
func request_ticked_items() -> Array[int]:
	var ticked: Array[int] = []
	for item in LoanRequirements.all_items():
		if request_checks.has(item) and request_checks[item].button_pressed:
			ticked.append(item)
	return ticked

func _on_cancel_request_button_pressed() -> void:
	request_vbox.visible = false
	decision_hbox.visible = credit_checked

## Sends the file into the pipeline (LoanRole), off the pile (the next
## applicant joins it) and counts it as this slot's application like a
## decision (decision_graded). The application's `decision` stays NONE, no
## history record is written (Approvals never sees a request) and nothing is
## booked.
func _on_confirm_request_button_pressed() -> void:
	var application := _current_application
	var ticked := request_ticked_items()
	if application == null or ticked.is_empty():
		return
	var missing := LoanRequirements.missing_now(application, LoanDeskManager.career_seed, GameClock.day)
	var result := LoanRequirements.grade_request(application, ticked, missing)
	var refusal := LoanRole.pipeline.refusal_for(application, ticked, GameClock.day)
	var file: LoanFile = null
	if refusal == LoanPipeline.Refusal.NONE:
		file = LoanRole.request_documents(application, ticked)
	if file == null:
		# Refused at the last moment (a file went in since this opened): say
		# why, back to the decisions, and the application stays on the desk.
		request_vbox.visible = false
		decision_hbox.visible = credit_checked
		decision_status_label.visible = true
		decision_status_label.text = REQUEST_REFUSED_TEXT % request_refusal_text(refusal)
		_refresh_request()
		return
	_decision_made_for_current = true
	LoanDeskManager.player_decided(application)
	var score: int = result["score"]
	var reputation_delta: int = result["reputation"]
	var xp := score * XPManager.XP_PER_SCORE_POINT
	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	request_vbox.visible = false
	decision_hbox.visible = false
	decision_status_label.visible = true
	decision_status_label.text = request_feedback(file, result, xp)
	decision_graded.emit(score, reputation_delta, xp)
	decision_recorded.emit(application)
	_refresh_request()

## The feedback after a request: what was asked for and when it is due, how
## it was graded, and what was right and what was missed (never more of the
## file's hidden values than that).
static func request_feedback(file: LoanFile, result: Dictionary, xp: int) -> String:
	var kind: LoanRequirements.RequestKind = result["kind"]
	var right: Array[int] = result["right"]
	var wrong: Array[int] = result["wrong"]
	var missed: Array[int] = result["missed"]
	var lines: PackedStringArray = []
	lines.append("Request sent: %s. Due %s." % [LoanRequirements.labels(file.items), BankCalendar.short_text(file.due_date())])
	lines.append("%s (%+d Score, %+d Reputation, %+d XP)" % [LoanRequirements.request_description(kind), result["score"], result["reputation"], xp])
	match kind:
		LoanRequirements.RequestKind.COMPLETE_FILE:
			lines.append("Nothing was missing from this file.")
		LoanRequirements.RequestKind.FORGED:
			lines.append("The problem was a document that doesn't match: asking for more can't fix that. Reject it as unverifiable.")
		_:
			if not right.is_empty():
				lines.append("Right: %s." % LoanRequirements.labels(right))
			if not wrong.is_empty():
				lines.append("Not missing: %s." % LoanRequirements.labels(wrong))
			if not missed.is_empty():
				lines.append("Missed: %s." % LoanRequirements.labels(missed))
	return "
".join(lines)

## Stores the decision on the current application, grades it against
## risk_assessment (a counter-offer on its amount, a denial's stated reasons
## on top), and applies the resulting Score/Reputation/XP — the same
## add_shift_score()/add_reputation()/add_shift_xp() pattern teller_screen.gd
## uses for its shift summary.
func _record_decision(decision_type: LoanApplication.DecisionType, amount: float, action_text: String, reasons: Array[LoanApplication.DenialReason] = []) -> void:
	if _current_application == null:
		return

	var application := _current_application
	application.decision = decision_type
	application.decision_amount = amount
	_decision_made_for_current = true
	# Off the pile; the next one joins it. A returned file's applicant has no
	# more business here: the file closes.
	LoanDeskManager.player_decided(application)
	LoanRole.pipeline.close(application)
	# Into the loan book (an approval or counter-offer), or counted as a good
	# applicant turned away. With closings on, an approval or counter-offer
	# opens a closing instead and is booked when it is funded; the first
	# shift's three teaching cases are always booked at once.
	var book_now := not LoanConfig.closings_enabled or LoanApplicationsData.is_teaching_case(application.applicant_name)
	LoanBookManager.note_decision(application, true, LoanBookManager.PLAYER_MAKER, book_now)

	# The documents (verified first or not) and the decision, together.
	var result := application.grade_documents(reasons, documents_verified)
	var grade: LoanApplication.Grade = result["grade"]
	var score: int = result["score"]
	var reputation_delta: int = result["reputation"]
	var details: PackedStringArray = []
	var documents_ok := application.documents_check_out()
	if decision_type == LoanApplication.DecisionType.REJECT:
		var reason_grade: Dictionary = result["reasons"]
		details.append(reasons_feedback(reason_grade))
	elif decision_type == LoanApplication.DecisionType.COUNTER_OFFER and documents_ok:
		details.append(application.counter_offer_note(amount))
	details.append_array(documents_feedback(application, result))
	var detail := "\n".join(details)
	var xp := score * XPManager.XP_PER_SCORE_POINT

	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	decision_hbox.visible = false
	counter_offer_vbox.visible = false
	reasons_vbox.visible = false
	decision_status_label.visible = true
	decision_status_label.text = "Decision recorded: %s\n%s (%+d Score, %+d Reputation, %+d XP)" % [action_text, application.decision_description(grade), score, reputation_delta, xp]
	if detail != "":
		decision_status_label.text += "\n" + detail

	var record := HistoryManager.add_loan_record(
		_history_description(decision_type, amount, reasons),
		application.decision_description(grade),
		application.risk_assessment,
		decision_type,
		application.applicant_name,
		amount,
	)
	record.nothing_affordable = application.nothing_affordable()
	record.documents_problem = not documents_ok

	decision_graded.emit(score, reputation_delta, xp)
	decision_recorded.emit(application)
	_refresh_request()

## What the documents meant for this decision, one line each (revealing,
## after the fact, what was wrong with them).
static func documents_feedback(application: LoanApplication, result: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var problem := application.documents_problem_text()
	if result["caught"]:
		lines.append("Good catch: %s." % problem)
	elif not application.documents_check_out():
		if application.decision == LoanApplication.DecisionType.REJECT:
			if application.is_missing_documents_only():
				lines.append("Rejecting works, but asking the applicant to bring the missing documents (%s) is the better call." % problem)
			else:
				lines.append("The documents didn't check out (%s): that was the reason to give." % problem)
		else:
			lines.append("Serious: the income or identity was never verified (%s)." % problem)
	if result["false_unverified"]:
		lines.append("The documents checked out: turning them away as unverifiable (%+d Score, %+d Reputation)." % [LoanApplication.FALSE_UNVERIFIED_SCORE, LoanApplication.FALSE_UNVERIFIED_REPUTATION])
	if result["skipped"]:
		lines.append("Documents not verified before deciding (%+d Score)." % LoanApplication.VERIFY_SKIPPED_SCORE)
	return lines

## "Stated reasons: 1 right, 1 wrong, 1 missed (-1 Score)."
static func reasons_feedback(reason_grade: Dictionary) -> String:
	var wrong: int = reason_grade["wrong"]
	var missing: int = reason_grade["missing"]
	var parts: PackedStringArray = ["%d right" % reason_grade["right"]]
	if wrong > 0:
		parts.append("%d wrong" % wrong)
	if missing > 0:
		parts.append("%d missed" % missing)
	return "Stated reasons: %s (%+d Score)." % [", ".join(parts), reason_grade["score"]]

## Written only to HistoryManager for the Branch Manager's Approvals —
## unlike the rest of this screen, it names risk_assessment directly, since
## the whole point of that review is to check a Loan Officer's decision
## against the risk they couldn't see. Never shown to the player during the
## decision itself.
func _history_description(decision_type: LoanApplication.DecisionType, amount: float, reasons: Array[LoanApplication.DenialReason]) -> String:
	var applicant_name := _current_application.applicant_name
	var risk_label := LoanApplication.risk_tier_label(_current_application.risk_assessment)
	match decision_type:
		LoanApplication.DecisionType.APPROVE:
			return "Loan approved: %s to %s (%s applicant)" % [LoanApplication.dollars(amount), applicant_name, risk_label]
		LoanApplication.DecisionType.REJECT:
			var labels: PackedStringArray = []
			for reason in reasons:
				labels.append(LoanApplication.denial_reason_label(reason))
			return "Loan rejected: %s (%s applicant) — reasons: %s" % [applicant_name, risk_label, ", ".join(labels)]
		_:
			return "Loan countered at %s: %s (%s applicant)" % [LoanApplication.dollars(amount), applicant_name, risk_label]
