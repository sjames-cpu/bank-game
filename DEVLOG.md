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

## Session 29 — Oct 25, 2026: Cash supply, part 2 — the armored truck

- **The truck comes to the branch**: on a day with cash to deliver or collect, two guards in their own uniform (olive jacket, silver badge; new generated art) walk in at 10:30 AM, a carrier's mid-morning stop, and wait by the vault door. Deliveries come as sealed bags of up to $50,000; pickups go out the same way.
- **Before promotion** the NPC branch manager receives them. **As Branch Manager** you do, at the vault door with a witness: first the crew's ID badges against the scheduled crew (bank security policy: if anything doesn't match, refuse and call it in), then each bag on the manifest against the bag delivered (a broken seal, a seal number that doesn't match, a missing bag), then you sign. Only accepted bags reach the vault; refused ones come back the next business day. Nobody there by 11:15 AM, and the crew leaves until tomorrow.
- **About 1 in 20 crews** isn't the scheduled one, and **about 1 in 10 deliveries** has a problem bag.
- **Grading**: a visit handled right +8 Score and +1 Reputation, +3 more per problem bag caught, +10/+2 for refusing an unscheduled crew; signing for a problem bag −10/−3 (the vault comes up short); refusing a good bag −3; refusing the genuine crew −5/−1; missing the truck −3; cash handled with an unscheduled crew −20/−8 and a regional warning.
- **Regional review**: a new Cash management area (15%) covers days the vault closed out of range and how each visit was handled, rated only when there was something to judge; vault reconciliation, unreviewed errors and fairness of reports gave up 5% each.
- Walking the crew in for real caught two things the tests skipped: a guard caught on the vault doorway's corner, and a second guard placed inside the sidewalk. A test now walks them in and out.

## Session 30 — Oct 25, 2026: The Loan Officer's underwriting worksheet

- **Applications got real numbers**: each now has a monthly housing payment (rent or mortgage), time in the job, and a loan purpose that sets the bank's term, rate and policy maximum: auto 5 years at 7.0% (up to $75,000), home a 30-year fixed at 6.5% (up to $800,000; the mortgage replaces the rent), personal 3 years at 12.0% ($50,000), business 10 years at 9.0% ($250,000). The new loan's payment uses the standard amortization formula. All ten sample applicants were rewritten with consistent figures: three clearly safe, four borderline, three clearly risky.
- **The worksheet**: after "Run Credit Check", a second column shows monthly income, housing, existing debt payments, the new payment, front-end DTI (housing ÷ income), total DTI (everything, the new loan included, ÷ income; guide bands 36% healthy, 43% stretched, 50% high), the credit band, employment and the largest amount the applicant could carry at 36%. Each ratio has a one-line explanation. The verdict stays hidden.
- **The hidden risk assessment** now reads total DTI, credit score and employment (under two years counts against). The old non-housing DTI and loan-to-income bands are gone. Under the old formula three applicants were off their intended tier; now all ten match.
- **Counter-offers** show the affordable amount and are graded on the amount: for a borderline applicant, an affordable offer below the request (and not a lowball) is the right call. A risky applicant countered for more than they can carry is graded as a risky loan.
- **Denials** need one or two stated reasons (total DTI, credit score, income for the amount, employment, amount over the maximum), graded against the application's real weak points: +2 each right, −2 each wrong, −1 for each real one left out.
- Staff loan officers decide with the same skill-based odds against the new assessment, countering at the affordable amount. The Branch Manager's staff review shows the worksheet; review items in older saves still load and say they have no worksheet.
- The screen's fit test caught it running off the window with the reasons open. The fix was compact checkboxes and a wider panel that still ends 8 px short of the HUD column.

## Session 31 — Oct 25, 2026: ID checks at the staff windows

- **Same bank policy for staff**: customers at Teller Windows 1-3 now carry IDs at the same rate and mix as the player's line (about 1 in 7 with a problem), and about 1 in 10 comes to open an account, which the staff member opens. Withdrawals and new accounts need an ID check; deposits don't.
- **How staff do it, from their stats**: skipping the check comes from low reliability (1% at reliability 10, 25% at 3, 40% at 1); missing a bad card once checked comes from low skill (2% at skill 10, 20% at 5, 37% at 3, 60% at 1). Having no ID at all is never missed. Derek Voss cuts corners (skips about a quarter of checks); Nina Ortiz checks every time but misses more bad cards. Derek's overall mistake rate rises to about 27%.
- **On the floor**: the staff member asks "May I see your ID, please?" and, on a refusal, says why ("Sorry, this ID has expired."); the customer leaves unserved.
- **Staff review**: serving on a bad ID is Serious, skipping the check on a valid one Minor (it counts toward repeated minor); a correct refusal is correct work and never queued. The item shows the request, the card as shown and the customer's portrait beside the card's photo, but not what was wrong until the manager decides.
- **Branch summary and Regional review**: each teller's line adds IDs checked, caught, skipped and missed (refused customers aren't counted as served), and ID slips count in the Regional staff mistake rate. The shift summary pairs Score with XP to make room.
- **Hiring** needed nothing new: a weak teller candidate's weakness is reliability, so they skip checks, and red-flag answers only come from reliability 2 or lower.

## Session 32 — Oct 25, 2026: Onboarding

- **Every new career starts with onboarding**, presented as bank policy: after the interview's hire with the interview on, and at career start with it off. First a letter saying the background check has cleared, then the employment contract (the Teller role, hours, probation terms if hired on probation, what leads to a report and to dismissal) with an "I agree" button.
- **Compliance training**: four short lessons, each with a two-question quiz that must be passed: ID checks before withdrawals and new accounts; the $3,350 drawer limit and sending the excess to the vault; dual control (you and one witness); customer privacy and handling complaints calmly. Every figure comes from the rules the game grades with, and a test checks each right answer against them. A wrong answer is explained and cleared, retries are unlimited, and the answers are shuffled every time a question is shown, so the right one isn't always in the same place. Finishing the training gives 50 XP, about one correctly served customer.
- **Saved step by step**, so quitting mid-onboarding resumes where it left off; a new game or career reset starts it over, and older saves count it as done. The arrival hints wait until it's over.
- **Fewer repeated hints**: the vault door hint is retired, and the ID and drawer hints now just point at where to act, since the training explains the policy.
- F1 and F2 (debug builds) skip onboarding, then do what they always do.

## Session 33 — Nov 4, 2026: Generated loan applicants (Loan Officer improvements, part 1 of 3)

- **Applicants are generated** instead of cycling through the ten samples, so they don't repeat and the answers can't be learnt. Each gets a tier first (aiming for 40% low, 35% medium, 25% high risk), then a profile saying what makes it risky: fair or poor credit, a stretched DTI from the new loan or from today's debts, a short time in the job, a payment too big for the income, or an amount over the policy maximum. The figures are built to land there and checked with the real worksheet formula. About a third put one factor just inside a band edge. Measured over 1,000: 38.4% low, 37.1% medium, 24.5% high; among medium and high, total DTI is a weak point for 52%, credit 52%, income 40%, employment 20%, amount 7%, in 11 combinations. Tests confirmed by breaking them on purpose: skewing the tier weights fails the mix test, and letting the look shift the credit score fails both fair-lending tests.
- **Nothing worth offering**: under the old grading, a medium-risk applicant whose worksheet leaves nothing affordable couldn't be graded "Correct" by any decision (a counter-offer had to be affordable). The samples never hit this; generated ones do. Now, when a borderline applicant can afford less than a quarter of their request, Reject is the correct call and a counter-offer of any amount only reasonable; the right reason is "Total DTI too high", or "Income too low for the amount" when the loan is what's too big. Staff officers and the Branch Manager's Approvals grade it the same way. About a quarter of generated medium applicants (99 of 371) are like this, mostly those stretched by their debts.
- **Fair lending**: names and portraits come from a separate generator, after the finances, and nothing graded reads them. No age, sex, race, religion, national origin, marital status or the like is generated or stored. Tests check the finances don't change with the name, the tier mix is the same for every look and group of names, and grading ignores both.
- **The first Loan Officer shift** of a career is three teaching cases from the samples, clear to borderline: Maria Chen (approve), Marcus Webb (reject), Angela Reyes (counter-offer). The review screen now shows the applicant's portrait.
- **Staff loan desks** decide generated applicants too, and no name repeats within a business day.
- **Saved**: the career's seed, the player's pile (the pending application and the queued ones) and today's names, so a loaded career shows the same applicants it would have.

## Session 34 — Nov 4, 2026: Walk-in applicants and document checks (Loan Officer improvements, part 2 of 3)

- **Walk-ins**: loan applicants now walk in through the entrance to their loan desk, sit down, say what the loan is for ("I'm hoping to finance a car."), and leave after the decision pleased, disappointed, or thinking over a counter-offer. The staff desks get walk-ins too, served in the background. Each desk has its own seat and its own row to walk along, applicants come in up one lane of the entrance corridor and leave down the other, and only one walks up the corridor at a time. Opening the review before the applicant reaches the desk seats them at once, so the walk never holds the player up.
- **Documents**: each applicant hands over a photo ID (bad at the teller window's rate, 1 in 7, with no date of birth on it), a pay stub with this month's gross and net pay, and last month's bank statement with two payroll deposits. 10% have another problem: the income on the form is more than the stub and statement show (4%), the pay stub is in someone else's name (2%), or the pay stub or statement is missing (2% each). About 23% of applicants don't check out. Whether they do never depends on the name, look or finances.
- **Verify Documents**: a new button beside Run Credit Check shows the documents in the right-hand column, with today's date and the bank's policy, against the stated income on the form. If something doesn't check out, the right call is to reject for a new reason, "Income or identity could not be verified".
- **Grading**: catching a problem is a correct call (+12 with the reason). Approving or counter-offering on documents that don't check out is as bad as approving a high-risk loan (−10, −2 Reputation). Deciding without verifying costs 3 Score even when the documents were fine. Turning away a good applicant as unverifiable costs 3 Score and 2 Reputation on top of the decision's own grade.
- **Staff officers** check documents too and miss a problem the way a staff teller misses a bad ID, by skill: 2% at skill 10, 60% at skill 1. Every miss goes to the Branch Manager's staff review, which now shows the documents as handed over: Serious when they lent on documents that didn't check out, Minor when they rejected the loan anyway.
- The tallest review screen (six reasons) ran under the bottom-left controls line, so the checks moved to the top of the right-hand column, the terms line was shortened and the reasons got a slightly smaller font. A new test keeps the loan screens clear of the controls line.

## Session 35 — Nov 4, 2026: Loan outcomes over time (Loan Officer improvements, part 3 of 3)

- **A loan book**: every loan the player or a staff officer approves or counter-offers is booked with its borrower, amount, risk, whether the documents checked out, and who made it.
- **Outcomes over 20 business days**: each loan is paid on time, runs 15 days late and then catches up, or runs 30 days late and defaults. The odds depend only on the risk and the documents: low risk 90/8/2% (on time / late / default), medium 77/15/8%, high 45/25/30%, and 30/20/50% on documents that didn't check out, whatever the risk. A default writes off part of the loan: a quarter of a mortgage, 40% of a car loan, 60% of a business loan, 75% of a personal loan. The End of Day summary lists the day's notable events ("Maria Chen's auto loan: payment 15 days late"): your own loans, and every loan for a Branch Manager.
- **Lost business**: good applicants (low risk, documents fine) who are turned away are counted, with the amount they asked for.
- **Loan Portfolio Report**: every 20 business days a letter from the Credit Risk Department covers a Loan Officer's own loans, or the whole branch's for a Branch Manager. It lists loans made, paid on time, late, defaulted, losses and good applicants turned away, with comments on being too lenient or too strict. The lending quality is the average of three parts (defaults, losses, and good applicants turned away), but never more than 10 points above the weakest of them, so being too lenient and being too strict both land in Poor: approving everything rates 35 and rejecting everything 0, while a careful lender rates 100 and a mostly sensible one with a few mistakes about 77 (Sound). Strong earns +10 Score and +2 Reputation, Sound +3, Weak −3 and −1, Poor −8 and −3.
- **Regional review**: a new Lending quality area (weight 10) uses the same rating on the branch's loans; vault reconciliation and fairness of reports went from 20 to 15 each.
- The End of Day summary got wider, and its text now scrolls when a busy day would run it off the window. A test found the busiest summary was already too tall.

## Session 36 — Nov 11, 2026: Credit reports and risk-based pricing (Loan Officer improvements, part 4a)

- **A credit report for every applicant**, at the player's desk and the staff desks: the on-time payment rate, 30-, 60- and 90-day late payments in the last 2 years, credit utilization, open accounts, hard inquiries in the last 6 months, and serious marks (collections, or a bankruptcy, in the last 7 years). Reports follow the score: over 2,000 applicants, utilization averages 6% at 800+ and 49% under 580, the on-time rate 99.5% down to 82.4%, and serious marks appear for none of those at 740+ but 66% of those under 580. Each report also tells its own story (a normal history, a clean recent one, maxed-out cards, a recent serious mark), so similar scores can read very differently.
- **The report counts in the hidden assessment** (bank policy): a 90-day late payment, a collection or a bankruptcy in the last 2 years adds 2 risk points, utilization over 75% adds 1, and a score under 670 with a clean last 2 years takes 1 away. The tier mix stays 40.8/34.7/24.5%, and the report changes the tier the score alone would give for 13.4% of applicants: 8.6% riskier (a good score hiding a recent collection), 4.9% safer (a fair score with a clean recent history). Loan outcomes still depend only on the tier.
- **Shown on the review screen**: Run Credit Check now also pulls the report into a third column beside the worksheet, each item with a one-line explanation and the policy below. The screen is wider, sits at the top of the window, and has Close beside the title, so its tallest state still fits.
- **Risk-based pricing**: one rate per purpose became a table by purpose and credit band: auto 5.50-14.50%, home 6.25-8.25%, personal 9.50-26.00%, business 7.75-13.00%, with the old rates as the Good column. The worksheet shows the rate offered and why, and the new payment, DTI and affordable amount use it. Several sample figures moved; Sophie Laurent now asks for $18,000 so she stays weak on credit alone.
- **A new denial reason**, "Recent late payments or collections", graded like the others: right when the report has a serious mark in the last 2 years.
- **Staff officers and staff review** use the same report and pricing; review items now show the report. The staff review panel got wider and its details a size smaller, since the busiest item ran off the window.
- **Fair lending**: the report comes from the applicant's finances and score, and the rate from the purpose and score; tests check neither depends on the name or look. Reports save with each application; an application saved before reports gets one in line with its score that doesn't change its call.

## Session 37 — Nov 11, 2026: Collateral, down payments and loan-to-value (Loan Officer improvements, part 4b)

- **Collateral**: home loans have a purchase price and the bank's appraisal (about 1 in 8 appraise under the price: 13% of 457 generated home loans); auto loans the vehicle's price; business loans equipment or property, or nothing; personal loans stay unsecured. The down payment is the price minus the loan.
- **Loan-to-value** is the loan ÷ the lower of price and appraisal (or the vehicle's or collateral's value), and counts in the hidden assessment (bank policy): home up to 80% healthy, up to 95% stretched (+1), over 95% high (+3); auto up to 100%, 120%, then high; business collateral up to 75%, 100%, then high. A high LTV is the new denial reason "Down payment too small for the value". The tier mix stays 39.5/36.0/24.5%, and the LTV makes the tier riskier for 7.8% of applicants. An appraisal under the price can push a buyer into the high band even when the down payment looks fine.
- **Mortgage insurance**: home loans over 80% LTV pay 0.30-1.00% of the loan a year depending on LTV, in the monthly payment, so in the DTI and the amount affordable. About a third of home loans pay it.
- **Counter-offers** show the down payment the amount means ("A $300,000 loan means a $80,000 down payment (21.1%).") and, when the LTV is over the healthy band, the target ("Healthy LTV needs a loan of $284,000 or less."). When the LTV is a weak point, a counter-offer is only correct if it brings the LTV into the healthy band as well as being affordable; staff officers counter at that amount.
- **Loss on default** now depends on the collateral: what selling it doesn't recover (a home 75% of its value, a car 60%, equipment 50%, business property 70%), never under 10%. A home at 80% LTV loses 10%, at 95% 21%; a car at 100% 40%, at 125% 52%; unsecured loans 75%. Default odds still go by risk. The portfolio report lists secured loans and their average LTV.
- **Review screen**: rather than shrink the text, the worksheet column now has two tabs, Payments and Collateral; the credit score moved to the credit report column, and the form shows the purchase price, vehicle price or collateral offered. Staff review items show the collateral, and their Terminate buttons sit side by side so the busiest item still fits.
- **Fair lending**: collateral comes from the applicant's finances only; tests check it, the LTV and the insurance never change with the name or look. Collateral saves with each application and each booked loan; older saves get a healthy LTV that doesn't change any call, and older booked loans keep their old loss shares.

## Session 38 — Nov 18, 2026: Art visibility pass, stage 1 (world-space effects)

- **Characters stand out**: every character (player, customers, staff, applicants, guards, the Regional Manager) has a soft ground shadow and a thin dark outline. The outline is the sprite's frame stamped one pixel around it, not a shader, because the sheets' art touches the frame edges and a shader would clip or pick up the next frame; the sheets and the art check are untouched. A new character class must call `CharacterFx.attach()`.
- **What E does is obvious**: the interactable the player stands at gets a gentle pulsing gold outline, only when its "E — ..." prompt is showing, so locked, staffed, covered and waiting desks get none.
- **Attention markers**: small pixel icons (generated by the art script, so the art check covers them) float over the player's teller window (a customer is waiting), the vault door (the armored truck is waiting for the manager, or the drawer is over its limit), the player's loan desk (an applicant is seated) and the Branch Manager desk (staff reviews are waiting). They stay 16 screen pixels wide at either zoom.
- **Zones**: a faint floor tint for the vault, manager's office, loans and tellers, with a small sign for each in the crisp world text.
- **Feedback numbers**: "+5 Score", "-2 Reputation" and "+50 XP" rise from the player and fade in about a second (green for gains, red for losses); changes that arrive together share one cluster, and they keep running while a desk screen has the game paused.
- **1x overview** hides the highlights and the feedback numbers and keeps the markers and signs.
- Nothing allocates per frame, hidden effects don't process, and `world_visuals_test.gd` checks that no node is left behind after a busy day. The y-sort test now skips the marker icons, which are overlays. No screen changed size.
- Built on the `shared/art-visibility` branch (it edits `teller_room.gd`, a shared file); before/after screenshots are in `scratch/viz_shots/` (not committed).
- **Merged with the time-slots main** (6c67e7f): no textual conflicts. The tests moved to `start_regional_visit` via `regional_visit().start_visit()`, the truck arrives with `arrive_now()` (what the 9 AM slot calls), the loan seats are emptied through `room.loan_seats`, and the loan marker test clocks in through a real work slot. The doormat no longer glows on slot days (E there only explains). New tests cover the teller marker in a work slot, effects staying outside every CanvasLayer, highlights hiding under the transition card, and the overview on a slot day.

## Notes for next session

- The hiring interview is switched off (`InterviewManager.INTERVIEW_ENABLED`); decide how it fits into the game, then turn it back on.

- No `.csproj`/`.sln` yet: everything is still GDScript despite the project being configured for .NET.
- The save has one slot and no autosave mid-shift: quitting mid-shift loses that shift's work.
- The business day has opening hours and an End of Day summary (`BusinessDay`), but nothing ever closes the career's days for good: there's no week, month or year view yet.
- Loan application figures are whole-dollar floats by design (judged, never moved as cash).

## Session 39 � Nov 18, 2026: The black figure beside the player (`shared/art-shadow-fix`)

A black, body-shaped figure the player's size appeared beside them when they walked left (at 2x it sat under the HUD's notification box while standing still, which is why the first look missed it). Cause: `CharacterOutline` drew its four dark copies with a negative-width rectangle when the sprite was mirrored, and Godot anchors such a rectangle at its left edge, so the copy landed one frame width to the right. Fixed by drawing positive rectangles and mirroring with a transform about the frame's centre. The outline now also redraws from the sprite's own signals (it used to lag a frame), and a character whose art is missing shows a magenta warning box. `character_fx_look_test.gd` measures what is drawn across every character type, facing, mirror and frame at both zooms. Before/after screenshots: `scratch/shadow_shots/` (ignored).

## Session 40 � Nov 18, 2026: Art animation, stage 2a (world-space motion) (`shared/art-animation`)

Code-driven only (no new frames, sheets or animation names). Characters breathe (a 1 px step every 1.2 s, a different phase each), dip for 0.1 s when they stop, and staff serving someone step faster; the sprite and its outline move together by whole art pixels and the ground shadow never moves. `CharacterMotionDriver.advance()` steps them all from one clock (no autoload, no tween per character). The impatience bubble and speech lines pop in (2 px over 0.15 s, whole-pixel steps) and the bubble pulses on a stage change. The Z zoom eases over 0.25 s with hard limits so the room clamp holds the whole way. The ATM and the vault door glow softly while in use. "Effects: On / Off" in the pause menu (its own settings file, never a career save, same save guard; default On) turns all of it off; the shared test base runs with it Off. Tests measure what is drawn (`character_motion_test.gd`, `world_motion_test.gd`, `effects_setting_test.gd`); breaking the outline sync, the shadow or the whole-pixel rule each fails them. Frame strips and before/after pictures: `scratch/motion_shots/` (ignored). Interface motion (letters, the transition card, HUD counters) is stage 2b, not started.



## Session 41 - Nov 19, 2026: Art animation, stage 2b (interface motion) (`shared/art-ui-motion`)

Code-driven only; no art, layout, content, gameplay, scoring or save changes, and no role-owned file touched (a test checks the branch's file list).
- **One shared driver** (`UiMotionDriver`, added to the UI layer by `teller_room.gd`) watches the whole room, so every screen, letter, lesson, summary, review, the pause menu and the slot card fades in (0.15 s) with an 8 px whole-pixel slide and fades out (0.1 s) as a ghost; the hint card fades only. Buttons brighten on hover and sit a pixel lower while pressed. The HUD's Score, Reputation and XP count with a green/red flash and the slot line crossfades.
- **Lesson learned**: the first version slid each panel, but a panel re-centres itself when its content is filled in, which swallowed the slide and left it 8 px off at the end. It now slides the full-window root, which no layout resizes, and compensates the backdrop.
- **Found, not fixed (not ours)**: a letter's scrolling body fits itself one pixel taller or shorter on every other open, with Effects Off too. The new test compares at the same point in that cycle.
- Checked by ending the slide 1 px off: seven tests failed; restored. Screenshots in `scratch/ui_motion_shots/` (not committed): the widest screens are pixel-identical with and without motion.


## Session 42 - Nov 20, 2026: Multi-day loan applications, part 1 of 4: data and rules (`loan/multi-day-applications`)

No screens and nothing a player can see; Loan files only (nothing shared). The Loan Officer will be able to ask an applicant for more documents; the application waits in a pipeline of open files and comes back later.
- **New** (`scripts/roles/loan/`): `LoanPipeline` (the open files and the rules: at most 3 open, 2 requests per file, a further request only once the applicant is back), `LoanFile` (one file: what was asked, the due day, and how and when the applicant answers) and `LoanRequirements` (the checklist: pay stub, bank statement, valid photo ID, appraisal, proof of down payment, a letter explaining a late payment or collection; which an application is truly missing; due days). Numbers in `LoanConfig`. `LoanRole` holds the pipeline and saves it in its own section (key `file_pipeline`, written only once a file has existed, so other saves are unchanged and an old save loads an empty pipeline). `LoanDeskManager.names_taken()` counts applicants in open files.
- **Deterministic**: a file's return (on time 70%, late 20%, never 10%; complete 75%, incomplete 20%, wrong 5%) is rolled once from the career seed, the file number and the request number, never the applicant's finances, name or look, and never the global generator, so reloading can't re-roll it. A return is a pure function of the day number (`GameClock.day`, business days), so no daily tick. The appraisal, down payment and letter come from a new stream, so no existing applicant shifts.
- **Lesson learned**: the tests passed but `run_tests.sh` failed on its warnings step (a shadowed member, an unsafe `int()` on a Variant, untyped loops and casts, all in the new files): a green test count is not a green script.
- Tests: `loan_pipeline_test.gd` (34): save and load, an old save, determinism, measured rates, independence, due days across a weekend and a holiday, expiry, the caps, names. Parts 2 to 4 (the request on the review screen and its grading, returned applicants and the Loan Officer screen, promotion and edge cases) are not started.


## Session 43 - Nov 20, 2026: Multi-day loan applications, part 2 of 4: the request on the review screen (`loan/multi-day-applications`)

Loan files only (nothing shared). A "Request More Documents" action beside Approve, Reject and Counter-Offer: after Verify Documents (no credit check needed) the Loan Officer ticks which of up to six documents are missing (pay stub, bank statement, valid photo ID, appraisal, proof of down payment, a letter explaining a late payment or collection; only those that apply to the loan and credit report are listed) and sends the file into the pipeline from part 1.
- **Not a decision**: `decision` stays NONE, no history record is written (Approvals never sees it) and nothing is booked. It leaves the pile (a new applicant joins, so it stays at 3), counts as the slot's one application through `decision_graded` (the slot ends exactly as before and the HUD and card strings are unchanged) and the applicant leaves through the existing flow with a line of their own. Off, with a one-line reason, before the documents are verified, with 3 files open, when this file has asked twice or the applicant is still out; hidden on the first shift's three teaching cases with a line saying why. A request refused at the last moment says so on the screen.
- **Grading** (numbers in `LoanConfig`): exactly the right checklist +3; each wrong tick or missed item -1; a file with nothing missing -2; a forged or wrong document -3 (best answer there stays Reject naming "could not be verified"). For documents that are simply missing (no stub or statement, no or an expired ID) a request is now the best call and a rejection, even naming the reason, is only partial credit (+5, was +12); approving or countering them is still the serious mistake. Per slot: deciding a good file at once is 10; a request then its decision is (3+10)/2 = 6.5, or 4 if nothing was missing; so asking never beats deciding.
- **Screen**: the checklist takes the decisions' place (like the denial reasons), the button and its note sit in a row under them; no text was shrunk. In a real window the tallest states (the six-item checklist and the eight denial reasons) are both 586 px tall, 2 px above the controls line.
- **Lesson learned**: the headless fit tests lay the review screen out about 41 px shorter than a real window does (543 and 545 px against 586), so they pass with 43 px to spare where the real screen has 2. The tallest-state test measures and prints the headless numbers; the real clearance was measured in a window with a scratch script.
- Tests: `loan_request_test.gd` (32); one existing expectation changed (`loan_documents_test.gd`: the missing-document kinds are no longer "caught"), and the every-applicant fit test now opens the checklist. Parts 3 and 4 (the returning flow, a returned file withdrawn if undecided after 3 business days, promotion and edge cases) are not started.


## Session 44 - Nov 20, 2026: Multi-day loan applications, part 3 of 4: the returning flow (`loan/multi-day-applications`)

Loan files only (nothing shared). A file whose applicant has come back with documents takes the desk before the pile (the one back longest first; the pile stays at 3) and is the slot's one application. What came back is put on the application itself (`LoanReturn`, once per request, from the career seed and the file number): the requested items present and the problem cleared (the loan then books with its documents fine), one item still missing (incomplete), or a document that doesn't match (wrong: a forged-type problem, best rejected as unverifiable). Appraisal, proof of down payment and the explanation letter have no place on the form, so a new `DocProblem.PAPER_MISMATCH` and two fields hold them, and Verify Documents lists them in one short line each. Verify Documents is needed again. The applicant walks in as themselves and says what they brought (lines for on time, incomplete and late).
- **Withdrawal**: a returned file not decided within 3 Loan Officer days of coming back is withdrawn at the start of the next work day (Opening), costing -2 Score and -1 Reputation (and the XP a Score point is worth), none if decided first. The clock counts only days whose recorded role was Loan Officer: a Teller day, any other role's day or a day with no role does not count, so the file waits. The role of each day is noted as its slots start (`LoanRole.role_days`, kept only while a file is open and saved only then). It is a pure function of the day numbers and those roles, applied once (the file is removed in the same step): "Start Day N+1" saves before Opening, so quitting mid-day replays Opening from the saved state and charges it once, going home early skips work slots and not Opening, and a save made after Opening has no file left to charge. A Branch Manager is never charged. A withdrawal never takes Reputation to 0 (that would write a report at Opening, before the day's role is chosen). Files that never come back still expire quietly, 3 business days after their due day.
- **Waiting list** on the Loan Officer screen (not the review screen, whose tallest states leave 2 px above the controls line in a real window and are unchanged): who, what loan, what was asked for, and the due day, or for a returned file the day to decide it by if every day from now is a Loan Officer day; nothing about whether or how well a file will come back. End of Day: lines for files back, files withdrawn (with their cost) and files that never came back, ahead of the loan events.
- **Lessons learned**: the first full run failed on a guard test that lists every stored `LoanApplication` field (the new fields had to be added); papers first wrapped onto six lines and made the review panel 642 px tall, so each is one short line and they take the policy paragraph's place; a test day's Opening never ends until someone clocks in; and the headless fit tests are not the real window, so every changed screen was measured in a window with a scratch script (review screen tallest states 586 px, 2 px above the controls line, unchanged; waiting list 517 px; End of Day 456 px).
- Tests: `loan_return_test.gd` (47). Part 4 (promotion and demotion: open files withdrawn quietly at promotion, the first-shift and edge cases) is not started.


## Session 45 - Nov 20, 2026: Multi-day loan applications, part 4 of 4: edge cases and a full check (`loan/multi-day-applications`)

Loan files only, plus a docs-only paragraph in `CLAUDE.md`. The edge cases of the whole feature:
- **Promotion**: becoming Branch Manager closes every open file (waiting or returned) quietly: no penalty, no history record (so nothing in Approvals), no booking, the waiting list goes with the desk, and that day's End of Day says "Open loan files were passed to your staff". `LoanRole` hears `XPManager.branch_manager_unlocked`, so no shared file changed; after it nothing from the pipeline runs (a file left over from a save is passed to the staff at Opening, never penalised). **Demotion** (`branch_manager_demoted`) starts clean: no file or role day can come back, and the withdrawal clock starts from the days since.
- **Abandoned files**: a returned file still undecided 15 business days after its return day (`LoanConfig.ABANDONED_AFTER_DAYS`) is closed quietly at Opening whatever role the player has, with an End of Day line; the 3 Loan Officer day penalty still comes first (a file that used its days is withdrawn with the penalty, a file parked by a Teller-only player goes quietly).
- **Saves**: the appraisal, proof of down payment and letter papers moved from `LoanApplication` onto `LoanFile` (they exist only while a file waits, and the file saves them), so a career that never requests a file saves exactly what it did on main: a test compares its saved role, pile and loan book sections with `tests/data/loan/loan_sections_on_main.json`, a file made by running the same steps on main (1b24fa3). Every old save fixture loads with an empty pipeline and no role days.
- **Confirmed and tested**: the three teaching cases never show the request button; a request made before going home early is in the End of Day save; going home early skips the work slot without losing a returned file; every request and every returned decision uses exactly one slot application (strings unchanged). Demo helpers: F2 and F3 leave a pending file alone and F1 promotes (so passes the files to the staff); the Loan debug keys F9 and F10 are still reserved and do nothing, and none were added.
- **Lesson learned**: `LoanApplication`'s new fields were exported, so every saved application, with or without a file, gained two keys; making them plain variables then broke a guard test that wants every variable saved, so they moved onto the file. Only a comparison with what main really saved could show the first problem.
- Tests: `loan_edge_test.gd` (19), and the suite total is the sum of the four parts: `loan_pipeline_test` 34, `loan_request_test` 32, `loan_return_test` 47, `loan_edge_test` 19. The feature is complete; nothing merged into main yet.


## Session 46 - Nov 25, 2026: The closing step, part 1 of 4: rules and saves (`loan/closing-step`)

No screens and nothing a player can see; Loan files only, no shared file (one loop added to `LoanDeskManager.names_taken()`, which is James's). An approved loan (or accepted counter-offer) will wait for a closing day before it is booked; this part is the data and the rules.
- **New** (`scripts/roles/loan/`): `LoanClosing` (one closing: the application, the approved amount, rate, term and payment frozen, the approval and due days, its number, the reserved loan id (only stored), the problem and what the paperwork shows) and `LoanClosings` (the list, held by `LoanRole` next to the pipeline, not counted against `PIPELINE_MAX`). Numbers in `LoanConfig`, `CLOSINGS_ENABLED` false (nothing reads it yet). Due 1 business day after approval for auto and personal, 2 for business, 3 for home.
- **The problem**: 1 in 7 closings (the career's first is always clean): terms that don't match the approval 30% (one figure wrong: amount, rate, term or payment; an accepted counter-offer's wrong figure is the amount first asked for), an expired photo ID 25%, a missing signature 25%, a new debt 20% (a payment that takes total DTI to 44-50%, always over the 43% band, whatever the applicant's DTI was). Rolled once, from the career seed and the closing number only, never the global generator, so a reload can't re-roll it; independent of name, look, finances and decision type (only the size of a new debt and a counter-offer's wrong figure read the application, because they mean nothing otherwise).
- **Time** (pure functions of day numbers): due from its due day; lapses at Opening once 3 Loan Officer days have passed after the due day (the withdrawal's -2 Score and Reputation cost, once: the closing is removed in the same step, so going home early and a reload can't charge it twice); a closing still open 15 business days after its due day is closed quietly at Opening whatever role the player chose (no penalty, no booking, not "turned away", name released), only after the lapse had its turn. `LoanRole` keeps role days from the oldest due day while a closing is open, saves the closings under `"closings"` only once one has existed (a career that never closes saves exactly what main saved: the `loan_edge_test` comparison is unchanged), and a demotion starts clean. `LoanClosings.promotion_plan()` says what staff would do at promotion (stop problem closings, fund clean ones) and applies nothing; part 2 applies it.
- **Reputation floor changed (shared helper)**: a withdrawn file or a lapsed closing now never adds Reputation and never takes it to 0: it costs nothing at Reputation 0 or 1 and 1 at 2 or more. The old floor (`maxi(-1, 1 - reputation)`) gave **+1 at Reputation 0**. No existing expectation changed (none covered Reputation 0); `test_a_withdrawal_never_adds_reputation` was added.
- **Lessons learned**: the first full run failed the warnings step, three times over (shadowed members, untyped loops, unsafe casts, `int()` of a Variant), after the suite itself passed; a rate made by `0.07 - 0.01` is not the double of `0.06` and came back one bit off through the save file, so rates are rounded to the basis point.
- Tests: `loan_closing_test.gd` (36), plus one in `loan_return_test.gd` (48). Parts 2 to 4 (funding and stopping, the desk and the closing screen, polish and switching it on) are not started.


## Session 47 - Nov 25, 2026: The closing step, part 2 of 4: booking integration (`loan/closing-step`)

Loan files only, no shared file. Behind a switch (`LoanConfig.closings_enabled`, now a static variable, off by default and reset after every loan test) the player's approval or accepted counter-offer no longer books the loan: it reserves a loan number, opens a closing and books at funding. With the switch off nothing changes; the first shift's three teaching cases and the staff always book at once.
- **Booking** (`LoanBookManager`): `note_decision(..., book_now := true)`; `fund(closing)` books under the reserved number with the funding day as `made_day`, the tier, documents and collateral frozen on the closing (four new `LoanClosing` fields, saved only when closings exist: no `BookedLoan` field and no new `loan_book` or `loan_desk` keys, so the byte-for-byte comparison with main still passes), and the unverified odds when a problem went through. Funding order never changes an outcome (the outcome reads only the career seed and the reserved number). `stop(closing)` never books.
- **Points** (`LoanConfig`): fund a clean closing +5 Score; stop a problem closing +8 Score and +1 Reputation; stop a clean one -3 Score (and a good applicant lost that way counts as turned away); fund a problem closing -10 Score and -2 Reputation. At 1 problem in 7: careful play +5.43 per closing, blind funding +2.86, stopping everything -1.43; approve then close is 7.7 a slot against 10 for a correct reject. A lapsed good applicant counts as turned away; the quiet expiry counts nothing.
- **History**: a funded or stopped closing is a record-only entry (`reviewed`), like the portfolio report's, so Approvals offers no override. **Promotion**: the staff stop problem closings and fund clean ones (booked normally, the promotion day), with no Score, Reputation, XP or history; a closing left over at a Branch Manager's Opening goes the same way.
- **End of Day**: lines for closings funded, stopped, lapsed (with their cost), closed quietly, and passed to staff, saved with the closings log; the portfolio report now says defaults were on documents "unverified or mismatched". Measured in a real window: an ordinary day's summary is 556 px high (45 px clear below), the busiest possible one fills the window with its 16 px margins and scrolls (697 px of text in 507 px).
- **Changed expectations**: the switch test (a variable now); a Branch Manager's leftover closing is passed to staff instead of staying open; the promotion plan test no longer applies it (the new tests do); the report's wording in `loan_book_test`.
- **Lesson learned**: two closings can't be a lapse and a quiet expiry on the same day (an older one always has at least as many Loan Officer days after its due day), so one test of both lines needs two days.
- Tests: `loan_closing_booking_test.gd` (27). Parts 3 and 4 (the desk and the closing screen, polish and switching it on) are not started.


## Session 48 - Nov 25, 2026: The closing step, part 3 of 4: the desk (`loan/closing-step`)

Loan files only, no shared file (`teller_room.gd`, `SlotWiring` and `loan_review_screen.tscn` untouched: the closing panel is built in code). Behind `LoanConfig.closings_enabled` (still off by default; part 4 flips it); with it off nothing changes.
- **Desk order** (`LoanDeskManager.current_player_application()`): a due closing first (the one due longest first), then a returned file, then the pile. A closing is the slot's one application through the existing `decision_graded` signal, so the slot adapter and the HUD and card strings are unchanged; it never counts against the three open files, and the pile stays at three.
- **Closing mode** (`scripts/roles/loan/loan_closing_panel.gd`, `LoanClosingPanel`, shown by the review screen in place of the three columns): the terms as approved on the left (frozen on the closing); after "Run closing check" the paperwork on the right: amount, rate, term and payment as written, the photo ID's expiry beside today's date, signed or not, and the monthly debt payments at approval beside those now with the total DTI of each (both lines always, so nothing says which closings have a problem). Nothing is highlighted, flagged or marked: a test checks every problem type has the same screen shape once dates, numbers and the signature value are masked. "Fund the loan" waits for the check ("Run the closing check first."); "Stop the closing" is always there. A closing that isn't due, or has vanished, shows "Closing not completed: ..." and changes nothing. The feedback after Fund or Stop (the part 2 points) names what was right or missed using only what the paperwork showed. The first closing (number 1) has a short explanation in the panel (no hint, no save key).
- **Applicant** (`LoanApplicantNPC`): new lines on sitting down for the closing, pleased after Fund and confused after Stop (`LoanClosings.outcome_for()`, kept in memory only); same name and look as anyone's, nothing reads either.
- **Measured** (a real window, 1152x648, the same scratch script as Session 44): the tallest closing state (the first closing, feedback after Fund) is 544 px, 44 px above the controls line and 8 px left of the HUD column; the old tallest states are 518 px (six-item checklist) and 546 px (eight denial reasons), 42 px clear, and 546 px with the closing panel taken out of the screen altogether, so the panel adds nothing to the old states.
- **Discrepancy**: Sessions 43 and 44 recorded those two old states as 586 px in a real window against 543 and 545 headless (2 px above the controls line). The same script, run again on this machine today, gives 518 and 546 in a real window, so the 41 px gap between a real window and the headless tests, and the 586, are not reproduced here; the closing panel is no taller than the old tallest state in either case, but whatever made the 586 (another machine's fonts or display scaling) is not known. Measure on that machine if the margin matters.
- **Lessons learned**: the review screen is a child of the Loan Officer screen, so it is only laid out while that is open: showing it directly leaves a stale layout (a 902 px panel in tests and a 911 px one in a window) that is not a layout bug; open it through the desk, as the player does. A wrapping label needs a minimum width of its own or it wraps at one character and leaves the panel thousands of pixels tall. The Session 44 scratch script no longer ran after Part 4 (a fourth file request is refused), so its fourth file is built by hand.
- Tests: `loan_closing_desk_test.gd` (22). Part 4 (the Loan Officer screen's waiting list, polish, switching it on) is not started.
