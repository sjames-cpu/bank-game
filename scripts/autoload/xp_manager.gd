extends Node

## Autoload singleton — same pattern as ScoreManager/ReputationManager (see
## those files for why an autoload is the right fit). XP is a persistent,
## cross-shift progression total, similar to Reputation, except nothing
## else reads/writes it directly — this manager also owns the Loan
## Officer unlock check, since that check needs both XP and Reputation.
##
## Like the other managers, this only lives in memory for now and resets
## if the game is closed. Persisting across full restarts would mean
## saving to a user:// file on change and loading it back in _ready().

signal xp_changed(new_total: int)
signal loan_officer_unlocked
signal branch_manager_unlocked

## Shift score points are small (currently -5 to +10) while XP is meant to
## read as a bigger, more granular progression number against a 500-point
## unlock threshold, so each score point is worth 10 XP.
const XP_PER_SCORE_POINT: int = 10

## How much XP and Reputation are needed to unlock the Loan Officer role.
## Kept as named constants since both are expected to move once real
## tuning starts.
const XP_UNLOCK_THRESHOLD: int = 500
const REPUTATION_UNLOCK_FLOOR: int = 40

## Branch Manager (Phase 5f) sits above Loan Officer in the promotion
## path, so both thresholds are set meaningfully higher rather than
## reusing the Loan Officer ones: 3x the XP, since Teller -> Loan Officer
## -> Branch Manager is meant to read as an increasingly bigger career
## step, not evenly-spaced tiers. The Reputation floor (60) is set above
## ReputationManager's default starting value (50) rather than below it
## the way Loan Officer's floor (40) is — reaching Branch Manager should
## mean having actively built reputation, not just avoided losing it.
const XP_UNLOCK_THRESHOLD_BRANCH_MANAGER: int = 1500
const REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER: int = 60

## Floored at 0 rather than allowed negative — a bad shift can cost score
## and reputation, but XP is meant to read as pure cumulative progress.
var total_xp: int = 0

## Set once the unlock condition is met and never cleared afterward —
## Reputation dropping back below REPUTATION_UNLOCK_FLOOR later should not
## take the role away.
var is_loan_officer_unlocked: bool = false

## Same "never cleared once earned" rule as is_loan_officer_unlocked above.
var is_branch_manager_unlocked: bool = false

func add_shift_xp(shift_score: int) -> void:
	total_xp = maxi(0, total_xp + shift_score * XP_PER_SCORE_POINT)
	xp_changed.emit(total_xp)
	_check_unlock()
	_check_branch_manager_unlock()

func _check_unlock() -> void:
	if is_loan_officer_unlocked:
		return
	if total_xp >= XP_UNLOCK_THRESHOLD and ReputationManager.reputation >= REPUTATION_UNLOCK_FLOOR:
		is_loan_officer_unlocked = true
		loan_officer_unlocked.emit()

## Kept as its own function (rather than folded into _check_unlock() above)
## so the original Loan Officer check stays exactly as it was — this is a
## second, independent check added alongside it, not a restructuring of it.
func _check_branch_manager_unlock() -> void:
	if is_branch_manager_unlocked:
		return
	if total_xp >= XP_UNLOCK_THRESHOLD_BRANCH_MANAGER and ReputationManager.reputation >= REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER:
		is_branch_manager_unlocked = true
		branch_manager_unlocked.emit()
