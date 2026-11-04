extends Node

## Autoload singleton — the branch's loan book and how its loans turn out.
##
## Every loan the player or a staff loan officer approves or counter-offers
## is booked (BookedLoan): borrower, amount, risk tier, whether the documents
## checked out, and who made it. Its outcome is rolled at once, from the risk
## tier and the documents alone (OUTCOME_ODDS; fair lending: never the name or
## look, from its own generator seeded by the career and the loan's number),
## and plays out over the next SETTLE_DAYS business days: paid on time, a
## payment going late and then caught up, or a payment going late and then a
## default with part of the loan written off (LOSS_SHARE by purpose). The
## events are processed at each End of Day (close_day()), and the notable ones
## shown in its summary.
##
## Good applicants turned away (LOW risk, documents fine, rejected) are
## counted as lost business.
##
## Every REPORT_INTERVAL_DAYS business days a Loan Portfolio Report (the
## shared letter screen) covers the period: a Loan Officer's own decisions,
## or the whole branch's for a Branch Manager. Its lending quality (rate():
## defaults, losses and good applicants turned away) sets a Score and
## Reputation consequence. The same rating is the Regional review's "Lending
## quality" area (RegionalManager.note_lending()).
##
## Reset with the career (CareerReset) and saved with it (SaveGame).

signal portfolio_reported(result: Dictionary)

## Outcomes settle within this many business days of the loan.
const SETTLE_DAYS: int = 20
## The portfolio report comes every this many business days.
const REPORT_INTERVAL_DAYS: int = 20

## [on time, late then caught up, default] by risk tier, and for any loan
## made on documents that didn't check out (whatever its tier).
const OUTCOME_ODDS: Dictionary = {
	LoanApplication.RiskTier.LOW: [0.90, 0.08, 0.02],
	LoanApplication.RiskTier.MEDIUM: [0.77, 0.15, 0.08],
	LoanApplication.RiskTier.HIGH: [0.45, 0.25, 0.30],
}
const UNVERIFIED_ODDS: Array[float] = [0.30, 0.20, 0.50]

## Share of a defaulted loan written off, by purpose: a home or car can be
## sold to recover most of it; a personal or business loan much less.
const LOSS_SHARE: Dictionary = {"Home": 0.25, "Auto": 0.40, "Personal": 0.75, "Business": 0.60}

## When things happen (business days after the loan): a payment going late
## that's then caught up, and the days after it to catch up; a payment going
## late on the way to a default, and the days after it to default.
const LATE_AFTER: Array[int] = [5, 10]
const CATCH_UP_AFTER: Array[int] = [3, 6]
const DEFAULT_LATE_AFTER: Array[int] = [3, 7]
const DEFAULT_AFTER: Array[int] = [5, 9]
## Calendar days late, as reported.
const DAYS_LATE_CAUGHT_UP: int = 15
const DAYS_LATE_DEFAULTING: int = 30

## --- the lending quality rating (rate()) ---
## Defaults per loan settled: full marks up to GOOD, none from BAD. Losses per
## dollar settled the same. Good applicants turned away per good applicant
## seen: full marks at none, none from TURNED_AWAY_BAD. Small samples are
## measured against at least MIN_SETTLED loans (and MIN_GOOD_SEEN good
## applicants), so one unlucky default doesn't sink a careful lender.
const DEFAULT_RATE_GOOD: float = 0.08
const DEFAULT_RATE_BAD: float = 0.25
const LOSS_RATE_GOOD: float = 0.04
const LOSS_RATE_BAD: float = 0.12
const TURNED_AWAY_BAD: float = 0.30
const MIN_SETTLED: int = 10
const MIN_GOOD_SEEN: int = 5
## The score is never more than this above its weakest part (rate()): too
## lenient and too strict are both costly, and neither is offset by doing the
## other well.
const WEAKEST_PART_MARGIN: float = 10.0

enum Band { STRONG, SOUND, WEAK, POOR }
const STRONG_MIN: float = 85.0
const SOUND_MIN: float = 65.0
const WEAK_MIN: float = 40.0
## Score and Reputation per band (XP follows positive Score). Pitched at a
## single loan decision's range (+10 to -10): a period of good lending earns
## what a correct call does, a poor one costs nearly what the worst call does.
const BAND_SCORE: Dictionary = {Band.STRONG: 10, Band.SOUND: 3, Band.WEAK: -3, Band.POOR: -8}
const BAND_REPUTATION: Dictionary = {Band.STRONG: 2, Band.SOUND: 0, Band.WEAK: -1, Band.POOR: -3}

const SENDER: String = "Credit Risk Department"
## The End of Day shows at most this many loan events.
const MAX_EVENT_LINES: int = 3

## Period statistics, kept for the player's own decisions and the branch's.
const STAT_KEYS: Array[String] = [
	"made", "lent", "on_time", "late", "defaulted", "defaulted_unverified", "losses",
	"settled_amount", "good_seen", "turned_away", "turned_away_amount",
]
const PLAYER: String = "player"
## Who made a loan the player made.
const PLAYER_MAKER: String = "You"
const BRANCH: String = "branch"

var book: Array[BookedLoan] = []
var next_loan_id: int = 1
## The first business day of the current report period.
var period_first_day: int = 1
var period_stats: Dictionary = {}
## The last day close_day() processed, and that day's events
## ({"text", "by_player"}) for its summary.
var last_closed_day: int = 0
var today_events: Array[Dictionary] = []

func _ready() -> void:
	reset()

func reset() -> void:
	book.clear()
	next_loan_id = 1
	period_first_day = 1
	period_stats = {PLAYER: _empty_stats(), BRANCH: _empty_stats()}
	last_closed_day = 0
	today_events.clear()

func _empty_stats() -> Dictionary:
	var stats := {}
	for key in STAT_KEYS:
		stats[key] = 0.0
	return stats

# --- decisions ---------------------------------------------------------------------

## A loan decision (the player's or a staff officer's, `made_by`): an
## approval or counter-offer is booked; a good applicant (LOW, documents fine)
## is counted as seen, and as turned away when rejected. Returns the booked
## loan, or null.
func note_decision(application: LoanApplication, by_player: bool, made_by: String) -> BookedLoan:
	var tier := application.calculate_risk_assessment()
	var documents_ok := application.documents_check_out()
	var good := tier == LoanApplication.RiskTier.LOW and documents_ok
	if good:
		_add("good_seen", 1.0, by_player)
	match application.decision:
		LoanApplication.DecisionType.APPROVE, LoanApplication.DecisionType.COUNTER_OFFER:
			return book_loan(application.applicant_name, application.loan_purpose, application.decision_amount, tier, documents_ok, by_player, made_by)
		LoanApplication.DecisionType.REJECT:
			if good:
				_add("turned_away", 1.0, by_player)
				_add("turned_away_amount", application.requested_amount, by_player)
	return null

## Books a loan made today, with its outcome rolled.
func book_loan(borrower: String, purpose: String, amount: float, tier: LoanApplication.RiskTier, documents_ok: bool, by_player: bool, made_by: String) -> BookedLoan:
	var loan := BookedLoan.new()
	loan.loan_id = next_loan_id
	next_loan_id += 1
	loan.borrower = borrower
	loan.purpose = purpose
	loan.amount = amount
	loan.risk_tier = tier
	loan.documents_ok = documents_ok
	loan.by_player = by_player
	loan.made_by = made_by
	loan.made_day = BusinessDay.stats_day
	roll_outcome(loan, outcome_rng(loan.loan_id))
	book.append(loan)
	_add("made", 1.0, by_player)
	_add("lent", amount, by_player)
	return loan

## The loan's own generator: from the career's seed and the loan's number
## only, so nothing about the borrower can enter it.
func outcome_rng(loan_id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([LoanDeskManager.career_seed, "outcome", loan_id])
	return rng

## The chances [on time, late, default] for a loan of `tier`, made on
## documents that did or didn't check out.
func odds_for(tier: LoanApplication.RiskTier, documents_ok: bool) -> Array[float]:
	if not documents_ok:
		return UNVERIFIED_ODDS
	var tier_odds: Array = OUTCOME_ODDS[tier]
	var odds: Array[float] = []
	odds.assign(tier_odds)
	return odds

## Rolls `loan`'s outcome and timeline from `rng` (its risk tier and
## documents decide the odds).
func roll_outcome(loan: BookedLoan, rng: RandomNumberGenerator) -> void:
	var odds := odds_for(loan.risk_tier, loan.documents_ok)
	var roll := rng.randf()
	if roll < odds[0]:
		loan.outcome = BookedLoan.Outcome.ON_TIME
		loan.resolve_day = loan.made_day + SETTLE_DAYS
	elif roll < odds[0] + odds[1]:
		loan.outcome = BookedLoan.Outcome.LATE
		loan.late_day = loan.made_day + rng.randi_range(LATE_AFTER[0], LATE_AFTER[1])
		loan.days_late = DAYS_LATE_CAUGHT_UP
		loan.resolve_day = loan.late_day + rng.randi_range(CATCH_UP_AFTER[0], CATCH_UP_AFTER[1])
	else:
		loan.outcome = BookedLoan.Outcome.DEFAULT
		loan.late_day = loan.made_day + rng.randi_range(DEFAULT_LATE_AFTER[0], DEFAULT_LATE_AFTER[1])
		loan.days_late = DAYS_LATE_DEFAULTING
		loan.resolve_day = mini(loan.late_day + rng.randi_range(DEFAULT_AFTER[0], DEFAULT_AFTER[1]), loan.made_day + SETTLE_DAYS)
		var share: float = LOSS_SHARE.get(loan.purpose, 0.6)
		loan.loss = roundf(loan.amount * share)

# --- the day's events -------------------------------------------------------------------

## The End of Day for `day` (once a day; teller_room.show_end_of_day()):
## payments going late, loans caught up or defaulted, loans paid on time
## through the settling period; then the portfolio report when one is due.
## Today's notable events are kept for the summary (summary_lines()).
func close_day(day: int) -> void:
	if day <= last_closed_day:
		return
	last_closed_day = day
	today_events.clear()
	var still: Array[BookedLoan] = []
	for loan in book:
		if loan.stage == BookedLoan.Stage.BOOKED and loan.outcome != BookedLoan.Outcome.ON_TIME and loan.late_day <= day:
			loan.stage = BookedLoan.Stage.LATE_REPORTED
			_event("%s: payment %d days late" % [loan.label(), loan.days_late], loan.by_player)
		if loan.resolve_day <= day:
			_resolve(loan)
		else:
			still.append(loan)
	book = still
	if is_report_due(day):
		run_report(day)

func _resolve(loan: BookedLoan) -> void:
	_add("settled_amount", loan.amount, loan.by_player)
	match loan.outcome:
		BookedLoan.Outcome.ON_TIME:
			_add("on_time", 1.0, loan.by_player)
		BookedLoan.Outcome.LATE:
			_add("late", 1.0, loan.by_player)
			_event("%s: caught up on payments" % loan.label(), loan.by_player)
		BookedLoan.Outcome.DEFAULT:
			_add("defaulted", 1.0, loan.by_player)
			if not loan.documents_ok:
				_add("defaulted_unverified", 1.0, loan.by_player)
			_add("losses", loan.loss, loan.by_player)
			_event("%s: defaulted — %s written off" % [loan.label(), LoanApplication.dollars(loan.loss)], loan.by_player)

func _event(text: String, by_player: bool) -> void:
	today_events.append({"text": text, "by_player": by_player})

## Today's loan events for the End of Day summary: the player's own loans
## always, the staff's too for a Branch Manager (`whole_branch`). At most
## MAX_EVENT_LINES, then "… and N more".
func summary_lines(whole_branch: bool) -> PackedStringArray:
	var shown: Array[String] = []
	for event in today_events:
		var by_player: bool = event["by_player"]
		if by_player or whole_branch:
			var text: String = event["text"]
			shown.append(text + (" (yours)" if by_player and whole_branch else ""))
	var lines: PackedStringArray = []
	for i in mini(shown.size(), MAX_EVENT_LINES):
		lines.append(shown[i])
	if shown.size() > MAX_EVENT_LINES:
		lines.append("… and %d more" % (shown.size() - MAX_EVENT_LINES))
	return lines

# --- statistics ----------------------------------------------------------------------

## Adds to the period's branch figures, the player's when it's their loan,
## and the Regional review window's.
func _add(key: String, value: float, by_player: bool) -> void:
	var branch: Dictionary = period_stats[BRANCH]
	branch[key] = stat(branch, key) + value
	if by_player:
		var player: Dictionary = period_stats[PLAYER]
		player[key] = stat(player, key) + value
	RegionalManager.note_lending(key, value)

func stat(stats: Dictionary, key: String) -> float:
	var value: Variant = stats.get(key, 0.0)
	if value is float or value is int:
		var number: float = value
		return number
	return 0.0

## The lending quality of `stats` (STAT_KEYS figures): {"rated", "score"
## (0-100), "defaults", "losses", "turned_away" (each a part's score, or -1
## when there was nothing to rate)}. Rated when anything was settled or a
## good applicant was seen. The score is the average of the rated parts,
## capped at the weakest part + WEAKEST_PART_MARGIN, so both extremes rate
## Poor: approving everything (defaults 29, losses 25, nobody turned away
## 100: 35) and turning every good applicant away (0); a careful lender rates
## 100, a mostly sensible one with a few mistakes Sound (about 77).
func rate(stats: Dictionary) -> Dictionary:
	var settled := stat(stats, "on_time") + stat(stats, "late") + stat(stats, "defaulted")
	var good_seen := stat(stats, "good_seen")
	var parts: Array[float] = []
	var defaults := -1.0
	var losses := -1.0
	var turned := -1.0
	if settled > 0.0:
		var default_rate := stat(stats, "defaulted") / maxf(settled, MIN_SETTLED)
		defaults = _scale(default_rate, DEFAULT_RATE_GOOD, DEFAULT_RATE_BAD)
		parts.append(defaults)
		var settled_amount := stat(stats, "settled_amount")
		if settled_amount > 0.0:
			var loss_rate := stat(stats, "losses") / settled_amount * settled / maxf(settled, MIN_SETTLED)
			losses = _scale(loss_rate, LOSS_RATE_GOOD, LOSS_RATE_BAD)
			parts.append(losses)
	if good_seen > 0.0:
		var turned_rate := stat(stats, "turned_away") / maxf(good_seen, MIN_GOOD_SEEN)
		turned = _scale(turned_rate, 0.0, TURNED_AWAY_BAD)
		parts.append(turned)
	if parts.is_empty():
		return {"rated": false, "score": 0.0, "defaults": defaults, "losses": losses, "turned_away": turned}
	var total := 0.0
	var weakest := 100.0
	for part in parts:
		total += part
		weakest = minf(weakest, part)
	# The average, but never more than WEAKEST_PART_MARGIN above the weakest
	# part: strength in one can't make up for failing another.
	var score := minf(total / parts.size(), weakest + WEAKEST_PART_MARGIN)
	return {"rated": true, "score": score, "defaults": defaults, "losses": losses, "turned_away": turned}

## 100 at or below `good`, 0 at or above `bad`, in between linearly.
func _scale(value: float, good: float, bad: float) -> float:
	if bad <= good:
		return 100.0 if value <= good else 0.0
	return 100.0 * clampf((bad - value) / (bad - good), 0.0, 1.0)

func band_for(score: float) -> Band:
	if score >= STRONG_MIN:
		return Band.STRONG
	if score >= SOUND_MIN:
		return Band.SOUND
	if score >= WEAK_MIN:
		return Band.WEAK
	return Band.POOR

func band_label(band: Band) -> String:
	match band:
		Band.STRONG:
			return "Strong"
		Band.SOUND:
			return "Sound"
		Band.WEAK:
			return "Weak"
		_:
			return "Poor"

# --- the portfolio report -------------------------------------------------------------------

func period_last_day() -> int:
	return period_first_day + REPORT_INTERVAL_DAYS - 1

func is_report_due(day: int) -> bool:
	return day >= period_last_day()

## The period's report: for a Branch Manager the whole branch, for a Loan
## Officer their own decisions; a Teller gets none. Applies the consequences,
## starts the next period, and emits portfolio_reported (the letter). Returns
## the result: {"first_day", "last_day", "scope" ("branch"/"player"),
## "stats", "rating" (rate()), "band", "score_change", "reputation_change",
## "xp_change"}, or {} when there was no report.
func run_report(day: int) -> Dictionary:
	var first := period_first_day
	var scope := ""
	if XPManager.is_branch_manager_unlocked:
		scope = BRANCH
	elif XPManager.is_loan_officer_unlocked:
		scope = PLAYER
	var stats: Dictionary = period_stats.get(scope, {}) if scope != "" else {}
	period_first_day = day + 1
	period_stats = {PLAYER: _empty_stats(), BRANCH: _empty_stats()}
	if scope == "":
		return {}
	var rating := rate(stats)
	var result := {"first_day": first, "last_day": day, "scope": scope, "stats": stats, "rating": rating}
	var score := 0
	var reputation := 0
	if rating["rated"]:
		var rating_score: float = rating["score"]
		var band := band_for(rating_score)
		result["band"] = band
		score = BAND_SCORE[band]
		reputation = BAND_REPUTATION[band]
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
	var record := HistoryManager.add_record(
		DecisionRecord.Role.BRANCH_MANAGER if scope == BRANCH else DecisionRecord.Role.LOAN_OFFICER,
		"Loan Portfolio Report, Days %d-%d: %s" % [first, day, report_rating_text(result)],
		report_rating_text(result),
	)
	# A record, not a decision to override in Approvals.
	record.reviewed = true
	portfolio_reported.emit(result)
	return result

func report_rating_text(result: Dictionary) -> String:
	var rating: Dictionary = result["rating"]
	if not rating["rated"]:
		return "not rated"
	var band: Band = result["band"]
	var rating_score: float = rating["score"]
	return "%s (%d/100)" % [band_label(band), roundi(rating_score)]

func report_title(result: Dictionary) -> String:
	return "Loan Portfolio Report — Days %d-%d" % [result["first_day"], result["last_day"]]

func report_body(result: Dictionary) -> String:
	var stats: Dictionary = result["stats"]
	var whose := "the branch's loans (yours and your staff's)" if result["scope"] == BRANCH else "the loans you decided"
	var made := roundi(stat(stats, "made"))
	var lines: PackedStringArray = [
		"This report covers %s over the last %d business days (Days %d-%d)." % [whose, REPORT_INTERVAL_DAYS, result["first_day"], result["last_day"]],
		"",
		"Loans made: %d (%s lent)" % [made, LoanApplication.dollars(stat(stats, "lent"))],
		"Settled: %d paid on time · %d ran late, then caught up · %d defaulted" % [roundi(stat(stats, "on_time")), roundi(stat(stats, "late")), roundi(stat(stats, "defaulted"))],
		"Losses: %s written off" % LoanApplication.dollars(stat(stats, "losses")),
		"Good applicants turned away: %d of %d (%s of sound lending)" % [roundi(stat(stats, "turned_away")), roundi(stat(stats, "good_seen")), LoanApplication.dollars(stat(stats, "turned_away_amount"))],
		"",
		"Lending quality: %s" % report_rating_text(result),
		"",
	]
	lines.append_array(comments(result))
	lines.append("")
	lines.append("Both count: a lender who says yes to everyone loses money to defaults, and one who says no to everyone loses good business to other banks.")
	lines.append("")
	var rating: Dictionary = result["rating"]
	if rating["rated"]:
		lines.append("Result: %+d Score, %+d Reputation." % [result["score_change"], result["reputation_change"]])
	else:
		lines.append("Nothing to rate this period, so no change to your record.")
	return "\n".join(lines)

## One line each on what went well or badly.
func comments(result: Dictionary) -> PackedStringArray:
	var stats: Dictionary = result["stats"]
	var rating: Dictionary = result["rating"]
	var lines: PackedStringArray = []
	var defaulted := roundi(stat(stats, "defaulted"))
	var unverified := roundi(stat(stats, "defaulted_unverified"))
	var defaults: float = rating["defaults"]
	if defaults >= 0.0:
		if defaulted == 0:
			lines.append("Well done: no loan defaulted.")
		elif defaults >= SOUND_MIN:
			lines.append("Defaults were within what careful lending expects (%d, %s written off)." % [defaulted, LoanApplication.dollars(stat(stats, "losses"))])
		else:
			lines.append("Too lenient: %d loan%s defaulted, writing off %s. Check total DTI, credit and the documents before lending." % [defaulted, "" if defaulted == 1 else "s", LoanApplication.dollars(stat(stats, "losses"))])
		if unverified > 0:
			lines.append("%d of the defaults %s on documents that didn't check out." % [unverified, "was" if unverified == 1 else "were"])
	var turned := roundi(stat(stats, "turned_away"))
	if stat(stats, "good_seen") > 0.0:
		if turned == 0:
			lines.append("Well done: every good applicant got their loan.")
		else:
			lines.append("Too strict: %d good applicant%s turned away, %s of sound lending lost to other banks." % [turned, " was" if turned == 1 else "s were", LoanApplication.dollars(stat(stats, "turned_away_amount"))])
	if lines.is_empty():
		lines.append("No loans settled and no good applicants came this period.")
	return lines

# --- save and load ---------------------------------------------------------------------

func save_data() -> Dictionary:
	var loans: Array = []
	for loan in book:
		loans.append(SaveGame.resource_to_dict(loan))
	return {
		"book": loans,
		"next_loan_id": next_loan_id,
		"period_first_day": period_first_day,
		"period_stats": period_stats.duplicate(true),
		"last_closed_day": last_closed_day,
		"today_events": today_events.duplicate(true),
	}

## A save from before the loan book starts an empty one, its first period
## from the loaded day (call after GameClock and BusinessDay).
func load_data(data: Dictionary) -> void:
	reset()
	if not data.has("book"):
		period_first_day = maxi(1, BusinessDay.stats_day)
		last_closed_day = BusinessDay.stats_day - 1
		return
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "book")):
		var loan := BookedLoan.new()
		SaveGame.fill_resource(loan, entry)
		book.append(loan)
	next_loan_id = maxi(1, SaveGame.int_of(data, "next_loan_id", 1))
	period_first_day = maxi(1, SaveGame.int_of(data, "period_first_day", 1))
	var saved := SaveGame.dict_of(data, "period_stats")
	for scope: String in [PLAYER, BRANCH]:
		var from := SaveGame.dict_of(saved, scope)
		var stats: Dictionary = period_stats[scope]
		for key in STAT_KEYS:
			stats[key] = SaveGame.float_of(from, key, 0.0)
	last_closed_day = maxi(0, SaveGame.int_of(data, "last_closed_day", 0))
	for event in SaveGame.dicts_of(SaveGame.array_of(data, "today_events")):
		today_events.append({"text": SaveGame.string_of(event, "text", ""), "by_player": SaveGame.bool_of(event, "by_player", false)})
