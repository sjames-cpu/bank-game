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

func reset() -> void:
	files.clear()
	next_file_number = 1

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
	return {"next_file_number": next_file_number, "files": saved}

func load_data(data: Dictionary) -> void:
	reset()
	next_file_number = maxi(1, SaveGame.int_of(data, "next_file_number", 1))
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "files")):
		var file := LoanFile.from_data(entry)
		if file != null:
			files.append(file)
			next_file_number = maxi(next_file_number, file.number + 1)
