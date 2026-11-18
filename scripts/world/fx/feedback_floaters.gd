extends Node2D
class_name FeedbackFloaters

## "+5 Score" style labels that float up from the player and fade in about a
## second when Score, Reputation or XP change (green for a gain, red for a
## loss). Changes that arrive together join one cluster, one line per
## statistic, so they stack instead of overlapping. It keeps running while a
## desk screen has the game paused (the room's score changes while a screen
## is open), is hidden at the 1x overview, and frees every label when it is
## done. Text goes through WorldText, so it stays crisp at either zoom.

const LIFETIME: float = 1.1
const FADE_START: float = 0.55
const RISE: float = 24.0
## A change within this long of a cluster's start joins that cluster.
const MERGE_WINDOW: float = 0.3
const LINE_HEIGHT: float = 13.0
const FONT_SIZE: int = 11
const GAIN: Color = Color(0.45, 1.0, 0.5, 1.0)
const LOSS: Color = Color(1.0, 0.42, 0.4, 1.0)
const ABOVE_PLAYER: Vector2 = Vector2(0, -34)

## Statistic names in the order their lines stack (bottom first).
const STATS: Array[String] = ["Score", "Reputation", "XP"]

class Cluster extends Node2D:
	var age: float = 0.0
	var start_y: float = 0.0
	var lines: Dictionary[String, Label] = {}
	var amounts: Dictionary[String, int] = {}

	func advance(seconds: float) -> void:
		age += seconds
		if age >= FeedbackFloaters.LIFETIME:
			queue_free()
			return
		var progress := age / FeedbackFloaters.LIFETIME
		position.y = start_y - FeedbackFloaters.RISE * (1.0 - (1.0 - progress) * (1.0 - progress))
		var fade := clampf(1.0 - (age - FeedbackFloaters.FADE_START) / (FeedbackFloaters.LIFETIME - FeedbackFloaters.FADE_START), 0.0, 1.0)
		modulate.a = fade

	func _process(delta: float) -> void:
		advance(delta)

var target: Node2D = null
var _clusters: Array[Cluster] = []
var _last: Dictionary[String, int] = {}

## Follows `follow` (the player) and listens to the three managers.
func connect_to(follow: Node2D) -> void:
	target = follow
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 20
	_last["Score"] = ScoreManager.total_score
	_last["Reputation"] = ReputationManager.reputation
	_last["XP"] = XPManager.total_xp
	ScoreManager.score_changed.connect(_changed.bind("Score"))
	ReputationManager.reputation_changed.connect(_changed.bind("Reputation"))
	XPManager.xp_changed.connect(_changed.bind("XP"))

func _exit_tree() -> void:
	for pair: Array in [[ScoreManager.score_changed, "Score"], [ReputationManager.reputation_changed, "Reputation"], [XPManager.xp_changed, "XP"]]:
		var changed: Signal = pair[0]
		var callable := _changed.bind(pair[1])
		if changed.is_connected(callable):
			changed.disconnect(callable)

func set_overview(value: bool) -> void:
	visible = not value

func _changed(new_total: int, stat: String) -> void:
	var before: int = _last.get(stat, new_total)
	var delta: int = new_total - before
	_last[stat] = new_total
	if delta != 0:
		show_change(stat, delta)

## Floats "+5 Score" (or "-3 Reputation") above the player.
func show_change(stat: String, delta: int) -> void:
	if delta == 0 or target == null:
		return
	var cluster := _live_cluster()
	if cluster == null:
		cluster = Cluster.new()
		cluster.start_y = target.global_position.y + ABOVE_PLAYER.y
		cluster.global_position = Vector2(target.global_position.x, cluster.start_y)
		add_child(cluster)
		_clusters.append(cluster)
	var total: int = cluster.amounts.get(stat, 0) + delta
	cluster.amounts[stat] = total
	var label: Label = cluster.lines.get(stat, null)
	if label == null:
		label = _new_line(cluster)
		cluster.lines[stat] = label
	label.text = "%s%d %s" % ["+" if total > 0 else "", total, stat]
	label.add_theme_color_override("font_color", GAIN if total > 0 else LOSS)

## The cluster still young enough to take another line, or null.
func _live_cluster() -> Cluster:
	for i in range(_clusters.size() - 1, -1, -1):
		var cluster := _clusters[i]
		if not is_instance_valid(cluster) or cluster.is_queued_for_deletion():
			_clusters.remove_at(i)
	if _clusters.is_empty():
		return null
	var newest := _clusters[-1]
	return newest if newest.age <= MERGE_WINDOW else null

func _new_line(cluster: Cluster) -> Label:
	var label := Label.new()
	var line_index := cluster.lines.size()
	label.size = Vector2(110, LINE_HEIGHT)
	label.position = Vector2(-55, -LINE_HEIGHT - line_index * LINE_HEIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	cluster.add_child(label)
	WorldText.register(label)
	return label

## How many clusters are still floating (tests).
func live_cluster_count() -> int:
	var count := 0
	for cluster in _clusters:
		if is_instance_valid(cluster) and not cluster.is_queued_for_deletion():
			count += 1
	return count
