extends GdUnitTestSuite

## Stage 2b (shared/art-ui-motion) is interface motion from one shared
## driver: it must not touch a role's own files (ROLE_BOUNDARIES.md). While
## this branch is checked out, lists every file it changed against main (what
## is committed, edited or new) and fails if one is role-owned. On any other
## branch, without git, or in a checkout with no main to compare against (a
## shallow CI clone), there is nothing to check here.

const BRANCH: String = "shared/art-ui-motion"

## Role-owned files and folders: the Teller's and the Loan Officer's, the
## frozen Branch Manager's, and the screens they own (ROLE_BOUNDARIES.md and
## the manager's screens), scenes and tests included.
const ROLE_OWNED: Array[String] = [
	"scripts/roles/",
	"scripts/ui/teller_screen.gd", "scripts/ui/drawer_count_screen.gd", "scripts/ui/vault_transfer_screen.gd",
	"scripts/world/customer_queue.gd", "scripts/world/teller_desk.gd", "scripts/npc/customer_npc.gd",
	"scripts/ui/loan_officer_screen.gd", "scripts/ui/loan_review_screen.gd",
	"scripts/data/loan_application.gd", "scripts/data/loan_applications_data.gd", "scripts/data/loan_applicant_generator.gd",
	"scripts/data/booked_loan.gd", "scripts/data/credit_report.gd",
	"scripts/autoload/loan_desk_manager.gd", "scripts/autoload/loan_book_manager.gd",
	"scripts/world/loan_desk_seat.gd", "scripts/world/loan_officer_desk.gd", "scripts/world/npc_loan_desk_worker.gd",
	"scripts/npc/loan_applicant_npc.gd",
	# The Branch Manager's screens (frozen) and the staff screens beneath them.
	"scripts/ui/branch_manager_screen.gd", "scripts/ui/staff_review_screen.gd", "scripts/ui/staff_scheduling_screen.gd",
	"scripts/ui/cash_orders_screen.gd", "scripts/ui/approvals_screen.gd", "scripts/ui/hiring_screen.gd",
	"scripts/ui/vault_reconciliation_screen.gd", "scripts/ui/armored_truck_screen.gd",
	"scenes/ui/teller_screen.tscn", "scenes/ui/drawer_count_screen.tscn", "scenes/ui/vault_transfer_screen.tscn",
	"scenes/ui/loan_officer_screen.tscn", "scenes/ui/loan_review_screen.tscn", "scenes/ui/branch_manager_screen.tscn",
	"scenes/ui/staff_review_screen.tscn", "scenes/ui/staff_scheduling_screen.tscn", "scenes/ui/cash_orders_screen.tscn",
	"scenes/ui/approvals_screen.tscn", "scenes/ui/hiring_screen.tscn", "scenes/ui/vault_reconciliation_screen.tscn",
	"scenes/ui/armored_truck_screen.tscn",
]

## Role-owned test files, by name.
const ROLE_OWNED_TEST_PREFIXES: Array[String] = ["tests/teller_", "tests/kyc_", "tests/b2_", "tests/b6_", "tests/loan_", "tests/credit_report_", "tests/support/teller/", "tests/support/loan/"]

static func git_lines(arguments: PackedStringArray) -> PackedStringArray:
	var output: Array = []
	var code := OS.execute("git", arguments, output, true)
	if code != 0 or output.is_empty():
		return PackedStringArray()
	var lines := PackedStringArray()
	for line in str(output[0]).split("\n", false):
		lines.append(line.strip_edges())
	return lines

## True when `path` is one a role owns.
static func is_role_owned(path: String) -> bool:
	for owned in ROLE_OWNED:
		if path == owned or (owned.ends_with("/") and path.begins_with(owned)):
			return true
	for prefix in ROLE_OWNED_TEST_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false

func test_the_check_knows_which_files_are_role_owned() -> void:
	assert_bool(is_role_owned("scripts/ui/teller_screen.gd")).is_true()
	assert_bool(is_role_owned("scripts/ui/loan_review_screen.gd")).is_true()
	assert_bool(is_role_owned("scripts/roles/loan/loan_config.gd")).is_true()
	assert_bool(is_role_owned("scripts/ui/staff_review_screen.gd")).is_true()
	assert_bool(is_role_owned("scripts/ui/cash_orders_screen.gd")).is_true()
	assert_bool(is_role_owned("tests/loan_pile_test.gd")).is_true()
	assert_bool(is_role_owned("scripts/ui/hud.gd")).is_false()
	assert_bool(is_role_owned("scripts/ui/fx/ui_motion_driver.gd")).is_false()
	assert_bool(is_role_owned("scripts/world/teller_room.gd")).is_false()

## The files this branch changed against main, listed and checked.
func test_this_branch_touches_no_role_owned_file() -> void:
	var branch := git_lines(PackedStringArray(["rev-parse", "--abbrev-ref", "HEAD"]))
	if branch.is_empty() or branch[0] != BRANCH:
		return
	var base := git_lines(PackedStringArray(["merge-base", "HEAD", "main"]))
	if base.is_empty():
		base = git_lines(PackedStringArray(["merge-base", "HEAD", "origin/main"]))
	if base.is_empty():
		# A shallow CI checkout has no main to compare against.
		print("No merge base with main here: the file check is skipped.")
		return
	var touched := git_lines(PackedStringArray(["diff", "--name-only", base[0]]))
	touched.append_array(git_lines(PackedStringArray(["ls-files", "--others", "--exclude-standard"])))
	print("Files this branch touches: ", ", ".join(touched))
	var owned: Array[String] = []
	for path in touched:
		if is_role_owned(path):
			owned.append(path)
	assert_array(owned).override_failure_message("Role-owned files changed on %s (stop and list them for their owner): %s" % [BRANCH, ", ".join(owned)]).is_empty()
