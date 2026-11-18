extends Node
class_name RegionalVisitSlot

## The Regional Manager's visit on the time-slot day (decision 13): on a
## review day they walk in from the entrance when
## DaySchedule.REGIONAL_VISIT_SLOT (11 AM) starts, stand outside the
## Manager's Office, and walk out when it ends or is skipped. They never
## hold the slot. The review itself runs at End of Day, which also ends any
## visit still under way (TellerRoom.show_end_of_day() calls end_visit()).
## Placed in the room by SlotWiring.

## Entrance -> up the aisle beside the lounge -> outside the Manager's
## Office door (columns 9-10), facing it.
const VISIT_ENTRANCE: Vector2 = Vector2(384, 690)
const VISIT_ROUTE: Array[Vector2] = [Vector2(384, 330), Vector2(320, 330), Vector2(320, 290)]
const VISIT_GREETING: String = "Just here to observe. Carry on."

var room: TellerRoom

## The visiting Regional Manager (null when not here).
var visitor: StaffNPC = null
var _leaving: bool = false
## The day they last came, so they don't come back once they've left.
var _visit_day: int = 0

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_ended.connect(_on_slot_over)
	DayFlow.slot_skipped.connect(_on_slot_over)

## The autoloads outlive the room: let go of them with it.
func _exit_tree() -> void:
	DayFlow.slot_started.disconnect(_on_slot_started)
	DayFlow.slot_ended.disconnect(_on_slot_over)
	DayFlow.slot_skipped.disconnect(_on_slot_over)

func _on_slot_started(slot: DaySlot) -> void:
	if slot.id != DaySchedule.REGIONAL_VISIT_SLOT:
		return
	if RegionalManager.is_review_day() and not done_today() and not is_instance_valid(visitor):
		start_visit()

func _on_slot_over(slot: DaySlot) -> void:
	if slot.id == DaySchedule.REGIONAL_VISIT_SLOT:
		send_out()

## Whether the Regional Manager has come today already.
func done_today() -> bool:
	return _visit_day == BusinessDay.stats_day

## On their way out.
func is_leaving() -> bool:
	return _leaving

func start_visit() -> void:
	_visit_day = BusinessDay.stats_day
	_leaving = false
	var member := StaffMember.new()
	member.staff_name = RegionalManager.SENDER
	member.look = StaffLooks.REGIONAL_MANAGER_LOOK
	visitor = room.STAFF_NPC_SCENE.instantiate()
	visitor.setup(member)
	visitor.name = "RegionalManagerVisitor"
	room.staff_layer.add_child(visitor)
	visitor.place_at(VISIT_ENTRANCE, StaffNPC.State.ON_BREAK)
	visitor.follow_route(VISIT_ROUTE, StaffNPC.State.ON_BREAK)
	visitor.route_finished.connect(visitor.say.bind(VISIT_GREETING, 4.0), CONNECT_ONE_SHOT)

## The visitor walks out the way they came, and is gone at the entrance.
func send_out() -> void:
	if not is_instance_valid(visitor) or _leaving:
		return
	_leaving = true
	var route: Array[Vector2] = VISIT_ROUTE.duplicate()
	route.reverse()
	route.remove_at(0) # standing there
	route.append(VISIT_ENTRANCE)
	visitor.follow_route(route, StaffNPC.State.ON_BREAK)
	visitor.route_finished.connect(end_visit, CONNECT_ONE_SHOT)

## The visitor leaves the room (walked out, or the day ended).
func end_visit() -> void:
	# queue_free only: this can run from the visitor's own route_finished.
	if is_instance_valid(visitor):
		visitor.queue_free()
	visitor = null
	_leaving = false
