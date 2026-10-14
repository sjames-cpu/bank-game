extends Node

## Autoload singleton — same pattern as ScoreManager (see that file for
## why an autoload is the right fit). Reputation differs from Score in
## that it's a persistent, cross-shift, customer-facing metric rather
## than a per-shift tally, so it's never reset between shifts — only
## ever adjusted up or down and clamped to [0, 100].
##
## Saved with the career (save_data()/load_data(), see SaveGame).

signal reputation_changed(new_reputation: int)

## How low reputation must fall to trigger the low-reputation warning.
## Kept as a named constant (rather than a hardcoded 0) since this is
## expected to move once real tuning starts.
const LOW_REPUTATION_THRESHOLD: int = 0

const STARTING_REPUTATION: int = 50

var reputation: int = STARTING_REPUTATION

func add_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, 0, 100)
	reputation_changed.emit(reputation)

## New career after termination — see CareerReset.
func reset() -> void:
	reputation = STARTING_REPUTATION
	reputation_changed.emit(reputation)

func save_data() -> Dictionary:
	return {"reputation": reputation}

func load_data(data: Dictionary) -> void:
	reputation = clampi(SaveGame.int_of(data, "reputation", STARTING_REPUTATION), 0, 100)
	reputation_changed.emit(reputation)
