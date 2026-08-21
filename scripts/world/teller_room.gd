extends Node2D

## Root of the room. Listens for signals from interactable objects
## in the scene and decides what should happen.

@onready var teller_screen: Control = $UI/TellerScreen

func _ready() -> void:
	$TellerDesk.interacted.connect(_on_teller_desk_interacted)

func _on_teller_desk_interacted() -> void:
	teller_screen.show_screen()
