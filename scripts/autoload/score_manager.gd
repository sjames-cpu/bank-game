extends Node

## Autoload singleton — registered in project.godot under [autoload], so
## Godot creates exactly one instance of this node at startup and keeps
## it alive for the entire run, outside of (and never freed by) any
## scene change. Any script can reach it by the global name "ScoreManager"
## with no node path or scene reference needed, which is what makes it
## the right fit for state like this that needs to outlive any single
## shift or scene.
##
## total_score survives between shifts within a play session because this
## node does; across launches it's saved with the rest of the career
## (save_data()/load_data(), see SaveGame).

signal score_changed(new_total: int)

var total_score: int = 0

func add_shift_score(points: int) -> void:
	total_score += points
	score_changed.emit(total_score)

## New career after termination — see CareerReset.
func reset() -> void:
	total_score = 0
	score_changed.emit(total_score)

func save_data() -> Dictionary:
	return {"total_score": total_score}

func load_data(data: Dictionary) -> void:
	total_score = SaveGame.int_of(data, "total_score", 0)
	score_changed.emit(total_score)
