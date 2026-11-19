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

## "Wed, Day 3 · 10:42 AM" (GameClock), at the top of the column; with
## time slots "Wed, Day 3 · 11 AM slot" (SlotStatus).
@onready var clock_label: Label = $RightColumn/StatsPanel/VBox/ClockLabel
## How the player's slot is going ("Customers: 1 / 2"),
## from whichever slot piece answers (SlotStatus); hidden otherwise.
@onready var slot_label: Label = $RightColumn/StatsPanel/VBox/SlotLabel
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

## Score, Reputation and XP count to a new value with a brief green or red
## flash (HudCounter; stage 2b interface motion), and the slot line
## crossfades when its text changes. With Effects Off both happen at once.
var score_counter := HudCounter.new()
var reputation_counter := HudCounter.new()
var xp_counter := HudCounter.new()
const SLOT_FADE_SECONDS: float = 0.15
var _slot_text: String = ""
var _slot_seen: bool = false
## 0 to 1: how far the slot line's crossfade has got (1: done).
var _slot_fade: float = 1.0
var _slot_ghost: Label

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

func _process(delta: float) -> void:
	step_motion(delta)
	refresh()

## Steps the counters and the slot line's crossfade by `delta` seconds
## (also what tests call to step time by hand).
func step_motion(delta: float) -> void:
	if not EffectsSetting.is_on():
		score_counter.finish()
		reputation_counter.finish()
		xp_counter.finish()
		_slot_fade = 1.0
	else:
		score_counter.step(delta)
		reputation_counter.step(delta)
		xp_counter.step(delta)
		_slot_fade = minf(_slot_fade + delta / SLOT_FADE_SECONDS, 1.0)
	_show_counters()
	_show_slot_fade()

func refresh() -> void:
	visible = letter_screen == null or not letter_screen.is_full_screen_letter_shown()
	# "Wed, Day 3 · 11 AM slot" (SlotStatus).
	clock_label.text = SlotStatus.clock_text()
	var slot_text := SlotStatus.status_text(get_tree())
	if slot_text != _slot_text:
		_slot_text_changed(_slot_text, slot_text)
	slot_label.text = slot_text
	slot_label.visible = slot_text != ""
	role_label.text = "Role: %s" % role_name()
	var animate := EffectsSetting.is_on()
	score_counter.set_target(ScoreManager.total_score, animate)
	reputation_counter.set_target(ReputationManager.reputation, animate)
	xp_counter.set_target(XPManager.total_xp, animate)
	_show_counters()
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

func _show_counters() -> void:
	score_label.text = "Score: %d" % score_counter.value()
	reputation_label.text = "Reputation: %d" % reputation_counter.value()
	xp_label.text = "XP: %d" % xp_counter.value()
	_tint(score_label, score_counter.tint())
	_tint(reputation_label, reputation_counter.tint())
	_tint(xp_label, xp_counter.tint())

static func _tint(label: Label, color: Color) -> void:
	if label.self_modulate != color:
		label.self_modulate = color

## The slot line's text changed from `old` to `new`: the old text fades out
## over the new one fading in (a ghost label over the line), unless effects
## are off or one of them is empty (the line then simply appears or goes).
func _slot_text_changed(old: String, new: String) -> void:
	_slot_text = new
	var first := not _slot_seen
	_slot_seen = true
	if first or not EffectsSetting.is_on() or new == "":
		_slot_fade = 1.0
		return
	_slot_fade = 0.0
	if old != "":
		if _slot_ghost == null:
			_slot_ghost = Label.new()
			_slot_ghost.name = "SlotGhost"
			_slot_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_slot_ghost.autowrap_mode = slot_label.autowrap_mode
			_slot_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
			slot_label.add_child(_slot_ghost)
		_slot_ghost.text = old
		_slot_ghost.visible = true
	_show_slot_fade()

func _show_slot_fade() -> void:
	var alpha := _slot_fade if _slot_fade < 1.0 else 1.0
	if slot_label.self_modulate.a != alpha:
		slot_label.self_modulate.a = alpha
	if _slot_ghost != null and _slot_ghost.visible:
		if _slot_fade >= 1.0:
			_slot_ghost.visible = false
		else:
			_slot_ghost.modulate.a = 1.0 - _slot_fade

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
	# Retired hints (the onboarding training covers them) never show.
	if HintManager.RETIRED.has(hint) or not HintManager.mark_shown(hint):
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
