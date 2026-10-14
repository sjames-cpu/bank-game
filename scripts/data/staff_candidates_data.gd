extends RefCounted
class_name StaffCandidatesData

## Static content for job applicants (NPC coworkers, step 5): their own name
## pool, kept apart from CustomerQueue.CUSTOMER_NAMES and the starting roster
## (StaffRosterData) so an applicant never shares a name with a customer or a
## coworker, and one-line backgrounds per role. Backgrounds are picked
## independently of the hidden stats, so they never give a candidate away:
## the interview answers are what tell them apart (HiringManager).

const CANDIDATE_NAMES: Array[String] = [
	"Harper Quinn", "Rowan Ellis", "Imani Brooks-Hale", "Felix Hartmann",
	"Leila Farouk", "Gideon Park", "Maren Lindqvist", "Tobias Reyes",
	"Juniper Vance", "Anika Bose", "Callum Fraser", "Esme Delgado",
	"Ezra Whitlock", "Noor Siddiqui", "Owen Castellano", "Priscilla Yuen",
	"Rafael Montoya", "Talia Brennan", "Wesley Adeyemi", "Celeste Moreno",
	"Dmitri Volkov", "Ines Carvalho", "Jasper Kowalski", "Keiko Mori",
]

const TELLER_BACKGROUNDS: Array[String] = [
	"2 years as a teller at a credit union",
	"Cashier and shift lead at a grocery store",
	"Recent graduate with a finance degree",
	"4 years in retail customer service",
	"Bookkeeping assistant at a small accounting firm",
	"Teller at a big national bank for a year",
	"Front desk at a busy hotel",
	"Returning to work after running a family business",
]

const LOAN_OFFICER_BACKGROUNDS: Array[String] = [
	"3 years as a loan processor at a mortgage lender",
	"Credit analyst at a regional bank",
	"Small-business lending assistant at a credit union",
	"Car-dealership finance manager",
	"Recent MBA graduate with an internship in underwriting",
	"5 years in consumer lending at a national bank",
	"Personal banker moving into lending",
	"Collections specialist at a credit card company",
]

static func backgrounds_for(role: String) -> Array[String]:
	return LOAN_OFFICER_BACKGROUNDS if role == "Loan Officer" else TELLER_BACKGROUNDS
