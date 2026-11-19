extends RefCounted
class_name CharacterFx

## Gives a character (the player, customers, staff, applicants, guards, the
## Regional Manager) a ground shadow and a dark outline so it reads against
## the floor, and the small motion that makes it feel alive (CharacterMotion). Each character class calls attach() from its own _ready(), so
## every character, including ones created later, has them; nothing needs
## to be remembered per character, and both nodes are children, so they go
## when the character is freed.

const GROUP: StringName = &"fx_characters"
const SHADOW_NODE: StringName = &"GroundShadow"
const OUTLINE_NODE: StringName = &"Outline"
const MOTION_NODE: StringName = &"Motion"

## Adds the shadow and outline behind `sprite` (once).
static func attach(character: Node2D, sprite: AnimatedSprite2D) -> void:
	if character.has_node(NodePath(SHADOW_NODE)):
		return
	var outline := CharacterOutline.new()
	outline.name = OUTLINE_NODE
	outline.sprite = sprite
	var shadow := CharacterShadow.new()
	shadow.name = SHADOW_NODE
	character.add_child(outline)
	character.move_child(outline, 0)
	character.add_child(shadow)
	character.move_child(shadow, 0)
	# The small whole-pixel motion (breathing, settling, working), stepped
	# by CharacterMotionDriver; the shadow stays where it is.
	var motion := CharacterMotion.new()
	motion.name = MOTION_NODE
	motion.character = character
	motion.sprite = sprite
	motion.outline = outline
	character.add_child(motion)
	character.add_to_group(GROUP)

static func has_fx(character: Node) -> bool:
	return character.get_node_or_null(NodePath(SHADOW_NODE)) is CharacterShadow and character.get_node_or_null(NodePath(OUTLINE_NODE)) is CharacterOutline
