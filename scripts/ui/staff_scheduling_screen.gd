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
##
## Layout: everything sits in one auto-sizing PanelContainer, like the other
## screens, so the panel always covers its content. The roster scrolls in a
## fixed-height area with wrapping entries, and the desks are laid out in two
## columns, teller windows left and loan desks right, so even a Branch
## Manager's six desks keep the panel inside the 648px window and clear of
## the HUD column (screen_fit_test.gd).

signal closed

## The slots are the branch's staffed desks (ScheduleManager.DESK_SLOTS:
## two teller windows, three loan desks), so the six-person roster leaves a
## teller off the floor until Teller Window 3 opens. Each slot starts on its
## current assignment so confirming without changes keeps the desks as
## they are. Rebuilt every time the screen opens, since Teller Window 3
## only exists after promotion (ScheduleManager.get_desk_slots()).
var _shift_slots: Array[Dictionary] = []

@onready var roster_vbox: VBoxContainer = $Panel/VBox/RosterScrollContainer/RosterVBox
## Teller windows' rows (left) and loan desks' rows (right).
@onready var teller_grid: GridContainer = $Panel/VBox/SlotsColumns/TellerGrid
@onready var loan_grid: GridContainer = $Panel/VBox/SlotsColumns/LoanGrid
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
	_populate_roster()
	_populate_slots()
	status_label.visible = false
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

## Rebuilt on every open: staff reports change during play, and terminated
## staff (ScheduleManager.get_roster()) are no longer listed.
func _populate_roster() -> void:
	for child in roster_vbox.get_children():
		roster_vbox.remove_child(child)
		child.queue_free()
	for staff in ScheduleManager.get_roster():
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.text = "%s (%s) — Reports: %d / %d\nSkill %d | Reliability %d | Speed %d | Customer Service %d\n\"%s\"" % [
			staff.staff_name, staff.role,
			StaffReviewManager.reports_for(staff.staff_name), StaffReviewManager.STAFF_REPORTS_FOR_TERMINATION,
			staff.skill, staff.reliability, staff.speed, staff.customer_service, staff.flavor_text,
		]
		roster_vbox.add_child(entry)
		roster_vbox.add_child(HSeparator.new())

func _populate_slots() -> void:
	for grid: GridContainer in [teller_grid, loan_grid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_slot_option_buttons.clear()
	_shift_slots = ScheduleManager.get_desk_slots()
	var all_staff := ScheduleManager.get_roster()

	for slot in _shift_slots:
		var grid := loan_grid if slot["role"] == "Loan Officer" else teller_grid
		var slot_label := Label.new()
		slot_label.text = slot["name"]
		grid.add_child(slot_label)

		var option_button := OptionButton.new()
		option_button.add_item("Unassigned")
		option_button.set_item_metadata(0, null)

		var slot_name: String = slot["name"]
		var assigned := ScheduleManager.get_assigned(slot_name)
		for staff in all_staff:
			# The current assignee is always listed — Teller Window 3's default
			# can be a non-Teller if no Teller was free.
			var is_assigned := assigned != null and assigned.staff_name == staff.staff_name
			if staff.role == slot["role"] or is_assigned:
				var item_index := option_button.item_count
				option_button.add_item(staff.staff_name)
				option_button.set_item_metadata(item_index, staff)
				if assigned != null and assigned.staff_name == staff.staff_name:
					option_button.select(item_index)

		var slot_index := _slot_option_buttons.size()
		option_button.item_selected.connect(_on_slot_option_selected.bind(slot_index))

		grid.add_child(option_button)
		_slot_option_buttons.append(option_button)

## Same-role slots share the same staff list (e.g. both Teller slots), so
## nothing stops picking the same StaffMember for two slots at once
## otherwise. Whichever slot the player just changed wins the assignment;
## any other slot already holding that same staff member is bumped back
## to Unassigned so nobody's double-booked into simultaneous shifts.
func _on_slot_option_selected(_item_index: int, changed_slot_index: int) -> void:
	var changed_button := _slot_option_buttons[changed_slot_index]
	var selected_staff: StaffMember = changed_button.get_item_metadata(changed_button.selected)
	if selected_staff == null:
		return

	for i in _slot_option_buttons.size():
		if i == changed_slot_index:
			continue
		var other_button := _slot_option_buttons[i]
		var other_staff: StaffMember = other_button.get_item_metadata(other_button.selected)
		if other_staff == selected_staff:
			other_button.select(0)

func _on_confirm_button_pressed() -> void:
	var new_schedule: Dictionary = {}
	var unassigned: Array[String] = []

	for i in _shift_slots.size():
		var option_button := _slot_option_buttons[i]
		var selected_staff: StaffMember = option_button.get_item_metadata(option_button.selected)
		if selected_staff != null:
			var slot_name: String = _shift_slots[i]["name"]
			new_schedule[slot_name] = selected_staff
		else:
			unassigned.append(_shift_slots[i]["name"])

	ScheduleManager.confirm_schedule(new_schedule)

	# One short line: the desks are listed just above.
	status_label.visible = true
	status_label.text = "Schedule confirmed — %d of %d desks staffed." % [new_schedule.size(), _shift_slots.size()]
	if not unassigned.is_empty():
		status_label.text += " Unassigned: %s." % ", ".join(unassigned)
