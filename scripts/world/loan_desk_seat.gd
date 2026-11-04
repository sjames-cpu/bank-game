extends Node
class_name LoanDeskSeat

## The applicant's seat in front of one loan desk, and the walk to and from
## it (loan applicants: LoanApplicantNPC). One applicant at a time: the next
## comes only once the last has gone, so two never share a seat or a path.
## Each desk has its own route (ROUTES): in up the entrance corridor's left
## lane, along the desk's own row and up to its seat; out down the same row
## and the corridor's right lane, back through the entrance.
##
## Used by the staff loan desks (NpcLoanDeskWorker: walk-ins served in the
## background) and, at Loan Desk 1 while the player works it, by the room
## (TellerRoom: the pile's applicant comes in, the review screen seats them at
## once if they're still walking, and they leave with a reaction after the
## decision). Mid-shift state, never saved.

signal seated(application: LoanApplication)
signal emptied

enum Phase { EMPTY, WALKING_IN, SEATED, LEAVING }

const APPLICANT_SCENE: PackedScene = preload("res://scenes/characters/loan_applicant_npc.tscn")

## The doormat, where applicants appear and leave.
const ENTRANCE: Vector2 = Vector2(384, 690)
## The entrance corridor's lanes (x): in on the left, out on the right.
const LANE_IN_X: float = 376.0
const LANE_OUT_X: float = 392.0
## Per desk: its seat (in front of the desk, facing it) and the row (y) its
## applicants walk along, a different row for each desk.
const SEATS: Dictionary = {
	ScheduleManager.SLOT_LOAN_DESK_1: Vector2(208, 364),
	ScheduleManager.SLOT_LOAN_DESK_2: Vector2(112, 364),
	ScheduleManager.SLOT_LOAN_DESK_3: Vector2(304, 364),
}
const ROWS: Dictionary = {
	ScheduleManager.SLOT_LOAN_DESK_1: 404.0,
	ScheduleManager.SLOT_LOAN_DESK_2: 420.0,
	ScheduleManager.SLOT_LOAN_DESK_3: 436.0,
}

## Below this (y), an applicant walking in is still in the entrance
## corridor, below every desk's row: nobody else starts in until they're past
## it, so two never walk up the corridor together.
const CORRIDOR_TOP_Y: float = 470.0

## Every seat in the room, for the corridor rule (entrance_clear()).
static var _seats: Array[LoanDeskSeat] = []

## Seconds a reaction or purpose line stays up.
const LINE_SECONDS: float = 3.0

var slot_name: String = ScheduleManager.SLOT_LOAN_DESK_1
## Where applicants are added (the room's y-sorted staff layer).
var layer: Node = null
var phase: Phase = Phase.EMPTY
var applicant: LoanApplicantNPC = null
var application: LoanApplication = null

## Picks the purpose and reaction lines (presentation only).
var line_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	line_rng.randomize()
	_seats.append(self)

func _exit_tree() -> void:
	_seats.erase(self)

## Nobody is walking in up the entrance corridor.
static func entrance_clear() -> bool:
	for seat in _seats:
		if seat.phase == Phase.WALKING_IN and is_instance_valid(seat.applicant) and seat.applicant.global_position.y > CORRIDOR_TOP_Y:
			return false
	return true

func seat_position() -> Vector2:
	return SEATS[slot_name]

## In: from the doormat up the corridor's left lane, along this desk's row,
## up to the seat.
func route_in() -> Array[Vector2]:
	var seat := seat_position()
	var row: float = ROWS[slot_name]
	return [Vector2(LANE_IN_X, ENTRANCE.y), Vector2(LANE_IN_X, row), Vector2(seat.x, row), seat]

## Out: down to this desk's row, along it to the corridor's right lane, down
## to the doormat.
func route_out() -> Array[Vector2]:
	var seat := seat_position()
	var row: float = ROWS[slot_name]
	return [Vector2(seat.x, row), Vector2(LANE_OUT_X, row), Vector2(LANE_OUT_X, ENTRANCE.y), ENTRANCE]

func is_empty() -> bool:
	return phase == Phase.EMPTY

func is_seated() -> bool:
	return phase == Phase.SEATED

## `for_application` walks in from the entrance to the seat, when the seat
## is empty and the entrance corridor clear (or `now`: the review screen
## needs them, and seats them at once). Returns whether they came.
func arrive(for_application: LoanApplication, now: bool = false) -> bool:
	if phase != Phase.EMPTY or layer == null:
		return false
	if not now and not entrance_clear():
		return false
	application = for_application
	applicant = APPLICANT_SCENE.instantiate()
	applicant.set_look(for_application.applicant_look)
	applicant.name = "LoanApplicant"
	layer.add_child(applicant)
	applicant.place_at(ENTRANCE, StaffNPC.State.WALKING)
	applicant.follow_route(route_in(), StaffNPC.State.ON_BREAK)
	applicant.route_finished.connect(_on_arrived, CONNECT_ONE_SHOT)
	phase = Phase.WALKING_IN
	if now:
		seat_now()
	return true

## Seated at once (the review screen opened before they got there).
func seat_now() -> void:
	if phase == Phase.WALKING_IN and is_instance_valid(applicant):
		applicant.finish_route()

func _on_arrived() -> void:
	if phase != Phase.WALKING_IN:
		return
	phase = Phase.SEATED
	applicant.say(LoanApplicantNPC.purpose_line(application.loan_purpose, line_rng.randi()), LINE_SECONDS)
	seated.emit(application)

## The applicant says `line` and walks out; the seat is empty once they've
## gone.
func send_off(line: String) -> void:
	if phase == Phase.EMPTY or phase == Phase.LEAVING or not is_instance_valid(applicant):
		return
	if phase == Phase.WALKING_IN and applicant.route_finished.is_connected(_on_arrived):
		applicant.route_finished.disconnect(_on_arrived)
	phase = Phase.LEAVING
	if line != "":
		applicant.say(line, LINE_SECONDS)
	# From wherever they are, onto this desk's row and out.
	applicant.follow_route(route_out(), StaffNPC.State.ON_BREAK)
	applicant.route_finished.connect(_on_left, CONNECT_ONE_SHOT)

## Reacts to `decided`'s decision and leaves.
func send_off_after_decision(decided: LoanApplication) -> void:
	send_off(LoanApplicantNPC.reaction_line(decided, line_rng.randi()))

## The walk out skipped (tests, and a new applicant the review screen needs
## seated now).
func finish_leaving() -> void:
	if phase == Phase.LEAVING and is_instance_valid(applicant):
		applicant.finish_route()

func _on_left() -> void:
	clear()

## Gone at once (going home, a new day, the room closing).
func clear() -> void:
	if is_instance_valid(applicant):
		applicant.queue_free()
	applicant = null
	application = null
	var was_empty := phase == Phase.EMPTY
	phase = Phase.EMPTY
	if not was_empty:
		emptied.emit()
