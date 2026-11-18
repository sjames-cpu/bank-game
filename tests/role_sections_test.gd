extends GdUnitTestSuite

## Each role's own save section (TellerRole, LoanRole, ManagerRole, saved
## under the career's "roles"): each saves and loads its own data, a new
## career starts them empty, and a version 2 save from before them loads
## with them empty.

const OLD_SAVE := "res://tests/data/old_saves/v2_switch_off_mid_day.json"

func before_test() -> void:
	CareerReset.reset_all()

func after_test() -> void:
	CareerReset.reset_all()

## The career as it would come back from a save file: through JSON.
func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

func test_each_role_saves_and_loads_its_own_section() -> void:
	TellerRole.section["opening_cutscene"] = "seen"
	LoanRole.section["desk_layout"] = "classic"
	ManagerRole.section["note"] = "frozen"
	var career := through_json(SaveGame.capture())
	var roles := SaveGame.dict_of(career, "roles")
	assert_str(SaveGame.string_of(SaveGame.dict_of(roles, "teller"), "opening_cutscene", "")).is_equal("seen")
	assert_str(SaveGame.string_of(SaveGame.dict_of(roles, "loan"), "desk_layout", "")).is_equal("classic")

	CareerReset.reset_all()
	assert_dict(TellerRole.section).is_empty()
	SaveGame.restore(career)
	assert_dict(TellerRole.section).is_equal({"opening_cutscene": "seen"})
	assert_dict(LoanRole.section).is_equal({"desk_layout": "classic"})
	assert_dict(ManagerRole.section).is_equal({"note": "frozen"})

func test_a_role_reads_numbers_back_with_the_typed_getters() -> void:
	TellerRole.section["days_worked"] = 3
	var career := through_json(SaveGame.capture())
	SaveGame.restore(career)
	# JSON brings numbers back as floats: read them as ints.
	assert_int(SaveGame.int_of(TellerRole.section, "days_worked", -1)).is_equal(3)

func test_a_new_career_starts_every_section_empty() -> void:
	TellerRole.section["x"] = "y"
	CareerReset.reset_all()
	for role: Node in [TellerRole, LoanRole, ManagerRole]:
		assert_dict(role.get("section") as Dictionary).is_empty()

func test_a_version_2_save_without_the_sections_still_loads() -> void:
	var saved := SaveGame.read_file(OLD_SAVE)
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	assert_bool(saved.career.has("roles")).is_false()
	TellerRole.section["left over"] = "no"
	SaveGame.restore(saved.career)
	assert_dict(TellerRole.section).is_empty()
	assert_dict(LoanRole.section).is_empty()
	assert_dict(ManagerRole.section).is_empty()
	# The rest of the career came back as usual.
	assert_int(GameClock.day).is_equal(2)
