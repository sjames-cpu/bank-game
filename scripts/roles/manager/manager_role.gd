extends Node

## Autoload singleton: the Branch Manager role's own career data, saved in
## the career's "roles" > "manager" section and reset with the career
## (ROLE_BOUNDARIES.md: a role saves its data in its own section; a role
## doesn't register autoloads of its own, so this one is registered for it).
## The role is frozen until it's redesigned.
##
## Empty for now. Keep the Branch Manager's new saved values here: either in
## `section` (saved as it is), or as variables of their own, written by
## save_data() and read back by load_data(). Saves come back through JSON,
## so read numbers with SaveGame.int_of()/float_of() and the other typed
## getters. A save without this section loads it empty.

## Free-form saved data for the Branch Manager role.
var section: Dictionary = {}

func reset() -> void:
	section = {}

func save_data() -> Dictionary:
	return section.duplicate(true)

func load_data(data: Dictionary) -> void:
	section = data.duplicate(true)
