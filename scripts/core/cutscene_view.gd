extends CanvasLayer
class_name CutsceneView

## What a cutscene looks like (built in code; Cutscenes drives it): the
## characters standing left and right, a fade to black, and at the bottom a
## dialogue box (speaker, line, Skip and Next) or a choice box (prompt, two
## options, Skip), with "Skip this scene?" (Yes / No) over everything when
## asked. Styled like the letters (the banking theme); drawn above the HUD
## and the slot card, clear of the HUD column and the controls line
## (cutscene_test.gd checks the fit).

signal next_pressed
signal option_chosen(option: int)
signal skip_pressed
signal skip_answered(yes: bool)

const PANEL_WIDTH: float = 640.0
## The dialogue and choice boxes' bottom edge, above the window's bottom.
const PANEL_BOTTOM_MARGIN: float = 64.0
const CHARACTER_SCALE: float = 8.0
## Where characters stand (their feet near the dialogue box).
const SIDE_POSITIONS: Dictionary = {"left": Vector2(330, 360), "right": Vector2(822, 360)}

var fade: ColorRect
var dialogue_panel: PanelContainer
var speaker_label: Label
var line_label: Label
var next_button: Button
var choice_panel: PanelContainer
var prompt_label: Label
var option_buttons: Array[Button] = []
var confirm_panel: PanelContainer
var confirm_label: Label
var yes_button: Button
var no_button: Button
## Characters on screen, by name.
var characters: Dictionary[String, AnimatedSprite2D] = {}
var _stage: Control

func _init() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = load("res://themes/banking_theme.tres")
	add_child(root)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

	# The dialogue box.
	dialogue_panel = _bottom_panel(root, "DialoguePanel")
	var dialogue_box := VBoxContainer.new()
	dialogue_box.add_theme_constant_override("separation", 8)
	dialogue_panel.add_child(dialogue_box)
	speaker_label = Label.new()
	speaker_label.theme_type_variation = &"HeaderLabel"
	dialogue_box.add_child(speaker_label)
	line_label = Label.new()
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	dialogue_box.add_child(line_label)
	var dialogue_buttons := HBoxContainer.new()
	dialogue_box.add_child(dialogue_buttons)
	dialogue_buttons.add_child(_skip_button())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_buttons.add_child(spacer)
	next_button = Button.new()
	next_button.text = "Next"
	next_button.theme_type_variation = &"PrimaryButton"
	# Enter and Space move on through Cutscenes, not through this button.
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.pressed.connect(func() -> void: next_pressed.emit())
	dialogue_buttons.add_child(next_button)

	# The choice box.
	choice_panel = _bottom_panel(root, "ChoicePanel")
	var choice_box := VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 8)
	choice_panel.add_child(choice_box)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	choice_box.add_child(prompt_label)
	for i in 2:
		var option := Button.new()
		option.custom_minimum_size = Vector2(0, 40)
		option.pressed.connect(func() -> void: option_chosen.emit(i))
		choice_box.add_child(option)
		option_buttons.append(option)
	choice_box.add_child(_skip_button())

	# "Skip this scene?"
	confirm_panel = PanelContainer.new()
	confirm_panel.name = "ConfirmPanel"
	confirm_panel.set_anchors_preset(Control.PRESET_CENTER)
	confirm_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	confirm_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	confirm_panel.custom_minimum_size = Vector2(320, 0)
	root.add_child(confirm_panel)
	var confirm_box := VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 10)
	confirm_panel.add_child(confirm_box)
	confirm_label = Label.new()
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_box.add_child(confirm_label)
	var confirm_buttons := HBoxContainer.new()
	confirm_buttons.add_theme_constant_override("separation", 10)
	confirm_box.add_child(confirm_buttons)
	yes_button = Button.new()
	yes_button.text = "Yes"
	yes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_button.pressed.connect(func() -> void: skip_answered.emit(true))
	confirm_buttons.add_child(yes_button)
	no_button = Button.new()
	no_button.text = "No"
	no_button.theme_type_variation = &"PrimaryButton"
	no_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_button.pressed.connect(func() -> void: skip_answered.emit(false))
	confirm_buttons.add_child(no_button)

	dialogue_panel.visible = false
	choice_panel.visible = false
	confirm_panel.visible = false

## A box at the bottom centre, PANEL_WIDTH wide, growing upwards (its
## height placed in _ready()).
func _bottom_panel(root: Control, panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	return panel

## Like the other screens, the boxes are placed against the 648 px design
## height (or the window, if that's shorter), measured from the top: the
## "expand" stretch can make the window taller, never shorter.
func _ready() -> void:
	var design_height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	var height := minf(get_viewport().get_visible_rect().size.y, design_height)
	for box: PanelContainer in [dialogue_panel, choice_panel]:
		box.offset_top = height - PANEL_BOTTOM_MARGIN
		box.offset_bottom = height - PANEL_BOTTOM_MARGIN
	confirm_panel.anchor_top = 0.0
	confirm_panel.anchor_bottom = 0.0
	confirm_panel.offset_top = height / 2.0
	confirm_panel.offset_bottom = height / 2.0

func _skip_button() -> Button:
	var skip := Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func() -> void: skip_pressed.emit())
	return skip

func show_line(speaker: String, line: String) -> void:
	choice_panel.visible = false
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	line_label.text = line
	dialogue_panel.visible = true

func show_choice(prompt: String, first: String, second: String) -> void:
	dialogue_panel.visible = false
	prompt_label.text = prompt
	option_buttons[0].text = first
	option_buttons[1].text = second
	choice_panel.visible = true
	option_buttons[0].grab_focus()

func hide_dialogue() -> void:
	dialogue_panel.visible = false
	choice_panel.visible = false

func show_character(character: String, side: String) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.name = character
	sprite.sprite_frames = CutsceneScene.frames_for(character)
	sprite.scale = Vector2(CHARACTER_SCALE, CHARACTER_SCALE)
	sprite.position = SIDE_POSITIONS[side]
	sprite.flip_h = side == "right"
	sprite.play(&"idle_down")
	_stage.add_child(sprite)
	characters[character] = sprite

func hide_character(character: String) -> void:
	var sprite: AnimatedSprite2D = characters.get(character)
	if sprite != null:
		sprite.queue_free()
	characters.erase(character)

func fade_alpha() -> float:
	return fade.color.a

func set_fade(alpha: float) -> void:
	fade.color.a = clampf(alpha, 0.0, 1.0)

func show_skip_confirm(text: String) -> void:
	confirm_label.text = text
	confirm_panel.visible = true
	no_button.grab_focus()

func hide_skip_confirm() -> void:
	confirm_panel.visible = false
	if choice_panel.visible:
		option_buttons[0].grab_focus()
