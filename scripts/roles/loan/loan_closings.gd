extends RefCounted
class_name LoanClosings

## The Loan Officer's open closings: approved loans (or accepted
## counter-offers) waiting for their closing day (LoanClosing). Held by
## LoanRole and saved in its section. Separate from the files waiting for
## documents (LoanPipeline): a closing never counts against
## LoanConfig.PIPELINE_MAX. Pure rules, no screens and no timers: whether a
## closing is due or has lapsed is worked out from the day numbers, so nothing
## has to run between days and a reload gives the same answers.
##
## This part only keeps the list: who makes a closing, books it or grades it is
## up to the caller.

## What staff would do with an open closing when the player is promoted.
enum StaffAction { FUND, STOP }

var closings: Array[LoanClosing] = []
## The number the next closing gets (the career's first is 1).
var next_number: int = 1

## What lapsed on one day, for that day's End of Day lines: log_day is the
## business day it describes. Kept (and saved) so the lines survive a reload.
## {"name", "amount", "score", "reputation", "turned_away"} for each closing
## that lapsed that day.
var log_day: int = 0
var log_lapsed: Array[Dictionary] = []
## Names of closings left open so long that they were closed quietly that day
## (no penalty, no booking, not a good applicant turned away).
var log_abandoned: Array[String] = []
## Names of the closings funded and stopped that day (LoanBookManager.fund(),
## stop()), and how many open closings were funded and stopped by the staff at
## a promotion that day.
var log_funded: Array[String] = []
var log_stopped: Array[String] = []
var log_passed_funded: int = 0
var log_passed_stopped: int = 0

func reset() -> void:
	closings.clear()
	next_number = 1
	_clear_log(0)

func is_empty() -> bool:
	return closings.is_empty()

func count() -> int:
	return closings.size()

# --- making and finding ------------------------------------------------------------------

## A closing for the approved or counter-offered `application`, approved on
## business day `today` (due after LoanClosing.due_days_for()), its problem
## rolled from `career_seed` and its number. `reserved_loan_id` is the loan
## number the caller reserved for it (only stored). Null if the application
## wasn't approved or counter-offered.
func open(application: LoanApplication, today: int, career_seed: int, reserved_loan_id: int = 0) -> LoanClosing:
	var closing := LoanClosing.create(application, today, next_number, career_seed, reserved_loan_id)
	if closing == null:
		return null
	next_number += 1
	closings.append(closing)
	return closing

## The closing for `application`, if it has one.
func closing_for(application: LoanApplication) -> LoanClosing:
	for closing in closings:
		if closing.application == application:
			return closing
	return null

## A closing is over (funded, stopped or lapsed): it leaves the list.
func close(closing: LoanClosing) -> void:
	closings.erase(closing)

## Closings whose day has come, the one due longest first.
func due_closings(today: int) -> Array[LoanClosing]:
	var due: Array[LoanClosing] = []
	for closing in closings:
		if closing.is_due(today):
			due.append(closing)
	due.sort_custom(func(a: LoanClosing, b: LoanClosing) -> bool: return a.due_day < b.due_day or (a.due_day == b.due_day and a.number < b.number))
	return due

## Names of the applicants with open closings (LoanDeskManager.names_taken()).
func names() -> PackedStringArray:
	var taken := PackedStringArray()
	for closing in closings:
		taken.append(closing.application.applicant_name)
	return taken

## Every closing's recorded days are needed from the oldest due day on
## (LoanRole.role_days); `fallback` when none is open.
func oldest_due_day(fallback: int) -> int:
	var oldest := fallback
	for closing in closings:
		oldest = mini(oldest, closing.due_day)
	return oldest

# --- the start of a work day ------------------------------------------------------------

## The closings that lapse at the start of `today` (a pure function of the day
## numbers and `role_days`).
func overdue_closings(today: int, role_days: Dictionary) -> Array[LoanClosing]:
	var overdue: Array[LoanClosing] = []
	for closing in closings:
		if closing.is_overdue(today, role_days):
			overdue.append(closing)
	return overdue

## Runs at the start of every work day: closings past their Loan Officer days
## lapse, and any still open LoanConfig.ABANDONED_AFTER_DAYS business days after
## their due day are closed quietly, whatever the player's role. `cost`
## is called for each, applies what it costs the player and returns
## {"score", "reputation"} as applied (LoanRole.closing_lapse_cost()); the
## closing leaves the list and goes in the log. Safe to run again for the same
## day: a lapsed closing is gone, so it is never charged twice. Returns the
## closings lapsed now.
func start_of_day(today: int, role_days: Dictionary, cost: Callable) -> Array[LoanClosing]:
	# A day with nothing to note leaves no log (and nothing to save).
	if log_day != today:
		_clear_log(0)
	var lapsed := overdue_closings(today, role_days)
	for closing in lapsed:
		closings.erase(closing)
		log_day = today
		var applied: Dictionary = cost.call(closing)
		log_lapsed.append({
			"name": closing.application.applicant_name,
			"amount": closing.approved_amount,
			"score": SaveGame.int_of(applied, "score", 0),
			"reputation": SaveGame.int_of(applied, "reputation", 0),
			"turned_away": closing.counts_as_turned_away_if_lapsed(),
		})
	# What is left and has been open for ever: gone quietly, only after the
	# lapse above had its turn.
	var snapshot: Array[LoanClosing] = closings.duplicate()
	for closing in snapshot:
		if closing.is_abandoned(today):
			closings.erase(closing)
			log_day = today
			log_abandoned.append(closing.application.applicant_name)
	return lapsed

func _clear_log(day: int) -> void:
	log_day = day
	log_lapsed.clear()
	log_abandoned.clear()
	log_funded.clear()
	log_stopped.clear()
	log_passed_funded = 0
	log_passed_stopped = 0

# --- the day's log -----------------------------------------------------------------------

## Starts (or goes on with) the log for `today`.
func _log_for(today: int) -> void:
	if log_day != today:
		_clear_log(0)
	log_day = today

## `closing` was funded on `today` (it leaves the list).
func note_funded(closing: LoanClosing, today: int) -> void:
	closings.erase(closing)
	_log_for(today)
	log_funded.append(closing.application.applicant_name)

## `closing` was stopped on `today` (it leaves the list).
func note_stopped(closing: LoanClosing, today: int) -> void:
	closings.erase(closing)
	_log_for(today)
	log_stopped.append(closing.application.applicant_name)

## The staff dealt with the open closings at a promotion on `today`.
func note_passed(funded: int, stopped: int, today: int) -> void:
	if funded + stopped == 0:
		return
	_log_for(today)
	log_passed_funded += funded
	log_passed_stopped += stopped

## The End of Day lines for `today` (nothing when nothing happened): closings
## funded and stopped, closings that lapsed with what each cost, closings left
## open so long they were closed quietly, closings the staff took over.
func summary_lines(today: int) -> PackedStringArray:
	var lines := PackedStringArray()
	if log_day != today:
		return lines
	if not log_funded.is_empty():
		lines.append("Closings funded: %s" % ", ".join(log_funded))
	if not log_stopped.is_empty():
		lines.append("Closings stopped: %s" % ", ".join(log_stopped))
	if not log_lapsed.is_empty():
		var entries := PackedStringArray()
		for entry in log_lapsed:
			entries.append(_lapsed_text(entry))
		lines.append("Closings not completed in time: %s" % ", ".join(entries))
	if not log_abandoned.is_empty():
		lines.append("Closings left open too long were closed: %s" % ", ".join(log_abandoned))
	if log_passed_funded + log_passed_stopped > 0:
		lines.append("Closings passed to your staff: %d funded, %d stopped" % [log_passed_funded, log_passed_stopped])
	return lines

## "Ben Hart (-2 Score, -1 Reputation)": a lapsed closing's name and cost (just
## the name when it cost nothing).
func _lapsed_text(entry: Dictionary) -> String:
	var costs := PackedStringArray()
	var score := SaveGame.int_of(entry, "score", 0)
	var reputation := SaveGame.int_of(entry, "reputation", 0)
	if score != 0:
		costs.append("%+d Score" % score)
	if reputation != 0:
		costs.append("%+d Reputation" % reputation)
	var who := str(entry.get("name", ""))
	return who if costs.is_empty() else "%s (%s)" % [who, ", ".join(costs)]

# --- promotion and demotion ---------------------------------------------------------------

## What staff would do with each open closing if the player were promoted now
## (the caller applies it): a closing with a problem is stopped and a clean one
## funded. One entry per closing, in list order: {"closing": LoanClosing,
## "action": StaffAction}. Applies nothing.
func promotion_plan() -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	for closing in closings:
		plan.append({"closing": closing, "action": StaffAction.STOP if closing.has_problem() else StaffAction.FUND})
	return plan

## Every closing dropped with nothing noted (a demotion starts clean). The
## numbers keep counting, so no closing ever repeats an old one's roll.
func close_all() -> void:
	closings.clear()
	_clear_log(0)

# --- save and load ---------------------------------------------------------------------

## Whether there is anything to save (a career that never made a closing saves
## nothing).
func has_data() -> bool:
	return not closings.is_empty() or next_number > 1 or log_day > 0

func save_data() -> Dictionary:
	var saved: Array = []
	for closing in closings:
		saved.append(closing.save_data())
	var data := {"next_number": next_number, "closings": saved}
	if log_day > 0:
		data["log"] = {"day": log_day, "lapsed": log_lapsed.duplicate(true), "abandoned": Array(log_abandoned), "funded": Array(log_funded), "stopped": Array(log_stopped), "passed_funded": log_passed_funded, "passed_stopped": log_passed_stopped}
	return data

func load_data(data: Dictionary) -> void:
	reset()
	next_number = maxi(1, SaveGame.int_of(data, "next_number", 1))
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "closings")):
		var closing := LoanClosing.from_data(entry)
		if closing != null:
			closings.append(closing)
			next_number = maxi(next_number, closing.number + 1)
	var logged := SaveGame.dict_of(data, "log")
	if not logged.is_empty():
		log_day = SaveGame.int_of(logged, "day", 0)
		log_abandoned.assign(SaveGame.strings_of(SaveGame.array_of(logged, "abandoned")))
		log_funded.assign(SaveGame.strings_of(SaveGame.array_of(logged, "funded")))
		log_stopped.assign(SaveGame.strings_of(SaveGame.array_of(logged, "stopped")))
		log_passed_funded = maxi(0, SaveGame.int_of(logged, "passed_funded", 0))
		log_passed_stopped = maxi(0, SaveGame.int_of(logged, "passed_stopped", 0))
		for entry in SaveGame.dicts_of(SaveGame.array_of(logged, "lapsed")):
			log_lapsed.append({
				"name": SaveGame.string_of(entry, "name", ""),
				"amount": SaveGame.float_of(entry, "amount", 0.0),
				"score": SaveGame.int_of(entry, "score", LoanConfig.WITHDRAWN_SCORE),
				"reputation": SaveGame.int_of(entry, "reputation", LoanConfig.WITHDRAWN_REPUTATION),
				"turned_away": SaveGame.bool_of(entry, "turned_away", false),
			})
