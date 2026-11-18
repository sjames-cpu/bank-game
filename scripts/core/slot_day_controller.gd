extends Node
class_name SlotDayController

## Starts and drives the room's time-slot day, so the room itself holds no
## slot code (placed by SlotWiring):
## - starts today's slots at Opening when the room is ready, and the next
##   day's after "Start Day N+1", waiting between slots for the card;
## - the entrance doormat: going home early is on the card between slots;
## - the debug skip-slot key (F3, DEBUG_SKIP_SLOT_ACTION; decision 4),
##   debug builds only (TellerRoom.debug_cheats_enabled).

const DEBUG_SKIP_SLOT_ACTION: StringName = &"debug_skip_slot"
## The doormat's notice when pressed, and its prompt (TellerRoom builds the
## prompts and reads this one).
const GO_HOME_BETWEEN_SLOTS_TEXT: String = "You can go home early between slots, from the slot card."
const GO_HOME_SLOTS_PROMPT: String = "Going home early is on the card between slots"

var room: TellerRoom

func _ready() -> void:
	room.exit_door.interacted.connect(_on_exit_door_interacted)
	# After the room's own handler (BusinessDay.start_next_day() and the save).
	room.end_of_day_screen.next_day_requested.connect(start_day)
	start_day()

## Starts today's time slots at Opening, waiting between slots for the
## card. Never while a day is running or its End of Day is due, so a day
## never starts twice or straight from an End of Day: the next one starts
## from "Start Day N+1". A career loaded from a save whose day had ended has
## its End of Day due already (DayFlow.load_data()), so it comes back to that
## End of Day.
func start_day() -> void:
	if DayFlow.is_running() or DayFlow.end_of_day_due:
		return
	DayFlow.pause_between_slots = true
	DayFlow.start_day()

func _on_exit_door_interacted() -> void:
	if room.end_of_day_screen.visible or room.is_player_on_shift():
		return
	room.show_timed_notice(GO_HOME_BETWEEN_SLOTS_TEXT, TellerRoom.DESK_NOTICE_SECONDS)

func _unhandled_input(event: InputEvent) -> void:
	if room.debug_cheats_enabled and event.is_action_pressed(DEBUG_SKIP_SLOT_ACTION) and not event.is_echo():
		debug_skip_slot()
		get_viewport().set_input_as_handled()

## F3: skips the current time slot (debug builds). Returns whether it did.
func debug_skip_slot() -> bool:
	if not room.debug_cheats_enabled or not DayFlow.is_running() or DayFlow.is_between_slots():
		return false
	return DayFlow.skip_slot()
