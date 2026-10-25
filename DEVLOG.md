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

## Session 17 — Oct 21, 2026: Staffing sets the pace of the player's line
*(the player's-line pressure commit)*

- **Customers choose a line** (HANDOFF design flaw, "staffing is decorative", the part the audit left open): when a staff teller window is closed or its line is long because its teller is slow, customers come to the Player Teller Window sooner.
- **The model**: each staff window's crowding is 1 when closed, 0 with nobody waiting behind the customer at the window, and 0.5 or 1 with one or two waiting (the line holds three). The average over Teller Windows 1 and 2 is the pressure, and the gap between the player's arrivals is 20 s × (1 − 0.5 × pressure): 20 s fully staffed, 15 s with one window closed, 10 s with both closed or both full. It's worked out as each gap starts.
- **Unchanged**: 4 customers a shift, patience and abandonment, opening hours.
- **CI flake fixed** (separate commit): `hiring_test`'s save round trip failed on CI because the game clock's minutes (510.06136363636364) came back from JSON one bit off. Clock-driven floats are now saved snapped to 1/64 of a game minute, and a test round-trips 200 awkward values through a real save.

## Session 18 — Oct 21, 2026: Weekends, holidays and the 2 PM cutoff
*(the calendar commit)*

- **Calendar** (`BankCalendar`): Day 1 is Monday 5 January 2026, and "Day N" is the Nth business day, so the HUD reads "Mon, Day 6 · 8:30 AM" on Monday 12 January. Records carry the date ("Day 6, Mon 12 Jan, 9:15 AM") and the End of Day summary opens with it.
- **Weekends and holidays**: after Friday's End of Day, "Start Day N+1" shows "Weekend — the branch is closed" with the dates, then Monday 8:30 AM. Federal Reserve holidays are skipped the same way, named ("Weekend and Birthday of Martin Luther King, Jr. — the branch is closed"); Sunday holidays are observed Monday, Saturday ones aren't moved.
- **2:00 PM cutoff**: teller transactions from 2 PM post on the next business day. The teller screen says so, the transaction records its posting day, and the End of Day summary lists them. Balances and grading don't change.
- **Regional reviews** count business days (they always counted day numbers, which are now business days). The calendar's start date is saved with the clock.

## Session 19 — Oct 21, 2026: A realistic cash model
*(the cash model commit)*

- **Denominations** (`CashDenominations`): $100, $50, $20, $10, $5 and $1 bills, and quarters, dimes, nickels and pennies, for the drawer count and the vault, laid out in two columns (bills, coins).
- **Teller float**: $3,000 instead of $50,000: 5×$100, 6×$50, 75×$20, 40×$10, 45×$5, 40×$1 and two rolls of each coin. A shift's four customers can withdraw at most $2,000, so the drawer always covers them, and a cash withdrawal larger than the drawer's cash is refused. Counting the float as it came is Perfect: the count allows for the pieces the drawer plausibly holds.
- **Vault**: $200,000 instead of $500,000, a small branch's scale.
- **Thresholds**: Minor is within $50 for a drawer (half the largest note, as $500 was half a $1,000 bill) and $500 for the vault (10×, as before). The piece tolerances (4 and 15 over the plausible count; 40 and 150 for the vault) are unchanged: they count swaps, not dollars. Customer requests ($20–$500), starting balances ($200–$2,000), staff-line requests and the ATM ($500 limit) didn't depend on the float and are unchanged.

## Session 20 — Oct 21, 2026: Three loan desks and an F2 shortcut
*(the loan desks commit)*

- **Three staffed loan desks**: the two desks either side of the Loan Desk, decor until now, are Loan Desks 2 and 3, each a ScheduleManager slot with its own staff member and background loan decisions. The player works Loan Desk 1 (its officer steps away to the break room and back); 2 and 3 work throughout. After promotion all three are staffed for good. The six starting staff fill every desk (three tellers for Teller Windows 1-3, three loan officers), so the roster and looks are unchanged.
- **Everything per desk**: the schedule screen, Branch summary, staff review, hiring vacancies and the Regional review's vacant-desk hours pick the desks up from the slots. An old save's "Loan Desk" assignment and vacancy become Loan Desk 1, and its Loan Desks 2 and 3 get the unassigned loan officers.
- **F2** (debug builds only): Loan Officer without Branch Manager (XP at least 500, Reputation at least 50). F1 is unchanged.

## Session 21 — Oct 21, 2026: Staff Scheduling fits again
*(the screen-fit commit)*

- **Staff Scheduling** broke with six desks: it was a fixed 440x560 `Panel` whose contents overflowed it (the title above the window, Close below it, the roster under the HUD, a confirmation line per desk). It's now one auto-sizing `PanelContainer` like the other screens, with a scrolling, wrapping roster, desks in two columns (teller windows, loan desks) and a one-line confirmation.
- **Fit tests that look inside**: `layout_problems()` checks every visible control of a screen against its panel, the window (with an 8 px margin) and the HUD column, not just the panel's rect. It failed on the old Staff Scheduling screen. Run on every screen that lists desks or staff, it also caught the Branch shift summary and the Hiring screen within a few pixels of the window's edge: the summary's lines are now closer together, and the interview transcript scrolls in 180 px instead of 220.

## Session 22 — Oct 21, 2026: A cover teller for the Player Teller Window
*(the cover teller commit)*

- **Cover teller**: while the player works Loan Desk 1, the teller who'd take Teller Window 3 at promotion (Nina Ortiz, or another free teller) walks from the break room to the Player Teller Window and runs its line like Windows 1 and 2. The window says who's covering instead of opening the teller screen.
- **Clock-out**: no new arrivals, waiting customers move to Teller Window 1 or 2 if there's room or leave, the customer at the window is finished, and the cover teller walks back to the break room. The window is the player's again.
- **Promotion and demotion**: a promotion at that clock-out hands the window to Teller Window 3's staff; after a demotion the cover returns. Cover work is logged and counted like other staff work; nothing new is saved (it's mid-shift state).

---

## Session 23 — Oct 21, 2026: The interview behind a switch (demo)
*(branch `demo-menu-and-saves`)*

- **Interview off for now**, by agreement, while its place in the game is redesigned. One constant, `InterviewManager.INTERVIEW_ENABLED` (false), turns it off; nothing was deleted, and setting it to true restores the old flow.
- **New game without it**: the start screen with no save shows its menu with just New Game. A new game hires the player straight away as a regular Teller, with no probation, saves, and walks into the room.
- **Being fired is game over**: the termination letter says the career has ended, and its button, "Back to Start Screen", wipes the career and opens the start screen, where New Game starts again. (With the interview on it's "Apply for a new job" into the interview, as before.)
- **Tests** cover both settings: the suite base restores the switch around every test, and interview-dependent tests set it themselves, so the suite passes whichever way it's set.

## Session 24 — Oct 21, 2026: Main menu, three save slots and a pause menu (demo)
*(branch `demo-menu-and-saves`)*

- **Main menu**: the game opens on "Play" and "Quit". Play shows three save slots: a filled one shows the role, the in-game day and date and when it was last played, and loads that career; an empty one says "New Game" and starts one; "Back" returns to the menu. There's no delete or overwrite. A damaged slot says so and offers a fresh game there, keeping the bad file beside it.
- **One file per slot** (`user://career_slot_1.json` to `_3.json`): everything saves to the slot being played, never the others. The old single save (`user://career.json`) moves into Slot 1 the first time the menu opens, if Slot 1 is empty.
- **Esc pause menu** in the room: Resume, or Back to Main Menu, which saves first when off shift. A career is never saved mid-shift, so when clocked in it asks first and warns that the shift will be lost.
- **Fired = this slot cleared**: the termination letter explains why, then "Back to Save Slots" lands on the slot screen, where that slot shows New Game; the other slots are untouched.
- **No leftovers**: the menu resets the whole career and unpauses whenever it opens, and tests check that loading or starting another slot after a full career (or mid-shift) leaves nothing behind.

## Session 25 — Oct 24, 2026: ID checks at the teller window, and two safety fixes

- **ID checks (KYC)**, presented as bank policy: every customer in the player's line carries a photo ID (name, date of birth, ID number, expiry, a portrait of their look). About 1 in 7 has a problem: expired, another name, someone else's photo, or no ID at all (rate and mix are constants in `KycPolicy`). Withdrawals and new accounts need ID; deposits don't. Check ID shows the card beside the teller panel, next to the customer's own face; Refuse Service ("I'm sorry, I can't process this without valid ID.") is on the card.
- **Grading**: valid ID checked and served, +5 as usual; bad ID refused, +5 "Good catch"; served on a bad ID, −8 Score, −3 Reputation and two mistakes (a written warning at once); ID not checked first, −3 Score and one mistake; a valid ID refused, −3 Score and −3 Reputation as the customer walks out. The shift summary counts IDs checked, bad IDs caught and checks skipped.
- **Account openers**: about 1 in 10 regular customers comes to open an account with a first deposit. The player checks ID, opens it in their name and deposits; Complete Transaction grades it all.
- **Staff windows and the ATM** don't check ID yet. A one-time hint explains the policy at the first customer who needs ID.
- **HUD hints scroll**: with every notification up, three hints (arrival, Loan Officer unlocked, opening hours) ran past the bottom of the window. The HUD test only tried one short hint. The hint text now scrolls in whatever room is left, and the test lays out every hint.
- **Save guard**: scratch screenshot scripts now name every slot from a scratch prefix, so a slot screen can't lead them to a real save; and the guard recognises a real save however its path is spelled.

## Session 26 — Oct 24, 2026: Drawer limits and cash transfers with the vault

- **Limits**: the teller drawer should hold between $1,000 and $3,350. With the $3,000 float and today's customers, a simulation puts the drawer over $3,350 at some point in about one shift in four (over $4,000, the first idea, in under 1%). Customers alone can't take it under $1,000, so "low" means too much went to the vault. Both are constants on `TellerScreen`.
- **Drawer panel** beside the teller screen: the cash, the limits, "Drawer over limit — send excess cash to the vault" or "Drawer low — get cash from the vault", and Send to Vault / Get Cash from Vault in whole dollars, with a receipt line ("Sold $1000 to the vault") and a history record. Card transactions never touch the drawer.
- **Exact to the cent**: the closing count expects float + net cash − sold + bought, and the vault's expected total (new `VaultManager`, saved with the career) moves by the same transfers, so the Branch Manager's vault count is graded against what the vault should really hold.
- **Consequences**: going over during a shift is a warning and a one-time hint; clocking out over the limit is a procedure mistake (−3 Score, one mistake toward reports). The shift summary shows transfers and any breach.
- **Tests** that served four $500 deposits now send the excess to the vault before clocking out, as a careful teller would.

## Session 27 — Oct 25, 2026: Dual control for the vault

- **No vault action with one person**: the vault door (inside the Vault room, E) is where a teller on shift sends cash to the vault or gets cash from it, and where the Branch Manager reconciles it. Either way a second staff member is called to the door, and the vault opens only once both are there ("Dual control: the vault needs two people. Waiting for [Name]…"). The teller screen keeps the drawer total, limits and warnings, and points to the vault door; the Branch Manager's hub button does the same.
- **Who comes**: an idle staff member first (a loan officer, someone in the break room, or a teller with nobody waiting), the nearest; otherwise the teller with the shortest line, after finishing their customer; never anyone already walking, nor a closed window's staff. With nobody available, "No one is free to witness the vault right now."
- **Their window waits**: the line keeps its customers, unserved, while patience keeps running, so a long visit can cost customers. They walk back and carry on afterwards.
- **Records**: receipts read "Sold $500 to the vault · witnessed by Walter Higgins", history entries name both people, and the Branch summary shows each staff member's time at the vault. A one-time hint explains dual control at the first visit.
- **Accounting** is unchanged and exact: the drawer, its closing count and the vault's expected total move by the same transfers as before.

## Session 28 — Oct 25, 2026: Cash supply, part 1 — vault levels and orders

- **Vault limits**: the vault should hold between $100,000 (about two weeks of ATM restocks plus refilling the teller drawers) and $300,000 (idle cash at risk capped at 1.5× the $200,000 start, which sits in the middle). The vault door warns "Vault low" or "Vault over limit", and a day that closes outside the limits is recorded for the Regional Manager (part 2).
- **The branch's day of cash**: at each day's close the vault takes in the staff windows' net cash (their real cash deposits and withdrawals; cards don't count), and every third business day gives $24,000 to restock the ATM (a busy branch machine pays out about $8,000 a day). The End of Day summary shows it all.
- **Cash Orders**: a new Branch Manager screen orders cash from the Federal Reserve Bank, or ships excess out, in $10,000 straps of $100 notes, one order a day, delivered at opening the next business day (weekends and holidays skipped, since day numbers count business days). It shows the vault, its limits, what's pending and a forecast for tomorrow.
- **Before promotion** an NPC branch manager orders at each close: up to the middle when tomorrow looks low, down to it when high, a strap inside each limit to allow for the staff windows' swing. A simulated month stays in range.
- Part 2 will bring the armored truck that delivers and collects the cash.

## Notes for next session

- The hiring interview is switched off (`InterviewManager.INTERVIEW_ENABLED`); decide how it fits into the game, then turn it back on.

- No `.csproj`/`.sln` yet: everything is still GDScript despite the project being configured for .NET.
- The save has one slot and no autosave mid-shift: quitting mid-shift loses that shift's work.
- The business day has opening hours and an End of Day summary (`BusinessDay`), but nothing ever closes the career's days for good: there's no week, month or year view yet.
- Loan application figures are whole-dollar floats by design (judged, never moved as cash).
