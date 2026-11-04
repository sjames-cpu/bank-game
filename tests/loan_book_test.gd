extends "res://tests/support/teller_room_suite.gd"

## The loan book and loan outcomes (LoanBookManager, BookedLoan): loans join
## the book; outcomes come at the configured odds by tier and documents and
## settle within SETTLE_DAYS; their events reach the End of Day summary; good
## applicants turned away are counted; the Loan Portfolio Report's numbers,
## rating and consequences; the Regional review's Lending quality area and
## weights; fair lending (outcomes never depend on the borrower); save, load
## and career reset.

const Tier := LoanApplication.RiskTier
const Outcome := BookedLoan.Outcome

var lo: LoanOfficerScreen
var review: LoanReviewScreen
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	lo = room.loan_officer_screen
	review = lo.loan_review_screen

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			application.documents_issued = true
			return application
	return null

func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

## Opens `application`, verifies, checks credit and decides.
func decide(application: LoanApplication, decision: LoanApplication.DecisionType, reasons: Array = []) -> void:
	LoanDeskManager.player_queue.push_front(application)
	lo.applications_reviewed = 0
	lo.review_next_button.pressed.emit()
	review.verify_documents_button.pressed.emit()
	review.run_credit_check_button.pressed.emit()
	match decision:
		LoanApplication.DecisionType.APPROVE:
			review.approve_button.pressed.emit()
		LoanApplication.DecisionType.COUNTER_OFFER:
			review.counter_offer_button.pressed.emit()
			review.counter_offer_amount_spinbox.value = 10000.0
			review.submit_counter_offer_button.pressed.emit()
		_:
			review.reject_button.pressed.emit()
			for reason: int in reasons:
				review.reason_checks[reason].button_pressed = true
			review.submit_denial_button.pressed.emit()
	review.close_button.pressed.emit()

## A booked loan with a fixed outcome: late on `late_day`, settled on
## `resolve_day` (days after `made_day`).
func fixed_loan(borrower: String, outcome: Outcome, by_player: bool = true, amount: float = 20000.0, purpose: String = "Auto", documents_ok: bool = true, made_day: int = 1) -> BookedLoan:
	var loan := BookedLoan.new()
	loan.loan_id = LoanBookManager.next_loan_id
	LoanBookManager.next_loan_id += 1
	loan.borrower = borrower
	loan.purpose = purpose
	loan.amount = amount
	loan.documents_ok = documents_ok
	loan.by_player = by_player
	loan.made_by = "You" if by_player else "Priya Anand"
	loan.made_day = made_day
	loan.outcome = outcome
	match outcome:
		Outcome.ON_TIME:
			loan.resolve_day = made_day + LoanBookManager.SETTLE_DAYS
		Outcome.LATE:
			loan.late_day = made_day + 5
			loan.days_late = LoanBookManager.DAYS_LATE_CAUGHT_UP
			loan.resolve_day = made_day + 9
		Outcome.DEFAULT:
			loan.late_day = made_day + 4
			loan.days_late = LoanBookManager.DAYS_LATE_DEFAULTING
			loan.resolve_day = made_day + 10
			loan.loss = roundf(amount * loss_share(purpose))
	LoanBookManager.book.append(loan)
	return loan

func score_of(rating: Dictionary) -> float:
	var value: float = rating["score"]
	return value

func band_of(rating: Dictionary) -> LoanBookManager.Band:
	return LoanBookManager.band_for(score_of(rating))

func loss_share(purpose: String) -> float:
	var share: float = LoanBookManager.LOSS_SHARE[purpose]
	return share

func branch_stats() -> Dictionary:
	return LoanBookManager.period_stats[LoanBookManager.BRANCH]

func player_stats() -> Dictionary:
	return LoanBookManager.period_stats[LoanBookManager.PLAYER]

func stats_of(values: Dictionary) -> Dictionary:
	var stats := {}
	for key in LoanBookManager.STAT_KEYS:
		stats[key] = LoanBookManager.stat(values, key)
	return stats

# --- the book ------------------------------------------------------------------------

func test_approved_and_countered_loans_join_the_book() -> void:
	clock_in_at_loan_desk()
	decide(sample("Maria Chen"), LoanApplication.DecisionType.APPROVE)
	decide(sample("Angela Reyes"), LoanApplication.DecisionType.COUNTER_OFFER)
	decide(sample("Marcus Webb"), LoanApplication.DecisionType.REJECT, [LoanApplication.DenialReason.TOTAL_DTI])
	assert_int(LoanBookManager.book.size()).is_equal(2)
	var maria := LoanBookManager.book[0]
	assert_str(maria.borrower).is_equal("Maria Chen")
	assert_str(maria.purpose).is_equal("Auto")
	assert_float(maria.amount).is_equal(15000.0)
	assert_int(maria.risk_tier).is_equal(Tier.LOW)
	assert_bool(maria.documents_ok).is_true()
	assert_bool(maria.by_player).is_true()
	assert_str(maria.made_by).is_equal("You")
	assert_int(maria.made_day).is_equal(BusinessDay.stats_day)
	# A counter-offer is booked at the amount offered.
	assert_float(LoanBookManager.book[1].amount).is_equal(10000.0)
	assert_int(LoanBookManager.book[1].risk_tier).is_equal(Tier.MEDIUM)
	assert_float(LoanBookManager.stat(player_stats(), "made")).is_equal(2.0)
	assert_float(LoanBookManager.stat(player_stats(), "lent")).is_equal(25000.0)

	# A staff officer's loans too, under their name, for the branch only.
	var worker := room.loan_desk_worker
	worker.staff_npc.staff.skill = 10
	worker.staff_doc_slips = false
	worker.decide_next(sample("David Okafor"))
	var staff_loan := LoanBookManager.book[-1]
	assert_str(staff_loan.borrower).is_equal("David Okafor")
	assert_bool(staff_loan.by_player).is_false()
	assert_str(staff_loan.made_by).is_equal(worker.staff_npc.staff.staff_name)
	assert_float(LoanBookManager.stat(branch_stats(), "made")).is_equal(3.0)
	assert_float(LoanBookManager.stat(player_stats(), "made")).is_equal(2.0)

	# A loan on documents that didn't check out says so.
	var unverified := sample("Noah Kim")
	unverified.id_problem = IdCard.Problem.EXPIRED
	decide(unverified, LoanApplication.DecisionType.APPROVE)
	assert_bool(LoanBookManager.book[-1].documents_ok).is_false()

# --- outcomes ------------------------------------------------------------------------

## Over 20,000 loans of each kind, the outcomes come at OUTCOME_ODDS (and
## UNVERIFIED_ODDS for documents that didn't check out), each settled within
## SETTLE_DAYS business days, losses at LOSS_SHARE.
func test_outcomes_come_at_their_odds_by_tier_and_documents() -> void:
	var count := 20000
	var kinds: Array = [[Tier.LOW, true], [Tier.MEDIUM, true], [Tier.HIGH, true], [Tier.LOW, false], [Tier.HIGH, false]]
	var report: PackedStringArray = []
	for kind: Array in kinds:
		var tier: Tier = kind[0]
		var documents_ok: bool = kind[1]
		var tallies := [0, 0, 0]
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in count:
			var loan := BookedLoan.new()
			loan.risk_tier = tier
			loan.documents_ok = documents_ok
			loan.made_day = 7
			loan.amount = 10000.0
			loan.purpose = ["Auto", "Home", "Personal", "Business"][i % 4]
			LoanBookManager.roll_outcome(loan, rng)
			tallies[loan.outcome] += 1
			assert_int(loan.resolve_day).is_between(8, 7 + LoanBookManager.SETTLE_DAYS)
			match loan.outcome:
				Outcome.ON_TIME:
					assert_int(loan.resolve_day).is_equal(7 + LoanBookManager.SETTLE_DAYS)
					assert_float(loan.loss).is_equal(0.0)
				Outcome.LATE:
					assert_int(loan.late_day).is_less(loan.resolve_day)
					assert_int(loan.days_late).is_equal(LoanBookManager.DAYS_LATE_CAUGHT_UP)
				Outcome.DEFAULT:
					assert_int(loan.late_day).is_less(loan.resolve_day)
					assert_float(loan.loss).is_equal(roundf(10000.0 * loss_share(loan.purpose)))
		var odds: Array[float] = LoanBookManager.odds_for(tier, documents_ok)
		var shares: PackedStringArray = []
		for outcome in 3:
			var share: float = tallies[outcome] / float(count)
			shares.append("%.1f%%" % (share * 100.0))
			assert_float(share).override_failure_message("tier %d, documents %s, outcome %d" % [tier, documents_ok, outcome]).is_between(odds[outcome] - 0.012, odds[outcome] + 0.012)
		report.append("%s%s: %s" % [LoanApplication.risk_tier_label(tier), "" if documents_ok else " (unverified)", " / ".join(shares)])
	print("Loan outcomes (on time / late / default) over %d each: %s" % [count, "; ".join(report)])
	# Unverified documents are much worse than the tier alone.
	assert_float(LoanBookManager.odds_for(Tier.LOW, false)[2]).is_greater(LoanBookManager.odds_for(Tier.HIGH, true)[2])

## Fair lending: an outcome comes from the loan's own generator (career seed
## and loan number), and the odds from the risk and documents: the same loan
## under any other name turns out the same, and outcomes don't differ by name
## or look.
func test_outcomes_never_depend_on_the_borrower() -> void:
	var by_group := {}
	var names := LoanApplicantGenerator.FIRST_NAMES
	for i in 3000:
		LoanBookManager.next_loan_id = i + 1
		var first := LoanBookManager.book_loan("Kira Ibarra", "Auto", 10000.0, Tier.MEDIUM, true, true, "You")
		LoanBookManager.next_loan_id = i + 1
		var other := LoanBookManager.book_loan("%s Walsh" % names[i % names.size()], "Auto", 10000.0, Tier.MEDIUM, true, false, "Priya Anand")
		assert_int(other.outcome).is_equal(first.outcome)
		assert_int(other.resolve_day).is_equal(first.resolve_day)
		var group := i % 4
		var tally: Vector2 = by_group.get(group, Vector2.ZERO)
		by_group[group] = tally + Vector2(1.0 if first.outcome == Outcome.DEFAULT else 0.0, 1.0)
	# BookedLoan holds no look, and nothing about the borrower but a name.
	for property in BookedLoan.new().get_property_list():
		var property_name: String = property["name"]
		assert_str(property_name).is_not_equal("age")
		for forbidden: String in ["look", "birth", "sex", "gender", "race", "religio", "nation", "origin", "marital"]:
			assert_str(property_name).not_contains(forbidden)
	for group: int in by_group:
		var tally: Vector2 = by_group[group]
		assert_float(tally.x / tally.y).override_failure_message("group %d" % group).is_between(0.08 - 0.035, 0.08 + 0.035)

# --- the day's events ------------------------------------------------------------------

func test_events_reach_the_end_of_day_summary() -> void:
	XPManager.is_loan_officer_unlocked = true
	# No portfolio report in the way.
	LoanBookManager.period_first_day = 100
	fixed_loan("Maria Chen", Outcome.LATE)
	fixed_loan("Tom Whitfield", Outcome.DEFAULT, true, 100000.0, "Business")
	fixed_loan("Elena Petrova", Outcome.ON_TIME)
	fixed_loan("Kira Ibarra", Outcome.DEFAULT, false, 20000.0, "Auto", false)
	# Day 5: nothing yet.
	LoanBookManager.close_day(4)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_empty()
	# Day 5: Tom's payment 30 days late (and the staff's loan's, shown only to a
	# Branch Manager).
	LoanBookManager.close_day(5)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Tom Whitfield's business loan: payment 30 days late"])
	assert_array(Array(LoanBookManager.summary_lines(true))).is_equal(["Tom Whitfield's business loan: payment 30 days late (yours)", "Kira Ibarra's auto loan: payment 30 days late"])
	# Day 6: Maria's 15 days late.
	LoanBookManager.close_day(6)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Maria Chen's auto loan: payment 15 days late"])
	# Day 10: Maria caught up.
	LoanBookManager.close_day(10)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Maria Chen's auto loan: caught up on payments"])
	assert_float(LoanBookManager.stat(player_stats(), "late")).is_equal(1.0)
	# Day 11: Tom defaulted, $60,000 written off (60% of a business loan).
	LoanBookManager.close_day(11)
	assert_array(Array(LoanBookManager.summary_lines(false))).is_equal(["Tom Whitfield's business loan: defaulted — $60,000 written off"])
	assert_float(LoanBookManager.stat(player_stats(), "losses")).is_equal(60000.0)
	assert_float(LoanBookManager.stat(branch_stats(), "losses")).is_equal(60000.0 + 8000.0)
	assert_float(LoanBookManager.stat(branch_stats(), "defaulted_unverified")).is_equal(1.0)
	# Each day is processed once.
	LoanBookManager.close_day(11)
	assert_float(LoanBookManager.stat(player_stats(), "defaulted")).is_equal(1.0)
	# Elena paid on time through the settling period: settled quietly.
	LoanBookManager.close_day(21)
	assert_array(Array(LoanBookManager.summary_lines(true))).is_empty()
	assert_float(LoanBookManager.stat(player_stats(), "on_time")).is_equal(1.0)
	assert_bool(LoanBookManager.book.is_empty()).is_true()

## Through the room: the End of Day summary lists the day's loan events, at
## most MAX_EVENT_LINES and "… and N more", and still fits the window with a
## busy day's vault and after-cutoff lines.
func test_the_end_of_day_shows_loan_events_and_fits() -> void:
	XPManager.is_loan_officer_unlocked = true
	var today := BusinessDay.stats_day
	for i in 5:
		fixed_loan("Borrower %d" % i, Outcome.DEFAULT, true, 20000.0, "Auto", true, today - 4)
	# A busy day's cutoff list as well.
	for i in 9:
		BusinessDay.after_cutoff.append({"time": "2:%02d PM" % (10 + i), "type": "Deposit", "amount_cents": 50000, "account": "Customer %d" % i, "posting_day": today + 1})
	GameClock.minutes = 17 * 60.0 + 1.0
	room.show_end_of_day()
	var eod := room.end_of_day_screen
	assert_bool(eod.is_summary_shown()).is_true()
	var text := eod.summary_label.text
	assert_str(text).contains("Loans: Borrower 0's auto loan: payment 30 days late")
	assert_str(text).contains("… and 2 more")
	# With loans to show, the after-cutoff list keeps to 3 lines.
	assert_str(text).contains("… and %d more" % (9 - EndOfDayScreen.MAX_CUTOFF_LINES_WITH_LOANS))
	await frames(4)
	var problems := layout_problems(eod.summary_panel)
	problems.append_array(controls_line_problems(eod.summary_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

	# The busiest summary there can be: an armored truck line and a cash order
	# as well, and the vault out of range.
	var figures := BusinessDay.summary()
	var vault: Dictionary = VaultManager.last_close.duplicate()
	vault["truck"] = "Armored truck: 2 of 3 bags accepted; 1 refused and rescheduled."
	vault["order"] = {"placed_day": today, "delivery_day": today + 1, "cents": 3000000}
	vault["in_range"] = false
	vault["atm_restock"] = VaultManager.ATM_RESTOCK_CENTS
	figures["vault"] = vault
	figures["loans"] = LoanBookManager.summary_lines(true)
	eod.show_summary(figures)
	await frames(4)
	problems = layout_problems(eod.summary_panel)
	problems.append_array(controls_line_problems(eod.summary_panel))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- turned-away business --------------------------------------------------------------------

func test_good_applicants_turned_away_are_counted() -> void:
	clock_in_at_loan_desk()
	# A good applicant (low risk, documents fine) rejected: lost business.
	decide(sample("Maria Chen"), LoanApplication.DecisionType.REJECT, [LoanApplication.DenialReason.TOTAL_DTI])
	assert_float(LoanBookManager.stat(player_stats(), "good_seen")).is_equal(1.0)
	assert_float(LoanBookManager.stat(player_stats(), "turned_away")).is_equal(1.0)
	assert_float(LoanBookManager.stat(player_stats(), "turned_away_amount")).is_equal(15000.0)
	# A good applicant approved: seen, not turned away.
	decide(sample("David Okafor"), LoanApplication.DecisionType.APPROVE)
	assert_float(LoanBookManager.stat(player_stats(), "good_seen")).is_equal(2.0)
	assert_float(LoanBookManager.stat(player_stats(), "turned_away")).is_equal(1.0)
	# Not good applicants: a risky one, and a safe one whose documents didn't
	# check out.
	decide(sample("Marcus Webb"), LoanApplication.DecisionType.REJECT, [LoanApplication.DenialReason.TOTAL_DTI])
	var unverified := sample("Elena Petrova")
	unverified.doc_problem = LoanApplication.DocProblem.MISSING_STUB
	decide(unverified, LoanApplication.DecisionType.REJECT, [LoanApplication.DenialReason.UNVERIFIED])
	assert_float(LoanBookManager.stat(player_stats(), "good_seen")).is_equal(2.0)
	assert_float(LoanBookManager.stat(player_stats(), "turned_away")).is_equal(1.0)
	# A staff officer turning one away counts for the branch.
	var worker := room.loan_desk_worker
	worker.staff_npc.staff.skill = 0
	var turned_before := LoanBookManager.stat(branch_stats(), "turned_away")
	for i in 30:
		var safe := sample("Maria Chen")
		safe.applicant_name = "Safe %d" % i
		worker.decide_next(safe)
	assert_float(LoanBookManager.stat(branch_stats(), "turned_away")).is_greater(turned_before)
	assert_float(LoanBookManager.stat(player_stats(), "turned_away")).is_equal(1.0)

# --- the rating and report ------------------------------------------------------------------

## The rating's parts and bands: a careful lender, one unlucky default, a
## lender who approves everything, one who turns good applicants away.
func test_the_lending_quality_rating() -> void:
	# Careful: 20 settled, 1 default (5%), $8,000 lost of $400,000; every good
	# applicant served.
	var careful := LoanBookManager.rate(stats_of({"on_time": 17, "late": 2, "defaulted": 1, "losses": 8000, "settled_amount": 400000, "good_seen": 12}))
	assert_bool(careful["rated"]).is_true()
	assert_float(careful["score"]).is_equal(100.0)
	assert_int(band_of(careful)).is_equal(LoanBookManager.Band.STRONG)
	# A small book with one unlucky default is measured against 10 loans.
	var unlucky := LoanBookManager.rate(stats_of({"on_time": 5, "defaulted": 1, "losses": 8000, "settled_amount": 120000, "good_seen": 4}))
	assert_int(band_of(unlucky)).is_equal(LoanBookManager.Band.STRONG)
	# Approving everything: 20% defaults (29.4), 10% lost (25), nobody
	# turned away (100). The average would be 51.5, but the score is capped at
	# the weakest part + 10: 35, Poor.
	var lenient := LoanBookManager.rate(stats_of({"on_time": 14, "late": 2, "defaulted": 4, "losses": 40000, "settled_amount": 400000, "good_seen": 8}))
	assert_float(lenient["losses"]).is_equal_approx(25.0, 0.001)
	assert_float(score_of(lenient)).is_equal_approx(25.0 + LoanBookManager.WEAKEST_PART_MARGIN, 0.001)
	assert_int(band_of(lenient)).is_equal(LoanBookManager.Band.POOR)
	# Mostly sensible, a few mistakes: 2 defaults in 20 (88.2), 5% lost
	# (87.5), 1 of 10 good applicants turned away (66.7): the average 80.8,
	# capped at 76.7, Sound.
	var sensible := LoanBookManager.rate(stats_of({"on_time": 16, "late": 2, "defaulted": 2, "losses": 20000, "settled_amount": 400000, "good_seen": 10, "turned_away": 1}))
	assert_float(score_of(sensible)).is_equal_approx(100.0 * 2.0 / 3.0 + LoanBookManager.WEAKEST_PART_MARGIN, 0.001)
	assert_int(band_of(sensible)).is_equal(LoanBookManager.Band.SOUND)
	# Turning every good applicant away, lending nothing: only that is rated.
	var strict := LoanBookManager.rate(stats_of({"good_seen": 8, "turned_away": 8}))
	assert_float(strict["defaults"]).is_equal(-1.0)
	assert_float(strict["score"]).is_equal(0.0)
	# Rejecting everything with some loans still settling from before: the
	# turned-away part (0) caps it at 10 whatever the rest.
	var strict_with_book := LoanBookManager.rate(stats_of({"on_time": 10, "settled_amount": 200000, "good_seen": 8, "turned_away": 8}))
	assert_float(score_of(strict_with_book)).is_equal_approx(LoanBookManager.WEAKEST_PART_MARGIN, 0.001)
	assert_int(band_of(strict_with_book)).is_equal(LoanBookManager.Band.POOR)
	assert_int(band_of(strict)).is_equal(LoanBookManager.Band.POOR)
	# Nothing at all: not rated.
	assert_bool(LoanBookManager.rate(stats_of({}))["rated"]).is_false()

func test_the_portfolio_report_for_a_loan_officer() -> void:
	XPManager.is_loan_officer_unlocked = true
	var player := player_stats()
	for pair: Array in [["made", 9], ["lent", 210000], ["on_time", 6], ["late", 1], ["defaulted", 2], ["defaulted_unverified", 1], ["losses", 18000], ["settled_amount", 190000], ["good_seen", 6], ["turned_away", 2], ["turned_away_amount", 45000]]:
		player[pair[0]] = pair[1] * 1.0
	# The staff's work doesn't count in a Loan Officer's report.
	branch_stats()["made"] = 40.0
	var start := totals()
	LoanBookManager.close_day(LoanBookManager.period_last_day())
	assert_bool(room.letter_screen.visible).is_true()
	assert_str(room.letter_screen.title_label.text).is_equal("Loan Portfolio Report — Days 1-20")
	var body := room.letter_screen.body_label.text
	for line: String in [
		"This report covers the loans you decided over the last 20 business days (Days 1-20).",
		"Loans made: 9 ($210,000 lent)",
		"Settled: 6 paid on time · 1 ran late, then caught up · 2 defaulted",
		"Losses: $18,000 written off",
		"Good applicants turned away: 2 of 6 ($45,000 of sound lending)",
		"Too lenient: 2 loans defaulted, writing off $18,000.",
		"1 of the defaults was on documents that didn't check out.",
		"Too strict: 2 good applicants were turned away, $45,000 of sound lending lost to other banks.",
		"Both count:",
	]:
		assert_str(body).contains(line)
	# 2 defaults of 10 (20%) -> 29; losses 18,000 / 190,000 x 9/10 (8.5%) -> 44;
	# 2 turned away of 6 (33%) -> 0: 24, Poor.
	var rating: Dictionary = LoanBookManager.rate(stats_of({"on_time": 6, "late": 1, "defaulted": 2, "losses": 18000, "settled_amount": 190000, "good_seen": 6, "turned_away": 2}))
	assert_int(band_of(rating)).is_equal(LoanBookManager.Band.POOR)
	assert_str(body).contains("Lending quality: Poor (%d/100)" % roundi(score_of(rating)))
	assert_str(body).contains("Result: -8 Score, -3 Reputation.")
	assert_vector(totals() - start).is_equal(Vector3i(-8, -3, 0))
	# A new period, with nothing carried over.
	assert_int(LoanBookManager.period_first_day).is_equal(21)
	assert_float(LoanBookManager.stat(player_stats(), "made")).is_equal(0.0)
	assert_float(LoanBookManager.stat(branch_stats(), "made")).is_equal(0.0)
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.description).contains("Loan Portfolio Report, Days 1-20: Poor")
	assert_bool(record.reviewed).is_true()
	await frames(4)
	var problems := layout_problems(room.letter_screen.letter_panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

## Each band's consequences; a Branch Manager's report covers the whole
## branch; a Teller gets no report (the period still starts over).
func test_report_consequences_and_scope() -> void:
	var cases := [
		[{"on_time": 19, "late": 1, "settled_amount": 400000, "good_seen": 10}, LoanBookManager.Band.STRONG, 10, 2],
		[{"on_time": 16, "late": 2, "defaulted": 2, "losses": 20000, "settled_amount": 400000, "good_seen": 10, "turned_away": 1}, LoanBookManager.Band.SOUND, 3, 0],
		[{"on_time": 15, "defaulted": 3, "losses": 20000, "settled_amount": 400000, "good_seen": 10}, LoanBookManager.Band.WEAK, -3, -1],
		[{"good_seen": 10, "turned_away": 5}, LoanBookManager.Band.POOR, -8, -3],
	]
	XPManager.is_loan_officer_unlocked = true
	for entry: Array in cases:
		var values: Dictionary = entry[0]
		LoanBookManager.period_stats[LoanBookManager.PLAYER] = stats_of(values)
		var start := totals()
		var result := LoanBookManager.run_report(LoanBookManager.period_last_day())
		assert_int(result["band"]).override_failure_message(str(values)).is_equal(entry[1])
		var score: int = entry[2]
		var reputation: int = entry[3]
		assert_vector(totals() - start).is_equal(Vector3i(score, reputation, maxi(0, score) * XPManager.XP_PER_SCORE_POINT))
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()

	# A Branch Manager's covers the branch (staff loans included).
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	LoanBookManager.period_stats[LoanBookManager.BRANCH] = stats_of({"made": 60, "on_time": 50, "settled_amount": 900000, "good_seen": 30})
	var branch := LoanBookManager.run_report(LoanBookManager.period_last_day())
	assert_str(branch["scope"]).is_equal(LoanBookManager.BRANCH)
	assert_str(LoanBookManager.report_body(branch)).contains("the branch's loans (yours and your staff's)")
	assert_str(LoanBookManager.report_body(branch)).contains("Loans made: 60")

	# Nothing to rate: a letter, no change.
	XPManager.demote_branch_manager()
	var empty := LoanBookManager.run_report(LoanBookManager.period_last_day())
	assert_str(LoanBookManager.report_body(empty)).contains("Nothing to rate this period, so no change to your record.")

	# A Teller gets none.
	CareerReset.reset_all()
	OnboardingManager.skip()
	var none := LoanBookManager.run_report(LoanBookManager.period_last_day())
	assert_dict(none).is_empty()
	assert_int(LoanBookManager.period_first_day).is_equal(21)

# --- the Regional review ---------------------------------------------------------------------

func test_lending_quality_in_the_regional_review() -> void:
	var weights := RegionalManager.AREA_WEIGHTS
	var total := 0
	for key: String in weights:
		total += weights[key]
	assert_int(total).is_equal(100)
	assert_dict(weights).is_equal({
		RegionalManager.AREA_VAULT: 15, RegionalManager.AREA_IGNORED: 15, RegionalManager.AREA_UNFAIR: 15,
		RegionalManager.AREA_EXCUSED: 10, RegionalManager.AREA_MISTAKES: 5, RegionalManager.AREA_ABANDONED: 5,
		RegionalManager.AREA_VACANCY: 5, RegionalManager.AREA_HIRING: 5, RegionalManager.AREA_CASH: 15,
		RegionalManager.AREA_LENDING: 10,
	})
	# Not collected before promotion.
	LoanBookManager.book_loan("Kira Ibarra", "Auto", 10000.0, Tier.LOW, true, false, "Priya Anand")
	assert_dict(RegionalManager.lending).is_empty()
	XPManager._grant_branch_manager()
	while room.letter_screen.visible:
		room.letter_screen.action_button.pressed.emit()
	var area := _lending(RegionalManager.evaluate())
	assert_bool(area["rated"]).is_false()
	# The branch's loans settle in the window: one default in ten, a good
	# applicant turned away by staff.
	for i in 9:
		fixed_loan("On Time %d" % i, Outcome.ON_TIME, false, 20000.0, "Auto", true, BusinessDay.stats_day - LoanBookManager.SETTLE_DAYS)
	fixed_loan("Defaulter", Outcome.DEFAULT, false, 20000.0, "Auto", true, BusinessDay.stats_day - 10)
	LoanBookManager.close_day(BusinessDay.stats_day)
	RegionalManager.note_lending("good_seen", 5.0)
	RegionalManager.note_lending("turned_away", 1.0)
	area = _lending(RegionalManager.evaluate())
	assert_bool(area["rated"]).is_true()
	assert_float(score_of(area)).is_equal_approx(score_of(LoanBookManager.rate(RegionalManager.lending)), 0.001)
	assert_str(area["detail"]).is_equal("10 loans settled, 1 defaulted ($8,000 written off); 1 of 5 good applicants turned away.")
	assert_str(area["comment"]).contains("good applicants were turned away")
	assert_int(area["weight"]).is_equal(10)
	# In the letter.
	var result := RegionalManager.evaluate()
	result["first_day"] = 1
	result["last_day"] = 5
	result["score_change"] = 0
	result["reputation_change"] = 0
	result["warnings_before"] = 0
	result["warnings"] = 0
	assert_str(RegionalManager.review_body(result)).contains("Lending quality — %d/100 (weight 10%%)" % roundi(score_of(area)))

func _lending(result: Dictionary) -> Dictionary:
	var areas: Array = result["areas"]
	for entry: Variant in areas:
		var area: Dictionary = entry
		if area["key"] == RegionalManager.AREA_LENDING:
			return area
	return {}

# --- save, load and reset -------------------------------------------------------------------

func test_the_book_and_pending_outcomes_survive_save_and_load() -> void:
	XPManager.is_loan_officer_unlocked = true
	fixed_loan("Maria Chen", Outcome.LATE)
	fixed_loan("Tom Whitfield", Outcome.DEFAULT, true, 100000.0, "Business")
	fixed_loan("Kira Ibarra", Outcome.ON_TIME, false, 30000.0, "Home", false)
	LoanBookManager.close_day(5)
	LoanBookManager.period_first_day = 3
	var saved := LoanBookManager.save_data()
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_bool(LoanBookManager.book.is_empty()).is_true()
	assert_int(LoanBookManager.next_loan_id).is_equal(1)
	SaveGame.restore(SaveGame.read().career)
	assert_dict(LoanBookManager.save_data()).is_equal(saved)
	assert_int(LoanBookManager.book.size()).is_equal(3)
	var tom := LoanBookManager.book[1]
	assert_str(tom.borrower).is_equal("Tom Whitfield")
	assert_int(tom.stage).is_equal(BookedLoan.Stage.LATE_REPORTED)
	assert_float(tom.loss).is_equal(60000.0)
	assert_bool(LoanBookManager.book[2].documents_ok).is_false()
	# The rest of the story plays out the same after loading.
	LoanBookManager.close_day(11)
	assert_float(LoanBookManager.stat(player_stats(), "defaulted")).is_equal(1.0)
	assert_float(LoanBookManager.stat(player_stats(), "late")).is_equal(1.0)

## A save from before the loan book: an empty book, its first period from
## the loaded day.
func test_an_older_save_starts_an_empty_book() -> void:
	SaveGame.restore({"clock": {"day": 12}, "business_day": {"stats_day": 12}})
	assert_bool(LoanBookManager.book.is_empty()).is_true()
	assert_int(LoanBookManager.period_first_day).is_equal(BusinessDay.stats_day)
