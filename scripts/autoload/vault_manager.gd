extends Node

## Autoload singleton — the branch vault's expected cash, in int cents (B3),
## and its supply chain (part 1: cash levels and ordering; part 2 will add
## the armored truck). Reset with the career (CareerReset) and saved with it
## (see SaveGame).
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
##   back to it (place_order()), arriving at opening on the next business day
##   (receive_deliveries()). Day numbers count business days only, so the next
##   business day is always day + 1, whatever weekend or holiday is between.
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

## Opening on `day`: every order due by then arrives (cash in) or goes (cash
## out; never more than the vault holds). Returns the orders handled.
func receive_deliveries(day: int) -> Array[Dictionary]:
	var handled: Array[Dictionary] = []
	var still_pending: Array[Dictionary] = []
	for order in pending_orders:
		var delivery_day: int = order["delivery_day"]
		if delivery_day > day:
			still_pending.append(order)
			continue
		var cents: int = order["cents"]
		if cents > 0:
			expected_cents += cents
			delivered_today_cents += cents
		else:
			var shipped := mini(-cents, expected_cents)
			expected_cents -= shipped
			shipped_today_cents += shipped
		handled.append(order)
	pending_orders = still_pending
	if not handled.is_empty():
		expected_changed.emit(expected_cents)
	return handled

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

## The business day `day` closes (once; again returns the same figures): any
## order due that wasn't received at opening arrives, the staff windows' net
## cash goes in, an ATM restock day takes ATM_RESTOCK_CENTS out (never below
## zero), a close outside the limits is recorded, and, unless the player is
## the Branch Manager (`player_manages`), the NPC branch manager orders for
## tomorrow. Returns the day's movements for the End of Day summary.
func close_day(day: int, staff_net_cents: int, player_manages: bool) -> Dictionary:
	if day <= last_closed_day:
		return last_close
	receive_deliveries(day)
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
	}
	delivered_today_cents = 0
	shipped_today_cents = 0
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
		}
	expected_changed.emit(expected_cents)

static func _order_of(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	return {
		"placed_day": SaveGame.int_of(data, "placed_day", 1),
		"delivery_day": SaveGame.int_of(data, "delivery_day", 1),
		"cents": SaveGame.int_of(data, "cents", 0),
	}
