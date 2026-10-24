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

## "Day 3 · 10:42 AM" (GameClock), at the top of the column.
@onready var clock_label: Label = $RightColumn/StatsPanel/VBox/ClockLabel
@onready var role_label: Label = $RightColumn/StatsPanel/VBox/RoleLabel
@onready var score_label: Label = $RightColumn/StatsPanel/VBox/ScoreLabel
@onready var reputation_label: Label = $RightColumn/StatsPanel/VBox/ReputationLabel
@onready var xp_label: Label = $RightColumn/StatsPanel/VBox/XPLabel
@onready var reports_label: Label = $RightColumn/StatsPanel/VBox/ReportsLabel
## "Probation — 1 of 3 clean shifts", only while on probation.
@onready var probation_label: Label = $RightColumn/StatsPanel/VBox/ProbationLabel
## "Next review: Day 15 · Warnings 1/3", only while Branch Manager
## (RegionalManager).
@onready var regional_label: Label = $RightColumn/StatsPanel/VBox/RegionalLabel
@onready var shift_label: Label = $RightColumn/StatsPanel/VBox/ShiftLabel
@onready var stats_panel: PanelContainer = $RightColumn/StatsPanel

## Stacked in one panel. The low-reputation warning is a state: it stays up
## while Reputation is low. A role-unlocked notification is an event: shown
## once when the unlock happens (XPManager's signal, so never again after a
## save is loaded or the room reloads), then faded out
## (show_unlock_notification()).
@onready var notification_panel: PanelContainer = $RightColumn/NotificationPanel
@onready var low_reputation_warning_label: Label = $RightColumn/NotificationPanel/NotificationStack/LowReputationWarningLabel
@onready var loan_officer_unlocked_label: Label = $RightColumn/NotificationPanel/NotificationStack/LoanOfficerUnlockedLabel
@onready var branch_manager_unlocked_label: Label = $RightColumn/NotificationPanel/NotificationStack/BranchManagerUnlockedLabel

@onready var hint_panel: PanelContainer = $RightColumn/HintPanel
@onready var hint_label: Label = $RightColumn/HintPanel/VBox/HintScroll/HintLabel
## The hint text scrolls when the column has no room left for all of it
## (every notification up, a long hint): see _fit_hint().
@onready var hint_scroll: ScrollContainer = $RightColumn/HintPanel/VBox/HintScroll
@onready var hint_dismiss_button: Button = $RightColumn/HintPanel/VBox/DismissButton

## Always-on reminder of the keys, e.g. "E — interact · Z — zoom · Esc — menu", in the
## bottom-left corner (clear of the right column and every centred screen).
@onready var controls_panel: PanelContainer = $ControlsPanel
@onready var controls_label: Label = $ControlsPanel/ControlsLabel

@onready var prompt_panel: PanelContainer = $PromptPanel
@onready var prompt_label: Label = $PromptPanel/PromptLabel

## Gap (in room pixels, so it holds at any camera zoom) between the
## interactable's position and the top of the prompt: the
## prompt sits below it, on the player's side, clear of a player standing at
## the desk (their feet reach ~48px below a desk's centre) and of the staff
## name labels above the counters.
const PROMPT_OFFSET_Y: float = 52.0

## How long an unlock notification stays up, then how long it takes to fade.
## Real seconds, paused or not (the HUD always processes).
const UNLOCK_NOTIFICATION_SECONDS: float = 5.0
const UNLOCK_FADE_SECONDS: float = 0.6

## Unlock label -> the Tween showing and fading it.
var unlock_tweens: Dictionary[Label, Tween] = {}

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
	loan_officer_unlocked_label.visible = false
	branch_manager_unlocked_label.visible = false
	controls_label.text = controls_text()
	XPManager.loan_officer_unlocked.connect(show_unlock_notification.bind(loan_officer_unlocked_label))
	XPManager.branch_manager_unlocked.connect(show_unlock_notification.bind(branch_manager_unlocked_label))
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	visible = letter_screen == null or not letter_screen.is_full_screen_letter_shown()
	clock_label.text = GameClock.hud_text()
	role_label.text = "Role: %s" % role_name()
	score_label.text = "Score: %d" % ScoreManager.total_score
	reputation_label.text = "Reputation: %d" % ReputationManager.reputation
	xp_label.text = "XP: %d" % XPManager.total_xp
	reports_label.text = ReportManager.status_text()
	probation_label.text = InterviewManager.probation_status_text()
	probation_label.visible = probation_label.text != ""
	regional_label.text = RegionalManager.status_text()
	regional_label.visible = regional_label.text != ""
	# A Branch Manager has no reports ("n/a"): the Regional Manager's review
	# line takes its place.
	reports_label.visible = not regional_label.visible
	shift_label.text = shift_status.call() if shift_status.is_valid() else "Off shift"
	low_reputation_warning_label.visible = ReputationManager.reputation <= ReputationManager.LOW_REPUTATION_THRESHOLD
	notification_panel.visible = low_reputation_warning_label.visible or loan_officer_unlocked_label.visible or branch_manager_unlocked_label.visible
	_fit_hint()
	# Any open desk screen pauses the tree, and the prompt belongs to the room.
	if get_tree().paused:
		prompt_panel.visible = false
	elif prompt_panel.visible:
		_place_prompt()

## The column keeps this far from the bottom of the window.
const COLUMN_BOTTOM_MARGIN: float = 8.0

## Sizes the hint's text area to its text, but never taller than the room
## left under the stats and notifications: past that the text scrolls, so
## the column always ends inside the window, whatever the hint.
func _fit_hint() -> void:
	if not hint_panel.visible:
		return
	var column := hint_panel.get_parent() as Control
	var text_height := hint_label.get_minimum_size().y
	# A ScrollContainer adds only its own minimum height to the column.
	var without_text := column.get_combined_minimum_size().y - hint_scroll.custom_minimum_size.y
	# Against the 648px design height: the "expand" stretch never shows less,
	# and every screen is laid out for it.
	var design_height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	var window_height := minf(get_viewport().get_visible_rect().size.y, design_height)
	var room := window_height - COLUMN_BOTTOM_MARGIN - column.get_global_rect().position.y - without_text
	var height := clampf(text_height, 0.0, maxf(room, 0.0))
	if not is_equal_approx(hint_scroll.custom_minimum_size.y, height):
		hint_scroll.custom_minimum_size.y = height

## The controls line, with key names from the InputMap (InputPrompts), so
## it can't drift from the keys that actually work.
static func controls_text() -> String:
	return "%s — interact · %s — zoom · %s — menu" % [InputPrompts.key_for(InputPrompts.INTERACT), InputPrompts.key_for(InputPrompts.OVERVIEW), InputPrompts.key_for(InputPrompts.PAUSE_MENU)]

## The highest role the career has reached.
static func role_name() -> String:
	if XPManager.is_branch_manager_unlocked:
		return "Branch Manager"
	if XPManager.is_loan_officer_unlocked:
		return "Loan Officer"
	return "Teller"

# --- unlock notifications ---------------------------------------------------

## Shows `label` (an unlock notification) for UNLOCK_NOTIFICATION_SECONDS,
## then fades it out and hides it. Showing it again restarts the timer.
func show_unlock_notification(label: Label) -> void:
	var previous: Tween = unlock_tweens.get(label)
	if previous != null:
		previous.kill()
	label.modulate.a = 1.0
	label.visible = true
	var tween := create_tween()
	tween.tween_interval(UNLOCK_NOTIFICATION_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, UNLOCK_FADE_SECONDS)
	tween.tween_callback(_hide_unlock_notification.bind(label))
	unlock_tweens[label] = tween
	refresh()

func _hide_unlock_notification(label: Label) -> void:
	label.visible = false
	label.modulate.a = 1.0
	unlock_tweens.erase(label)
	refresh()

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
		var next_hint: HintManager.Hint = _hint_queue.pop_front()
		_show_hint(next_hint)

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
