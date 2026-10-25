extends Control
class_name LoanReviewScreen

## Loan review task screen: an underwriting worksheet (HANDOFF.md Phase 3).
## Pulls from LoanApplicationsData and cycles through the sample
## applications in order. The left column shows the application; "Run
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
@onready var applicant_name_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ApplicantNameLabel
@onready var requested_amount_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/RequestedAmountLabel
@onready var terms_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/TermsLabel
@onready var credit_score_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/CreditScoreLabel
@onready var annual_income_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/AnnualIncomeLabel
@onready var housing_payment_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/HousingPaymentLabel
@onready var existing_debt_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/ExistingDebtLabel
@onready var employment_label: Label = $Panel/VBox/Columns/LeftVBox/ApplicantSection/ApplicantVBox/EmploymentLabel
@onready var run_credit_check_button: Button = $Panel/VBox/Columns/LeftVBox/RunCreditCheckButton
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
@onready var close_button: Button = $Panel/VBox/CloseButton

signal decision_graded(score_delta: int, reputation_delta: int, xp_delta: int)
signal closed(was_decided: bool)

## Explanation lines under the worksheet's figures: smaller than body text.
const EXPLANATION_FONT_SIZE: int = 12

var applications: Array[LoanApplication] = []
var _next_application_index: int = 0
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
	approve_button.pressed.connect(_on_approve_button_pressed)
	reject_button.pressed.connect(_on_reject_button_pressed)
	counter_offer_button.pressed.connect(_on_counter_offer_button_pressed)
	submit_counter_offer_button.pressed.connect(_on_submit_counter_offer_button_pressed)
	cancel_counter_offer_button.pressed.connect(_on_cancel_counter_offer_button_pressed)
	submit_denial_button.pressed.connect(_on_submit_denial_button_pressed)
	cancel_denial_button.pressed.connect(_on_cancel_denial_button_pressed)
	for reason: int in LoanApplication.DenialReason.values():
		var check := CheckBox.new()
		check.text = LoanApplication.denial_reason_label(reason as LoanApplication.DenialReason)
		# Compact rows: the theme's button panel makes each twice as tall.
		var compact := StyleBoxEmpty.new()
		compact.content_margin_left = 4.0
		compact.content_margin_top = 2.0
		compact.content_margin_bottom = 2.0
		for style: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			check.add_theme_stylebox_override(style, compact)
		check.toggled.connect(_on_reason_toggled.bind(check))
		reason_checks_vbox.add_child(check)
		reason_checks.append(check)
	applications = LoanApplicationsData.get_applications()

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

## An application closed without a decision stays current — it's shown
## again (from a fresh, un-credit-checked state) next time rather than
## skipped, so only an actual Approve/Reject/Counter-Offer moves on to the
## next applicant.
func _display_next_application() -> void:
	if applications.is_empty():
		return

	var application := _current_application
	if application == null or _decision_made_for_current:
		application = applications[_next_application_index]
		_next_application_index = (_next_application_index + 1) % applications.size()
	_current_application = application
	_decision_made_for_current = false

	# Computed here (not shown) so it's available as soon as this applicant
	# is current — see risk_assessment on LoanApplication.
	application.risk_assessment = application.calculate_risk_assessment()

	applicant_name_label.text = application.applicant_name
	requested_amount_label.text = "Requested: %s %s loan" % [LoanApplication.dollars(application.requested_amount), application.loan_purpose.to_lower()]
	terms_label.text = terms_text(application)
	credit_score_label.text = "Credit score: %d" % application.credit_score
	annual_income_label.text = "Annual income: %s" % LoanApplication.dollars(application.annual_income)
	housing_payment_label.text = "Housing (rent or mortgage): %s/mo" % LoanApplication.dollars(application.monthly_housing_payment)
	existing_debt_label.text = "Existing debt: %s balance · %s/mo" % [LoanApplication.dollars(application.existing_debt), LoanApplication.dollars(application.monthly_debt_payments)]
	employment_label.text = "Employment: %s" % LoanApplication.employment_text(application.employment_months)

	run_credit_check_button.visible = true
	worksheet_placeholder_label.visible = true
	_clear_worksheet()
	decision_hbox.visible = false
	counter_offer_vbox.visible = false
	reasons_vbox.visible = false
	decision_status_label.visible = false

## "60 months at 7.00% (bank rate for auto loans) · policy maximum $75,000".
static func terms_text(application: LoanApplication) -> String:
	return "%d months at %.2f%% (bank rate for %s loans) · policy maximum %s" % [
		application.term_months(), application.annual_rate() * 100.0,
		application.loan_purpose.to_lower(), LoanApplication.dollars(application.policy_maximum()),
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
	credit_score_label.text = "Credit score: %d — %s" % [application.credit_score, LoanApplication.credit_score_band(application.credit_score)]
	worksheet_placeholder_label.visible = false
	_fill_worksheet(application)

	# Done with: hidden, leaving the column's room to the decisions.
	run_credit_check_button.visible = false

	# Decisions are gated behind having run the credit check first, so the
	# player can't decide blind.
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

	var grade := application.grade_decision()
	var score := LoanApplication.score_for_grade(grade)
	var reputation_delta := LoanApplication.reputation_for_grade(grade)
	var detail := ""
	if decision_type == LoanApplication.DecisionType.REJECT:
		var reason_grade := application.grade_denial_reasons(reasons)
		var reason_score: int = reason_grade["score"]
		score += reason_score
		detail = reasons_feedback(reason_grade)
	elif decision_type == LoanApplication.DecisionType.COUNTER_OFFER:
		detail = application.counter_offer_note(amount)
	var xp := score * XPManager.XP_PER_SCORE_POINT

	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	decision_hbox.visible = false
	counter_offer_vbox.visible = false
	reasons_vbox.visible = false
	decision_status_label.visible = true
	decision_status_label.text = "Decision recorded: %s\n%s (%+d Score, %+d Reputation, %+d XP)" % [action_text, LoanApplication.grade_description(grade), score, reputation_delta, xp]
	if detail != "":
		decision_status_label.text += "\n" + detail

	HistoryManager.add_loan_record(
		_history_description(decision_type, amount, reasons),
		LoanApplication.grade_description(grade),
		application.risk_assessment,
		decision_type,
		application.applicant_name,
		amount,
	)

	decision_graded.emit(score, reputation_delta, xp)

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
