class_name CashDenominations
extends RefCounted

## The cash a teller drawer or the vault holds (HANDOFF.md design flaw: the
## old model had $1,000 and $500 bills and no coins): current US notes and
## coins, in int cents (B3, see MoneyMath), shared by DrawerCountScreen and
## VaultReconciliationScreen. Both screens build their count rows from
## here (build_grid()): bills in the left column, coins in the right.

## Largest first: $100, $50, $20, $10, $5 and $1 bills, then quarters,
## dimes, nickels and pennies.
const DENOMINATION_CENTS: Array[int] = [10000, 5000, 2000, 1000, 500, 100, 25, 10, 5, 1]
const LABELS: Array[String] = ["$100", "$50", "$20", "$10", "$5", "$1", "Quarters (25¢)", "Dimes (10¢)", "Nickels (5¢)", "Pennies (1¢)"]
## DENOMINATION_CENTS from here on are coins.
const FIRST_COIN: int = 6
## Most of any one piece a count row takes.
const MAX_PIECES: int = 99999

## Total of `quantities` (one per DENOMINATION_CENTS entry).
static func total_cents(quantities: Array[int]) -> int:
	var total := 0
	for i in DENOMINATION_CENTS.size():
		total += DENOMINATION_CENTS[i] * quantities[i]
	return total

## The fewest pieces making up `cents`, largest first: greedy is optimal
## for US notes and coins (a canonical system), and pennies make any amount.
static func fewest_pieces(cents: int) -> Array[int]:
	var quantities: Array[int] = []
	var remaining := maxi(0, cents)
	for denom in DENOMINATION_CENTS:
		var quantity := floori(float(remaining) / denom)
		quantities.append(quantity)
		remaining -= quantity * denom
	return quantities

static func piece_count(quantities: Array[int]) -> int:
	var count := 0
	for quantity in quantities:
		count += quantity
	return count

## Fills `grid` with a row per denomination, bills on the left and coins on
## the right under "Bills" and "Coins" headers, and returns the SpinBoxes in
## DENOMINATION_CENTS order.
static func build_grid(grid: GridContainer) -> Array[SpinBox]:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	var inputs: Array[SpinBox] = []
	for i in DENOMINATION_CENTS.size():
		var spin := SpinBox.new()
		spin.name = "Denom%dSpinBox" % DENOMINATION_CENTS[i]
		spin.max_value = MAX_PIECES
		spin.step = 1.0
		spin.select_all_on_focus = true
		inputs.append(spin)
	var bills := FIRST_COIN
	var coins := DENOMINATION_CENTS.size() - FIRST_COIN
	_add_label(grid, "Bills")
	_add_label(grid, "")
	_add_label(grid, "Coins")
	_add_label(grid, "")
	for row in maxi(bills, coins):
		for i: int in [row, FIRST_COIN + row]:
			var in_column := row < (bills if i < FIRST_COIN else coins)
			if in_column:
				_add_label(grid, LABELS[i])
				grid.add_child(inputs[i])
			else:
				_add_label(grid, "")
				_add_label(grid, "")
	return inputs

static func _add_label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
