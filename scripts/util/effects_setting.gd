extends RefCounted
class_name EffectsSetting

## The "Effects: On / Off" option (pause menu): whether the world's motion
## plays at all. On (the default): characters breathe, settle and work with
## tiny whole-pixel steps, bubbles pop in, the camera eases between its two
## zooms, and highlights and glows pulse. Off: none of that moves; glows and
## highlights stay steady, and the camera and every state change happen at
## once. Nothing about the game itself depends on it.
##
## It is a player preference, not career progress: it lives in a small file
## of its own (REAL_PATH), never in a career save or a save slot, and a new
## game, a loaded career or a reset leaves it alone. Not an autoload: this
## static class is all there is, and it reads the file the first time
## anything asks.
##
## The same guard as the saves (SaveGame): only the real game flow may write
## the real file. Tests and scratch scripts point `path` at a file of their
## own (use_file()); anything else that still has `path` on the real file is
## refused with a warning, so a forgotten path can never change someone's
## setting. Reading is always allowed.

const REAL_PATH: String = "user://settings.cfg"
const SECTION: String = "effects"
const KEY: String = "on"

## The file read and written; tests and scratch scripts point it elsewhere.
static var path: String = REAL_PATH

static var _on: bool = true
static var _loaded: bool = false

## Whether effects play. Reads the file the first time.
static func is_on() -> bool:
	if not _loaded:
		_read()
	return _on

## Turns effects on or off now, and writes the file unless `persist` is
## false (tests set it for one run without a file). Turning them off stops
## every character's motion at once.
static func set_on(value: bool, persist: bool = true) -> void:
	_on = value
	_loaded = true
	if persist:
		save()
	CharacterMotionDriver.apply_setting()

## Reads the setting from `file_path` from now on (and forgets what was
## loaded), as tests and scratch scripts do to keep to files of their own.
static func use_file(file_path: String) -> void:
	path = file_path
	_loaded = false
	_on = true

## Writes the setting to `path`. False when the guard refuses (see above) or
## the file can't be written.
static func save() -> bool:
	if not _may_write():
		return false
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY, _on)
	return config.save(path) == OK

static func _read() -> void:
	_loaded = true
	_on = true
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var value: Variant = config.get_value(SECTION, KEY, true)
	if value is bool:
		_on = value

## Whether `file_path` is the player's real settings file (compared as files
## on disk, like SaveGame._is_real()).
static func is_real_file(file_path: String) -> bool:
	return SaveGame._disk_path(file_path) == SaveGame._disk_path(REAL_PATH)

static func _may_write() -> bool:
	if not is_real_file(path):
		return true
	if SaveGame.real_save_allowed:
		return true
	push_warning("EffectsSetting: refused to write the real settings file (%s) outside the real game flow. Point EffectsSetting.path at a test or scratch file." % path)
	return false
