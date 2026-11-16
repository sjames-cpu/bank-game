# Role Boundaries and Git Workflow

**Status:** Agreed by Liam (`lym221-not`) and James (`James2k8`) on 2026-11-16. The folder layout below is a plan; it is set up in Phase A session 4 and this file is updated then if anything changes.

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

Planned layout (set up in Phase A session 4):

```
scripts/
  core/            ← shared: DayFlow, DaySchedule, cutscene runner, save system
  roles/
    teller/        ← Liam: TellerSlotAdapter, teller mechanics, teller config
    loan/          ← James: LoanSlotAdapter, loan mechanics, loan config
    manager/       ← frozen: ManagerSlotAdapter
scenes/
  cutscenes/
    teller/        ← Liam's cutscenes (e.g. opening security entry)
    loan/          ← James's cutscenes
tests/
  support/
    shared/        ← shared test helpers
    teller/        ← Liam's test helpers
    loan/          ← James's test helpers
```

Rules:
- **New files for a role go in that role's folders.** If you're unsure where something goes, ask before creating it.
- **Each role has its own config file** for its numbers (dollar amounts, XP, work per slot). A small shared config holds only values both roles need.
- **Each role saves its data in its own section** of the save file, so new saved values don't collide.
- **Cutscenes use the one shared cutscene runner.** Don't build a second one. Each role only adds its own scene files.
- **Roles never edit each other's files** and never reach into `DayFlow`'s internals. They talk to `DayFlow` only through its signals and `claim_work()` / `finish_work()` / `hold()` / `release()` / `skip_slot()`.

## 3. Shared files (handle with care)

These files are touched by both roles. Changing them on a role branch is how conflicts happen.

- Everything in `scripts/core/` (DayFlow, DaySchedule, cutscene runner, save system)
- `project.godot` (autoloads and input keys)
- The shared config file
- `tests/support/shared/` helpers
- `scripts/world/teller_room.gd` and other shared scene/world scripts, until fully split up
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
  GODOT_BIN="/c/Users/La Yaung Moe/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" bash addons/gdUnit4/runtest.sh --headless -a res://tests --ignoreHeadlessMode
  ```
  Success ends with `Run tests ends with 0`. (James: use your own `GODOT_BIN` path.)
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

## 5. Rules for AI agents (summary)

When you work in this repo:
1. Work only on the branch named in the prompt. Never commit to `main`.
2. Only change files in the owner's area named in the prompt. Put new files in the right folder (section 2).
3. **Do not change shared files** (section 3) unless the prompt is a `shared/...` task. If you think you need to, stop and report.
4. Use the existing shared systems (DayFlow, cutscene runner, save sections, configs). Don't build duplicates.
5. Put numbers in the role's config file, not in code.
6. Commit in small steps and run the full test suite before each commit.
7. Report back in plain English: what you changed, which files, test results, and anything you weren't sure about.
