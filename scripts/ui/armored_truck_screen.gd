extends Control
class_name ArmoredTruckScreen

## The Branch Manager receives the armored truck at the vault door, under
## dual control (teller_room.gd, once the witness is there):
## 1. Crew check (bank security policy): each guard's ID badge against the
##    crew the carrier scheduled (company, names, badge numbers). Anything
##    that doesn't match: refuse and call it in.
## 2. Verify Shipment: each bag on the manifest (declared amount, seal
##    number) beside the bag delivered (its seal number, and whether the seal
##    is intact, or the bag is missing). Accept good bags, refuse problem
##    ones; then sign. A pickup's bags are handed over at the same signature.
## VaultManager.complete_visit() applies it (only accepted bags reach the
## vault; refused ones are re-delivered the next business day), and grade()
## scores it. Pauses the tree while open; closing it lets the crew and the
## witness go.

signal closed

## Grading (grade()). Handling a visit right is worth a little less than a
## Perfect vault count (+10/+2), with each problem bag caught worth a fair
## staff-review call (+3), and catching an unscheduled crew a Perfect count's
## worth. Signing for a problem bag is a serious error: the vault comes up
## short, so it costs as much as a Major count's Reputation's worth of Score
## (-10) and a dismissive complaint's Reputation (-3). Refusing a good bag
## only delays cash: a wrong request's Score (-3), no Reputation. Refusing the
## genuine crew delays the whole shipment (-5, -1). Handing cash to, or taking
## it from, an unscheduled crew is critical: twice a serious error's Score,
## a Reputation hit beyond a Major count, and a regional warning.
const CORRECT_SCORE: int = 8
const CORRECT_REPUTATION: int = 1
const PROBLEM_CAUGHT_SCORE: int = 3
const FAKE_CREW_CAUGHT_SCORE: int = 10
const FAKE_CREW_CAUGHT_REPUTATION: int = 2
const PROBLEM_SIGNED_SCORE: int = -10
const PROBLEM_SIGNED_REPUTATION: int = -3
const GOOD_REFUSED_SCORE: int = -3
const GENUINE_REFUSED_SCORE: int = -5
const GENUINE_REFUSED_REPUTATION: int = -1
const CRITICAL_SCORE: int = -20
const CRITICAL_REPUTATION: int = -8

const POLICY_TEXT: String = "Bank security policy: check each guard's ID badge against the scheduled crew before anything is handed over or signed. If anything doesn't match, refuse and call it in."

@onready var panel: PanelContainer = $Panel
@onready var policy_label: Label = $Panel/VBox/PolicyLabel
@onready var crew_grid: GridContainer = $Panel/VBox/CrewSection/CrewVBox/CrewGrid
@onready var accept_crew_button: Button = $Panel/VBox/CrewSection/CrewVBox/CrewButtonsHBox/AcceptCrewButton
@onready var refuse_crew_button: Button = $Panel/VBox/CrewSection/CrewVBox/CrewButtonsHBox/RefuseCrewButton
## Hidden once the crew check is decided, to keep the panel short.
@onready var crew_buttons: HBoxContainer = $Panel/VBox/CrewSection/CrewVBox/CrewButtonsHBox
@onready var shipment_section: PanelContainer = $Panel/VBox/ShipmentSection
@onready var bags_scroll: ScrollContainer = $Panel/VBox/ShipmentSection/ShipmentVBox/BagsScroll
@onready var bags_vbox: VBoxContainer = $Panel/VBox/ShipmentSection/ShipmentVBox/BagsScroll/BagsVBox
@onready var pickup_label: Label = $Panel/VBox/ShipmentSection/ShipmentVBox/PickupLabel
@onready var sign_button: Button = $Panel/VBox/ShipmentSection/ShipmentVBox/SignButton
@onready var result_label: Label = $Panel/VBox/ResultLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

## The bags' Accept toggles, in manifest order.
var accept_checks: Array[CheckButton] = []
var witness_name: String = ""
## The last visit's outcome and grade, once settled ({} before).
var last_outcome: Dictionary = {}
var last_grade: Dictionary = {}

const CREW_HEADING_WIDTH: float = 76.0

## Bag rows (about 50 px each, with the Accept toggle) show at most this many
## before the list scrolls.
const VISIBLE_BAG_ROWS: int = 3
const BAG_ROW_HEIGHT: float = 50.0

func _ready() -> void:
	visible = false
	policy_label.text = POLICY_TEXT
	accept_crew_button.pressed.connect(_on_accept_crew)
	refuse_crew_button.pressed.connect(_on_refuse_crew)
	sign_button.pressed.connect(_on_sign)
	close_button.pressed.connect(hide_screen)

func show_screen(visit: Dictionary, witness: String) -> void:
	witness_name = witness
	last_outcome = {}
	last_grade = {}
	_fill_crew(visit)
	_fill_bags(visit)
	shipment_section.visible = false
	result_label.visible = false
	close_button.visible = false
	accept_crew_button.disabled = false
	refuse_crew_button.disabled = false
	crew_buttons.visible = true
	visible = true
	get_tree().paused = true

func hide_screen() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()

## Scheduled crew (the carrier's dispatch) beside the badges the crew shows.
func _fill_crew(visit: Dictionary) -> void:
	for child in crew_grid.get_children():
		crew_grid.remove_child(child)
		child.queue_free()
	var scheduled: Dictionary = visit["scheduled"]
	var presented: Dictionary = visit["presented"]
	_crew_row("", "Scheduled", "Badge shown", true)
	var scheduled_company: String = scheduled["company"]
	var presented_company: String = presented["company"]
	_crew_row("Company", scheduled_company, presented_company, false)
	var scheduled_guards: Array = scheduled["guards"]
	var presented_guards: Array = presented["guards"]
	for i in scheduled_guards.size():
		var expected: Dictionary = scheduled_guards[i]
		var shown: Dictionary = presented_guards[i]
		_crew_row("Guard %d" % (i + 1), "%s · %s" % [expected["name"], expected["badge"]], "%s · %s" % [shown["name"], shown["badge"]], false)

## The row heading has a fixed width; the two crew columns share the rest
## and wrap.
func _crew_row(heading: String, scheduled: String, shown: String, header: bool) -> void:
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.custom_minimum_size.x = CREW_HEADING_WIDTH
	heading_label.theme_type_variation = &"MutedLabel"
	crew_grid.add_child(heading_label)
	for text: String in [scheduled, shown]:
		var label := Label.new()
		label.text = text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if header:
			label.theme_type_variation = &"MutedLabel"
		crew_grid.add_child(label)

## One row per bag: manifest, delivered, and an Accept toggle (on by default).
func _fill_bags(visit: Dictionary) -> void:
	for child in bags_vbox.get_children():
		bags_vbox.remove_child(child)
		child.queue_free()
	accept_checks.clear()
	var bags: Array = visit["bags"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var row := HBoxContainer.new()
		var manifest := Label.new()
		manifest.text = "Bag %d · %s · %s" % [i + 1, MoneyMath.format(SaveGame.int_of(bag, "declared", 0), true), bag["manifest_seal"]]
		manifest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(manifest)
		var delivered := Label.new()
		delivered.text = delivered_text(bag)
		delivered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(delivered)
		var check := CheckButton.new()
		check.text = "Accept"
		check.button_pressed = true
		row.add_child(check)
		bags_vbox.add_child(row)
		accept_checks.append(check)
	bags_scroll.visible = not bags.is_empty()
	bags_scroll.custom_minimum_size.y = BAG_ROW_HEIGHT * mini(bags.size(), VISIBLE_BAG_ROWS)
	var pickup: int = visit["pickup"]
	pickup_label.visible = pickup > 0
	pickup_label.text = "Pickup: hand over %s in %d sealed bag%s" % [MoneyMath.format(pickup, true), ceili(float(pickup) / VaultManager.BAG_MAX_CENTS), "" if pickup <= VaultManager.BAG_MAX_CENTS else "s"]
	sign_button.text = "Sign the Manifest" if not bags.is_empty() else "Hand Over and Sign"

## What the bag that came looks like: "S-123456 · seal intact", "S-123456 ·
## seal broken", or "Not delivered".
static func delivered_text(bag: Dictionary) -> String:
	if SaveGame.bool_of(bag, "missing", false):
		return "Not delivered"
	return "%s · seal %s" % [bag["seal"], "intact" if SaveGame.bool_of(bag, "intact", false) else "BROKEN"]

func _on_accept_crew() -> void:
	accept_crew_button.disabled = true
	refuse_crew_button.disabled = true
	crew_buttons.visible = false
	shipment_section.visible = true

func _on_refuse_crew() -> void:
	_settle(VaultManager.complete_visit(false, []))

func _on_sign() -> void:
	var accepted: Array[bool] = []
	for check in accept_checks:
		accepted.append(check.button_pressed)
	_settle(VaultManager.complete_visit(true, accepted))

## Grades the outcome, applies it, and shows what happened.
func _settle(outcome: Dictionary) -> void:
	last_outcome = outcome
	last_grade = grade(outcome)
	apply_grade(last_grade, outcome)
	accept_crew_button.disabled = true
	refuse_crew_button.disabled = true
	crew_buttons.visible = false
	shipment_section.visible = false
	result_label.text = last_grade["text"]
	result_label.modulate = TellerScreen.FEEDBACK_GOOD_COLOR if SaveGame.int_of(last_grade, "score", 0) > 0 else TellerScreen.FEEDBACK_BAD_COLOR
	result_label.visible = true
	close_button.visible = true

## Score, Reputation and whether it earns a regional warning, with the
## feedback, for complete_visit()'s outcome (see the constants above).
static func grade(outcome: Dictionary) -> Dictionary:
	var verdict: int = outcome["verdict"]
	var score := 0
	var reputation := 0
	var lines: PackedStringArray = []
	if verdict == VaultManager.ShipmentVerdict.CRITICAL:
		score = CRITICAL_SCORE
		reputation = CRITICAL_REPUTATION
		lines.append("Critical security breach: that wasn't the scheduled crew, and cash changed hands. Policy is to refuse and call it in. A regional warning follows.")
	elif not SaveGame.bool_of(outcome, "crew_accepted", false):
		if SaveGame.bool_of(outcome, "fake", false):
			score = FAKE_CREW_CAUGHT_SCORE
			reputation = FAKE_CREW_CAUGHT_REPUTATION
			lines.append("Good catch: not the scheduled crew. Refused and called in; the real shipment comes the next business day.")
		else:
			score = GENUINE_REFUSED_SCORE
			reputation = GENUINE_REFUSED_REPUTATION
			lines.append("That was the scheduled crew: refusing them delays the whole shipment to the next business day.")
	else:
		var bad_accepted: int = outcome["bad_accepted"]
		var bad_refused: int = outcome["bad_refused"]
		var good_refused: int = outcome["good_refused"]
		if bad_accepted == 0 and good_refused == 0:
			score += CORRECT_SCORE
			reputation += CORRECT_REPUTATION
			lines.append("Received correctly: crew checked, every bag verified.")
		if bad_refused > 0:
			score += PROBLEM_CAUGHT_SCORE * bad_refused
			lines.append("Good catch: %d problem bag%s refused, to be re-delivered." % [bad_refused, "" if bad_refused == 1 else "s"])
		if bad_accepted > 0:
			score += PROBLEM_SIGNED_SCORE * bad_accepted
			reputation += PROBLEM_SIGNED_REPUTATION * bad_accepted
			lines.append("Serious error: signed for %d problem bag%s; the vault is %s short." % [bad_accepted, "" if bad_accepted == 1 else "s", MoneyMath.format(SaveGame.int_of(outcome, "short", 0), true)])
		if good_refused > 0:
			score += GOOD_REFUSED_SCORE * good_refused
			lines.append("%d good bag%s refused: that cash is delayed a day." % [good_refused, "" if good_refused == 1 else "s"])
	var points := "%+d Score" % score
	if reputation != 0:
		points += ", %+d Reputation" % reputation
	lines.append("(%s)" % points)
	return {"score": score, "reputation": reputation, "warning": verdict == VaultManager.ShipmentVerdict.CRITICAL, "verdict": verdict, "text": " ".join(lines)}

## Applies a grade: Score (XP on gains), Reputation, the Regional review's
## record, a regional warning for a critical breach, and a history entry.
static func apply_grade(graded: Dictionary, outcome: Dictionary) -> void:
	var score: int = graded["score"]
	var reputation: int = graded["reputation"]
	ScoreManager.add_shift_score(score)
	if score > 0:
		XPManager.add_shift_xp(score)
	if reputation != 0:
		ReputationManager.add_reputation(reputation)
	RegionalManager.note_shipment(SaveGame.int_of(graded, "verdict", VaultManager.ShipmentVerdict.CORRECT))
	if SaveGame.bool_of(graded, "warning", false):
		RegionalManager.add_security_warning()
	var verdict_names: Array[String] = ["Correct", "Delay", "Serious", "Critical"]
	HistoryManager.add_record(DecisionRecord.Role.BRANCH_MANAGER, "Armored truck: %s%s" % [VaultManager.visit_note.trim_prefix("Armored truck: "), "" if SaveGame.bool_of(outcome, "crew_accepted", false) or not SaveGame.bool_of(outcome, "fake", false) else " (unscheduled crew refused)"], verdict_names[SaveGame.int_of(graded, "verdict", 0)])
