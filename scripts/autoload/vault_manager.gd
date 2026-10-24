extends Node

## Autoload singleton — the branch vault's expected cash, in int cents (B3).
## It starts at VaultReconciliationScreen.STARTING_VAULT_CENTS and changes
## only by the teller's transfers (TellerScreen's Send to Vault / Get Cash
## from Vault), so the Branch Manager's vault reconciliation is graded
## against what the vault should really hold. Reset with the career
## (CareerReset) and saved with it (see SaveGame).

signal expected_changed(cents: int)

var expected_cents: int = VaultReconciliationScreen.STARTING_VAULT_CENTS

## The teller sold `cents` of cash to the vault.
func receive_from_drawer(cents: int) -> void:
	if cents <= 0:
		return
	expected_cents += cents
	expected_changed.emit(expected_cents)

## The teller bought `cents` of cash from the vault. Returns false (and
## changes nothing) if the vault doesn't hold that much.
func pay_to_drawer(cents: int) -> bool:
	if cents <= 0 or cents > expected_cents:
		return false
	expected_cents -= cents
	expected_changed.emit(expected_cents)
	return true

func reset() -> void:
	expected_cents = VaultReconciliationScreen.STARTING_VAULT_CENTS
	expected_changed.emit(expected_cents)

func save_data() -> Dictionary:
	return {"expected_cents": expected_cents}

## A save from before transfers existed has the starting total.
func load_data(data: Dictionary) -> void:
	expected_cents = maxi(0, SaveGame.int_of(data, "expected_cents", VaultReconciliationScreen.STARTING_VAULT_CENTS))
	expected_changed.emit(expected_cents)
