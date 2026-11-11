extends RefCounted
class_name CreditReport

## An applicant's credit report (bank policy, not any law): what "Run Credit
## Check" pulls besides the score. The figures live on LoanApplication as
## flat exported fields (so they save with it, like the documents); this
## class issues them, says what they mean, and holds the policy for how they
## count in the risk assessment (LoanApplication.credit_report_points()).
##
## Consistent with the score: the lower the score, the more late payments,
## the higher the utilization and the more often a collection or bankruptcy
## sits in the last seven years, but within a band each report has its own
## story (Story below), so two applicants with much the same score can read
## very differently.
##
## Fair lending: a report is issued from the applicant's finance generator
## and their credit score alone (LoanApplicantGenerator), never from the name
## or look, and nothing in it describes who the applicant is.

## The story a report tells, chosen by LoanApplicantGenerator with the rest of
## the applicant's profile. Each has a fixed number of risk points
## (story_points()):
## - NORMAL: a history in line with the score, nothing the policy counts (a
##   score under 670 always has something late or a balance over 30%, so it's
##   never a clean history). 0.
## - REBUILT: a score under 670 from older trouble (a collection or
##   bankruptcy over two years ago, or old late payments), with a clean last
##   two years: nothing late, utilization 30% or less. −1.
## - MAXED: utilization over 75%. +1.
## - RECENT_MARK: a serious mark in the last two years (a 90-day late
##   payment, a collection, or for scores under 600 a bankruptcy). +2. Only
##   for scores under 740.
## - RECENT_MARK_MAXED: both. +3.
enum Story { NORMAL, REBUILT, MAXED, RECENT_MARK, RECENT_MARK_MAXED }

## --- Bank policy: how the report counts in the risk assessment ---
## "Recent" is the last two years.
const RECENT_MONTHS: int = 24
## Serious marks stay on a report for seven years.
const REPORT_MONTHS: int = 84
## A 90-day late payment, a collection or a bankruptcy in the last two years.
const SERIOUS_MARK_POINTS: int = 2
## Utilization over this share of credit limits.
const HIGH_UTILIZATION_PERCENT: int = 75
const HIGH_UTILIZATION_POINTS: int = 1
## A score under GOOD_CREDIT with a clean last two years (nothing late, no
## serious mark, utilization at most this) counts for less.
const CLEAN_UTILIZATION_PERCENT: int = 30
const CLEAN_HISTORY_POINTS: int = -1

const POLICY_TEXT: String = "Bank policy: a 90-day late, a collection or a bankruptcy in the last 2 years adds risk; so does utilization over 75%. A score under 670 with a clean last 2 years (nothing late, utilization 30% or less) counts for less."

static func story_points(story: Story) -> int:
	match story:
		Story.REBUILT:
			return CLEAN_HISTORY_POINTS
		Story.MAXED:
			return HIGH_UTILIZATION_POINTS
		Story.RECENT_MARK:
			return SERIOUS_MARK_POINTS
		Story.RECENT_MARK_MAXED:
			return SERIOUS_MARK_POINTS + HIGH_UTILIZATION_POINTS
		_:
			return 0

static func has_recent_mark(story: Story) -> bool:
	return story == Story.RECENT_MARK or story == Story.RECENT_MARK_MAXED

## Can `story` go with `credit_score`? A clean rebuilt history only explains
## a score under 670; a recent serious mark or maxed-out cards don't go with a
## score of 740 or more.
static func story_fits(story: Story, credit_score: int) -> bool:
	match story:
		Story.REBUILT:
			return credit_score < LoanApplication.GOOD_CREDIT
		Story.NORMAL:
			return true
		_:
			return credit_score < LoanApplication.VERY_GOOD_CREDIT

# --- issuing -------------------------------------------------------------------------

## Score bands for the report's figures (LoanApplication.credit_score_band()'s
## five): 0 Excellent 800+, 1 Very Good 740-799, 2 Good 670-739, 3 Fair
## 580-669, 4 Poor under 580.
## Late payments in the last two years for a NORMAL history: [30-day min, max,
## 60-day min, max] per band. Fair and Poor always have one or more.
const LATES_BY_BAND: Array = [[0, 1, 0, 0], [0, 1, 0, 0], [0, 2, 0, 1], [1, 4, 0, 2], [2, 6, 1, 3]]
## Chance of a single 30-day late at all, Excellent and Very Good (the
## others always roll their range).
const TOP_BAND_LATE_CHANCE: Array[float] = [0.1, 0.3]
## Chance of a 60-day late in the Good band (its range is 0-1).
const GOOD_BAND_60_DAY_CHANCE: float = 0.2
## Utilization (percent) for histories that aren't maxed out, per band.
const UTILIZATION_BY_BAND: Array = [[1, 12], [4, 28], [10, 50], [28, 70], [45, 75]]
const MAXED_UTILIZATION: Array[int] = [76, 98]
const REBUILT_UTILIZATION: Array[int] = [4, 30]
## On-time share of every payment ever made (percent), per band.
const ON_TIME_BY_BAND: Array = [[99, 100], [97, 99], [94, 98], [87, 95], [76, 89]]
## Older trouble (two to seven years ago) behind a score under 670 with a
## NORMAL history: an old collection, and under 580 sometimes an old
## bankruptcy.
const OLD_COLLECTION_CHANCE: float = 0.4
const OLD_BANKRUPTCY_CHANCE: float = 0.2
## Behind a REBUILT history: a collection or a bankruptcy two to seven years
## ago (the rest, late payments over two years ago, no longer on the 2-year
## count).
const REBUILT_COLLECTION_CHANCE: float = 0.45
const REBUILT_BANKRUPTCY_CHANCE: float = 0.25
## A recent serious mark's kind, by weight: a 90-day late payment, a
## collection, or (scores under RECENT_BANKRUPTCY_MAX_SCORE only) a
## bankruptcy.
const RECENT_MARK_WEIGHTS: Array[int] = [4, 4, 1]
const RECENT_BANKRUPTCY_MAX_SCORE: int = 600

## Fills in `application`'s credit report from `rng` and its credit score,
## telling `story` (see Story; one that doesn't fit the score is told as
## NORMAL). Never reads the name, look or anything else about the applicant.
static func issue(application: LoanApplication, rng: RandomNumberGenerator, story: Story) -> void:
	var score := application.credit_score
	if not story_fits(story, score):
		story = Story.NORMAL
	var band := band_index(score)
	# 0 at the top of the scale, 1 at the bottom.
	var strain := 1.0 - clampf((score - 500) / 330.0, 0.0, 1.0)

	var late_30 := 0
	var late_60 := 0
	var late_90 := 0
	var collections := 0
	var since_collection := 0
	var since_bankruptcy := 0
	var utilization := 0
	if story == Story.REBUILT:
		utilization = rng.randi_range(REBUILT_UTILIZATION[0], REBUILT_UTILIZATION[1])
		var roll := rng.randf()
		if roll < REBUILT_COLLECTION_CHANCE:
			collections = rng.randi_range(1, 2)
			since_collection = rng.randi_range(RECENT_MONTHS + 1, REPORT_MONTHS)
		elif roll < REBUILT_COLLECTION_CHANCE + REBUILT_BANKRUPTCY_CHANCE:
			since_bankruptcy = rng.randi_range(RECENT_MONTHS + 1, REPORT_MONTHS)
	else:
		var lates: Array = LATES_BY_BAND[band]
		var min_30: int = lates[0]
		var max_30: int = lates[1]
		var min_60: int = lates[2]
		var max_60: int = lates[3]
		late_30 = rng.randi_range(min_30, max_30)
		late_60 = rng.randi_range(min_60, max_60)
		if band <= 1 and rng.randf() >= TOP_BAND_LATE_CHANCE[band]:
			late_30 = 0
		if band == 2 and rng.randf() >= GOOD_BAND_60_DAY_CHANCE:
			late_60 = 0
		var usage: Array = UTILIZATION_BY_BAND[band]
		var usage_min: int = usage[0]
		var usage_max: int = usage[1]
		utilization = rng.randi_range(usage_min, usage_max)
		if story == Story.MAXED or story == Story.RECENT_MARK_MAXED:
			utilization = rng.randi_range(MAXED_UTILIZATION[0], MAXED_UTILIZATION[1])
		# Older trouble behind a low score.
		if score < LoanApplication.GOOD_CREDIT and rng.randf() < OLD_COLLECTION_CHANCE:
			collections = rng.randi_range(1, 2)
			since_collection = rng.randi_range(RECENT_MONTHS + 1, REPORT_MONTHS)
		if score < LoanApplication.FAIR_CREDIT and rng.randf() < OLD_BANKRUPTCY_CHANCE:
			since_bankruptcy = rng.randi_range(RECENT_MONTHS + 1, REPORT_MONTHS)
		if has_recent_mark(story):
			var weights: Array[int] = RECENT_MARK_WEIGHTS.duplicate()
			if score >= RECENT_BANKRUPTCY_MAX_SCORE:
				weights[2] = 0
			match LoanApplicantGenerator._weighted(rng, weights):
				0:
					late_90 = rng.randi_range(1, 2 if band >= 3 else 1)
				1:
					collections = maxi(collections, 0) + 1
					since_collection = rng.randi_range(1, RECENT_MONTHS)
				_:
					since_bankruptcy = rng.randi_range(6, RECENT_MONTHS)
		# A score under 670 that isn't REBUILT is never a clean history.
		if score < LoanApplication.GOOD_CREDIT and late_30 + late_60 + late_90 == 0 and utilization <= CLEAN_UTILIZATION_PERCENT:
			late_30 = 1

	var on_time: Array = ON_TIME_BY_BAND[band]
	var on_time_min: int = on_time[0]
	var on_time_max: int = on_time[1]
	var on_time_percent := rng.randi_range(on_time_min, on_time_max)
	if late_30 + late_60 + late_90 > 0:
		on_time_percent = mini(on_time_percent, 99)
	elif band <= 1 and collections == 0 and since_bankruptcy == 0:
		on_time_percent = maxi(on_time_percent, 99)

	application.credit_report_issued = true
	application.on_time_percent = on_time_percent
	application.late_30_days = late_30
	application.late_60_days = late_60
	application.late_90_days = late_90
	application.utilization_percent = utilization
	# More accounts with a longer, stronger history; more recent applications
	# for credit lower down.
	application.open_accounts = rng.randi_range(2, 5) + roundi((1.0 - strain) * rng.randi_range(0, 8))
	application.hard_inquiries = rng.randi_range(0, 1 + roundi(strain * 4.0))
	application.collections = collections
	application.months_since_collection = since_collection
	application.months_since_bankruptcy = since_bankruptcy

## The five score bands, best first (LoanApplication.credit_score_band()).
static func band_index(score: int) -> int:
	if score >= 800:
		return 0
	elif score >= LoanApplication.VERY_GOOD_CREDIT:
		return 1
	elif score >= LoanApplication.GOOD_CREDIT:
		return 2
	elif score >= LoanApplication.FAIR_CREDIT:
		return 3
	return 4

# --- shown to the player ---------------------------------------------------------------

## The report as [label, value, explanation] rows, for the review screen
## (after the credit check). Facts and what they mean; never the verdict.
static func rows(application: LoanApplication) -> Array[PackedStringArray]:
	return [
		PackedStringArray(["On-time payments", "%d%%" % application.on_time_percent, "Share of all payments made on time."]),
		PackedStringArray(["Late payments (2 yrs)", late_text(application), "30, 60 or 90+ days overdue."]),
		PackedStringArray(["Credit utilization", "%d%%" % application.utilization_percent, "Card balances ÷ limits; 30% or less is healthy."]),
		PackedStringArray(["Open accounts", str(application.open_accounts), "Cards and loans open now."]),
		PackedStringArray(["Hard inquiries (6 mo)", str(application.hard_inquiries), "Recent applications for new credit."]),
		PackedStringArray(["Serious marks", marks_text(application), "Collections and bankruptcies stay 7 years."]),
	]

## "2 × 30-day, 1 × 90-day" (only the kinds there are), or "None".
static func late_text(application: LoanApplication) -> String:
	var parts: PackedStringArray = []
	for kind: Array in [[application.late_30_days, 30], [application.late_60_days, 60], [application.late_90_days, 90]]:
		var count: int = kind[0]
		if count > 0:
			parts.append("%d × %d-day" % [count, kind[1]])
	return ", ".join(parts) if not parts.is_empty() else "None"

## "1 collection, 1 year 2 months ago · Bankruptcy, 5 years ago", or "None".
static func marks_text(application: LoanApplication) -> String:
	var marks: PackedStringArray = []
	if application.collections > 0:
		marks.append("%d collection%s, latest %s ago" % [application.collections, "" if application.collections == 1 else "s", LoanApplication.employment_text(application.months_since_collection)])
	if application.months_since_bankruptcy > 0:
		marks.append("Bankruptcy, %s ago" % LoanApplication.employment_text(application.months_since_bankruptcy))
	return " · ".join(marks) if not marks.is_empty() else "None"

## One compact paragraph, frozen on a staff review item: "Credit report: on
## time 96% · late (2 yrs) 2 × 30-day · utilization 64% · 7 accounts · 2
## inquiries · marks: None".
static func summary(application: LoanApplication) -> String:
	return "Credit report: on time %d%% · late (2 yrs) %s · utilization %d%% · %d account%s · %d inquir%s · marks: %s" % [
		application.on_time_percent, late_text(application).to_lower(), application.utilization_percent,
		application.open_accounts, "" if application.open_accounts == 1 else "s",
		application.hard_inquiries, "y" if application.hard_inquiries == 1 else "ies", marks_text(application),
	]
