extends Node2D
class_name TellerRoom

## Root of the room. Listens for signals from interactable objects
## in the scene and decides what should happen.
##
## The Loan Officer desk (Phase 4f) lives in this same room rather than a
## separate scene — the room already has the tilemap/player/camera setup
## a new room would just duplicate, and there's no door/transition system
## yet to justify a second area. It's additive alongside the existing
## Teller desk/screen wiring below, not a change to it.
##
## The role isn't available to the player until
## XPManager.is_loan_officer_unlocked; _on_loan_officer_desk_interacted()
## checks that itself (rather than the desk script knowing about XPManager),
## so the desk is usable the moment it's earned. The desk is always visible
## and always detects the player — it's the branch's Loan Desk, worked by a
## staff member until the player can work it, and its interaction prompt
## says what unlocks it (B4).
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
## (StaffBreakArea) and walks back on clock-out.
##
## B5: the whole room is y-sorted. The root, the Staff layer, the customer
## lines, Decor and each desk have y_sort_enabled, so the player, customers,
## staff and every furniture sprite sort together by their y. Each furniture
## sprite's origin is at its base (texture offset up), so a character switches
## from behind to in front where its feet pass the furniture's bottom edge;
## staff stand above their counter's base, so the counter covers their lower
## body. Solid furniture has a Footprint StaticBody2D on physics layer 16 that
## only the player's mask includes: customers and staff walk scripted paths,
## colliding with walls only (unchanged), so furniture can't alter them, and
## the player and NPCs never block each other: a customer walks through a
## player standing in their lane.
##
## BranchManagerDesk (Phase 5f) follows the exact same pattern one tier up
## — hidden/non-monitoring until XPManager.is_branch_manager_unlocked,
## revealed reactively off XPManager.branch_manager_unlocked. Additive
## alongside the Teller/Loan Officer wiring above, not a change to it.
##
## DEBUG_UNLOCK_KEY (F1) is a debug-build-only shortcut (B7: gated on
## debug_cheats_enabled, i.e. OS.is_debug_build(), so it never works in an
## exported release) that maxes Reputation and adds XP, so the Loan Officer
## and Branch Manager loops can be played without grinding real shifts.
## DEBUG_LOAN_OFFICER_KEY (F2, same guard) unlocks Loan Officer only: XP to
## at least XP_UNLOCK_THRESHOLD (500) and Reputation to at least
## DEBUG_LOAN_OFFICER_REPUTATION (50), below Branch Manager's 60.
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
##
## B4 adds the always-on HUD (hud.gd): this room feeds it the shift-status
## line (describe_shift_status()), the "E — ..." prompt for whichever
## interactable the player stands at (interaction_prompt_text(), refreshed in
## _process()), and the moments each first-run hint (HintManager) fires.
##
## Save and load (SaveGame): the room saves the career at every clock-out
## (teller, Loan Desk, Branch Manager), after a promotion and after the
## one-time orientation letter (save_career()). A career loaded from the
## start screen (start_screen.gd) comes straight into this room off shift:
## everything here is built from the autoloads in _ready().

const DEBUG_UNLOCK_KEY := KEY_F1
const DEBUG_LOAN_OFFICER_KEY := KEY_F2
const DEBUG_LOAN_OFFICER_REPUTATION: int = 50

## Whether DEBUG_UNLOCK_KEY and DEBUG_LOAN_OFFICER_KEY work — only in debug builds. A variable rather
## than a direct OS.is_debug_build() call so tests (which always run in a
## debug build) can check the release-build behaviour (B7).
var debug_cheats_enabled: bool = OS.is_debug_build()

## Name the player's own window is reported to XPManager under while on shift.
const PLAYER_TELLER_WINDOW: String = "Player Teller Window"

## Phase 6g: Reputation penalty when a queued customer abandons the line
## (see CustomerQueue.customer_abandoned). Deliberately smaller in magnitude
## than MAJOR_DISCREPANCY_REPUTATION (-5, teller_screen.gd) since this is a
## systemic pacing issue rather than a direct error the player made, and
## smaller than even a dismissive complaint response (-3,
## customer_complaints_data.gd) for the same reason.
const ABANDONMENT_REPUTATION_PENALTY: int = -2

## B2: abandoning also costs Score, so ignoring customers can't pay — the
## same cost as a wrong request (TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE).
## No XP is taken, matching a wrong request.
const ABANDONMENT_SCORE_PENALTY: int = TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE

@onready var teller_screen: TellerScreen = $UI/TellerScreen
@onready var teller_desk: TellerDesk = $TellerDesk
@onready var loan_officer_desk: LoanOfficerDesk = $LoanOfficerDesk
@onready var loan_officer_screen: LoanOfficerScreen = $UI/LoanOfficerScreen
@onready var branch_manager_desk: BranchManagerDesk = $BranchManagerDesk
@onready var branch_manager_screen: BranchManagerScreen = $UI/BranchManagerScreen
@onready var customer_queue: CustomerQueue = $CustomerQueue
@onready var atm: ATM = $ATM
@onready var atm_screen: ATMScreen = $UI/ATMScreen
@onready var staff_layer: Node2D = $Staff
@onready var staff_break_area: Node2D = $StaffBreakArea
@onready var window1_npc_line: NpcCustomerLine = $Window1NpcLine
@onready var window2_line: NpcCustomerLine = $Window2Line
@onready var window3_line: NpcCustomerLine = $Window3Line
## Loan Desk 1's worker, the desk the player works as Loan Officer.
@onready var loan_desk_worker: NpcLoanDeskWorker = $LoanDeskWorker
## One worker per loan desk (each knows its slot_name), Loan Desk 1's first.
@onready var loan_desk_workers: Array[NpcLoanDeskWorker] = [$LoanDeskWorker, $LoanDeskWorker2, $LoanDeskWorker3]
@onready var desk_notice: PanelContainer = $UI/DeskNotice
@onready var player: PlayerMovement = $Player
@onready var desk_notice_label: Label = $UI/DeskNotice/Label
@onready var letter_screen: DisciplineLetterScreen = $UI/DisciplineLetterScreen
@onready var hud: Hud = $HUD
## Esc: Resume / Back to Main Menu (pause_menu.gd). It finds this room itself.
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var camera: RoomCamera = $Player/Camera2D
@onready var room_layer: TileMapLayer = $Room
@onready var exit_door: ExitDoor = $ExitDoor
@onready var end_of_day_screen: EndOfDayScreen = $UI/EndOfDayScreen

## How long the "X is working this window" notice stays up.
const DESK_NOTICE_SECONDS: float = 3.5
var _desk_notice_token: int = 0

## What a staffed desk says after promotion (%s = the staff member), as the
## interaction prompt and, with MANAGER_DESK_REMINDER added, the desk notice.
const WINDOW_STAFFED_TEXT: String = "%s is working this window."
const LOAN_DESK_STAFFED_TEXT: String = "%s is working Loan Desk 1."
const UNASSIGNED_DESK_TEXT: String = "No one is assigned here right now."
## The Player Teller Window while its cover teller works it (%s = their name).
const WINDOW_COVERED_TEXT: String = "%s is covering this window while you work the Loan Desk."
const MANAGER_DESK_REMINDER: String = " As Branch Manager, your desk is in the office."

const STAFF_NPC_SCENE: PackedScene = preload("res://scenes/characters/staff_npc.tscn")

## Desk node for each ScheduleManager desk slot; each has a StaffSpot marker.
@onready var _desk_for_slot: Dictionary[String, Node2D] = {
	ScheduleManager.SLOT_TELLER_WINDOW_1: $TellerWindow1,
	ScheduleManager.SLOT_TELLER_WINDOW_2: $TellerWindow2,
	ScheduleManager.SLOT_TELLER_WINDOW_3: $TellerDesk, # the Player Teller Window, after promotion
	ScheduleManager.SLOT_LOAN_DESK_1: $LoanOfficerDesk,
	ScheduleManager.SLOT_LOAN_DESK_2: $Decor/LoanDesk2,
	ScheduleManager.SLOT_LOAN_DESK_3: $Decor/LoanDesk3,
}

## slot name -> the StaffNPC currently placed at that desk.
var _staff_by_slot: Dictionary[String, StaffNPC] = {}

## The cover teller: while the player works Loan Desk 1 (before promotion),
## ScheduleManager.cover_teller() walks from the break room to the Player
## Teller Window and serves Window3Line, the window's NPC line, as a staff
## window like Windows 1 and 2. At clock-out they finish their customer,
## the rest of the line moves to Windows 1/2 or leaves (wind_down()), and
## they walk back to the break room and go. Null when nobody's covering.
## Mid-shift state, so never saved: a loaded career starts off shift.
var cover_npc: StaffNPC = null
## The cover teller has finished and is walking back to the break room.
var _cover_leaving: bool = false

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
	# The camera stays inside the room, walls and sidewalk included.
	camera.set_room_bounds(room_bounds())
	hud.shift_status = describe_shift_status
	hud.letter_screen = letter_screen
	teller_screen.ending_count_started.connect(hud.show_hint_once.bind(HintManager.Hint.FIRST_CLOCK_OUT))
	teller_desk.interacted.connect(_on_teller_desk_interacted)
	teller_screen.customer_request_satisfied.connect(_on_teller_customer_request_satisfied)
	teller_screen.customer_left_unfixed.connect(_on_teller_customer_left_unfixed)
	teller_screen.screen_closed.connect(_on_teller_screen_closed)
	teller_screen.complaint_resolved.connect(_on_teller_complaint_resolved)
	teller_screen.customer_refused.connect(_on_teller_customer_refused)
	teller_screen.remaining_shift_work = _describe_remaining_shift_work
	customer_queue.arrival_pressure = staff_window_pressure
	teller_screen.shift_clocked_in.connect(customer_queue.start_shift)
	teller_screen.shift_clocked_out.connect(customer_queue.end_shift)
	teller_screen.shift_clocked_out.connect(_on_teller_shift_clocked_out)
	# A Branch Manager promotion earned mid-shift waits for clock-out.
	teller_screen.shift_clocked_in.connect(XPManager.begin_player_shift.bind(PLAYER_TELLER_WINDOW))
	teller_screen.shift_clocked_out.connect(XPManager.end_player_shift.bind(PLAYER_TELLER_WINDOW))
	# Probation counts completed teller shifts without a new report.
	teller_screen.shift_clocked_in.connect(InterviewManager.begin_teller_shift)
	teller_screen.shift_clocked_out.connect(InterviewManager.end_teller_shift)
	# Saved last, once the promotion and probation above have settled.
	teller_screen.shift_clocked_out.connect(_on_shift_completed)
	customer_queue.customer_abandoned.connect(_on_customer_abandoned)
	loan_officer_desk.interacted.connect(_on_loan_officer_desk_interacted)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)

	branch_manager_desk.interacted.connect(_on_branch_manager_desk_interacted)
	branch_manager_screen.shift_clocked_in.connect(_on_branch_manager_clocked_in)
	branch_manager_screen.shift_clocked_out.connect(_on_shift_completed)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	_update_branch_manager_desk_availability()

	atm.interacted.connect(_on_atm_interacted)
	exit_door.interacted.connect(_on_exit_door_interacted)
	end_of_day_screen.go_home_confirmed.connect(_on_go_home_confirmed)
	end_of_day_screen.next_day_requested.connect(_on_next_day_requested)
	# Customers the staff serve count toward today's branch total; those who
	# give up at a staffed window count against the manager's review.
	for line: NpcCustomerLine in [window1_npc_line, window2_line, window3_line]:
		line.customer_served.connect(_on_staff_customer_served)
		line.customer_abandoned.connect(RegionalManager.note_staff_line_abandoned)
	XPManager.branch_manager_demoted.connect(_on_branch_manager_demoted)

	loan_officer_screen.shift_clocked_in.connect(_on_player_clocked_in.bind(ScheduleManager.SLOT_LOAN_DESK_1))
	loan_officer_screen.shift_clocked_out.connect(_on_player_clocked_out.bind(ScheduleManager.SLOT_LOAN_DESK_1))
	loan_officer_screen.shift_clocked_out.connect(_on_shift_completed)
	ScheduleManager.schedule_confirmed.connect(_on_schedule_confirmed)
	_place_staff()

	# Staff serve customers from the start: _place_staff() opened each
	# staffed teller window's line (_update_staff_lines()). Every loan desk
	# decides applications; only Loan Desk 1's worker pauses while the
	# player works it (see _on_player_clocked_in/_out).
	for worker in loan_desk_workers:
		worker.active = true
	if XPManager.is_branch_manager_unlocked:
		_apply_branch_manager_desks()

	hud.show_hint_once(HintManager.Hint.ARRIVAL)
	hud.show_hint_once(HintManager.Hint.OPENING_HOURS)

func _process(_delta: float) -> void:
	_update_interaction_prompt()
	_check_branch_opening()
	_update_regional_visit()
	_check_end_of_day()

# --- the business day (BusinessDay) -----------------------------------------------

## Customers the player's shift will still bring: none once the doors have
## closed for the day, so the ones that never came don't block clock-out.
func customers_still_to_arrive() -> int:
	if BusinessDay.doors_closed():
		return 0
	return customer_queue.get_customers_left_to_spawn()

## Clocked in at any desk (teller window, Loan Desk or Branch Manager's).
func is_player_on_shift() -> bool:
	return teller_screen.shift_state == TellerScreen.ShiftState.CLOCKED_IN or loan_officer_screen.is_clocked_in() or branch_manager_screen.is_clocked_in()

## Whether the branch was open last frame, to catch the moment it opens.
## Starts as it is now, so a career loaded mid-morning doesn't "open" again.
var _was_open: bool = BusinessDay.is_open()

## At 9:00 every line taking customers restarts its spawn timer, so the day's
## first customers arrive within a few game minutes of opening.
func _check_branch_opening() -> void:
	var open := BusinessDay.is_open()
	if open and not _was_open:
		for line: CustomerQueue in [customer_queue, window1_npc_line, window2_line, window3_line]:
			line.open_for_the_day()
	_was_open = open

## Nobody from any line is still in the building.
func is_lobby_empty() -> bool:
	for line: CustomerQueue in [customer_queue, window1_npc_line, window2_line, window3_line]:
		if line.has_customers():
			return false
	return true

## The day ends on its own once it's past closing time, the player is off
## shift and the last customer has left (checked every frame the world runs,
## so never behind an open screen or letter).
func _check_end_of_day() -> void:
	if end_of_day_screen.visible or get_tree().paused:
		return
	if BusinessDay.is_day_over() and not is_player_on_shift() and is_lobby_empty():
		show_end_of_day()

## The End of Day summary, saved as it appears. On a review day the Regional
## Manager's review comes first (RegionalManager.run_review()): its letter,
## and a demotion's, pause the room, and once they're acknowledged
## _check_end_of_day() comes back here for the summary. A demotion due from a
## third regional warning for Reputation 0 comes first instead, and then
## there's no review (the player is no longer Branch Manager).
func show_end_of_day() -> void:
	end_regional_visit()
	if RegionalManager.demote_if_due():
		save_career()
		if letter_screen.visible:
			return
	elif RegionalManager.is_review_due():
		RegionalManager.run_review()
		save_career()
		if letter_screen.visible:
			return
	end_of_day_screen.show_summary(BusinessDay.summary(), BusinessDay.closures_before_next_day())
	save_career()

# --- the Regional Manager's visit (RegionalManager) --------------------------------

## On a review day the Regional Manager walks in from the entrance at
## VISIT_START_MINUTES, stands outside the Manager's Office, and walks out
## again at VISIT_END_MINUTES. A room loaded part-way through the visit finds
## them already standing there.
const VISIT_START_MINUTES: float = 10.0 * 60.0
const VISIT_END_MINUTES: float = 11.0 * 60.0 + 30.0
## Later than this after VISIT_START_MINUTES, they're placed at the spot.
const VISIT_LATE_ARRIVAL_MINUTES: float = 10.0
## Entrance -> up the aisle beside the lounge -> outside the Manager's
## Office door (columns 9-10), facing it.
const VISIT_ENTRANCE: Vector2 = Vector2(384, 690)
const VISIT_ROUTE: Array[Vector2] = [Vector2(384, 330), Vector2(320, 330), Vector2(320, 290)]
const VISIT_GREETING: String = "Just here to observe. Carry on."

## The visiting Regional Manager (null when not here).
var regional_visitor: StaffNPC = null
var _visitor_leaving: bool = false
## The day they last came, so they don't come back once they've left.
var _visit_day: int = 0

func _update_regional_visit() -> void:
	var during_visit := GameClock.minutes >= VISIT_START_MINUTES and GameClock.minutes < VISIT_END_MINUTES and not BusinessDay.is_day_over()
	if not is_instance_valid(regional_visitor):
		regional_visitor = null
		if during_visit and RegionalManager.is_review_day() and _visit_day != BusinessDay.stats_day:
			_start_regional_visit()
		return
	if not during_visit and not _visitor_leaving:
		_visitor_leaving = true
		var route: Array[Vector2] = VISIT_ROUTE.duplicate()
		route.reverse()
		route.remove_at(0) # standing there
		route.append(VISIT_ENTRANCE)
		regional_visitor.follow_route(route, StaffNPC.State.ON_BREAK)
		regional_visitor.route_finished.connect(end_regional_visit, CONNECT_ONE_SHOT)

func _start_regional_visit() -> void:
	_visit_day = BusinessDay.stats_day
	_visitor_leaving = false
	var member := StaffMember.new()
	member.staff_name = RegionalManager.SENDER
	member.look = StaffLooks.REGIONAL_MANAGER_LOOK
	regional_visitor = STAFF_NPC_SCENE.instantiate()
	regional_visitor.setup(member)
	regional_visitor.name = "RegionalManagerVisitor"
	staff_layer.add_child(regional_visitor)
	if GameClock.minutes - VISIT_START_MINUTES > VISIT_LATE_ARRIVAL_MINUTES:
		regional_visitor.place_at(VISIT_ROUTE[-1], StaffNPC.State.ON_BREAK)
		return
	regional_visitor.place_at(VISIT_ENTRANCE, StaffNPC.State.ON_BREAK)
	regional_visitor.follow_route(VISIT_ROUTE, StaffNPC.State.ON_BREAK)
	regional_visitor.route_finished.connect(regional_visitor.say.bind(VISIT_GREETING, 4.0), CONNECT_ONE_SHOT)

## The visitor leaves the room (walked out, the day ended, or going home).
func end_regional_visit() -> void:
	# queue_free only: this can run from the visitor's own route_finished.
	if is_instance_valid(regional_visitor):
		regional_visitor.queue_free()
	regional_visitor = null
	_visitor_leaving = false

## Demoted to Loan Officer (RegionalManager, at a review's End of Day): undoes
## _apply_branch_manager_desks(). ScheduleManager has already closed Teller
## Window 3 and re-announced the schedule, so its staff member is gone from
## the desk; its line closes too, and the Branch Manager desk hides. The
## Player Teller Window and the Loan Desk work for the player again (they
## check XPManager themselves), and the Loan Desk's staff step away again
## while the player works it.
func _on_branch_manager_demoted() -> void:
	if window3_line.active:
		window3_line.close_line()
	_update_branch_manager_desk_availability()
	loan_desk_worker.active = true
	save_career()

func _on_exit_door_interacted() -> void:
	if end_of_day_screen.visible or is_player_on_shift():
		return
	end_of_day_screen.ask_go_home(BusinessDay.stats_day)

## Going home early: the rest of the day is skipped, with nobody left in the
## lobby to serve (no customers or staff work are simulated).
func _on_go_home_confirmed() -> void:
	end_of_day_screen.close()
	BusinessDay.go_home_early()
	for line: CustomerQueue in [customer_queue, window1_npc_line, window2_line, window3_line]:
		line.clear_lobby()
	_customers_awaiting_farewell.clear()
	_customer_being_served = null
	end_regional_visit()
	show_end_of_day()

## "Start Day N+1": 8:30 AM the next morning, saved.
func _on_next_day_requested() -> void:
	BusinessDay.start_next_day()
	save_career()

func _on_shift_completed() -> void:
	BusinessDay.note_shift_completed()
	save_career()

func _on_staff_customer_served(_customer: CustomerNPC, _staff: StaffMember, _was_mistake: bool) -> void:
	BusinessDay.note_customer_served_by_staff()

## The whole tiled area (the room and the sidewalk outside it), in world
## pixels: what the camera may show (RoomCamera).
func room_bounds() -> Rect2:
	var used := room_layer.get_used_rect()
	var tile := Vector2(room_layer.tile_set.tile_size)
	return Rect2(room_layer.position + Vector2(used.position) * tile, Vector2(used.size) * tile)

# --- HUD (B4) -----------------------------------------------------------------

## The interactables the prompt covers, in the order ties are broken.
func _interactables() -> Array[Interactable]:
	return [teller_desk, loan_officer_desk, branch_manager_desk, atm, exit_door]

## The interactable the player is standing at (the nearest, if several), or
## null. A hidden desk (the Branch Manager desk before promotion) doesn't count.
func interactable_in_range() -> Interactable:
	var player_position := player.global_position
	var nearest: Interactable = null
	for desk in _interactables():
		if not (desk.monitoring and desk.visible and desk.player_in_range):
			continue
		if nearest == null or desk.global_position.distance_to(player_position) < nearest.global_position.distance_to(player_position):
			nearest = desk
	return nearest

func _update_interaction_prompt() -> void:
	var desk := interactable_in_range()
	if desk == null:
		hud.hide_prompt()
	else:
		hud.show_prompt(interaction_prompt_text(desk), desk.global_position)

## "E — what pressing the interact key does here", or, for a desk the player
## can't use, why not. The key comes from the InputMap (InputPrompts).
func interaction_prompt_text(desk: Interactable) -> String:
	var key := InputPrompts.key_for(InputPrompts.INTERACT)
	if desk == teller_desk:
		if XPManager.is_branch_manager_unlocked:
			return _staffed_desk_text(ScheduleManager.SLOT_TELLER_WINDOW_3, WINDOW_STAFFED_TEXT)
		if is_window_covered():
			return WINDOW_COVERED_TEXT % cover_npc.staff.staff_name
		var teller_action := "Clock in"
		if teller_screen.shift_state == TellerScreen.ShiftState.CLOCKED_IN:
			teller_action = "Clock out" if _describe_remaining_shift_work() == "" else "Serve customers"
		return "%s — %s (%s)" % [key, teller_action, PLAYER_TELLER_WINDOW]
	if desk == loan_officer_desk:
		if XPManager.is_branch_manager_unlocked:
			return _staffed_desk_text(ScheduleManager.SLOT_LOAN_DESK_1, LOAN_DESK_STAFFED_TEXT)
		if not XPManager.is_loan_officer_unlocked:
			return "%s — unlocks at %d XP and %d Reputation" % [ScheduleManager.SLOT_LOAN_DESK_1, XPManager.XP_UNLOCK_THRESHOLD, XPManager.REPUTATION_UNLOCK_FLOOR]
		var loan_action := "Clock in"
		if loan_officer_screen.is_clocked_in():
			loan_action = "Clock out" if loan_officer_screen.applications_left() == 0 else "Review applications"
		return "%s — %s (%s)" % [key, loan_action, ScheduleManager.SLOT_LOAN_DESK_1]
	if desk == branch_manager_desk:
		return "%s — Branch Manager desk" % key
	if desk == exit_door:
		if is_player_on_shift():
			return "Clock out before you go home"
		return "%s — Go home (end Day %d)" % [key, BusinessDay.stats_day]
	if desk == atm:
		return "%s — Use ATM" % key
	return ""

## The HUD's shift line: "Off shift", or "On shift — " and where, with
## what's left of that shift's work.
func describe_shift_status() -> String:
	var parts: PackedStringArray = []
	if teller_screen.shift_state == TellerScreen.ShiftState.CLOCKED_IN:
		var customers_left := customer_queue.queue.size() + customers_still_to_arrive()
		var teller_part := "%s · %d customer%s left" % [PLAYER_TELLER_WINDOW, customers_left, "" if customers_left == 1 else "s"]
		# Closing time cut this shift short: say so, since fewer than 4 came.
		if BusinessDay.doors_closed() and customer_queue.get_customers_left_to_spawn() > 0:
			teller_part += " · %s" % BusinessDay.DOORS_CLOSED_TEXT
		parts.append(teller_part)
	if loan_officer_screen.is_clocked_in():
		var applications_left: int = loan_officer_screen.applications_left()
		parts.append("%s · %d application%s left" % [ScheduleManager.SLOT_LOAN_DESK_1, applications_left, "" if applications_left == 1 else "s"])
	if branch_manager_screen.is_clocked_in():
		parts.append("Branch Manager office · vault %s" % ("reconciled" if branch_manager_screen.is_vault_reconciled() else "not reconciled yet"))
	if parts.is_empty():
		return "Off shift"
	return "On shift — %s" % "; ".join(parts)

## First-customer hint: only for a regular customer at the desk (a complaint
## customer has no request to complete).
## The ID-check hint comes the first time a customer at the desk needs ID.
func _hint_first_customer(customer: CustomerNPC) -> void:
	if is_instance_valid(customer) and customer.complaint == null:
		hud.show_hint_once(HintManager.Hint.FIRST_CUSTOMER)
		if KycPolicy.requires_id(customer):
			hud.show_hint_once(HintManager.Hint.ID_CHECK)

## (Re)creates one StaffNPC per assigned desk from ScheduleManager. A desk
## the player is clocked in at gets its staff member placed straight in the
## break room instead.
func _place_staff() -> void:
	for npc: StaffNPC in _staff_by_slot.values():
		staff_layer.remove_child(npc)
		npc.queue_free()
	_staff_by_slot.clear()
	for slot in ScheduleManager.get_desk_slots():
		var slot_name: String = slot["name"]
		_place_slot_staff(slot_name)
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
	var window_3_staff: StaffNPC = _staff_by_slot.get(ScheduleManager.SLOT_TELLER_WINDOW_3)
	window3_line.staff_npc = window_3_staff if window_3_staff != null else cover_npc
	for worker in loan_desk_workers:
		worker.staff_npc = _staff_by_slot.get(worker.slot_name)
	_update_staff_lines()

## How busy the staff teller windows are for customers choosing a line, 0-1:
## the average of Teller Windows 1 and 2's NpcCustomerLine.crowding() (a
## closed window counts as full). It shortens the gap between arrivals at
## the player's line (CustomerQueue.arrival_pressure): a fully staffed
## branch whose staff keep up leaves it at 0, the usual pace. Teller
## Window 3 only opens once the player no longer works their own line.
func staff_window_pressure() -> float:
	return (window1_npc_line.crowding() + window2_line.crowding()) / 2.0

## A staffed teller window's line is open; an unassigned one (e.g. its staff
## member was terminated) is closed — no new customers, and anyone waiting
## walks out (NpcCustomerLine.close_line()). Teller Window 3's line only
## exists once the player is Branch Manager.
func _update_staff_lines() -> void:
	var lines := {
		ScheduleManager.SLOT_TELLER_WINDOW_1: window1_npc_line,
		ScheduleManager.SLOT_TELLER_WINDOW_2: window2_line,
	}
	if XPManager.is_branch_manager_unlocked:
		lines[ScheduleManager.SLOT_TELLER_WINDOW_3] = window3_line
	for slot_name: String in lines:
		var line: NpcCustomerLine = lines[slot_name]
		var staffed := ScheduleManager.get_assigned(slot_name) != null
		if staffed and not line.active:
			line.activate()
		elif not staffed and line.active:
			line.close_line()

func _on_schedule_confirmed(_schedule: Dictionary) -> void:
	_place_staff()

## Only Loan Desk 1 is shared with staff (the player's teller window is
## their own; Loan Desks 2 and 3 are never the player's): its worker stops
## deciding and walks to the break room while the player works it.
func _on_player_clocked_in(slot_name: String) -> void:
	XPManager.begin_player_shift(slot_name)
	# Can't normally happen (the desk is locked after promotion), but a
	# Branch Manager's loan desk staff never step away.
	if XPManager.is_branch_manager_unlocked:
		return
	if slot_name == ScheduleManager.SLOT_LOAN_DESK_1:
		loan_desk_worker.active = false
		_start_cover()
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
	if slot_name == ScheduleManager.SLOT_LOAN_DESK_1:
		loan_desk_worker.active = true
	_player_desk_slots.erase(slot_name)
	# A promotion held back during the shift is granted here, and takes the
	# cover teller over as Teller Window 3 (_apply_branch_manager_desks()).
	XPManager.end_player_shift(slot_name)
	if slot_name == ScheduleManager.SLOT_LOAN_DESK_1:
		_end_cover()
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

# --- the cover teller -------------------------------------------------------------

## The Player Teller Window is being worked by the cover teller.
func is_window_covered() -> bool:
	return cover_npc != null and not _cover_leaving

## Loan Desk 1 clock-in: the cover teller (if there is one) walks from the
## break room to the Player Teller Window, and its line opens as a staff
## window. Not as Branch Manager (Teller Window 3 is staffed for good), nor
## while the player is still on a teller shift there.
func _start_cover() -> void:
	if XPManager.is_branch_manager_unlocked or cover_npc != null or teller_screen.shift_state == TellerScreen.ShiftState.CLOCKED_IN:
		return
	var member := ScheduleManager.cover_teller()
	if member == null:
		return
	cover_npc = STAFF_NPC_SCENE.instantiate()
	cover_npc.setup(member)
	cover_npc.name = "CoverTeller"
	staff_layer.add_child(cover_npc)
	_cover_leaving = false
	# The break-room route, the other way round, ending at the window.
	var route := _route_to_break(ScheduleManager.SLOT_TELLER_WINDOW_3)
	route.reverse()
	cover_npc.place_at(route[0], StaffNPC.State.ON_BREAK)
	route.remove_at(0)
	route.append(_desk_spot(ScheduleManager.SLOT_TELLER_WINDOW_3))
	cover_npc.follow_route(route, StaffNPC.State.AT_DESK)
	window3_line.slot_name = PLAYER_TELLER_WINDOW
	window3_line.staff_npc = cover_npc
	window3_line.activate()

## Loan Desk 1 clock-out: the cover teller finishes their customer, the rest
## move to Windows 1/2 if there's room or leave, then they walk back.
func _end_cover() -> void:
	if cover_npc == null or _cover_leaving or XPManager.is_branch_manager_unlocked:
		return
	window3_line.wind_down([window1_npc_line, window2_line])
	if not window3_line.wound_down.is_connected(_send_cover_to_break):
		window3_line.wound_down.connect(_send_cover_to_break, CONNECT_ONE_SHOT)

func _send_cover_to_break() -> void:
	if cover_npc == null:
		return
	_cover_leaving = true
	window3_line.staff_npc = null
	window3_line.slot_name = ScheduleManager.SLOT_TELLER_WINDOW_3
	cover_npc.follow_route(_route_to_break(ScheduleManager.SLOT_TELLER_WINDOW_3), StaffNPC.State.ON_BREAK)
	cover_npc.route_finished.connect(_dismiss_cover, CONNECT_ONE_SHOT)

## Back in the break room, the cover teller goes (they aren't at a desk).
func _dismiss_cover() -> void:
	if cover_npc != null:
		cover_npc.queue_free()
	cover_npc = null
	_cover_leaving = false

## A promotion granted at Loan Desk 1 clock-out: Teller Window 3's own staff
## member takes the window and its line over from the cover teller.
func _end_cover_now() -> void:
	if window3_line.wound_down.is_connected(_send_cover_to_break):
		window3_line.wound_down.disconnect(_send_cover_to_break)
	if cover_npc != null:
		staff_layer.remove_child(cover_npc)
		cover_npc.queue_free()
	cover_npc = null
	_cover_leaving = false
	window3_line.slot_name = ScheduleManager.SLOT_TELLER_WINDOW_3

func _desk_spot(slot_name: String) -> Vector2:
	return (_desk_for_slot[slot_name].get_node("StaffSpot") as Node2D).global_position

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
		_show_desk_notice(ScheduleManager.SLOT_TELLER_WINDOW_3, WINDOW_STAFFED_TEXT)
		return
	if is_window_covered():
		_show_notice(WINDOW_COVERED_TEXT % cover_npc.staff.staff_name)
		return
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.show_screen(_customer_being_served)
	_hint_first_customer(_customer_being_served)

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

## Refused service (no valid ID): they leave the line, saying their
## CustomerNPC.farewell_line once the screen closes, and the screen moves on
## to whoever's next. Not counted as served for the day's totals.
func _on_teller_customer_refused(customer: CustomerNPC) -> void:
	if customer != _customer_being_served:
		return
	var leaving := customer_queue.serve_front_customer()
	if leaving != null:
		_customers_awaiting_farewell.append(leaving)
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.advance_to_customer(_customer_being_served)
	_hint_first_customer(_customer_being_served)

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
		BusinessDay.note_customer_served_by_player()
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.advance_to_customer(_customer_being_served)
	_hint_first_customer(_customer_being_served)

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
## mistake to be corrected, or for Complete Transaction, is still in the
## queue, so they block clock-out too (named separately). Returns "" when
## that's the case, otherwise a short description of what's left for the
## error message.
func _describe_remaining_shift_work() -> String:
	var parts: PackedStringArray = []
	var waiting := customer_queue.queue.size()
	if is_instance_valid(_customer_being_served) and customer_queue.queue.has(_customer_being_served):
		if _customer_being_served.was_mistake:
			parts.append("%s is still waiting for a correction" % _customer_being_served.display_name)
			waiting -= 1
		elif teller_screen.has_uncompleted_transactions():
			parts.append("%s's transaction isn't completed yet" % _customer_being_served.display_name)
			waiting -= 1
	if waiting > 0:
		parts.append("%d %scustomer%s still waiting" % [waiting, "more " if parts.size() > 0 else "", "" if waiting == 1 else "s"])
	var to_arrive := customers_still_to_arrive()
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
	ScoreManager.add_shift_score(ABANDONMENT_SCORE_PENALTY)
	ReputationManager.add_reputation(ABANDONMENT_REPUTATION_PENALTY)
	teller_screen.note_customer_abandoned(ABANDONMENT_SCORE_PENALTY, ABANDONMENT_REPUTATION_PENALTY)
	HistoryManager.add_record(
		DecisionRecord.Role.TELLER,
		"Customer abandoned the line: %s" % customer.display_name,
		"Abandoned"
	)

## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment. Before the Loan Officer unlock the desk
## does nothing (its prompt already says what unlocks it); a Branch Manager
## can't work it either, but gets the staffed-desk notice.
func _on_loan_officer_desk_interacted() -> void:
	if loan_officer_screen.visible:
		return
	if XPManager.is_branch_manager_unlocked:
		_show_desk_notice(ScheduleManager.SLOT_LOAN_DESK_1, LOAN_DESK_STAFFED_TEXT)
		return
	if not XPManager.is_loan_officer_unlocked:
		return
	loan_officer_screen.show_screen()

func _on_loan_officer_unlocked() -> void:
	hud.show_hint_once(HintManager.Hint.LOAN_OFFICER_UNLOCKED)

## `template` (one %s) filled with whoever is assigned to `slot_name`, or
## UNASSIGNED_DESK_TEXT.
func _staffed_desk_text(slot_name: String, template: String) -> String:
	var member := ScheduleManager.get_assigned(slot_name)
	if member == null:
		return UNASSIGNED_DESK_TEXT
	return template % member.staff_name

## Short notice naming whoever is assigned to `slot_name` (template has one
## %s for the name). Shown over the room for DESK_NOTICE_SECONDS.
func _show_desk_notice(slot_name: String, template: String) -> void:
	_show_notice(_staffed_desk_text(slot_name, template) + MANAGER_DESK_REMINDER)

## `text` over the room for DESK_NOTICE_SECONDS.
func _show_notice(text: String) -> void:
	desk_notice_label.text = text
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
	hud.show_hint_once(HintManager.Hint.BRANCH_MANAGER_UNLOCKED)
	save_career()

## The orientation letter is one-time, so the career is saved once it's shown.
func _on_branch_manager_clocked_in() -> void:
	if letter_screen.show_branch_orientation_once():
		save_career()

## Saves the career (SaveGame) at clock-outs, the promotion and the
## orientation letter. Never mid-shift state: the save holds only the
## autoloads' career data, and a loaded career starts off shift.
func save_career() -> void:
	SaveGame.save()

## After promotion (never mid-shift — XPManager holds it until clock-out):
## the Player Teller Window becomes Teller Window 3, staffed (ScheduleManager
## has already filled the slot) and served from the player's lane by its own
## NpcCustomerLine; the player's own line is never started again since the
## desk no longer opens TellerScreen. Every loan desk's staff member stays at
## their desk for good (_on_player_clocked_in() no longer sends them away).
## Undone by CareerReset + the scene reload after "Apply for a new job".
func _apply_branch_manager_desks() -> void:
	_end_cover_now()
	if not _staff_by_slot.has(ScheduleManager.SLOT_TELLER_WINDOW_3):
		_place_slot_staff(ScheduleManager.SLOT_TELLER_WINDOW_3)
	_assign_staff_to_work() # opens Window3Line when the desk is staffed
	for worker in loan_desk_workers:
		worker.active = true

func _update_branch_manager_desk_availability() -> void:
	var unlocked := XPManager.is_branch_manager_unlocked
	branch_manager_desk.visible = unlocked
	branch_manager_desk.monitoring = unlocked
	# A hidden desk mustn't be solid either.
	branch_manager_desk.get_node("Footprint/CollisionShape2D").set_deferred("disabled", not unlocked)

## No availability check, unlike the job desks above — the ATM (Phase 6f)
## is a customer-facing feature available regardless of shift/clock-in
## status or XP unlocks, so it's just always visible and monitoring.
## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment.
func _on_atm_interacted() -> void:
	if atm_screen.visible:
		return
	atm_screen.show_screen()

## The F1 and F2 debug shortcuts — see the DEBUG_UNLOCK_KEY doc comment
## above. For F1: Reputation is bumped first so it's already at its clamped max by the time
## XPManager's unlock check (triggered by the XP change right after) reads
## ReputationManager.reputation — both thresholds clear in one keypress
## regardless of current progress. Because it goes through XPManager's
## normal unlock check, a Branch Manager unlock pressed mid-shift waits for
## clock-out and shows the same promotion letter as a real one.
##
## Gated on debug_cheats_enabled (OS.is_debug_build()) so it works when
## running from the editor (or a debug export) but never in an exported
## release build.
func _unhandled_input(event: InputEvent) -> void:
	if not debug_cheats_enabled:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == DEBUG_UNLOCK_KEY:
		ReputationManager.add_reputation(100)
		XPManager.add_shift_xp(200)
	elif key_event.keycode == DEBUG_LOAN_OFFICER_KEY:
		# Raised only up to the Loan Officer thresholds, never down, through
		# the normal unlock checks; Reputation 50 stays under Branch Manager's.
		var xp_short := XPManager.XP_UNLOCK_THRESHOLD - XPManager.total_xp
		if xp_short > 0:
			XPManager.add_shift_xp(ceili(float(xp_short) / XPManager.XP_PER_SCORE_POINT))
		if ReputationManager.reputation < DEBUG_LOAN_OFFICER_REPUTATION:
			ReputationManager.add_reputation(DEBUG_LOAN_OFFICER_REPUTATION - ReputationManager.reputation)
