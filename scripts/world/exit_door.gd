extends Interactable
class_name ExitDoor

## The entrance doormat: off shift, the player can go home here and end the
## day early (teller_room.gd asks first, then shows the End of Day summary;
## see BusinessDay.go_home_early()). Like the other interactables it only
## detects the player and emits `interacted`.
##
## The node sits at the top edge of the doormat with its area below, so the
## HUD's prompt (placed below the node) shows under the player's feet.
