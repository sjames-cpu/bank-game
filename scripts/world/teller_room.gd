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
## a completed deposit/withdrawal for them (transaction_completed) — not
## just whenever the screen is closed, since closing without doing anything
## (checking a balance, clocking in/out) shouldn't silently drop them from
## the line. See _on_teller_desk_interacted and
## _on_teller_transaction_completed.

const DEBUG_UNLOCK_KEY := KEY_F1

@onready var teller_screen: TellerScreen = $UI/TellerScreen
@onready var loan_officer_desk: Area2D = $LoanOfficerDesk
@onready var loan_officer_screen: Control = $UI/LoanOfficerScreen
@onready var branch_manager_desk: Area2D = $BranchManagerDesk
@onready var branch_manager_screen: Control = $UI/BranchManagerScreen
@onready var customer_queue: CustomerQueue = $CustomerQueue

var _customer_being_served: CustomerNPC = null

func _ready() -> void:
	$TellerDesk.interacted.connect(_on_teller_desk_interacted)
	teller_screen.transaction_completed.connect(_on_teller_transaction_completed)
	teller_screen.shift_clocked_in.connect(customer_queue.start_shift)
	teller_screen.shift_clocked_out.connect(customer_queue.end_shift)
	loan_officer_desk.interacted.connect(_on_loan_officer_desk_interacted)
	XPManager.loan_officer_unlocked.connect(_on_loan_officer_unlocked)
	_update_loan_officer_desk_availability()

	branch_manager_desk.interacted.connect(_on_branch_manager_desk_interacted)
	XPManager.branch_manager_unlocked.connect(_on_branch_manager_unlocked)
	_update_branch_manager_desk_availability()

## Remembers whoever's at the front of the line (null if the queue is
## empty) before opening the screen, and hands them to show_screen() so it
## can display who's being served (or "No customer waiting.").
func _on_teller_desk_interacted() -> void:
	_customer_being_served = customer_queue.get_front_customer()
	teller_screen.show_screen(_customer_being_served)

## Fires once a deposit or withdrawal actually succeeds. If someone was at
## the front of the line when the screen opened, that transaction counts as
## serving them: pop them from the queue (advancing the rest of the line)
## and clear the reference so a second transaction in the same visit doesn't
## try to serve whoever stepped up next. No customer waiting is a no-op.
func _on_teller_transaction_completed() -> void:
	if _customer_being_served == null:
		return
	customer_queue.serve_front_customer()
	_customer_being_served = null
	teller_screen.set_serving_customer(null)

func _on_loan_officer_desk_interacted() -> void:
	loan_officer_screen.show_screen()

func _on_loan_officer_unlocked() -> void:
	_update_loan_officer_desk_availability()

func _update_loan_officer_desk_availability() -> void:
	var unlocked := XPManager.is_loan_officer_unlocked
	loan_officer_desk.visible = unlocked
	loan_officer_desk.monitoring = unlocked

func _on_branch_manager_desk_interacted() -> void:
	branch_manager_screen.show_screen()

func _on_branch_manager_unlocked() -> void:
	_update_branch_manager_desk_availability()

func _update_branch_manager_desk_availability() -> void:
	var unlocked := XPManager.is_branch_manager_unlocked
	branch_manager_desk.visible = unlocked
	branch_manager_desk.monitoring = unlocked

## TEMP debug cheat — see DEBUG_UNLOCK_KEY doc comment above. Reputation is
## bumped first so it's already at its clamped max by the time
## XPManager's unlock check (triggered by the XP change right after) reads
## ReputationManager.reputation — both thresholds clear in one keypress
## regardless of current progress.
func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == DEBUG_UNLOCK_KEY:
		ReputationManager.add_reputation(100)
		XPManager.add_shift_xp(200)
