extends CustomerQueue
class_name NpcCustomerLine

## A teller window's customer line served by its staff member (StaffNPC)
## rather than the player. Reuses CustomerQueue's spawning, walking,
## accounts, stated intents and patience; differs in that:
## - there's no per-shift cap — customers keep arriving every
##   spawn_interval while the line is active, up to one per QueuePositions
##   marker (the maximum line length);
## - customers are regular ones only (no complaints);
## - nobody listens to customer_abandoned here, so a customer who runs out
##   of patience just leaves (no Reputation effect — NPC work never touches
##   the player's Score/Reputation/XP).
##
## - customers' accounts are their own namespace (staff-line accounts), so
##   a same-named customer in the player's line never shares one.
##
## Service: once the front customer has reached the window and the staff
## member is at their desk, the staff member works for
## StaffMember.service_seconds(). With StaffMember.mistake_chance() the
## transaction goes wrong: the customer points it out, the staff member
## spends StaffMember.mistake_fix_seconds() more fixing it, and the
## customer then leaves normally (still logged as a mistake). The final
## transaction is applied to the customer's own account via AccountManager
## — it's never recorded in the player's drawer — and logged as a STAFF
## record in HistoryManager. Everything runs on unpaused time only.
##
## ID checks follow the Player Teller Window's policy (KycPolicy): customers
## carry IDs from the same rate and mix, and about 1 in 10 comes to open an
## account. For a withdrawal or a new account, the staff member skips the
## check with StaffMember.id_skip_chance() (reliability); otherwise, a
## ID_ASK_SHARE of the way into the service, they ask for ID, and at
## ID_DECIDE_SHARE either accept it (a bad card slips past with
## StaffMember.id_miss_chance(), from skill; having no ID at all is never
## missed) or refuse, saying why, and the customer leaves unserved. Rolls use
## the line's own kyc_rng. What they did is kept on the staff record
## (KycPolicy.StaffCheck), and a slip goes to StaffReviewManager.
##
## teller_room.gd sets staff_npc and switches both lines (Teller Windows 1
## and 2) on at the start; they stay on. The player works their own
## Player Teller Window with its own CustomerQueue — until promotion to
## Branch Manager, when Window3Line (same lane) takes it over as Teller
## Window 3.

signal customer_served(customer: CustomerNPC, staff: StaffMember, was_mistake: bool)
## A customer turned away for a bad ID (not served).
signal customer_refused(customer: CustomerNPC, staff: StaffMember)
## After wind_down(), once the customer at the window (if any) is served.
signal wound_down

## Desk slot this line belongs to (ScheduleManager.SLOT_*), for logs.
@export var slot_name: String = ""

## Each gap between arrivals is a fresh random value in this range (instead
## of the base class's fixed spawn_interval), so lines are sometimes short
## or empty rather than always full.
@export var spawn_interval_min: float = 12.0
@export var spawn_interval_max: float = 18.0

var staff_npc: StaffNPC = null
var active: bool = false

## The staff member has been called to witness the vault (VaultDualControl):
## they finish the customer at the window but start no new one. Their line
## keeps its customers (and takes new ones), whose patience keeps running.
## Cleared once they're back at the desk.
var paused_for_vault: bool = false

## Seconds the most recent completed service actually took (unpaused time),
## including any mistake fix — kept for tuning service speed; nothing reads
## it yet.
var last_service_seconds: float = 0.0

## False makes the staff member always check correctly (tests that aren't
## about ID checks; staff_id_checks_test.gd leaves it on).
var staff_id_slips: bool = true

## The ID step's place in a service, as shares of its length.
const ID_ASK_SHARE: float = 0.3
const ID_DECIDE_SHARE: float = 0.6

## Set by wind_down() until wound_down fires.
var _winding_down: bool = false

var _serving: CustomerNPC = null
var _serving_staff: StaffNPC = null
var _time_left: float = 0.0
var _elapsed: float = 0.0
var _mistake_pending: bool = false
var _mistake_detail: String = ""
var _mistake_kind: StaffReviewItem.TellerMistake = StaffReviewItem.TellerMistake.AMOUNT_SHORT
## The current service's ID step: its length, whether the check is skipped,
## asked for and decided, and the outcome so far.
var _service_seconds: float = 0.0
var _id_skipped: bool = false
var _id_asked: bool = false
var _id_decided: bool = true
var _id_check: KycPolicy.StaffCheck = KycPolicy.StaffCheck.NOT_NEEDED

## Said by customers sent away when the desk closes (close_line()).
const CLOSED_LINE_FAREWELL: String = "Window's closed? I'll come back another time."

## Mistake kinds a customer can point out: [customer line, log detail].
## "%s" is a small dollar amount. The wrong-type kind is picked to match
## the customer's request (see _reveal_mistake()).
const _MISTAKE_AMOUNT_SHORT: Array = ["Hang on — that's %s short!", "came up %s short"]
const _MISTAKE_AMOUNT_OVER: Array = ["Wait, that's %s too much!", "gave %s too much"]
const _MISTAKE_WRONG_ACCOUNT: Array = ["That's not my account!", "used the wrong account"]
const _MISTAKE_WRONG_TYPE_DEPOSIT: Array = ["I said deposit, not withdraw!", "did a withdrawal instead of a deposit"]
const _MISTAKE_WRONG_TYPE_WITHDRAW: Array = ["I asked to withdraw, not deposit!", "did a deposit instead of a withdrawal"]

func activate() -> void:
	_winding_down = false
	active = true
	spawn_timer.start(_next_spawn_interval())

## The desk has nobody assigned (e.g. its staff member was terminated): stop
## taking customers and send everyone waiting — including whoever was
## mid-service — out of the line. activate() opens it again.
func close_line() -> void:
	active = false
	spawn_timer.stop()
	_cancel_service()
	var leaving := queue.duplicate()
	queue.clear()
	for entry: Variant in leaving:
		if is_instance_valid(entry):
			var customer: CustomerNPC = entry
			_departing.append(customer)
			send_customer_off(customer, CLOSED_LINE_FAREWELL)

## The window closes after its current customer (the Player Teller
## Window's cover teller at Loan Desk clock-out, teller_room.gd): no new
## arrivals; everyone still waiting moves to the first of `other_lines`
## that's open with room, or walks out; wound_down fires once the customer
## at the window (if any) has been served.
func wind_down(other_lines: Array[NpcCustomerLine]) -> void:
	active = false
	spawn_timer.stop()
	_winding_down = true
	var waiting: Array[CustomerNPC] = []
	for customer in queue:
		if customer != _serving:
			waiting.append(customer)
	for customer in waiting:
		queue.erase(customer)
		var target: NpcCustomerLine = null
		for line in other_lines:
			if line.active and line.has_room():
				target = line
				break
		if target != null:
			target.take_customer(customer)
		else:
			_departing.append(customer)
			send_customer_off(customer, CLOSED_LINE_FAREWELL)
	_advance_queue()

## Going home early: whoever is being served goes too.
func clear_lobby() -> void:
	_cancel_service()
	_departing.clear()
	super.clear_lobby()

func _next_spawn_interval() -> float:
	return randf_range(spawn_interval_min, spawn_interval_max)

## How crowded this window looks to an arriving customer, 0-1, for the
## player's line (teller_room.staff_window_pressure()): a closed window is
## 1 (its customers must go elsewhere); an open one is 0 with nobody waiting
## behind the customer at the window, rising to 1 with the line full.
func crowding() -> float:
	if not active:
		return 1.0
	var behind := queue.size() - 1
	var room_behind := queue_positions.size() - 1
	if behind <= 0 or room_behind <= 0:
		return 0.0
	return clampf(float(behind) / room_behind, 0.0, 1.0)

func is_serving() -> bool:
	return _serving != null

func _may_spawn() -> bool:
	return active

func _rolls_complaint() -> bool:
	return false

## Staff-line customers bank in their own account namespace, never sharing
## an account with a customer in the player's line (see
## Account.is_staff_line_account).
func _uses_staff_line_accounts() -> bool:
	return true

## Staff windows follow the same ID policy, and open accounts (KycPolicy).
func _checks_ids() -> bool:
	return true

## What the staff member did about the current (or last) customer's ID.
func current_id_check() -> KycPolicy.StaffCheck:
	return _id_check

func _process(delta: float) -> void:
	if _winding_down and _serving == null:
		_winding_down = false
		wound_down.emit()
		return
	if _serving != null:
		if not is_instance_valid(_serving) or not is_instance_valid(_serving_staff) or _serving_staff.state != StaffNPC.State.AT_DESK:
			_cancel_service()
			return
		_elapsed += delta
		_time_left -= delta
		if not _id_decided:
			if not _id_skipped and not _id_asked and _elapsed >= _service_seconds * ID_ASK_SHARE:
				_ask_for_id()
			if _elapsed >= _service_seconds * ID_DECIDE_SHARE and _decide_id():
				return
		if _time_left <= 0.0:
			if _mistake_pending:
				_reveal_mistake()
			else:
				_complete_service()
		return

	if not active or paused_for_vault or not is_instance_valid(staff_npc) or staff_npc.state != StaffNPC.State.AT_DESK:
		return
	var front := get_front_customer()
	if front != null and front.global_position.distance_to(queue_positions[0].global_position) <= CustomerNPC.ARRIVAL_DISTANCE:
		_start_service(front)

func _start_service(customer: CustomerNPC) -> void:
	_serving = customer
	_serving_staff = staff_npc
	var staff := staff_npc.staff
	_time_left = staff.service_seconds()
	_service_seconds = _time_left
	_elapsed = 0.0
	_mistake_pending = randf() < staff.mistake_chance()
	_id_asked = false
	_id_skipped = false
	_id_check = KycPolicy.StaffCheck.NOT_NEEDED
	_id_decided = not KycPolicy.requires_id(customer) or customer.id_card == null
	if not _id_decided:
		_id_skipped = staff_id_slips and kyc_rng.randf() < staff.id_skip_chance()
	customer.stop_waiting()
	staff_npc.say("Hi! How can I help?")
	var amount := MoneyMath.format(customer.intent_amount_cents, true)
	if customer.opens_account:
		customer.say("Open an account with %s, please." % amount)
	else:
		customer.say("%s %s, please." % ["Deposit" if customer.intent_type == ShiftTransaction.Type.DEPOSIT else "Withdraw", amount])

func _ask_for_id() -> void:
	_id_asked = true
	_serving_staff.say(KycPolicy.STAFF_ASK_LINE)
	_serving.say(KycPolicy.CUSTOMER_SHOWS_ID_LINE if _serving.id_card.presented else KycPolicy.CUSTOMER_NO_ID_LINE)

## Settles the ID step (skipped, accepted or refused). Returns true when the
## customer was refused, which ends the service.
func _decide_id() -> bool:
	_id_decided = true
	var card := _serving.id_card
	if _id_skipped:
		_id_check = KycPolicy.StaffCheck.SKIPPED if card.is_valid() else KycPolicy.StaffCheck.SKIPPED_BAD
		return false
	if not _id_asked:
		_ask_for_id()
	if card.is_valid():
		_id_check = KycPolicy.StaffCheck.CHECKED
	elif staff_id_slips and card.presented and kyc_rng.randf() < _serving_staff.staff.id_miss_chance():
		_id_check = KycPolicy.StaffCheck.MISSED
	else:
		_id_check = KycPolicy.StaffCheck.CAUGHT
		_refuse_service()
		return true
	_serving_staff.say(KycPolicy.STAFF_ID_OK_LINE)
	return false

## A bad ID refused: correct work, logged, and the customer leaves unserved.
func _refuse_service() -> void:
	var customer := _serving
	var staff := _serving_staff.staff
	var description := "%s (%s) refused %s's %s: the ID %s" % [staff.staff_name, slot_name, customer.display_name, request_text(customer), KycPolicy.problem_text(customer.id_card.problem)]
	HistoryManager.add_staff_record(staff.staff_name, slot_name, description, "Correct", KycPolicy.StaffCheck.CAUGHT)
	_serving_staff.say(KycPolicy.staff_refusal_line(customer.id_card.problem), 3.0)
	_serving = null
	_serving_staff = null
	_mistake_pending = false
	var refused := serve_front_customer()
	if refused != null:
		send_customer_off(refused, KycPolicy.REFUSED_FAREWELL)
	customer_refused.emit(customer, staff)

## "$200 withdrawal", "new account with $200".
static func request_text(customer: CustomerNPC) -> String:
	var amount := MoneyMath.format(customer.intent_amount_cents, true)
	if customer.opens_account:
		return "new account with %s" % amount
	return "%s %s" % [amount, "deposit" if customer.intent_type == ShiftTransaction.Type.DEPOSIT else "withdrawal"]

func _reveal_mistake() -> void:
	_mistake_pending = false
	_serving.was_mistake = true
	var wrong_type := _MISTAKE_WRONG_TYPE_DEPOSIT if _serving.intent_type == ShiftTransaction.Type.DEPOSIT else _MISTAKE_WRONG_TYPE_WITHDRAW
	var kinds: Array = [_MISTAKE_AMOUNT_SHORT, _MISTAKE_AMOUNT_OVER, wrong_type, _MISTAKE_WRONG_ACCOUNT]
	var kind_index := randi_range(0, kinds.size() - 1)
	# Same order as StaffReviewItem.TellerMistake.
	_mistake_kind = kind_index as StaffReviewItem.TellerMistake
	var kind: Array = kinds[kind_index]
	var amount := MoneyMath.format(randi_range(1, 5) * 1000, true) # $10-$50
	var line: String = kind[0]
	var detail: String = kind[1]
	_serving.say(line % amount if line.contains("%s") else line, 2.5)
	_serving_staff.say("Sorry — fixing that now.", 2.5)
	_mistake_detail = detail % amount if detail.contains("%s") else detail
	_time_left = _serving_staff.staff.mistake_fix_seconds()

func _complete_service() -> void:
	# Completed early (tests call this directly): the ID step first.
	if not _id_decided and _decide_id():
		return
	var customer := _serving
	var staff := _serving_staff.staff
	var deposit := customer.intent_type == ShiftTransaction.Type.DEPOSIT
	var applied := true
	var opened := customer.opens_account and customer.account == null
	if opened:
		customer.account = AccountManager.create_account(customer.display_name, 0)
		customer.account.is_customer_account = true
		customer.account.is_staff_line_account = true
	if deposit:
		AccountManager.deposit(customer.account, customer.intent_amount_cents)
	else:
		applied = AccountManager.withdraw(customer.account, customer.intent_amount_cents)

	# Cash moves through the window's till and on to the vault at the day's
	# close; a card transaction doesn't.
	if applied and customer.payment_method == ShiftTransaction.PaymentMethod.CASH:
		BusinessDay.note_staff_cash(customer.intent_amount_cents if deposit else -customer.intent_amount_cents)

	var what := "%s %s %s %s's account" % ["deposited" if deposit else "withdrew", MoneyMath.format(customer.intent_amount_cents, true), "into" if deposit else "from", customer.display_name]
	if opened:
		what = "opened an account for %s with %s" % [customer.display_name, MoneyMath.format(customer.intent_amount_cents, true)]
	elif not applied:
		what = "couldn't withdraw %s from %s's account (insufficient funds)" % [MoneyMath.format(customer.intent_amount_cents, true), customer.display_name]
	var description := "%s (%s) %s" % [staff.staff_name, slot_name, what]
	var id_check := _id_check
	match id_check:
		KycPolicy.StaffCheck.CHECKED:
			description += " — ID checked"
		KycPolicy.StaffCheck.SKIPPED, KycPolicy.StaffCheck.SKIPPED_BAD:
			description += " — didn't check ID (the ID %s)" % KycPolicy.problem_text(customer.id_card.problem)
		KycPolicy.StaffCheck.MISSED:
			description += " — checked ID but missed that it %s" % KycPolicy.problem_text(customer.id_card.problem)
	if customer.was_mistake:
		description += " — mistake: %s, then fixed it" % _mistake_detail
	var slipped := KycPolicy.is_slip(id_check)
	HistoryManager.add_staff_record(staff.staff_name, slot_name, description, "Mistake" if customer.was_mistake or slipped else "Correct", id_check)
	if customer.was_mistake:
		StaffReviewManager.add_teller_mistake(staff, slot_name, customer, _mistake_kind, _mistake_detail)
	if slipped:
		StaffReviewManager.add_id_slip(staff, slot_name, customer, id_check)

	last_service_seconds = _elapsed
	_serving_staff.say("All set — have a nice day!")
	var was_mistake := customer.was_mistake
	_serving = null
	_serving_staff = null
	_mistake_detail = ""
	var served := serve_front_customer()
	if served != null:
		send_customer_off(served)
	customer_served.emit(customer, staff, was_mistake)

func _cancel_service() -> void:
	_serving = null
	_serving_staff = null
	_mistake_pending = false
	_mistake_detail = ""
	_id_decided = true
	_id_check = KycPolicy.StaffCheck.NOT_NEEDED
