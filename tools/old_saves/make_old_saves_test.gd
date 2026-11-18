extends GdUnitTestSuite

## Writes sample saves in the CURRENT save format into tests/data/old_saves/,
## for tests/old_saves_test.gd. Not part of the test run (run_tests.sh runs
## res://tests only). Run it just BEFORE you change the save format
## (SaveGame.FORMAT_VERSION), so the old format stays covered once the new
## one exists. See README.md beside it.
##
##   "$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##       -a res://tools/old_saves/make_old_saves_test.gd --ignoreHeadlessMode
##
## Each sample is a real career captured by SaveGame.capture(), named
## v<FORMAT_VERSION>_<kind>.json. A file that already exists is never
## overwritten: the committed samples are a record of what old games wrote.
## The version 1 and the first version 2 samples were made by an earlier
## version of this script, with the running clock that's since gone.

const OUT := "res://tests/data/old_saves/"

func test_write_the_samples() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# A Loan Officer at the start of Day 6 (saved at Start Day 6).
	career(6)
	XPManager.is_loan_officer_unlocked = true
	XPManager.total_xp = 820
	ScoreManager.total_score = 82
	ReputationManager.reputation = 57
	write("start_of_day")

	# A Teller at the End of Day 4 (saved when the summary came up): the
	# vault's and loans' day closed.
	career(4)
	GameClock.minutes = DaySchedule.slot_at(DaySchedule.count() - 1).start_minutes()
	XPManager.total_xp = 400
	ScoreManager.total_score = 40
	ReputationManager.reputation = 52
	BusinessDay.customers_served_by_player = 8
	BusinessDay.customers_served_by_staff = 22
	VaultManager.last_closed_day = 4
	LoanBookManager.last_closed_day = 4
	DayFlow.end_of_day_due = true
	write("end_of_day")

	# A new career part-way through onboarding (Day 1, at the contract).
	career(1)
	OnboardingManager.reset()
	OnboardingManager.step = OnboardingManager.Step.CONTRACT
	write("onboarding")

	# A Branch Manager at the End of Day 12.
	career(12)
	GameClock.minutes = DaySchedule.slot_at(DaySchedule.count() - 1).start_minutes()
	XPManager.is_loan_officer_unlocked = true
	XPManager.total_xp = 1600
	ReputationManager.reputation = 64
	XPManager._grant_branch_manager()
	VaultManager.last_closed_day = 12
	LoanBookManager.last_closed_day = 12
	DayFlow.end_of_day_due = true
	write("branch_manager_end_of_day")

	CareerReset.reset_all()

## A fresh career at the start of `day` (Opening), onboarding done, with a
## customer's account.
func career(day: int) -> void:
	CareerReset.reset_all()
	OnboardingManager.skip()
	GameClock.day = day
	GameClock.minutes = DaySchedule.slot_at(0).start_minutes()
	BusinessDay.stats_day = day
	AccountManager.create_account("Priya Shah", 125000)

func write(kind: String) -> void:
	var path := OUT + "v%d_%s.json" % [SaveGame.FORMAT_VERSION, kind]
	if FileAccess.file_exists(path):
		print("Kept %s (it exists already)" % path)
		return
	var text := JSON.stringify({"format_version": SaveGame.FORMAT_VERSION, "saved_at": Time.get_datetime_string_from_system(), "career": SaveGame.capture()}, "\t", false, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	print("Wrote %s" % path)
