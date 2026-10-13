extends Node

## Autoload singleton — which first-run hints (B4) this career has already
## seen. Each hint is shown once per career at the moment it's useful:
## teller_room.gd decides when, the HUD (hud.gd) shows and queues them, and
## this only remembers what's been shown so a scene reload doesn't repeat
## them. Reset with the career (CareerReset), like XPManager's
## has_seen_branch_orientation. In memory only, like the other managers.

enum Hint { ARRIVAL, FIRST_CUSTOMER, FIRST_CLOCK_OUT, LOAN_OFFICER_UNLOCKED, BRANCH_MANAGER_UNLOCKED }

## Hint -> true once shown.
var _shown: Dictionary = {}

func has_shown(hint: Hint) -> bool:
	return _shown.has(hint)

## Records `hint` as shown. Returns false if it already had been, so the
## caller knows not to show it again.
func mark_shown(hint: Hint) -> bool:
	if _shown.has(hint):
		return false
	_shown[hint] = true
	return true

func reset() -> void:
	_shown.clear()

## Player-facing text for `hint`; the interact key comes from the InputMap.
static func text_for(hint: Hint) -> String:
	var key := InputPrompts.key_for(InputPrompts.INTERACT)
	match hint:
		Hint.ARRIVAL:
			return "Walk with WASD or the arrow keys. Go to your teller window and press %s to clock in." % key
		Hint.FIRST_CUSTOMER:
			return "Do what the customer asks, then press Complete Transaction."
		Hint.FIRST_CLOCK_OUT:
			return "Count the drawer to finish your shift."
		Hint.LOAN_OFFICER_UNLOCKED:
			return "Loan Officer unlocked! The Loan Desk is left of the teller windows, between the two marketing desks. Walk up to it and press %s to clock in." % key
		Hint.BRANCH_MANAGER_UNLOCKED:
			return "Branch Manager unlocked! Your desk is in the Manager's Office at the back, through the doorway above the marketing desk right of the Loan Desk."
	return ""
