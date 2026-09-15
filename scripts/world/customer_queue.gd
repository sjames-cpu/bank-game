extends Node2D
class_name CustomerQueue

## Owns the Teller room's customer line (Phase 6a). Spawns a CustomerNPC
## every spawn_interval seconds while a shift is active, walks it to the
## back of the line, and slides everyone forward one slot whenever the
## front customer is served. Each spawn gets a random name, a random
## payment method (Phase 6e), and, per COMPLAINT_CHANCE, either a random
## flavor line (Phase 6b) or a complaint scenario (Phase 6c) — see
## teller_screen.gd for how these are shown and resolved differently.
## Payment method and complaint/dialogue are rolled independently of each
## other.
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
## completes. Pops them and advances everyone else up one slot.
func serve_front_customer() -> void:
	if queue.is_empty():
		return
	var served: CustomerNPC = queue.pop_front()
	served.queue_free()
	_advance_queue()

func _on_spawn_timer_timeout() -> void:
	if queue.size() >= queue_positions.size():
		return
	_spawn_customer()

## Random name + dialogue line are both picked here, once, at spawn — not
## at serve-time — so a customer keeps the same name and line for their
## whole time in queue regardless of how many times the Teller screen is
## opened and closed while they're waiting.
func _spawn_customer() -> void:
	var customer := customer_scene.instantiate() as CustomerNPC
	add_child(customer)
	customer.global_position = spawn_point.global_position
	customer.display_name = CUSTOMER_NAMES.pick_random()
	if randf() < COMPLAINT_CHANCE:
		customer.complaint = _complaint_pool.pick_random()
	else:
		customer.dialogue_line = _dialogue_pool.pick_random()
	customer.payment_method = ShiftTransaction.PaymentMethod.CARD if randf() < CARD_CHANCE else ShiftTransaction.PaymentMethod.CASH
	customer.patience_expired.connect(_on_customer_patience_expired.bind(customer))
	queue.append(customer)
	_advance_queue()

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
