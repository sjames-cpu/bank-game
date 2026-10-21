extends Node

## Autoload singleton — same pattern as ScoreManager (see that file for
## why an autoload is the right fit). Reputation differs from Score in
## that it's a persistent, cross-shift, customer-facing metric rather
## than a per-shift tally, so it's never reset between shifts — only
## ever adjusted up or down and clamped to [0, 100].
##
## Falling to 0 has consequences beyond the HUD warning: once each time it
## happens, reputation_reached_zero fires (ReportManager issues a report to a
## Teller or Loan Officer; RegionalManager gives a Branch Manager a regional
## warning). It fires again only after Reputation has recovered above
## LOW_REPUTATION_THRESHOLD (zero_armed).
##
## Saved with the career (save_data()/load_data(), see SaveGame).

signal reputation_changed(new_reputation: int)
## Reputation has just fallen to 0 (once per fall; see zero_armed).
signal reputation_reached_zero

## How low reputation must fall to trigger the low-reputation warning.
## Kept as a named constant (rather than a hardcoded 0) since this is
## expected to move once real tuning starts.
const LOW_REPUTATION_THRESHOLD: int = 0

const STARTING_REPUTATION: int = 50

var reputation: int = STARTING_REPUTATION
## Whether falling to 0 fires reputation_reached_zero: cleared when it fires,
## set again once Reputation is above LOW_REPUTATION_THRESHOLD.
var zero_armed: bool = true

func add_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, 0, 100)
	if reputation > LOW_REPUTATION_THRESHOLD:
		zero_armed = true
	reputation_changed.emit(reputation)
	if reputation == 0 and zero_armed:
		zero_armed = false
		reputation_reached_zero.emit()

## New career after termination — see CareerReset.
func reset() -> void:
	reputation = STARTING_REPUTATION
	zero_armed = true
	reputation_changed.emit(reputation)

func save_data() -> Dictionary:
	return {"reputation": reputation, "zero_armed": zero_armed}

func load_data(data: Dictionary) -> void:
	reputation = clampi(SaveGame.int_of(data, "reputation", STARTING_REPUTATION), 0, 100)
	# A save from before zero_armed: armed unless it was saved at the bottom.
	zero_armed = SaveGame.bool_of(data, "zero_armed", reputation > LOW_REPUTATION_THRESHOLD)
	reputation_changed.emit(reputation)
