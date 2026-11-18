extends Node2D
class_name WallSign

## A small plate with a zone's name (TELLERS, LOANS, VAULT, MANAGER). The
## text goes through WorldText, so it stays crisp at either camera zoom; the
## plate behind it is refitted to the text when the zoom changes
## (refresh(), from the room). Signs stay visible at the 1x overview.

const GROUP: StringName = &"wall_signs"
const PLATE: Color = Color(0.1, 0.09, 0.16, 0.9)
const BORDER: Color = Color(0.85, 0.7, 0.35, 1.0)
const TEXT: Color = Color(1.0, 0.95, 0.8, 1.0)
const FONT_SIZE: int = 10
const PADDING: float = 8.0

var text: String = ""
var label: Label

## Builds one on `parent`, with its text's bottom-centre at `at`.
static func create(parent: Node2D, label_text: String, at: Vector2) -> WallSign:
	var sign_node := WallSign.new()
	sign_node.name = "Sign" + label_text.capitalize().replace(" ", "")
	sign_node.text = label_text
	sign_node.position = at
	parent.add_child(sign_node)
	return sign_node

func _ready() -> void:
	label = Label.new()
	label.name = "Text"
	label.text = text
	# Tall enough for the text at every zoom (WorldText anchors the box's bottom).
	label.position = Vector2(-36, -18)
	label.size = Vector2(72, 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_constant_override("outline_size", 0)
	add_child(label)
	WorldText.register(label)
	add_to_group(GROUP)
	refresh()

## Fits the plate to the label as the current zoom has sized it.
func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if label == null:
		return
	# The label's box as WorldText has placed and scaled it, in sign space;
	# the plate is the box, widened or narrowed to the text.
	var box := Rect2(label.position, label.size * label.scale)
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + PADDING) * label.scale.x
	var plate := Rect2(box.get_center().x - width / 2.0, box.position.y, width, box.size.y)
	draw_rect(plate, PLATE, true)
	draw_rect(plate, BORDER, false, 1.0 / WorldText.zoom_factor)
