extends Node2D
class_name CustomerQueue

## Owns the Teller room's customer line (Phase 6a). Spawns a CustomerNPC
## every spawn_interval seconds while a shift is active, walks it to the
## back of the line, and slides everyone forward one slot whenever the
## front customer is served. Each spawn gets a random name, their own
## Account (Phase 6h, see _get_or_create_customer_account()), a random
## payment method (Phase 6e), and, per COMPLAINT_CHANCE, either a stated
## Deposit/Withdraw request (Phase 6h, see _assign_transaction_intent())
## or a complaint scenario (Phase 6c) — see teller_screen.gd for how these
## are shown and resolved differently. Payment method and complaint/intent
## are rolled independently of each other.
##
## Queue capacity is however many QueuePositions markers exist in the
## scene, so the line length can be tuned by adding/removing markers in
## the .tscn without touching this script.
##
## teller_room.gd drives start_shift()/end_shift() off TellerScreen's
## clock-in/clock-out, and get_front_customer()/serve_front_customer() off
## the desk interaction — see there for how "serving" is decided.

@export var customer_scene: PackedScene
@export var spawn_interval: float = 20.0

## Phase 6c: chance a newly spawned customer presents a complaint (see
## CustomerComplaintsData) instead of a regular 6b flavor line. Doesn't
## touch spawn timing itself — just which dialogue a spawned customer
## gets handed below.
const COMPLAINT_CHANCE: float = 0.2

## Phase 6e: chance a newly spawned customer pays by card instead of cash
## (see teller_screen.gd for how the two flows differ). Rolled
## independently of COMPLAINT_CHANCE above — a customer's payment method
## has nothing to do with whether they have a complaint.
const CARD_CHANCE: float = 0.5

## Phase 6h: starting balance range for a customer's own Account, created
## (or reused, see _get_or_create_customer_account()) the moment they spawn.
const CUSTOMER_ACCOUNT_MIN_BALANCE: float = 200.0
const CUSTOMER_ACCOUNT_MAX_BALANCE: float = 2000.0

## Phase 6h: range a non-complaint customer's stated Deposit/Withdraw
## request is drawn from (see _assign_transaction_intent()). A withdrawal
## is additionally capped at the customer's own account balance, so the
## upper bound here is just "reasonable," not a guarantee.
const INTENT_MIN_AMOUNT: float = 20.0
const INTENT_MAX_AMOUNT: float = 500.0

## Caps how many customers can spawn in a single shift, independent of
## queue_positions.size() (which caps how many can be in line at once).
## 4 is a middle-of-the-road pick within the requested 3-5 range — enough
## to keep a shift busy without letting the queue backlog indefinitely on
## a slow player.
const CUSTOMERS_PER_SHIFT_CAP: int = 4

## Phase 6g: emitted when a queued customer's patience runs out (see
## CustomerNPC.patience_expired) and they're removed from the line unserved.
## teller_room.gd listens for this to apply the Reputation penalty and log
## the event to HistoryManager — this script only owns the queue mechanics
## (removing them, advancing everyone else), not the consequence.
signal customer_abandoned(customer: CustomerNPC)

## Names aren't guaranteed unique, matching Account.customer_name's own
## "customer names aren't guaranteed unique" caveat (see teller_screen.gd) —
## real people share names, and nothing here keys off a customer's name.
const CUSTOMER_NAMES: Array[String] = [
	"Alex Rivera", "Sam Chen", "Jordan Blake", "Taylor Morgan",
	"Casey Nguyen", "Morgan Lee", "Riley Patel", "Avery Kim",
	"Jamie Fischer", "Drew Sanders",
]

@onready var spawn_point: Marker2D = $SpawnPoint
@onready var queue_positions: Array[Marker2D] = _collect_queue_positions()
@onready var spawn_timer: Timer = $SpawnTimer

## Built once rather than re-fetched from CustomerDialogueData on every
## spawn — the pool itself never changes, only which line gets picked.
var _dialogue_pool: Array[CustomerDialogueLine] = CustomerDialogueData.get_lines()

## Same reasoning as _dialogue_pool above, just for the 6c complaint pool.
var _complaint_pool: Array[CustomerComplaint] = CustomerComplaintsData.get_complaints()

var queue: Array[CustomerNPC] = []

## Reset in start_shift() so each shift gets its own fresh cap.
var _customers_spawned_this_shift: int = 0

func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.one_shot = false
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func _collect_queue_positions() -> Array[Marker2D]:
	var positions: Array[Marker2D] = []
	for child in $QueuePositions.get_children():
		positions.append(child as Marker2D)
	return positions

func start_shift() -> void:
	_customers_spawned_this_shift = 0
	spawn_timer.start()

## Clock-out just clears the line rather than preserving it across shifts —
## queue persistence isn't a Phase 6a concern (see requirements doc).
func end_shift() -> void:
	spawn_timer.stop()
	for customer in queue:
		customer.queue_free()
	queue.clear()

func get_front_customer() -> CustomerNPC:
	if queue.is_empty():
		return null
	return queue[0]

## Called once the desk interaction that was serving the front customer
## completes. Pops them and advances everyone else up one slot immediately
## — queue advancement doesn't wait on anything below.
##
## Phase 6i: returns the served customer instead of freeing them here — the
## node's lifetime is now owned by their own farewell + walk-away sequence
## (see send_customer_off()), which teller_room.gd triggers once the Teller
## screen actually closes, not at the instant the transaction completes.
func serve_front_customer() -> CustomerNPC:
	if queue.is_empty():
		return null
	var served: CustomerNPC = queue.pop_front()
	_advance_queue()
	return served

## Phase 6i: hands a served customer off to say_farewell_and_leave(), sending
## them back out toward spawn_point — the reverse of the walk_to() call that
## brought them into the queue in _spawn_customer(). Called by teller_room.gd
## once the Teller screen closes for a visit that served this customer; by
## then they're already out of `queue` (see serve_front_customer() above), so
## this runs entirely in the background and never delays anyone still in line.
func send_customer_off(customer: CustomerNPC) -> void:
	customer.say_farewell_and_leave(spawn_point.global_position)

func _on_spawn_timer_timeout() -> void:
	if queue.size() >= queue_positions.size():
		return
	if _customers_spawned_this_shift >= CUSTOMERS_PER_SHIFT_CAP:
		return
	_spawn_customer()

## Random name + account + dialogue/intent are all picked here, once, at
## spawn — not at serve-time — so a customer keeps the same name, account,
## and stated request for their whole time in queue regardless of how many
## times the Teller screen is opened and closed while they're waiting.
func _spawn_customer() -> void:
	var customer := customer_scene.instantiate() as CustomerNPC
	add_child(customer)
	customer.global_position = spawn_point.global_position
	customer.display_name = CUSTOMER_NAMES.pick_random()
	customer.account = _get_or_create_customer_account(customer.display_name)
	if randf() < COMPLAINT_CHANCE:
		customer.complaint = _complaint_pool.pick_random()
	else:
		_assign_transaction_intent(customer)
	customer.payment_method = ShiftTransaction.PaymentMethod.CARD if randf() < CARD_CHANCE else ShiftTransaction.PaymentMethod.CASH
	customer.patience_expired.connect(_on_customer_patience_expired.bind(customer))
	queue.append(customer)
	_customers_spawned_this_shift += 1
	_advance_queue()

## Phase 6h: reused by name if this customer has already banked here before
## (names aren't guaranteed unique — see AccountManager.find_account_by_name()
## — so this deliberately reuses rather than creating a duplicate account for
## a repeat name), otherwise a fresh Account is opened with a random starting
## balance. This is what lets teller_screen.gd select THIS customer's own
## account instead of the shared demo one once they're served.
##
## Phase 6j: a freshly-created account is flagged is_customer_account so it
## stays out of the Teller screen's general dropdown (see AccountManager.
## get_browsable_accounts()) — an existing match keeps whatever flag it
## already had, so a name that happens to collide with a player-opened
## account never gets wrongly hidden from that dropdown.
func _get_or_create_customer_account(customer_name: String) -> Account:
	var existing := AccountManager.find_account_by_name(customer_name)
	if existing != null:
		return existing
	var new_account := AccountManager.create_account(customer_name, randf_range(CUSTOMER_ACCOUNT_MIN_BALANCE, CUSTOMER_ACCOUNT_MAX_BALANCE))
	new_account.is_customer_account = true
	return new_account

## Regular (non-complaint) customers state a specific Deposit/Withdraw
## request instead of a pure flavor line. A withdrawal request never
## exceeds the customer's own account balance — falling back to a deposit
## request if their balance is below INTENT_MIN_AMOUNT — so the stated
## request is always one the account could actually satisfy.
func _assign_transaction_intent(customer: CustomerNPC) -> void:
	var intent_type := ShiftTransaction.Type.WITHDRAWAL if randf() < 0.5 else ShiftTransaction.Type.DEPOSIT
	if intent_type == ShiftTransaction.Type.WITHDRAWAL and customer.account.balance < INTENT_MIN_AMOUNT:
		intent_type = ShiftTransaction.Type.DEPOSIT

	var max_amount := INTENT_MAX_AMOUNT
	if intent_type == ShiftTransaction.Type.WITHDRAWAL:
		max_amount = minf(INTENT_MAX_AMOUNT, customer.account.balance)

	## Rounded to the nearest $10 so the stated amount reads like something
	## a person would actually say ("$150", not "$147.32"), then clamped
	## back inside range in case rounding nudged it past max_amount.
	var amount := roundf(randf_range(INTENT_MIN_AMOUNT, max_amount) / 10.0) * 10.0
	amount = clampf(amount, INTENT_MIN_AMOUNT, max_amount)

	customer.intent_type = intent_type
	customer.intent_amount = amount
	customer.dialogue_line = _build_intent_dialogue_line(intent_type, amount)

## Builds the stated-request sentence as a CustomerDialogueLine (the same
## resource teller_screen.gd already knows how to display) so no separate
## display path is needed there — this just constructs one dynamically
## instead of picking a static one from _dialogue_pool. A short personality
## line is still appended when there's room, per Requirement 2, pulled from
## the same flavor pool the old generic-only dialogue used.
func _build_intent_dialogue_line(intent_type: ShiftTransaction.Type, amount: float) -> CustomerDialogueLine:
	var line := CustomerDialogueLine.new()
	if intent_type == ShiftTransaction.Type.DEPOSIT:
		line.text = "I'd like to deposit $%.0f." % amount
	else:
		line.text = "I need to withdraw $%.0f." % amount

	var flavor: CustomerDialogueLine = _dialogue_pool.pick_random()
	line.text += " " + flavor.text
	line.mood = flavor.mood
	return line

func _advance_queue() -> void:
	for i in queue.size():
		queue[i].walk_to(queue_positions[i].global_position)

## Same "pop + advance" shape serve_front_customer() uses, except this can
## remove a customer from anywhere in the line (whoever's patience ran out
## first, which in practice is always whoever's been waiting longest, i.e.
## the front) and emits customer_abandoned instead of just freeing silently,
## so teller_room.gd can react before the node is gone.
func _on_customer_patience_expired(customer: CustomerNPC) -> void:
	var index := queue.find(customer)
	if index == -1:
		return
	queue.remove_at(index)
	customer_abandoned.emit(customer)
	customer.queue_free()
	_advance_queue()
