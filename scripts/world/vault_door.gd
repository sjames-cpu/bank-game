extends Interactable
class_name VaultDoor

## The vault's door, inside the Vault room at the back. Every vault action
## happens here under dual control (VaultDualControl): the teller's cash
## transfers, and the Branch Manager's vault reconciliation. Like the other
## interactables it only detects the player and emits `interacted`;
## teller_room.gd decides what happens.
