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
## LoanOfficerDesk starts hidden and non-monitoring (see teller_room.tscn)
## since the role isn't available until XPManager.is_loan_officer_unlocked
## — reacting to that unlock here (rather than polling it, or having the
## desk script know about XPManager itself) makes the desk visibly appear
## the moment it's earned, the same reactive pattern teller_screen.gd
## already uses to reveal its "Loan Officer role unlocked!" label.
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
## a completed deposit/withdrawal for them (transaction_completed), or, for
## a complaint customer, a resolved complaint (complaint_resolved) — not
## just whenever the screen is closed, since closing without doing anything
## (checking a balance, clocking in/out) shouldn't silently drop them from
## the line. See _on_teller_desk_interacted and _serve_current_customer.
##
## Phase 6f adds the ATM: unlike the three job desks above, it has no
## availability gating at all — see _on_atm_interacted() — since it's a
## customer-facing feature available regardless of shift/clock-in state,
## not a job role.

const DEBUG_UNLOCK_KEY := KEY_F1

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
	teller_screen.transaction_completed.connect(_on_teller_transaction_completed)
	teller_screen.screen_closed.connect(_on_teller_screen_closed)
	teller_screen.complaint_resolved.connect(_on_teller_complaint_resolved)
	teller_screen.remaining_shift_work = _describe_remaining_shift_work
	teller_screen.shift_clocked_in.connect(customer_queue.start_shift)
	teller_screen.shift_clocked_out.connect(customer_queue.end_shift)
	teller_screen.shift_clocked_out.connect(_on_teller_shift_clocked_out)
	customer_queue.customer_abandoned.connect(_on_customer_abandoned)
	loan_officer_desk.interacted.connect(_on_loan_officer_desk_interacted)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)
	_update_loan_officer_desk_availability()

	branch_manager_desk.interacted.connect(_on_branch_manager_desk_interacted)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	_update_branch_manager_desk_availability()

	atm.interacted.connect(_on_atm_interacted)

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
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.show_screen(_customer_being_served)

## Fires once a deposit or withdrawal actually succeeds. If a regular
## customer is being served, that transaction is theirs (TellerScreen has
## already graded it against their request) — serve them and move on to
## whoever's next. No customer waiting is a no-op. A complaint customer
## isn't served by a transaction (they have no request); they're handled
## by resolving the complaint instead — see _on_teller_complaint_resolved().
func _on_teller_transaction_completed() -> void:
	if _customer_being_served == null or _customer_being_served.complaint != null:
		return
	_serve_current_customer()

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
## is empty, and nobody is mid-service. Returns "" when that's the case,
## otherwise a short description of what's left for the error message.
func _describe_remaining_shift_work() -> String:
	var parts: PackedStringArray = []
	var waiting := customer_queue.queue.size()
	if waiting > 0:
		parts.append("%d customer%s still waiting" % [waiting, "" if waiting == 1 else "s"])
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
## about to serve, clear that reference/UI the same way
## _on_teller_transaction_completed() does — belt-and-suspenders, since the
## tree being paused whenever the screen is actually open should already
## prevent a customer mid-visit from reaching that state (see
## CustomerNPC._process()'s doc comment).
func _on_customer_abandoned(customer: CustomerNPC) -> void:
	if _customer_being_served == customer:
		_customer_being_served = null
		teller_screen.set_serving_customer(null)
	ReputationManager.add_reputation(ABANDONMENT_REPUTATION_PENALTY)
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
	loan_officer_screen.show_screen()

func _on_loan_officer_unlocked() -> void:
	_update_loan_officer_desk_availability()

func _update_loan_officer_desk_availability() -> void:
	var unlocked := XPManager.is_loan_officer_unlocked
	loan_officer_desk.visible = unlocked
	loan_officer_desk.monitoring = unlocked

## Guarded against re-entry the same way _on_teller_desk_interacted() is —
## see that function's doc comment.
func _on_branch_manager_desk_interacted() -> void:
	if branch_manager_screen.visible:
		return
	branch_manager_screen.show_screen()

func _on_branch_manager_unlocked() -> void:
	_update_branch_manager_desk_availability()

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
## regardless of current progress.
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
