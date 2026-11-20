extends RefCounted
class_name LoanPipeline

## The Loan Officer's open files: applications waiting for documents they
## asked an applicant to bring back (LoanFile). Held by LoanRole and saved in
## its section. Pure rules, no screens and no timers: a file's state is
## worked out from the day number, so nothing has to run between days, and a
## reload gives the same answers (LoanFile rolls from the career seed).
##
## At most LoanConfig.PIPELINE_MAX files are open (waiting, or back and not
## yet decided); each may ask for more documents up to
## LoanConfig.MAX_REQUESTS_PER_FILE times, and only once the applicant has
## come back from the last request. An expired file (never came back) stays
## listed through its expiry day, so that day can say so, and is dropped the
## day after. Deciding or giving up on a file takes it out (close()).

## Why a request wasn't made.
enum Refusal { NONE, NO_ITEMS, UNKNOWN_ITEM, FULL, STILL_OUT, TOO_MANY_REQUESTS }

var files: Array[LoanFile] = []
## The number the next new file gets.
var next_file_number: int = 1

## What happened to the files on one day, for that day's End of Day lines:
## log_day is the business day it describes. Kept (and saved) so the lines
## survive a reload of the End of Day.
var log_day: int = 0
var log_returned: Array[String] = []
## {"name", "score", "reputation"} for each file withdrawn that day.
var log_withdrawn: Array[Dictionary] = []
var log_expired: Array[String] = []

func reset() -> void:
	files.clear()
	next_file_number = 1
	_clear_log(0)

func is_empty() -> bool:
	return files.is_empty()

# --- what is open ----------------------------------------------------------------------

## Files not expired on business day `today`.
func open_files(today: int) -> Array[LoanFile]:
	var open: Array[LoanFile] = []
	for file in files:
		if not file.is_expired(today):
			open.append(file)
	return open

func open_count(today: int) -> int:
	return open_files(today).size()

## Files that expire on `today` (their applicant never came back).
func expired_on(today: int) -> Array[LoanFile]:
	var expired: Array[LoanFile] = []
	for file in files:
		if file.is_expired(today) and file.expire_day() == today:
			expired.append(file)
	return expired

## Files whose applicant has come back and not yet been decided, oldest
## return first (the order they would take a slot).
func returned_files(today: int) -> Array[LoanFile]:
	var back: Array[LoanFile] = []
	for file in files:
		if file.has_returned(today):
			back.append(file)
	back.sort_custom(func(a: LoanFile, b: LoanFile) -> bool: return a.return_day < b.return_day or (a.return_day == b.return_day and a.number < b.number))
	return back

## The file for `application`, if it has one.
func file_for(application: LoanApplication) -> LoanFile:
	for file in files:
		if file.application == application:
			return file
	return null

## Names of the applicants in open files (LoanDeskManager.names_taken()).
func names(today: int) -> PackedStringArray:
	var taken := PackedStringArray()
	for file in open_files(today):
		taken.append(file.application.applicant_name)
	return taken

# --- the start of a work day ---------------------------------------------------------

## The files withdrawn on `today`: back, and their Loan Officer days used up
## (LoanFile.is_overdue()). A pure function of the day numbers and `role_days`.
func overdue_files(today: int, role_days: Dictionary) -> Array[LoanFile]:
	var overdue: Array[LoanFile] = []
	for file in files:
		if file.is_overdue(today, role_days):
			overdue.append(file)
	return overdue

## Runs at the start of every work day, whatever the player's role today (it
## is only the recorded Loan Officer days that count): files that expired
## before today are forgotten, today's log is started (kept if it is already
## today's), what comes back and what expires today is noted, and the files
## past their time are withdrawn. `cost` is called for each file withdrawn,
## applies what it costs the player and returns {"score", "reputation"} as
## applied (LoanRole.withdrawal_cost()); that goes in the log. Returns the
## files withdrawn now.
##
## Safe to run again for the same day: a withdrawn file is gone, so it is
## never withdrawn (or charged) twice, and the log keeps what it noted.
func start_of_day(today: int, role_days: Dictionary, cost: Callable) -> Array[LoanFile]:
	_drop_old(today)
	# A day with nothing to note leaves no log (and nothing to save).
	if log_day != today:
		_clear_log(0)
	for file in files:
		if file.has_returned(today) and file.return_day == today and not log_returned.has(file.application.applicant_name):
			log_day = today
			log_returned.append(file.application.applicant_name)
	for file in expired_on(today):
		if not log_expired.has(file.application.applicant_name):
			log_day = today
			log_expired.append(file.application.applicant_name)
	var withdrawn := overdue_files(today, role_days)
	for file in withdrawn:
		files.erase(file)
		log_day = today
		var applied: Dictionary = cost.call(file)
		log_withdrawn.append({"name": file.application.applicant_name, "score": SaveGame.int_of(applied, "score", 0), "reputation": SaveGame.int_of(applied, "reputation", 0)})
	return withdrawn

## "Ben Hart (-2 Score, -1 Reputation)": a file's name and what its withdrawal
## cost (just the name when it cost nothing).
func _withdrawn_text(entry: Dictionary) -> String:
	var costs := PackedStringArray()
	var score := SaveGame.int_of(entry, "score", 0)
	var reputation := SaveGame.int_of(entry, "reputation", 0)
	if score != 0:
		costs.append("%+d Score" % score)
	if reputation != 0:
		costs.append("%+d Reputation" % reputation)
	var name := str(entry.get("name", ""))
	return name if costs.is_empty() else "%s (%s)" % [name, ", ".join(costs)]

func _clear_log(day: int) -> void:
	log_day = day
	log_returned.clear()
	log_withdrawn.clear()
	log_expired.clear()

## The End of Day lines for `today`: files that came back, files withdrawn
## with what it cost, files that never came back. Nothing when none did.
func summary_lines(today: int) -> PackedStringArray:
	var lines := PackedStringArray()
	if log_day != today:
		return lines
	if not log_returned.is_empty():
		lines.append("Files back with documents: %s" % ", ".join(log_returned))
	if not log_withdrawn.is_empty():
		var withdrawn_entries := PackedStringArray()
		for entry in log_withdrawn:
			withdrawn_entries.append(_withdrawn_text(entry))
		lines.append("Files withdrawn, not decided in time: %s" % ", ".join(withdrawn_entries))
	if not log_expired.is_empty():
		lines.append("Files that never came back: %s" % ", ".join(log_expired))
	return lines

# --- requests --------------------------------------------------------------------------

## Why asking for `items` on `application` on day `today` would be refused
## (Refusal.NONE if it wouldn't be).
func refusal_for(application: LoanApplication, items: Array[int], today: int) -> Refusal:
	if items.is_empty():
		return Refusal.NO_ITEMS
	for item in items:
		if not LoanRequirements.is_valid(item):
			return Refusal.UNKNOWN_ITEM
	var file := file_for(application)
	if file == null:
		return Refusal.FULL if open_count(today) >= LoanConfig.PIPELINE_MAX else Refusal.NONE
	if not file.has_returned(today):
		return Refusal.STILL_OUT
	if file.request_count >= LoanConfig.MAX_REQUESTS_PER_FILE:
		return Refusal.TOO_MANY_REQUESTS
	return Refusal.NONE

## Asks for `items` on day `today`: a new file for `application`, or a further
## request on its file. Returns the file, or null if it was refused
## (refusal_for() says why). Rolls the answer from `career_seed`.
func request(application: LoanApplication, items: Array[int], today: int, career_seed: int) -> LoanFile:
	_drop_old(today)
	if refusal_for(application, items, today) != Refusal.NONE:
		return null
	var file := file_for(application)
	if file == null:
		file = LoanFile.new()
		file.number = next_file_number
		next_file_number += 1
		file.application = application
		files.append(file)
	file.begin_request(items, today, career_seed)
	return file

## `application` was decided, or given up on: its file closes.
func close(application: LoanApplication) -> void:
	var file := file_for(application)
	if file != null:
		files.erase(file)

## Files that expired before `today` are forgotten; the one that expires today
## stays for today.
func _drop_old(today: int) -> void:
	var kept: Array[LoanFile] = []
	for file in files:
		if file.is_expired(today) and file.expire_day() < today:
			continue
		kept.append(file)
	files = kept

# --- save and load ---------------------------------------------------------------------

func save_data() -> Dictionary:
	var saved: Array = []
	for file in files:
		saved.append(file.save_data())
	var data := {"next_file_number": next_file_number, "files": saved}
	if log_day > 0:
		data["log"] = {"day": log_day, "returned": Array(log_returned), "withdrawn": log_withdrawn.duplicate(true), "expired": Array(log_expired)}
	return data

func load_data(data: Dictionary) -> void:
	reset()
	next_file_number = maxi(1, SaveGame.int_of(data, "next_file_number", 1))
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "files")):
		var file := LoanFile.from_data(entry)
		if file != null:
			files.append(file)
			next_file_number = maxi(next_file_number, file.number + 1)
	var logged := SaveGame.dict_of(data, "log")
	if not logged.is_empty():
		log_day = SaveGame.int_of(logged, "day", 0)
		log_returned.assign(SaveGame.strings_of(SaveGame.array_of(logged, "returned")))
		log_expired.assign(SaveGame.strings_of(SaveGame.array_of(logged, "expired")))
		for entry in SaveGame.dicts_of(SaveGame.array_of(logged, "withdrawn")):
			log_withdrawn.append({
				"name": SaveGame.string_of(entry, "name", ""),
				"score": SaveGame.int_of(entry, "score", LoanConfig.WITHDRAWN_SCORE),
				"reputation": SaveGame.int_of(entry, "reputation", LoanConfig.WITHDRAWN_REPUTATION),
			})
