extends Node

## Autoload singleton — the branch vault's expected cash, in int cents (B3),
## and its supply chain: cash levels, orders and the armored truck that
## delivers and collects them. Reset with the career (CareerReset) and saved
## with it (see SaveGame).
##
## The expected total starts at VaultReconciliationScreen.STARTING_VAULT_CENTS
## and moves by:
## - the teller's transfers at the vault door (receive_from_drawer(),
##   pay_to_drawer());
## - each business day's close (close_day(), when the End of Day summary
##   appears): the staff windows' net cash for the day (cash only, from
##   BusinessDay.staff_net_cash_cents) and, every ATM_RESTOCK_EVERY_DAYS, an
##   ATM restock taken from the vault;
## - cash orders from the Federal Reserve Bank, and shipments of excess cash
##   back to it (place_order()), for the next business day. Day numbers count
##   business days only, so the next business day is always day + 1, whatever
##   weekend or holiday is between. The armored truck brings and collects them
##   (ArmoredTruckVisit, in the room): prepare_visit() builds the day's visit
##   (the scheduled crew and the crew who turns up, the sealed bags against
##   the manifest, the pickup), and complete_visit() applies what the manager
##   accepted; miss_visit() reschedules it; npc_handle_visit() is the NPC
##   branch manager's handling before promotion.
## The vault should stay between VAULT_MIN_CENTS and VAULT_MAX_CENTS: a day
## that closes outside them is recorded (out_of_range_days) for the Regional
## Manager's review (part 2). Before the player is Branch Manager, an NPC
## branch manager orders by itself at each close (_npc_order()).

signal expected_changed(cents: int)

## The vault's limits. The minimum covers about two weeks of ATM restocks
## ($24,000 every 3 business days: 4 restocks, $96,000) plus refilling the
## four teller drawers ($3,000 floats) a time or two, so a late or missed
## delivery doesn't empty the branch. The maximum caps idle cash at risk (and
## the insurance it needs) at one and a half times the $200,000 the branch
## starts with, which sits in the middle.
const VAULT_MIN_CENTS: int = 10000000
const VAULT_MAX_CENTS: int = 30000000
## Halfway between them: $200,000, the starting total.
const VAULT_MID_CENTS: int = 20000000

## The branch ATM: a busy branch machine pays out around $8,000 a business
## day (about 80 withdrawals averaging $100). Its cassettes hold more than
## that, so it's refilled every third business day with $24,000 from the vault
## (at that day's close).
const ATM_RESTOCK_CENTS: int = 2400000
const ATM_RESTOCK_EVERY_DAYS: int = 3

## Orders and shipments go in standard straps: 100 $100 notes, $10,000.
const STRAP_CENTS: int = 1000000

## The NPC branch manager acts one strap inside the limits, because its
## forecast leaves out tomorrow's staff windows, whose day's net cash runs to
## a few thousand dollars either way.
const NPC_BUFFER_CENTS: int = STRAP_CENTS

# --- the armored truck -----------------------------------------------------------

## How an armored truck visit was handled, for grading and the Regional
## review: right; cash delayed (a good bag or a genuine crew refused, or the
## visit missed); a problem bag signed for; cash handled with an unscheduled
## crew.
enum ShipmentVerdict { CORRECT, DELAY, SERIOUS, CRITICAL }
## What's wrong with a delivered bag.
enum BagProblem { NONE, BROKEN_SEAL, SEAL_MISMATCH, MISSING }
## The day's visit: built, crew in the branch, done, or gone (missed or
## refused). A save made while the crew is in the branch loads as BUILT, so
## the same crew comes back.
enum VisitState { BUILT, ARRIVED, DONE, LEFT }

## Bags hold up to five straps.
const BAG_MAX_CENTS: int = 5 * STRAP_CENTS
## About 1 in 20 visits is a crew that isn't the scheduled one, or doesn't
## match it; about 1 in 10 deliveries has one problem bag, picked by weight.
const FAKE_CREW_CHANCE: float = 1.0 / 20.0
const SHIPMENT_PROBLEM_CHANCE: float = 0.1
const BAG_PROBLEM_WEIGHTS: Dictionary = {
	BagProblem.BROKEN_SEAL: 2,
	BagProblem.SEAL_MISMATCH: 1,
	BagProblem.MISSING: 1,
}
## A broken or swapped seal: the bag holds this share less than declared.
const PROBLEM_SHORTFALL_SHARE: float = 0.2

## The armored carrier, and a look-alike name an unscheduled crew might use.
## Fictional.
const CARRIER: String = "Keystone Armored Transport"
const CARRIER_LOOKALIKE: String = "Keystone Armoured Logistics"
const GUARD_NAMES: Array[String] = [
	"Ray Delgado", "Tom Whitfield", "Andre Collins", "Mike Brannigan",
	"Luis Ortega", "Dana Pruitt", "Glen Hartley", "Curtis Boone",
	"Ivan Sokolov", "Jada Freeman", "Owen McAllister", "Rita Navarro",
]

## The visit's rolls use their own generator (randomized in _ready(); tests
## seed it), with these chances (tests may fix them).
var visit_rng := RandomNumberGenerator.new()
var fake_crew_chance: float = FAKE_CREW_CHANCE
var shipment_problem_chance: float = SHIPMENT_PROBLEM_CHANCE

## Today's armored truck visit ({} when there's none): {"day", "state"
## (VisitState), "fake" (bool), "scheduled" and "presented" ({"company",
## "guards": [{"name", "badge"}, ...]}), "bags" ([{"declared", "manifest_seal",
## "seal", "intact", "missing", "content"}]), "pickup" (cents)}.
var today_visit: Dictionary = {}
## What happened with today's visit, for the End of Day summary ("" for none).
var visit_note: String = ""

const VAULT_LOW_TEXT: String = "Vault low — order cash from the Federal Reserve"
const VAULT_OVER_TEXT: String = "Vault over limit — ship excess cash to the Federal Reserve"

var expected_cents: int = VaultReconciliationScreen.STARTING_VAULT_CENTS

## Orders not yet delivered, oldest first: {"placed_day", "delivery_day",
## "cents"}; cents > 0 is cash coming in, < 0 cash shipped out.
var pending_orders: Array[Dictionary] = []
## The day the last order was placed (one order a day), 0 for none yet.
var last_order_day: int = 0
## Business days that closed with the vault outside its limits.
var out_of_range_days: PackedInt32Array = []
## The last day close_day() ran for (it runs once a day), 0 for none yet.
var last_closed_day: int = 0
## Delivered and shipped today, so far (cents, both positive), for the close.
var delivered_today_cents: int = 0
var shipped_today_cents: int = 0
## The last close's movements (close_day()), kept for the End of Day summary.
var last_close: Dictionary = {}

# --- the teller's transfers ------------------------------------------------------

## The teller sold `cents` of cash to the vault.
func receive_from_drawer(cents: int) -> void:
	if cents <= 0:
		return
	expected_cents += cents
	expected_changed.emit(expected_cents)

## The teller bought `cents` of cash from the vault. Returns false (and
## changes nothing) if the vault doesn't hold that much: it never goes below
## zero.
func pay_to_drawer(cents: int) -> bool:
	if cents <= 0 or cents > expected_cents:
		return false
	expected_cents -= cents
	expected_changed.emit(expected_cents)
	return true

# --- limits -----------------------------------------------------------------------

func is_in_range(cents: int = expected_cents) -> bool:
	return cents >= VAULT_MIN_CENTS and cents <= VAULT_MAX_CENTS

## VAULT_LOW_TEXT, VAULT_OVER_TEXT, or "" within the limits.
func limit_warning() -> String:
	if expected_cents < VAULT_MIN_CENTS:
		return VAULT_LOW_TEXT
	if expected_cents > VAULT_MAX_CENTS:
		return VAULT_OVER_TEXT
	return ""

func is_atm_restock_day(day: int) -> bool:
	return day % ATM_RESTOCK_EVERY_DAYS == 0

# --- orders -------------------------------------------------------------------------

## Whether today's one order has been placed.
func has_ordered(day: int) -> bool:
	return last_order_day == day

## Orders `cents` of cash in (> 0) or ships it out (< 0) on `day`, for
## delivery at opening on day + 1 (the next business day). Returns "" when
## placed, or why not.
func place_order(cents: int, day: int) -> String:
	if cents == 0 or cents % STRAP_CENTS != 0:
		return "Order in whole straps of %s." % MoneyMath.format(STRAP_CENTS, true)
	if has_ordered(day):
		return "Today's cash order is already placed."
	if cents < 0 and -cents > expected_cents - pending_shipments_cents():
		return "The vault doesn't hold %s to ship." % MoneyMath.format(-cents, true)
	pending_orders.append({"placed_day": day, "delivery_day": day + 1, "cents": cents})
	last_order_day = day
	return ""

## Cash already promised to shipments not yet gone (positive cents).
func pending_shipments_cents() -> int:
	var total := 0
	for order in pending_orders:
		var cents: int = order["cents"]
		if cents < 0:
			total -= cents
	return total

## The net of the orders arriving on `day` (cents in minus out).
func arriving_on(day: int) -> int:
	var total := 0
	for order in pending_orders:
		var delivery_day: int = order["delivery_day"]
		if delivery_day == day:
			var cents: int = order["cents"]
			total += cents
	return total

# --- the armored truck visit ---------------------------------------------------------

func _ready() -> void:
	visit_rng.randomize()

## Orders due on `day` or before (rescheduled ones included).
func _due_orders(day: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	for order in pending_orders:
		var delivery_day: int = order["delivery_day"]
		if delivery_day <= day:
			due.append(order)
	return due

## The truck has something to bring or collect on `day`, and today's visit
## isn't over.
func has_visit_due(day: int) -> bool:
	if _due_orders(day).is_empty():
		return false
	return not (SaveGame.int_of(today_visit, "day", 0) == day and SaveGame.int_of(today_visit, "state", VisitState.BUILT) >= VisitState.DONE)

## The visit for `day` (built once, then the same one): the crew scheduled by
## the carrier and the crew who turns up (FAKE_CREW_CHANCE: someone not
## scheduled, the wrong company, or a badge number that doesn't match), the
## delivery split into sealed bags of at most BAG_MAX_CENTS against the
## manifest (SHIPMENT_PROBLEM_CHANCE: one bag with a broken seal, a seal
## number that doesn't match, or missing), and the pickup.
func prepare_visit(day: int) -> Dictionary:
	if SaveGame.int_of(today_visit, "day", 0) == day and not today_visit.is_empty():
		return today_visit
	var delivery := 0
	var pickup := 0
	for order in _due_orders(day):
		var cents: int = order["cents"]
		if cents > 0:
			delivery += cents
		else:
			pickup -= cents
	var names := GUARD_NAMES.duplicate()
	var first: String = names.pop_at(visit_rng.randi_range(0, names.size() - 1))
	var second: String = names.pop_at(visit_rng.randi_range(0, names.size() - 1))
	var scheduled := {"company": CARRIER, "guards": [
		{"name": first, "badge": _badge()},
		{"name": second, "badge": _badge()},
	]}
	var presented: Dictionary = scheduled.duplicate(true)
	var fake := visit_rng.randf() < fake_crew_chance
	if fake:
		var guards: Array = presented["guards"]
		var guard: Dictionary = guards[visit_rng.randi_range(0, 1)]
		match visit_rng.randi_range(0, 2):
			0:
				presented["company"] = CARRIER_LOOKALIKE
			1:
				guard["name"] = names[visit_rng.randi_range(0, names.size() - 1)]
			_:
				guard["badge"] = _badge()
	var bags: Array[Dictionary] = []
	var left := delivery
	while left > 0:
		var declared := mini(left, BAG_MAX_CENTS)
		left -= declared
		var seal := _seal()
		bags.append({"declared": declared, "manifest_seal": seal, "seal": seal, "intact": true, "missing": false, "content": declared})
	if not bags.is_empty() and visit_rng.randf() < shipment_problem_chance:
		_spoil(bags[visit_rng.randi_range(0, bags.size() - 1)], _roll_bag_problem())
	today_visit = {"day": day, "state": VisitState.BUILT, "fake": fake, "scheduled": scheduled, "presented": presented, "bags": bags, "pickup": pickup}
	return today_visit

func _badge() -> String:
	return "KAT-%05d" % visit_rng.randi_range(10000, 99999)

func _seal() -> String:
	return "S-%06d" % visit_rng.randi_range(100000, 999999)

func _roll_bag_problem() -> BagProblem:
	var total := 0
	for weight: int in BAG_PROBLEM_WEIGHTS.values():
		total += weight
	var pick := visit_rng.randi_range(1, total)
	for problem: BagProblem in BAG_PROBLEM_WEIGHTS:
		var weight: int = BAG_PROBLEM_WEIGHTS[problem]
		pick -= weight
		if pick <= 0:
			return problem
	return BagProblem.BROKEN_SEAL

## Makes `bag` show `problem` (tests use it to build each case).
func _spoil(bag: Dictionary, problem: BagProblem) -> void:
	var declared: int = bag["declared"]
	match problem:
		BagProblem.BROKEN_SEAL:
			bag["intact"] = false
			bag["content"] = declared - roundi(declared * PROBLEM_SHORTFALL_SHARE)
		BagProblem.SEAL_MISMATCH:
			var seal: String = bag["manifest_seal"]
			var number := (seal.substr(2).to_int() + 1 + visit_rng.randi_range(0, 8)) % 1000000
			bag["seal"] = "S-%06d" % number
			bag["content"] = declared - roundi(declared * PROBLEM_SHORTFALL_SHARE)
		BagProblem.MISSING:
			bag["missing"] = true
			bag["seal"] = ""
			bag["intact"] = false
			bag["content"] = 0

func bag_problem(bag: Dictionary) -> BagProblem:
	if SaveGame.bool_of(bag, "missing", false):
		return BagProblem.MISSING
	if not SaveGame.bool_of(bag, "intact", false):
		return BagProblem.BROKEN_SEAL
	if SaveGame.string_of(bag, "seal", "") != SaveGame.string_of(bag, "manifest_seal", ""):
		return BagProblem.SEAL_MISMATCH
	return BagProblem.NONE

## The crew in the branch matches the scheduled one exactly.
func crew_matches(visit: Dictionary) -> bool:
	return JSON.stringify(visit["scheduled"]) == JSON.stringify(visit["presented"])

func set_visit_state(state: VisitState) -> void:
	if not today_visit.is_empty():
		today_visit["state"] = state

## The manager's handling of today's visit: whether they accepted the crew,
## and, if so, which bags (by index) they accepted. Applies it: accepted bags
## of a genuine crew reach the vault with what they hold, refused ones are
## re-delivered the next business day, the pickup is handed over; a refused
## crew's shipment is rescheduled for the next business day; an unscheduled
## crew accepted takes the pickup with them and brings nothing real (the
## genuine delivery still comes, the next business day). Returns the outcome:
## {"verdict" (ShipmentVerdict), "fake", "crew_accepted", "good_accepted",
## "good_refused", "bad_accepted", "bad_refused", "credited", "short",
## "redelivery", "pickup", "missed"}.
func complete_visit(crew_accepted: bool, accepted_bags: Array[bool]) -> Dictionary:
	var day: int = today_visit["day"]
	var fake: bool = today_visit["fake"]
	var bags: Array = today_visit["bags"]
	var pickup: int = today_visit["pickup"]
	var outcome := {
		"verdict": ShipmentVerdict.CORRECT, "fake": fake, "crew_accepted": crew_accepted,
		"good_accepted": 0, "good_refused": 0, "bad_accepted": 0, "bad_refused": 0,
		"credited": 0, "short": 0, "redelivery": 0, "pickup": 0, "missed": false,
	}
	var due := _due_orders(day)
	if not crew_accepted:
		_reschedule(due, day + 1)
		outcome["verdict"] = ShipmentVerdict.CORRECT if fake else ShipmentVerdict.DELAY
		visit_note = "Armored truck: crew refused%s; shipment rescheduled for Day %d." % [" (not the scheduled crew)" if fake else "", day + 1]
	elif fake:
		# Their bags are worthless, and the cash handed to them is gone.
		var lost := mini(pickup, expected_cents)
		expected_cents -= lost
		outcome["pickup"] = lost
		var deliveries: Array[Dictionary] = []
		for order in due:
			var cents: int = order["cents"]
			if cents > 0:
				deliveries.append(order)
			else:
				pending_orders.erase(order)
		_reschedule(deliveries, day + 1)
		for bag: Dictionary in bags:
			var declared: int = bag["declared"]
			outcome["short"] += declared
		outcome["verdict"] = ShipmentVerdict.CRITICAL
		visit_note = "Armored truck: cash handled with an unscheduled crew."
	else:
		var redelivery := 0
		for i in bags.size():
			var bag: Dictionary = bags[i]
			var declared: int = bag["declared"]
			var content: int = bag["content"]
			var good := bag_problem(bag) == BagProblem.NONE
			var accept := i < accepted_bags.size() and accepted_bags[i]
			if accept:
				expected_cents += content
				delivered_today_cents += content
				outcome["credited"] += content
				if good:
					outcome["good_accepted"] += 1
				else:
					outcome["bad_accepted"] += 1
					outcome["short"] += declared - content
			else:
				redelivery += declared
				outcome["good_refused" if good else "bad_refused"] += 1
		for order in due:
			pending_orders.erase(order)
		if redelivery > 0:
			pending_orders.append({"placed_day": day, "delivery_day": day + 1, "cents": redelivery})
		var handed := mini(pickup, expected_cents)
		expected_cents -= handed
		shipped_today_cents += handed
		outcome["redelivery"] = redelivery
		outcome["pickup"] = handed
		if SaveGame.int_of(outcome, "bad_accepted", 0) > 0:
			outcome["verdict"] = ShipmentVerdict.SERIOUS
		elif SaveGame.int_of(outcome, "good_refused", 0) > 0:
			outcome["verdict"] = ShipmentVerdict.DELAY
		var parts: PackedStringArray = []
		if not bags.is_empty():
			parts.append("%d of %d bag%s accepted" % [SaveGame.int_of(outcome, "good_accepted", 0) + SaveGame.int_of(outcome, "bad_accepted", 0), bags.size(), "" if bags.size() == 1 else "s"])
		if redelivery > 0:
			parts.append("%s re-delivered on Day %d" % [MoneyMath.format(redelivery, true), day + 1])
		if handed > 0:
			parts.append("%s collected" % MoneyMath.format(handed, true))
		visit_note = "Armored truck: %s." % ", ".join(parts)
	today_visit["state"] = VisitState.DONE
	expected_changed.emit(expected_cents)
	return outcome

## Nobody received the truck in time: the crew leaves and the shipment comes
## the next business day.
func miss_visit(day: int) -> Dictionary:
	prepare_visit(day)
	_reschedule(_due_orders(day), day + 1)
	today_visit["state"] = VisitState.LEFT
	visit_note = "Armored truck: missed; shipment rescheduled for Day %d." % (day + 1)
	return {"verdict": ShipmentVerdict.DELAY, "missed": true}

## The NPC branch manager (before promotion) receives the truck: refuses an
## unscheduled crew, accepts good bags, refuses problem ones, hands over the
## pickup. Never graded.
func npc_handle_visit(day: int) -> Dictionary:
	var visit := prepare_visit(day)
	if not crew_matches(visit):
		return complete_visit(false, [])
	var accepted: Array[bool] = []
	for bag: Dictionary in visit["bags"]:
		accepted.append(bag_problem(bag) == BagProblem.NONE)
	return complete_visit(true, accepted)

func _reschedule(orders: Array[Dictionary], day: int) -> void:
	for order in orders:
		order["delivery_day"] = day

## Where the vault should stand at tomorrow's close (`day` + 1), with what's
## known now: today's orders still to arrive, today's staff net so far and
## today's ATM restock (unless today has closed already), then tomorrow's
## arrivals and restock. Staff windows average out, so tomorrow's aren't
## guessed.
func forecast_for_tomorrow(day: int, staff_net_today_cents: int) -> int:
	var forecast := expected_cents
	if last_closed_day < day:
		for order in pending_orders:
			var delivery_day: int = order["delivery_day"]
			if delivery_day <= day:
				var cents: int = order["cents"]
				forecast += cents
		forecast += staff_net_today_cents
		if is_atm_restock_day(day):
			forecast -= ATM_RESTOCK_CENTS
	forecast += arriving_on(day + 1)
	if is_atm_restock_day(day + 1):
		forecast -= ATM_RESTOCK_CENTS
	return forecast

# --- the day's close ------------------------------------------------------------------

## The business day `day` closes (once; again returns the same figures): a
## truck visit still due is settled (the NPC branch manager receives it, or,
## for a player Branch Manager, it's missed and rescheduled; the room
## normally settles it first, with grading), the staff windows' net
## cash goes in, an ATM restock day takes ATM_RESTOCK_CENTS out (never below
## zero), a close outside the limits is recorded, and, unless the player is
## the Branch Manager (`player_manages`), the NPC branch manager orders for
## tomorrow. Returns the day's movements for the End of Day summary.
func close_day(day: int, staff_net_cents: int, player_manages: bool) -> Dictionary:
	if day <= last_closed_day:
		return last_close
	if has_visit_due(day):
		if player_manages:
			miss_visit(day)
		else:
			npc_handle_visit(day)
	expected_cents += staff_net_cents
	var restock := mini(ATM_RESTOCK_CENTS, expected_cents) if is_atm_restock_day(day) else 0
	expected_cents -= restock
	var in_range := is_in_range()
	if not in_range:
		out_of_range_days.append(day)
	last_closed_day = day
	last_close = {
		"day": day,
		"delivered": delivered_today_cents,
		"shipped": shipped_today_cents,
		"staff_net": staff_net_cents,
		"atm_restock": restock,
		"expected": expected_cents,
		"in_range": in_range,
		"order": {} if player_manages else _npc_order(day),
		"truck": visit_note,
	}
	delivered_today_cents = 0
	shipped_today_cents = 0
	visit_note = ""
	expected_changed.emit(expected_cents)
	return last_close

## The NPC branch manager's rule, at `day`'s close: if tomorrow's forecast is
## below the minimum (with NPC_BUFFER_CENTS to spare), order up to the middle
## of the range; above the maximum (likewise), ship down to it; in whole
## straps, one order a day. Returns the order placed
## ({} for none).
func _npc_order(day: int) -> Dictionary:
	if has_ordered(day):
		return {}
	var forecast := forecast_for_tomorrow(day, 0)
	var cents := 0
	if forecast < VAULT_MIN_CENTS + NPC_BUFFER_CENTS:
		cents = ceili(float(VAULT_MID_CENTS - forecast) / STRAP_CENTS) * STRAP_CENTS
	elif forecast > VAULT_MAX_CENTS - NPC_BUFFER_CENTS:
		var available := expected_cents - pending_shipments_cents()
		cents = -mini(ceili(float(forecast - VAULT_MID_CENTS) / STRAP_CENTS) * STRAP_CENTS, floori(float(available) / STRAP_CENTS) * STRAP_CENTS)
	if cents == 0 or place_order(cents, day) != "":
		return {}
	return pending_orders[-1].duplicate()

# --- career ---------------------------------------------------------------------------

func reset() -> void:
	expected_cents = VaultReconciliationScreen.STARTING_VAULT_CENTS
	pending_orders.clear()
	last_order_day = 0
	out_of_range_days.clear()
	last_closed_day = 0
	delivered_today_cents = 0
	shipped_today_cents = 0
	last_close = {}
	today_visit = {}
	visit_note = ""
	fake_crew_chance = FAKE_CREW_CHANCE
	shipment_problem_chance = SHIPMENT_PROBLEM_CHANCE
	expected_changed.emit(expected_cents)

func save_data() -> Dictionary:
	return {
		"expected_cents": expected_cents,
		"pending_orders": pending_orders.duplicate(true),
		"last_order_day": last_order_day,
		"out_of_range_days": Array(out_of_range_days),
		"last_closed_day": last_closed_day,
		"delivered_today_cents": delivered_today_cents,
		"shipped_today_cents": shipped_today_cents,
		"last_close": last_close.duplicate(true),
		"today_visit": today_visit.duplicate(true),
		"visit_note": visit_note,
	}

## A save from before transfers or orders existed has the starting total and
## nothing pending.
func load_data(data: Dictionary) -> void:
	reset()
	expected_cents = maxi(0, SaveGame.int_of(data, "expected_cents", VaultReconciliationScreen.STARTING_VAULT_CENTS))
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "pending_orders")):
		var cents := SaveGame.int_of(entry, "cents", 0)
		if cents != 0:
			pending_orders.append({
				"placed_day": SaveGame.int_of(entry, "placed_day", 1),
				"delivery_day": SaveGame.int_of(entry, "delivery_day", 1),
				"cents": cents,
			})
	last_order_day = maxi(0, SaveGame.int_of(data, "last_order_day", 0))
	out_of_range_days = SaveGame.ints_of(SaveGame.array_of(data, "out_of_range_days"))
	last_closed_day = maxi(0, SaveGame.int_of(data, "last_closed_day", 0))
	delivered_today_cents = maxi(0, SaveGame.int_of(data, "delivered_today_cents", 0))
	shipped_today_cents = maxi(0, SaveGame.int_of(data, "shipped_today_cents", 0))
	var close := SaveGame.dict_of(data, "last_close")
	if not close.is_empty():
		last_close = {
			"day": SaveGame.int_of(close, "day", 0),
			"delivered": SaveGame.int_of(close, "delivered", 0),
			"shipped": SaveGame.int_of(close, "shipped", 0),
			"staff_net": SaveGame.int_of(close, "staff_net", 0),
			"atm_restock": SaveGame.int_of(close, "atm_restock", 0),
			"expected": SaveGame.int_of(close, "expected", expected_cents),
			"in_range": SaveGame.bool_of(close, "in_range", true),
			"order": _order_of(SaveGame.dict_of(close, "order")),
			"truck": SaveGame.string_of(close, "truck", ""),
		}
	today_visit = _visit_of(SaveGame.dict_of(data, "today_visit"))
	visit_note = SaveGame.string_of(data, "visit_note", "")
	expected_changed.emit(expected_cents)

## A saved visit, read back field by field; a crew that was in the branch when
## it was saved comes back (BUILT). {} if it's missing or damaged.
static func _visit_of(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var bags: Array[Dictionary] = []
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "bags")):
		bags.append({
			"declared": SaveGame.int_of(entry, "declared", 0),
			"manifest_seal": SaveGame.string_of(entry, "manifest_seal", ""),
			"seal": SaveGame.string_of(entry, "seal", ""),
			"intact": SaveGame.bool_of(entry, "intact", true),
			"missing": SaveGame.bool_of(entry, "missing", false),
			"content": SaveGame.int_of(entry, "content", 0),
		})
	var state := SaveGame.int_of(data, "state", VisitState.BUILT)
	if state == VisitState.ARRIVED or state < VisitState.BUILT or state > VisitState.LEFT:
		state = VisitState.BUILT
	return {
		"day": SaveGame.int_of(data, "day", 0),
		"state": state,
		"fake": SaveGame.bool_of(data, "fake", false),
		"scheduled": _crew_of(SaveGame.dict_of(data, "scheduled")),
		"presented": _crew_of(SaveGame.dict_of(data, "presented")),
		"bags": bags,
		"pickup": SaveGame.int_of(data, "pickup", 0),
	}

static func _crew_of(data: Dictionary) -> Dictionary:
	var guards: Array = []
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "guards")):
		guards.append({"name": SaveGame.string_of(entry, "name", ""), "badge": SaveGame.string_of(entry, "badge", "")})
	return {"company": SaveGame.string_of(data, "company", ""), "guards": guards}

static func _order_of(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	return {
		"placed_day": SaveGame.int_of(data, "placed_day", 1),
		"delivery_day": SaveGame.int_of(data, "delivery_day", 1),
		"cents": SaveGame.int_of(data, "cents", 0),
	}
