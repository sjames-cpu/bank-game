# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**BankSim** is a Godot project past initial scaffolding, with a first vertical slice implemented end-to-end in GDScript: a hiring interview mini-game, a top-down player/room, and a teller desk workflow (drawer counts, deposits/withdrawals, shift scoring, reputation). No `.csproj`/`.sln` exists yet — everything so far is GDScript, even though the project is configured for .NET (see below). `node_2d.tscn` is a leftover placeholder scene, no longer the entry point.

Treat any architectural description here as provisional — update this file as real structure changes, since it's still an early slice.

### Flow

`run/main_scene` is `scenes/world/teller_room.tscn` (spawns the player in a small tile room with a `TellerDesk`) — the hiring interview (`scenes/ui/interview_screen.tscn`, `InterviewManager`) is not the entry point for now since it's being rebuilt from scratch. Its only way in is termination: 3 disciplinary reports (`ReportManager`) show a termination letter (`discipline_letter_screen.tscn`, in teller_room's `UI` layer) whose "Apply for a new job" button wipes all career progress via `CareerReset.reset_all()` (each autoload has a `reset()`) and loads the interview; passing it loads teller_room again. `is_on_probation` therefore stays `false` until the player has been through that path. Interacting with the desk (`ui_accept` or the `interact` action, E) opens `TellerScreen`, which pauses the tree and drives clock-in → deposits/withdrawals → clock-out → shift summary. The player spawns at (384, 624), just inside the entrance gap and clear of furniture and customer lanes (checked by `tests/b4_hud_test.gd`).

### Autoloads (`scripts/autoload/`)

Global singletons registered in `project.godot`'s `[autoload]` section, each a plain `Node` holding in-memory state (nothing persisted to disk yet) and a `*_changed`/`*_completed` signal for UI to react to:

- **ScoreManager** — `total_score`, a running per-session tally adjusted via `add_shift_score()`.
- **ReputationManager** — `reputation`, clamped to `[0, 100]`, adjusted via `add_reputation()`. `LOW_REPUTATION_THRESHOLD` gates a warning label; a Loan Officer role unlock is planned but not wired up.
- **ReportManager** — disciplinary reports: every 2 mistaken teller customers (`CustomerNPC.was_mistake`) = 1 report, 3 reports = termination. Carries across shifts/roles; cleared and disabled once Branch Manager unlocks (TODO: Regional Manager review for managers). The Branch Manager unlock (`XPManager`) is held while the player is clocked in at the Player Teller Window or Loan Desk (`begin_player_shift`/`end_player_shift`, called by teller_room) and granted on clock-out; it shows one promotion letter (`discipline_letter_screen.gd`) that also states the record was cleared. The F1 debug unlock goes through the same check. After promotion: the Player Teller Window becomes the staffed "Teller Window 3" (`ScheduleManager.SLOT_TELLER_WINDOW_3`, only in `get_desk_slots()` once `is_teller_window_3_open`; served by `Window3Line` on the player's lane), the Loan Desk's staff never steps away, both desks only show a "[staff] is working…" notice (`UI/DeskNotice`), the first Branch Manager clock-in shows a one-time orientation letter (`XPManager.has_seen_branch_orientation`), and the Branch Manager shift summary gets a report-only "Branch" section built from that shift's staff records (`HistoryManager.staff_record_added`; records carry `staff_slot`). `CareerReset` + the scene reload undo all of it. Logs to HistoryManager under `DecisionRecord.Role.DISCIPLINARY` (never actionable in approvals). Registered last in `[autoload]` since it connects to XPManager in `_ready()`.
- **StaffReviewManager** — the Branch Manager's staff review (NPC coworkers step 4). Once the player is Branch Manager, every staff teller mistake and every staff loan decision not graded BEST becomes a `StaffReviewItem` in its own queue (separate from HistoryManager's 200-record staff cap). Severity (hidden until the manager decides): wrong-account teller mistake or WORST loan = Serious (Issue Report); other teller mistakes and BAD loans = Minor (Give Feedback), Repeated minor once that staff member has had 2 feedbacks (Issue Report); PARTIAL loans = Acceptable (Excuse). Point table in its constants. Serious items left unreviewed at Branch Manager clock-out cost Reputation and close as "Ignored". Per-staff reports/feedbacks for the career; at 3 reports the Staff Review screen (`staff_review_screen.gd`, from the Branch Manager hub) offers Terminate, which calls `ScheduleManager.dismiss_staff()` — the desk becomes unassigned and `teller_room.gd` closes its line (`NpcCustomerLine.close_line()`). No hiring yet. Logs as BRANCH_MANAGER records; reset by `CareerReset`.
- **HintManager** — which first-run hints (`Hint` enum: arrival, first customer, first clock-out, Loan Officer and Branch Manager unlocks) this career has seen, so each shows once per career (`mark_shown()`), plus their text (`text_for()`). `teller_room.gd` decides when they fire; the HUD shows and queues them. Reset by `CareerReset`.
- **InterviewManager** — resolves the interview mini-game's outcome (`resolve_outcome()`), exposes `Outcome` enum (`HIRED` / `HIRED_ON_PROBATION` / `REJECTED`), `HIRE_THRESHOLD`/`PROBATION_THRESHOLD` constants, and `is_on_probation` (set but not yet used by gameplay).

### Data resources (`scripts/data/`)

Small `Resource`-based structs, built in code rather than loaded from `.tres` files (no save/load need yet): `Account` (customer name + balance, mutated only via `deposit()`/`withdraw()`), `ShiftTransaction` (one deposit/withdrawal record), `InterviewQuestion`/`InterviewAnswer` (interview question text plus 2-4 scored answer choices, an answer can be `is_instant_reject`). `interview_questions_data.gd` is a static provider (`InterviewQuestionsData.get_questions()`) holding the actual 9-question interview script, kept separate from the data shape so content can grow independently.

### World & UI scripts (`scripts/world/`, `scripts/player/`, `scripts/ui/`)

- `player_movement.gd` — 8-direction `CharacterBody2D` movement (WASD/arrows) via the `move_*` InputMap actions.
- `room_builder.gd` — fills a `TileMapLayer` with a simple walled rectangular room at runtime (placeholder level, no hand-painted layout yet). The entrance gap is a doormat and a solid sidewalk strip runs outside the bottom wall, from a second atlas (`assets/tilesets/outdoor_tiles.png`, source 1), so the player can stand in the doorway but not leave.
- `teller_desk.gd` — an `Area2D` that only detects player proximity + interact key (`ui_accept` or the `interact` action) and emits `interacted`; it doesn't know what happens next (`teller_room.gd` connects the signal to opening `TellerScreen`). `loan_officer_desk.gd`, `branch_manager_desk.gd` and `atm.gd` are the same pattern. The Loan Desk always detects the player; `teller_room.gd` ignores its interaction until the Loan Officer unlock.
- `hud.gd`/`hud.tscn` (`HUD` CanvasLayer in teller_room, layer 2 above `UI`) — the always-on HUD (B4): role, Score, Reputation, XP, Reports and shift status (from `teller_room.describe_shift_status()`) in a top-right column outside every centred screen at 1152px wide; below them the low-reputation warning and role-unlocked notifications (moved off TellerScreen), then first-run hints with a "Got it" button; and the "E — …" interaction prompt below (on the player's side of) whichever interactable the player stands at (`teller_room.interaction_prompt_text()`, hidden while a screen pauses the tree). Hidden while the termination letter is up. The desk screens no longer have their own score panels or notifications. Key names come from the InputMap via `InputPrompts.key_for()` (`scripts/util/input_prompts.gd`).
- `teller_room.gd` — room root, wires `TellerDesk.interacted` to `TellerScreen.show_screen()`. The branch has three teller windows: `TellerDesk` is the player's own **Player Teller Window** (x=464, its own `CustomerQueue` lane, never staffed), and `TellerWindow1`/`TellerWindow2` are always staffed. It places NPC coworkers (`StaffNPC`, `scenes/characters/staff_npc.tscn`) at the staffed desks — Teller Window 1, Teller Window 2, the Loan Desk (`LoanOfficerDesk`) — from `ScheduleManager`'s desk slots (`DESK_SLOTS`, default assignment picked from `StaffRosterData` by role). While the player is clocked in at the Loan Desk, its staff member walks to `StaffBreakArea` (conference room) and back on clock-out. Queue pacing (`CustomerQueue._update_queue_movement()`, shared by every line): customers step forward one spot at a time only into a clear spot, the counter spot stays blocked until the previous customer has said goodbye and walked clear, and leaving customers sidestep into a corridor between lanes (`exit_side_offset`) so they never walk through a waiting line — visual only, nothing graded depends on it. Draw order (B5): the room root is y-sorted, and so are `Staff`, the customer lines, `Decor` and each desk node, so the player, customers, staff and every furniture sprite sort together. Each furniture sprite's origin is at its base (texture `offset` up), so characters switch from behind to in front where their feet pass its bottom edge; staff stand above their counter's base, so it covers their lower body. Solid furniture has a `Footprint` `StaticBody2D` (its base only, not the full sprite) on physics layer 16. Only the player's mask (17 = walls + furniture) includes it. Customers and staff walk scripted paths and collide with walls only, and the player and NPCs never collide, so a customer walks through a player standing in their lane. The hidden Branch Manager desk's footprint is disabled until promotion. Staff work: each teller window has its own line — `Window1NpcLine` and `Window2Line` (`NpcCustomerLine`, extends `CustomerQueue`: no per-shift cap, max 3, no complaints, arrivals every random 12-18 s, always on) are served by the desk's NPC with service time/mistake chance from `StaffMember` stats. `NpcLoanDeskWorker` decides loan applications in the background while the player isn't at the Loan Desk. NPC work applies real account changes but never touches the player's Score/Reputation/XP or drawer; it's logged as `DecisionRecord.Role.STAFF` records (only the newest 200 kept; hidden from the approvals inbox for now).
- `interview_screen.gd`/`.tscn` — the interview mini-game UI (question label + dynamically-built answer buttons), tracks running score and an instant-reject flag across all questions, then hands both to `InterviewManager.resolve_outcome()`.
- `teller_screen.gd`/`.tscn` — the main teller desk UI: account selection/creation, deposit/withdraw, clock-in/out (each routes through `drawer_count_screen.gd` for a cash count), and a shift summary that posts to `ScoreManager`/`ReputationManager`.
- `drawer_count_screen.gd`/`.tscn` — denomination-based cash-counting mini-game; compares the player's count against an expected balance the caller supplies and classifies the result as Perfect/Minor/Major discrepancy. Doesn't manage its own pause state — the caller (`TellerScreen`) is expected to already have the tree paused.

## Engine configuration (`project.godot`)

- **Godot version**: 4.7, GL Compatibility rendering feature profile.
- **Renderer**: `gl_compatibility` on both desktop and mobile (not Forward+/Mobile).
- **Rendering device (Windows)**: `d3d12`.
- **.NET/C#**: enabled — `[dotnet] project/assembly_name="BankSim"`. When C# scripts are added, a `.sln`/`.csproj` will need to be generated (Godot does this automatically the first time a C# script is created in the editor, or via `dotnet new`).
- **Physics**: 3D physics engine is Jolt Physics (not the Godot default).
- **Display stretch**: `canvas_items` mode with `expand` aspect — this is a 2D-scaled project setup even though 3D physics (Jolt) is configured, so don't assume the project is purely 2D or purely 3D from this alone.

## Editing `project.godot`

This file is hand-editable but the header explicitly warns it's best edited via the Godot editor UI, since not all parameters are obvious/documented. Prefer making engine-setting changes through the editor when possible; when editing directly, keep the section/key format consistent with the existing file. A `project.godot.bak` backup exists from a prior editor save — don't treat it as a file to edit or keep in sync.

## Version control notes

- `.gitattributes` normalizes all text files to LF line endings.
- `.godot/` (Godot's local cache/import directory) is gitignored — never treat files under it as source.
- `.summer/local/` is gitignored — it holds local-only state for a "Summer Engine" tooling layer wrapping this repo (including its own nested bare git repo under `.summer/local/git/`). This is tooling-local, not project source; don't edit or commit through it.

## Development workflow

Since there's no `.csproj`, C# scripts can't be compiled outside the Godot editor until one is generated. Playing the game means opening the project in the Godot 4.7 editor and using Play/Run.

### Tests

Automated tests use **gdUnit4 v6.2.1** (`addons/gdUnit4/`, supports Godot 4.7/4.7.1; the addon's own self-tests were left out). Suites live in `tests/` (`*_test.gd`, extending `GdUnitTestSuite`). Suites that drive the real teller room extend `tests/support/teller_room_suite.gd`, which gives each test a fresh `teller_room.tscn` and a fresh career (`CareerReset`), seeds the RNG, and has helpers for clocking in/out, spawning customers with fixed requests, and pressing the teller buttons.

Run everything locally with one command (Git Bash on Windows):

```sh
GODOT_BIN="/c/Users/USER/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" ./run_tests.sh
```

`run_tests.sh` imports the project, runs every suite in `tests/`, then does a `--headless --quit-after 300` boot. It fails if a test fails, the boot fails, or Godot prints any `ERROR:`/`SCRIPT ERROR:` line. HTML/XML reports go to `reports/` (gitignored). CI (`.github/workflows/tests.yml`) runs the same script on every push and pull request with a pinned Godot 4.7.1 Linux build. Keep the CI version, the local version and the gdUnit4 version in step.

**Rule: when you verify a fix or feature, add or update permanent tests in `tests/`.** Don't write temporary verification scripts and delete them afterwards. If something can't be reached from a test, make it injectable (e.g. `teller_room.gd`'s `debug_cheats_enabled`) rather than skipping the test.
