extends Node

## Autoload singleton — registered in project.godot under [autoload], so
## Godot creates exactly one instance of this node at startup and keeps
## it alive for the entire run, outside of (and never freed by) any
## scene change. Any script can reach it by the global name "ScoreManager"
## with no node path or scene reference needed, which is what makes it
## the right fit for state like this that needs to outlive any single
## shift or scene.
##
## total_score only lives in memory for now, so it resets if the game is
## closed — it survives between shifts within a play session because
## this node does, not because anything is written to disk. Making it
## survive a full restart later would mean saving it to a file (e.g. via
## ConfigFile or FileAccess against a user:// path) on change and
## loading it back in _ready().

signal score_changed(new_total: int)

var total_score: int = 0

func add_shift_score(points: int) -> void:
	total_score += points
	score_changed.emit(total_score)
