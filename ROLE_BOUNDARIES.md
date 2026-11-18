# Role Boundaries and Git Workflow

**Status:** Agreed by Liam (`lym221-not`) and James (`James2k8`) on 2026-11-16. Updated at the end of Phase A (session 4, 2026-11-18): the layout below is now the real one, and section 5 has the Phase B rules.

**Why this file exists:** Liam and James build different roles at the same time, each with their own AI agent. Git only has trouble when two people change the **same lines of the same file**. So each role lives in its own files, and the few shared files are changed carefully, one at a time.

**Paste this whole file into every AI agent prompt** (Claude Code or any other agent), so the agent follows the same rules.

---

## 1. Who owns what

| Area | Owner | What that means |
|---|---|---|
| Teller | Liam | Liam's branches change these files freely. |
| Loan Officer | James | James's branches change these files freely. |
| Branch Manager | Both (frozen for now) | Stays on `ManagerSlotAdapter`. Don't change it without agreeing first. |
| Shared foundation | Both | Change only through a small `shared/...` branch (see section 3). |

## 2. Where files go

The layout (set up in Phase A session 4):

```
scripts/
  core/              ← shared: DayFlow, DaySchedule (shared numbers), the slot pieces,
                       SlotWiring, the cutscene player (Cutscenes), DebugKeys
    events/          ← shared: day events (armored truck, Regional visit)
  roles/
    teller/          ← Liam: TellerSlotAdapter, TellerConfig, TellerRole
    loan/            ← James: LoanSlotAdapter, LoanConfig, LoanRole
    manager/         ← frozen: ManagerSlotAdapter, EndSlotBar, ManagerRole
scenes/
  cutscenes/         ← scene files (JSON; README.md there has the format)
    teller/          ← Liam's cutscenes
    loan/            ← James's cutscenes
    shared/          ← scenes for more than one role (shared branch)
tests/
  support/
    shared/          ← room_suite.gd: the room, career, saves, slot day (shared)
    teller/          ← teller_suite.gd: Liam's test helpers
    loan/            ← loan_suite.gd: James's test helpers
  data/old_saves/    ← sample saves from older formats (shared)
tools/old_saves/     ← the old-save generator (run before a save format change)
```

**Files from before this layout stay where they are** (moving them would touch many files and `project.godot`). They belong to their role all the same:

| Owner | Files |
|---|---|
| Teller (Liam) | `scripts/ui/teller_screen.gd`, `scripts/ui/drawer_count_screen.gd`, `scripts/ui/vault_transfer_screen.gd`, `scripts/world/customer_queue.gd`, `scripts/world/teller_desk.gd`, `scripts/npc/customer_npc.gd`, the teller tests (`teller_*`, `kyc_*`, `b2_*`, `b6_*`) |
| Loan Officer (James) | `scripts/ui/loan_officer_screen.gd`, `scripts/ui/loan_review_screen.gd`, `scripts/data/loan_application.gd`, `scripts/data/loan_applications_data.gd`, `scripts/data/loan_applicant_generator.gd`, `scripts/data/booked_loan.gd`, `scripts/data/credit_report.gd`, `scripts/autoload/loan_desk_manager.gd`, `scripts/autoload/loan_book_manager.gd`, `scripts/world/loan_desk_seat.gd`, `scripts/world/loan_officer_desk.gd`, `scripts/world/npc_loan_desk_worker.gd`, `scripts/npc/loan_applicant_npc.gd`, the loan tests (`loan_*`, `credit_report_*`) |

Anything not listed, and not in a role folder, is shared (section 3). If you're unsure, ask.

Rules:
- **New files for a role go in that role's folders** (`scripts/roles/<role>/`, `scenes/cutscenes/<role>/`, `tests/support/<role>/`). If you're unsure where something goes, ask before creating it.
- **Each role has its own config file** for its numbers: `TellerConfig` (`scripts/roles/teller/teller_config.gd`) and `LoanConfig` (`scripts/roles/loan/loan_config.gd`). `DaySchedule` holds only what's shared: the slots, the staff desks' work, the event slots and the Branch Manager's clean-slot reward.
- **Each role saves its data in its own section** of the save file: `TellerRole.section`, `LoanRole.section` (and the frozen `ManagerRole`), saved under `"roles"`. A role may replace `section` with variables of its own, keeping `reset()`, `save_data()` and `load_data()`. Numbers come back from JSON as floats: read them with `SaveGame.int_of()` and the other typed getters.
- **Cutscenes use the one shared cutscene player** (`Cutscenes`). Don't build a second one. Each role only adds its own scene files.
- **Roles never edit each other's files** and never reach into `DayFlow`'s internals. They talk to `DayFlow` only through its signals and `claim_work()` / `finish_work()` / `hold()` / `release()` / `skip_slot()` (and the read-only checks like `current_slot()` and `is_skip_requested()`).

## 3. Shared files (handle with care)

These files are touched by both roles. Changing them on a role branch is how conflicts happen.

- Everything in `scripts/core/` (DayFlow, DaySchedule, the slot pieces, SlotWiring, the cutscene player, DebugKeys) and `scripts/core/events/`
- `scripts/util/save_game.gd` and `scripts/util/career_reset.gd` (the save system), and the other autoloads in `scripts/autoload/` not listed as a role's in section 2
- `project.godot` (autoloads and input keys)
- `DaySchedule` (the shared config)
- `tests/support/shared/` helpers and `tests/data/old_saves/`
- `scenes/cutscenes/shared/` and `scenes/cutscenes/README.md`
- `CLAUDE.md`
- `scripts/world/teller_room.gd`, `scenes/world/teller_room.tscn` and the other shared scene/world, HUD and letter scripts (a role shouldn't need teller_room.gd in Phase B: see section 5)
- `.github/workflows/` (CI)
- `TIME_SLOTS_DECISIONS.md` and this file

**To change a shared file:**
1. Make a small, separate branch named `shared/<what-it-does>`.
2. Change only the shared file(s) there, run the tests, open a pull request.
3. The other person approves it. Merge it into `main`.
4. Tell the other person to pull `main` into their branch.
5. Then continue your role work on top of it.

If an AI agent thinks it needs to change a shared file while working on a role branch, it must **stop and report** instead of changing it.

## 4. Git workflow

**Idea:** `main` is the official copy of the game and must always work. A branch is a photocopy you change freely. A pull request (PR) asks to copy your changes back into `main`.

### Branches
- **One branch per small piece of work**, merged within a few days. No long-lived personal branches.
- Name branches after the job, with a prefix:
  - `teller/...` (e.g. `teller/opening-cutscenes`)
  - `loan/...` (e.g. `loan/application-redesign`)
  - `shared/...` (e.g. `shared/cutscene-runner`)
  - `fix/...` (e.g. `fix/vault-count-twenties`)
- **Never commit directly to `main`.**
- A `shared/...` branch is worked on by **one person at a time**.

### Starting a piece of work
```bash
git checkout main
git pull
git checkout -b teller/opening-cutscenes
```

### While working
- Commit in small steps with clear messages.
- Run the tests before each commit (Git Bash):
  ```bash
  GODOT_BIN="/c/Users/La Yaung Moe/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ./run_tests.sh
  ```
  Success ends with `== ALL PASSED` (about 5 minutes). It also fails on any GDScript warning, a failed boot or stale character art, like CI. (James: use your own `GODOT_BIN` path.) While working you can run just your suites, then the full script before committing:
  ```bash
  "$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/loan_pile_test.gd -c --ignoreHeadlessMode
  ```
- **At the start of each session**, bring in the latest `main`:
  ```bash
  git checkout <your-branch>
  git merge main
  ```

### Finishing
```bash
git push -u origin <your-branch>
```
Then on GitHub:
1. Open a pull request into `main`.
2. Wait for CI to pass. If it fails, fix it on the same branch and push again.
3. The other person takes a quick look, mainly: "Does this touch my files or a shared file?" Then approves.
4. Merge, and delete the branch.

Back on your computer:
```bash
git checkout main
git pull
git branch -d <your-branch>
```

### If there's a merge conflict
It means both of you changed the same lines. Git marks both versions in the file. Either fix it by hand, or ask the AI agent to resolve it **and explain in plain English what it kept and why**. If it touches the other person's area, check with them first.

### Protecting `main`
On GitHub, `main` has a rule that requires a pull request and passing CI checks before merging. This stops anyone (including an AI agent) from pushing straight to `main` by accident.

---

## 5. Phase B rules

Phase B is Liam (Teller) and James (Loan Officer) working at the same time. Everything a role needs from the shared side is already in place, so a role branch should never need a shared file:

1. **No new autoloads.** Each role already has one: `TellerRole`, `LoanRole` (keep its `reset()`, `save_data()`, `load_data()`). If a role really needs another, that's a `shared/...` branch.
2. **No new input actions.** Each role has two debug keys reserved, for debug builds only: the Teller `DebugKeys.TELLER_1` (F5) and `TELLER_2` (F6), the Loan Officer `DebugKeys.LOAN_1` (F9) and `LOAN_2` (F10). Read them with `OS.is_debug_build() and event.is_action_pressed(DebugKeys.TELLER_1)`. Taken already: WASD/arrows, E, Z, Esc, Enter/Space, F1, F2, F3. A real (non-debug) key is a `shared/...` branch.
3. **Cutscenes must use the shared player:** a JSON file in `scenes/cutscenes/<role>/`, played with `await Cutscenes.play(path)`. `tests/cutscene_scene_test.gd` checks every scene file. If version 1 can't do something (for example walking characters), that's a `shared/...` change to the player, not a second player.
4. **Each role's numbers live in its own config** (`TellerConfig`, `LoanConfig`), not in code and not in `DaySchedule`.
5. **Each role's saved data lives in its own section** (`TellerRole`, `LoanRole`). No new top-level save keys and no format version change on a role branch.
6. **Don't edit `teller_room.gd`, `project.godot` or `SlotWiring`.** A role's piece of the day is its slot adapter (`TellerSlotAdapter`, `LoanSlotAdapter`), already placed by SlotWiring. A role's test helpers go in its own suite (`tests/support/teller/teller_suite.gd`, `tests/support/loan/loan_suite.gd`). If a role needs something new from the room, stop and ask for a `shared/...` branch.
7. **The Branch Manager stays frozen.** Don't change `scripts/roles/manager/` without agreeing first.

---

## 6. Rules for AI agents (summary)

When you work in this repo:
1. Work only on the branch named in the prompt. Never commit to `main`.
2. Only change files in the owner's area named in the prompt. Put new files in the right folder (section 2).
3. **Do not change shared files** (section 3) unless the prompt is a `shared/...` task. If you think you need to, stop and report.
4. Use the existing shared systems (DayFlow, the cutscene player, save sections, configs, reserved debug keys). Don't build duplicates, and follow section 5.
5. Put numbers in the role's config file, not in code.
6. Commit in small steps and run the full test suite before each commit.
7. Report back in plain English: what you changed, which files, test results, and anything you weren't sure about.
