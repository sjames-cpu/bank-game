extends RefCounted
class_name DaySlot

## One time slot of the business day (DaySchedule.slots()): Opening, a work
## slot, or Closing. Built once by DaySchedule and shared, so treat it as
## read-only.

## A stable name for code and saves, e.g. &"slot_9am".
var id: StringName
## What the player sees, e.g. "9 AM".
var label: String
## When the slot starts, on a 24-hour clock.
var hour: int
var minute: int
## Whether the slot has work in it (customers, applications). Opening and
## Closing don't.
var is_work: bool

func _init(slot_id: StringName, slot_label: String, slot_hour: int, slot_minute: int, work: bool) -> void:
	id = slot_id
	label = slot_label
	hour = slot_hour
	minute = slot_minute
	is_work = work

## The start time in minutes since midnight, the unit GameClock uses.
func start_minutes() -> float:
	return hour * 60.0 + minute
