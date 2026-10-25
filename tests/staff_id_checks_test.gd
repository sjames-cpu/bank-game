extends "res://tests/support/teller_room_suite.gd"

## ID checks (KYC) at the staff windows: staff-line customers carry IDs from
## the same KycPolicy rate and mix; staff skip the check (reliability) or
## miss a bad ID (skill) at the StaffMember formulas' rates, otherwise check
## and refuse a bad ID, saying why; each slip's severity in staff review,
## correct refusals kept out of the queue, the Branch summary's counts, the
## Regional mistake rate, the review screen (with the card) fitting the
## window, and hiring candidates' stats predicting their ID behaviour.

const Check := KycPolicy.StaffCheck
const Problem := IdCard.Problem
const Severity := StaffReviewItem.Severity
const Action := StaffReviewManager.Action

var line: NpcCustomerLine
var window_before: Vector2i

func before_test() -> void:
	await super()
	window_before = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	line = room.get_node("Window1NpcLine")
	line.spawn_timer.stop()

func after_test() -> void:
	get_tree().root.size = window_before
	await super()

# --- helpers -------------------------------------------------------------------

func staff() -> StaffMember:
	return line.staff_npc.staff

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()
	XPManager.has_seen_branch_orientation = true

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## A staff-line customer withdrawing $100 with an ID showing `problem`, at
## the front of the line.
func customer_with(problem: Problem, withdrawal: bool = true) -> CustomerNPC:
	line._spawn_customer()
	var customer: CustomerNPC = line.queue[-1]
	customer.opens_account = false
	customer.intent_type = ShiftTransaction.Type.WITHDRAWAL if withdrawal else ShiftTransaction.Type.DEPOSIT
	customer.intent_amount_cents = 10000
	customer.id_card = KycPolicy.issue_card(line.kyc_rng, customer.display_name, customer.look_index, GameClock.today_date(), problem, CustomerNPC.CUSTOMER_FRAME_SETS.size())
	return customer

## One whole service of `customer` (no transaction mistake), returning what
## the staff member did about the ID.
func serve(customer: CustomerNPC, skip: int = -1) -> Check:
	line._start_service(customer)
	line._mistake_pending = false
	if skip >= 0:
		line._id_skipped = skip == 1
	line._complete_service()
	var check := line.current_id_check()
	if is_instance_valid(customer):
		customer.queue_free()
	return check

## Serves `problem` IDs until the staff member's outcome is `wanted` (the
## line's generator is seeded, so this is the same every run).
func serve_until(problem: Problem, wanted: Check, skip: int = -1) -> CustomerNPC:
	for attempt in 200:
		var customer := customer_with(problem)
		line._start_service(customer)
		line._mistake_pending = false
		if skip >= 0:
			line._id_skipped = skip == 1
		line._complete_service()
		if line.current_id_check() == wanted:
			return customer
	assert_bool(false).override_failure_message("never got %s" % Check.keys()[wanted]).is_true()
	return null

func real_rates() -> void:
	line.id_problem_chance = KycPolicy.ID_PROBLEM_CHANCE
	line.account_opening_chance = KycPolicy.ACCOUNT_OPENING_CHANCE
	line.staff_id_slips = true

# --- IDs at the staff windows ----------------------------------------------------------

func test_staff_line_customers_carry_ids_at_the_policy_rate() -> void:
	real_rates()
	var counts := {}
	var openers := 0
	var total := 1400
	for i in total:
		# Every name new to the bank, so anyone may come to open an account.
		AccountManager.reset()
		line._spawn_customer()
		var customer: CustomerNPC = line.queue.pop_back()
		assert_object(customer.id_card).is_not_null()
		var problem := customer.id_card.problem
		counts[problem] = counts.get(problem, 0) + 1
		if customer.opens_account:
			openers += 1
			# Someone new: no account yet, and a name nobody banks under at the
			# staff windows.
			assert_object(customer.account).is_null()
			assert_object(AccountManager.find_account_by_name(customer.display_name, true)).is_null()
		customer.free()
	var valid_count: int = counts.get(Problem.NONE, 0)
	var bad := total - valid_count
	assert_float(float(bad) / total).is_equal_approx(KycPolicy.ID_PROBLEM_CHANCE, 0.03)
	# The mix follows PROBLEM_WEIGHTS (3:2:2:1).
	var weight_total := 8.0
	for problem: Problem in KycPolicy.PROBLEM_WEIGHTS:
		var problem_count: int = counts.get(problem, 0)
		var share := float(problem_count) / bad
		var expected: float = KycPolicy.PROBLEM_WEIGHTS[problem] / weight_total
		assert_float(share).override_failure_message("%s: %.3f" % [Problem.keys()[problem], share]).is_equal_approx(expected, 0.08)
	assert_float(float(openers) / total).is_equal_approx(KycPolicy.ACCOUNT_OPENING_CHANCE, 0.03)

func test_withdrawals_and_new_accounts_need_id_and_deposits_dont() -> void:
	var depositor := customer_with(Problem.EXPIRED, false)
	assert_int(serve(depositor)).is_equal(Check.NOT_NEEDED)
	assert_int(serve(customer_with(Problem.NONE))).is_equal(Check.CHECKED)
	# A new account: the ID is checked, the account opened in their name.
	line.account_opening_chance = 1.0
	line._spawn_customer()
	var opener: CustomerNPC = line.queue[-1]
	assert_bool(opener.opens_account).is_true()
	opener.id_card = KycPolicy.issue_card(line.kyc_rng, opener.display_name, opener.look_index, GameClock.today_date(), Problem.NONE, CustomerNPC.CUSTOMER_FRAME_SETS.size())
	var opener_name := opener.display_name
	var amount := opener.intent_amount_cents
	assert_int(serve(opener)).is_equal(Check.CHECKED)
	var account := AccountManager.find_account_by_name(opener_name, true)
	assert_object(account).is_not_null()
	assert_int(account.balance_cents).is_equal(amount)
	assert_bool(account.is_staff_line_account).is_true()
	assert_str(HistoryManager.records[-1].description).contains("opened an account for %s" % opener_name)

# --- the formulas ------------------------------------------------------------------

func test_the_skip_and_miss_formulas() -> void:
	var member := StaffMember.new()
	for case: Array in [[10, 0.01], [9, 0.0148], [7, 0.0533], [5, 0.1304], [3, 0.2460], [1, 0.40]]:
		var expected: float = case[1]
		member.reliability = case[0]
		assert_float(member.id_skip_chance()).override_failure_message("reliability %d" % case[0]).is_equal_approx(expected, 0.0005)
	for case: Array in [[10, 0.02], [9, 0.0272], [7, 0.0844], [5, 0.1990], [3, 0.3709], [1, 0.60]]:
		var expected: float = case[1]
		member.skill = case[0]
		assert_float(member.id_miss_chance()).override_failure_message("skill %d" % case[0]).is_equal_approx(expected, 0.0005)

func test_skip_and_miss_rates_follow_the_formulas_over_many_services() -> void:
	line.staff_id_slips = true
	# Derek Voss: reliability 3 (skips about 25%), skill 9 (misses about 3%).
	assert_str(staff().staff_name).is_equal("Derek Voss")
	var services := 1200
	var skipped := 0
	for i in services:
		if serve(customer_with(Problem.NONE)) == Check.SKIPPED:
			skipped += 1
	assert_float(float(skipped) / services).is_equal_approx(staff().id_skip_chance(), 0.035)

	# Misses, measured where the check wasn't skipped, for a weak and a strong
	# eye (skill 3 and 9).
	for skill: int in [3, 9]:
		staff().skill = skill
		var checked := 0
		var missed := 0
		var caught := 0
		for i in services:
			var outcome := serve(customer_with(Problem.EXPIRED), 0)
			checked += 1
			if outcome == Check.MISSED:
				missed += 1
			elif outcome == Check.CAUGHT:
				caught += 1
		assert_int(missed + caught).is_equal(checked)
		assert_float(float(missed) / checked).override_failure_message("skill %d" % skill).is_equal_approx(staff().id_miss_chance(), 0.035)

	# Having no ID at all is never missed once they ask.
	staff().skill = 1
	for i in 50:
		assert_int(serve(customer_with(Problem.NO_ID), 0)).is_equal(Check.CAUGHT)

# --- on the floor -----------------------------------------------------------------

func test_a_bad_id_is_refused_on_the_floor_and_the_customer_leaves_unserved() -> void:
	promote()
	var customer := customer_with(Problem.EXPIRED)
	var balance := customer.account.balance_cents
	var refused := []
	line.customer_refused.connect(func(c: CustomerNPC, _s: StaffMember) -> void: refused.append(c))
	var served_before := BusinessDay.customers_served_by_staff
	line._start_service(customer)
	line._mistake_pending = false
	var seconds := line._service_seconds
	var staff_speech: Label = line.staff_npc.get_node("SpeechLabel")
	assert_str(staff_speech.text).is_equal("Hi! How can I help?")
	assert_str(customer._farewell_label.text).is_equal("Withdraw $100, please.")
	# A third of the way in, they ask for ID.
	line._process(seconds * 0.35)
	assert_str(staff_speech.text).is_equal(KycPolicy.STAFF_ASK_LINE)
	assert_str(customer._farewell_label.text).is_equal(KycPolicy.CUSTOMER_SHOWS_ID_LINE)
	# Then refuse, saying why; the customer leaves without being served.
	line._process(seconds * 0.3)
	assert_int(line.current_id_check()).is_equal(Check.CAUGHT)
	assert_str(staff_speech.text).is_equal("Sorry, this ID has expired.")
	assert_str(customer._farewell_label.text).is_equal(KycPolicy.REFUSED_FAREWELL)
	assert_bool(line.is_serving()).is_false()
	assert_bool(line.queue.has(customer)).is_false()
	assert_array(refused).is_equal([customer])
	assert_int(customer.account.balance_cents).is_equal(balance)
	assert_int(BusinessDay.customers_served_by_staff).is_equal(served_before)
	# Correct work: logged as such, never queued.
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.grade_label).is_equal("Correct")
	assert_int(record.staff_id_check).is_equal(Check.CAUGHT)
	assert_str(record.description).is_equal("Derek Voss (Teller Window 1) refused %s's $100 withdrawal: the ID had expired" % customer.display_name)
	assert_int(StaffReviewManager.queue.size()).is_equal(0)

func test_each_refusal_says_whats_wrong() -> void:
	assert_str(KycPolicy.staff_refusal_line(Problem.EXPIRED)).is_equal("Sorry, this ID has expired.")
	assert_str(KycPolicy.staff_refusal_line(Problem.NAME_MISMATCH)).is_equal("Sorry, the name on this ID doesn't match.")
	assert_str(KycPolicy.staff_refusal_line(Problem.WRONG_PORTRAIT)).is_equal("Sorry, this isn't your photo.")
	assert_str(KycPolicy.staff_refusal_line(Problem.NO_ID)).is_equal("Sorry, I need a photo ID for this.")
	# No ID at all: the customer says so when asked.
	var customer := customer_with(Problem.NO_ID)
	line._start_service(customer)
	line._process(line._service_seconds * 0.35)
	assert_str(customer._farewell_label.text).is_equal(KycPolicy.CUSTOMER_NO_ID_LINE)

# --- staff review ------------------------------------------------------------------

func test_each_staff_outcome_has_its_severity_in_review() -> void:
	promote()
	line.staff_id_slips = true
	var missed := serve_until(Problem.NAME_MISMATCH, Check.MISSED, 0)
	var item: StaffReviewItem = StaffReviewManager.queue[-1]
	assert_int(item.kind).is_equal(StaffReviewItem.Kind.ID_CHECK)
	assert_int(item.id_check).is_equal(Check.MISSED)
	assert_int(item.severity).is_equal(Severity.SERIOUS)
	assert_str(item.customer_name).is_equal(missed.display_name)

	serve(customer_with(Problem.EXPIRED), 1)
	assert_int(StaffReviewManager.queue[-1].id_check).is_equal(Check.SKIPPED_BAD)
	assert_int(StaffReviewManager.queue[-1].severity).is_equal(Severity.SERIOUS)

	serve(customer_with(Problem.NONE), 1)
	var skipped: StaffReviewItem = StaffReviewManager.queue[-1]
	assert_int(skipped.id_check).is_equal(Check.SKIPPED)
	assert_int(skipped.severity).is_equal(Severity.MINOR)
	assert_int(StaffReviewManager.queue.size()).is_equal(3)

	# Correct work stays out: a valid ID checked, a bad one refused.
	line.staff_id_slips = false
	serve(customer_with(Problem.NONE), 0)
	serve(customer_with(Problem.WRONG_PORTRAIT), 0)
	assert_int(StaffReviewManager.queue.size()).is_equal(3)

	# The usual rules: report the serious ones, feedback for the skip, and a
	# skip by someone with two feedbacks already is a repeated minor.
	assert_bool(StaffReviewManager.decide(item, Action.REPORT)["fair"]).is_true()
	assert_bool(StaffReviewManager.decide(skipped, Action.FEEDBACK)["fair"]).is_true()
	StaffReviewManager.staff_feedbacks["Derek Voss"] = StaffReviewManager.FEEDBACKS_BEFORE_REPEAT
	serve(customer_with(Problem.NONE), 1)
	var repeat: StaffReviewItem = StaffReviewManager.queue[-1]
	assert_int(StaffReviewManager.effective_severity(repeat)).is_equal(Severity.REPEATED_MINOR)
	var result := StaffReviewManager.decide(repeat, Action.FEEDBACK)
	assert_bool(result["fair"]).is_false()
	assert_str(result["explanation"]).contains("it was time for a report")

func test_before_promotion_slips_are_logged_but_not_queued() -> void:
	serve(customer_with(Problem.EXPIRED), 1)
	assert_int(StaffReviewManager.queue.size()).is_equal(0)
	var record: DecisionRecord = HistoryManager.records[-1]
	assert_str(record.grade_label).is_equal("Mistake")
	assert_int(record.staff_id_check).is_equal(Check.SKIPPED_BAD)
	assert_str(record.description).ends_with("— didn't check ID (the ID had expired)")

func test_the_review_item_shows_the_card_the_request_and_what_they_did() -> void:
	promote()
	var customer := customer_with(Problem.EXPIRED)
	var card := customer.id_card
	serve(customer, 1)
	var item: StaffReviewItem = StaffReviewManager.queue[-1]
	var details := StaffReviewScreen.details_text(item)
	assert_str(details).is_equal("Customer %s asked to withdraw $100 (served %s).\nID: %s · No. %s · born %s · expires %s\nThe staff member served them without checking ID." % [
		item.customer_name, IdCard.date_text(GameClock.today_date()), card.holder_name, card.id_number, IdCard.date_text(card.date_of_birth), IdCard.date_text(card.expiry_date)])
	# What was wrong stays hidden until the manager decides.
	for hidden: String in ["expired", "Serious", "Minor", "valid"]:
		assert_str(details).not_contains(hidden)

	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()
	var screen := bm.staff_review_screen
	screen.show_screen()
	assert_bool(screen.id_hbox.visible).is_true()
	assert_object(screen.customer_portrait.texture).is_same(CustomerNPC.portrait_of(item.customer_look))
	assert_object(screen.card_portrait.texture).is_same(CustomerNPC.portrait_of(card.portrait_look))
	await frames(4)
	var problems := layout_problems(screen.get_node("Panel") as Control)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
	screen.report_button.pressed.emit()
	assert_str(screen.result_label.text).contains("serving without checking an ID that had expired is a serious error")
	assert_str(screen.result_label.text).ends_with("The ID had expired.")
	# No ID shown: the card says so.
	serve(customer_with(Problem.NO_ID), 1)
	screen._refresh()
	assert_str(StaffReviewScreen.details_text(StaffReviewManager.queue[-1])).contains("\nNo ID shown.\n")
	assert_bool(screen.card_portrait.visible).is_false()
	await frames(4)
	problems = layout_problems(screen.get_node("Panel") as Control)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

# --- the Branch summary and the Regional review -----------------------------------------

func test_the_branch_summary_counts_each_staff_members_id_checks() -> void:
	var records: Array[DecisionRecord] = []
	for entry: Array in [
		[Check.CHECKED, "Correct"], [Check.CHECKED, "Correct"], [Check.CAUGHT, "Correct"],
		[Check.SKIPPED, "Mistake"], [Check.SKIPPED_BAD, "Mistake"], [Check.MISSED, "Mistake"],
		[Check.NOT_NEEDED, "Correct"],
	]:
		var label: String = entry[1]
		var check: Check = entry[0]
		records.append(HistoryManager.add_staff_record("Derek Voss", ScheduleManager.SLOT_TELLER_WINDOW_1, "work", label, check))
	records.append(HistoryManager.add_staff_record("Walter Higgins", ScheduleManager.SLOT_TELLER_WINDOW_2, "deposit", "Correct"))
	assert_dict(BranchManagerScreen.id_check_counts(records.slice(0, 7))).is_equal({"needed": 6, "checked": 4, "caught": 1, "skipped": 2, "missed": 2})
	var summary := BranchManagerScreen.branch_summary_text(records)
	# Seven records, one a refusal: six served.
	assert_str(summary).contains("Teller Window 1 — Derek Voss: 6 served, 3 mistakes\nIDs: 4 checked, 1 caught, 2 skipped, 2 missed")
	# Nobody needing ID: no ID line.
	assert_str(summary).contains("Teller Window 2 — Walter Higgins: 1 served, 0 mistakes\n")
	assert_str(summary).contains("Total: 7 customers served by staff, 3 teller mistakes")

	# The shift summary with ID lines at every window still fits.
	promote()
	var bm := room.branch_manager_screen
	bm.show_screen()
	bm.clock_in_button.pressed.emit()
	acknowledge_letters()
	for slot_name: String in [ScheduleManager.SLOT_TELLER_WINDOW_1, ScheduleManager.SLOT_TELLER_WINDOW_2, ScheduleManager.SLOT_TELLER_WINDOW_3]:
		var member := ScheduleManager.get_assigned(slot_name)
		for check: Check in [Check.CHECKED, Check.CAUGHT, Check.SKIPPED, Check.MISSED]:
			HistoryManager.add_staff_record(member.staff_name, slot_name, "work", "Correct", check)
	for slot_name in ScheduleManager.LOAN_DESK_SLOTS:
		HistoryManager.add_staff_record(ScheduleManager.get_assigned(slot_name).staff_name, slot_name, "loan", "Correct")
	bm._prepare_shift_summary()
	assert_str(bm.shift_branch_label.text).contains("IDs: 3 checked, 1 caught, 1 skipped, 1 missed")
	var summary_panel: Control = bm.get_node("ShiftSummaryPanel")
	(bm.get_node("Panel") as Control).visible = false
	summary_panel.visible = true
	await frames(4)
	var problems := layout_problems(summary_panel)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()

func test_the_regional_mistake_rate_includes_id_slips() -> void:
	promote()
	assert_bool(RegionalManager.is_collecting()).is_true()
	var work := RegionalManager.staff_work
	var mistakes := RegionalManager.staff_mistakes
	serve(customer_with(Problem.NONE), 1) # skipped: a slip
	serve(customer_with(Problem.EXPIRED), 1) # served on a bad ID: a slip
	serve(customer_with(Problem.EXPIRED), 0) # refused: correct work
	serve(customer_with(Problem.NONE), 0) # checked: correct work
	assert_int(RegionalManager.staff_work - work).is_equal(4)
	assert_int(RegionalManager.staff_mistakes - mistakes).is_equal(2)
	for i in 6:
		serve(customer_with(Problem.NONE), 0)
	var areas: Array = RegionalManager.evaluate()["areas"]
	var mistakes_area: Dictionary = areas.filter(func(entry: Dictionary) -> bool: return entry["key"] == RegionalManager.AREA_MISTAKES)[0]
	assert_bool(mistakes_area["rated"]).is_true()
	assert_str(mistakes_area["detail"]).is_equal("2 mistakes in 10 pieces of staff work (20%).")

# --- hiring ------------------------------------------------------------------------

## No new mechanics: a teller candidate's weakness is reliability (and so
## skipped checks), and the red-flag answers come only from reliability 2 or
## lower, so they predict the worst skippers.
func test_teller_candidates_stats_predict_their_id_checks() -> void:
	for attempt in 20:
		var candidates := HiringManager.generate_candidates("Teller")
		var by_rating := candidates.duplicate()
		by_rating.sort_custom(func(a: StaffCandidate, b: StaffCandidate) -> bool: return a.rating() > b.rating())
		var strong_candidate: StaffCandidate = by_rating[0]
		var strong := strong_candidate.to_staff_member()
		var weak_candidate: StaffCandidate = by_rating[2]
		var weak := weak_candidate.to_staff_member()
		assert_float(strong.id_skip_chance()).is_less_equal(0.06)
		assert_float(strong.id_miss_chance()).is_less_equal(0.09)
		assert_float(weak.id_skip_chance()).is_greater_equal(0.31)
		for candidate: StaffCandidate in candidates:
			if candidate.red_flag_answer() != null:
				assert_int(candidate.reliability).is_less_equal(HiringManager.RED_FLAG_RELIABILITY)
				assert_float(candidate.to_staff_member().id_skip_chance()).is_greater_equal(0.31)
