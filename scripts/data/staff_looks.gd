extends RefCounted
class_name StaffLooks

## The staff uniform sprites (assets/sprites/staff_NN_frames.tres, made by
## tools/art/generate_characters.py; see ART.md): the same uniform with a
## different hair style, hair colour and skin tone per look, so staff can be
## told apart without their name labels. The starting roster wears
## ROSTER_LOOKS (one each, StaffRosterData); new hires get one of HIRE_LOOKS
## (pick_hire_look()).

const ROSTER_LOOKS: Array[String] = ["staff_01", "staff_02", "staff_03", "staff_04", "staff_05", "staff_06"]
const HIRE_LOOKS: Array[String] = ["staff_07", "staff_08", "staff_09", "staff_10"]

## Worn by anyone whose look isn't known (e.g. from a damaged save).
const FALLBACK_LOOK: String = "staff_01"

static func all_looks() -> Array[String]:
	var looks: Array[String] = []
	looks.append_array(ROSTER_LOOKS)
	looks.append_array(HIRE_LOOKS)
	return looks

static func frames_path(look: String) -> String:
	return "res://assets/sprites/%s_frames.tres" % look

static func frames_for(look: String) -> SpriteFrames:
	return load(frames_path(look if all_looks().has(look) else FALLBACK_LOOK)) as SpriteFrames

## A hire look nobody on `roster` wears yet, in HIRE_LOOKS order; once all
## are taken, they repeat in turn.
static func pick_hire_look(roster: Array[StaffMember]) -> String:
	var worn: Array[String] = []
	for member in roster:
		worn.append(member.look)
	for look in HIRE_LOOKS:
		if not worn.has(look):
			return look
	var hired := 0
	for look in worn:
		if HIRE_LOOKS.has(look):
			hired += 1
	return HIRE_LOOKS[hired % HIRE_LOOKS.size()]
