extends "res://tests/support/loan/loan_suite.gd"

## Part 1 of multi-day loan applications: the rules and data behind files
## waiting for documents (LoanPipeline, LoanFile, LoanRequirements, LoanConfig,
## saved in LoanRole's section). No screens: nothing here changes what a
## player sees. Covers the save and load round trip (and a save with no
## pipeline), the deterministic return, the measured rates, independence from
## name, look and finances, the due-day maths across weekends and holidays,
## expiry, the caps, and the names of open files.

const OLD_SAVE := "res://tests/data/old_saves/v2_switch_off_mid_day.json"

const PAY_STUB := LoanRequirements.Item.PAY_STUB
const STATEMENT := LoanRequirements.Item.BANK_STATEMENT
const PHOTO_ID := LoanRequirements.Item.PHOTO_ID
const APPRAISAL := LoanRequirements.Item.APPRAISAL
const DOWN_PAYMENT := LoanRequirements.Item.DOWN_PAYMENT_PROOF
const LETTER := LoanRequirements.Item.EXPLANATION_LETTER

# --- helpers -------------------------------------------------------------------

## The career as it would come back from a save file: through JSON.
func through_json(career: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(career, "", false, true))
	return parsed

## A generated applicant, built the way LoanDeskManager builds one but from a
## seed of the test's own (so any number of them, with no name limits).
func make_application(number: int) -> LoanApplication:
	var finance := RandomNumberGenerator.new()
	finance.seed = hash(["pipeline test finance", number])
	var application := LoanApplicantGenerator.generate(finance)
	var identity := RandomNumberGenerator.new()
	identity.seed = hash(["pipeline test identity", number])
	LoanApplicantGenerator.assign_identity(application, identity, {})
	var documents := RandomNumberGenerator.new()
	documents.seed = hash(["pipeline test documents", number])
	LoanApplicantGenerator.issue_documents(application, documents, GameClock.today_date())
	return application

## A file made by hand, rolled from `career_seed`, on a due day of 10.
func rolled_file(career_seed: int, number: int, count: int, items: Array[int]) -> LoanFile:
	var file := LoanFile.new()
	file.number = number
	file.request_count = count
	file.items = items
	file.due_day = 10
	file.roll(career_seed)
	return file

func asked(items: Array[int]) -> Array[int]:
	return items

# --- the numbers -----------------------------------------------------------------

func test_the_numbers_are_in_the_loan_config() -> void:
	assert_int(LoanConfig.PIPELINE_MAX).is_equal(3)
	assert_int(LoanConfig.MAX_REQUESTS_PER_FILE).is_equal(2)
	assert_float(LoanConfig.RETURN_ON_TIME).is_equal(0.70)
	assert_float(LoanConfig.RETURN_LATE).is_equal(0.20)
	assert_float(LoanConfig.RETURN_NEVER).is_equal(0.10)
	assert_float(LoanConfig.RETURN_ON_TIME + LoanConfig.RETURN_LATE + LoanConfig.RETURN_NEVER).is_equal_approx(1.0, 0.0001)
	assert_float(LoanConfig.QUALITY_COMPLETE).is_equal(0.75)
	assert_float(LoanConfig.QUALITY_INCOMPLETE).is_equal(0.20)
	assert_float(LoanConfig.QUALITY_WRONG).is_equal(0.05)
	assert_float(LoanConfig.QUALITY_COMPLETE + LoanConfig.QUALITY_INCOMPLETE + LoanConfig.QUALITY_WRONG).is_equal_approx(1.0, 0.0001)
	assert_int(LoanConfig.LATE_DAYS_MIN).is_equal(1)
	assert_int(LoanConfig.LATE_DAYS_MAX).is_equal(2)
	assert_int(LoanConfig.EXPIRES_AFTER_DUE_DAYS).is_equal(3)

# --- save and load ---------------------------------------------------------------

func test_open_files_survive_a_save_and_a_load() -> void:
	GameClock.day = 4
	var first := make_application(1)
	var second := make_application(2)
	var file_one := LoanRole.request_documents(first, asked([PAY_STUB, APPRAISAL]))
	var file_two := LoanRole.request_documents(second, asked([LETTER]))
	assert_object(file_one).is_not_null()
	assert_object(file_two).is_not_null()
	# A second request on the first file, once it is back.
	GameClock.day = file_one.return_day if file_one.timing != LoanFile.Timing.NEVER else file_one.due_day
	file_one.timing = LoanFile.Timing.ON_TIME
	file_one.return_day = GameClock.day
	var again := LoanRole.request_documents(first, asked([DOWN_PAYMENT]))
	assert_object(again).is_same(file_one)

	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	SaveGame.restore(career)

	var files := LoanRole.pipeline.files
	assert_int(files.size()).is_equal(2)
	for index in 2:
		var saved: LoanFile = file_one if index == 0 else file_two
		var loaded := files[index]
		assert_int(loaded.number).is_equal(saved.number)
		assert_str(loaded.application.applicant_name).is_equal(saved.application.applicant_name)
		assert_float(loaded.application.requested_amount).is_equal(saved.application.requested_amount)
		assert_int(loaded.request_count).is_equal(saved.request_count)
		assert_array(loaded.items).is_equal(saved.items)
		assert_int(loaded.request_day).is_equal(saved.request_day)
		assert_int(loaded.due_day).is_equal(saved.due_day)
		assert_int(loaded.timing).is_equal(saved.timing)
		assert_int(loaded.return_day).is_equal(saved.return_day)
		assert_int(loaded.quality).is_equal(saved.quality)
		assert_int(loaded.short_item).is_equal(saved.short_item)
		assert_int(loaded.wrong_item).is_equal(saved.wrong_item)
		assert_array(loaded.delivered_before).is_equal(saved.delivered_before)
	assert_int(LoanRole.pipeline.next_file_number).is_equal(3)
	# Numbers keep counting after a load.
	assert_int(LoanRole.pipeline.request(make_application(3), asked([PAY_STUB]), GameClock.day, LoanDeskManager.career_seed).number).is_equal(3)

func test_a_career_with_no_files_saves_what_it_always_did() -> void:
	LoanRole.section["desk_layout"] = "classic"
	var roles := SaveGame.dict_of(SaveGame.capture(), "roles")
	assert_dict(SaveGame.dict_of(roles, "loan")).is_equal({"desk_layout": "classic"})

func test_the_other_loan_section_data_is_kept_beside_the_files() -> void:
	LoanRole.section["desk_layout"] = "classic"
	LoanRole.request_documents(make_application(1), asked([PAY_STUB]))
	var career := through_json(SaveGame.capture())
	CareerReset.reset_all()
	SaveGame.restore(career)
	assert_dict(LoanRole.section).is_equal({"desk_layout": "classic"})
	assert_int(LoanRole.pipeline.files.size()).is_equal(1)

func test_an_old_save_with_no_pipeline_loads_an_empty_one() -> void:
	LoanRole.request_documents(make_application(1), asked([PAY_STUB]))
	var saved := SaveGame.read_file(OLD_SAVE)
	assert_int(saved.status).is_equal(SaveGame.Status.OK)
	SaveGame.restore(saved.career)
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_int(LoanRole.pipeline.next_file_number).is_equal(1)
	assert_dict(LoanRole.section).is_empty()

func test_unreadable_saved_files_are_dropped() -> void:
	var good := make_application(1)
	LoanRole.request_documents(good, asked([PAY_STUB, STATEMENT]))
	var data := LoanRole.save_data()
	var saved_files := SaveGame.dicts_of(SaveGame.array_of(SaveGame.dict_of(data, LoanRole.PIPELINE_KEY), "files"))
	var broken := saved_files[0].duplicate(true)
	var broken_application := SaveGame.dict_of(broken, "application")
	broken_application["loan_purpose"] = "Spaceship"
	broken["application"] = broken_application
	var no_application := {"number": 9}
	var odd_items := saved_files[0].duplicate(true)
	odd_items["items"] = [PAY_STUB, 99, "x", STATEMENT]
	data[LoanRole.PIPELINE_KEY] = {"next_file_number": 1, "files": [broken, no_application, odd_items]}
	LoanRole.load_data(through_json(data))
	assert_int(LoanRole.pipeline.files.size()).is_equal(1)
	assert_array(LoanRole.pipeline.files[0].items).is_equal([PAY_STUB, STATEMENT])
	assert_int(LoanRole.pipeline.next_file_number).is_greater(1)

func test_a_new_career_starts_with_no_files() -> void:
	LoanRole.request_documents(make_application(1), asked([PAY_STUB]))
	CareerReset.reset_all()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()
	assert_int(LoanRole.pipeline.next_file_number).is_equal(1)

# --- determinism -----------------------------------------------------------------

func test_the_same_seed_and_file_number_give_the_same_return_every_time() -> void:
	for number in range(1, 200):
		var one := rolled_file(777, number, 1, asked([PAY_STUB, LETTER]))
		var two := rolled_file(777, number, 1, asked([PAY_STUB, LETTER]))
		assert_int(two.timing).is_equal(one.timing)
		assert_int(two.return_day).is_equal(one.return_day)
		assert_int(two.quality).is_equal(one.quality)
		assert_int(two.short_item).is_equal(one.short_item)
		assert_int(two.wrong_item).is_equal(one.wrong_item)

func test_a_different_seed_or_file_or_request_rolls_differently() -> void:
	var base := rolled_file(1, 1, 1, asked([PAY_STUB]))
	var differs := 0
	for number in range(2, 60):
		if rolled_file(1, number, 1, asked([PAY_STUB])).return_day != base.return_day:
			differs += 1
	assert_int(differs).is_greater(5)
	var other_seed := 0
	var other_request := 0
	for number in range(1, 60):
		if rolled_file(2, number, 1, asked([PAY_STUB])).quality != rolled_file(1, number, 1, asked([PAY_STUB])).quality:
			other_seed += 1
		if rolled_file(1, number, 2, asked([PAY_STUB])).quality != rolled_file(1, number, 1, asked([PAY_STUB])).quality:
			other_request += 1
	assert_int(other_seed).is_greater(0)
	assert_int(other_request).is_greater(0)

func test_reloading_cannot_reroll_a_return() -> void:
	var file := LoanRole.request_documents(make_application(1), asked([PAY_STUB, STATEMENT]))
	var career := through_json(SaveGame.capture())
	for attempt in 3:
		SaveGame.restore(career)
		var loaded := LoanRole.pipeline.files[0]
		assert_int(loaded.return_day).is_equal(file.return_day)
		assert_int(loaded.quality).is_equal(file.quality)
		assert_int(loaded.short_item).is_equal(file.short_item)
		# Rolling it again from the saved seed and number gives the same answer.
		loaded.roll(LoanDeskManager.career_seed)
		assert_int(loaded.return_day).is_equal(file.return_day)
		assert_int(loaded.quality).is_equal(file.quality)

func test_a_return_never_uses_the_global_random_generator() -> void:
	seed(4242)
	var expected := randi()
	seed(4242)
	var application := make_application(5)
	var before_count := LoanDeskManager.generated_count
	seed(4242)
	LoanRequirements.missing_items(application, LoanDeskManager.career_seed)
	LoanRole.request_documents(application, asked([PAY_STUB, LETTER]))
	assert_int(randi()).is_equal(expected)
	assert_int(LoanDeskManager.generated_count).is_equal(before_count)

func test_asking_never_changes_the_applicant() -> void:
	var application := make_application(6)
	var saved := SaveGame.resource_to_dict(application)
	LoanRequirements.missing_items(application, LoanDeskManager.career_seed)
	LoanRole.request_documents(application, asked([PAY_STUB]))
	assert_dict(SaveGame.resource_to_dict(application)).is_equal(saved)

# --- the measured rates ----------------------------------------------------------

func test_the_measured_return_rates_match_the_configured_ones() -> void:
	var count := 6000
	var timing := {LoanFile.Timing.ON_TIME: 0, LoanFile.Timing.LATE: 0, LoanFile.Timing.NEVER: 0}
	var quality := {LoanFile.Quality.COMPLETE: 0, LoanFile.Quality.INCOMPLETE: 0, LoanFile.Quality.WRONG: 0}
	var late_days := {1: 0, 2: 0}
	for number in range(1, count + 1):
		var size := 1 + number % 3
		var items: Array[int] = []
		for index in size:
			items.append(index)
		var file := rolled_file(2026, number, 1, items)
		timing[file.timing] += 1
		quality[file.quality] += 1
		match file.timing:
			LoanFile.Timing.ON_TIME:
				assert_int(file.return_day).is_equal(file.due_day)
			LoanFile.Timing.LATE:
				late_days[file.return_day - file.due_day] += 1
			LoanFile.Timing.NEVER:
				assert_int(file.return_day).is_equal(LoanFile.NEVER_DAY)
		match file.quality:
			LoanFile.Quality.COMPLETE:
				assert_int(file.short_item).is_equal(-1)
				assert_int(file.wrong_item).is_equal(-1)
			LoanFile.Quality.INCOMPLETE:
				assert_bool(items.has(file.short_item)).is_true()
				assert_int(file.wrong_item).is_equal(-1)
			LoanFile.Quality.WRONG:
				assert_bool(items.has(file.wrong_item)).is_true()
				assert_int(file.short_item).is_equal(-1)
	var total := float(count)
	assert_float(timing[LoanFile.Timing.ON_TIME] / total).is_between(0.70 - 0.025, 0.70 + 0.025)
	assert_float(timing[LoanFile.Timing.LATE] / total).is_between(0.20 - 0.025, 0.20 + 0.025)
	assert_float(timing[LoanFile.Timing.NEVER] / total).is_between(0.10 - 0.02, 0.10 + 0.02)
	assert_float(quality[LoanFile.Quality.COMPLETE] / total).is_between(0.75 - 0.025, 0.75 + 0.025)
	assert_float(quality[LoanFile.Quality.INCOMPLETE] / total).is_between(0.20 - 0.025, 0.20 + 0.025)
	assert_float(quality[LoanFile.Quality.WRONG] / total).is_between(0.05 - 0.015, 0.05 + 0.015)
	# A late file is one or two days late, both happening.
	assert_int(late_days[1]).is_greater(0)
	assert_int(late_days[2]).is_greater(0)
	assert_int(late_days[1] + late_days[2]).is_equal(timing[LoanFile.Timing.LATE])

func test_the_measured_rate_of_missing_extra_items_matches_the_config() -> void:
	var applicable := 0
	var missing := 0
	for number in range(1, 1501):
		var application := make_application(number)
		var seed_value := 99
		var found := LoanRequirements.missing_items(application, seed_value)
		for item in LoanRequirements.ROLLED_ITEMS:
			if LoanRequirements.applies(application, item):
				applicable += 1
				if found.has(item):
					missing += 1
	assert_int(applicable).is_greater(1000)
	assert_float(float(missing) / applicable).is_between(LoanConfig.NEW_ITEM_MISSING_CHANCE - 0.02, LoanConfig.NEW_ITEM_MISSING_CHANCE + 0.02)

# --- independence ----------------------------------------------------------------

func test_a_return_depends_on_nothing_about_the_applicant() -> void:
	# The roll takes the career seed, the file number and the request, and
	# nothing else: applicants of every look and finances asked on the same
	# file number get the same answer.
	var reference := rolled_file(31, 7, 1, asked([PAY_STUB, STATEMENT]))
	for number in range(1, 80):
		var application := make_application(number)
		GameClock.day = 10
		var pipeline := LoanPipeline.new()
		pipeline.next_file_number = 7
		var file := pipeline.request(application, asked([PAY_STUB, STATEMENT]), 8, 31)
		var same := rolled_file(31, 7, 1, asked([PAY_STUB, STATEMENT]))
		same.due_day = file.due_day
		same.roll(31)
		assert_int(file.timing).is_equal(same.timing)
		assert_int(file.quality).is_equal(same.quality)
		assert_int(file.return_day - file.due_day).is_equal(same.return_day - same.due_day)
	assert_int(reference.timing).is_equal(rolled_file(31, 7, 1, asked([PAY_STUB, STATEMENT])).timing)

func test_missing_extra_items_do_not_depend_on_name_look_or_finances() -> void:
	# The rate among the applications an item applies to is the same for every
	# look, every risk tier and either half of the alphabet.
	var by_group := {}
	for number in range(1, 2501):
		var application := make_application(number)
		var found := LoanRequirements.missing_items(application, 5)
		var groups: Array[String] = [
			"look %d" % application.applicant_look,
			"tier %d" % application.calculate_risk_assessment(),
			"name %s" % ("A-M" if application.applicant_name.unicode_at(0) <= "M".unicode_at(0) else "N-Z"),
			"purpose %s" % application.loan_purpose,
		]
		for item in LoanRequirements.ROLLED_ITEMS:
			if not LoanRequirements.applies(application, item):
				continue
			for group in groups:
				var tally: Vector2i = by_group.get(group, Vector2i.ZERO)
				tally.x += 1
				if found.has(item):
					tally.y += 1
				by_group[group] = tally
	var checked := 0
	for group: String in by_group:
		var tally: Vector2i = by_group[group]
		if tally.x < 250:
			continue
		checked += 1
		var rate := float(tally.y) / tally.x
		assert_float(rate).override_failure_message("%s: %d of %d" % [group, tally.y, tally.x]).is_between(0.08 - 0.045, 0.08 + 0.045)
	assert_int(checked).is_greater(6)

func test_the_extra_items_apply_only_where_the_loan_and_report_make_them_relevant() -> void:
	var seen := {APPRAISAL: false, DOWN_PAYMENT: false, LETTER: false}
	for number in range(1, 600):
		var application := make_application(number)
		var found := LoanRequirements.missing_items(application, 3)
		if found.has(APPRAISAL):
			assert_str(application.loan_purpose).is_equal("Home")
		if found.has(DOWN_PAYMENT):
			assert_bool(application.has_down_payment()).is_true()
		if found.has(LETTER):
			assert_bool(application.late_30_days + application.late_60_days + application.late_90_days > 0 or application.collections > 0).is_true()
		for item: int in seen:
			seen[item] = seen[item] or found.has(item)
	for item: int in seen:
		assert_bool(seen[item]).override_failure_message("item %d never missing" % item).is_true()

func test_the_stub_statement_and_id_are_missing_when_the_documents_say_so() -> void:
	var application := make_application(1)
	application.documents_issued = true
	application.has_pay_stub = true
	application.has_statement = true
	application.id_presented = true
	application.id_problem = IdCard.Problem.NONE
	application.loan_purpose = "Personal"
	application.late_30_days = 0
	application.late_60_days = 0
	application.late_90_days = 0
	application.collections = 0
	assert_array(LoanRequirements.missing_items(application, 1)).is_empty()
	application.has_pay_stub = false
	application.has_statement = false
	assert_array(LoanRequirements.missing_items(application, 1)).is_equal([PAY_STUB, STATEMENT])
	application.id_presented = false
	application.id_problem = IdCard.Problem.NO_ID
	assert_array(LoanRequirements.missing_items(application, 1)).is_equal([PAY_STUB, STATEMENT, PHOTO_ID])
	application.id_presented = true
	application.id_problem = IdCard.Problem.EXPIRED
	assert_bool(LoanRequirements.missing_items(application, 1).has(PHOTO_ID)).is_true()
	# A mismatched name or photo is an identity problem to reject, not a
	# document to ask for.
	application.id_problem = IdCard.Problem.NAME_MISMATCH
	assert_bool(LoanRequirements.missing_items(application, 1).has(PHOTO_ID)).is_false()
	application.id_problem = IdCard.Problem.WRONG_PORTRAIT
	assert_bool(LoanRequirements.missing_items(application, 1).has(PHOTO_ID)).is_false()

# --- due days --------------------------------------------------------------------

func test_the_due_day_follows_the_checklist_size() -> void:
	assert_int(LoanRequirements.due_days(1)).is_equal(2)
	assert_int(LoanRequirements.due_days(2)).is_equal(3)
	assert_int(LoanRequirements.due_days(3)).is_equal(4)
	assert_int(LoanRequirements.due_days(4)).is_equal(5)
	assert_int(LoanRequirements.due_days(5)).is_equal(5)
	assert_int(LoanRequirements.due_days(6)).is_equal(5)
	assert_int(LoanRequirements.due_days(0)).is_equal(2)

func test_a_due_day_skips_weekends() -> void:
	# Day 5 is Friday 9 January 2026: two business days on is Tuesday the 13th.
	assert_str(BankCalendar.iso(GameClock.date_of_day(5))).is_equal("2026-01-09")
	var file := LoanRole.pipeline.request(make_application(1), asked([PAY_STUB]), 5, 1)
	assert_int(file.due_day).is_equal(7)
	assert_str(BankCalendar.iso(file.due_date())).is_equal("2026-01-13")
	assert_bool(BankCalendar.is_business_day(file.due_date())).is_true()
	# Three items on a Thursday: Day 4 (8 Jan) + 4 business days = Wednesday 14 Jan.
	var bigger := LoanRole.pipeline.request(make_application(2), asked([PAY_STUB, STATEMENT, PHOTO_ID]), 4, 1)
	assert_str(BankCalendar.iso(bigger.due_date())).is_equal("2026-01-14")

func test_a_due_day_skips_a_bank_holiday() -> void:
	# Day 10 is Friday 16 January; Monday the 19th is Martin Luther King Jr. Day.
	assert_str(BankCalendar.iso(GameClock.date_of_day(10))).is_equal("2026-01-16")
	assert_str(BankCalendar.iso(GameClock.date_of_day(11))).is_equal("2026-01-20")
	var file := LoanRole.pipeline.request(make_application(1), asked([PAY_STUB]), 10, 1)
	assert_str(BankCalendar.iso(file.due_date())).is_equal("2026-01-21")
	assert_bool(BankCalendar.is_business_day(file.due_date())).is_true()

func test_every_return_and_expiry_falls_on_a_business_day() -> void:
	for number in range(1, 300):
		var file := LoanRole.pipeline.request(make_application(number), asked([PAY_STUB]), 1 + number % 40, 8)
		if file == null:
			LoanRole.pipeline.reset()
			continue
		assert_bool(BankCalendar.is_business_day(GameClock.date_of_day(file.due_day))).is_true()
		assert_bool(BankCalendar.is_business_day(GameClock.date_of_day(file.expire_day()))).is_true()
		if file.timing != LoanFile.Timing.NEVER:
			assert_bool(BankCalendar.is_business_day(GameClock.date_of_day(file.return_day))).is_true()
		LoanRole.pipeline.close(file.application)

# --- a return is a pure function of the day -------------------------------------

func test_a_file_returns_when_today_reaches_its_return_day() -> void:
	var file := LoanRole.pipeline.request(make_application(1), asked([PAY_STUB]), 3, 1)
	file.timing = LoanFile.Timing.LATE
	file.return_day = file.due_day + 2
	assert_bool(file.has_returned(file.due_day + 1)).is_false()
	assert_bool(file.is_waiting(file.due_day + 1)).is_true()
	assert_bool(file.has_returned(file.due_day + 2)).is_true()
	assert_bool(file.has_returned(file.due_day + 30)).is_true()
	# Asking the same question twice, in any order, gives the same answer.
	assert_bool(file.has_returned(file.due_day + 2)).is_true()
	assert_bool(file.has_returned(file.due_day + 1)).is_false()

# --- expiry ----------------------------------------------------------------------

func test_a_file_that_never_returns_expires_three_days_after_its_due_day() -> void:
	var application := make_application(1)
	var file := LoanRole.pipeline.request(application, asked([PAY_STUB]), 3, 1)
	file.timing = LoanFile.Timing.NEVER
	file.return_day = LoanFile.NEVER_DAY
	assert_int(file.expire_day()).is_equal(file.due_day + 3)
	assert_bool(file.is_expired(file.due_day + 2)).is_false()
	assert_bool(file.is_waiting(file.due_day + 2)).is_true()
	assert_bool(file.is_expired(file.due_day + 3)).is_true()
	assert_bool(file.has_returned(file.due_day + 100)).is_false()
	assert_int(LoanRole.pipeline.open_count(file.due_day + 2)).is_equal(1)
	assert_int(LoanRole.pipeline.open_count(file.due_day + 3)).is_equal(0)
	assert_array(LoanRole.pipeline.expired_on(file.due_day + 3)).is_equal([file])
	assert_array(LoanRole.pipeline.expired_on(file.due_day + 4)).is_empty()
	assert_array(LoanRole.pipeline.names(file.due_day + 3)).is_empty()

func test_an_expired_file_is_forgotten_the_day_after_it_expires() -> void:
	var file := LoanRole.pipeline.request(make_application(1), asked([PAY_STUB]), 3, 1)
	file.timing = LoanFile.Timing.NEVER
	file.return_day = LoanFile.NEVER_DAY
	var later := make_application(2)
	# On its expiry day it is still listed (the day can say so).
	LoanRole.pipeline.request(later, asked([PAY_STUB]), file.expire_day(), 1)
	assert_bool(LoanRole.pipeline.files.has(file)).is_true()
	LoanRole.pipeline.close(later)
	LoanRole.pipeline.request(later, asked([PAY_STUB]), file.expire_day() + 1, 1)
	assert_bool(LoanRole.pipeline.files.has(file)).is_false()

func test_a_late_or_on_time_file_never_expires_and_stays_until_decided() -> void:
	var application := make_application(1)
	var file := LoanRole.pipeline.request(application, asked([PAY_STUB]), 3, 1)
	file.timing = LoanFile.Timing.LATE
	file.return_day = file.due_day + 2
	assert_bool(file.is_expired(file.due_day + 2)).is_false()
	assert_bool(file.is_expired(file.due_day + 200)).is_false()
	assert_array(LoanRole.pipeline.returned_files(file.due_day + 50)).is_equal([file])
	LoanRole.pipeline.close(application)
	assert_bool(LoanRole.pipeline.is_empty()).is_true()

func test_returned_files_come_back_in_the_order_they_returned() -> void:
	var a := LoanRole.pipeline.request(make_application(1), asked([PAY_STUB]), 3, 1)
	var b := LoanRole.pipeline.request(make_application(2), asked([PAY_STUB]), 3, 1)
	var c := LoanRole.pipeline.request(make_application(3), asked([PAY_STUB]), 3, 1)
	for file: LoanFile in [a, b, c]:
		file.timing = LoanFile.Timing.ON_TIME
	a.return_day = 9
	b.return_day = 6
	c.return_day = 6
	assert_array(LoanRole.pipeline.returned_files(7)).is_equal([b, c])
	assert_array(LoanRole.pipeline.returned_files(9)).is_equal([b, c, a])

# --- the caps --------------------------------------------------------------------

func test_at_most_three_files_are_open() -> void:
	var apps: Array[LoanApplication] = []
	for number in range(1, 5):
		apps.append(make_application(number))
	for index in 3:
		assert_int(LoanRole.pipeline.refusal_for(apps[index], asked([PAY_STUB]), 5)).is_equal(LoanPipeline.Refusal.NONE)
		assert_object(LoanRole.pipeline.request(apps[index], asked([PAY_STUB]), 5, 1)).is_not_null()
	assert_int(LoanRole.pipeline.refusal_for(apps[3], asked([PAY_STUB]), 5)).is_equal(LoanPipeline.Refusal.FULL)
	assert_object(LoanRole.pipeline.request(apps[3], asked([PAY_STUB]), 5, 1)).is_null()
	assert_int(LoanRole.pipeline.files.size()).is_equal(3)
	assert_int(LoanRole.pipeline.next_file_number).is_equal(4)
	# A returned file still counts until it is decided.
	var back := LoanRole.pipeline.files[0]
	back.timing = LoanFile.Timing.ON_TIME
	back.return_day = 6
	assert_int(LoanRole.pipeline.refusal_for(apps[3], asked([PAY_STUB]), 8)).is_equal(LoanPipeline.Refusal.FULL)
	# Deciding one (closing its file) frees the place.
	LoanRole.pipeline.close(back.application)
	assert_object(LoanRole.pipeline.request(apps[3], asked([PAY_STUB]), 8, 1)).is_not_null()

func test_an_expired_file_frees_its_place() -> void:
	var apps: Array[LoanApplication] = []
	for number in range(1, 5):
		apps.append(make_application(number))
	for index in 3:
		var file := LoanRole.pipeline.request(apps[index], asked([PAY_STUB]), 5, 1)
		file.timing = LoanFile.Timing.NEVER
		file.return_day = LoanFile.NEVER_DAY
	var expiry := LoanRole.pipeline.files[0].expire_day()
	assert_int(LoanRole.pipeline.refusal_for(apps[3], asked([PAY_STUB]), expiry - 1)).is_equal(LoanPipeline.Refusal.FULL)
	assert_int(LoanRole.pipeline.refusal_for(apps[3], asked([PAY_STUB]), expiry)).is_equal(LoanPipeline.Refusal.NONE)

func test_a_file_may_ask_twice_and_only_once_the_applicant_is_back() -> void:
	var application := make_application(1)
	var file := LoanRole.pipeline.request(application, asked([PAY_STUB, STATEMENT]), 5, 1)
	assert_int(file.request_count).is_equal(1)
	file.timing = LoanFile.Timing.ON_TIME
	file.quality = LoanFile.Quality.INCOMPLETE
	file.short_item = STATEMENT
	file.wrong_item = -1
	file.return_day = file.due_day
	# Not back yet.
	assert_int(LoanRole.pipeline.refusal_for(application, asked([STATEMENT]), file.due_day - 1)).is_equal(LoanPipeline.Refusal.STILL_OUT)
	assert_object(LoanRole.pipeline.request(application, asked([STATEMENT]), file.due_day - 1, 1)).is_null()
	assert_int(file.request_count).is_equal(1)
	# Back: a second request is the same file and keeps what came.
	var again := LoanRole.pipeline.request(application, asked([STATEMENT]), file.due_day, 1)
	assert_object(again).is_same(file)
	assert_int(file.request_count).is_equal(2)
	assert_int(LoanRole.pipeline.files.size()).is_equal(1)
	assert_array(file.delivered_before).is_equal([PAY_STUB])
	assert_int(file.request_day).is_equal(file.due_day - LoanRequirements.due_days(1))
	# Not a third.
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = file.due_day
	assert_int(LoanRole.pipeline.refusal_for(application, asked([STATEMENT]), file.due_day)).is_equal(LoanPipeline.Refusal.TOO_MANY_REQUESTS)
	assert_object(LoanRole.pipeline.request(application, asked([STATEMENT]), file.due_day, 1)).is_null()
	assert_int(file.request_count).is_equal(2)

func test_a_request_needs_known_items() -> void:
	var application := make_application(1)
	assert_int(LoanRole.pipeline.refusal_for(application, asked([]), 3)).is_equal(LoanPipeline.Refusal.NO_ITEMS)
	assert_int(LoanRole.pipeline.refusal_for(application, asked([99]), 3)).is_equal(LoanPipeline.Refusal.UNKNOWN_ITEM)
	assert_object(LoanRole.request_documents(application, asked([]))).is_null()
	assert_bool(LoanRole.pipeline.is_empty()).is_true()

func test_what_came_back_and_what_is_still_missing() -> void:
	var application := make_application(1)
	application.documents_issued = true
	application.has_pay_stub = false
	application.has_statement = false
	application.id_presented = true
	application.id_problem = IdCard.Problem.NONE
	application.loan_purpose = "Personal"
	application.late_30_days = 0
	application.late_60_days = 0
	application.late_90_days = 0
	application.collections = 0
	var file := LoanRole.pipeline.request(application, asked([PAY_STUB, STATEMENT]), 3, 1)
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = file.due_day
	file.quality = LoanFile.Quality.INCOMPLETE
	file.short_item = STATEMENT
	file.wrong_item = -1
	# Not back: nothing handed over.
	assert_array(file.still_missing(1, file.due_day - 1)).is_equal([PAY_STUB, STATEMENT])
	assert_array(file.still_missing(1, file.due_day)).is_equal([STATEMENT])
	# Complete and wrong returns.
	file.quality = LoanFile.Quality.COMPLETE
	file.short_item = -1
	assert_array(file.still_missing(1, file.due_day)).is_empty()
	file.quality = LoanFile.Quality.WRONG
	file.wrong_item = PAY_STUB
	assert_array(file.still_missing(1, file.due_day)).is_equal([PAY_STUB])

# --- names -----------------------------------------------------------------------

func test_names_taken_includes_the_applicants_in_open_files() -> void:
	GameClock.day = 6
	var application := make_application(1)
	application.applicant_name = "Zelda Quillfeather"
	assert_bool(LoanDeskManager.names_taken().has("Zelda Quillfeather")).is_false()
	var file := LoanRole.request_documents(application, asked([PAY_STUB]))
	assert_bool(LoanDeskManager.names_taken().has("Zelda Quillfeather")).is_true()
	# Back and not yet decided: still theirs.
	file.timing = LoanFile.Timing.ON_TIME
	file.return_day = GameClock.day
	assert_bool(LoanDeskManager.names_taken().has("Zelda Quillfeather")).is_true()
	# Decided: free again.
	LoanRole.pipeline.close(application)
	assert_bool(LoanDeskManager.names_taken().has("Zelda Quillfeather")).is_false()
	# An expired file's applicant has gone.
	var gone := LoanRole.request_documents(application, asked([PAY_STUB]))
	gone.timing = LoanFile.Timing.NEVER
	gone.return_day = LoanFile.NEVER_DAY
	GameClock.day = gone.expire_day()
	assert_bool(LoanDeskManager.names_taken().has("Zelda Quillfeather")).is_false()

func test_no_new_applicant_shares_a_name_with_an_open_file() -> void:
	GameClock.day = 6
	var application := make_application(1)
	application.applicant_name = LoanApplicantGenerator.FIRST_NAMES[0] + " " + LoanApplicantGenerator.LAST_NAMES[0]
	LoanRole.request_documents(application, asked([PAY_STUB]))
	for index in 400:
		var generated := LoanDeskManager.generate_application()
		assert_str(generated.applicant_name).is_not_equal(application.applicant_name)
