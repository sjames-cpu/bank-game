# BankSim — Development Log

Living record of what's been built, session by session. Update this alongside `CLAUDE.md` as new work lands; `CLAUDE.md` describes current architecture, this file describes how it got there.

## Where things stand (as of 2026-10-19)

BankSim is a single-room bank-branch simulation with a career path, NPC coworkers and an automated test suite:

- **Roles/desks**: Teller (customers with stated requests graded on Complete Transaction, complaints, opening and closing drawer counts), Loan Officer (credit checks, application grading), Branch Manager (staff scheduling, approvals, vault reconciliation, staff review and discipline), plus a standalone ATM.
- **Career**: XP and Reputation unlock Loan Officer and then Branch Manager (promotion held until clock-out, with letters). Teller mistakes earn written warnings; 3 reports mean termination, a career reset and the hiring interview.
- **NPC coworkers**: staff work Teller Windows 1-3 and the Loan Desk with their own customer lines, make stat-driven mistakes, and are reviewed and disciplined by the Branch Manager.
- **World**: a full branch floor plan (`room_builder.gd`) with y-sorted characters and furniture, furniture collision, an outdoor entrance, a customer queue per window, and a day/night tint.
- **Player guidance**: an always-on HUD (role, Score, Reputation, XP, Reports, shift status, notifications), "E — ..." interaction prompts and first-run hints.
- **Money**: integer cents end to end, formatted through `MoneyMath`.
- **Time**: a game clock and a business day (open 9 AM-5 PM), with an End of Day summary and going home early. The career saves to disk and continues from a start screen.
- **Quality**: 177 gdUnit4 tests, strict GDScript warnings that fail CI, and a GitHub Actions run on every push.

---

## Session 1 — Sep 8, 2026: Loan Officer, Branch Manager, Teller queue systems
*(commit `7bfca42`)*

Brought in Phase 4-5 role systems plus a Phase 6a customer queue:

- **Loan Officer desk** (`loan_officer_screen`, `loan_officer_desk.gd`) — review loan applications with a credit-check step and grade them Approve / Reject / Counter-Offer (`loan_review_screen`, `loan_application.gd`).
- **Branch Manager hub** (`branch_manager_screen`, `branch_manager_desk.gd`) — staff scheduling (`staff_scheduling_screen`, `staff_member.gd`, `staff_roster_data.gd`), an approvals override screen for manager sign-off, and vault reconciliation (`vault_reconciliation_screen`).
- **New autoloads**: `HistoryManager` (logs decisions/events) and `ScheduleManager`, backing the above.
- **Customer queue for the Teller room**: `CustomerNPC` + `CustomerQueue` spawn customers and walk them into a line; the teller desk now serves the front customer automatically on a completed deposit/withdrawal (not just when the screen closes), and shows a live "Serving: X" / "No customer waiting." status.
- **Fix**: renamed a shadowed parameter in `LoanApplication.grade()` that was causing a warning-as-error build failure.

## Session 2 — Sep 15, 2026 (AM): AccountManager, ATM, complaints, UI polish
*(commit `a2c6572`)*

- **`AccountManager` autoload** — single shared source of account data so the ATM and Teller desk read/write the same records instead of diverging.
- **ATM screen** (`atm_screen`) — standalone deposit/withdraw flow, no account creation.
- **Customer complaints + dialogue** — `customer_complaint.gd`, `complaint_response.gd`, `customer_complaints_data.gd`, `customer_dialogue_data.gd`/`customer_dialogue_line.gd`, wired into a Teller complaint-resolution flow.
- **Day/night cycle** (`day_night_cycle.gd`).
- **`banking_theme.tres`** — shared theme applied across Teller and five other screens for consistent visual hierarchy, section grouping, and currency formatting (`currency_spin_box_format.gd`).
- **Exploit fixes** found during review passes:
  - Vault Reconciliation repeat-click / repeat-visit exploit.
  - Loan review shift-limit skip.
  - Staff double-booking in scheduling.
  - Card-decline retry spam on the ATM.
  - Desk re-entrancy guards added generally.
- **Cleanup**: dead signals/vars removed (`InterviewManager`, ATM/Teller closed signals, `HistoryManager`), `class_name ATMScreen` added, stale doc comments on `LoanApplication` corrected.

## Session 3 — Sep 15, 2026 (PM): Content rewrite, queue abandonment, UI fix
*(commit `1674313`)*

- **Interview content rewrite** — `InterviewQuestionsData` replaced with research-backed situational-judgment and competency questions, including instant-reject items for integrity violations.
- **Complaint content rewrite** — `CustomerComplaintsData` replaced with realistic fee/wait/discrepancy/escalation/bereavement scenarios following a proper acknowledge-then-resolve de-escalation pattern.
- **Queue abandonment mechanic** — each waiting customer now has a patience timer with a visual tint as it runs down; if it expires the customer abandons the line, taking a Reputation penalty and logging an entry via `HistoryManager`.
- **UI fix** — Complaint panel and 7 task-layer screens were overflowing content above/below their visible border; fixed by converting their main `Panel` to an auto-sizing `PanelContainer`.

## Session 4 — Sep 16, 2026: Player animation, full branch layout, modern-office redesign
*(commit `039762e`)*

- **Player animation** — the player is now an `AnimatedSprite2D` with idle/walk loops for down/up/side facing (side mirrors for left via `flip_h`), driven by a facing-state tracker in `player_movement.gd` that only restarts the animation when the resolved state actually changes (no restart-jitter) and scales walk speed to actual movement speed.
- **Full branch floor plan** — `teller_room`'s single small placeholder room is replaced with a proper multi-zone layout built procedurally in `room_builder.gd`: a back-office row (Vault / Manager's Office / Conference Room / Accounting), each with one door gap, walled off from one open floor (Marketing+Loan bullpen, Teller Area, Waiting Lounge near the entrance). Every desk, the ATM, and the customer queue moved to match. `Camera2D` zoom dropped from 2x to 1x, which had been magnifying everything more than intended.
- **Visual redesign** — went through two full palette passes (a navy/gold "traditional bank" look, then a muted retro-tile look) before landing on a modern-office identity matching a floor-plan reference image: grey-blue open floor and light walls in the bullpen, brick walls and wood floors in the back offices, cream desks with blue-screened monitors and black rolling chairs. Added ambient props the reference suggested: potted plants, a wall clock, an archive bookshelf, a printer, wall-mounted whiteboards, and a water cooler. Every piece kept its original footprint/position from the layout pass, so only the artwork changed.
- **Interview disabled as the entry point** — `run/main_scene` now boots straight into `teller_room` instead of the hiring interview, since the interview is being rebuilt from scratch. `InterviewManager`/`interview_screen` are untouched and still work standalone; `is_on_probation` stays at its default `false` until it's reconnected.
- **Tooling**: added three Godot-specialist subagents (`godot-specialist`, `godot-gdscript-specialist`, `godot-shader-specialist`) to `.claude/agents/`, cherry-picked from the open-source Claude-Code-Game-Studios framework for architecture/code-quality/shader consults going forward.

## Session 5 — Sep 23, 2026: Customer accounts, intents and looks
*(commits `6bb2876`, `4e2d2e4`, `e7ad33d`)*

- **Customers became people**: each spawned customer gets their own account (reused by name) and a stated Deposit/Withdraw request; serving them selects their account. Served customers say a farewell and walk out after the Teller screen closes. Auto-created customer accounts stay out of the teller's account dropdown.
- **Three customer designs** (business-casual, retiree, streetwear) with full idle/walk sprite sheets on the player's frame grid, as `AnimatedSprite2D`s.
- **Tooling**: the Godot specialist agents' sources and their `production/` scaffold.

## Session 6 — Sep 29 – Oct 9, 2026: Handoff and audit
*(commits `fdd9b79`, `9643190`)*

- **`HANDOFF.md`**: a bug list (B1-B14), design flaws and a roadmap toward a bank-training simulation.
- **`AUDIT_REPORT.md`**: an audit of the first round of fixes (below): which were done, which need rework, and the order for the rest.

## Session 7 — Oct 7, 2026: First Phase 0 fixes, reports, NPC coworkers
*(commits `e4fc55e` through `22995ba`)*

- **Fixes**: B7 (F1 cheat only in debug builds), B8 (unlocks re-checked on Reputation changes), B1 (clock-out clears the served customer), B3 first pass (whole-dollar amounts, cent-exact discrepancy checks), B2/B6 first pass (clock-out gated on finished work instead of a 45 s timer; requests graded), B9 (DTI from monthly payments), B12 (`.godot/` untracked). Notifications moved out of the teller title.
- **Customer corrections**: a wrong transaction leaves the customer at the desk saying what's wrong; fix it with another transaction or Reverse Transaction, or they leave upset. Wrong-account transactions must be reversed.
- **Disciplinary reports and termination** (`ReportManager`, `CareerReset`, letters), reconnecting the interview after a firing.
- **NPC coworkers**: staffed Teller Windows 1-2 and Loan Desk (`StaffNPC`, `ScheduleManager` desk slots), staff serving their own customer lines with stat-driven speed and mistakes, the player's own teller window, and queue pacing so customers never overlap.

## Session 8 — Oct 8, 2026: Branch Manager promotion
*(commit `b78dc20`)*

- Promotion is held until clock-out, with a Letter of Promotion that clears the record. After promotion the Player Teller Window becomes staffed Teller Window 3, the Loan Desk's staff stays put, a one-time orientation letter appears, and the shift summary gains a Branch section.

## Session 9 — Oct 12, 2026: Audit rework, tests, CI, staff review
*(commits `bce4dd0` through `8f9a933`)*

- **B6**: requests are graded on Complete Transaction, so a split deposit is no longer a mistake; the account resets once nobody is served.
- **B2**: customers, not the drawer, are the main teller score (+5 per correct request, abandonment costs Score, the drawer bonus scales with customers served).
- **Staff-line accounts** in their own namespace, so staff can't drain a player-line customer's balance. Customer balances start on whole dollars.
- **Tests and CI**: gdUnit4 v6.2.1, permanent tests for B1-B9, reports and NPC staff, and a GitHub Actions workflow running `run_tests.sh`.
- **Staff review**: the Branch Manager reviews staff mistakes and loan calls (report, feedback, excuse; hidden severity), with points for fair calls and termination at 3 staff reports.

## Session 10 — Oct 14, 2026: Remaining handoff items
*(commits `f71b351` through the B13 docs commit)*

- **B4**: an always-on HUD (role, Score, Reputation, XP, Reports, shift status; notifications moved off TellerScreen), "E — ..." interaction prompts with reasons for locked desks, and first-run hints once per career (`HintManager`). The spawn point was checked and kept.
- **B5**: the whole room is y-sorted with furniture sorting at its base; furniture footprints block the player only; the entrance is a doormat with a solid sidewalk outside.
- **B2**: the opening count matters: Minor is logged, Major needs a recount, and after two recounts a supervisor signs off for −2 Reputation.
- **B3**: money is integer cents end to end, displayed through `MoneyMath.format()`; seeded gameplay is unchanged.
- **B11**: desks share an `Interactable` base, and desks, screens and the room have class_names and typed references.
- **B10**: stricter GDScript warnings, all fixed, and CI fails on any warning (`tools/`).
- **B14**: leftover placeholder files deleted. **B13**: this log, `CLAUDE.md` rewritten, stale comments fixed, status notes on `HANDOFF.md` and `AUDIT_REPORT.md`.

## Session 11 — Oct 14, 2026: Probation, save and load
*(commits `8d19d94` through the save/load commit)*

- **Probation**: every new game now starts at the interview. Hired on Probation lowers the termination limit to 2 reports. Three teller shifts in a row without a report end probation with a "Probation Complete" letter, and a report restarts the count. Promotion to Branch Manager ends probation without a letter. The HUD shows progress ("Probation — 1 of 3 clean shifts") and warning letters mention probation.
- **Boot check**: `run_tests.sh` and CI also boot `teller_room.tscn` directly, since the main scene no longer leads straight to it.
- **Save and load** (`SaveGame`, the HANDOFF "no persistence" flaw): the whole career is saved as versioned JSON in `user://career.json` when the player is hired, at every clock-out, after a promotion and after the orientation letter. Mid-shift state is never saved. A new start screen offers Continue (back into the room, off shift) or New Game (after a confirmation, the save is deleted). A damaged or wrong-version save shows a message, is moved aside, and a new game starts. Termination deletes the save as soon as the letter appears. Tests use their own save path.

## Session 12 — Oct 14, 2026: Hiring staff (NPC coworkers, step 5)
*(the hiring commit)*

- **Hire Staff**: a Branch Manager with an empty desk (after a termination, or left empty on the schedule) gets three candidates for that desk's role. Their names come from a separate pool, each has a one-line background, and their stats are hidden. One is strong, one average, and one weak in the stat that matters at that desk: reliability for a teller, skill for a loan officer.
- **Interviews**: the manager asks three questions from the player's own interview. Candidates answer from the stats that drive the desk, so the weakness shows in poorer answers. Very low reliability can produce an instant-reject answer (a red flag) for either role. Stats are revealed only on the "hired" card.
- **Scoring** (`HiringManager`): candidates are ranked by the stats the desk's formulas use. The best hire earns +6 Score/+1 Reputation, the middle one +1/0, the weakest −4/−1, and a red-flag hire −6/−2. Reject All scores nothing, and new candidates arrive at the next clock-in. Hired staff work with the same formulas as everyone else. The roster is capped at 8, and hiring is only possible for a real vacancy.
- **Save/load**: hired staff, waiting candidates with their interview progress, and rejected vacancies are saved. A new career goes back to the original roster.

## Session 13 — Oct 15, 2026: Camera zoom and controls line
*(commits `995e8ac`, `89fb8a4`)*

- **Camera** (`RoomCamera`): characters were 24 px tall at the 1x zoom, too small to show their sprite detail. The camera now follows the player at 2x, smoothly, clamped to the room and sidewalk so nothing past the walls shows. Z (`toggle_overview`, named in the arrival hint) switches to the old 1x overview, centred on the room horizontally.
- **Crisp world text** (`WorldText`): staff names and speech, customer farewells and requests are rasterised at their on-screen size and scaled by 1/zoom, so they stay sharp at either zoom (11–12 px at 1x, 1.25x that at 2x). The HUD, screens and letters don't zoom.
- **Controls line**: "E — interact · Z — zoom" stays in the HUD's bottom-left corner, with key names read from the InputMap, so the zoom key can still be found after the one-time arrival hint. It sits clear of the HUD column, every centred screen and letters.

## Session 14 — Oct 15–19, 2026: Game clock and business day
*(commit `5c77e6d` for part 1, and the business day part 2 commit)*

- **Part 1, the game clock** (`GameClock`, the HANDOFF "wall-clock time" flaw): a day number and time of day that run only on unpaused time, 1.5 game minutes per second. It's shown on the HUD, drives the day/night tint, and stamps every record, report and shift summary. A new career starts on Day 1 at 8:30 AM.
- **Part 2, opening hours** (`BusinessDay`): the branch is open 9:00 AM–5:00 PM. Customers arrive and the Loan Desk's staff decide only while it's open. The player can clock in from 8:30 for the opening count, but not after 4:30 PM. At 9:00 every line taking customers restarts its arrival timer, so the first customers come within a few game minutes instead of up to half an hour late.
- **Closing**: at 5:00 PM the doors close. Customers already inside are still served and staff finish theirs, then idle. Customers the player's shift never got don't block clock-out, and the HUD says the branch is closed.
- **End of Day summary** (`end_of_day_screen.gd`): once it's past 5:00, the player is off shift and the lobby is empty, a summary shows the customers the branch served (player and staff), the player's shifts, and the day's Score, Reputation and XP changes. "Start Day N+1" moves to 8:30 the next morning. A day left running past midnight still ends at its summary.
- **Going home early**: off shift, the entrance doormat (`ExitDoor`) asks "Go home and end Day N?". Going home skips the clock to 5:00 PM, clears the lobby and shows the same summary, with nothing simulated for the skipped hours.
- **Save/load and hints**: the day's totals are saved with the career, which is also saved when the summary appears and when the next day starts. A one-time hint explains the hours and going home.

## Session 15 — Oct 19, 2026: The Regional Manager
*(the Regional Manager commit)*

- **Reviews** (`RegionalManager`): every 5 business days as Branch Manager, the Regional Manager reviews the days since the promotion or the last review. On review day they visit mid-morning (a new generated look: grey suit, silver hair) and stand outside the Manager's Office. The review letter comes at that day's End of Day, before the summary.
- **The rating** weighs vault reconciliation (by day; a day with no count scores 0), serious staff errors left unreviewed, unfair reports, excused serious errors, the staff mistake rate, customers who gave up at staffed windows, vacant desks and hiring quality into a 0–100 score: Exceeds, Meets, Needs Improvement or Unsatisfactory. Areas with nothing to judge aren't rated, so a week of going home without working is judged on its missing vault counts and waiting serious items.
- **Consequences**: Exceeds earns +15 Score and +3 Reputation and removes a regional warning; Needs Improvement adds a warning; Unsatisfactory adds one and costs 5 Reputation. Three warnings demote the player to Loan Officer: Teller Window 3 closes, the Branch Manager desk hides, the player's desks and the branch's reports apply again, staff review items still waiting are closed without penalty, and promotion again takes 500 more XP and Reputation 60. The HUD shows "Next review: Day N · Warnings 1/3" in place of "Reports: n/a (manager)", and the Branch Manager unlock hint is shorter so the column still fits.

## Session 16 — Oct 21, 2026: Reputation 0 has consequences
*(the Reputation 0 commit)*

- **Reputation 0** (HANDOFF design flaw): falling to 0 used to only show the HUD warning. Now a Teller or Loan Officer gets one written warning ("customer satisfaction has fallen to zero") that counts toward termination like any other, and a Branch Manager gets one regional warning with its own letter. The HUD warning stays.
- **Once per fall**: it fires again only after Reputation has recovered above the low-reputation threshold (`ReputationManager.zero_armed`, saved with the career).
- **A third regional warning this way** demotes at that day's End of Day, before the summary, so the player is never demoted mid-shift.

---

## Notes for next session

- No `.csproj`/`.sln` yet: everything is still GDScript despite the project being configured for .NET.
- The save has one slot and no autosave mid-shift: quitting mid-shift loses that shift's work.
- The business day has opening hours and an End of Day summary (`BusinessDay`), but nothing ever closes the career's days for good: there's no week, month or year view yet.
- The cash model still has $1,000/$500 bills and no coins; amounts are already in cents, so coins can be added as more `DENOMINATION_CENTS` entries.
- Loan application figures are whole-dollar floats by design (judged, never moved as cash).
