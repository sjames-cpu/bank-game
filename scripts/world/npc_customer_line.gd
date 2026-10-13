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
## teller_room.gd sets staff_npc and switches both lines (Teller Windows 1
## and 2) on at the start; they stay on. The player works their own
## Player Teller Window with its own CustomerQueue — until promotion to
## Branch Manager, when Window3Line (same lane) takes it over as Teller
## Window 3.

signal customer_served(customer: CustomerNPC, staff: StaffMember, was_mistake: bool)

## Desk slot this line belongs to (ScheduleManager.SLOT_*), for logs.
@export var slot_name: String = ""

## Each gap between arrivals is a fresh random value in this range (instead
## of the base class's fixed spawn_interval), so lines are sometimes short
## or empty rather than always full.
@export var spawn_interval_min: float = 12.0
@export var spawn_interval_max: float = 18.0

var staff_npc: StaffNPC = null
var active: bool = false

## Seconds the most recent completed service actually took (unpaused time),
## including any mistake fix — for tests/tuning.
var last_service_seconds: float = 0.0

var _serving: CustomerNPC = null
var _serving_staff: StaffNPC = null
var _time_left: float = 0.0
var _elapsed: float = 0.0
var _mistake_pending: bool = false
var _mistake_detail: String = ""
var _mistake_kind: StaffReviewItem.TellerMistake = StaffReviewItem.TellerMistake.AMOUNT_SHORT

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
	for customer in leaving:
		if is_instance_valid(customer):
			_departing.append(customer)
			send_customer_off(customer, CLOSED_LINE_FAREWELL)

func _next_spawn_interval() -> float:
	return randf_range(spawn_interval_min, spawn_interval_max)

func _on_spawn_timer_timeout() -> void:
	super._on_spawn_timer_timeout()
	if active:
		spawn_timer.start(_next_spawn_interval())

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

func _process(delta: float) -> void:
	if _serving != null:
		if not is_instance_valid(_serving) or not is_instance_valid(_serving_staff) or _serving_staff.state != StaffNPC.State.AT_DESK:
			_cancel_service()
			return
		_elapsed += delta
		_time_left -= delta
		if _time_left <= 0.0:
			if _mistake_pending:
				_reveal_mistake()
			else:
				_complete_service()
		return

	if not active or not is_instance_valid(staff_npc) or staff_npc.state != StaffNPC.State.AT_DESK:
		return
	var front := get_front_customer()
	if front != null and front.global_position.distance_to(queue_positions[0].global_position) <= CustomerNPC.ARRIVAL_DISTANCE:
		_start_service(front)

func _start_service(customer: CustomerNPC) -> void:
	_serving = customer
	_serving_staff = staff_npc
	var staff := staff_npc.staff
	_time_left = staff.service_seconds()
	_elapsed = 0.0
	_mistake_pending = randf() < staff.mistake_chance()
	customer.stop_waiting()
	staff_npc.say("Hi! How can I help?")
	customer.say("%s %s, please." % ["Deposit" if customer.intent_type == ShiftTransaction.Type.DEPOSIT else "Withdraw", MoneyMath.format(customer.intent_amount_cents, true)])

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
	var customer := _serving
	var staff := _serving_staff.staff
	var deposit := customer.intent_type == ShiftTransaction.Type.DEPOSIT
	var applied := true
	if deposit:
		AccountManager.deposit(customer.account, customer.intent_amount_cents)
	else:
		applied = AccountManager.withdraw(customer.account, customer.intent_amount_cents)

	var what := "%s %s %s %s's account" % ["deposited" if deposit else "withdrew", MoneyMath.format(customer.intent_amount_cents, true), "into" if deposit else "from", customer.display_name]
	if not applied:
		what = "couldn't withdraw %s from %s's account (insufficient funds)" % [MoneyMath.format(customer.intent_amount_cents, true), customer.display_name]
	var description := "%s (%s) %s" % [staff.staff_name, slot_name, what]
	if customer.was_mistake:
		description += " — mistake: %s, then fixed it" % _mistake_detail
	HistoryManager.add_staff_record(staff.staff_name, slot_name, description, "Mistake" if customer.was_mistake else "Correct")
	if customer.was_mistake:
		StaffReviewManager.add_teller_mistake(staff, slot_name, customer, _mistake_kind, _mistake_detail)

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
