extends Node
class_name ArmoredTruckVisit

## The armored truck's visit to the branch (part 2 of the cash supply): on a
## day with cash to deliver or collect (VaultManager.has_visit_due()), a crew
## of two guards (StaffLooks.GUARD_LOOKS) walks in from the entrance at
## ARRIVAL_MINUTES and waits by the vault door.
## - Before promotion the NPC branch manager receives them as they arrive
##   (VaultManager.npc_handle_visit()) and they leave.
## - A player Branch Manager receives them at the vault door under dual
##   control (teller_room.gd: the vault door's ARMORED purpose, then
##   ArmoredTruckScreen). If nobody has started that within WAIT_MINUTES,
##   the crew leaves and the shipment is rescheduled for the next business
##   day (VaultManager.miss_visit(), graded as a delay).
## Mid-shift state: the crew isn't saved (a visit saved while they were here
## loads as BUILT, and they come back if there's still time).

## 10:30 AM: a carrier's mid-morning stop, after the opening rush and the
## morning counts and before the lunch-time queues.
const ARRIVAL_MINUTES: float = 10.0 * 60.0 + 30.0
## They wait 45 game minutes (30 seconds of unpaused play; open screens stop
## the clock) and leave at 11:15 AM. A real stop is tighter, but the manager
## has to notice, walk to the vault and get a witness there.
const WAIT_MINUTES: float = 45.0

## In from the entrance, up the aisle beside the lounge, along the aisle
## behind the desks, straight up through the vault's door gap and into the
## room, then to a spot each (a diagonal out of the gap would catch the
## wall's corner).
const ENTRANCE: Vector2 = Vector2(384, 690)
const ROUTE_IN: Array[Vector2] = [Vector2(384, 288), Vector2(112, 288), Vector2(112, 232), Vector2(112, 206)]
const GUARD_SPOTS: Array[Vector2] = [Vector2(88, 206), Vector2(136, 206)]

const ARRIVED_TEXT: String = "The armored truck crew is at the vault door. As Branch Manager, receive them there with a witness before %s."

## Missing the truck costs as much as refusing a good bag (ArmoredTruckScreen).
const MISSED_SCORE: int = -3

enum Phase { IDLE, WALKING_IN, WAITING, BEING_RECEIVED, LEAVING }

signal crew_arrived

var room: TellerRoom
var phase: Phase = Phase.IDLE
var guards: Array[StaffNPC] = []
var _arrived: int = 0

func _process(_delta: float) -> void:
	_drop_freed()
	match phase:
		Phase.IDLE:
			if _should_arrive():
				_arrive()
		Phase.WAITING:
			if GameClock.minutes >= ARRIVAL_MINUTES + WAIT_MINUTES or BusinessDay.is_day_over():
				miss()

func _should_arrive() -> bool:
	var day := GameClock.day
	if BusinessDay.is_day_over() or not VaultManager.has_visit_due(day):
		return false
	return GameClock.minutes >= ARRIVAL_MINUTES and GameClock.minutes < ARRIVAL_MINUTES + WAIT_MINUTES

## The crew is waiting at the vault door for the Branch Manager.
func is_waiting() -> bool:
	return phase == Phase.WAITING

func _arrive() -> void:
	var visit := VaultManager.prepare_visit(GameClock.day)
	VaultManager.set_visit_state(VaultManager.VisitState.ARRIVED)
	var presented: Dictionary = visit["presented"]
	var crew: Array = presented["guards"]
	_arrived = 0
	for i in 2:
		var member := StaffMember.new()
		var guard: Dictionary = crew[i]
		member.staff_name = guard["name"]
		member.look = StaffLooks.GUARD_LOOKS[i]
		var npc: StaffNPC = room.STAFF_NPC_SCENE.instantiate()
		npc.setup(member)
		npc.name = "ArmoredGuard%d" % (i + 1)
		room.staff_layer.add_child(npc)
		# Side by side on the doormat (below it is the solid sidewalk).
		npc.place_at(ENTRANCE + Vector2(24 * i, 0), StaffNPC.State.ON_BREAK)
		var route: Array[Vector2] = ROUTE_IN.duplicate()
		route.append(GUARD_SPOTS[i])
		npc.follow_route(route, StaffNPC.State.ON_BREAK)
		npc.route_finished.connect(_on_guard_arrived, CONNECT_ONE_SHOT)
		guards.append(npc)
	phase = Phase.WALKING_IN

## Both guards at the vault door: the NPC branch manager receives them at
## once; a player Branch Manager is told they're here.
func _on_guard_arrived() -> void:
	_arrived += 1
	if _arrived < guards.size() or phase != Phase.WALKING_IN:
		return
	phase = Phase.WAITING
	crew_arrived.emit()
	if not XPManager.is_branch_manager_unlocked:
		VaultManager.npc_handle_visit(GameClock.day)
		guards[0].say("All signed. Thanks!", 2.5)
		leave()
	else:
		room.show_timed_notice(ARRIVED_TEXT % GameClock.format_time(ARRIVAL_MINUTES + WAIT_MINUTES), 6.0)

## The Branch Manager has started receiving them at the vault door.
func begin_receiving() -> void:
	if phase == Phase.WAITING:
		phase = Phase.BEING_RECEIVED

## Receiving fell through before the screen opened (the witness call was
## called off): they wait again, if there's still time.
func resume_waiting() -> void:
	if phase == Phase.BEING_RECEIVED:
		phase = Phase.WAITING

## Nobody came in time: graded as a delay for a Branch Manager, the shipment
## rescheduled, and the crew leaves.
func miss() -> void:
	var outcome := VaultManager.miss_visit(GameClock.day)
	if XPManager.is_branch_manager_unlocked:
		grade_missed(outcome)
	leave()

static func grade_missed(outcome: Dictionary) -> void:
	ScoreManager.add_shift_score(MISSED_SCORE)
	RegionalManager.note_shipment(SaveGame.int_of(outcome, "verdict", VaultManager.ShipmentVerdict.DELAY))
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Armored truck missed: nobody received the crew in time; shipment rescheduled", "Delay")

## Out the way they came, then gone.
func leave() -> void:
	phase = Phase.LEAVING
	for i in guards.size():
		var npc := guards[i]
		if not is_instance_valid(npc):
			continue
		var route: Array[Vector2] = ROUTE_IN.duplicate()
		route.reverse()
		route.append(ENTRANCE)
		npc.follow_route(route, StaffNPC.State.ON_BREAK)
		npc.route_finished.connect(npc.queue_free, CONNECT_ONE_SHOT)

## Everyone's gone (going home, a new day): no crew left in the room.
func clear() -> void:
	for npc in guards:
		if is_instance_valid(npc):
			npc.queue_free()
	guards.clear()
	phase = Phase.IDLE

func _drop_freed() -> void:
	if guards.is_empty():
		return
	var still: Array[StaffNPC] = []
	for npc: Variant in guards:
		if is_instance_valid(npc):
			var guard: StaffNPC = npc
			if not guard.is_queued_for_deletion():
				still.append(guard)
	guards = still
	if guards.is_empty() and phase == Phase.LEAVING:
		phase = Phase.IDLE

## Before the End of Day summary: a visit still due today is settled now, a
## missed one graded (VaultManager.close_day() would settle it ungraded).
func settle_day() -> void:
	var day := BusinessDay.stats_day
	if VaultManager.has_visit_due(day):
		if XPManager.is_branch_manager_unlocked:
			var outcome := VaultManager.miss_visit(day)
			grade_missed(outcome)
		else:
			VaultManager.npc_handle_visit(day)
	clear()
