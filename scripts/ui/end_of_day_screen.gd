extends Control
class_name EndOfDayScreen

## The end of the business day (BusinessDay): the "End of Day N" summary
## (the date, customers the whole branch served today, the player's shifts,
## today's Score, Reputation and XP changes, and transactions after the
## 2:00 PM cutoff) with its "Start Day N+1" button, and the "Go home and end
## Day N?" question the entrance doormat asks (ExitDoor). When the next
## business day comes after a weekend or bank holiday, "Start Day N+1" first
## shows the closure ("Weekend — the branch is closed") in the same panel,
## and its button then starts the day. teller_room.gd decides when to show either and what the
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
## The closed days still to show before the next day (show_summary()).
var _closures: Array[Dictionary] = []
var _closure_shown: bool = false
var _next_day: int = 0

## At most this many after-cutoff transactions are listed by line.
const MAX_CUTOFF_LINES: int = 6

func _ready() -> void:
	visible = false
	go_home_button.pressed.connect(_on_go_home_pressed)
	stay_button.pressed.connect(close)
	next_day_button.pressed.connect(_on_next_day_pressed)

## The summary, or the closure notice that follows it in the same panel.
func is_summary_shown() -> bool:
	return visible and summary_panel.visible

## The weekend or holiday notice is up.
func is_closure_shown() -> bool:
	return is_summary_shown() and _closure_shown

## "Go home and end Day N?"
func ask_go_home(day: int) -> void:
	confirm_label.text = "Go home and end Day %d?" % day
	_open(confirm_panel)

## The summary for BusinessDay.summary()'s figures. `closures`: the closed
## days before the next business day (BusinessDay.closures_before_next_day()).
func show_summary(figures: Dictionary, closures: Array[Dictionary] = []) -> void:
	var day: int = figures["day"]
	_closures = closures
	_closure_shown = false
	_next_day = day + 1
	summary_title_label.text = "End of Day %d" % day
	summary_label.text = summary_text(figures)
	next_day_button.text = "Start Day %d" % _next_day
	_open(summary_panel)

static func summary_text(figures: Dictionary) -> String:
	var shifts: int = figures["shifts"]
	var date: int = figures["date"]
	var text := "%s\n\nCustomers served by the branch: %d (you %d, staff %d)\nYour shifts today: %d\n\nToday: Score %+d · Reputation %+d · XP %+d" % [
		BankCalendar.long_text(date),
		figures["customers"], figures["customers_by_player"], figures["customers_by_staff"],
		shifts,
		figures["score"], figures["reputation"], figures["xp"],
	]
	var vault: Dictionary = figures.get("vault", {})
	if not vault.is_empty():
		text += "\n\n" + vault_text(vault)
	var after_cutoff: Array = figures["after_cutoff"]
	if not after_cutoff.is_empty():
		text += "\n\n" + cutoff_text(after_cutoff)
	return text

## The vault's day (VaultManager.close_day()): what moved, where it stands
## against its limits, and any order placed for tomorrow, e.g.
## "Vault: staff windows +$1234.50 · ATM restock -$24000.00" then
## "Vault now $177234.50 (limits $100000–$300000)".
static func vault_text(vault: Dictionary) -> String:
	var staff_net: int = vault["staff_net"]
	var restock: int = vault["atm_restock"]
	var delivered: int = vault["delivered"]
	var shipped: int = vault["shipped"]
	var expected: int = vault["expected"]
	var in_range: bool = vault["in_range"]
	var moves: PackedStringArray = ["staff windows %s%s" % ["+" if staff_net >= 0 else "", MoneyMath.format(staff_net)]]
	if restock > 0:
		moves.append("ATM restock -%s" % MoneyMath.format(restock))
	if delivered > 0:
		moves.append("delivered +%s" % MoneyMath.format(delivered))
	if shipped > 0:
		moves.append("shipped -%s" % MoneyMath.format(shipped))
	var lines: PackedStringArray = ["Vault: %s" % " · ".join(moves)]
	var standing := "Vault now %s (limits %s–%s)" % [MoneyMath.format(expected), MoneyMath.format(VaultManager.VAULT_MIN_CENTS, true), MoneyMath.format(VaultManager.VAULT_MAX_CENTS, true)]
	if not in_range:
		standing += " — out of range"
	lines.append(standing)
	var truck: String = vault.get("truck", "")
	if truck != "":
		lines.append(truck)
	var order: Dictionary = vault["order"]
	if not order.is_empty():
		var cents: int = order["cents"]
		var delivery_day: int = order["delivery_day"]
		lines.append("Branch manager's cash order: %s %s for %s" % ["in" if cents > 0 else "out", MoneyMath.format(absi(cents), true), BankCalendar.short_text(GameClock.date_of_day(delivery_day))])
	return "\n".join(lines)

## "After the 2:00 PM cutoff, posting Tue 6 Jan: 2" and a line each.
static func cutoff_text(after_cutoff: Array) -> String:
	var first: Dictionary = after_cutoff[0]
	var posting_day: int = first["posting_day"]
	var lines: Array[String] = ["After the 2:00 PM cutoff, posting %s: %d" % [BankCalendar.short_text(GameClock.date_of_day(posting_day)), after_cutoff.size()]]
	for i in mini(after_cutoff.size(), MAX_CUTOFF_LINES):
		var entry: Dictionary = after_cutoff[i]
		var amount_cents: int = entry["amount_cents"]
		lines.append("%s %s %s — %s" % [entry["time"], entry["type"], MoneyMath.format(amount_cents), entry["account"]])
	if after_cutoff.size() > MAX_CUTOFF_LINES:
		lines.append("… and %d more" % (after_cutoff.size() - MAX_CUTOFF_LINES))
	return "\n".join(lines)

## "Weekend — the branch is closed", the closed dates, and when it reopens.
func _show_closure() -> void:
	var lines: Array[String] = []
	for closure in _closures:
		var date: int = closure["date"]
		var holiday: String = closure["holiday"]
		lines.append("%s — %s" % [BankCalendar.short_text(date), holiday if holiday != "" else "weekend"])
	lines.append("")
	lines.append("The branch reopens on %s." % BankCalendar.long_text(GameClock.date_of_day(_next_day)))
	summary_title_label.text = BankCalendar.closure_title(_closures)
	summary_label.text = "\n".join(lines)
	_closures = []
	_closure_shown = true

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
	if not _closures.is_empty():
		_show_closure()
		return
	_closure_shown = false
	close()
	next_day_requested.emit()
