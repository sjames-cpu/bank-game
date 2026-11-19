extends Node

## Autoload singleton: the Loan Officer role's own career data (Phase B on),
## saved in the career's "roles" > "loan" section and reset with the career
## (ROLE_BOUNDARIES.md: a role saves its data in its own section; a role
## doesn't register autoloads of its own, so this one is registered for it).
##
## Keep the Loan Officer's new saved values here: either in `section` (saved
## as it is), or as variables of their own, written by save_data() and read
## back by load_data(). Saves come back through JSON, so read numbers with
## SaveGame.int_of()/float_of() and the other typed getters. A save without
## this section loads it empty.
##
## The open files waiting for documents (`pipeline`, LoanPipeline) are saved
## under the key PIPELINE_KEY of this section, only while there is something
## to save, so a career that never used them saves exactly what it did
## before, and a save without the key loads an empty pipeline.

const PIPELINE_KEY: String = "file_pipeline"

## Free-form saved data for the Loan Officer role.
var section: Dictionary = {}

## The files waiting for documents.
var pipeline: LoanPipeline = LoanPipeline.new()

func reset() -> void:
	section = {}
	pipeline = LoanPipeline.new()

func save_data() -> Dictionary:
	var data := section.duplicate(true)
	if not pipeline.is_empty() or pipeline.next_file_number > 1:
		data[PIPELINE_KEY] = pipeline.save_data()
	return data

func load_data(data: Dictionary) -> void:
	section = data.duplicate(true)
	section.erase(PIPELINE_KEY)
	pipeline = LoanPipeline.new()
	pipeline.load_data(SaveGame.dict_of(data, PIPELINE_KEY))

## Asks for `items` on `application` today (LoanPipeline.request()), rolled
## from this career's seed. Null if refused.
func request_documents(application: LoanApplication, items: Array[int]) -> LoanFile:
	return pipeline.request(application, items, GameClock.day, LoanDeskManager.career_seed)
