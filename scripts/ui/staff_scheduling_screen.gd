extends Control
class_name StaffSchedulingScreen

## Staff scheduling screen (Phase 5c). Displays the full roster from
## StaffRosterData (5b) and lets the player assign eligible staff to a
## fixed set of shift slots, then commit that assignment to
## ScheduleManager via "Confirm Schedule."
##
## Phase 5f wires this into branch_manager_screen.gd's shift hub, which
## instances this screen and opens it from a menu button. `closed`
## (emitted from hide_screen(), same as drawer_count_screen.gd) is how the
## hub knows to bring its own menu back; there's no equivalent "graded"
## signal to emit since scheduling has no Score/Reputation/XP consequence
## yet (the hub reads ScheduleManager's own schedule_confirmed signal
## directly instead of this screen re-announcing it).
##
## class_name added for that same reason LoanReviewScreen got one in 4f —
## so branch_manager_screen.gd can hold a typed reference to this screen
## and connect to `closed` directly.
##
## Manages its own pause state the same defensive way
## drawer_count_screen.gd does (_paused_by_self tracks whether *this*
## screen was the one that paused, so hide_screen() never unpauses a tree
## something else still needs paused) — branch_manager_screen.gd pauses
## for the whole shift the same way teller_screen.gd/loan_officer_screen.gd
## do, so this stays defensive rather than assuming it's always the one in
## charge of pausing.
##
## Each slot is one OptionButton listing only staff whose `role` matches
## the slot, plus an "Unassigned" option — the eligible StaffMember (or
## null for Unassigned) is stashed directly on each item via
## set_item_metadata() rather than kept in a parallel lookup array, so
## reading the current selection back is a single get_item_metadata()
## call away.

signal closed

## Fixed shift slots, 2 per role — few enough to stay clear as "a first
## version" (per the brief) while still leaving one qualified staff
## member unscheduled per role in the current 6-person roster, so which
## two to pick is an actual choice rather than "assign everyone."
const SHIFT_SLOTS: Array[Dictionary] = [
	{"name": "Teller Shift 1", "role": "Teller"},
	{"name": "Teller Shift 2", "role": "Teller"},
	{"name": "Loan Officer Shift 1", "role": "Loan Officer"},
	{"name": "Loan Officer Shift 2", "role": "Loan Officer"},
]

@onready var roster_vbox: VBoxContainer = $Panel/VBox/RosterScrollContainer/RosterVBox
@onready var slots_grid: GridContainer = $Panel/VBox/SlotsGrid
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var confirm_button: Button = $Panel/VBox/ConfirmButton
@onready var close_button: Button = $Panel/VBox/CloseButton

var _paused_by_self: bool = false
var _slot_option_buttons: Array[OptionButton] = []

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	confirm_button.pressed.connect(_on_confirm_button_pressed)

	_populate_roster()
	_populate_slots()

func show_screen() -> void:
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

func _on_close_button_pressed() -> void:
	hide_screen()

func _populate_roster() -> void:
	for staff in StaffRosterData.get_staff():
		var entry := Label.new()
		entry.text = "%s (%s)\nSkill %d | Reliability %d | Speed %d | Customer Service %d\n\"%s\"" % [
			staff.staff_name, staff.role, staff.skill, staff.reliability, staff.speed, staff.customer_service, staff.flavor_text,
		]
		roster_vbox.add_child(entry)
		roster_vbox.add_child(HSeparator.new())

func _populate_slots() -> void:
	var all_staff := StaffRosterData.get_staff()

	for slot in SHIFT_SLOTS:
		var slot_label := Label.new()
		slot_label.text = slot["name"]
		slots_grid.add_child(slot_label)

		var option_button := OptionButton.new()
		option_button.add_item("Unassigned")
		option_button.set_item_metadata(0, null)

		for staff in all_staff:
			if staff.role == slot["role"]:
				var item_index := option_button.item_count
				option_button.add_item(staff.staff_name)
				option_button.set_item_metadata(item_index, staff)

		slots_grid.add_child(option_button)
		_slot_option_buttons.append(option_button)

func _on_confirm_button_pressed() -> void:
	var new_schedule: Dictionary = {}
	var assigned_names: Array[String] = []

	for i in SHIFT_SLOTS.size():
		var option_button := _slot_option_buttons[i]
		var selected_staff: StaffMember = option_button.get_item_metadata(option_button.selected)
		if selected_staff != null:
			var slot_name: String = SHIFT_SLOTS[i]["name"]
			new_schedule[slot_name] = selected_staff
			assigned_names.append("%s: %s" % [slot_name, selected_staff.staff_name])

	ScheduleManager.confirm_schedule(new_schedule)

	status_label.visible = true
	if assigned_names.is_empty():
		status_label.text = "Schedule confirmed — no shifts assigned."
	else:
		status_label.text = "Schedule confirmed —\n%s" % "\n".join(assigned_names)
