extends SceneTree

## Compiles every GDScript file in the project (addons excluded, like the
## project's warning directory_rules; gitignored scratch/ too) and fails if
## any doesn't. With override.cfg from tools/write_warnings_override.gd in
## place, every enabled warning is an error, so this is CI's warning check:
## each one prints as "SCRIPT ERROR: ... (Warning treated as error.)" with
## its file and line.
##
##   godot --headless --path . -s res://tools/check_scripts.gd
##
## Runs on the first frame rather than in _init(): scripts that use an
## autoload (ScoreManager, XPManager, ...) only compile once the autoloads
## have been added.

const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://scratch"]

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var paths: Array[String] = []
	_collect("res://", paths)
	# Reloading the script that's running would swap its code mid-call; it's
	# compiled (with the same warning levels) just by running it.
	var own_script: Script = get_script()
	paths.erase(own_script.resource_path)
	var failed: Array[String] = []
	for path in paths:
		var script: GDScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if script == null or not script.can_instantiate():
			failed.append(path)
	if failed.is_empty():
		print("Checked %d scripts: no errors or warnings." % paths.size())
	else:
		printerr("ERROR: %d of %d scripts have errors or warnings: %s" % [failed.size(), paths.size(), ", ".join(failed)])
	quit(1 if not failed.is_empty() else 0)
	return false

func _collect(dir_path: String, paths: Array[String]) -> void:
	if SKIP_DIRS.has(dir_path.trim_suffix("/")):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			paths.append(dir_path.path_join(file_name))
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), paths)
