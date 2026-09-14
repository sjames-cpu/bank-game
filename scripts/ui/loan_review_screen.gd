extends Control
class_name LoanReviewScreen

## Loan review task screen (Phase 4b-4f). Pulls from
## LoanApplicationsData (Phase 4a) and cycles through the sample
## applications in order. Phase 4c adds a "Run Credit Check" action that
## reveals calculated reference numbers (debt-to-income, loan-to-income,
## credit score band) so the player can reason about risk themselves — no
## risk tier or approve/reject hint is ever shown. Phase 4d adds the
## Approve/Reject/Counter-Offer decision itself, gated behind having run
## the credit check first (so the player can't decide blind). Phase 4e
## grades that decision against risk_assessment (see
## LoanApplication.grade_decision()) and applies the resulting
## Score/Reputation/XP consequences, the same add_shift_score() /
## add_reputation() / add_shift_xp() pattern teller_screen.gd uses for
## shift summaries.
##
## Each decision also logs a DecisionRecord to HistoryManager for the
## eventual Branch Manager review (Phase 5) — see _history_description().
##
## Phase 4f wires this into loan_officer_screen.gd's shift loop, which
## instances this screen once and calls show_screen() once per
## application in the shift: decision_graded (emitted alongside the
## Score/Reputation/XP calls above) lets the shift screen tally a running
## shift total without re-deriving it, and closed (emitted from
## hide_screen(), same as drawer_count_screen.gd) tells it when to
## advance to the next application or reveal the shift summary. closed
## carries whether the current application was actually decided before
## closing — the player can hit Close before deciding at all, and without
## that flag the shift loop would only count decided applications toward
## APPLICATIONS_PER_SHIFT, letting a skipped application be reopened
## indefinitely instead of consuming its slot.
##
## No caller existed yet when this screen was first built, so it still
## manages its own pause state the same defensive way drawer_count_screen.gd
## does (_paused_by_self tracks whether *this* screen was the one that
## paused, so hide_screen() never unpauses a tree something else still
## needs paused) — loan_officer_screen.gd pauses for the whole shift the
## same way teller_screen.gd does, so this stays defensive rather than
## assuming it's always the one in charge of pausing.

@onready var main_panel: Panel = $Panel
@onready var applicant_name_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/ApplicantNameLabel
@onready var requested_amount_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/RequestedAmountLabel
@onready var credit_score_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/CreditScoreLabel
@onready var annual_income_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/AnnualIncomeLabel
@onready var existing_debt_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/ExistingDebtLabel
@onready var loan_purpose_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/LoanPurposeLabel
@onready var run_credit_check_button: Button = $Panel/VBox/RunCreditCheckButton
@onready var debt_to_income_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/DebtToIncomeLabel
@onready var loan_to_income_label: Label = $Panel/VBox/ApplicantSection/ApplicantVBox/LoanToIncomeLabel
@onready var decision_hbox: HBoxContainer = $Panel/VBox/DecisionHBox
@onready var approve_button: Button = $Panel/VBox/DecisionHBox/ApproveButton
@onready var reject_button: Button = $Panel/VBox/DecisionHBox/RejectButton
@onready var counter_offer_button: Button = $Panel/VBox/DecisionHBox/CounterOfferButton
@onready var counter_offer_hbox: HBoxContainer = $Panel/VBox/CounterOfferHBox
@onready var counter_offer_amount_spinbox: SpinBox = $Panel/VBox/CounterOfferHBox/CounterOfferAmountSpinBox
@onready var submit_counter_offer_button: Button = $Panel/VBox/CounterOfferHBox/SubmitCounterOfferButton
@onready var cancel_counter_offer_button: Button = $Panel/VBox/CounterOfferHBox/CancelCounterOfferButton
@onready var decision_status_label: Label = $Panel/VBox/DecisionStatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

signal decision_graded(score_delta: int, reputation_delta: int, xp_delta: int)
signal closed(was_decided: bool)

var applications: Array[LoanApplication] = []
var _next_application_index: int = 0
var _paused_by_self: bool = false
var _current_application: LoanApplication = null

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

func _display_next_application() -> void:
	if applications.is_empty():
		return

	var application := applications[_next_application_index]
	_next_application_index = (_next_application_index + 1) % applications.size()
	_current_application = application
	_decision_made_for_current = false

	# Computed here (not shown yet) rather than on-demand later, so it's
	# available as soon as this applicant is current — see risk_assessment
	# doc on LoanApplication.
	application.risk_assessment = application.calculate_risk_assessment()

	applicant_name_label.text = application.applicant_name
	requested_amount_label.text = "Requested Amount: $%.2f" % application.requested_amount
	credit_score_label.text = "Credit Score: %d" % application.credit_score
	annual_income_label.text = "Annual Income: $%.2f" % application.annual_income
	existing_debt_label.text = "Existing Debt: $%.2f" % application.existing_debt
	loan_purpose_label.text = "Loan Purpose: %s" % application.loan_purpose

	run_credit_check_button.disabled = false
	debt_to_income_label.visible = false
	loan_to_income_label.visible = false
	decision_hbox.visible = false
	counter_offer_hbox.visible = false
	decision_status_label.visible = false

func _on_close_button_pressed() -> void:
	hide_screen()

func _on_run_credit_check_button_pressed() -> void:
	if _current_application == null:
		return

	var application := _current_application
	credit_score_label.text = "Credit Score: %d — %s" % [application.credit_score, LoanApplication.credit_score_band(application.credit_score)]
	debt_to_income_label.text = "Debt-to-Income: %.1f%%" % (application.debt_to_income_ratio() * 100.0)
	loan_to_income_label.text = "Loan-to-Income: %.1f%%" % (application.loan_to_income_ratio() * 100.0)
	debt_to_income_label.visible = true
	loan_to_income_label.visible = true

	run_credit_check_button.disabled = true

	# Decisions are gated behind having run the credit check first, so the
	# player can't decide blind.
	decision_hbox.visible = true

func _on_approve_button_pressed() -> void:
	_record_decision(LoanApplication.DecisionType.APPROVE, _current_application.requested_amount, "Approved at $%.2f" % _current_application.requested_amount)

func _on_reject_button_pressed() -> void:
	_record_decision(LoanApplication.DecisionType.REJECT, 0.0, "Rejected")

func _on_counter_offer_button_pressed() -> void:
	decision_hbox.visible = false
	counter_offer_amount_spinbox.value = _current_application.requested_amount
	counter_offer_hbox.visible = true

func _on_submit_counter_offer_button_pressed() -> void:
	_record_decision(LoanApplication.DecisionType.COUNTER_OFFER, counter_offer_amount_spinbox.value, "Counter-Offered at $%.2f" % counter_offer_amount_spinbox.value)

func _on_cancel_counter_offer_button_pressed() -> void:
	counter_offer_hbox.visible = false
	decision_hbox.visible = true

## Stores the decision on the current application, grades it against
## risk_assessment (Phase 4e), and applies the resulting Score/Reputation/XP
## consequences — the same add_shift_score()/add_reputation()/add_shift_xp()
## pattern teller_screen.gd uses for its shift summary.
func _record_decision(decision_type: LoanApplication.DecisionType, amount: float, action_text: String) -> void:
	if _current_application == null:
		return

	_current_application.decision = decision_type
	_current_application.decision_amount = amount
	_decision_made_for_current = true

	var grade := _current_application.grade_decision()
	var score := LoanApplication.score_for_grade(grade)
	var reputation_delta := LoanApplication.reputation_for_grade(grade)
	var xp := score * XPManager.XP_PER_SCORE_POINT

	ScoreManager.add_shift_score(score)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score)

	decision_hbox.visible = false
	counter_offer_hbox.visible = false
	decision_status_label.visible = true
	decision_status_label.text = "Decision recorded: %s\n%s (%+d Score, %+d Reputation, %+d XP)" % [action_text, LoanApplication.grade_description(grade), score, reputation_delta, xp]

	HistoryManager.add_loan_record(
		_history_description(decision_type, amount),
		LoanApplication.grade_description(grade),
		_current_application.risk_assessment,
		decision_type,
		_current_application.applicant_name,
		amount,
	)

	decision_graded.emit(score, reputation_delta, xp)

## Written only to HistoryManager for the future Branch Manager review
## (Phase 5) — unlike the rest of this screen, it names risk_assessment
## directly, since the whole point of the eventual review is to check a
## Loan Officer's decision against the risk they couldn't see. Never shown
## to the player during the decision itself.
func _history_description(decision_type: LoanApplication.DecisionType, amount: float) -> String:
	var applicant_name := _current_application.applicant_name
	var risk_label := LoanApplication.risk_tier_label(_current_application.risk_assessment)
	match decision_type:
		LoanApplication.DecisionType.APPROVE:
			return "Loan approved: $%.2f to %s (%s applicant)" % [amount, applicant_name, risk_label]
		LoanApplication.DecisionType.REJECT:
			return "Loan rejected: %s (%s applicant)" % [applicant_name, risk_label]
		_:
			return "Loan countered at $%.2f: %s (%s applicant)" % [amount, applicant_name, risk_label]
