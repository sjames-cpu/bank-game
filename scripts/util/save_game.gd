extends RefCounted
class_name SaveGame

## Saves and loads a career (HANDOFF.md design flaw: no persistence) as one
## JSON file at `path`, with a FORMAT_VERSION number.
##
## What's saved is everything the autoloads hold for the career: each one
## has save_data() (a JSON-ready Dictionary) and load_data() next to its
## reset(), and capture()/restore() below call them all. Mid-shift state
## (queues, drawers, open screens, which desks are clocked in) lives in the
## room and is never saved, so a loaded career always starts off shift.
##
## When: on being hired (interview_screen.gd), and (teller_room.gd) at every
## clock-out (any role), after a promotion and after the one-time
## orientation letter. The probation letter comes
## at a teller clock-out, so that save covers it. Termination deletes the
## save (discipline_letter_screen.gd), and nothing is saved after it.
##
## Robustness: read() never fails loudly. A missing file is MISSING; a file
## that isn't JSON, or isn't shaped like a save, is CORRUPT; another version
## is WRONG_VERSION. The start screen (start_screen.gd) then falls back to a
## new game, setting the unreadable file aside (set_aside()). load_data()
## reads every value through the typed getters below, so a value of the
## wrong type falls back to its fresh-career default instead of erroring.

const FORMAT_VERSION: int = 1
const DEFAULT_PATH: String = "user://career.json"

## Where the save lives. Tests point this at their own file
## (tests/support/teller_room_suite.gd) so they never touch a real save, and
## so do the scratch/ screenshot scripts.
static var path: String = DEFAULT_PATH

## The player's real save. Only the real game flow may write, move or delete
## it: the start screen (the main scene) calls allow_real_save(). Anything
## else that still points at it (a test, a screenshot script, a scene run on
## its own from the editor) is refused with a warning (_may_write()), so a
## forgotten `path` can never overwrite someone's career. A variable only so
## the guard's own test can stand in a file of its own.
static var real_path: String = DEFAULT_PATH

## Set by allow_real_save(); see real_path.
static var real_save_allowed: bool = false

## Called by the start screen (start_screen.gd): from here on this is the
## real game, and it may write the real save.
static func allow_real_save() -> void:
	real_save_allowed = true

## Whether `path` may be written, moved or deleted (see real_path). Warns
## when it may not.
static func _may_write(action: String) -> bool:
	if path != real_path or real_save_allowed:
		return true
	push_warning("SaveGame: refused to %s the real save (%s) outside the real game flow. Point SaveGame.path at a test or scratch file." % [action, real_path])
	return false

enum Status { MISSING, OK, CORRUPT, WRONG_VERSION }

class ReadResult:
	var status: SaveGame.Status = SaveGame.Status.MISSING
	## The "career" section (see capture()); empty unless status is OK.
	var career: Dictionary = {}
	## When it was saved (system time), for the start screen.
	var saved_at: String = ""

static func exists() -> bool:
	return FileAccess.file_exists(path)

## The whole career, as JSON-ready data.
static func capture() -> Dictionary:
	return {
		"score": ScoreManager.save_data(),
		"reputation": ReputationManager.save_data(),
		"xp": XPManager.save_data(),
		"interview": InterviewManager.save_data(),
		"reports": ReportManager.save_data(),
		"history": HistoryManager.save_data(),
		"accounts": AccountManager.save_data(),
		"schedule": ScheduleManager.save_data(),
		"staff_review": StaffReviewManager.save_data(),
		"hiring": HiringManager.save_data(),
		"hints": HintManager.save_data(),
		"clock": GameClock.save_data(),
		"business_day": BusinessDay.save_data(),
		"regional": RegionalManager.save_data(),
	}

## Replaces the current career with `career` (from capture() or read()).
## Starts from a fresh career, so anything missing from `career` keeps its
## new-game value.
static func restore(career: Dictionary) -> void:
	CareerReset.reset_all()
	# Reputation before XP: setting it re-runs XPManager's unlock checks,
	# which must still see XP at 0. The saved unlock flags are then restored
	# as they were rather than earned again (no unlock signals, no letters).
	ReputationManager.load_data(dict_of(career, "reputation"))
	XPManager.load_data(dict_of(career, "xp"))
	ScoreManager.load_data(dict_of(career, "score"))
	InterviewManager.load_data(dict_of(career, "interview"))
	ReportManager.load_data(dict_of(career, "reports"))
	HistoryManager.load_data(dict_of(career, "history"))
	AccountManager.load_data(dict_of(career, "accounts"))
	ScheduleManager.load_data(dict_of(career, "schedule"))
	StaffReviewManager.load_data(dict_of(career, "staff_review"))
	# After ScheduleManager: candidates are kept per desk slot.
	HiringManager.load_data(dict_of(career, "hiring"))
	HintManager.load_data(dict_of(career, "hints"))
	GameClock.load_data(dict_of(career, "clock"))
	# Today's totals are measured against the loaded career and clock.
	BusinessDay.load_data(dict_of(career, "business_day"))
	# After XPManager and the business day: the review window is the manager's.
	RegionalManager.load_data(dict_of(career, "regional"))

## Writes the current career to `path`. Refused once the player has been
## terminated (that career is over), and for the real save outside the real
## game flow (real_path). Returns whether it was written.
static func save() -> bool:
	if ReportManager.is_terminated or not _may_write("write"):
		return false
	var root := {
		"format_version": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"career": capture(),
	}
	# full_precision so floats (loan amounts) come back exactly.
	var text := JSON.stringify(root, "\t", false, true)
	# Written beside the save and moved over it, so a crash mid-write can't
	# leave a half-written save behind.
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Couldn't save the career to %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_warning("Couldn't save the career to %s (%s)" % [path, error_string(error)])
		DirAccess.remove_absolute(temp_path)
		return false
	return true

## Reads `path` without changing the career. See the class doc for statuses.
static func read() -> ReadResult:
	var result := ReadResult.new()
	if not exists():
		return result
	result.status = Status.CORRUPT
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return result
	var root: Variant = json.data
	if not root is Dictionary:
		return result
	var root_dict: Dictionary = root
	var version: Variant = root_dict.get("format_version")
	if not (version is int or version is float):
		return result
	if int_value(version, -1) != FORMAT_VERSION:
		result.status = Status.WRONG_VERSION
		return result
	var career: Variant = root_dict.get("career")
	if not career is Dictionary:
		return result
	result.status = Status.OK
	result.career = career
	result.saved_at = string_of(root_dict, "saved_at", "")
	return result

static func delete() -> void:
	if exists() and _may_write("delete"):
		DirAccess.remove_absolute(path)

## Moves an unreadable save to `path` + ".bad" (replacing an older one) so a
## new game doesn't overwrite it, in case it's worth looking at.
static func set_aside() -> void:
	if not exists() or not _may_write("move"):
		return
	var bad_path := path + ".bad"
	if FileAccess.file_exists(bad_path):
		DirAccess.remove_absolute(bad_path)
	if DirAccess.rename_absolute(path, bad_path) != OK:
		DirAccess.remove_absolute(path)

# --- reading values back ---------------------------------------------------------
# JSON numbers come back as floats, and a damaged or edited save can hold any
# type: each getter returns `default` unless the value has the right type.

static func int_of(data: Dictionary, key: String, default: int) -> int:
	return int_value(data.get(key), default)

## `value` as an int if it's a number, else `default`.
static func int_value(value: Variant, default: int) -> int:
	if value is int:
		var whole: int = value
		return whole
	if value is float:
		var number: float = value
		return int(number)
	return default

static func float_of(data: Dictionary, key: String, default: float) -> float:
	var value: Variant = data.get(key)
	if value is int or value is float:
		var number: float = value
		return number
	return default

static func bool_of(data: Dictionary, key: String, default: bool) -> bool:
	var value: Variant = data.get(key)
	if value is bool:
		return value
	return default

static func string_of(data: Dictionary, key: String, default: String) -> String:
	var value: Variant = data.get(key)
	if value is String:
		return value
	return default

static func array_of(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key)
	if value is Array:
		return value
	return []

static func dict_of(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key)
	if value is Dictionary:
		return value
	return {}

## The String entries of `values`, skipping anything else.
static func strings_of(values: Array) -> PackedStringArray:
	var strings: PackedStringArray = []
	for value: Variant in values:
		if value is String:
			var text: String = value
			strings.append(text)
	return strings

## The numeric entries of `values` as ints, skipping anything else.
static func ints_of(values: Array) -> PackedInt32Array:
	var ints: PackedInt32Array = []
	for value: Variant in values:
		if value is int or value is float:
			ints.append(int_value(value, 0))
	return ints

## The Dictionary entries of `values`, skipping anything else (a list of
## saved resources).
static func dicts_of(values: Array) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for value: Variant in values:
		if value is Dictionary:
			var entry: Dictionary = value
			dicts.append(entry)
	return dicts

# --- data resources --------------------------------------------------------------
# Account, DecisionRecord, DisciplinaryReport, StaffReviewItem, StaffMember
# (hired staff) and StaffCandidate are saved field by field from their
# exported properties, so a field added to one of them is saved without
# touching this file (enums are ints; int, float, bool, String,
# PackedStringArray and PackedInt32Array fields are supported).

## The exported properties of `resource` as JSON-ready data.
static func resource_to_dict(resource: Resource) -> Dictionary:
	var data := {}
	for property in _saved_properties(resource):
		var property_name: String = property["name"]
		var value: Variant = resource.get(property_name)
		if value is PackedStringArray:
			var strings: PackedStringArray = value
			value = Array(strings)
		elif value is PackedInt32Array:
			var ints: PackedInt32Array = value
			value = Array(ints)
		data[property_name] = value
	return data

## Sets each exported property of `resource` found in `data` with the right
## type; anything missing or mistyped keeps the resource's default.
static func fill_resource(resource: Resource, data: Dictionary) -> void:
	for property in _saved_properties(resource):
		var property_name: String = property["name"]
		if not data.has(property_name):
			continue
		var property_type: int = property["type"]
		match property_type:
			TYPE_INT:
				if data[property_name] is int or data[property_name] is float:
					resource.set(property_name, int_of(data, property_name, 0))
			TYPE_FLOAT:
				if data[property_name] is int or data[property_name] is float:
					resource.set(property_name, float_of(data, property_name, 0.0))
			TYPE_BOOL:
				if data[property_name] is bool:
					resource.set(property_name, data[property_name])
			TYPE_STRING:
				if data[property_name] is String:
					resource.set(property_name, data[property_name])
			TYPE_PACKED_STRING_ARRAY:
				if data[property_name] is Array:
					resource.set(property_name, strings_of(array_of(data, property_name)))
			TYPE_PACKED_INT32_ARRAY:
				if data[property_name] is Array:
					resource.set(property_name, ints_of(array_of(data, property_name)))

static func _saved_properties(resource: Resource) -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for property in resource.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			saved.append(property)
	return saved
