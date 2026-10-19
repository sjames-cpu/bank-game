extends Control
class_name EndOfDayScreen

## The end of the business day (BusinessDay): the "End of Day N" summary
## (customers the whole branch served today, the player's shifts, and
## today's Score, Reputation and XP changes) with its "Start Day N+1"
## button, and the "Go home and end Day N?" question the entrance doormat
## asks (ExitDoor). teller_room.gd decides when to show either and what the
## buttons do. Pauses the tree while up, like the letters; process_mode
## ALWAYS so its buttons work while paused.

signal go_home_confirmed
signal next_day_requested

@onready var confirm_panel: PanelContainer = $ConfirmPanel
@onready var confirm_label: Label = $ConfirmPanel/VBox/QuestionLabel
@onready var go_home_button: Button = $ConfirmPanel/VBox/ButtonsHBox/GoHomeButton
@onready var stay_button: Button = $ConfirmPanel/VBox/ButtonsHBox/StayButton

@onready var summary_panel: PanelContainer = $SummaryPanel
@onready var summary_title_label: Label = $SummaryPanel/VBox/TitleLabel
@onready var summary_label: Label = $SummaryPanel/VBox/SummaryLabel
@onready var next_day_button: Button = $SummaryPanel/VBox/NextDayButton

var _paused_by_self: bool = false

func _ready() -> void:
	visible = false
	go_home_button.pressed.connect(_on_go_home_pressed)
	stay_button.pressed.connect(close)
	next_day_button.pressed.connect(_on_next_day_pressed)

func is_summary_shown() -> bool:
	return visible and summary_panel.visible

## "Go home and end Day N?"
func ask_go_home(day: int) -> void:
	confirm_label.text = "Go home and end Day %d?" % day
	_open(confirm_panel)

## The summary for BusinessDay.summary()'s figures.
func show_summary(figures: Dictionary) -> void:
	var day: int = figures["day"]
	summary_title_label.text = "End of Day %d" % day
	summary_label.text = summary_text(figures)
	next_day_button.text = "Start Day %d" % (day + 1)
	_open(summary_panel)

static func summary_text(figures: Dictionary) -> String:
	var shifts: int = figures["shifts"]
	return "Customers served by the branch: %d (you %d, staff %d)\nYour shifts today: %d\n\nToday: Score %+d · Reputation %+d · XP %+d" % [
		figures["customers"], figures["customers_by_player"], figures["customers_by_staff"],
		shifts,
		figures["score"], figures["reputation"], figures["xp"],
	]

func close() -> void:
	visible = false
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false

func _open(panel: Control) -> void:
	confirm_panel.visible = panel == confirm_panel
	summary_panel.visible = panel == summary_panel
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func _on_go_home_pressed() -> void:
	go_home_confirmed.emit()

func _on_next_day_pressed() -> void:
	close()
	next_day_requested.emit()
