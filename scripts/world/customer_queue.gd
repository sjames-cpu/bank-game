extends Node2D
class_name CustomerQueue

## Owns the Teller room's customer line (Phase 6a). Spawns a CustomerNPC
## every spawn_interval seconds while a shift is active, walks it to the
## back of the line, and slides everyone forward one slot whenever the
## front customer is served. Deliberately dumb — no dialogue, no
## patience/complaints (6b/6c) — customers are silent queue slots with a
## walk animation until a later phase gives them more to do.
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

@onready var spawn_point: Marker2D = $SpawnPoint
@onready var queue_positions: Array[Marker2D] = _collect_queue_positions()
@onready var spawn_timer: Timer = $SpawnTimer

var queue: Array[CustomerNPC] = []
var _next_customer_number: int = 1

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

func _spawn_customer() -> void:
	var customer := customer_scene.instantiate() as CustomerNPC
	add_child(customer)
	customer.global_position = spawn_point.global_position
	customer.display_name = "Customer #%d" % _next_customer_number
	_next_customer_number += 1
	queue.append(customer)
	_advance_queue()

func _advance_queue() -> void:
	for i in queue.size():
		queue[i].walk_to(queue_positions[i].global_position)
