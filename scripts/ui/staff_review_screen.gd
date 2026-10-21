extends Control
class_name StaffReviewScreen

## Branch Manager staff review (NPC coworkers, step 4). Shows
## StaffReviewManager's queue one item at a time (oldest first, < > to
## browse): who, which desk, when, what happened, and the staff member's
## record so far. The manager picks Issue Report / Give Feedback / Excuse;
## the item's severity and (for loans) the hidden grade are only revealed
## in the result line after they've decided. Staff who have reached
## StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION get a "Terminate
## Employment" button here — the manager's choice.
##
## Opened from branch_manager_screen.gd's hub, which tallies review_completed
## into the shift total and returns to its menu on closed. Pauses the tree
## defensively, like the hub's other sub-screens.

signal closed
signal review_completed(score_delta: int, reputation_delta: int, xp_delta: int)

@onready var queue_label: Label = $Panel/VBox/QueueHBox/QueueLabel
@onready var prev_button: Button = $Panel/VBox/QueueHBox/PrevButton
@onready var next_button: Button = $Panel/VBox/QueueHBox/NextButton
@onready var item_section: PanelContainer = $Panel/VBox/ItemSection
@onready var staff_label: Label = $Panel/VBox/ItemSection/ItemVBox/StaffLabel
@onready var record_label: Label = $Panel/VBox/ItemSection/ItemVBox/RecordLabel
@onready var details_label: Label = $Panel/VBox/ItemSection/ItemVBox/DetailsLabel
@onready var actions_hbox: HBoxContainer = $Panel/VBox/ActionsHBox
@onready var report_button: Button = $Panel/VBox/ActionsHBox/ReportButton
@onready var feedback_button: Button = $Panel/VBox/ActionsHBox/FeedbackButton
@onready var excuse_button: Button = $Panel/VBox/ActionsHBox/ExcuseButton
@onready var result_label: Label = $Panel/VBox/ResultLabel
@onready var terminate_vbox: VBoxContainer = $Panel/VBox/TerminateVBox
@onready var close_button: Button = $Panel/VBox/CloseButton

const FAIR_COLOR: Color = Color(0.3, 1, 0.3, 1)
const UNFAIR_COLOR: Color = Color(1, 0.45, 0.35, 1)

var _paused_by_self: bool = false
var _index: int = 0

func _ready() -> void:
	visible = false
	prev_button.pressed.connect(_step.bind(-1))
	next_button.pressed.connect(_step.bind(1))
	report_button.pressed.connect(_decide.bind(StaffReviewManager.Action.REPORT))
	feedback_button.pressed.connect(_decide.bind(StaffReviewManager.Action.FEEDBACK))
	excuse_button.pressed.connect(_decide.bind(StaffReviewManager.Action.EXCUSE))
	close_button.pressed.connect(hide_screen)

func show_screen() -> void:
	_index = 0
	result_label.visible = false
	_refresh()
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
	closed.emit()

## The item currently shown, or null when the queue is empty.
func current_item() -> StaffReviewItem:
	var queue := StaffReviewManager.queue
	if queue.is_empty():
		return null
	return queue[clampi(_index, 0, queue.size() - 1)]

func _step(delta: int) -> void:
	_index = clampi(_index + delta, 0, maxi(0, StaffReviewManager.queue.size() - 1))
	_refresh()

func _decide(action: StaffReviewManager.Action) -> void:
	var item := current_item()
	if item == null:
		return
	var result := StaffReviewManager.decide(item, action)
	result_label.text = _result_text(item, result)
	result_label.modulate = FAIR_COLOR if result["fair"] else UNFAIR_COLOR
	result_label.visible = true
	review_completed.emit(result["score"], result["reputation"], result["xp"])
	_refresh()

func _refresh() -> void:
	var queue := StaffReviewManager.queue
	_index = clampi(_index, 0, maxi(0, queue.size() - 1))
	var item := current_item()
	item_section.visible = item != null
	actions_hbox.visible = item != null
	prev_button.disabled = _index <= 0
	next_button.disabled = _index >= queue.size() - 1
	if item == null:
		queue_label.text = "No staff work waiting for review."
	else:
		queue_label.text = "Item %d of %d waiting for review" % [_index + 1, queue.size()]
		staff_label.text = "%s — %s — %s" % [item.staff_name, item.staff_slot, item.timestamp]
		record_label.text = StaffReviewManager.record_text(item.staff_name)
		details_label.text = details_text(item)
	_refresh_terminations()

func _refresh_terminations() -> void:
	for child in terminate_vbox.get_children():
		terminate_vbox.remove_child(child)
		child.queue_free()
	for staff_name in StaffReviewManager.terminable_staff():
		var button := Button.new()
		button.text = "Terminate Employment — %s (%d reports)" % [staff_name, StaffReviewManager.reports_for(staff_name)]
		button.pressed.connect(_on_terminate_pressed.bind(staff_name))
		terminate_vbox.add_child(button)
	terminate_vbox.visible = terminate_vbox.get_child_count() > 0

func _on_terminate_pressed(staff_name: String) -> void:
	if StaffReviewManager.terminate(staff_name):
		result_label.text = "%s has been let go. Their desk is now unassigned." % staff_name
		result_label.modulate = Color(1, 1, 1, 1)
		result_label.visible = true
	_refresh()

## What happened, without the hidden severity or loan grade.
static func details_text(item: StaffReviewItem) -> String:
	if item.kind == StaffReviewItem.Kind.TELLER:
		var verb := "deposit" if item.request_type == ShiftTransaction.Type.DEPOSIT else "withdraw"
		return "Customer %s asked to %s %s.\nThe staff member %s; the customer pointed it out and it was fixed on the spot." % [
			item.customer_name, verb, MoneyMath.format(item.request_amount_cents, true), item.mistake_detail,
		]
	var decision := LoanApplication.decision_type_label(item.decision)
	if item.decision != LoanApplication.DecisionType.REJECT:
		decision += " ($%s)" % _thousands(item.decision_amount)
	return "Applicant: %s — $%s %s loan\nCredit score %d · Income $%s/yr · Debt payments $%s/mo\nDTI %.1f%% · Loan-to-income %.0f%%\nDecision: %s" % [
		item.applicant_name, _thousands(item.requested_amount), item.loan_purpose.to_lower(),
		item.credit_score, _thousands(item.annual_income), _thousands(item.monthly_debt_payments),
		item.debt_to_income * 100.0, item.loan_to_income * 100.0,
		decision,
	]

## Revealed only after the decision: severity, the verdict and points, and
## for loans the grade the decision got.
static func _result_text(item: StaffReviewItem, result: Dictionary) -> String:
	var points: PackedStringArray = []
	if result["score"] != 0:
		points.append("%+d Score" % result["score"])
	if result["xp"] != 0:
		points.append("%+d XP" % result["xp"])
	if result["reputation"] != 0:
		points.append("%+d Reputation" % result["reputation"])
	# The screen has already moved on to the next item, so name whose work
	# this verdict is about.
	var severity: StaffReviewItem.Severity = result["severity"]
	var text := "%s (%s): %s" % [item.staff_name, StaffReviewManager.severity_label(severity), result["explanation"]]
	if not points.is_empty():
		text += " (%s)" % ", ".join(points)
	if item.kind == StaffReviewItem.Kind.LOAN:
		text += "\nGraded: %s." % LoanApplication.grade_description(item.grade)
	return text

static func _thousands(amount: float) -> String:
	var digits := str(roundi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out
