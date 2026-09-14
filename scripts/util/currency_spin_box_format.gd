extends RefCounted
class_name CurrencySpinBoxFormat

## SpinBox trims trailing zeros from its displayed value regardless of
## `step` — a $0.01-stepped box showing 0 renders "$ 0.0", not "$ 0.00",
## and 5 renders "$ 5.0", not "$ 5.00" (SpinBox's own display logic, not
## something `step` controls). Every other currency figure in the game is
## formatted "%.2f" (see Account/ShiftTransaction display code), so a
## currency SpinBox showing fewer decimals reads as an inconsistency/bug
## next to them. apply() forces a fixed 2 decimals by overwriting the
## SpinBox's internal LineEdit text after every value change — connected
## here (after the SpinBox's own internal display update already ran, at
## its own _ready()) so this one wins for the frame.

static func apply(spin_box: SpinBox) -> void:
	_refresh(spin_box)
	spin_box.value_changed.connect(func(_new_value: float) -> void: _refresh(spin_box))

static func _refresh(spin_box: SpinBox) -> void:
	var text := "%.2f" % spin_box.value
	if spin_box.prefix != "":
		text = "%s %s" % [spin_box.prefix, text]
	if spin_box.suffix != "":
		text = "%s %s" % [text, spin_box.suffix]
	spin_box.get_line_edit().text = text
