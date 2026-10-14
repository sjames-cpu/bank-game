# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**BankSim** is a Godot 4.7 bank-branch simulation written entirely in GDScript (the project is configured for .NET, but there are no C# scripts, `.csproj` or `.sln`). The player starts as a Teller, unlocks Loan Officer and then Branch Manager, works alongside NPC coworkers, and can be disciplined and fired. `HANDOFF.md` (the original bug list and roadmap) and `AUDIT_REPORT.md` (an audit of the first fixes) drive the current work; both have a status note at the top. `DEVLOG.md` records how the project got here, session by session.

Keep this file in step with the code: update it when structure or behaviour changes.

## Flow

`run/main_scene` is the hiring interview (`scenes/ui/interview_screen.tscn`, `InterviewManager`): every new game starts there. Hired or Hired on Probation loads `scenes/world/teller_room.tscn`, where the whole branch is one room and every role works; Rejected restarts the interview. Termination (see Reports) shows a letter whose "Apply for a new job" wipes all career progress (`CareerReset.reset_all()`, which calls each autoload's `reset()`) and loads the interview again.

Desk screens pause the tree while open (`get_tree().paused = true`), so customers, staff and the room's `_process` stop; the HUD, letters and the day/night tint run with `process_mode` ALWAYS.

## The room (`scenes/world/teller_room.tscn`, `scripts/world/`)

- **Layout** (`room_builder.gd`, built at runtime on a 24×22-tile `TileMapLayer`, 32 px tiles): a back-office row along the top (Vault, Manager's Office, Conference Room, Accounting), each with a door gap into one open floor below (Marketing + Loan bullpen on the left, the three teller windows in the middle, the Waiting Lounge and ATM near the entrance). The entrance gap in the bottom wall is a doormat, and a solid sidewalk strip runs outside it (second atlas `assets/tilesets/outdoor_tiles.png`), so the player can stand in the doorway but not leave. The player spawns at (384, 624), just inside the entrance.
- **Desks**: the player's own **Player Teller Window** (`TellerDesk`, x=464, its own `CustomerQueue` lane); **Teller Window 1/2** (x=560/656, always staffed); the **Loan Desk** (`LoanOfficerDesk`, x=208, staffed until the player works it); the **Branch Manager desk** in the Manager's Office (hidden until promotion); the **ATM**. The four usable ones extend `Interactable` (`interactable.gd`: `signal interacted`, `player_in_range`, fires on `ui_accept` or the `interact` action, E) with class_names `TellerDesk`, `LoanOfficerDesk`, `BranchManagerDesk`, `ATM`. They know nothing about what happens next; `teller_room.gd` (`TellerRoom`) connects their signals, gates them (Loan Desk until the unlock, everything staffed after promotion) and opens the screens.
- **Draw order and collision (B5)**: the room root is y-sorted, as are `Staff`, the customer lines, `Decor` and each desk node, so the player, customers, staff and furniture sort together. Each furniture sprite's origin is its base (texture `offset` up), so characters switch from behind to in front where their feet pass its bottom edge; staff stand above their counter's base so it covers their lower body. Solid furniture has a `Footprint` `StaticBody2D` covering only its base, on physics layer 16. Only the player's mask (17 = walls + furniture) includes it. Customers and staff walk scripted paths and collide with walls only, and the player and NPCs never collide: a customer walks through a player standing in their lane. The hidden Branch Manager desk's footprint is disabled until promotion.
- `player_movement.gd` (`PlayerMovement`): 8-direction `CharacterBody2D` movement through the `move_*` actions (WASD + arrows), 4-direction idle/walk animation. `day_night_cycle.gd`: a purely visual `CanvasModulate` tint.

## Autoloads (`scripts/autoload/`, registered in `project.godot`)

All in memory only (nothing persists across launches). Each has `reset()`, called by `CareerReset`; any new autoload holding career progress needs one too.

- **AccountManager**: the shared `Account` list (Teller, ATM and staff lines all use it). `create_account()`, `deposit()`/`withdraw()` (cents), `get_browsable_accounts()` (hides auto-created customer accounts from the teller dropdown), `find_account_by_name(name, staff_line)` (the player's line and the staff lines are separate namespaces, so staff work never moves a player-line customer's balance). Seeds a $1,000 demo account.
- **ScoreManager** / **ReputationManager**: career Score, and Reputation clamped to [0, 100] starting at 50 (`LOW_REPUTATION_THRESHOLD` 0 shows the HUD warning).
- **XPManager**: XP (10 per Score point, floored at 0) and the role unlocks. Loan Officer: 500 XP and 40 Reputation; Branch Manager: 1500 XP and 60 Reputation. Checks run on XP and Reputation changes and fire once. A Branch Manager unlock earned while clocked in at the Player Teller Window or Loan Desk (`begin_player_shift()`/`end_player_shift()`) is held until clock-out. Also holds `has_seen_branch_orientation`.
- **InterviewManager**: resolves the interview (`resolve_outcome()`: `HIRE_THRESHOLD` 15, `PROBATION_THRESHOLD` 5 out of 30 over 10 questions in `InterviewQuestionsData`; some answers are instant rejects) and owns probation. While `is_on_probation`, `report_limit()` is 2 (`PROBATION_REPORTS_FOR_TERMINATION`) instead of 3; `teller_room.gd` reports teller clock-in/out (`begin_teller_shift()`/`end_teller_shift()`), and 3 completed teller shifts with no new report (`PROBATION_CLEAN_SHIFTS`) end probation with a "Probation Complete" letter (`probation_completed`). A report (`note_report()`, from ReportManager) restarts the count; promotion to Branch Manager ends probation silently. Plain Hired has no probation.
- **HistoryManager**: log of `DecisionRecord`s. Roles: TELLER and LOAN_OFFICER (the player's work; actionable in Approvals), BRANCH_MANAGER, DISCIPLINARY and DRAWER_VARIANCE (record only), STAFF (NPC work: only the newest 200 kept, announced via `staff_record_added`, hidden from Approvals).
- **ScheduleManager**: which `StaffMember` (from `StaffRosterData`, with speed/skill/reliability stats) works each desk slot (`DESK_SLOTS`: Teller Window 1, Teller Window 2, Loan Desk; Teller Window 3 joins after promotion). `dismiss_staff()` for terminations.
- **StaffReviewManager**: the Branch Manager's staff review queue (see Branch Manager below).
- **HintManager**: which first-run hints this career has seen (`Hint`: arrival, first customer, first clock-out, Loan Officer and Branch Manager unlocks) and their text.
- **ReportManager**: the player's disciplinary record (see Reports below). Registered last: it connects to XPManager in `_ready()`.

## Money (B3)

Every amount the player handles is **int cents** end to end: `Account.balance_cents`, `ShiftTransaction.amount_cents`, `CustomerNPC.intent_amount_cents`, drawer and vault expected/counted totals (denominations are `DENOMINATION_CENTS`, ready for coins), ATM amounts, `TellerScreen.STARTING_FLOAT_CENTS` ($50,000), `VaultReconciliationScreen.EXPECTED_VAULT_CENTS` ($500,000). Dollars appear only at the edges: `MoneyMath.to_cents()` once when a SpinBox value is entered, and `MoneyMath.format(cents)` ("$1234.50", "$-10.00") or `MoneyMath.format(cents, true)` ("$500" for whole dollars, for what people say) for every display. Loan application figures stay whole-dollar floats on purpose: they're judged, never moved as cash (see `loan_application.gd`).

## Teller (`scripts/ui/teller_screen.gd`, `TellerScreen`)

- **Clock-in / opening count (B2)**: the drawer is counted (`drawer_count_screen.gd`, `DrawerCountScreen`: Perfect needs an exact total and at most 4 more bills than the minimum; Minor is within $500 and 15 extra bills; otherwise Major). Perfect starts the shift; Minor starts it and logs a DRAWER_VARIANCE record; Major blocks it until a recount ("Recount Drawer", up to `MAX_OPENING_RECOUNTS` 2). Still Major after both, a supervisor signs off (−2 Reputation, logged) and the shift starts. The drawer always starts at the assigned float; the opening count earns no Score or XP.
- **Customers**: the player's line (`CustomerQueue`, `scripts/world/customer_queue.gd`) brings 4 customers per shift (`CUSTOMERS_PER_SHIFT_CAP`), each with their own account and a stated request (a round $10, $20–$500; withdrawals capped by their balance), 20% complaints, 50% paying by card (card transactions skip the drawer and can be declined, 10%). Customers wait 50 s before abandoning (−3 Score, −2 Reputation). Queue movement is visual only: each customer holds a spot, steps forward into clear spots, and leaves sideways down a corridor between lanes.
- **Requests and Complete Transaction (B6)**: any number of deposits/withdrawals (and Reverse Transaction) for the customer at the desk, then **Complete Transaction** grades the net effect on their own account. Correct: +5 Score (+50 XP). Wrong: −3 Score, −2 Reputation and a mistake toward reports (once per customer); the customer says what's wrong and waits for a fix. A transaction on someone else's account must be reversed. Closing the screen completes open transactions; leaving a mistake unfixed sends the customer off upset (−3 more Reputation). Complaint customers are served by picking a response.
- **Clock-out gate (B2)**: only once every customer of the shift is handled (served, left, or abandoned); otherwise the error names what's left. The closing count grades Perfect +10 Score/+2 Reputation, Minor +5/0, Major −5/−5; Perfect/Minor are scaled by the share of the shift's customers actually served (zero if none).
- **Shift summary**: opening-count line, drawer and customer sections, and a "This shift" total.

## Loan Officer (`loan_officer_screen.gd`, `loan_review_screen.gd`, `LoanApplication`)

Unlocked at 500 XP / 40 Reputation. A shift is 3 applications (`APPLICATIONS_PER_SHIFT`); each is approved, rejected or counter-offered once the credit check has been run (decisions stay locked until then) and graded BEST/PARTIAL/BAD/WORST against its risk assessment (+10/+3/−3/−10 Score). DTI is monthly debt payments ÷ monthly income (B9). Closing an application without deciding keeps it pending. While the player works the Loan Desk its staff member walks to the break room in the conference room and back.

## Branch Manager (`branch_manager_screen.gd`)

Unlocked at 1500 XP / 60 Reputation, granted at clock-out if earned mid-shift, with one "Letter of Promotion" (`discipline_letter_screen.gd`) that also clears the disciplinary record, and a one-time orientation letter on the first Branch Manager clock-in. After promotion the Player Teller Window becomes the staffed **Teller Window 3** (`Window3Line` on the player's lane), the Loan Desk's staff never steps away, and both desks only show "[staff] is working…". The hub offers:
- **Staff Scheduling** (`staff_scheduling_screen.gd`): assign staff to desk slots.
- **Approvals** (`approvals_screen.gd`): override a loan decision or flag a teller record for retraining.
- **Vault Reconciliation** (`vault_reconciliation_screen.gd`): once per shift, required before clock-out.
- **Staff Review** (`staff_review_screen.gd`, `StaffReviewManager`): every staff teller mistake and every staff loan decision not graded BEST becomes a review item. Severity stays hidden until the manager decides: Serious (wrong-account mistake, WORST loan) → Issue Report; Minor (other mistakes, BAD loans) → Give Feedback, or Issue Report once that person has had 2 feedbacks; Acceptable (PARTIAL loans) → Excuse. Fair calls +3 Score; unfair reports −3 Score/−1 Reputation; serious items left unreviewed at clock-out −2 Reputation each. At 3 reports the manager can terminate a staff member: their desk becomes unassigned and its line closes.
- The shift summary adds report-only "Branch" (each desk's staff work this shift) and "Staff Review" sections.

## NPC coworkers (`scripts/npc/staff_npc.gd`, `npc_customer_line.gd`, `npc_loan_desk_worker.gd`)

`teller_room.gd` places a `StaffNPC` at each staffed desk from `ScheduleManager`. Teller Windows 1/2 (and 3 after promotion) serve their own `NpcCustomerLine` (extends `CustomerQueue`: regular customers only, no per-shift cap, up to 3 waiting, arrivals every 12–18 s), with service time and mistake chance from the staff member's stats. `NpcLoanDeskWorker` decides loan applications in the background while the player isn't at the Loan Desk. NPC work changes real (staff-line) accounts but never the player's Score, Reputation, XP or drawer; it's logged as STAFF records.

## Reports and termination (`ReportManager`)

Every 2 mistaken teller customers = 1 written warning (a letter); 3 reports = termination (2 while on probation; `ReportManager.report_limit()`), with a full-screen letter, then the interview (see Flow). Warning letters on probation say so. Reports carry across shifts and roles. Branch Managers are exempt: promotion clears the record (TODO: Regional Manager review for managers).

## HUD, prompts and hints (`scripts/ui/hud.gd`, `scenes/ui/hud.tscn`, B4)

The `HUD` CanvasLayer (layer 2, above `UI`) shows role, Score, Reputation, XP, Reports (with the probation line, e.g. "Probation — 1 of 3 clean shifts", while on probation) and shift status in a top-right column that stays clear of every centred screen at 1152×648. Below it are the low-reputation and role-unlocked notifications, then first-run hints with a "Got it" button. It's visible with or without a desk screen open, and hidden while the termination letter is up. The "E — …" interaction prompt appears below whichever interactable the player stands at (`teller_room.interaction_prompt_text()`), or says why a desk can't be used (e.g. "Loan Desk — unlocks at 500 XP and 40 Reputation"). It's hidden while a screen is open. Key names come from the InputMap (`InputPrompts.key_for()`).

## Data resources (`scripts/data/`)

Small `Resource` structs built in code (no `.tres` data files): `Account`, `ShiftTransaction`, `DecisionRecord`, `DisciplinaryReport`, `StaffMember`, `StaffReviewItem`, `LoanApplication`, `CustomerComplaint`/`ComplaintResponse`, `CustomerDialogueLine`, `InterviewQuestion`/`InterviewAnswer`. Content lives in static providers kept apart from the data shapes: `InterviewQuestionsData`, `LoanApplicationsData`, `CustomerComplaintsData`, `CustomerDialogueData`, `StaffRosterData`.

## Engine configuration (`project.godot`)

- **Godot**: 4.7 (4.7.1 locally and in CI), GL Compatibility renderer on desktop and mobile; Windows rendering device `d3d12`.
- **.NET/C#**: enabled (`[dotnet] project/assembly_name="BankSim"`) but unused; the first C# script would need a generated `.sln`/`.csproj`.
- **Physics**: 3D engine is Jolt (unused; the game is 2D). Physics layers in use: 1 walls, 2 player, 4 customers, 8 staff, 16 furniture.
- **Display**: 1152×648, stretch `canvas_items` with `expand` aspect.
- **Input**: `move_up/down/left/right` (WASD + arrows) and `interact` (E); desks also accept `ui_accept`.
- **GDScript warnings**: untyped declarations, unsafe property/method access, unsafe casts, unsafe call arguments and integer division are enabled (Warn level) on top of the defaults. Addons are excluded (`directory_rules`). CI fails on any warning (see Tests).

The file is hand-editable, but prefer the editor for engine settings; when editing directly, keep its section/key format.

## Version control notes

- `.gitattributes` normalizes text files to LF.
- Gitignored: `.godot/` (cache), `reports/` (test reports), `scratch/` (local drafts, screenshot scripts), `override.cfg` (temporary, see Tests), `.summer/local/` (local state for a "Summer Engine" tooling layer, including a nested bare git repo; not project source).
- `production/` and `.claude/agents/` belong to the Godot specialist agent tooling, not the game.

## Development workflow

Play by opening the project in the Godot 4.7 editor and using Play/Run.

### Tests and CI

Tests use **gdUnit4 v6.2.1** (`addons/gdUnit4/`, the addon's own self-tests left out). Suites live in `tests/` (`*_test.gd`, extending `GdUnitTestSuite`). Suites that drive the real room extend `tests/support/teller_room_suite.gd`: a fresh `teller_room.tscn` (`room: TellerRoom`) and a fresh career per test, a seeded RNG, and helpers to clock in/out, spawn customers with fixed requests, and press the teller buttons (`deposit()`/`withdraw()`/`spawn()` take dollars, like a player typing; `count_drawer()` takes cents).

Run everything locally (Git Bash on Windows):

```sh
GODOT_BIN="/c/Users/USER/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" ./run_tests.sh
```

`run_tests.sh`:
1. Imports the project.
2. Checks scripts for warnings. Warnings never print when a script loads, so `tools/write_warnings_override.gd` writes `override.cfg` raising every enabled warning to Error for one run, and `tools/check_scripts.gd` compiles every script (addons excluded); the override is deleted afterwards.
3. Runs every suite in `tests/`.
4. Does two `--headless --quit-after 300` boots: the main scene (the interview) and `teller_room.tscn` directly, so the gameplay room is boot-checked on its own, not only through tests.

It fails on any warning, any failing test, a failed boot, or any `ERROR:`/`SCRIPT ERROR:` line. CI (`.github/workflows/tests.yml`) runs the same script on every push and pull request with a pinned Godot 4.7.1 Linux build and uploads the gdUnit4 report. Keep the CI, local and gdUnit4 versions in step.

**Rule: when you verify a fix or feature, add or update permanent tests in `tests/`.** Don't write temporary verification scripts and delete them afterwards. If something can't be reached from a test, make it injectable (e.g. `teller_room.gd`'s `debug_cheats_enabled`) rather than skipping the test.

**Debug shortcut**: F1 (debug builds only, `debug_cheats_enabled`) maxes Reputation and adds XP, unlocking roles through the normal checks.
