extends Control
class_name ApprovalsScreen

## Branch Manager approvals screen (Phase 5d). Lists recent HistoryManager
## (5a) entries and lets the Branch Manager act on ones that haven't been
## reviewed yet:
##
## - Loan Officer entries can be "Overridden" — pick a different decision
##   (Approve/Reject/Counter-Offer) than the original, re-graded against
##   the SAME hidden risk_assessment the original decision was graded
##   against (LoanApplication.grade(), stored on the record by
##   HistoryManager.add_loan_record() — see DecisionRecord's doc comment
##   for why a frozen copy of the risk tier is kept there rather than a
##   live LoanApplication reference).
## - Teller entries get "Flag for Retraining" instead of a numeric
##   override: a drawer discrepancy is an objective fact (counted cash vs.
##   an expected balance), not a judgment call against a hidden variable,
##   so there's no alternate "decision" to re-grade and nothing to
##   justify reversing. Flagging just logs a note for a future retraining
##   mechanic — no Score/Reputation/XP change.
## - Past Branch Manager entries (this screen's own output) get no action
##   — there's nothing to review about a review.
##
## Phase 5f wires this into branch_manager_screen.gd's shift hub, which
## instances this screen and opens it from a menu button. review_completed
## (emitted alongside the Score/Reputation/XP calls each review action
## already makes) lets the hub tally a running shift total without
## re-deriving it — mirrors loan_review_screen.gd's decision_graded. closed
## (emitted from hide_screen(), same as drawer_count_screen.gd) is how the
## hub knows to bring its own menu back. class_name added for the same
## reason LoanReviewScreen got one in 4f — so the hub can hold a typed
## reference and connect to both signals directly.
##
## Manages its own pause state the same defensive way drawer_count_screen.gd
## does (_paused_by_self tracks whether *this* screen was the one that
## paused, so hide_screen() never unpauses a tree something else still
## needs paused) — branch_manager_screen.gd pauses for the whole shift the
## same way teller_screen.gd/loan_officer_screen.gd do, so this stays
## defensive rather than assuming it's always the one in charge of pausing.
##
## Reviewing an entry never deletes or rewrites its original
## description/grade_label — only its `reviewed` flag changes in place —
## and every review action logs a brand new BRANCH_MANAGER record, so the
## original decision and the review both stay visible in history.

signal closed
signal review_completed(score_delta: int, reputation_delta: int, xp_delta: int)

## How many of the most recent records to show — HistoryManager itself
## keeps everything, but an approvals inbox only needs to surface recent
## activity, not a full-session scrollback.
const MAX_VISIBLE_ENTRIES: int = 20

## Override outcome point table (Phase 5d). BRANCH_MANAGER_OVERRIDE_*
## apply to the Branch Manager's own Score/Reputation/XP (the same global
## totals every role feeds — this game doesn't track per-role totals) —
## magnitudes are pitched half of a Loan Officer's own BEST/WORST swing
## (LoanApplication.BEST_DECISION_SCORE=10), since catching (or missing)
## someone else's call after the fact is worth less than making the right
## call in the first place. Justified and unjustified use the same
## magnitude in opposite directions so overriding is a real bet, not a
## free action to try on every entry.
const BRANCH_MANAGER_OVERRIDE_JUSTIFIED_SCORE: int = 5
const BRANCH_MANAGER_OVERRIDE_JUSTIFIED_REPUTATION: int = 1
const BRANCH_MANAGER_OVERRIDE_UNJUSTIFIED_SCORE: int = -5
const BRANCH_MANAGER_OVERRIDE_UNJUSTIFIED_REPUTATION: int = -1

@onready var main_panel: Panel = $Panel
@onready var entries_vbox: VBoxContainer = $Panel/VBox/EntriesScrollContainer/EntriesVBox
@onready var close_button: Button = $Panel/VBox/CloseButton

@onready var override_panel: Panel = $OverridePanel
@onready var override_context_label: Label = $OverridePanel/VBox/OverrideContextLabel
@onready var approve_override_button: Button = $OverridePanel/VBox/OverrideButtonsHBox/ApproveOverrideButton
@onready var reject_override_button: Button = $OverridePanel/VBox/OverrideButtonsHBox/RejectOverrideButton
@onready var counter_offer_override_button: Button = $OverridePanel/VBox/OverrideButtonsHBox/CounterOfferOverrideButton
@onready var override_cancel_button: Button = $OverridePanel/VBox/OverrideCancelButton

@onready var result_panel: Panel = $ResultPanel
@onready var result_title_label: Label = $ResultPanel/VBox/ResultTitleLabel
@onready var result_detail_label: Label = $ResultPanel/VBox/ResultDetailLabel
@onready var result_done_button: Button = $ResultPanel/VBox/ResultDoneButton

var _paused_by_self: bool = false
var _selected_record: DecisionRecord = null

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	approve_override_button.pressed.connect(_on_approve_override_button_pressed)
	reject_override_button.pressed.connect(_on_reject_override_button_pressed)
	counter_offer_override_button.pressed.connect(_on_counter_offer_override_button_pressed)
	override_cancel_button.pressed.connect(_on_override_cancel_button_pressed)
	result_done_button.pressed.connect(_on_result_done_button_pressed)

func show_screen() -> void:
	_show_main_panel()
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

func _on_close_button_pressed() -> void:
	hide_screen()

func _show_main_panel() -> void:
	override_panel.visible = false
	result_panel.visible = false
	main_panel.visible = true
	_populate_entries()

func _populate_entries() -> void:
	for child in entries_vbox.get_children():
		child.queue_free()

	var records := HistoryManager.records
	var start_index: int = max(0, records.size() - MAX_VISIBLE_ENTRIES)

	if start_index > 0:
		var truncated_label := Label.new()
		truncated_label.text = "(%d earlier entries not shown)" % start_index
		entries_vbox.add_child(truncated_label)
		entries_vbox.add_child(HSeparator.new())

	# Most recent first, so the Branch Manager doesn't have to scroll past
	# a whole session's history to find what just happened.
	for i in range(records.size() - 1, start_index - 1, -1):
		_add_entry_row(records[i])

func _add_entry_row(record: DecisionRecord) -> void:
	var row := Label.new()
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reviewed_suffix := " (Reviewed)" if record.reviewed else ""
	row.text = "[%s] %s\n%s%s" % [DecisionRecord.role_label(record.role), record.description, record.grade_label, reviewed_suffix]
	entries_vbox.add_child(row)

	if not record.reviewed:
		if record.role == DecisionRecord.Role.LOAN_OFFICER:
			var override_button := Button.new()
			override_button.text = "Override"
			override_button.pressed.connect(_on_override_button_pressed.bind(record))
			entries_vbox.add_child(override_button)
		elif record.role == DecisionRecord.Role.TELLER:
			var flag_button := Button.new()
			flag_button.text = "Flag for Retraining"
			flag_button.pressed.connect(_on_flag_for_retraining_button_pressed.bind(record))
			entries_vbox.add_child(flag_button)

	entries_vbox.add_child(HSeparator.new())

func _on_override_button_pressed(record: DecisionRecord) -> void:
	_selected_record = record
	main_panel.visible = false
	override_panel.visible = true
	override_context_label.text = "Applicant: %s ($%.2f requested)\nOriginal decision: %s" % [record.applicant_name, record.decision_amount, LoanApplication.decision_type_label(record.original_decision_type)]

func _on_override_cancel_button_pressed() -> void:
	_selected_record = null
	override_panel.visible = false
	main_panel.visible = true

func _on_approve_override_button_pressed() -> void:
	_resolve_override(LoanApplication.DecisionType.APPROVE)

func _on_reject_override_button_pressed() -> void:
	_resolve_override(LoanApplication.DecisionType.REJECT)

func _on_counter_offer_override_button_pressed() -> void:
	_resolve_override(LoanApplication.DecisionType.COUNTER_OFFER)

## Re-grades the override decision against the same risk_assessment the
## original decision was graded against (see class doc comment), then
## decides Justified/Unjustified purely by comparing the two resulting
## scores — strictly better is Justified, same or worse is Unjustified.
func _resolve_override(override_decision_type: LoanApplication.DecisionType) -> void:
	var record := _selected_record
	if record == null:
		return

	var old_grade := LoanApplication.grade(record.original_decision_type, record.risk_assessment)
	var new_grade := LoanApplication.grade(override_decision_type, record.risk_assessment)
	var old_score := LoanApplication.score_for_grade(old_grade)
	var new_score := LoanApplication.score_for_grade(new_grade)
	var old_reputation := LoanApplication.reputation_for_grade(old_grade)

	var justified := new_score > old_score
	var score_delta: int
	var reputation_delta: int

	if justified:
		# Partially (not fully) undo the original decision's penalty, if
		# it had one — a correction after the fact still means the bad
		# call happened, so it shouldn't retroactively become a non-event.
		# Half, rounded up so even a small original penalty (e.g. -1
		# Reputation) still visibly reverses instead of rounding to 0.
		var reversal_score := int(ceil(abs(old_score) / 2.0)) if old_score < 0 else 0
		var reversal_reputation := int(ceil(abs(old_reputation) / 2.0)) if old_reputation < 0 else 0
		score_delta = reversal_score + BRANCH_MANAGER_OVERRIDE_JUSTIFIED_SCORE
		reputation_delta = reversal_reputation + BRANCH_MANAGER_OVERRIDE_JUSTIFIED_REPUTATION
	else:
		score_delta = BRANCH_MANAGER_OVERRIDE_UNJUSTIFIED_SCORE
		reputation_delta = BRANCH_MANAGER_OVERRIDE_UNJUSTIFIED_REPUTATION

	ScoreManager.add_shift_score(score_delta)
	ReputationManager.add_reputation(reputation_delta)
	XPManager.add_shift_xp(score_delta)

	record.reviewed = true

	var outcome_label := "Justified" if justified else "Unjustified"
	HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER,
		"Override on %s's loan: %s → %s (%s)" % [record.applicant_name, LoanApplication.decision_type_label(record.original_decision_type), LoanApplication.decision_type_label(override_decision_type), outcome_label],
		outcome_label,
	)

	result_title_label.text = outcome_label
	result_detail_label.text = "%s (%+d Score, %+d Reputation)" % [LoanApplication.grade_description(new_grade), score_delta, reputation_delta]

	_selected_record = null
	override_panel.visible = false
	result_panel.visible = true

	review_completed.emit(score_delta, reputation_delta, score_delta * XPManager.XP_PER_SCORE_POINT)

func _on_flag_for_retraining_button_pressed(record: DecisionRecord) -> void:
	record.reviewed = true
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Flagged for retraining: %s" % record.description, "Flagged")

	result_title_label.text = "Flagged for Retraining"
	result_detail_label.text = "No scoring impact — logged for review."

	main_panel.visible = false
	result_panel.visible = true

	review_completed.emit(0, 0, 0)

func _on_result_done_button_pressed() -> void:
	_show_main_panel()
