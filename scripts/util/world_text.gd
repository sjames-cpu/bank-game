extends RefCounted
class_name WorldText

## Keeps world-space labels (staff names and speech, customer farewells)
## readable and crisp at any camera zoom (RoomCamera).
##
## A label in the world is magnified with everything else, so at 2x its
## 11px font would be 22px on screen, oversized and drawn from a texture
## made for 11px. Instead each registered label is rasterised at its
## on-screen size and scaled by 1/zoom, so it draws at exactly one texel per
## screen pixel. The on-screen size is the 1x design size times
## screen_scale(): 1.0 at 1x and FOLLOW_TEXT_SCALE at 2x, so text grows a
## little with the characters but never doubles. The label's box keeps its
## bottom-centre at the same point in the world (above the character), and
## its width grows with the text, so wrapping matches the 1x design.
##
## Labels register themselves (register(), from StaffNPC and CustomerNPC)
## and are refreshed when the camera zooms (set_zoom(), from RoomCamera).

const GROUP: StringName = &"world_text"
## On-screen text size at the 2x follow zoom, relative to the 1x design.
const FOLLOW_TEXT_SCALE: float = 1.25

## The current camera zoom, shared by every world label.
static var zoom_factor: float = 1.0

## The 1x design size and place, as metadata on each label.
const META_RECT: StringName = &"world_text_rect"
const META_FONT: StringName = &"world_text_font_size"
const META_OUTLINE: StringName = &"world_text_outline_size"

## How big world text is on screen at `zoom`, relative to its 1x design:
## 1.0 at 1x, FOLLOW_TEXT_SCALE at 2x (in between, linearly).
static func screen_scale(zoom: float) -> float:
	return lerpf(1.0, FOLLOW_TEXT_SCALE, clampf(zoom - 1.0, 0.0, 1.0))

## Remembers `label`'s 1x design (its rect, font size and outline as laid
## out in the scene) and fits it to the current zoom.
static func register(label: Label) -> void:
	if not label.has_meta(META_RECT):
		label.set_meta(META_RECT, Rect2(label.position, label.size))
		label.set_meta(META_FONT, label.get_theme_font_size("font_size"))
		label.set_meta(META_OUTLINE, label.get_theme_constant("outline_size"))
		label.add_to_group(GROUP)
		# New text can need a bigger box: refit, so it stays centred above
		# the character (Control's own grow directions ignore the label's
		# scale and would drift it sideways).
		label.minimum_size_changed.connect(apply.bind(label))
	apply(label)

static func apply(label: Label) -> void:
	var design: Rect2 = label.get_meta(META_RECT)
	var design_font: int = label.get_meta(META_FONT)
	var design_outline: int = label.get_meta(META_OUTLINE)
	var text_scale := screen_scale(zoom_factor)
	label.add_theme_font_size_override("font_size", roundi(design_font * text_scale))
	label.add_theme_constant_override("outline_size", roundi(design_outline * text_scale))
	label.scale = Vector2.ONE / zoom_factor
	# Local units are screen pixels; the box is the design box at text_scale,
	# or bigger if the text needs it (a label is never smaller than its text).
	label.size = design.size * text_scale
	var anchor := Vector2(design.get_center().x, design.end.y)
	label.position = anchor - Vector2(label.size.x / 2.0, label.size.y) / zoom_factor

## Sets the zoom every world label is fitted to, and refits the ones in
## `tree` now.
static func set_zoom(zoom: float, tree: SceneTree) -> void:
	zoom_factor = zoom
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		var label := node as Label
		if label != null:
			apply(label)
