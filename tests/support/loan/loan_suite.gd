extends "res://tests/support/shared/room_suite.gd"

## Base for suites that work the loan desks (the Loan Officer's role) and
## need none of the teller's helpers. Everything about the room itself is in
## the shared suite (room_suite.gd). The Loan Officer's shared test helpers
## (James's) go here; a helper only one file uses can stay in that file.
##
## Not a test suite itself (no test_ functions) — suites extend it by path.

## The room's LoanSlotAdapter (the Loan Officer's link to the time slots).
func loan_slot_adapter() -> LoanSlotAdapter:
	return room.get_node("LoanSlotAdapter")

## The loan officer's screen and its review screen, for suites that fill them
## in before_test (lo = room.loan_officer_screen, review = lo.loan_review_screen).
var lo: LoanOfficerScreen
var review: LoanReviewScreen

## Waits `count` frames.
func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## The hand-written sample application for `applicant_name`, or null.
## (loan_book_test overrides it to also mark the documents issued.)
func sample(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			return application
	return null

## Clocked in at Loan Desk 1 at 10 AM, with the screen left open.
## (loan_walk_in_test overrides it to clock in through a work slot.)
func clock_in_at_loan_desk() -> void:
	GameClock.minutes = 10 * 60.0
	XPManager.is_loan_officer_unlocked = true
	room._on_loan_officer_desk_interacted()
	lo.clock_in_button.pressed.emit()

## The review screen's panel stays inside the window, clear of the HUD
## column and the controls line.
func assert_fits() -> void:
	await frames(4)
	var problems := layout_problems(review.main_panel)
	problems.append_array(controls_line_problems(review.main_panel))
	assert_array(problems).override_failure_message("
".join(problems)).is_empty()
