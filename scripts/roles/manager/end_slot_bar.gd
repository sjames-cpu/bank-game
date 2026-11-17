extends CanvasLayer
class_name EndSlotBar

## The Branch Manager's "End this slot" bar (decision 7), at the top centre
## of the screen: the current slot's name and the button. Shown only on a
## Branch Manager day inside one of their work slots, with nothing else
## pausing the game (so never over a desk screen, letter or the card). Clear
## of the HUD column (top right), the controls line (bottom left), the desk
## notice (bottom centre) and the "E — …" prompts, which always sit below
## their interactable, well under the bar (manager_slots_test.gd checks).
## Built in code; ManagerSlotAdapter places it and does the work.

## The bar's narrowest width.
const BAR_WIDTH: float = 380.0
const TOP_MARGIN: float = 8.0
const END_SLOT_TEXT: String = "End this slot"
const SLOT_TEXT: String = "%s slot"
## After "End this slot", while an event still holds the slot (only the
## armored truck does).
const HELD_TEXT: String = "%s slot — waiting for the armored truck"

var adapter: ManagerSlotAdapter
var panel: PanelContainer
var label: Label
var end_button: Button

func _init() -> void:
	layer = 2
	# Hides itself while anything pauses the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://themes/banking_theme.tres")
	add_child(root)
	panel = PanelContainer.new()
	panel.name = "Panel"
	# Centred, at least BAR_WIDTH wide, growing both ways to fit its text.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_top = TOP_MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	end_button = Button.new()
	end_button.text = END_SLOT_TEXT
	end_button.theme_type_variation = &"PrimaryButton"
	end_button.focus_mode = Control.FOCUS_NONE
	end_button.pressed.connect(_on_end_pressed)
	row.add_child(end_button)
	visible = false

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var shown := adapter != null and adapter.in_work_slot() and not get_tree().paused
	visible = shown
	if not shown:
		return
	var slot_label := DayFlow.current_slot().label
	var waiting := not adapter.can_end_slot() and DayFlow.is_held()
	label.text = (HELD_TEXT if waiting else SLOT_TEXT) % slot_label
	end_button.disabled = not adapter.can_end_slot()

func _on_end_pressed() -> void:
	adapter.end_slot()
	refresh()
