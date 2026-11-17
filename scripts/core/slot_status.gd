extends RefCounted
class_name SlotStatus

## What shared UI shows about the time-slot day (slots on only): the HUD's
## clock line ("Wed, Day 3 · 11 AM slot"), its slot line (from whichever
## SlotStatusProvider answers) and the card's report on a finished slot.
## Knows DayFlow and the providers, never a role.

const DAY_ENDED_TEXT: String = "End of Day"
const WORK_SLOT_TEXT: String = "%s slot"

## The HUD's top line: with slots on, the day and where it is in its slots
## (the clock only shows each slot's start time); otherwise GameClock's.
static func clock_text() -> String:
	if not DayFlow.slots_enabled:
		return GameClock.hud_text()
	var where := where_text()
	if where == "":
		return GameClock.hud_text()
	return "%s, Day %d · %s" % [BankCalendar.weekday_short(GameClock.today_date()), GameClock.day, where]

## "11 AM slot", "Opening", "Closing" or "End of Day"; "" with no day yet.
static func where_text() -> String:
	if DayFlow.end_of_day_due:
		return DAY_ENDED_TEXT
	if not DayFlow.is_running():
		return ""
	return slot_text(DayFlow.current_slot())

## "11 AM slot" for a work slot, else its name ("Opening").
static func slot_text(slot: DaySlot) -> String:
	if slot == null:
		return ""
	return WORK_SLOT_TEXT % slot.label if slot.is_work else slot.label

## The HUD's slot line: the first provider's, or "" (slots off, between
## slots, or nobody has anything to say).
static func status_text(tree: SceneTree) -> String:
	if not DayFlow.slots_enabled or not DayFlow.is_running() or DayFlow.is_between_slots():
		return ""
	for provider in _providers(tree):
		var text := provider.status_text()
		if text != "":
			return text
	return ""

## Every provider's lines about `slot`, just finished.
static func slot_report(tree: SceneTree, slot: DaySlot) -> PackedStringArray:
	var lines := PackedStringArray()
	if slot == null:
		return lines
	for provider in _providers(tree):
		lines.append_array(provider.slot_report(slot))
	return lines

static func _providers(tree: SceneTree) -> Array[SlotStatusProvider]:
	var providers: Array[SlotStatusProvider] = []
	for node in tree.get_nodes_in_group(SlotStatusProvider.GROUP):
		var provider := node as SlotStatusProvider
		if provider != null:
			providers.append(provider)
	return providers
