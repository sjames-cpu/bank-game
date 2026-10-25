extends "res://tests/support/teller_room_suite.gd"

## The armored truck visit (ArmoredTruckVisit, VaultManager's visits,
## ArmoredTruckScreen): the crew's arrival and departure; the identity check
## and an unscheduled crew; each delivery problem; accepting, refusing and
## re-delivery; pickups; the missed window; the NPC branch manager before
## promotion; each grading row; the Regional review's record; save and load.

const STRAP := VaultManager.STRAP_CENTS
const START := VaultReconciliationScreen.STARTING_VAULT_CENTS
const Problem := VaultManager.BagProblem
const Verdict := VaultManager.ShipmentVerdict

var truck: ArmoredTruckVisit
var screen: ArmoredTruckScreen

func before_test() -> void:
	await super()
	truck = room.armored_visit
	screen = room.armored_truck_screen
	for hint: int in HintManager.Hint.values():
		HintManager.mark_shown(hint)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func acknowledge_letters() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

func promote() -> void:
	XPManager._grant_branch_manager()
	acknowledge_letters()

## Day `day` at `minutes`, today's stats on that day.
func set_time(day: int, minutes: float) -> void:
	GameClock.day = day
	GameClock.minutes = minutes
	BusinessDay.stats_day = day

## An order placed the day before `day`, so the truck comes on `day`.
func order_for(day: int, cents: int) -> void:
	assert_str(VaultManager.place_order(cents, day - 1)).is_empty()

## The truck arrives at 10:30 on `day`; the crew's walk is skipped.
func crew_arrives(day: int) -> void:
	set_time(day, ArmoredTruckVisit.ARRIVAL_MINUTES)
	await frames(2)
	assert_int(truck.guards.size()).is_equal(2)
	for guard: StaffNPC in truck.guards.duplicate():
		guard.finish_route()

## The Branch Manager at the vault door receives the crew: the witness comes
## (their walk skipped) and the screen opens. Returns the witness.
func receive_at_door() -> StaffNPC:
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	var control := room.vault_control
	assert_int(control.purpose).is_equal(VaultDualControl.Purpose.ARMORED)
	control._process(0.0)
	var witness := control.witness
	witness.finish_route()
	control._process(0.0)
	assert_bool(screen.visible).is_true()
	return witness

## Bag `index` of today's visit shows `problem`.
func spoil_bag(index: int, problem: VaultManager.BagProblem) -> void:
	var bags: Array = VaultManager.today_visit["bags"]
	var bag: Dictionary = bags[index]
	VaultManager._spoil(bag, problem)

func an_outcome(overrides: Dictionary) -> Dictionary:
	var outcome := {
		"verdict": Verdict.CORRECT, "fake": false, "crew_accepted": true,
		"good_accepted": 1, "good_refused": 0, "bad_accepted": 0, "bad_refused": 0,
		"credited": 0, "short": 0, "redelivery": 0, "pickup": 0, "missed": false,
	}
	outcome.merge(overrides, true)
	return outcome

# --- arrival and departure -------------------------------------------------------------

func test_the_crew_arrives_mid_morning_and_the_npc_manager_receives_them() -> void:
	order_for(4, 7 * STRAP)
	set_time(4, ArmoredTruckVisit.ARRIVAL_MINUTES - 1)
	await frames(2)
	assert_array(truck.guards).is_empty()
	GameClock.minutes = ArmoredTruckVisit.ARRIVAL_MINUTES
	await frames(2)
	# Two guards in their own uniforms walk in from the entrance.
	assert_int(truck.guards.size()).is_equal(2)
	var presented: Array = VaultManager.today_visit["presented"]["guards"]
	for i in 2:
		var guard := truck.guards[i]
		assert_str(guard.staff.staff_name).is_equal(presented[i]["name"])
		assert_str(guard.staff.look).is_equal(StaffLooks.GUARD_LOOKS[i])
		assert_int(guard.state).is_equal(StaffNPC.State.WALKING)
	assert_int(VaultManager.expected_cents).is_equal(START) # not yet
	# At the vault door, the NPC branch manager receives them, and they go.
	for guard: StaffNPC in truck.guards.duplicate():
		guard.finish_route()
	assert_int(VaultManager.expected_cents).is_equal(START + 7 * STRAP)
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	for guard: StaffNPC in truck.guards.duplicate():
		guard.finish_route()
	await frames(2)
	assert_array(truck.guards).is_empty()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.IDLE)
	# Done for the day: they don't come back.
	await frames(2)
	assert_array(truck.guards).is_empty()

func test_the_crew_really_walks_to_the_vault_door_and_out() -> void:
	# No skipped walks here: the routes must be clear of every wall.
	promote()
	order_for(4, 5 * STRAP)
	set_time(4, ArmoredTruckVisit.ARRIVAL_MINUTES)
	await frames(2)
	var crew := truck.guards.duplicate()
	Engine.time_scale = 4.0
	var waited := 0
	while not truck.is_waiting() and waited < 900:
		await get_tree().physics_frame
		waited += 1
	assert_bool(truck.is_waiting()).override_failure_message("the crew never reached the vault door").is_true()
	for i in 2:
		var guard: StaffNPC = crew[i]
		assert_vector(guard.global_position).is_equal_approx(ArmoredTruckVisit.GUARD_SPOTS[i], Vector2(1, 1))
	truck.leave()
	waited = 0
	while not truck.guards.is_empty() and waited < 900:
		await get_tree().physics_frame
		waited += 1
	Engine.time_scale = 1.0
	assert_array(truck.guards).override_failure_message("the crew never left").is_empty()

func test_no_truck_without_cash_to_move() -> void:
	set_time(4, ArmoredTruckVisit.ARRIVAL_MINUTES)
	await frames(2)
	assert_array(truck.guards).is_empty()

func test_the_npc_manager_refuses_problem_bags_and_unscheduled_crews() -> void:
	order_for(4, 12 * STRAP)
	VaultManager.prepare_visit(4)
	spoil_bag(1, Problem.BROKEN_SEAL)
	var outcome := VaultManager.npc_handle_visit(4)
	assert_int(outcome["bad_refused"]).is_equal(1)
	assert_int(outcome["good_accepted"]).is_equal(2)
	# 12 straps in bags of 5, 5 and 2: the second refused, re-delivered.
	assert_int(VaultManager.expected_cents).is_equal(START + 7 * STRAP)
	assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
	# An unscheduled crew the next day: refused, the shipment waits a day.
	VaultManager.fake_crew_chance = 1.0
	outcome = VaultManager.npc_handle_visit(5)
	assert_bool(outcome["crew_accepted"]).is_false()
	assert_int(VaultManager.arriving_on(6)).is_equal(5 * STRAP)
	assert_int(VaultManager.expected_cents).is_equal(START + 7 * STRAP)

# --- the Branch Manager receives them ----------------------------------------------------

func test_the_branch_manager_receives_a_delivery_under_dual_control() -> void:
	promote()
	order_for(4, 7 * STRAP)
	await crew_arrives(4)
	assert_bool(truck.is_waiting()).is_true()
	assert_str(room.desk_notice_label.text).contains("armored truck crew is at the vault door")
	assert_str(room.interaction_prompt_text(room.vault_door)).is_equal("E — Receive the armored truck (dual control)")
	var witness := receive_at_door()
	# The crew check comes first: nothing to sign until it's done.
	assert_bool(screen.shipment_section.visible).is_false()
	assert_str(screen.policy_label.text).contains("Bank security policy")
	screen.accept_crew_button.pressed.emit()
	assert_bool(screen.shipment_section.visible).is_true()
	assert_int(screen.accept_checks.size()).is_equal(2) # $50,000 and $20,000
	var start := totals()
	screen.sign_button.pressed.emit()
	assert_int(VaultManager.expected_cents).is_equal(START + 7 * STRAP)
	assert_int(screen.last_outcome["verdict"]).is_equal(Verdict.CORRECT)
	assert_vector(totals() - start).is_equal(Vector3i(ArmoredTruckScreen.CORRECT_SCORE, ArmoredTruckScreen.CORRECT_REPUTATION, ArmoredTruckScreen.CORRECT_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(screen.result_label.text).contains("Received correctly")
	# Closing lets the crew and the witness go.
	screen.close_button.pressed.emit()
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	assert_int(witness.state).is_equal(StaffNPC.State.WALKING)
	assert_str(HistoryManager.records[-1].description).starts_with("Armored truck: 2 of 2 bags accepted")

func test_each_problem_bag_shows_and_is_refused_for_re_delivery() -> void:
	promote()
	for problem: VaultManager.BagProblem in [Problem.BROKEN_SEAL, Problem.SEAL_MISMATCH, Problem.MISSING]:
		CareerReset.reset_all()
		fix_truck_rolls()
		XPManager._grant_branch_manager()
		acknowledge_letters()
		truck.clear()
		order_for(4, 7 * STRAP)
		VaultManager.prepare_visit(4)
		spoil_bag(0, problem)
		var bag: Dictionary = VaultManager.today_visit["bags"][0]
		assert_int(VaultManager.bag_problem(bag)).is_equal(problem)
		await crew_arrives(4)
		var witness := receive_at_door()
		screen.accept_crew_button.pressed.emit()
		var row_text := (screen.bags_vbox.get_child(0).get_child(1) as Label).text
		match problem:
			Problem.BROKEN_SEAL:
				assert_str(row_text).ends_with("seal BROKEN")
			Problem.SEAL_MISMATCH:
				assert_str(row_text).is_not_equal("%s · seal intact" % bag["manifest_seal"])
				assert_str(row_text).ends_with("seal intact")
			Problem.MISSING:
				assert_str(row_text).is_equal("Not delivered")
		screen.accept_checks[0].button_pressed = false
		var start := totals()
		screen.sign_button.pressed.emit()
		# The good bag reaches the vault; the refused one comes tomorrow.
		assert_int(VaultManager.expected_cents).is_equal(START + 2 * STRAP)
		assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
		assert_int((totals() - start).x).is_equal(ArmoredTruckScreen.CORRECT_SCORE + ArmoredTruckScreen.PROBLEM_CAUGHT_SCORE)
		assert_str(screen.result_label.text).contains("Good catch")
		screen.close_button.pressed.emit()
		witness.finish_route()

func test_a_refused_bag_comes_back_the_next_business_day() -> void:
	order_for(5, 5 * STRAP) # Friday's delivery
	VaultManager.prepare_visit(5)
	spoil_bag(0, Problem.BROKEN_SEAL)
	VaultManager.npc_handle_visit(5)
	assert_int(VaultManager.expected_cents).is_equal(START)
	assert_str(BankCalendar.short_text(GameClock.date_of_day(6))).is_equal("Mon 12 Jan")
	assert_bool(VaultManager.has_visit_due(6)).is_true()
	VaultManager.npc_handle_visit(6)
	assert_int(VaultManager.expected_cents).is_equal(START + 5 * STRAP)

func test_signing_for_a_problem_bag_leaves_the_vault_short() -> void:
	promote()
	order_for(4, 5 * STRAP)
	VaultManager.prepare_visit(4)
	spoil_bag(0, Problem.BROKEN_SEAL)
	await crew_arrives(4)
	receive_at_door()
	screen.accept_crew_button.pressed.emit()
	var start := totals()
	screen.sign_button.pressed.emit()
	# 20% short of the $50,000 declared.
	assert_int(VaultManager.expected_cents).is_equal(START + 4 * STRAP)
	assert_int(screen.last_outcome["short"]).is_equal(STRAP)
	assert_int(screen.last_outcome["verdict"]).is_equal(Verdict.SERIOUS)
	assert_vector(totals() - start).is_equal(Vector3i(ArmoredTruckScreen.PROBLEM_SIGNED_SCORE, ArmoredTruckScreen.PROBLEM_SIGNED_REPUTATION, 0))
	assert_str(screen.result_label.text).contains("Serious error")
	assert_array(RegionalManager.shipment_verdicts).is_equal([Verdict.SERIOUS])

func test_a_pickup_is_handed_over_after_the_crew_check() -> void:
	promote()
	order_for(4, -6 * STRAP)
	await crew_arrives(4)
	receive_at_door()
	screen.accept_crew_button.pressed.emit()
	assert_bool(screen.pickup_label.visible).is_true()
	assert_str(screen.pickup_label.text).is_equal("Pickup: hand over $60000 in 2 sealed bags")
	assert_str(screen.sign_button.text).is_equal("Hand Over and Sign")
	screen.sign_button.pressed.emit()
	assert_int(VaultManager.expected_cents).is_equal(START - 6 * STRAP)
	assert_int(VaultManager.shipped_today_cents).is_equal(6 * STRAP)
	assert_array(VaultManager.pending_orders).is_empty()
	assert_int(screen.last_outcome["verdict"]).is_equal(Verdict.CORRECT)

func test_the_crew_leaves_and_the_shipment_waits_if_nobody_comes() -> void:
	promote()
	order_for(4, 5 * STRAP)
	await crew_arrives(4)
	var start := totals()
	GameClock.minutes = ArmoredTruckVisit.ARRIVAL_MINUTES + ArmoredTruckVisit.WAIT_MINUTES - 1
	await frames(2)
	assert_bool(truck.is_waiting()).is_true()
	GameClock.minutes = ArmoredTruckVisit.ARRIVAL_MINUTES + ArmoredTruckVisit.WAIT_MINUTES
	await frames(2)
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.LEAVING)
	assert_int(VaultManager.expected_cents).is_equal(START)
	assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
	assert_int((totals() - start).x).is_equal(ArmoredTruckVisit.MISSED_SCORE)
	assert_array(RegionalManager.shipment_verdicts).is_equal([Verdict.DELAY])
	assert_str(HistoryManager.records[-1].description).starts_with("Armored truck missed")

func test_receiving_in_progress_isnt_missed() -> void:
	promote()
	order_for(4, 5 * STRAP)
	await crew_arrives(4)
	room.vault_door.player_in_range = true
	room._on_vault_door_interacted()
	GameClock.minutes = ArmoredTruckVisit.ARRIVAL_MINUTES + ArmoredTruckVisit.WAIT_MINUTES + 5
	await frames(2)
	assert_int(truck.phase).is_equal(ArmoredTruckVisit.Phase.BEING_RECEIVED)
	assert_bool(VaultManager.has_visit_due(4)).is_true()

func test_going_home_before_the_truck_reschedules_it_for_a_manager() -> void:
	promote()
	order_for(4, 5 * STRAP)
	set_time(4, 9 * 60.0)
	room._on_exit_door_interacted()
	room.end_of_day_screen.go_home_button.pressed.emit()
	assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
	assert_str(room.end_of_day_screen.summary_label.text).contains("Armored truck: missed; shipment rescheduled for Day 5.")
	assert_array(RegionalManager.shipment_verdicts).is_equal([Verdict.DELAY])

# --- the crew's identity ---------------------------------------------------------------

func test_about_one_visit_in_twenty_is_an_unscheduled_crew() -> void:
	assert_float(VaultManager.FAKE_CREW_CHANCE).is_equal_approx(0.05, 0.0001)
	assert_float(VaultManager.SHIPMENT_PROBLEM_CHANCE).is_equal_approx(0.1, 0.0001)
	VaultManager.fake_crew_chance = VaultManager.FAKE_CREW_CHANCE
	VaultManager.shipment_problem_chance = VaultManager.SHIPMENT_PROBLEM_CHANCE
	VaultManager.place_order(7 * STRAP, 1)
	var fakes := 0
	var problems := 0
	var kinds := {"company": 0, "name": 0, "badge": 0}
	for i in 2000:
		VaultManager.today_visit = {}
		var visit := VaultManager.prepare_visit(2)
		if visit["fake"]:
			fakes += 1
			assert_bool(VaultManager.crew_matches(visit)).is_false()
			var scheduled: Dictionary = visit["scheduled"]
			var presented: Dictionary = visit["presented"]
			var scheduled_guards := JSON.stringify(scheduled["guards"])
			var shown_guards: Array = presented["guards"]
			var first: Dictionary = shown_guards[0]
			var second: Dictionary = shown_guards[1]
			var first_badge: String = first["badge"]
			var second_badge: String = second["badge"]
			if scheduled["company"] != presented["company"]:
				kinds["company"] += 1
			elif scheduled_guards.contains(first_badge) and scheduled_guards.contains(second_badge):
				kinds["name"] += 1
			else:
				kinds["badge"] += 1
		else:
			assert_bool(VaultManager.crew_matches(visit)).is_true()
		for bag: Dictionary in visit["bags"]:
			if VaultManager.bag_problem(bag) != Problem.NONE:
				problems += 1
	# 1 in 20 of 2000 is 100 (spread about 10); 1 in 10 is 200 (about 13).
	assert_int(fakes).is_between(70, 130)
	assert_int(problems).is_between(160, 240)
	for kind: String in kinds:
		assert_int(kinds[kind]).override_failure_message(kind).is_greater(0)

func test_refusing_an_unscheduled_crew_is_a_good_catch() -> void:
	promote()
	VaultManager.fake_crew_chance = 1.0
	order_for(4, 5 * STRAP)
	await crew_arrives(4)
	receive_at_door()
	var start := totals()
	screen.refuse_crew_button.pressed.emit()
	assert_vector(totals() - start).is_equal(Vector3i(ArmoredTruckScreen.FAKE_CREW_CAUGHT_SCORE, ArmoredTruckScreen.FAKE_CREW_CAUGHT_REPUTATION, ArmoredTruckScreen.FAKE_CREW_CAUGHT_SCORE * XPManager.XP_PER_SCORE_POINT))
	assert_str(screen.result_label.text).contains("Good catch: not the scheduled crew")
	assert_int(VaultManager.expected_cents).is_equal(START)
	assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
	assert_int(RegionalManager.warnings).is_equal(0)

func test_handing_cash_to_an_unscheduled_crew_is_critical() -> void:
	promote()
	VaultManager.fake_crew_chance = 1.0
	order_for(4, -6 * STRAP)
	await crew_arrives(4)
	receive_at_door()
	screen.accept_crew_button.pressed.emit()
	var start := totals()
	screen.sign_button.pressed.emit()
	# The cash is gone; the pickup is over.
	assert_int(VaultManager.expected_cents).is_equal(START - 6 * STRAP)
	assert_array(VaultManager.pending_orders).is_empty()
	assert_int(screen.last_outcome["verdict"]).is_equal(Verdict.CRITICAL)
	assert_vector(totals() - start).is_equal(Vector3i(ArmoredTruckScreen.CRITICAL_SCORE, ArmoredTruckScreen.CRITICAL_REPUTATION, 0))
	assert_str(screen.result_label.text).contains("Critical security breach")
	# A regional warning, with its letter.
	assert_int(RegionalManager.warnings).is_equal(1)
	assert_str(room.letter_screen.title_label.text).is_equal("Regional Warning — 1 of 3")
	assert_str(room.letter_screen.body_label.text).contains("wasn't scheduled")

func test_refusing_the_genuine_crew_delays_the_shipment() -> void:
	promote()
	order_for(4, 5 * STRAP)
	await crew_arrives(4)
	receive_at_door()
	var start := totals()
	screen.refuse_crew_button.pressed.emit()
	assert_vector(totals() - start).is_equal(Vector3i(ArmoredTruckScreen.GENUINE_REFUSED_SCORE, ArmoredTruckScreen.GENUINE_REFUSED_REPUTATION, 0))
	assert_int(VaultManager.arriving_on(5)).is_equal(5 * STRAP)
	assert_array(RegionalManager.shipment_verdicts).is_equal([Verdict.DELAY])

# --- grading ------------------------------------------------------------------------------

func test_each_grading_row() -> void:
	var correct := ArmoredTruckScreen.grade(an_outcome({}))
	assert_int(correct["score"]).is_equal(8)
	assert_int(correct["reputation"]).is_equal(1)
	var caught := ArmoredTruckScreen.grade(an_outcome({"bad_refused": 1}))
	assert_int(caught["score"]).is_equal(8 + 3)
	var signed := ArmoredTruckScreen.grade(an_outcome({"verdict": Verdict.SERIOUS, "bad_accepted": 1, "short": STRAP}))
	assert_int(signed["score"]).is_equal(-10)
	assert_int(signed["reputation"]).is_equal(-3)
	var good_refused := ArmoredTruckScreen.grade(an_outcome({"verdict": Verdict.DELAY, "good_refused": 1}))
	assert_int(good_refused["score"]).is_equal(-3)
	assert_int(good_refused["reputation"]).is_equal(0)
	var genuine_refused := ArmoredTruckScreen.grade(an_outcome({"verdict": Verdict.DELAY, "crew_accepted": false}))
	assert_int(genuine_refused["score"]).is_equal(-5)
	assert_int(genuine_refused["reputation"]).is_equal(-1)
	var fake_refused := ArmoredTruckScreen.grade(an_outcome({"fake": true, "crew_accepted": false}))
	assert_int(fake_refused["score"]).is_equal(10)
	assert_int(fake_refused["reputation"]).is_equal(2)
	var critical := ArmoredTruckScreen.grade(an_outcome({"verdict": Verdict.CRITICAL, "fake": true}))
	assert_int(critical["score"]).is_equal(-20)
	assert_int(critical["reputation"]).is_equal(-8)
	assert_bool(critical["warning"]).is_true()
	assert_bool(correct["warning"]).is_false()
	assert_int(ArmoredTruckVisit.MISSED_SCORE).is_equal(-3)

func test_the_regional_review_rates_cash_management() -> void:
	promote()
	RegionalManager.note_shipment(Verdict.CORRECT)
	RegionalManager.note_shipment(Verdict.DELAY)
	var area: Dictionary = {}
	for entry: Dictionary in RegionalManager.evaluate()["areas"]:
		if entry["key"] == RegionalManager.AREA_CASH:
			area = entry
	assert_bool(area["rated"]).is_true()
	assert_int(area["weight"]).is_equal(15)
	# In range every day (100) and visits averaging 80: 90.
	assert_float(area["score"]).is_equal_approx(90.0, 0.01)
	assert_str(area["detail"]).contains("2 armored truck visits, 1 handled correctly.")

# --- save and load -------------------------------------------------------------------------

func test_a_visit_and_rescheduled_shipments_are_saved() -> void:
	promote()
	order_for(4, 7 * STRAP)
	VaultManager.prepare_visit(4)
	spoil_bag(1, Problem.SEAL_MISMATCH)
	VaultManager.set_visit_state(VaultManager.VisitState.ARRIVED)
	VaultManager.pending_orders.append({"placed_day": 3, "delivery_day": 5, "cents": -2 * STRAP})
	RegionalManager.note_shipment(Verdict.SERIOUS)
	var visit_before: Dictionary = VaultManager.today_visit.duplicate(true)
	assert_bool(SaveGame.save()).is_true()
	CareerReset.reset_all()
	assert_dict(VaultManager.today_visit).is_empty()
	SaveGame.restore(SaveGame.read().career)
	# A crew that was in the branch comes back: the visit loads as built.
	visit_before["state"] = VaultManager.VisitState.BUILT
	assert_str(JSON.stringify(VaultManager.today_visit)).is_equal(JSON.stringify(visit_before))
	assert_int(VaultManager.pending_orders.size()).is_equal(2)
	assert_int(VaultManager.pending_orders[1]["delivery_day"]).is_equal(5)
	assert_array(RegionalManager.shipment_verdicts).is_equal([Verdict.SERIOUS])

func test_career_reset_clears_the_truck() -> void:
	VaultManager.fake_crew_chance = 1.0
	order_for(4, 5 * STRAP)
	VaultManager.prepare_visit(4)
	CareerReset.reset_all()
	assert_dict(VaultManager.today_visit).is_empty()
	assert_float(VaultManager.fake_crew_chance).is_equal(VaultManager.FAKE_CREW_CHANCE)
	assert_str(VaultManager.visit_note).is_empty()

# --- fit ------------------------------------------------------------------------------------

func test_the_armored_truck_screen_fits_the_window() -> void:
	var window_before := get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)
	promote()
	# Six bags and a pickup: the most a visit carries.
	order_for(4, 30 * STRAP)
	VaultManager.pending_orders.append({"placed_day": 2, "delivery_day": 4, "cents": -5 * STRAP})
	VaultManager.prepare_visit(4)
	spoil_bag(2, Problem.MISSING)
	await crew_arrives(4)
	receive_at_door()
	await frames(3)
	var problems := layout_problems(screen.panel)
	assert_array(problems).override_failure_message("crew check:\n" + "\n".join(problems)).is_empty()
	screen.accept_crew_button.pressed.emit()
	await frames(3)
	assert_int(screen.accept_checks.size()).is_equal(6)
	assert_bool(screen.pickup_label.visible).is_true()
	problems = layout_problems(screen.panel)
	assert_array(problems).override_failure_message("shipment:\n" + "\n".join(problems)).is_empty()
	screen.sign_button.pressed.emit()
	await frames(3)
	problems = layout_problems(screen.panel)
	assert_array(problems).override_failure_message("result:\n" + "\n".join(problems)).is_empty()
	get_tree().root.size = window_before
