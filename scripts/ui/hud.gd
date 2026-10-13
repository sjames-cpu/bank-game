extends CanvasLayer
class_name Hud

## Always-on HUD for the room (B4): career stats and shift status, the
## low-reputation and role-unlocked notifications, the first-run hints
## (HintManager), and the "E — ..." interaction prompt. Replaces the
## ScoreHudPanel and notification stack the desk screens used to carry, which
## only showed while a screen was open.
##
## Layout: stats, notifications and hints stack in one column in the
## top-right corner, outside
## every centred desk screen, letter and summary at the 1152x648 window (the
## widest, the Branch Manager shift summary, ends at x=946; the column starts
## at x=952). This layer draws above the UI layer so a hint's "Got it" button
## stays clickable while a screen's backdrop covers the room; the only
## full-screen letter (termination) hides the whole HUD instead.
##
## Doesn't know about desks, queues or screens itself: teller_room.gd sets
## shift_status and letter_screen, decides when hints fire (show_hint_once())
## and drives the prompt (show_prompt()/hide_prompt()). Processes while the
## tree is paused, so the stats stay live behind an open screen.

@onready var role_label: Label = $RightColumn/StatsPanel/VBox/RoleLabel
@onready var score_label: Label = $RightColumn/StatsPanel/VBox/ScoreLabel
@onready var reputation_label: Label = $RightColumn/StatsPanel/VBox/ReputationLabel
@onready var xp_label: Label = $RightColumn/StatsPanel/VBox/XPLabel
@onready var reports_label: Label = $RightColumn/StatsPanel/VBox/ReportsLabel
@onready var shift_label: Label = $RightColumn/StatsPanel/VBox/ShiftLabel
@onready var stats_panel: PanelContainer = $RightColumn/StatsPanel

## Stacked in one panel; each stays up while its condition holds (an unlock
## is never taken back within a career).
@onready var notification_panel: PanelContainer = $RightColumn/NotificationPanel
@onready var low_reputation_warning_label: Label = $RightColumn/NotificationPanel/NotificationStack/LowReputationWarningLabel
@onready var loan_officer_unlocked_label: Label = $RightColumn/NotificationPanel/NotificationStack/LoanOfficerUnlockedLabel
@onready var branch_manager_unlocked_label: Label = $RightColumn/NotificationPanel/NotificationStack/BranchManagerUnlockedLabel

@onready var hint_panel: PanelContainer = $RightColumn/HintPanel
@onready var hint_label: Label = $RightColumn/HintPanel/VBox/HintLabel
@onready var hint_dismiss_button: Button = $RightColumn/HintPanel/VBox/DismissButton

@onready var prompt_panel: PanelContainer = $PromptPanel
@onready var prompt_label: Label = $PromptPanel/PromptLabel

## Gap (in room pixels, so it holds at any camera zoom) between the
## interactable's position and the top of the prompt: the
## prompt sits below it, on the player's side, clear of a player standing at
## the desk (their feet reach ~48px below a desk's centre) and of the staff
## name labels above the counters.
const PROMPT_OFFSET_Y: float = 52.0

## Returns the shift-status line ("Off shift" / "On shift — ..."); set by
## teller_room.gd. Left unset, the HUD shows "Off shift".
var shift_status: Callable

## While this shows a full-screen letter (termination) the HUD hides.
var letter_screen: DisciplineLetterScreen

## The hint on screen (-1 if none) and the ones waiting behind it.
var current_hint: int = -1
var _hint_queue: Array[HintManager.Hint] = []

var _prompt_world_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hint_dismiss_button.pressed.connect(dismiss_hint)
	hint_panel.visible = false
	prompt_panel.visible = false
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	visible = letter_screen == null or not letter_screen.is_full_screen_letter_shown()
	role_label.text = "Role: %s" % role_name()
	score_label.text = "Score: %d" % ScoreManager.total_score
	reputation_label.text = "Reputation: %d" % ReputationManager.reputation
	xp_label.text = "XP: %d" % XPManager.total_xp
	reports_label.text = ReportManager.status_text()
	shift_label.text = shift_status.call() if shift_status.is_valid() else "Off shift"
	low_reputation_warning_label.visible = ReputationManager.reputation <= ReputationManager.LOW_REPUTATION_THRESHOLD
	loan_officer_unlocked_label.visible = XPManager.is_loan_officer_unlocked
	branch_manager_unlocked_label.visible = XPManager.is_branch_manager_unlocked
	notification_panel.visible = low_reputation_warning_label.visible or loan_officer_unlocked_label.visible or branch_manager_unlocked_label.visible
	# Any open desk screen pauses the tree, and the prompt belongs to the room.
	if get_tree().paused:
		prompt_panel.visible = false
	elif prompt_panel.visible:
		_place_prompt()

## The highest role the career has reached.
static func role_name() -> String:
	if XPManager.is_branch_manager_unlocked:
		return "Branch Manager"
	if XPManager.is_loan_officer_unlocked:
		return "Loan Officer"
	return "Teller"

# --- hints ------------------------------------------------------------------

## Shows `hint` unless this career has already seen it (HintManager). Queued
## behind any hint still on screen. Returns whether it was new.
func show_hint_once(hint: HintManager.Hint) -> bool:
	if not HintManager.mark_shown(hint):
		return false
	if current_hint == -1:
		_show_hint(hint)
	else:
		_hint_queue.append(hint)
	return true

func dismiss_hint() -> void:
	if _hint_queue.is_empty():
		current_hint = -1
		hint_panel.visible = false
	else:
		_show_hint(_hint_queue.pop_front())

func _show_hint(hint: HintManager.Hint) -> void:
	current_hint = hint
	hint_label.text = HintManager.text_for(hint)
	hint_panel.visible = true

# --- interaction prompt -----------------------------------------------------

## Shows `text` centred just below `world_position` (a point in the room).
func show_prompt(text: String, world_position: Vector2) -> void:
	_prompt_world_position = world_position
	if prompt_label.text != text:
		prompt_label.text = text
		prompt_panel.reset_size()
	prompt_panel.visible = not get_tree().paused
	_place_prompt()

func hide_prompt() -> void:
	prompt_panel.visible = false

func _place_prompt() -> void:
	var screen_position := get_viewport().get_canvas_transform() * (_prompt_world_position + Vector2(0, PROMPT_OFFSET_Y))
	prompt_panel.position = screen_position - Vector2(prompt_panel.size.x / 2.0, 0)
