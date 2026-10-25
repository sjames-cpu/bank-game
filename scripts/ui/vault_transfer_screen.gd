extends Control
class_name VaultTransferScreen

## The teller's cash transfers with the vault, opened at the vault door once
## both people are there (VaultDualControl, teller_room.gd): the player, on a
## teller shift, and the staff member witnessing. Send to Vault / Get Cash
## from Vault move whole dollars; the accounting itself is TellerScreen's
## (send_to_vault()/get_from_vault()), so the drawer, its closing count and
## the vault's expected total stay exact. Pauses the tree while open, like
## the desk screens.

signal closed

## Set by teller_room.gd.
var teller_screen: TellerScreen

## Who's witnessing this visit.
var witness_name: String = ""

@onready var panel: PanelContainer = $Panel
@onready var dual_control_label: Label = $Panel/VBox/DualControlLabel
@onready var cash_label: Label = $Panel/VBox/DrawerSection/DrawerVBox/CashLabel
@onready var limits_label: Label = $Panel/VBox/DrawerSection/DrawerVBox/LimitsLabel
@onready var warning_label: Label = $Panel/VBox/DrawerSection/DrawerVBox/WarningLabel
## "Vault low" / "Vault over limit" (VaultManager.limit_warning()). Get Cash
## from Vault still can't take the vault below zero (pay_to_drawer()).
@onready var vault_warning_label: Label = $Panel/VBox/VaultWarningLabel
@onready var amount_input: SpinBox = $Panel/VBox/AmountSpinBox
@onready var send_button: Button = $Panel/VBox/ButtonsHBox/SendButton
@onready var get_button: Button = $Panel/VBox/ButtonsHBox/GetButton
@onready var receipt_label: Label = $Panel/VBox/ReceiptLabel
@onready var error_label: Label = $Panel/VBox/ErrorLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

func _ready() -> void:
	visible = false
	send_button.pressed.connect(_on_send_pressed)
	get_button.pressed.connect(_on_get_pressed)
	close_button.pressed.connect(hide_screen)
	limits_label.text = "Min %s · Max %s" % [MoneyMath.format(TellerScreen.DRAWER_MIN_CENTS, true), MoneyMath.format(TellerScreen.DRAWER_MAX_CENTS, true)]

func show_screen(witness: String) -> void:
	witness_name = witness
	dual_control_label.text = "Dual control: you and %s" % witness
	amount_input.value = 0
	receipt_label.visible = false
	error_label.visible = false
	_refresh()
	visible = true
	get_tree().paused = true

func hide_screen() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()

func _on_send_pressed() -> void:
	_transfer(teller_screen.send_to_vault(_amount_cents(), witness_name))

func _on_get_pressed() -> void:
	_transfer(teller_screen.get_from_vault(_amount_cents(), witness_name))

## Whole dollars, as cents.
func _amount_cents() -> int:
	return roundi(amount_input.value) * 100

## `error` is "" when the transfer went through: the receipt line shows.
func _transfer(error: String) -> void:
	error_label.text = error
	error_label.visible = error != ""
	if error == "":
		receipt_label.text = teller_screen.last_transfer_receipt
		receipt_label.visible = true
		amount_input.value = 0
	_refresh()

func _refresh() -> void:
	cash_label.text = "Drawer cash: %s" % MoneyMath.format(teller_screen.drawer_cash_cents())
	warning_label.text = teller_screen.drawer_limit_warning()
	warning_label.visible = warning_label.text != ""
	vault_warning_label.text = VaultManager.limit_warning()
	vault_warning_label.visible = vault_warning_label.text != ""
