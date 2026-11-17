extends Node
class_name SlotStatusProvider

## The shared interface through which the time-slot pieces say how the
## player's slot is going, so shared UI (the HUD's slot line, the card
## between slots) never knows about roles. Each role's adapter
## (TellerSlotAdapter, LoanSlotAdapter, ManagerSlotAdapter) and the shift's
## (ShiftSlotAdapter) extend it and answer only for what's theirs right now;
## SlotStatus asks them all.

const GROUP: StringName = &"slot_status_providers"

func _enter_tree() -> void:
	add_to_group(GROUP)

## The HUD's line for the slot running now ("Customers: 1 / 2"), or "" when
## it isn't this provider's.
func status_text() -> String:
	return ""

## Lines for the card about `slot`, just finished ("Customers you served:
## 2"), or none when it wasn't this provider's.
func slot_report(_slot: DaySlot) -> PackedStringArray:
	return PackedStringArray()
