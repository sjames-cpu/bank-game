extends Control
class_name CashOrdersScreen

## The Branch Manager's cash orders (VaultManager): order cash in from the
## Federal Reserve Bank, or ship excess cash out to it, in standard straps of
## $100 notes, for delivery at opening on the next business day; one order a
## day. Shows the vault's expected total against its limits, what's pending,
## and a forecast for tomorrow's close. Opened from the Branch Manager hub;
## closed returns to it.

signal closed

@onready var panel: PanelContainer = $Panel
@onready var expected_label: Label = $Panel/VBox/VaultSection/VaultVBox/ExpectedLabel
@onready var limits_label: Label = $Panel/VBox/VaultSection/VaultVBox/LimitsLabel
@onready var warning_label: Label = $Panel/VBox/VaultSection/VaultVBox/WarningLabel
@onready var pending_label: Label = $Panel/VBox/VaultSection/VaultVBox/PendingLabel
@onready var forecast_label: Label = $Panel/VBox/VaultSection/VaultVBox/ForecastLabel
@onready var straps_input: SpinBox = $Panel/VBox/StrapsHBox/StrapsSpinBox
@onready var amount_label: Label = $Panel/VBox/StrapsHBox/AmountLabel
@onready var order_in_button: Button = $Panel/VBox/ButtonsHBox/OrderInButton
@onready var ship_out_button: Button = $Panel/VBox/ButtonsHBox/ShipOutButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

var _paused_by_self: bool = false

func _ready() -> void:
	visible = false
	order_in_button.pressed.connect(_place.bind(1))
	ship_out_button.pressed.connect(_place.bind(-1))
	close_button.pressed.connect(hide_screen)
	straps_input.value_changed.connect(func(_value: float) -> void: _refresh())
	limits_label.text = "Limits: %s – %s (middle %s)" % [MoneyMath.format(VaultManager.VAULT_MIN_CENTS, true), MoneyMath.format(VaultManager.VAULT_MAX_CENTS, true), MoneyMath.format(VaultManager.VAULT_MID_CENTS, true)]

func show_screen() -> void:
	status_label.visible = false
	_refresh()
	visible = true
	_paused_by_self = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true

func hide_screen() -> void:
	visible = false
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false
	closed.emit()

## The order's size: whole straps, as cents.
func order_cents() -> int:
	return roundi(straps_input.value) * VaultManager.STRAP_CENTS

## `direction` 1 orders cash in, -1 ships it out.
func _place(direction: int) -> void:
	var cents := order_cents() * direction
	var day := GameClock.day
	var refused := VaultManager.place_order(cents, day)
	if refused != "":
		_show_status(refused)
		return
	var what := "Ordered %s from the Federal Reserve" % MoneyMath.format(absi(cents), true) if cents > 0 else "Shipping %s to the Federal Reserve" % MoneyMath.format(absi(cents), true)
	var text := "%s, for %s." % [what, delivery_text(day + 1)]
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Cash order: %s" % text, "Cash order")
	_show_status(text)
	_refresh()

func _show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = true

## "Tue 20 Jan (Day 11)".
static func delivery_text(day: int) -> String:
	return "%s (Day %d)" % [BankCalendar.short_text(GameClock.date_of_day(day)), day]

func _refresh() -> void:
	expected_label.text = "Vault: %s" % MoneyMath.format(VaultManager.expected_cents)
	warning_label.text = VaultManager.limit_warning()
	warning_label.visible = warning_label.text != ""
	pending_label.text = pending_text()
	var day := GameClock.day
	var forecast := VaultManager.forecast_for_tomorrow(day, BusinessDay.staff_net_cash_cents)
	forecast_label.text = "Forecast for %s's close: %s" % [BankCalendar.short_text(GameClock.date_of_day(day + 1)), MoneyMath.format(forecast)]
	if forecast < VaultManager.VAULT_MIN_CENTS:
		forecast_label.text += " — below the minimum"
	elif forecast > VaultManager.VAULT_MAX_CENTS:
		forecast_label.text += " — above the maximum"
	amount_label.text = "= %s" % MoneyMath.format(order_cents(), true)
	var ordered := VaultManager.has_ordered(day)
	order_in_button.disabled = ordered
	ship_out_button.disabled = ordered
	if ordered and not status_label.visible:
		_show_status("Today's cash order is placed.")

## "Pending: in $50000 for Tue 20 Jan (Day 11)", one line per order, or
## "Pending: none".
static func pending_text() -> String:
	if VaultManager.pending_orders.is_empty():
		return "Pending: none"
	var lines: PackedStringArray = []
	for order in VaultManager.pending_orders:
		var cents: int = order["cents"]
		var delivery_day: int = order["delivery_day"]
		lines.append("Pending: %s %s for %s" % ["in" if cents > 0 else "out", MoneyMath.format(absi(cents), true), delivery_text(delivery_day)])
	return "\n".join(lines)
