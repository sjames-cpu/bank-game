extends Node2D

## Root of the room. Listens for signals from interactable objects
## in the scene and decides what should happen.
##
## The Loan Officer desk (Phase 4f) lives in this same room rather than a
## separate scene — the room already has the tilemap/player/camera setup
## a new room would just duplicate, and there's no door/transition system
## yet to justify a second area. It's additive alongside the existing
## Teller desk/screen wiring below, not a change to it.
##
## LoanOfficerDesk starts non-monitoring (see teller_room.tscn) since the
## role isn't available to the player until XPManager.is_loan_officer_unlocked
## — reacting to that unlock here (rather than polling it, or having the
## desk script know about XPManager itself) makes the desk usable the
## moment it's earned. The desk itself is always visible: it's the branch's
## Loan Desk, worked by a staff member until the player can work it.
##
## The branch has three teller windows: the player's own Player Teller
## Window (the TellerDesk node — interaction + the player's CustomerQueue
## line, never staffed) and Teller Windows 1 and 2, always worked by staff.
## After promotion to Branch Manager the Player Teller Window becomes the
## staffed "Teller Window 3" (Window3Line on the same lane) and the Loan
## Desk's staff member stays put; both desks then only show a short notice
## (see _apply_branch_manager_desks()).
##
## Staff (NPC coworkers): each staffed desk — Teller Window 1, Teller
## Window 2, the Loan Desk — gets the StaffNPC that ScheduleManager assigns
## to it, standing at the desk's StaffSpot marker; the two teller windows
## serve their own NpcCustomerLines continuously. While the player is
## clocked in at the Loan Desk, its staff member walks to the break room
## (StaffBreakArea) and walks back on clock-out. The Staff layer sits under
## the desks in draw order (staff always stand behind a counter, so the
## counter correctly overlaps them) and is y-sorted among themselves.
##
## BranchManagerDesk (Phase 5f) follows the exact same pattern one tier up
## — hidden/non-monitoring until XPManager.is_branch_manager_unlocked,
## revealed reactively off XPManager.branch_manager_unlocked. Additive
## alongside the Teller/Loan Officer wiring above, not a change to it.
##
## TEMP: DEBUG_UNLOCK_KEY (F1) is a testing shortcut so the Branch Manager
## desk/shift loop can be exercised without grinding real shifts up to
## XP_UNLOCK_THRESHOLD_BRANCH_MANAGER — remove this once there's a real
## way to reach that threshold through normal play testing (or gate it
## behind a debug-build check).
##
## Phase 6a adds the customer queue: TellerScreen's clock-in/clock-out
## signals start/stop CustomerQueue's spawning, and the desk interaction
## remembers which customer was at the front of the line when the screen
## opened (passed to show_screen() so it can display "Serving: X"). That
## customer is only actually popped from the queue once TellerScreen reports
## their request done (customer_request_satisfied), or, for a complaint
## customer, a resolved complaint (complaint_resolved) — not just whenever
## the screen is closed, since closing without doing anything (checking a
## balance, clocking in/out) shouldn't silently drop them from the line. The
## one exception is a customer whose transaction was done wrong and never
## fixed: closing the screen sends them off upset (customer_left_unfixed).
## See _on_teller_desk_interacted and _serve_current_customer.
##
## Phase 6f adds the ATM: unlike the three job desks above, it has no
## availability gating at all — see _on_atm_interacted() — since it's a
## customer-facing feature available regardless of shift/clock-in state,
## not a job role.

const DEBUG_UNLOCK_KEY := KEY_F1

## Name the player's own window is reported to XPManager under while on shift.
const PLAYER_TELLER_WINDOW: String = "Player Teller Window"

## Phase 6g: Reputation penalty when a queued customer abandons the line
## (see CustomerQueue.customer_abandoned). Deliberately smaller in magnitude
## than MAJOR_DISCREPANCY_REPUTATION (-5, teller_screen.gd) since this is a
## systemic pacing issue rather than a direct error the player made, and
## smaller than even a dismissive complaint response (-3,
## customer_complaints_data.gd) for the same reason.
const ABANDONMENT_REPUTATION_PENALTY: int = -2

@onready var teller_screen: TellerScreen = $UI/TellerScreen
@onready var loan_officer_desk: Area2D = $LoanOfficerDesk
@onready var loan_officer_screen: Control = $UI/LoanOfficerScreen
@onready var branch_manager_desk: Area2D = $BranchManagerDesk
@onready var branch_manager_screen: Control = $UI/BranchManagerScreen
@onready var customer_queue: CustomerQueue = $CustomerQueue
@onready var atm: Area2D = $ATM
@onready var atm_screen: ATMScreen = $UI/ATMScreen
@onready var staff_layer: Node2D = $Staff
@onready var staff_break_area: Node2D = $StaffBreakArea
@onready var window1_npc_line: NpcCustomerLine = $Window1NpcLine
@onready var window2_line: NpcCustomerLine = $Window2Line
@onready var window3_line: NpcCustomerLine = $Window3Line
@onready var loan_desk_worker: NpcLoanDeskWorker = $LoanDeskWorker
@onready var desk_notice: Control = $UI/DeskNotice
@onready var desk_notice_label: Label = $UI/DeskNotice/Label

## How long the "X is working this window" notice stays up.
const DESK_NOTICE_SECONDS: float = 3.5
var _desk_notice_token: int = 0

const STAFF_NPC_SCENE: PackedScene = preload("res://scenes/characters/staff_npc.tscn")

## Desk node for each ScheduleManager desk slot; each has a StaffSpot marker.
@onready var _desk_for_slot: Dictionary = {
	ScheduleManager.SLOT_TELLER_WINDOW_1: $TellerWindow1,
	ScheduleManager.SLOT_TELLER_WINDOW_2: $TellerWindow2,
	ScheduleManager.SLOT_TELLER_WINDOW_3: $TellerDesk, # the Player Teller Window, after promotion
	ScheduleManager.SLOT_LOAN_DESK: $LoanOfficerDesk,
}

## slot name -> the StaffNPC currently placed at that desk.
var _staff_by_slot: Dictionary = {}

## Desks the player is currently clocked in at (by slot name) — their staff
## member is on break.
var _player_desk_slots: Array[String] = []

var _customer_being_served: CustomerNPC = null

## Phase 6i: everyone this visit has served, held here until the Teller
## screen actually closes (see _on_teller_screen_closed()) so their
## farewell + walk-away plays at the right moment instead of the instant
## they're served. A list rather than a single slot since the screen now
## moves straight on to the next customer mid-visit (see
## _serve_current_customer()), so one visit can serve several people.
var _customers_awaiting_farewell: Array[CustomerNPC] = []

func _ready() -> void:
	$TellerDesk.interacted.connect(_on_teller_desk_interacted)
	teller_screen.customer_request_satisfied.connect(_on_teller_customer_request_satisfied)
	teller_screen.customer_left_unfixed.connect(_on_teller_customer_left_unfixed)
	teller_screen.screen_closed.connect(_on_teller_screen_closed)
	teller_screen.complaint_resolved.connect(_on_teller_complaint_resolved)
	teller_screen.remaining_shift_work = _describe_remaining_shift_work
	teller_screen.shift_clocked_in.connect(customer_queue.start_shift)
	teller_screen.shift_clocked_out.connect(customer_queue.end_shift)
	teller_screen.shift_clocked_out.connect(_on_teller_shift_clocked_out)
	# A Branch Manager promotion earned mid-shift waits for clock-out.
	teller_screen.shift_clocked_in.connect(XPManager.begin_player_shift.bind(PLAYER_TELLER_WINDOW))
	teller_screen.shift_clocked_out.connect(XPManager.end_player_shift.bind(PLAYER_TELLER_WINDOW))
	customer_queue.customer_abandoned.connect(_on_customer_abandoned)
	loan_officer_desk.interacted.connect(_on_loan_officer_desk_interacted)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)
	_update_loan_officer_desk_availability()

	branch_manager_desk.interacted.connect(_on_branch_manager_desk_interacted)
	branch_manager_screen.shift_clocked_in.connect($UI/DisciplineLetterScreen.show_branch_orientation_once)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	_update_branch_manager_desk_availability()

	atm.interacted.connect(_on_atm_interacted)

	loan_officer_screen.shift_clocked_in.connect(_on_player_clocked_in.bind(ScheduleManager.SLOT_LOAN_DESK))
	loan_officer_screen.shift_clocked_out.connect(_on_player_clocked_out.bind(ScheduleManager.SLOT_LOAN_DESK))
	ScheduleManager.schedule_confirmed.connect(_on_schedule_confirmed)
	_place_staff()

	# Staff serve customers from the start. Both teller-window lines stay on;
	# only the loan worker pauses while the player works the Loan Desk (see
	# _on_player_clocked_in/_out).
	window2_line.activate()
	window1_npc_line.activate()
	loan_desk_worker.active = true
	if XPManager.is_branch_manager_unlocked:
		_apply_branch_manager_desks()

## (Re)creates one StaffNPC per assigned desk from ScheduleManager. A desk
## the player is clocked in at gets its staff member placed straight in the
## break room instead.
func _place_staff() -> void:
	for npc in _staff_by_slot.values():
		staff_layer.remove_child(npc)
		npc.queue_free()
	_staff_by_slot.clear()
	for slot in ScheduleManager.get_desk_slots():
		_place_slot_staff(slot["name"])
	_assign_staff_to_work()

## Places the StaffNPC for one desk (nothing if the desk is unassigned).
func _place_slot_staff(slot_name: String) -> void:
	var member := ScheduleManager.get_assigned(slot_name)
	if member == null:
		return
	var npc: StaffNPC = STAFF_NPC_SCENE.instantiate()
	npc.setup(member)
	npc.name = "Staff_" + slot_name.replace(" ", "")
	staff_layer.add_child(npc)
	_staff_by_slot[slot_name] = npc
	if _player_desk_slots.has(slot_name):
		npc.place_at(_break_spot_for(slot_name), StaffNPC.State.ON_BREAK)
	else:
		npc.place_at(_desk_spot(slot_name), StaffNPC.State.AT_DESK)

func _assign_staff_to_work() -> void:
	window1_npc_line.staff_npc = _staff_by_slot.get(ScheduleManager.SLOT_TELLER_WINDOW_1)
	window2_line.staff_npc = _staff_by_slot.get(ScheduleManager.SLOT_TELLER_WINDOW_2)
	window3_line.staff_npc = _staff_by_slot.get(ScheduleManager.SLOT_TELLER_WINDOW_3)
	loan_desk_worker.staff_npc = _staff_by_slot.get(ScheduleManager.SLOT_LOAN_DESK)

func _on_schedule_confirmed(_schedule: Dictionary) -> void:
	_place_staff()

## Only the Loan Desk is shared with staff (the player's teller window is
## their own): its worker stops deciding and walks to the break room while
## the player works it.
func _on_player_clocked_in(slot_name: String) -> void:
	XPManager.begin_player_shift(slot_name)
	# Can't normally happen (the desk is locked after promotion), but a
	# Branch Manager's Loan Desk staff never steps away.
	if XPManager.is_branch_manager_unlocked:
		return
	if slot_name == ScheduleManager.SLOT_LOAN_DESK:
		loan_desk_worker.active = false
	if not _player_desk_slots.has(slot_name):
		_player_desk_slots.append(slot_name)
	var npc: StaffNPC = _staff_by_slot.get(slot_name)
	if npc != null:
		npc.follow_route(_route_to_break(slot_name), StaffNPC.State.ON_BREAK)

## The loan worker resumes, but only actually decides once the staff
## member is back at their desk (it checks StaffNPC.State.AT_DESK).
## A promotion held back during this shift is granted here (XPManager), after
## which the walk back below leaves the staff member at the desk for good.
func _on_player_clocked_out(slot_name: String) -> void:
	if slot_name == ScheduleManager.SLOT_LOAN_DESK:
		loan_desk_worker.active = true
	_player_desk_slots.erase(slot_name)
	XPManager.end_player_shift(slot_name)
	var npc: StaffNPC = _staff_by_slot.get(slot_name)
	if npc == null:
		return
	# Retrace only the waypoints they actually reached (all of them if they
	# made it to the break room; none if the tree stayed paused the whole
	# shift and they never left), then back to the desk — never a straight
	# line through the back-office wall.
	var full_route := _route_to_break(slot_name)
	var reached := full_route.size() if npc.state == StaffNPC.State.ON_BREAK else npc.waypoints_reached
	var walked := full_route.slice(0, reached)
	walked.reverse()
	if npc.state == StaffNPC.State.ON_BREAK:
		walked.remove_at(0) # already standing at the break spot
	walked.append(_desk_spot(slot_name))
	npc.follow_route(walked, StaffNPC.State.AT_DESK)

func _desk_spot(slot_name: String) -> Vector2:
	return (_desk_for_slot[slot_name] as Node2D).get_node("StaffSpot").global_position

## Each desk slot gets its own break-room spot (same order as DESK_SLOTS).
func _break_spot_for(slot_name: String) -> Vector2:
	var spots := staff_break_area.get_node("BreakSpots").get_children()
	var index := 0
	for i in ScheduleManager.DESK_SLOTS.size():
		if ScheduleManager.DESK_SLOTS[i]["name"] == slot_name:
			index = i
	return (spots[index % spots.size()] as Node2D).global_position

## Desk -> along the aisle behind the desks -> through the conference-room
## door -> this desk's break spot. Straight lines between these points stay
## clear of the back-office wall (the door gap is the only way through).
func _route_to_break(slot_name: String) -> Array[Vector2]:
	var door_outside: Vector2 = (staff_break_area.get_node("DoorOutside") as Node2D).global_position
	var door_inside: Vector2 = (staff_break_area.get_node("DoorInside") as Node2D).global_position
	var desk := _desk_spot(slot_name)
	return [
		Vector2(desk.x, door_outside.y),
		door_outside,
		door_inside,
		_break_spot_for(slot_name),
	]

## Remembers whoever's at the front of the line (null if the queue is
## empty) before opening the screen, and hands them to show_screen() so it
## can display who's being served (or "No customer waiting.").
##
## Guarded against re-entry: TellerDesk's `interacted` only stops firing
## once the tree is actually paused, which happens partway through
## show_screen() rather than before it's called, so relying on that alone
## is fragile (a stray input event, or the desk/room ever gaining an
## explicit process_mode, could re-fire this while the screen is already
## up and re-run set_serving_customer()/show_screen() mid-visit).
func _on_teller_desk_interacted() -> void:
	if teller_screen.visible:
		return
	if XPManager.is_branch_manager_unlocked:
		_show_desk_notice(ScheduleManager.SLOT_TELLER_WINDOW_3, "%s is working this window. As Branch Manager, your desk is in the office.")
		return
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.show_screen(_customer_being_served)

## Fires once a regular customer's request is done (first try, or after a
## mistake was fixed) — serve them and move on to whoever's next. Complaint
## customers are handled by resolving the complaint instead — see
## _on_teller_complaint_resolved().
func _on_teller_customer_request_satisfied(customer: CustomerNPC) -> void:
	if customer != _customer_being_served:
		return
	_serve_current_customer()

## The screen is closing with this customer's mistake unfixed: they leave
## the line upset (CustomerNPC.left_upset picks the farewell line) with the
## same farewell timing as a served customer. The screen is closing, so
## there's no "next customer" to advance to here.
func _on_teller_customer_left_unfixed(customer: CustomerNPC) -> void:
	if customer != _customer_being_served:
		return
	var leaving := customer_queue.serve_front_customer()
	if leaving != null:
		_customers_awaiting_farewell.append(leaving)
	_customer_being_served = null

## Resolving a complaint is how a complaint customer gets served.
func _on_teller_complaint_resolved(customer: CustomerNPC) -> void:
	if customer != _customer_being_served:
		return
	_serve_current_customer()

## Pops the front customer (advancing the rest of the line immediately),
## then moves the screen straight on to whoever's next instead of leaving
## it on "No customer waiting." while people are still in line.
##
## Phase 6i: the served customer's node isn't freed here — it's kept in
## _customers_awaiting_farewell until the screen closes (see
## _on_teller_screen_closed()), so they visibly stick around at the desk
## for the rest of this visit rather than vanishing mid-transaction.
func _serve_current_customer() -> void:
	var served := customer_queue.serve_front_customer()
	if served != null:
		_customers_awaiting_farewell.append(served)
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.advance_to_customer(_customer_being_served)

## Phase 6i: fires whenever the player closes the Teller screen. Everyone
## this visit served has been waiting here (already out of the queue
## itself, so it kept advancing normally for everyone else) for the screen
## to close before their farewell + walk-away plays.
func _on_teller_screen_closed() -> void:
	for customer in _customers_awaiting_farewell:
		if is_instance_valid(customer):
			customer_queue.send_customer_off(customer)
	_customers_awaiting_farewell.clear()

## Backs TellerScreen.remaining_shift_work: clock-out is allowed only once
## every customer this shift brings has been handled (served, complaint
## resolved, or abandoned) — the per-shift cap has been reached, the queue
## is empty, and nobody is mid-service. A customer at the desk waiting for a
## mistake to be corrected is still in the queue, so they block clock-out
## too (named separately). Returns "" when that's the case, otherwise a
## short description of what's left for the error message.
func _describe_remaining_shift_work() -> String:
	var parts: PackedStringArray = []
	var waiting := customer_queue.queue.size()
	if is_instance_valid(_customer_being_served) and _customer_being_served.was_mistake and customer_queue.queue.has(_customer_being_served):
		parts.append("%s is still waiting for a correction" % _customer_being_served.display_name)
		waiting -= 1
	if waiting > 0:
		parts.append("%d %scustomer%s still waiting" % [waiting, "more " if parts.size() > 0 else "", "" if waiting == 1 else "s"])
	var to_arrive := customer_queue.get_customers_left_to_spawn()
	if to_arrive > 0:
		parts.append("%d more customer%s still to arrive" % [to_arrive, "" if to_arrive == 1 else "s"])
	if parts.is_empty() and is_instance_valid(_customer_being_served):
		parts.append("still serving %s" % _customer_being_served.display_name)
	return ", ".join(parts)

## Clock-out frees every queued customer (CustomerQueue.end_shift()), so
## whoever this visit was about to serve no longer exists — clear the
## reference and the "Serving: X" UI rather than leaving them stale.
func _on_teller_shift_clocked_out() -> void:
	_customer_being_served = null
	teller_screen.set_serving_customer(null)

## Fires when CustomerQueue removes a customer whose patience ran out before
## being served. If they happened to be whoever the desk interaction was
## about to serve, clear that reference/UI — belt-and-suspenders, since the
## tree being paused whenever the screen is actually open should already
## prevent a customer mid-visit from reaching that state (see
## CustomerNPC._process()'s doc comment).
func _on_customer_abandoned(customer: CustomerNPC) -> void:
	if _customer_being_served == customer:
		_customer_being_served = null
		teller_screen.set_serving_customer(null)
	ReputationManager.add_reputation(ABANDONMENT_REPUTATION_PENALTY)
	teller_screen.note_customer_abandoned(ABANDONMENT_REPUTATION_PENALTY)
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"Customer abandoned the line: %s" % customer.display_name,
		"Abandoned"
	)

## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment.
func _on_loan_officer_desk_interacted() -> void:
	if loan_officer_screen.visible:
		return
	if XPManager.is_branch_manager_unlocked:
		_show_desk_notice(ScheduleManager.SLOT_LOAN_DESK, "%s is working the Loan Desk. As Branch Manager, your desk is in the office.")
		return
	loan_officer_screen.show_screen()

func _on_loan_officer_unlocked() -> void:
	_update_loan_officer_desk_availability()

func _update_loan_officer_desk_availability() -> void:
	# Always visible (it's the staffed Loan Desk); only the player's ability
	# to use it waits for the unlock. A Branch Manager can't work it, but it
	# still responds (with the locked-desk notice).
	loan_officer_desk.monitoring = XPManager.is_loan_officer_unlocked or XPManager.is_branch_manager_unlocked

## Short notice naming whoever is assigned to `slot_name` (template has one
## %s for the name). Shown over the room for DESK_NOTICE_SECONDS.
func _show_desk_notice(slot_name: String, template: String) -> void:
	var member := ScheduleManager.get_assigned(slot_name)
	if member != null:
		desk_notice_label.text = template % member.staff_name
	else:
		desk_notice_label.text = "No one is assigned here right now. As Branch Manager, your desk is in the office."
	desk_notice.visible = true
	_desk_notice_token += 1
	get_tree().create_timer(DESK_NOTICE_SECONDS, false).timeout.connect(_hide_desk_notice.bind(_desk_notice_token))

func _hide_desk_notice(token: int) -> void:
	if token == _desk_notice_token:
		desk_notice.visible = false

## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment.
func _on_branch_manager_desk_interacted() -> void:
	if branch_manager_screen.visible:
		return
	branch_manager_screen.show_screen()

func _on_branch_manager_unlocked() -> void:
	_update_branch_manager_desk_availability()
	_apply_branch_manager_desks()

## After promotion (never mid-shift — XPManager holds it until clock-out):
## the Player Teller Window becomes Teller Window 3, staffed (ScheduleManager
## has already filled the slot) and served from the player's lane by its own
## NpcCustomerLine; the player's own line is never started again since the
## desk no longer opens TellerScreen. The Loan Desk's staff member stays at
## the desk for good (_on_player_clocked_in() no longer sends them away).
## Undone by CareerReset + the scene reload after "Apply for a new job".
func _apply_branch_manager_desks() -> void:
	if not _staff_by_slot.has(ScheduleManager.SLOT_TELLER_WINDOW_3):
		_place_slot_staff(ScheduleManager.SLOT_TELLER_WINDOW_3)
		_assign_staff_to_work()
	if not window3_line.active:
		window3_line.activate()
	loan_desk_worker.active = true
	_update_loan_officer_desk_availability()

func _update_branch_manager_desk_availability() -> void:
	var unlocked := XPManager.is_branch_manager_unlocked
	branch_manager_desk.visible = unlocked
	branch_manager_desk.monitoring = unlocked

## No availability check, unlike the job desks above — the ATM (Phase 6f)
## is a customer-facing feature available regardless of shift/clock-in
## status or XP unlocks, so it's just always visible and monitoring.
## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment.
func _on_atm_interacted() -> void:
	if atm_screen.visible:
		return
	atm_screen.show_screen()

## TEMP debug cheat — see DEBUG_UNLOCK_KEY doc comment above. Reputation is
## bumped first so it's already at its clamped max by the time
## XPManager's unlock check (triggered by the XP change right after) reads
## ReputationManager.reputation — both thresholds clear in one keypress
## regardless of current progress. Because it goes through XPManager's
## normal unlock check, a Branch Manager unlock pressed mid-shift waits for
## clock-out and shows the same promotion letter as a real one.
##
## Gated on OS.is_debug_build() so it works when running from the editor
## (or a debug export) but never in an exported release build.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == DEBUG_UNLOCK_KEY:
		ReputationManager.add_reputation(100)
		XPManager.add_shift_xp(200)
