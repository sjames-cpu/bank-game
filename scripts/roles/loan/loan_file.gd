extends RefCounted
class_name LoanFile

## One application waiting for documents (LoanPipeline): the application, what
## was asked for, when it is due, and how and when the applicant answers.
##
## How and when they answer is rolled once, when the request is made, from the
## career seed, the file's number and which request this is, and nothing else:
## never the applicant's finances, name or look (fair lending), and never the
## global random generator, so reloading a save can't re-roll it. Whether the
## applicant has come back is then a pure function of the day number
## (has_returned()): no daily tick runs. Days are the game's business days
## (GameClock.day), so a weekend or holiday never counts.

enum Timing { ON_TIME, LATE, NEVER }
## What comes back: everything asked for; everything but short_item; or
## everything, but wrong_item is a document that doesn't match.
enum Quality { COMPLETE, INCOMPLETE, WRONG }

## Day of a return that never comes.
const NEVER_DAY: int = -1

var number: int = 0
var application: LoanApplication = null
## Requests made for this file (1 after the first).
var request_count: int = 0
## What the latest request asked for (LoanRequirements.Item values).
var items: Array[int] = []
var request_day: int = 0
var due_day: int = 0
var timing: Timing = Timing.ON_TIME
## The business day the applicant comes back (NEVER_DAY: never).
var return_day: int = NEVER_DAY
var quality: Quality = Quality.COMPLETE
## The one item still missing (INCOMPLETE) or the one that doesn't match
## (WRONG) among `items`; -1 otherwise.
var short_item: int = -1
var wrong_item: int = -1
## Items handed over properly by earlier requests.
var delivered_before: Array[int] = []
## The papers handed over so far that the application form has no place for
## (the appraisal, the proof of the down payment, the explanation letter), and
## the one of them that doesn't match (-1: none). They live with the file, not
## on the application, so no other saved application changes by a byte.
var papers: Array[int] = []
var mismatched_paper: int = -1
## The request whose return is already on the application (LoanReturn): 0
## until a return has been applied, then request_count of that request. A
## further request (request_count + 1) is not applied until it comes back.
var return_applied: int = 0

## Asks for `asked` on business day `today`: sets the due day and rolls the
## answer. A further request (the applicant has come back, and still needed
## something) keeps what the earlier ones brought.
func begin_request(asked: Array[int], today: int, career_seed: int) -> void:
	if request_count > 0 and has_returned(today):
		for item in delivered_items():
			if not delivered_before.has(item):
				delivered_before.append(item)
	request_count += 1
	items = asked.duplicate()
	request_day = today
	due_day = today + LoanRequirements.due_days(items.size())
	roll(career_seed)

## Rolls the answer to the latest request from the career seed, this file's
## number and which request it is. Every draw is always made, in this order.
func roll(career_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([career_seed, "file-return", number, request_count])
	var when := rng.randf()
	var late_by := rng.randi_range(LoanConfig.LATE_DAYS_MIN, LoanConfig.LATE_DAYS_MAX)
	var what := rng.randf()
	var which := rng.randf()
	if when < LoanConfig.RETURN_ON_TIME:
		timing = Timing.ON_TIME
		return_day = due_day
	elif when < LoanConfig.RETURN_ON_TIME + LoanConfig.RETURN_LATE:
		timing = Timing.LATE
		return_day = due_day + late_by
	else:
		timing = Timing.NEVER
		return_day = NEVER_DAY
	short_item = -1
	wrong_item = -1
	var picked := -1
	if not items.is_empty():
		picked = items[mini(int(which * items.size()), items.size() - 1)]
	if what < LoanConfig.QUALITY_COMPLETE:
		quality = Quality.COMPLETE
	elif what < LoanConfig.QUALITY_COMPLETE + LoanConfig.QUALITY_INCOMPLETE:
		quality = Quality.INCOMPLETE
		short_item = picked
	else:
		quality = Quality.WRONG
		wrong_item = picked

## The day this file expires, with no penalty, if the applicant hasn't come
## back.
func expire_day() -> int:
	return due_day + LoanConfig.EXPIRES_AFTER_DUE_DAYS

## The applicant has come back (and not been given up on).
func has_returned(today: int) -> bool:
	return timing != Timing.NEVER and today >= return_day

func is_expired(today: int) -> bool:
	return not has_returned(today) and today >= expire_day()

## Still out: not back yet and not expired.
func is_waiting(today: int) -> bool:
	return not has_returned(today) and not is_expired(today)

## The clock on a returned file runs only on days when the player's chosen
## role was Loan Officer: a Teller's day (or any other role's, or a day with no
## role recorded) doesn't count, and the file waits. `role_days` is the
## recorded role of each business day (LoanRole.role_days: day number to
## PlayerShift.Role). This counts the Loan Officer days after the file came
## back and before `today`: whole days that are over.
func loan_officer_days_since_return(today: int, role_days: Dictionary) -> int:
	var count := 0
	for day in range(return_day + 1, today):
		if role_days.get(day, PlayerShift.Role.NONE) == PlayerShift.Role.LOAN_OFFICER:
			count += 1
	return count

## Loan Officer days still left to decide it in (0: overdue).
func decide_days_left(today: int, role_days: Dictionary) -> int:
	return maxi(0, LoanConfig.DECIDE_WITHIN_DAYS - loan_officer_days_since_return(today, role_days))

## Back, and left undecided LoanConfig.ABANDONED_AFTER_DAYS business days or
## more after its return day: closed quietly at Opening, whatever the
## player's role. A pure function of the day number.
func is_abandoned(today: int) -> bool:
	return has_returned(today) and today - return_day >= LoanConfig.ABANDONED_AFTER_DAYS

## Back, and its LoanConfig.DECIDE_WITHIN_DAYS Loan Officer days are used up:
## withdrawn at the start of `today`. A pure function of the day numbers and
## the recorded roles.
func is_overdue(today: int, role_days: Dictionary) -> bool:
	return has_returned(today) and decide_days_left(today, role_days) == 0

## The day a returned file is decided by if the player works as a Loan Officer
## from `today` on (each Teller day pushes it back). Only meaningful while it
## isn't overdue.
func decide_by_day(today: int, role_days: Dictionary) -> int:
	return today + maxi(1, decide_days_left(today, role_days)) - 1

## decide_by_day() as a date (an epoch day).
func decide_by_date(today: int, role_days: Dictionary) -> int:
	return GameClock.date_of_day(decide_by_day(today, role_days))

## The due day's date (an epoch day: BankCalendar.short_text() and friends
## show it).
func due_date() -> int:
	return GameClock.date_of_day(due_day)

## What the applicant brought back that is right, from the latest request
## (nothing until they have come back).
func delivered_items() -> Array[int]:
	var delivered: Array[int] = []
	for item in items:
		if item != short_item and item != wrong_item:
			delivered.append(item)
	return delivered

## Everything handed over properly so far, earlier requests included.
func all_delivered_items(today: int) -> Array[int]:
	var delivered := delivered_before.duplicate()
	if has_returned(today):
		for item in delivered_items():
			if not delivered.has(item):
				delivered.append(item)
	return delivered

## What `application` is still missing after everything handed over so far.
func still_missing(career_seed: int, today: int) -> Array[int]:
	var delivered := all_delivered_items(today)
	var missing: Array[int] = []
	for item in LoanRequirements.missing_items(application, career_seed):
		if not delivered.has(item):
			missing.append(item)
	return missing

# --- save and load ---------------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"number": number,
		"application": SaveGame.resource_to_dict(application),
		"request_count": request_count,
		"items": Array(items),
		"request_day": request_day,
		"due_day": due_day,
		"timing": timing,
		"return_day": return_day,
		"quality": quality,
		"short_item": short_item,
		"wrong_item": wrong_item,
		"delivered_before": Array(delivered_before),
		"return_applied": return_applied,
		"papers": Array(papers),
		"mismatched_paper": mismatched_paper,
	}

## A file from saved data, or null if it can't be read (no application, or a
## purpose the game no longer knows).
static func from_data(data: Dictionary) -> LoanFile:
	var saved := SaveGame.dict_of(data, "application")
	if saved.is_empty():
		return null
	var loaded := LoanApplication.new()
	SaveGame.fill_resource(loaded, saved)
	if not LoanApplication.PURPOSE_TERMS.has(loaded.loan_purpose):
		return null
	loaded.applicant_look = clampi(loaded.applicant_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)
	loaded.risk_assessment = loaded.calculate_risk_assessment()
	var file := LoanFile.new()
	file.application = loaded
	file.number = SaveGame.int_of(data, "number", 0)
	file.request_count = maxi(1, SaveGame.int_of(data, "request_count", 1))
	file.items = _items_of(data, "items")
	file.request_day = SaveGame.int_of(data, "request_day", 0)
	file.due_day = SaveGame.int_of(data, "due_day", file.request_day)
	file.timing = clampi(SaveGame.int_of(data, "timing", Timing.ON_TIME), Timing.ON_TIME, Timing.NEVER) as Timing
	file.return_day = SaveGame.int_of(data, "return_day", NEVER_DAY)
	file.quality = clampi(SaveGame.int_of(data, "quality", Quality.COMPLETE), Quality.COMPLETE, Quality.WRONG) as Quality
	file.short_item = SaveGame.int_of(data, "short_item", -1)
	file.wrong_item = SaveGame.int_of(data, "wrong_item", -1)
	file.delivered_before = _items_of(data, "delivered_before")
	file.return_applied = SaveGame.int_of(data, "return_applied", 0)
	file.papers = _items_of(data, "papers")
	file.mismatched_paper = SaveGame.int_of(data, "mismatched_paper", -1)
	return file

## The checklist items in saved `key`, any unknown ones dropped.
static func _items_of(data: Dictionary, key: String) -> Array[int]:
	var read: Array[int] = []
	for value: Variant in SaveGame.array_of(data, key):
		var item := -1
		if value is int:
			var whole: int = value
			item = whole
		elif value is float:
			var real: float = value
			item = int(real)
		if LoanRequirements.is_valid(item):
			read.append(item)
	return read
