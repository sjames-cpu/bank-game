extends VBoxContainer
class_name LoanClosingPanel

## The Loan Officer's closing screen: what the review screen shows in place of
## the worksheet columns when the application on the desk is a closing
## (LoanClosing). Built in code, so the review screen's scene is unchanged.
##
## On the left, the terms as approved (frozen on the closing). After "Run
## closing check", on the right, the paperwork the applicant brought: the
## amount, rate, term and monthly payment as written, the photo ID's expiry
## date beside today's date, whether it is signed, and the monthly debt
## payments at approval beside those now, with the total debt-to-income of
## each (always both, so the display doesn't say which closings have a
## problem). Nothing is highlighted, flagged or marked: the player compares.
## "Fund the loan" waits for the check; "Stop the closing" is always there.
##
## The first closing of a career (number 1) has a short explanation of what a
## closing is and what to compare. No career state of its own.

signal fund_requested
signal stop_requested

const CHECK_TEXT: String = "Run closing check"
const FUND_TEXT: String = "Fund the loan"
const STOP_TEXT: String = "Stop the closing"
const CHECK_FIRST_TEXT: String = "Run the closing check first."
const PLACEHOLDER_TEXT: String = "Run the closing check to see the paperwork the applicant brought."
const APPROVED_TITLE: String = "Terms you approved"
const PAPERWORK_TITLE: String = "Closing-day paperwork"
const FIRST_CLOSING_TEXT: String = "A closing is the last step before a loan is paid out: the applicant comes back to sign.\nRun the closing check, then compare the paperwork with the terms you approved: the amount, rate, term and payment, the photo ID and its expiry date, the signature, and any new debt.\nFund the loan if everything matches. Stop the closing if something is wrong."
## What a refused or failed Fund or Stop says (the reason follows).
const NOT_COMPLETED_TEXT: String = "Closing not completed: %s"
const NOT_DUE_TEXT: String = "this closing is due on %s."
const NOT_OPEN_TEXT: String = "it is no longer open."

const COMPACT_FONT_SIZE: int = 13
## A wrapping label needs a width of its own to start from (without one it
## wraps at a single character before the layout settles and leaves the panel
## thousands of pixels tall): a full-width line, and a column of the two.
const LINE_WIDTH: float = 860.0
const COLUMN_WIDTH: float = 400.0

var shown_closing: LoanClosing = null
## The closing check has been run on the closing shown.
var checked: bool = false
## Fund or Stop went through.
var finished: bool = false

var portrait: TextureRect
var name_label: Label
var subtitle_label: Label
var explanation_label: Label
var approved_title_label: Label
var approved_label: Label
var paperwork_title_label: Label
var paperwork_label: Label
var check_button: Button
var fund_button: Button
var stop_button: Button
var note_label: Label
var status_label: Label

func _init() -> void:
	add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	add_child(header)
	portrait = TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(56, 56)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(portrait)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(names)
	name_label = Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	names.add_child(name_label)
	subtitle_label = Label.new()
	names.add_child(subtitle_label)

	explanation_label = _wrapped_label()
	explanation_label.text = FIRST_CLOSING_TEXT
	add_child(explanation_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	add_child(columns)
	var left := _section(columns)
	approved_title_label = _title(left, APPROVED_TITLE)
	approved_label = _wrapped_label(false, COLUMN_WIDTH)
	left.add_child(approved_label)
	var right := _section(columns)
	paperwork_title_label = _title(right, PAPERWORK_TITLE)
	paperwork_label = _wrapped_label(false, COLUMN_WIDTH)
	right.add_child(paperwork_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	check_button = Button.new()
	check_button.text = CHECK_TEXT
	check_button.pressed.connect(run_check)
	buttons.add_child(check_button)
	fund_button = Button.new()
	fund_button.text = FUND_TEXT
	fund_button.pressed.connect(_on_fund_pressed)
	buttons.add_child(fund_button)
	stop_button = Button.new()
	stop_button.text = STOP_TEXT
	stop_button.pressed.connect(_on_stop_pressed)
	buttons.add_child(stop_button)
	note_label = _wrapped_label()
	add_child(note_label)
	status_label = _wrapped_label()
	add_child(status_label)
	visible = false

## A section panel in `columns` with a box for its rows.
func _section(columns: HBoxContainer) -> VBoxContainer:
	var section := PanelContainer.new()
	section.theme_type_variation = &"SectionPanel"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(section)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	section.add_child(box)
	return box

func _title(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	parent.add_child(label)
	return label

func _wrapped_label(compact: bool = true, width: float = LINE_WIDTH) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		label.add_theme_font_size_override("font_size", COMPACT_FONT_SIZE)
	return label

# --- showing a closing -----------------------------------------------------------------

## Shows `for_closing`, the check not yet run.
func show_closing(for_closing: LoanClosing) -> void:
	shown_closing = for_closing
	checked = false
	finished = false
	var application := for_closing.application
	portrait.texture = CustomerNPC.portrait_of(clampi(application.applicant_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1))
	name_label.text = "Closing: %s" % application.applicant_name
	subtitle_label.text = "%s loan · closing day %s" % [application.loan_purpose, BankCalendar.short_text(for_closing.closing_date())]
	explanation_label.visible = for_closing.number == 1
	approved_label.text = "\n".join(approved_lines(for_closing))
	paperwork_label.text = PLACEHOLDER_TEXT
	check_button.visible = true
	check_button.disabled = false
	fund_button.visible = true
	fund_button.disabled = true
	stop_button.visible = true
	stop_button.disabled = false
	note_label.text = CHECK_FIRST_TEXT
	note_label.visible = true
	status_label.text = ""
	status_label.visible = false

## Run closing check: the paperwork appears and Fund the loan is allowed.
func run_check() -> void:
	if shown_closing == null or checked or finished:
		return
	checked = true
	paperwork_label.text = "\n".join(paperwork_lines(shown_closing, GameClock.today_date()))
	check_button.disabled = true
	fund_button.disabled = false
	note_label.visible = false

func _on_fund_pressed() -> void:
	if fund_button.disabled or finished:
		return
	fund_requested.emit()

func _on_stop_pressed() -> void:
	if stop_button.disabled or finished:
		return
	stop_requested.emit()

## A message under the buttons (a refusal, a failure): nothing changed.
func show_message(text: String) -> void:
	status_label.text = text
	status_label.visible = true

## Fund or Stop went through: the buttons go and the feedback stays.
func show_result(text: String) -> void:
	finished = true
	check_button.visible = false
	fund_button.visible = false
	stop_button.visible = false
	note_label.visible = false
	status_label.text = text
	status_label.visible = true

# --- what is shown (static, for tests) ---------------------------------------------------

## "$396.02": a payment with its cents.
static func payment_text(amount: float) -> String:
	var cents := roundi(amount * 100.0)
	var whole := floori(cents / 100.0)
	return "%s.%02d" % [LoanApplication.dollars(float(whole)), cents - whole * 100]

static func rate_text(rate: float) -> String:
	return "%.2f%%" % (rate * 100.0)

static func term_text(months: int) -> String:
	return "%d months" % months

## The terms as approved, one line each.
static func approved_lines(closing: LoanClosing) -> PackedStringArray:
	var lines := PackedStringArray()
	if closing.kind == LoanClosing.Kind.COUNTER_OFFER:
		lines.append("Accepted counter-offer: %s offered, %s requested" % [LoanApplication.dollars(closing.approved_amount), LoanApplication.dollars(closing.application.requested_amount)])
	else:
		lines.append("Approved as requested")
	lines.append("Loan amount: %s" % LoanApplication.dollars(closing.approved_amount))
	lines.append("Interest rate: %s" % rate_text(closing.approved_rate))
	lines.append("Term: %s" % term_text(closing.approved_term))
	lines.append("Monthly payment: %s" % payment_text(closing.approved_payment))
	lines.append("Approved on %s" % BankCalendar.short_text(GameClock.date_of_day(closing.approval_day)))
	return lines

## The paperwork as the applicant brought it, one line each. Both debt lines
## are always there, and nothing says whether anything is wrong.
static func paperwork_lines(closing: LoanClosing, today_date: int) -> PackedStringArray:
	var application := closing.application
	var holder := application.id_holder_name if application.id_holder_name != "" else application.applicant_name
	var debts := application.monthly_debt_payments
	var lines := PackedStringArray()
	lines.append("Loan amount: %s" % LoanApplication.dollars(closing.paper_amount))
	lines.append("Interest rate: %s" % rate_text(closing.paper_rate))
	lines.append("Term: %s" % term_text(closing.paper_term))
	lines.append("Monthly payment: %s" % payment_text(closing.paper_payment))
	lines.append("Photo ID: %s · expires %s (today is %s)" % [holder, IdCard.date_text(closing.id_expiry_date), IdCard.date_text(today_date)])
	lines.append("Signature: %s" % ("signed" if closing.signed else "not signed"))
	lines.append("Monthly debt payments at approval: %s · total DTI %s" % [LoanApplication.dollars(debts), LoanApplication.percent(closing.dti_at_approval())])
	lines.append("Monthly debt payments now: %s · total DTI %s" % [LoanApplication.dollars(debts + closing.new_debt_payment), LoanApplication.percent(closing.dti_with_new_debt())])
	return lines

## What was wrong with the closing, in words from what the paperwork showed
## (never a hidden value), or that everything matched.
static func fact_text(closing: LoanClosing, today_date: int) -> String:
	match closing.problem:
		LoanClosing.Problem.TERMS:
			match closing.terms_field:
				LoanClosing.TermsField.AMOUNT:
					return "The amount on the paperwork (%s) did not match the approved %s." % [LoanApplication.dollars(closing.paper_amount), LoanApplication.dollars(closing.approved_amount)]
				LoanClosing.TermsField.RATE:
					return "The rate on the paperwork (%s) did not match the approved %s." % [rate_text(closing.paper_rate), rate_text(closing.approved_rate)]
				LoanClosing.TermsField.TERM:
					return "The term on the paperwork (%s) did not match the approved %s." % [term_text(closing.paper_term), term_text(closing.approved_term)]
				_:
					return "The monthly payment on the paperwork (%s) did not match the approved %s." % [payment_text(closing.paper_payment), payment_text(closing.approved_payment)]
		LoanClosing.Problem.EXPIRED_ID:
			return "The photo ID had expired on %s; today is %s." % [IdCard.date_text(closing.id_expiry_date), IdCard.date_text(today_date)]
		LoanClosing.Problem.NO_SIGNATURE:
			return "The paperwork was not signed."
		LoanClosing.Problem.NEW_DEBT:
			return "A new debt of %s a month had appeared since the approval: total DTI went from %s to %s." % [LoanApplication.dollars(closing.new_debt_payment), LoanApplication.percent(closing.dti_at_approval()), LoanApplication.percent(closing.dti_with_new_debt())]
	return "Everything matched the approval."

## The feedback after Fund (`funded`) or Stop: what it was worth (`result`, from
## LoanBookManager.fund() or stop()) and what was right or missed. `checked`:
## whether the closing check had been run (a Stop can come before it).
static func feedback(closing: LoanClosing, funded: bool, result: Dictionary, was_checked: bool, today_date: int) -> String:
	var problem := closing.has_problem()
	var headline: String
	if funded:
		headline = "Loan funded, but the closing had a problem: a serious mistake." if problem else "Loan funded."
	else:
		headline = "Closing stopped: good catch." if problem else "Closing stopped, but nothing was wrong."
	var lines := PackedStringArray()
	lines.append("%s (%+d Score, %+d Reputation, %+d XP)" % [headline, result["score"], result["reputation"], result["xp"]])
	if not funded and not was_checked:
		lines.append("You stopped it without running the closing check.")
	lines.append(fact_text(closing, today_date))
	return "\n".join(lines)
