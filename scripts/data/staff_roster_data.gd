extends RefCounted
class_name StaffRosterData

## Static provider for the sample staff roster (Phase 5b). Kept separate
## from StaffMember (the data shape) so the actual roster content can
## grow independently of it, mirroring InterviewQuestionsData and
## LoanApplicationsData.
##
## Profiles are deliberately varied and lopsided rather than clustered
## around average — a high-skill/low-reliability gamble, a low-stat
## specialist who's excellent at exactly one thing, a dependable
## generalist, and so on — so that scheduling choices (Phase 5c) have
## real tradeoffs to weigh instead of an obvious "best" pick.

static func get_staff() -> Array[StaffMember]:
	return [
		_staff("Derek Voss", "Teller", 9, 3, 8, 4,
			"Blazing fast and sharp with numbers, but shows up late more often than he'd like to admit."),
		_staff("Priya Anand", "Loan Officer", 7, 8, 6, 7,
			"Doesn't dazzle at any one thing, but you can count on her to get it right, every time."),
		_staff("Walter Higgins", "Teller", 5, 7, 3, 10,
			"Customers love him — he'll chat for ten minutes about their grandkids while the line grows behind them."),
		_staff("Nina Ortiz", "Teller", 3, 9, 5, 6,
			"Never misses a shift and never cuts corners, but still double-checks the manual for basic transactions."),
		_staff("Marcus Chen", "Loan Officer", 6, 5, 9, 5,
			"Fast but occasionally sloppy with paperwork."),
		_staff("Sana Malik", "Loan Officer", 9, 9, 5, 3,
			"Meticulous and almost never wrong on the numbers, though small talk clearly isn't her thing."),
	]

static func _staff(staff_name: String, role: String, skill: int, reliability: int, speed: int, customer_service: int, flavor_text: String) -> StaffMember:
	var staff := StaffMember.new()
	staff.staff_name = staff_name
	staff.role = role
	staff.skill = skill
	staff.reliability = reliability
	staff.speed = speed
	staff.customer_service = customer_service
	staff.flavor_text = flavor_text
	return staff
