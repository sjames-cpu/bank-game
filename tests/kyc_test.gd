extends "res://tests/support/teller_room_suite.gd"

## ID checks at the Player Teller Window (KycPolicy, TellerScreen): every
## player-line customer carries an ID, about 1 in 7 with a problem; ID is
## required for withdrawals and new accounts only; each grading row; account
## opening end to end; the shift summary's ID line; the panels fit the
## window.

const Problem := IdCard.Problem
const BAD_PROBLEMS: Array[IdCard.Problem] = [Problem.EXPIRED, Problem.NAME_MISMATCH, Problem.WRONG_PORTRAIT, Problem.NO_ID]

func before_test() -> void:
	await super()
	# Hints would sit over the screens; they have tests of their own.
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

## Spawns `count` player-line customers with the real chances and returns
## them as read, freeing each (the line has only 3 spots). `fresh_accounts`
## clears the accounts first each time, so every name is new to the bank.
func sample_customers(count: int, fresh_accounts: bool = false) -> Array[Dictionary]:
	cq.id_problem_chance = KycPolicy.ID_PROBLEM_CHANCE
	cq.account_opening_chance = KycPolicy.ACCOUNT_OPENING_CHANCE
	var seen: Array[Dictionary] = []
	for i in count:
		if fresh_accounts:
			AccountManager.reset()
		cq._spawn_customer()
		var c: CustomerNPC = cq.queue.pop_back()
		seen.append({"problem": c.id_card.problem, "presented": c.id_card.presented, "complaint": c.complaint != null, "opens": c.opens_account, "card": c.id_card, "name": c.display_name, "look": c.look_index})
		c.free()
	cq.id_problem_chance = 0.0
	cq.account_opening_chance = 0.0
	return seen

func points_since(start: Vector3i) -> Vector3i:
	return totals() - start

func pending_teller_mistakes() -> int:
	var pending: PackedStringArray = ReportManager._pending_mistakes.get(DecisionRecord.Role.TELLER, PackedStringArray())
	return pending.size()

# --- the cards -------------------------------------------------------------------

func test_id_problems_appear_at_the_configured_rate() -> void:
	assert_float(KycPolicy.ID_PROBLEM_CHANCE).is_equal_approx(1.0 / 7.0, 0.0001)
	var seen := sample_customers(1400)
	var counts: Array[int] = []
	counts.resize(Problem.size())
	for entry in seen:
		var problem: int = entry["problem"]
		counts[problem] += 1
	var bad := seen.size() - counts[Problem.NONE]
	# 1 in 7 of 1400 is 200; a binomial spread of about 13 either way.
	assert_int(bad).is_between(160, 240)
	# Each problem turns up in proportion to its weight (PROBLEM_WEIGHTS).
	var total_weight := 0
	for weight: int in KycPolicy.PROBLEM_WEIGHTS.values():
		total_weight += weight
	for problem in BAD_PROBLEMS:
		var weight: int = KycPolicy.PROBLEM_WEIGHTS[problem]
		var expected := float(bad) * weight / total_weight
		assert_float(float(counts[problem])).override_failure_message("%s: %d, expected about %.0f" % [Problem.keys()[problem], counts[problem], expected]).is_between(expected * 0.5, expected * 1.5)

func test_a_changed_rate_is_followed() -> void:
	cq.id_problem_chance = 1.0
	for i in 20:
		cq._spawn_customer()
		var c: CustomerNPC = cq.queue.pop_back()
		assert_bool(c.id_card.is_valid()).is_false()
		c.free()

func test_each_problem_shows_on_the_card() -> void:
	var today := GameClock.today_date()
	var customer := spawn()
	customer.set_look(1) # customer_a2
	give_id(customer, Problem.NONE)
	var card := customer.id_card
	assert_bool(card.presented).is_true()
	assert_str(card.holder_name).is_equal(customer.display_name)
	assert_int(card.portrait_look).is_equal(1)
	assert_int(card.expiry_date).is_greater(today)
	assert_int(today - card.date_of_birth).is_greater_equal(KycPolicy.AGE_MIN_YEARS * 365)
	assert_int(card.id_number.length()).is_equal(8)

	give_id(customer, Problem.EXPIRED)
	assert_int(customer.id_card.expiry_date).is_less(today)
	give_id(customer, Problem.NAME_MISMATCH)
	assert_str(customer.id_card.holder_name).is_not_equal(customer.display_name)
	# Same first name, another surname: it takes a careful read.
	assert_str(customer.id_card.holder_name.get_slice(" ", 0)).is_equal(customer.display_name.get_slice(" ", 0))
	give_id(customer, Problem.WRONG_PORTRAIT)
	assert_int(KycPolicy.design_of(customer.id_card.portrait_look)).is_not_equal(KycPolicy.design_of(1))
	give_id(customer, Problem.NO_ID)
	assert_bool(customer.id_card.presented).is_false()

# --- when ID is required -----------------------------------------------------------

func test_id_is_required_only_for_withdrawals_and_account_opening() -> void:
	var deposit_customer := spawn(ShiftTransaction.Type.DEPOSIT, 100)
	var cash_withdrawal := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	var card_withdrawal := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	card_withdrawal.payment_method = ShiftTransaction.PaymentMethod.CARD
	assert_bool(KycPolicy.requires_id(deposit_customer)).is_false()
	assert_bool(KycPolicy.requires_id(cash_withdrawal)).is_true()
	assert_bool(KycPolicy.requires_id(card_withdrawal)).is_true()
	cash_withdrawal.complaint = CustomerComplaintsData.get_complaints()[0]
	assert_bool(KycPolicy.requires_id(cash_withdrawal)).is_false()
	for c: CustomerNPC in cq.queue.duplicate():
		cq.queue.erase(c)
		c.free()
	var opener := spawn_opener()
	assert_bool(KycPolicy.requires_id(opener)).is_true()

func test_a_deposit_needs_no_check_even_on_a_bad_id() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.DEPOSIT, 100)
	give_id(customer, Problem.EXPIRED)
	var start := totals()
	open_desk()
	# Refuse Service is only for requests that need ID.
	assert_bool(ts.check_id_button.visible).is_true()
	assert_bool(ts.refuse_service_button.visible).is_false()
	deposit(100)
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE)
	assert_int(pending_teller_mistakes()).is_equal(0)
	assert_array(cq.queue).is_empty()

func test_refuse_service_needs_the_id_checked_first() -> void:
	clock_in()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	assert_bool(ts.refuse_service_button.visible).is_false()
	refuse_service() # nothing happens
	assert_int(cq.queue.size()).is_equal(1)
	check_id()
	assert_bool(ts.refuse_service_button.visible).is_true()
	assert_bool(ts.id_card_panel.visible).is_true()

# --- grading ------------------------------------------------------------------------

func test_valid_id_checked_and_request_done_earns_the_usual_reward() -> void:
	clock_in()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 120)
	var start := totals()
	open_desk()
	check_id()
	withdraw(120)
	complete()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE, TellerScreen.CUSTOMER_REQUEST_CORRECT_REPUTATION, TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(ts.feedback_label.text).starts_with("Correct")
	assert_int(pending_teller_mistakes()).is_equal(0)

func test_a_bad_id_refused_is_a_good_catch() -> void:
	clock_in()
	for problem in BAD_PROBLEMS:
		var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
		give_id(customer, problem)
		var start := totals()
		open_desk()
		check_id()
		refuse_service()
		assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.KYC_BAD_ID_CAUGHT_SCORE, TellerScreen.KYC_BAD_ID_CAUGHT_REPUTATION, TellerScreen.KYC_BAD_ID_CAUGHT_SCORE * XPManager.XP_PER_SCORE_POINT))
		assert_str(ts.feedback_label.text).contains("Good catch")
		assert_str(ts.feedback_label.text).contains(KycPolicy.REFUSAL_LINE)
		assert_str(ts.feedback_label.text).contains(ts.id_problem_text(customer))
		assert_array(cq.queue).not_contains([customer])
		assert_str(customer.farewell_line).is_not_empty()
		assert_bool(customer.left_upset).is_false()
		close_desk()
	assert_int(pending_teller_mistakes()).is_equal(0)
	assert_int(ts._bad_ids_caught).is_equal(BAD_PROBLEMS.size())

func test_a_withdrawal_on_a_bad_id_is_a_serious_mistake() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	give_id(customer, Problem.EXPIRED)
	var start := totals()
	open_desk()
	check_id()
	withdraw(100)
	complete()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.KYC_BAD_ID_ACCEPTED_SCORE, TellerScreen.KYC_BAD_ID_ACCEPTED_REPUTATION, 0))
	assert_str(ts.feedback_label.text).contains("Serious ID breach")
	# Worth two mistakes: a written warning straight away.
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_str(ReportManager.reports[0].items[0]).contains("invalid ID")
	# The request itself was done, so they're served (and gone).
	assert_array(cq.queue).is_empty()

func test_opening_an_account_on_a_bad_id_is_a_serious_mistake() -> void:
	clock_in()
	var customer := spawn_opener(200, Problem.NAME_MISMATCH)
	var start := totals()
	open_desk()
	check_id()
	open_account(customer.display_name)
	deposit(200)
	complete()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.KYC_BAD_ID_ACCEPTED_SCORE, TellerScreen.KYC_BAD_ID_ACCEPTED_REPUTATION, 0))
	assert_int(ReportManager.get_report_count()).is_equal(1)

func test_skipping_the_check_is_a_procedure_mistake_even_on_a_valid_id() -> void:
	clock_in()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	var start := totals()
	open_desk()
	withdraw(100)
	# Checking after the money went out doesn't count.
	check_id()
	complete()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.KYC_CHECK_SKIPPED_SCORE, TellerScreen.KYC_CHECK_SKIPPED_REPUTATION, 0))
	assert_str(ts.feedback_label.text).contains("Procedure mistake")
	assert_str(ts.feedback_label.text).contains("ID first for withdrawals")
	assert_str(ts.feedback_label.text).contains("bank policy")
	assert_int(pending_teller_mistakes()).is_equal(TellerScreen.KYC_CHECK_SKIPPED_MISTAKES)
	assert_array(cq.queue).is_empty()
	# A second one makes a written warning, like any two mistakes.
	close_desk()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	withdraw(100)
	complete()
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_str(ReportManager.reports[0].items[0]).contains("ID not checked")

func test_skipping_the_check_on_a_bad_id_is_serious() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	give_id(customer, Problem.NO_ID)
	var start := totals()
	open_desk()
	withdraw(100)
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.KYC_BAD_ID_ACCEPTED_SCORE)
	assert_int(ReportManager.get_report_count()).is_equal(1)
	assert_int(ts._id_checks_skipped).is_equal(1)
	assert_int(ts._bad_ids_accepted).is_equal(1)

func test_a_wrong_amount_and_a_skipped_check_are_both_mistakes() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	var start := totals()
	open_desk()
	withdraw(50)
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE + TellerScreen.KYC_CHECK_SKIPPED_SCORE)
	assert_str(ts.feedback_label.text).contains("Not right")
	assert_str(ts.feedback_label.text).contains("Procedure mistake")
	# Two mistakes in one visit: a written warning.
	assert_int(ReportManager.get_report_count()).is_equal(1)
	# Fixing the amount isn't graded again.
	withdraw(50)
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE + TellerScreen.KYC_CHECK_SKIPPED_SCORE)
	assert_array(cq.queue).not_contains([customer])

func test_a_valid_id_refused_leaves_the_customer_upset() -> void:
	clock_in()
	var customer := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	var start := totals()
	open_desk()
	check_id()
	refuse_service()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.KYC_VALID_ID_REFUSED_SCORE, TellerScreen.KYC_VALID_ID_REFUSED_REPUTATION, 0))
	assert_bool(customer.left_upset).is_true()
	assert_bool(CustomerNPC.REFUSED_VALID_ID_LINES.has(customer.farewell_line)).is_true()
	assert_str(ts.feedback_label.text).contains("was valid")
	assert_int(pending_teller_mistakes()).is_equal(0)
	assert_array(cq.queue).is_empty()

func test_refusing_needs_the_visit_undone_first() -> void:
	clock_in()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	check_id()
	withdraw(100)
	refuse_service()
	assert_bool(ts.error_label.visible).is_true()
	assert_int(cq.queue.size()).is_equal(1)
	reverse()
	refuse_service()
	assert_array(cq.queue).is_empty()

func test_the_shift_summary_counts_the_id_checks() -> void:
	clock_in()
	# Checked and served; a bad ID caught; a check skipped; a deposit.
	serve_correctly(spawn(ShiftTransaction.Type.WITHDRAWAL, 100))
	var bad := spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	give_id(bad, Problem.WRONG_PORTRAIT)
	open_desk()
	check_id()
	refuse_service()
	close_desk()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	withdraw(100)
	complete()
	close_desk()
	serve_correctly(spawn(ShiftTransaction.Type.DEPOSIT, 100))
	assert_bool(clock_out()).is_true()
	assert_str(ts.shift_customer_results_label.text).contains("ID checks: 2 checked · 1 bad ID caught · 1 skipped")
	# Every customer counted as handled, the refused one as served.
	assert_int(ts._shift_customer_count()).is_equal(4)
	assert_int(ts._customers_served()).is_equal(4)

# --- account opening ---------------------------------------------------------------

func test_about_one_in_ten_regular_customers_opens_an_account() -> void:
	assert_float(KycPolicy.ACCOUNT_OPENING_CHANCE).is_equal_approx(0.1, 0.0001)
	var seen := sample_customers(1000, true)
	var regular := 0
	var openers := 0
	for entry in seen:
		if entry["complaint"]:
			assert_bool(entry["opens"]).is_false()
			continue
		regular += 1
		if entry["opens"]:
			openers += 1
	# 10% of about 800 regular customers: about 80, spread about 8.5.
	assert_int(openers).is_between(int(regular * 0.1) - 30, int(regular * 0.1) + 30)

func test_an_account_opening_customer_has_no_account_and_says_so() -> void:
	var customer := spawn_opener(200)
	assert_object(customer.account).is_null()
	assert_object(AccountManager.find_account_by_name(customer.display_name)).is_null()
	assert_int(customer.intent_type).is_equal(ShiftTransaction.Type.DEPOSIT)
	assert_str(customer.dialogue_line.text).starts_with("I'd like to open an account with $")
	# Their ID is in their own name.
	assert_str(customer.id_card.holder_name).is_equal(customer.display_name)

func test_an_account_opening_customer_is_served_end_to_end() -> void:
	clock_in()
	var customer := spawn_opener(200)
	var start := totals()
	open_desk()
	assert_str(ts.customer_dialogue_label.text).contains("I'd like to open an account with $200.")
	check_id()
	open_account(customer.display_name)
	var opened := AccountManager.find_account_by_name(customer.display_name)
	assert_object(opened).is_not_null()
	assert_object(customer.account).is_same(opened)
	assert_object(ts.account).is_same(opened)
	deposit(200)
	complete()
	assert_vector(Vector3(points_since(start))).is_equal(Vector3(TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE, 0, TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(ts.feedback_label.text).contains("open an account with $200 as requested")
	assert_int(opened.balance_cents).is_equal(20000)
	assert_array(cq.queue).is_empty()
	# The cash went into the drawer.
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS + 20000)
	close_desk()
	assert_bool(clock_out()).is_false() # three more customers to come

func test_a_starting_deposit_counts_as_the_first_deposit() -> void:
	clock_in()
	var customer := spawn_opener(300)
	var start := totals()
	open_desk()
	check_id()
	open_account(customer.display_name, 300)
	assert_bool(ts.complete_transaction_button.disabled).is_false()
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.CUSTOMER_REQUEST_CORRECT_SCORE)
	assert_int(customer.account.balance_cents).is_equal(30000)
	assert_int(ts.drawer_cash_cents()).is_equal(TellerScreen.STARTING_FLOAT_CENTS + 30000)

func test_an_account_in_the_wrong_name_is_a_mistake() -> void:
	clock_in()
	var customer := spawn_opener(200)
	open_desk()
	check_id()
	open_account("Somebody Else", 200)
	assert_object(customer.account).is_null()
	complete()
	assert_bool(customer.was_mistake).is_true()
	assert_str(customer.correction_line).is_equal("I still need an account opened in my name — %s." % customer.display_name)
	# Put right: undo the deposit, open it in their name, deposit again.
	reverse()
	open_account(customer.display_name)
	deposit(200)
	complete()
	assert_array(cq.queue).is_empty()
	assert_int(customer.account.balance_cents).is_equal(20000)

func test_opening_without_checking_id_is_a_procedure_mistake() -> void:
	clock_in()
	var customer := spawn_opener(200)
	open_desk()
	open_account(customer.display_name)
	check_id()
	deposit(200)
	var start := totals()
	complete()
	assert_int(points_since(start).x).is_equal(TellerScreen.KYC_CHECK_SKIPPED_SCORE)
	assert_int(pending_teller_mistakes()).is_equal(1)

func test_an_account_opening_customer_with_a_bad_id_can_be_refused() -> void:
	clock_in()
	var customer := spawn_opener(200, Problem.EXPIRED)
	var start := totals()
	open_desk()
	check_id()
	refuse_service()
	assert_int(points_since(start).x).is_equal(TellerScreen.KYC_BAD_ID_CAUGHT_SCORE)
	assert_object(AccountManager.find_account_by_name(customer.display_name)).is_null()

# --- the hint ------------------------------------------------------------------------

func test_the_id_hint_shows_once_when_a_customer_first_needs_id() -> void:
	HintManager.reset()
	room.hud.dismiss_hint()
	clock_in()
	while room.hud.current_hint != -1:
		room.hud.dismiss_hint()
	var deposit_customer := spawn(ShiftTransaction.Type.DEPOSIT, 100)
	open_desk()
	assert_bool(HintManager.has_shown(HintManager.Hint.ID_CHECK)).is_false()
	deposit(100)
	complete()
	assert_array(cq.queue).not_contains([deposit_customer])
	close_desk()
	spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
	open_desk()
	assert_bool(HintManager.has_shown(HintManager.Hint.ID_CHECK)).is_true()
	assert_bool(room.hud.current_hint == HintManager.Hint.ID_CHECK or room.hud._hint_queue.has(HintManager.Hint.ID_CHECK)).is_true()
	assert_str(HintManager.text_for(HintManager.Hint.ID_CHECK)).contains("Bank policy")
	assert_bool(room.hud.show_hint_once(HintManager.Hint.ID_CHECK)).is_false()

# --- fit ------------------------------------------------------------------------------

func test_the_teller_screen_and_id_card_fit_the_window() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	clock_in()
	# Past the cutoff, so its line shows too. The longest feedback: a wrong
	# amount and an ID mistake at once, a serious one (bad ID) and a
	# procedure one (valid ID, not checked first), each with the customer's
	# correction line and the ID card up.
	GameClock.minutes = BusinessDay.CUTOFF_MINUTES + 30
	# The longest name a customer can have, paying by card (the longer
	# status line).
	var longest_name := ""
	for pool_name in CustomerQueue.CUSTOMER_NAMES:
		if pool_name.length() > longest_name.length():
			longest_name = pool_name
	# Many mistakes in a row here: keep reports (and termination) out of it.
	ReportManager.is_exempt = true
	var customer: CustomerNPC = null
	var cases: Array[IdCard.Problem] = BAD_PROBLEMS.duplicate()
	cases.append(Problem.NONE)
	for problem in cases:
		customer = spawn(ShiftTransaction.Type.WITHDRAWAL, 180)
		customer.display_name = longest_name
		customer.account.customer_name = customer.display_name
		customer.payment_method = ShiftTransaction.PaymentMethod.CARD
		give_id(customer, problem)
		spawn(ShiftTransaction.Type.WITHDRAWAL, 100)
		open_desk()
		withdraw(40)
		complete()
		check_id()
		for i in 4:
			await get_tree().process_frame
		assert_str(ts.feedback_label.text).contains("Serious ID breach" if problem != Problem.NONE else "Procedure mistake")
		assert_bool(ts.customer_dialogue_panel.visible).is_true()
		assert_bool(ts.cutoff_label.visible).is_true()
		assert_bool(ts.reverse_transaction_button.visible).is_true()
		assert_bool(ts.refuse_service_button.visible).is_true()
		assert_bool(ts.id_card_panel.visible).is_true()
		for panel: Control in [ts.main_panel, ts.id_card_panel]:
			var problems := layout_problems(panel)
			assert_array(problems).override_failure_message("%s:\n%s" % [Problem.keys()[problem], "\n".join(problems)]).is_empty()
		assert_bool(ts.main_panel.get_global_rect().intersects(ts.id_card_panel.get_global_rect())).is_false()
		if problem != Problem.NONE:
			# Put right and served, so the next one comes to the desk.
			withdraw(140)
			complete()
			close_desk()
			for c: CustomerNPC in cq.queue.duplicate():
				cq.queue.erase(c)
				c.free()
	# With no ID at all.
	give_id(customer, Problem.NO_ID)
	check_id()
	for i in 2:
		await get_tree().process_frame
	assert_array(layout_problems(ts.id_card_panel)).is_empty()
	# The Open New Account panel beside the card.
	ts.open_account_button.pressed.emit()
	for i in 2:
		await get_tree().process_frame
	assert_bool(ts.open_account_panel.get_global_rect().intersects(ts.id_card_panel.get_global_rect())).is_false()
	get_tree().root.size = window_before

func test_the_shift_summary_with_every_id_count_fits() -> void:
	clock_in()
	ts._ids_checked = 4
	ts._bad_ids_caught = 2
	ts._id_checks_skipped = 1
	ts._bad_ids_accepted = 1
	ts._valid_ids_refused = 1
	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		abandon(spawn())
	assert_bool(clock_out()).is_true()
	assert_str(ts.shift_customer_results_label.text).contains("1 bad ID accepted · 1 valid ID refused")
	assert_float(await settled_height(ts.shift_summary_panel)).is_less_equal(648.0)
