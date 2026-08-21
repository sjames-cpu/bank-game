extends Node

## Autoload singleton — same pattern as ScoreManager (see that file for
## why an autoload is the right fit). Reputation differs from Score in
## that it's a persistent, cross-shift, customer-facing metric rather
## than a per-shift tally, so it's never reset between shifts — only
## ever adjusted up or down and clamped to [0, 100].
##
## Like ScoreManager, this only lives in memory for now and resets if
## the game is closed. Persisting across full restarts would mean
## saving to a user:// file on change and loading it back in _ready().

signal reputation_changed(new_reputation: int)

## How low reputation must fall to trigger the low-reputation warning.
## Kept as a named constant (rather than a hardcoded 0) since this is
## expected to move once real tuning starts.
const LOW_REPUTATION_THRESHOLD: int = 0

var reputation: int = 50

func add_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, 0, 100)
	reputation_changed.emit(reputation)
