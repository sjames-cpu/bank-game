extends Node

## Autoload singleton: the Regional Manager, who reviews the Branch Manager
## (the player, once promoted). Same pattern as the other managers: reset()
## for CareerReset, save_data()/load_data() for SaveGame.
##
## Schedule: every REVIEW_INTERVAL_DAYS business days as Branch Manager. The
## day of the promotion doesn't count, so the first review is on the 5th
## full day after it (promoted on Day 10: reviewed at the End of Day 15),
## then every 5 days. On review day the Regional Manager visits the branch
## mid-morning (teller_room.gd), and the review letter comes at that day's
## End of Day, before the summary (teller_room.show_end_of_day() calls
## run_review(); DisciplineLetterScreen shows review_completed).
##
## The review window: everything from the promotion (or the last review) to
## the review, collected as it happens while the player is Branch Manager:
## - vault reconciliations, by day (branch_manager_screen.gd: note_vault_result())
## - serious staff-review items: reviewed (StaffReviewManager.review_decided),
##   closed as ignored at a clock-out (note_serious_ignored()), and still
##   waiting at the review (StaffReviewManager.queue)
## - unfair reports and excused serious items (review_decided)
## - staff work and mistakes (HistoryManager.staff_record_added)
## - customers who gave up at a staffed window (note_staff_line_abandoned(),
##   from the room's staff lines)
## - desks left vacant during opening hours (sample_vacancies())
## - hires and how good they were (HiringManager.staff_hired)
##
## Rating (evaluate()): each area scores 0-100, or isn't rated when there
## was nothing to judge (no hires, no serious items, ...). The overall score
## is the weighted average of the rated areas (AREA_WEIGHTS), and its band
## (EXCEEDS_MIN / MEETS_MIN / NEEDS_IMPROVEMENT_MIN) is the rating. A day
## the manager went home without working simply has no vault count and
## leaves serious items unreviewed, so it pulls the score down on its own.
##
## Consequences (apply_consequences()): Exceeds earns a bonus and removes a
## regional warning, Meets changes nothing, Needs Improvement adds a warning,
## Unsatisfactory adds one and costs Reputation. At WARNINGS_FOR_DEMOTION
## warnings the Branch Manager is demoted to Loan Officer
## (XPManager.demote_branch_manager()), and the warnings start over.
##
## Reputation falling to 0 (ReputationManager.reputation_reached_zero) also
## gives a Branch Manager a regional warning, with its own letter. If that
## is the third, the demotion comes at that day's End of Day, before the
## summary (demote_if_due(), from teller_room.show_end_of_day()), so the
## player is never demoted in the middle of a shift.
##
## Registered after BusinessDay and the managers it listens to.

## After a review, with the result (see run_review()).
signal review_completed(result: Dictionary)
## After a demotion, once XPManager has demoted the player.
signal demoted(warnings: int)
## A regional warning for Reputation falling to 0, with the warnings now.
signal zero_reputation_warning(warnings: int)

const REVIEW_INTERVAL_DAYS: int = 5
const WARNINGS_FOR_DEMOTION: int = 3

enum Rating { EXCEEDS, MEETS, NEEDS_IMPROVEMENT, UNSATISFACTORY }

## Overall score (0-100) at or above which each rating is given.
const EXCEEDS_MIN: float = 92.0
const MEETS_MIN: float = 80.0
const NEEDS_IMPROVEMENT_MIN: float = 50.0

## Areas in letter order, and their weights (they add up to 100). Areas that
## aren't rated drop out and the rest are re-weighted.
const AREA_VAULT: String = "vault"
const AREA_IGNORED: String = "ignored"
const AREA_UNFAIR: String = "unfair"
const AREA_EXCUSED: String = "excused"
const AREA_MISTAKES: String = "mistakes"
const AREA_ABANDONED: String = "abandoned"
const AREA_VACANCY: String = "vacancy"
const AREA_HIRING: String = "hiring"
const AREA_WEIGHTS: Dictionary[String, int] = {
	AREA_VAULT: 25,
	AREA_IGNORED: 20,
	AREA_UNFAIR: 25,
	AREA_EXCUSED: 10,
	AREA_MISTAKES: 5,
	AREA_ABANDONED: 5,
	AREA_VACANCY: 5,
	AREA_HIRING: 5,
}
const AREA_NAMES: Dictionary[String, String] = {
	AREA_VAULT: "Vault reconciliation",
	AREA_IGNORED: "Serious errors left unreviewed",
	AREA_UNFAIR: "Fairness of reports",
	AREA_EXCUSED: "Serious errors excused",
	AREA_MISTAKES: "Staff mistake rate",
	AREA_ABANDONED: "Customers who gave up at staffed windows",
	AREA_VACANCY: "Vacant desks",
	AREA_HIRING: "Hiring",
}

## Vault: each day of the window scores its best reconciliation that day.
const VAULT_DAY_SCORES: Dictionary[int, float] = {
	VaultReconciliationScreen.DiscrepancyResult.PERFECT: 100.0,
	VaultReconciliationScreen.DiscrepancyResult.MINOR: 70.0,
	VaultReconciliationScreen.DiscrepancyResult.MAJOR: 30.0,
}
## Points off per serious item ignored, unfair report, and serious item excused.
const IGNORED_PENALTY: float = 25.0
const UNFAIR_PENALTY: float = 40.0
const EXCUSED_PENALTY: float = 50.0
## Staff mistake rate (teller mistakes and wrong loan calls over all staff
## work): full marks up to MISTAKE_RATE_GOOD, none from MISTAKE_RATE_BAD.
## Rated once staff have done at least MIN_STAFF_WORK pieces of work.
const MISTAKE_RATE_GOOD: float = 0.10
const MISTAKE_RATE_BAD: float = 0.40
const MIN_STAFF_WORK: int = 10
## Share of staff-line customers who gave up: full marks at none, none at this.
const ABANDON_RATE_BAD: float = 0.25
## Points off per desk-hour a desk stood vacant during opening hours.
const VACANCY_PENALTY_PER_HOUR: float = 2.5
## Hiring: each hire scores by HiringManager's verdict.
const HIRE_SCORES: Dictionary[int, float] = {
	HiringManager.Verdict.BEST: 100.0,
	HiringManager.Verdict.MIDDLE: 60.0,
	HiringManager.Verdict.WEAKEST: 20.0,
	HiringManager.Verdict.RED_FLAG: 0.0,
}

## Consequences. Pitched above a single shift's best result (a Perfect
## count is +10 Score/+2 Reputation) since a review covers five days; the
## Unsatisfactory penalty matches a Major count's -5 Reputation.
const EXCEEDS_SCORE: int = 15 # XP follows Score (x10)
const EXCEEDS_REPUTATION: int = 3
const UNSATISFACTORY_REPUTATION: int = -5

const SENDER: String = "Regional Manager"

## Regional warnings, 0 to WARNINGS_FOR_DEMOTION - 1 (a third one demotes:
## at once at a review, at the End of Day for a zero-Reputation warning).
var warnings: int = 0

## First day of the current review window (the day after the promotion or
## the last review); 0 while the player isn't Branch Manager.
var window_first_day: int = 0
## Serious items from this day or earlier were already counted by a review
## (or come from before this stint as manager).
var counted_through_day: int = 0

# --- the review window's data ----------------------------------------------------

## Day -> best VaultReconciliationScreen.DiscrepancyResult that day.
var vault_by_day: Dictionary[int, int] = {}
## Serious items reviewed (any action), closed as ignored at a clock-out,
## and excused.
var serious_reviewed: int = 0
var serious_ignored: int = 0
var serious_excused: int = 0
## Staff-review decisions, and how many were reports the item didn't warrant.
var reviews: int = 0
var unfair_reports: int = 0
## Staff work (teller customers and loan decisions) and how much was wrong.
var staff_work: int = 0
var staff_mistakes: int = 0
## Customers staff served at the teller windows, and who gave up waiting there.
var staff_line_served: int = 0
var staff_line_abandoned: int = 0
## Desk-minutes of opening time with a desk unassigned.
var vacant_desk_minutes: float = 0.0
## HiringManager.Verdict of each hire.
var hire_verdicts: Array[int] = []

## Where sample_vacancies() last looked at the clock (-1 day: not yet).
var _sample_day: int = -1
var _sample_minutes: float = 0.0

func _ready() -> void:
	# Desks stay vacant behind open screens too, but time only passes while
	# the game runs, so sampling every frame is enough.
	process_mode = Node.PROCESS_MODE_ALWAYS
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	StaffReviewManager.review_decided.connect(_on_review_decided)
	HistoryManager.staff_record_added.connect(_on_staff_record_added)
	HiringManager.staff_hired.connect(_on_staff_hired)
	ReputationManager.reputation_reached_zero.connect(_on_reputation_reached_zero)

func _process(_delta: float) -> void:
	sample_vacancies()

func reset() -> void:
	warnings = 0
	window_first_day = 0
	counted_through_day = 0
	_clear_window()

func _clear_window() -> void:
	vault_by_day.clear()
	serious_reviewed = 0
	serious_ignored = 0
	serious_excused = 0
	reviews = 0
	unfair_reports = 0
	staff_work = 0
	staff_mistakes = 0
	staff_line_served = 0
	staff_line_abandoned = 0
	vacant_desk_minutes = 0.0
	hire_verdicts.clear()
	_sample_day = -1

# --- schedule ----------------------------------------------------------------------

## Collecting and reviewing only happen while the player is Branch Manager.
func is_collecting() -> bool:
	return XPManager.is_branch_manager_unlocked and window_first_day > 0

## The day of the next review (its End of Day), or 0 if none is coming.
func next_review_day() -> int:
	if not is_collecting():
		return 0
	return window_first_day + REVIEW_INTERVAL_DAYS - 1

## Today is a review day (the Regional Manager visits).
func is_review_day() -> bool:
	return is_collecting() and BusinessDay.stats_day == next_review_day()

## The review is due at this End of Day.
func is_review_due() -> bool:
	return is_collecting() and BusinessDay.stats_day >= next_review_day()

## "Next review: Day 15 · Warnings 1/3", for the HUD (empty unless Branch
## Manager).
func status_text() -> String:
	if not is_collecting():
		return ""
	return "Next review: Day %d · Warnings %d/%d" % [next_review_day(), warnings, WARNINGS_FOR_DEMOTION]

## Promoted (again): the first window starts tomorrow; serious items from
## today on are this stint's.
func _on_branch_manager_unlocked() -> void:
	_start_window(BusinessDay.stats_day + 1, BusinessDay.stats_day - 1)

func _start_window(first_day: int, counted_through: int) -> void:
	window_first_day = first_day
	counted_through_day = counted_through
	_clear_window()

# --- collecting ----------------------------------------------------------------------

## A graded vault reconciliation (branch_manager_screen.gd), kept as the
## best result of its day.
func note_vault_result(result: VaultReconciliationScreen.DiscrepancyResult) -> void:
	if not is_collecting():
		return
	var day := BusinessDay.stats_day
	var best: int = vault_by_day.get(day, result)
	vault_by_day[day] = mini(best, result)

## Serious items closed as ignored at a Branch Manager clock-out
## (StaffReviewManager.close_ignored_serious()'s items). Items a review has
## already counted as waiting aren't counted again.
func note_serious_ignored(items: Array[StaffReviewItem]) -> void:
	if not is_collecting():
		return
	for item in items:
		if GameClock.day_of(item.timestamp) > counted_through_day:
			serious_ignored += 1

## A customer gave up waiting at a staffed teller window (the room's staff
## lines' customer_abandoned).
func note_staff_line_abandoned(_customer: CustomerNPC) -> void:
	if is_collecting():
		staff_line_abandoned += 1

func _on_review_decided(result: Dictionary) -> void:
	if not is_collecting():
		return
	reviews += 1
	var unfair: bool = result["unfair_report"]
	if unfair:
		unfair_reports += 1
	var severity: StaffReviewItem.Severity = result["severity"]
	if severity == StaffReviewItem.Severity.SERIOUS:
		serious_reviewed += 1
		var action: StaffReviewManager.Action = result["action"]
		if action == StaffReviewManager.Action.EXCUSE:
			serious_excused += 1

func _on_staff_record_added(record: DecisionRecord) -> void:
	if not is_collecting():
		return
	staff_work += 1
	if record.grade_label == "Mistake":
		staff_mistakes += 1
	if record.staff_slot != ScheduleManager.SLOT_LOAN_DESK:
		staff_line_served += 1

func _on_staff_hired(result: Dictionary) -> void:
	if not is_collecting():
		return
	var verdict: HiringManager.Verdict = result["verdict"]
	hire_verdicts.append(verdict)

## Adds the opening time since the last look, times the desks vacant now.
## Called every frame, and by the review (going home skips the clock straight
## to closing, and the vacancy covers the skipped time too).
func sample_vacancies() -> void:
	if not is_collecting():
		_sample_day = -1
		return
	var now := GameClock.minutes
	if GameClock.day != _sample_day or now < _sample_minutes:
		_sample_day = GameClock.day
		_sample_minutes = now
		return
	var from := maxf(_sample_minutes, BusinessDay.OPEN_MINUTES)
	var to := minf(now, BusinessDay.CLOSE_MINUTES)
	if to > from:
		vacant_desk_minutes += (to - from) * ScheduleManager.vacant_slots().size()
	_sample_minutes = now

## Serious items still waiting in the staff review queue from this window.
func serious_waiting() -> int:
	var waiting := 0
	for item in StaffReviewManager.queue:
		if item.severity == StaffReviewItem.Severity.SERIOUS and GameClock.day_of(item.timestamp) > counted_through_day:
			waiting += 1
	return waiting

# --- the review ------------------------------------------------------------------------

## Reviews the window ending today, applies the consequences, starts the next
## window, and demotes at WARNINGS_FOR_DEMOTION warnings. Returns the result
## (see evaluate(), plus "first_day", "last_day" and the consequences:
## "score_change", "reputation_change", "xp_change", "warnings_before",
## "warnings", "demoted").
func run_review() -> Dictionary:
	sample_vacancies()
	var last_day := BusinessDay.stats_day
	var result := evaluate()
	result["first_day"] = window_first_day
	result["last_day"] = last_day
	apply_consequences(result)
	var rating: Rating = result["rating"]
	var overall: float = result["score"]
	HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER,
		"Regional review, Days %d-%d: %s (%d/100), regional warnings %d/%d" % [window_first_day, last_day, rating_label(rating), roundi(overall), warnings, WARNINGS_FOR_DEMOTION],
		rating_label(rating)
	)
	var demote := warnings >= WARNINGS_FOR_DEMOTION
	result["demoted"] = demote
	_start_window(last_day + 1, last_day)
	review_completed.emit(result)
	if demote:
		_demote()
	return result

## The rating for the window so far: {"score", "rating", "areas"}, areas
## being one {"key", "name", "weight", "rated", "score", "detail",
## "comment"} per AREA_WEIGHTS entry, in letter order.
func evaluate() -> Dictionary:
	var areas: Array[Dictionary] = [
		_vault_area(),
		_ignored_area(),
		_unfair_area(),
		_excused_area(),
		_mistakes_area(),
		_abandoned_area(),
		_vacancy_area(),
		_hiring_area(),
	]
	var weighted := 0.0
	var weights := 0
	for area in areas:
		if area["rated"]:
			var weight: int = area["weight"]
			var area_score: float = area["score"]
			weighted += area_score * weight
			weights += weight
	var overall := weighted / weights if weights > 0 else 100.0
	return {"score": overall, "rating": rating_for(overall), "areas": areas}

func rating_for(overall: float) -> Rating:
	if overall >= EXCEEDS_MIN:
		return Rating.EXCEEDS
	if overall >= MEETS_MIN:
		return Rating.MEETS
	if overall >= NEEDS_IMPROVEMENT_MIN:
		return Rating.NEEDS_IMPROVEMENT
	return Rating.UNSATISFACTORY

func rating_label(rating: Rating) -> String:
	match rating:
		Rating.EXCEEDS:
			return "Exceeds Expectations"
		Rating.MEETS:
			return "Meets Expectations"
		Rating.NEEDS_IMPROVEMENT:
			return "Needs Improvement"
		_:
			return "Unsatisfactory"

## Score, Reputation and warnings for the rating; records them in `result`.
func apply_consequences(result: Dictionary) -> void:
	var rating: Rating = result["rating"]
	var score := 0
	var reputation := 0
	result["warnings_before"] = warnings
	match rating:
		Rating.EXCEEDS:
			score = EXCEEDS_SCORE
			reputation = EXCEEDS_REPUTATION
			warnings = maxi(0, warnings - 1)
		Rating.NEEDS_IMPROVEMENT:
			warnings += 1
		Rating.UNSATISFACTORY:
			reputation = UNSATISFACTORY_REPUTATION
			warnings += 1
	if score != 0:
		ScoreManager.add_shift_score(score)
	if reputation != 0:
		ReputationManager.add_reputation(reputation)
	var xp := 0
	if score > 0:
		XPManager.add_shift_xp(score)
		xp = score * XPManager.XP_PER_SCORE_POINT
	result["score_change"] = score
	result["reputation_change"] = reputation
	result["xp_change"] = xp
	result["warnings"] = warnings

## Reputation fell to 0 while Branch Manager: one regional warning. During a
## review (an Unsatisfactory rating's Reputation cost) run_review() demotes
## if it's the third; otherwise the End of Day does (demote_if_due()).
func _on_reputation_reached_zero() -> void:
	if not is_collecting():
		return
	warnings = mini(warnings + 1, WARNINGS_FOR_DEMOTION)
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Regional warning from the Regional Manager: customer satisfaction has fallen to zero (regional warnings %d/%d)" % [warnings, WARNINGS_FOR_DEMOTION],
		"Regional warning"
	)
	zero_reputation_warning.emit(warnings)

## A third regional warning came outside a review: the demotion is due at
## this End of Day.
func is_demotion_due() -> bool:
	return is_collecting() and warnings >= WARNINGS_FOR_DEMOTION

## The End of Day's demotion, if one is due (teller_room.show_end_of_day()).
func demote_if_due() -> bool:
	if not is_demotion_due():
		return false
	_demote()
	return true

## Back to Loan Officer: XPManager demotes (ReportManager, ScheduleManager and
## the room react to its signal), and the regional record starts over.
func _demote() -> void:
	var had := warnings
	warnings = 0
	window_first_day = 0
	_clear_window()
	HistoryManager.add_record(
		DecisionRecord.Role.DISCIPLINARY,
		"Demoted to Loan Officer by the Regional Manager after %d regional warnings" % had,
		"Demoted"
	)
	XPManager.demote_branch_manager()
	demoted.emit(had)

# --- areas -----------------------------------------------------------------------------

func _area(key: String, rated: bool, area_score: float, detail: String, comment: String) -> Dictionary:
	return {
		"key": key,
		"name": AREA_NAMES[key],
		"weight": AREA_WEIGHTS[key],
		"rated": rated,
		"score": clampf(area_score, 0.0, 100.0) if rated else 0.0,
		"detail": detail,
		"comment": comment,
	}

func _vault_area() -> Dictionary:
	var total := 0.0
	var counts: Dictionary[int, int] = {}
	var missed := 0
	for i in REVIEW_INTERVAL_DAYS:
		var day := window_first_day + i
		if vault_by_day.has(day):
			var result: int = vault_by_day[day]
			total += VAULT_DAY_SCORES[result]
			var so_far: int = counts.get(result, 0)
			counts[result] = so_far + 1
		else:
			missed += 1
	var done := REVIEW_INTERVAL_DAYS - missed
	var results: PackedStringArray = []
	for pair: Array in [[VaultReconciliationScreen.DiscrepancyResult.PERFECT, "Perfect"], [VaultReconciliationScreen.DiscrepancyResult.MINOR, "Minor"], [VaultReconciliationScreen.DiscrepancyResult.MAJOR, "Major"]]:
		var result: int = pair[0]
		var label: String = pair[1]
		if counts.has(result):
			results.append("%d %s" % [counts[result], label])
	var detail := "Reconciled on %d of %d days" % [done, REVIEW_INTERVAL_DAYS]
	if not results.is_empty():
		detail += " (%s)" % ", ".join(results)
	if missed > 0:
		detail += "; %d day%s with no count" % [missed, "" if missed == 1 else "s"]
	detail += "."
	var comment := "Well done: the vault was counted every day and balanced."
	if missed > 0:
		comment = "To improve: reconcile the vault every day, even on a short one."
	elif counts.has(VaultReconciliationScreen.DiscrepancyResult.MINOR) or counts.has(VaultReconciliationScreen.DiscrepancyResult.MAJOR):
		comment = "To improve: take more care with the count; it didn't always balance."
	return _area(AREA_VAULT, true, total / REVIEW_INTERVAL_DAYS, detail, comment)

func _ignored_area() -> Dictionary:
	var ignored := serious_ignored + serious_waiting()
	var arose := serious_reviewed + ignored
	if arose == 0:
		return _area(AREA_IGNORED, false, 0.0, "No serious staff errors came up.", "")
	var detail := "%d serious error%s: %d reviewed, %d left unreviewed." % [arose, "" if arose == 1 else "s", serious_reviewed, ignored]
	var comment := "Well done: every serious error was dealt with." if ignored == 0 else "To improve: review serious errors before you clock out or go home."
	return _area(AREA_IGNORED, true, 100.0 - IGNORED_PENALTY * ignored, detail, comment)

func _unfair_area() -> Dictionary:
	if reviews == 0:
		return _area(AREA_UNFAIR, false, 0.0, "No staff reviews were decided.", "")
	var detail := "%d review%s, %d unfair report%s." % [reviews, "" if reviews == 1 else "s", unfair_reports, "" if unfair_reports == 1 else "s"]
	var comment := "Well done: your reports were fair." if unfair_reports == 0 else "To improve: keep reports for serious or repeated mistakes; coach the rest."
	return _area(AREA_UNFAIR, true, 100.0 - UNFAIR_PENALTY * unfair_reports, detail, comment)

func _excused_area() -> Dictionary:
	if serious_reviewed == 0:
		return _area(AREA_EXCUSED, false, 0.0, "No serious errors were reviewed.", "")
	var detail := "%d serious error%s reviewed, %d excused." % [serious_reviewed, "" if serious_reviewed == 1 else "s", serious_excused]
	var comment := "Well done: no serious error was let go." if serious_excused == 0 else "To improve: a serious error needs a report, not a pass."
	return _area(AREA_EXCUSED, true, 100.0 - EXCUSED_PENALTY * serious_excused, detail, comment)

func _mistakes_area() -> Dictionary:
	if staff_work < MIN_STAFF_WORK:
		return _area(AREA_MISTAKES, false, 0.0, "Too little staff work to judge (%d)." % staff_work, "")
	var rate := float(staff_mistakes) / staff_work
	var area_score := 100.0 * clampf((MISTAKE_RATE_BAD - rate) / (MISTAKE_RATE_BAD - MISTAKE_RATE_GOOD), 0.0, 1.0)
	var detail := "%d mistake%s in %d pieces of staff work (%d%%)." % [staff_mistakes, "" if staff_mistakes == 1 else "s", staff_work, roundi(rate * 100.0)]
	var comment := "Well done: your team's error rate is low." if rate <= MISTAKE_RATE_GOOD else "To improve: put your most accurate staff on the desks, and coach the rest."
	return _area(AREA_MISTAKES, true, area_score, detail, comment)

func _abandoned_area() -> Dictionary:
	var arrived := staff_line_served + staff_line_abandoned
	if arrived == 0:
		return _area(AREA_ABANDONED, false, 0.0, "No customers at the staffed windows.", "")
	var rate := float(staff_line_abandoned) / arrived
	var detail := "%d of %d customers at staffed windows gave up waiting." % [staff_line_abandoned, arrived]
	var comment := "Well done: nobody gave up waiting." if staff_line_abandoned == 0 else "To improve: keep every window staffed with quick tellers."
	return _area(AREA_ABANDONED, true, 100.0 * (1.0 - clampf(rate / ABANDON_RATE_BAD, 0.0, 1.0)), detail, comment)

func _vacancy_area() -> Dictionary:
	var hours := vacant_desk_minutes / 60.0
	var detail := "Every desk was staffed during opening hours."
	var comment := "Well done: no desk stood empty."
	if vacant_desk_minutes > 0.0:
		detail = "Desks stood vacant for %.1f desk-hours of opening time." % hours
		comment = "To improve: fill a vacant desk quickly, from the roster or by hiring."
	return _area(AREA_VACANCY, true, 100.0 - VACANCY_PENALTY_PER_HOUR * hours, detail, comment)

func _hiring_area() -> Dictionary:
	if hire_verdicts.is_empty():
		return _area(AREA_HIRING, false, 0.0, "No hires.", "")
	var total := 0.0
	var good := 0
	for verdict in hire_verdicts:
		total += HIRE_SCORES[verdict]
		if verdict == HiringManager.Verdict.BEST:
			good += 1
	var count := hire_verdicts.size()
	var detail := "%d hire%s, %d of them the best candidate." % [count, "" if count == 1 else "s", good]
	var comment := "Well done: you picked strong candidates." if good == count else "To improve: compare the candidates' answers carefully before hiring."
	return _area(AREA_HIRING, true, total / count, detail, comment)

# --- letters -----------------------------------------------------------------------------

## The review letter's title and body for run_review()'s result.
func review_title(result: Dictionary) -> String:
	return "Branch Manager Review — Days %d-%d" % [result["first_day"], result["last_day"]]

func review_body(result: Dictionary) -> String:
	var rating: Rating = result["rating"]
	var overall: float = result["score"]
	var lines: PackedStringArray = [
		"This is your review for your last %d days as Branch Manager (Days %d-%d)." % [REVIEW_INTERVAL_DAYS, result["first_day"], result["last_day"]],
		"",
		"Rating: %s (%d / 100)" % [rating_label(rating), roundi(overall)],
	]
	var areas: Array = result["areas"]
	for entry: Variant in areas:
		var area: Dictionary = entry
		lines.append("")
		var area_score: float = area["score"]
		var heading := "%s — %d/100 (weight %d%%)" % [area["name"], roundi(area_score), area["weight"]] if area["rated"] else "%s — not rated" % area["name"]
		lines.append(heading)
		var detail: String = area["detail"]
		lines.append(detail)
		var comment: String = area["comment"]
		if comment != "":
			lines.append(comment)
	lines.append("")
	lines.append(_outcome_text(result))
	return "\n".join(lines)

func _outcome_text(result: Dictionary) -> String:
	var rating: Rating = result["rating"]
	var before: int = result["warnings_before"]
	var now: int = result["warnings"]
	var text := ""
	match rating:
		Rating.EXCEEDS:
			text = "Excellent work: a bonus of %+d Score and %+d Reputation." % [result["score_change"], result["reputation_change"]]
			text += " One regional warning has been removed." if before > now else " You have no regional warnings to remove."
		Rating.MEETS:
			text = "Solid work. No change to your record."
		Rating.NEEDS_IMPROVEMENT:
			text = "This review adds a regional warning."
		_:
			text = "This review adds a regional warning and costs %d Reputation." % -UNSATISFACTORY_REPUTATION
	text += "\n\nRegional warnings: %d of %d." % [now, WARNINGS_FOR_DEMOTION]
	if now >= WARNINGS_FOR_DEMOTION:
		text += " That is the limit: see the letter that follows."
	elif now > 0:
		text += " At %d you'll return to the Loan Officer role." % WARNINGS_FOR_DEMOTION
	return text

func zero_reputation_body(warnings_now: int) -> String:
	var text := "Customer satisfaction at your branch has fallen to zero. As Branch Manager, that is your responsibility, and it earns a regional warning.\n\nRegional warnings: %d of %d." % [warnings_now, WARNINGS_FOR_DEMOTION]
	if warnings_now >= WARNINGS_FOR_DEMOTION:
		text += " That is the limit: at the end of today you'll return to the Loan Officer role."
	else:
		text += " At %d you'll return to the Loan Officer role." % WARNINGS_FOR_DEMOTION
	return text

func demotion_body(warnings_reached: int) -> String:
	return "Following %d regional warnings, you are no longer the Branch Manager, effective immediately. You return to the Loan Officer role.\n\nThe Player Teller Window and the Loan Desk are yours to work again, and the branch's disciplinary reports apply to you again, starting from none. Your staff, your hires and their records stay as they are.\n\nTo be promoted again you'll need %d more XP (%d in total) and Reputation of at least %d." % [
		warnings_reached, XPManager.REPROMOTION_XP, XPManager.repromotion_xp_target, XPManager.REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER,
	]

# --- save and load -------------------------------------------------------------------------

## Day-keyed data is saved with String keys (JSON keys are strings).
func save_data() -> Dictionary:
	var vault := {}
	for day in vault_by_day:
		vault[str(day)] = vault_by_day[day]
	return {
		"warnings": warnings,
		"window_first_day": window_first_day,
		"counted_through_day": counted_through_day,
		"window": {
			"vault_by_day": vault,
			"serious_reviewed": serious_reviewed,
			"serious_ignored": serious_ignored,
			"serious_excused": serious_excused,
			"reviews": reviews,
			"unfair_reports": unfair_reports,
			"staff_work": staff_work,
			"staff_mistakes": staff_mistakes,
			"staff_line_served": staff_line_served,
			"staff_line_abandoned": staff_line_abandoned,
			"vacant_desk_minutes": SaveGame.time_for_save(vacant_desk_minutes),
			"hire_verdicts": hire_verdicts.duplicate(),
		},
	}

## Loaded after XPManager, GameClock and BusinessDay. A Branch Manager from
## a save made before reviews existed starts a window from the loaded day.
func load_data(data: Dictionary) -> void:
	reset()
	# Up to WARNINGS_FOR_DEMOTION itself: a zero-Reputation demotion due at
	# the End of Day.
	warnings = clampi(SaveGame.int_of(data, "warnings", 0), 0, WARNINGS_FOR_DEMOTION)
	window_first_day = maxi(0, SaveGame.int_of(data, "window_first_day", 0))
	counted_through_day = maxi(0, SaveGame.int_of(data, "counted_through_day", 0))
	if not XPManager.is_branch_manager_unlocked:
		window_first_day = 0
	elif window_first_day == 0:
		_start_window(BusinessDay.stats_day + 1, BusinessDay.stats_day - 1)
		return
	var window := SaveGame.dict_of(data, "window")
	var vault := SaveGame.dict_of(window, "vault_by_day")
	for key: Variant in vault:
		if not key is String:
			continue
		var day_key: String = key
		var result := SaveGame.int_of(vault, day_key, -1)
		if day_key.is_valid_int() and VAULT_DAY_SCORES.has(result):
			vault_by_day[day_key.to_int()] = result
	serious_reviewed = maxi(0, SaveGame.int_of(window, "serious_reviewed", 0))
	serious_ignored = maxi(0, SaveGame.int_of(window, "serious_ignored", 0))
	serious_excused = maxi(0, SaveGame.int_of(window, "serious_excused", 0))
	reviews = maxi(0, SaveGame.int_of(window, "reviews", 0))
	unfair_reports = maxi(0, SaveGame.int_of(window, "unfair_reports", 0))
	staff_work = maxi(0, SaveGame.int_of(window, "staff_work", 0))
	staff_mistakes = maxi(0, SaveGame.int_of(window, "staff_mistakes", 0))
	staff_line_served = maxi(0, SaveGame.int_of(window, "staff_line_served", 0))
	staff_line_abandoned = maxi(0, SaveGame.int_of(window, "staff_line_abandoned", 0))
	vacant_desk_minutes = maxf(0.0, SaveGame.float_of(window, "vacant_desk_minutes", 0.0))
	for verdict in SaveGame.ints_of(SaveGame.array_of(window, "hire_verdicts")):
		if HIRE_SCORES.has(verdict):
			hire_verdicts.append(verdict)
