extends Node

## Autoload singleton — the career's loan applicants: the player's pile at
## Loan Desk 1 and every staff loan desk's next application, all from
## LoanApplicantGenerator, seeded per career so a career's applicants are the
## same every time it's played from the same save (and tests are
## deterministic).
##
## The player's pile (player_queue) always holds the next
## LoanOfficerScreen.APPLICATIONS_PER_SHIFT applications, the first being the
## one on the desk: one closed undecided stays first, a decided one leaves and
## a new one joins the end. A new career's pile is the three teaching cases
## (LoanApplicationsData.teaching_cases()), so the first Loan Officer shift
## works them, clear to borderline; everything after is generated. The staff
## desks draw a new applicant for each decision (next_staff_application()).
##
## No applicant's name repeats within a business day (GameClock.day): a new
## one avoids the names already seen today and those waiting in the pile.
##
## Each applicant comes from its own generators, seeded from career_seed and
## its number (generated_count): one for the finances, a separate one for the
## name and look (fair lending, see LoanApplicantGenerator). Reset with the
## career (CareerReset) and saved with it (SaveGame): the seed, the count,
## the pile (the pending application and those queued) and today's names.

## Where a new career's seed comes from: its own generator, so starting a
## career never draws from the global one. Tests seed it
## (teller_room_suite.gd).
var seed_source: RandomNumberGenerator = RandomNumberGenerator.new()

var career_seed: int = 0
## How many applicants this career has generated (the next one's number).
var generated_count: int = 0
var player_queue: Array[LoanApplication] = []
## The business day names_today belongs to.
var names_day: int = 0
var names_today: PackedStringArray = []

func _ready() -> void:
	seed_source.randomize()
	reset()

func reset() -> void:
	career_seed = seed_source.randi()
	generated_count = 0
	player_queue = LoanApplicationsData.teaching_cases()
	for application in player_queue:
		application.risk_assessment = application.calculate_risk_assessment()
	names_day = 0
	names_today = PackedStringArray()

func queue_size() -> int:
	return LoanOfficerScreen.APPLICATIONS_PER_SHIFT

# --- the player's pile -----------------------------------------------------------------

## The application on the player's desk (the pile's first), noted as seen
## today.
func current_player_application() -> LoanApplication:
	_top_up()
	var application := player_queue[0]
	_note_name(application.applicant_name)
	return application

## `application` was decided: it leaves the pile and a new one joins.
func player_decided(application: LoanApplication) -> void:
	var index := player_queue.find(application)
	if index != -1:
		player_queue.remove_at(index)
	_top_up()

func _top_up() -> void:
	while player_queue.size() < queue_size():
		player_queue.append(generate_application())

# --- the staff desks -----------------------------------------------------------------

func next_staff_application() -> LoanApplication:
	return generate_application()

# --- generating ------------------------------------------------------------------------

## The career's next applicant, named apart from today's.
func generate_application() -> LoanApplication:
	var number := generated_count
	generated_count += 1
	var application := LoanApplicantGenerator.generate(_rng_for("finance", number))
	LoanApplicantGenerator.assign_identity(application, _rng_for("identity", number), names_taken())
	_note_name(application.applicant_name)
	return application

func _rng_for(stream: String, number: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([career_seed, stream, number])
	return rng

## Names a new applicant can't have: today's, and those waiting in the pile.
func names_taken() -> Dictionary:
	_roll_day()
	var taken := {}
	for taken_name in names_today:
		taken[taken_name] = true
	for application in player_queue:
		taken[application.applicant_name] = true
	return taken

func _note_name(applicant_name: String) -> void:
	_roll_day()
	if not names_today.has(applicant_name):
		names_today.append(applicant_name)

func _roll_day() -> void:
	if names_day != GameClock.day:
		names_day = GameClock.day
		names_today = PackedStringArray()

# --- save and load ---------------------------------------------------------------------

func save_data() -> Dictionary:
	var queue: Array = []
	for application in player_queue:
		queue.append(SaveGame.resource_to_dict(application))
	return {
		"career_seed": career_seed,
		"generated_count": generated_count,
		"player_queue": queue,
		"names_day": names_day,
		"names_today": Array(names_today),
	}

## A save from before generated applicants keeps the new career's teaching
## cases unless that career had already reached Loan Officer (then its pile
## is generated when first needed). Call after XPManager.load_data().
func load_data(data: Dictionary) -> void:
	if not data.has("player_queue"):
		if XPManager.is_loan_officer_unlocked:
			player_queue.clear()
		return
	career_seed = SaveGame.int_of(data, "career_seed", career_seed)
	generated_count = maxi(0, SaveGame.int_of(data, "generated_count", 0))
	player_queue.clear()
	for entry in SaveGame.dicts_of(SaveGame.array_of(data, "player_queue")):
		var application := LoanApplication.new()
		SaveGame.fill_resource(application, entry)
		if not LoanApplication.PURPOSE_TERMS.has(application.loan_purpose):
			continue
		application.applicant_look = clampi(application.applicant_look, 0, CustomerNPC.CUSTOMER_FRAME_SETS.size() - 1)
		application.risk_assessment = application.calculate_risk_assessment()
		player_queue.append(application)
	names_day = SaveGame.int_of(data, "names_day", 0)
	names_today = SaveGame.strings_of(SaveGame.array_of(data, "names_today"))
