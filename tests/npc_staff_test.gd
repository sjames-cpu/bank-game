extends "res://tests/support/teller_room_suite.gd"

## NPC coworkers and the player's desk: staff lines bank in their own
## account namespace, the desk never stays on a departed customer's account,
## and a Branch Manager promotion earned mid-shift waits for clock-out.

func test_staff_line_accounts_are_a_separate_namespace() -> void:
	var staff_line: NpcCustomerLine = room.get_node("Window1NpcLine")
	var player_account := cq._get_or_create_customer_account("Alex Rivera")
	var staff_account := staff_line._get_or_create_customer_account("Alex Rivera")
	assert_object(staff_account).is_not_same(player_account)
	assert_bool(staff_account.is_staff_line_account).is_true()
	assert_bool(player_account.is_staff_line_account).is_false()
	# Each line keeps reusing its own account by name.
	assert_object(cq._get_or_create_customer_account("Alex Rivera")).is_same(player_account)
	assert_object(staff_line._get_or_create_customer_account("Alex Rivera")).is_same(staff_account)
	# Staff never reuse the demo / player-opened account either.
	var demo := AccountManager.get_browsable_accounts()[0]
	assert_object(staff_line._get_or_create_customer_account(demo.customer_name)).is_not_same(demo)
	assert_bool(AccountManager.get_browsable_accounts().has(staff_account)).is_false()

## Real staff service: player-line customers wait while both staff lines
## serve customers who share their names. Only staff-line balances move.
func test_staff_never_change_player_line_balances() -> void:
	clock_in()
	var window_1: NpcCustomerLine = room.get_node("Window1NpcLine")
	var window_2: NpcCustomerLine = room.get_node("Window2Line")
	var players: Array[CustomerNPC] = []
	for i in 3:
		players.append(spawn(ShiftTransaction.Type.WITHDRAWAL, 20.0))
	var balances := {}
	for customer in players:
		balances[customer.account] = customer.account.balance_cents

	var served := [0]
	for line: NpcCustomerLine in [window_1, window_2]:
		line.customer_served.connect(func(_c: CustomerNPC, _s: StaffMember, _m: bool) -> void: served[0] += 1)
	var renamed := 0
	Engine.time_scale = 8.0
	var frames := 0
	while served[0] < 6 and frames < 3000:
		# Give every new staff-line customer a player customer's name, the
		# same way a same-named spawn would resolve its account.
		for line: NpcCustomerLine in [window_1, window_2]:
			for npc in line.queue:
				if not npc.has_meta("renamed"):
					npc.display_name = players[renamed % players.size()].display_name
					npc.account = line._get_or_create_customer_account(npc.display_name)
					npc.set_meta("renamed", true)
					renamed += 1
		for customer in players:
			customer.wait_seconds = 0.0 # keep them in line
		await get_tree().physics_frame
		frames += 1

	assert_int(served[0]).is_greater_equal(6)
	for customer in players:
		assert_int(customer.account.balance_cents).is_equal(balances[customer.account])

func test_account_resets_once_the_customer_has_left() -> void:
	clock_in()
	var demo := AccountManager.get_browsable_accounts()[0]

	# Served at Complete as the last in line.
	var served := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	open_desk()
	deposit(100)
	assert_object(ts.account).is_same(served.account)
	complete()
	assert_object(ts.account).is_same(demo)
	var served_balance := served.account.balance_cents
	deposit(40)
	assert_int(served.account.balance_cents).is_equal(served_balance)
	close_desk()

	# An open transaction keeps the account until it's graded on close.
	var closing := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	open_desk()
	deposit(100)
	assert_object(ts.account).is_same(closing.account)
	close_desk()
	assert_bool(cq.queue.has(closing)).is_false()
	assert_object(ts.account).is_same(demo)

	# Waiting for a correction keeps the account; leaving upset resets it.
	var upset := spawn(ShiftTransaction.Type.DEPOSIT, 100.0)
	open_desk()
	deposit(30)
	complete()
	assert_object(ts.account).is_same(upset.account)
	close_desk()
	open_desk()
	assert_object(ts.account).is_same(demo)
	var upset_balance := upset.account.balance_cents
	deposit(25)
	assert_int(upset.account.balance_cents).is_equal(upset_balance)
	close_desk()

	# Abandoned while the desk was closed.
	abandon(spawn())
	open_desk()
	assert_object(ts.account).is_same(demo)

func test_promotion_earned_mid_shift_waits_for_clock_out() -> void:
	clock_in()
	ReputationManager.add_reputation(100)
	XPManager.add_shift_xp(XPManager.XP_UNLOCK_THRESHOLD_BRANCH_MANAGER / XPManager.XP_PER_SCORE_POINT)
	assert_bool(XPManager.is_branch_manager_promotion_pending).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()

	for i in CustomerQueue.CUSTOMERS_PER_SHIFT_CAP:
		serve_correctly(spawn())
	assert_bool(XPManager.is_branch_manager_unlocked).is_false()
	assert_bool(clock_out()).is_true()
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	assert_bool(XPManager.is_branch_manager_promotion_pending).is_false()
	assert_bool(ReportManager.is_exempt).is_true()
