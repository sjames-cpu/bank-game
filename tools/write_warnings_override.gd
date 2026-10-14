extends SceneTree

## Writes override.cfg (project root) raising every GDScript warning the
## project enables (level Warn in project.godot) to Error, so CI fails on any
## warning: warnings never print when a script loads, but errors do. Godot
## reads override.cfg at startup, so the warnings only become errors for
## the next Godot run; run_tests.sh deletes the file afterwards, and the
## editor keeps showing them as warnings. See tools/check_scripts.gd.
##
##   godot --headless --path . -s res://tools/write_warnings_override.gd

const PREFIX := "debug/gdscript/warnings/"

func _init() -> void:
	var config := ConfigFile.new()
	var raised := 0
	for property in ProjectSettings.get_property_list():
		var setting: String = property["name"]
		if not setting.begins_with(PREFIX):
			continue
		var level: Variant = ProjectSettings.get_setting(setting)
		if typeof(level) == TYPE_INT and level == 1:
			config.set_value("debug", setting.trim_prefix("debug/"), 2)
			raised += 1
	var error := config.save("res://override.cfg")
	if error != OK:
		printerr("ERROR: could not write override.cfg (%s)" % error_string(error))
		quit(1)
		return
	print("override.cfg: %d warnings raised to errors" % raised)
	quit()
