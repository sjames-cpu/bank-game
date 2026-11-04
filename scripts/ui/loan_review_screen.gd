extends Control
class_name LoanReviewScreen

## Loan review task screen: an underwriting worksheet (HANDOFF.md Phase 3).
## Works the player's pile of applications (LoanDeskManager: the first
## shift's teaching cases, then generated applicants), first to last. The
## left column shows the application, with the applicant's portrait; "Run
## Credit Check" fills in the worksheet on the right (monthly income,
## housing, existing debt payments, the new loan's payment at its purpose's
## term and rate, front-end and total DTI, credit score band, employment
## and the amount affordable at a healthy total DTI), each ratio with a
## one-line explanation. No risk tier or approve/reject hint is ever shown.
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
@onready var counter_offer_amount_spinbox: SpinBox = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/CounterOfferAmountSpinBox
@onready var submit_counter_offer_button: Button = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/SubmitCounterOfferButton
@onready var cancel_counter_offer_button: Button = $Panel/VBox/Columns/LeftVBox/CounterOfferVBox/CounterOfferHBox/CancelCounterOfferButton
@onready var reasons_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/ReasonsVBox
@onready var reason_checks_vbox: VBoxContainer = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonChecks
@onready var submit_denial_button: Button = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonsHBox/SubmitDenialButton
@onready var cancel_denial_button: Button = $Panel/VBox/Columns/LeftVBox/ReasonsVBox/ReasonsHBox/CancelDenialButton
@onready var decision_status_label: Label = $Panel/VBox/Columns/LeftVBox/DecisionStatusLabel
@onready var worksheet_placeholder_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetPlaceholderLabel
@onready var worksheet_rows_vbox: VBoxContainer = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetRows
@onready var worksheet_title_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/WorksheetTitleLabel
@onready var documents_vbox: VBoxContainer = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox
@onready var id_portrait: TextureRect = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/IdHBox/IdPortrait
@onready var id_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/IdHBox/IdLabel
@onready var stub_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/StubLabel
@onready var statement_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/StatementLabel
@onready var documents_policy_label: Label = $Panel/VBox/Columns/WorksheetSection/WorksheetVBox/DocumentsVBox/DocumentsPolicyLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

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

## One CheckBox per LoanApplication.DenialReason, in enum order.
var reason_checks: Array[CheckBox] = []

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
	cancel_denial_button.pressed.connect(_on_cancel_denial_button_pressed)
	decision_status_label.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	for reason: int in LoanApplication.DenialReason.values():
		var check := CheckBox.new()
		check.text = LoanApplication.denial_reason_label(reason as LoanApplication.DenialReason)
		# Compact rows: the theme's button panel makes each twice as tall.
		var compact := StyleBoxEmpty.new()
		compact.content_margin_left = 4.0
		compact.content_margin_top = 0.0
		compact.content_margin_bottom = 0.0
		for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			check.add_theme_stylebox_override(style, compact)
		# Six reasons in the left column: a size smaller than body text keeps the
		# screen clear of the controls line at its tallest.
		check.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
		check.toggled.connect(_on_reason_toggled.bind(check))
		reason_checks_vbox.add_child(check)
		reason_checks.append(check)

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
	decision_hbox.visible = false
	counter_offer_vbox.visible = false
	reasons_vbox.visible = false
	decision_status_label.visible = false
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

## The documents as shown (for tests).
func documents_text() -> String:
	return "\n".join([id_label.text, stub_label.text, statement_label.text, documents_policy_label.text])

## Verify Documents: the right column shows the documents, beside the
## application form's stated income on the left. Looking at them is what
## counts as verifying (grade_documents()).
func _on_verify_documents_button_pressed() -> void:
	if _current_application == null:
		return
	documents_verified = true
	_fill_documents(_current_application)
	_show_documents_view(true)

func _show_documents_view(show_documents: bool) -> void:
	documents_vbox.visible = show_documents
	worksheet_rows_vbox.visible = not show_documents
	worksheet_placeholder_label.visible = not show_documents and not credit_checked
	worksheet_title_label.text = DOCUMENTS_TITLE if show_documents else WORKSHEET_TITLE
	verify_documents_button.text = VERIFY_TEXT if not documents_verified else SHOW_DOCUMENTS_TEXT
	if credit_checked:
		run_credit_check_button.text = SHOW_WORKSHEET_TEXT

## "60 months at 7.00% · policy maximum $75,000" (the bank's term and rate
## for the purpose; one line, so the screen keeps its height).
static func terms_text(application: LoanApplication) -> String:
	return "%d months at %.2f%% · policy maximum %s" % [
		application.term_months(), application.annual_rate() * 100.0, LoanApplication.dollars(application.policy_maximum()),
	]

## The worksheet as [label, value, explanation] rows (explanation may be
## empty). Shown after the credit check; never names the hidden verdict.
static func worksheet_rows(application: LoanApplication) -> Array[PackedStringArray]:
	var housing := LoanApplication.dollars(application.housing_payment_after_loan())
	if application.replaces_housing():
		housing += " (new mortgage; replaces %s)" % LoanApplication.dollars(application.monthly_housing_payment)
	var rows: Array[PackedStringArray] = [
		PackedStringArray(["Monthly income", LoanApplication.dollars(application.monthly_income()), ""]),
		PackedStringArray(["Housing payment", housing, ""]),
		PackedStringArray(["Existing debt payments", LoanApplication.dollars(application.monthly_debt_payments), ""]),
		PackedStringArray(["New loan payment", "%s (%d months at %.2f%%)" % [LoanApplication.dollars(application.new_loan_payment()), application.term_months(), application.annual_rate() * 100.0], ""]),
		PackedStringArray(["Front-end DTI", LoanApplication.percent(application.front_end_dti()), "Housing ÷ income: the share of pay that goes on housing."]),
		PackedStringArray(["Total DTI", LoanApplication.percent(application.total_dti()), "Housing + debts + new payment ÷ income. Policy guide: about 36% healthy, 43% stretched, 50% high."]),
		PackedStringArray(["Credit score", "%d — %s" % [application.credit_score, LoanApplication.credit_score_band(application.credit_score)], ""]),
		PackedStringArray(["Employment", LoanApplication.employment_text(application.employment_months), "Policy looks for two years in the same line of work."]),
		PackedStringArray(["Affordable at 36% total DTI", LoanApplication.dollars(application.affordable_amount()), "The largest loan keeping total DTI at a healthy 36%."]),
	]
	return rows

func _clear_worksheet() -> void:
	for child in worksheet_rows_vbox.get_children():
		worksheet_rows_vbox.remove_child(child)
		child.queue_free()

func _fill_worksheet(application: LoanApplication) -> void:
	_clear_worksheet()
	for row in worksheet_rows(application):
		var line := Label.new()
		line.text = "%s: %s" % [row[0], row[1]]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		worksheet_rows_vbox.add_child(line)
		if row[2] != "":
			var explanation := Label.new()
			explanation.theme_type_variation = &"MutedLabel"
			explanation.add_theme_font_size_override("font_size", EXPLANATION_FONT_SIZE)
			explanation.text = row[2]
			explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			worksheet_rows_vbox.add_child(explanation)

## The worksheet's text as shown, one line per label (for tests).
func worksheet_text() -> String:
	var lines: PackedStringArray = []
	for child in worksheet_rows_vbox.get_children():
		lines.append((child as Label).text)
	return "\n".join(lines)

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
	counter_offer_vbox.visible = true

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

func selected_reasons() -> Array[LoanApplication.DenialReason]:
	var reasons: Array[LoanApplication.DenialReason] = []
	for i in reason_checks.size():
		if reason_checks[i].button_pressed:
			reasons.append(i as LoanApplication.DenialReason)
	return reasons

func _on_submit_denial_button_pressed() -> void:
	var reasons := selected_reasons()
	if reasons.is_empty():
		return
	_record_decision(LoanApplication.DecisionType.REJECT, 0.0, "Rejected", reasons)

func _on_cancel_denial_button_pressed() -> void:
	reasons_vbox.visible = false
	decision_hbox.visible = true

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
	# Off the pile; the next one joins it.
	LoanDeskManager.player_decided(application)
	# Into the loan book (an approval or counter-offer), or counted as a good
	# applicant turned away.
	LoanBookManager.note_decision(application, true, LoanBookManager.PLAYER_MAKER)

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

## What the documents meant for this decision, one line each (revealing,
## after the fact, what was wrong with them).
static func documents_feedback(application: LoanApplication, result: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var problem := application.documents_problem_text()
	if result["caught"]:
		lines.append("Good catch: %s." % problem)
	elif not application.documents_check_out():
		if application.decision == LoanApplication.DecisionType.REJECT:
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
