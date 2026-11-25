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

## The open closings (`closings`, LoanClosings) are saved under CLOSINGS_KEY,
## only once a closing has existed, in the same way.
const CLOSINGS_KEY: String = "closings"

## Free-form saved data for the Loan Officer role.
var section: Dictionary = {}

## The files waiting for documents.
var pipeline: LoanPipeline = LoanPipeline.new()

## The approved loans waiting for their closing day.
var closings: LoanClosings = LoanClosings.new()

## The role the player chose on each business day (day number to
## PlayerShift.Role), noted as the day's slots start (LoanSlotAdapter). The
## clock on a returned file, and on a closing, counts only the days recorded
## as Loan Officer (LoanFile.is_overdue(), LoanClosing.is_overdue()). Kept
## small: only while a file or a closing is open, from the oldest open request
## or due day on, and saved only then.
var role_days: Dictionary = {}

const ROLES_KEY: String = "file_roles"

func _ready() -> void:
	# A promotion passes every open file to the staff; a demotion starts clean.
	XPManager.branch_manager_unlocked.connect(_on_promoted)
	XPManager.branch_manager_demoted.connect(_on_demoted)

## The autoloads outlive the room, and tests reset them: let go with the node.
func _exit_tree() -> void:
	if XPManager.branch_manager_unlocked.is_connected(_on_promoted):
		XPManager.branch_manager_unlocked.disconnect(_on_promoted)
	if XPManager.branch_manager_demoted.is_connected(_on_demoted):
		XPManager.branch_manager_demoted.disconnect(_on_demoted)

## Promoted to Branch Manager: the Loan Desk is staffed from now on, so every
## open file (waiting or returned) is closed quietly, with no penalty, no
## history record and no booking, and the day's End of Day says so. The role
## days go with them.
##
## Open closings are left for whoever applies the promotion (closings
## .promotion_plan(): staff stop the ones with a problem and fund the rest), so
## their role days stay until then.
func _on_promoted() -> void:
	pipeline.pass_to_staff(GameClock.day)
	if closings.is_empty():
		role_days.clear()

## Demoted back to Loan Officer: the pipeline was emptied at the promotion,
## and nothing can bring an old file or role day back, so the player starts
## clean and the clock starts from the day they are back.
func _on_demoted() -> void:
	pipeline.close_all()
	closings.close_all()
	role_days.clear()

func reset() -> void:
	section = {}
	pipeline = LoanPipeline.new()
	closings = LoanClosings.new()
	role_days = {}

## Notes that the player's role on `day` is `role` (NONE is ignored: nothing
## was chosen), and drops the days no open file can need.
func note_role(day: int, role: PlayerShift.Role) -> void:
	if role == PlayerShift.Role.NONE:
		return
	role_days[day] = role
	_prune_roles()

func _prune_roles() -> void:
	if pipeline.is_empty() and closings.is_empty():
		role_days.clear()
		return
	var oldest := closings.oldest_due_day(GameClock.day)
	for file in pipeline.files:
		oldest = mini(oldest, file.request_day)
	for day: int in role_days.keys():
		if day < oldest:
			role_days.erase(day)

func save_data() -> Dictionary:
	var data := section.duplicate(true)
	if not pipeline.is_empty() or pipeline.next_file_number > 1 or pipeline.log_day > 0:
		data[PIPELINE_KEY] = pipeline.save_data()
	if closings.has_data():
		data[CLOSINGS_KEY] = closings.save_data()
	# The roles matter only while a file or a closing is open.
	if not (pipeline.is_empty() and closings.is_empty()) and not role_days.is_empty():
		var roles := {}
		for day: int in role_days:
			roles[str(day)] = role_days[day]
		data[ROLES_KEY] = roles
	return data

func load_data(data: Dictionary) -> void:
	section = data.duplicate(true)
	section.erase(PIPELINE_KEY)
	section.erase(ROLES_KEY)
	section.erase(CLOSINGS_KEY)
	closings = LoanClosings.new()
	closings.load_data(SaveGame.dict_of(data, CLOSINGS_KEY))
	pipeline = LoanPipeline.new()
	pipeline.load_data(SaveGame.dict_of(data, PIPELINE_KEY))
	role_days = {}
	var saved_roles := SaveGame.dict_of(data, ROLES_KEY)
	for key: String in saved_roles:
		if key.is_valid_int():
			var role := clampi(SaveGame.int_of(saved_roles, key, PlayerShift.Role.NONE), PlayerShift.Role.NONE, PlayerShift.Role.BRANCH_MANAGER)
			if role != PlayerShift.Role.NONE:
				role_days[key.to_int()] = role

## Asks for `items` on `application` today (LoanPipeline.request()), rolled
## from this career's seed. Null if refused.
func request_documents(application: LoanApplication, items: Array[int]) -> LoanFile:
	return pipeline.request(application, items, GameClock.day, LoanDeskManager.career_seed)

## The start of a work day (LoanSlotAdapter, at Opening): returned files that
## were not decided in time are withdrawn, each costing LoanConfig.WITHDRAWN_*
## once (the Score, the Reputation, and the XP a Score point is worth), and
## the day's file log starts. Whatever role the player has today. Returns the
## files withdrawn now.
func start_of_day() -> Array[LoanFile]:
	# Nothing from the pipeline runs for a Branch Manager: any file left
	# (a save from before the promotion handler) is passed to the staff.
	if XPManager.is_branch_manager_unlocked:
		pipeline.pass_to_staff(GameClock.day)
		if closings.is_empty():
			role_days.clear()
		return []
	var withdrawn := pipeline.start_of_day(GameClock.day, role_days, withdrawal_cost)
	# Closings past their Loan Officer days lapse (before the role days they
	# need are pruned).
	closings.start_of_day(GameClock.day, role_days, closing_lapse_cost)
	_prune_roles()
	return withdrawn

## What a withdrawn file costs the player, applied now: LoanConfig.WITHDRAWN_*,
## but never so much Reputation that it reaches 0 (that would write a report,
## and a withdrawal comes at Opening, before today's role is even chosen), and
## never a gain (at Reputation 0 it costs none).
## Returns {"score", "reputation"} as applied.
func withdrawal_cost(_file: LoanFile) -> Dictionary:
	return _apply_lapse_cost()

## What a closing that lapsed costs the player: the same as a withdrawn file
## (LoanConfig.WITHDRAWN_*, with the same Reputation floor). Returns
## {"score", "reputation"} as applied.
func closing_lapse_cost(_closing: LoanClosing) -> Dictionary:
	return _apply_lapse_cost()

## The Reputation cost is never positive and never takes Reputation to 0 (that
## would write a report at Opening, before the day's role is even chosen): at
## 0 or 1 it costs nothing, at 2 or more LoanConfig.WITHDRAWN_REPUTATION.
func _apply_lapse_cost() -> Dictionary:
	var reputation := mini(0, maxi(LoanConfig.WITHDRAWN_REPUTATION, 1 - ReputationManager.reputation))
	ScoreManager.add_shift_score(LoanConfig.WITHDRAWN_SCORE)
	XPManager.add_shift_xp(LoanConfig.WITHDRAWN_SCORE)
	if reputation != 0:
		ReputationManager.add_reputation(reputation)
	return {"score": LoanConfig.WITHDRAWN_SCORE, "reputation": reputation}
