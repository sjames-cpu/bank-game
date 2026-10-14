extends RefCounted
class_name InputPrompts

## Key names for on-screen prompts and hints, read from the InputMap so the
## text can't drift from the keys that actually work (B4).

## The desk/ATM interact action (project.godot [input]). The desks also
## accept ui_accept (Enter/Space); prompts only name this one.
const INTERACT: StringName = &"interact"
## Switches the camera between the close follow view and the overview
## (RoomCamera).
const OVERVIEW: StringName = &"toggle_overview"

## Display name of the first key bound to `action`, e.g. "E". Empty if the
## action has no key.
static func key_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		var keycode := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
		return OS.get_keycode_string(keycode)
	return ""
