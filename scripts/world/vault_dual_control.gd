extends Node
class_name VaultDualControl

## Dual control for the vault: no vault action happens with one person
## present. When the player starts one at the vault door (a teller's cash
## transfer, or the Branch Manager's vault reconciliation), a second staff
## member is called to the door, and the action opens only once both are
## there (ready_to_open). Afterwards (finish()) they walk back and resume.
##
## Who comes (choose_witness(), from TellerRoom.vault_witness_candidates()):
## - an idle staff member first: in the break room, at a loan desk (no
##   customer line), or at a teller window with nobody being served and an
##   empty line; the nearest to the vault door;
## - otherwise the teller with the shortest line (then the nearest), who
##   finishes the customer at the window first;
## - never anyone walking somewhere already, nor the staff of a closed line.
## Their window pauses while they're away (NpcCustomerLine.paused_for_vault):
## the line keeps its customers, unserved, and patience keeps running. With
## nobody available, NO_ONE_FREE_TEXT and the vault stays shut.
##
## Mid-shift state, never saved. teller_room.gd owns one of these.

enum Purpose { TRANSFER, RECONCILIATION }
enum Phase { IDLE, FINISHING, WALKING_IN, AT_VAULT, OPEN }

const NO_ONE_FREE_TEXT: String = "No one is free to witness the vault right now."
const WAITING_TEXT: String = "Dual control: the vault needs two people. Waiting for %s…"
const NEEDS_TWO_TEXT: String = "Dual control: the vault needs two people."

## Both are at the door: open the vault action for `purpose`.
signal ready_to_open(purpose: Purpose, witness_name: String)
## A witness is back at their desk after `minutes` of game time away.
signal witness_returned(witness_name: String, minutes: float)

## Set by teller_room.gd.
var room: TellerRoom

var phase: Phase = Phase.IDLE
var purpose: Purpose = Purpose.TRANSFER
var witness: StaffNPC = null
## The witness's teller window line (null for loan desk staff), paused while
## they're away.
var witness_line: NpcCustomerLine = null

var _route_in: Array[Vector2] = []
var _origin: Vector2 = Vector2.ZERO
var _origin_state: StaffNPC.State = StaffNPC.State.AT_DESK
var _left_at_minutes: float = 0.0

## Waiting for the witness (not yet open).
func is_waiting() -> bool:
	return phase in [Phase.FINISHING, Phase.WALKING_IN, Phase.AT_VAULT]

func is_busy() -> bool:
	return phase != Phase.IDLE

func waiting_text() -> String:
	return WAITING_TEXT % witness.staff.staff_name if is_instance_valid(witness) else NEEDS_TWO_TEXT

## Calls a witness for `for_purpose`. Returns "" when one is on their way,
## or NO_ONE_FREE_TEXT.
func start(for_purpose: Purpose) -> String:
	if is_busy():
		return ""
	var chosen := choose_witness(room.vault_witness_candidates(), room.vault_door.global_position)
	if chosen.is_empty():
		return NO_ONE_FREE_TEXT
	purpose = for_purpose
	witness = chosen["npc"]
	witness_line = chosen["line"]
	if witness_line != null:
		witness_line.paused_for_vault = true
	phase = Phase.FINISHING
	return ""

## The witness rule (see the class doc). Each candidate is {npc: StaffNPC,
## line: NpcCustomerLine or null}. Returns the chosen one, or {}.
static func choose_witness(candidates: Array[Dictionary], door: Vector2) -> Dictionary:
	var idle: Array[Dictionary] = []
	var busy: Array[Dictionary] = []
	for candidate in candidates:
		var npc: StaffNPC = candidate["npc"]
		var line: NpcCustomerLine = candidate["line"]
		if not is_instance_valid(npc) or not (npc.state == StaffNPC.State.AT_DESK or npc.state == StaffNPC.State.ON_BREAK):
			continue
		if npc.state == StaffNPC.State.ON_BREAK or line == null:
			idle.append(candidate)
		elif not line.active or line.paused_for_vault:
			continue
		elif not line.is_serving() and line.queue.is_empty():
			idle.append(candidate)
		else:
			busy.append(candidate)
	if not idle.is_empty():
		return _nearest(idle, door)
	var shortest: Array[Dictionary] = []
	for candidate in busy:
		var line: NpcCustomerLine = candidate["line"]
		if shortest.is_empty():
			shortest = [candidate]
			continue
		var best: NpcCustomerLine = shortest[0]["line"]
		if line.queue.size() < best.queue.size():
			shortest = [candidate]
		elif line.queue.size() == best.queue.size():
			shortest.append(candidate)
	return _nearest(shortest, door) if not shortest.is_empty() else {}

static func _nearest(candidates: Array[Dictionary], door: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var npc: StaffNPC = candidate["npc"]
		var distance := npc.global_position.distance_to(door)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _process(_delta: float) -> void:
	if phase == Phase.IDLE:
		return
	if not is_instance_valid(witness):
		_reset()
		return
	# The player walked away before the vault opened: the call is off.
	if is_waiting() and not room.vault_door.player_in_range:
		cancel()
		return
	match phase:
		Phase.FINISHING:
			if witness_line == null or not witness_line.is_serving():
				_walk_in()
		Phase.AT_VAULT:
			phase = Phase.OPEN
			ready_to_open.emit(purpose, witness.staff.staff_name)

func _walk_in() -> void:
	_origin = witness.global_position
	_origin_state = witness.state
	_route_in = room.route_to_vault(witness)
	_left_at_minutes = GameClock.minutes
	witness.say("Coming to the vault.")
	witness.follow_route(_route_in, StaffNPC.State.AT_VAULT)
	witness.route_finished.connect(_on_arrived, CONNECT_ONE_SHOT)
	phase = Phase.WALKING_IN

func _on_arrived() -> void:
	if phase == Phase.WALKING_IN:
		phase = Phase.AT_VAULT

## The vault action is over (its screen closed): the witness walks back.
func finish() -> void:
	if phase == Phase.OPEN:
		_walk_back()

## Called off before the vault opened.
func cancel() -> void:
	if phase == Phase.FINISHING:
		if witness_line != null:
			witness_line.paused_for_vault = false
		_reset()
	elif phase in [Phase.WALKING_IN, Phase.AT_VAULT]:
		_walk_back()

## Back along the part of the route they walked, to where they came from.
## The controller is free for the next action at once; the walk back runs
## on its own.
func _walk_back() -> void:
	if witness.route_finished.is_connected(_on_arrived):
		witness.route_finished.disconnect(_on_arrived)
	var reached := mini(witness.waypoints_reached, _route_in.size()) if witness.state == StaffNPC.State.WALKING else _route_in.size()
	var back := _route_in.slice(0, reached)
	back.reverse()
	if reached == _route_in.size() and not back.is_empty():
		back.remove_at(0) # standing there
	back.append(_origin)
	var returning := witness
	returning.follow_route(back, _origin_state)
	returning.route_finished.connect(_on_returned.bind(returning, witness_line, _left_at_minutes), CONNECT_ONE_SHOT)
	_reset()

func _on_returned(returning: StaffNPC, line: NpcCustomerLine, left_at_minutes: float) -> void:
	if is_instance_valid(line):
		line.paused_for_vault = false
	if is_instance_valid(returning):
		witness_returned.emit(returning.staff.staff_name, maxf(0.0, GameClock.minutes - left_at_minutes))

func _reset() -> void:
	phase = Phase.IDLE
	witness = null
	witness_line = null
	_route_in = []
