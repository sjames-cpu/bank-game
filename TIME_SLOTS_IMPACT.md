# Time Slots — Impact Check (read-only)

**Inspected:** branch `main`, commit `574d0150` ("Add collateral, down payments and loan-to-value to loan applications", 11 Nov 2026), after `git pull` (already up to date). No code was changed; this file is the only thing created, and it is not committed.

**Glossary used below**
- **Game clock**: the in-game time of day shown on the HUD ("Wed, Day 3 · 10:42 AM").
- **Unpaused seconds**: real seconds that pass while no screen or letter is open. This is a *second, separate* kind of time, and it matters a lot (see the summary).
- **Slot**: one block of the new day (Opening, 9 AM, 11 AM, 1 PM, 3 PM, Closing).
- **Adapter**: a small piece of glue code that lets an existing role work with the new slots without being redesigned.
- **Signal**: Godot's way for one piece of code to announce "this just happened" so others can react, without knowing who is listening.

---

## 1. Summary

- **Two scripts own the time today.** `GameClock` (the day number and time of day) and `BusinessDay` (opening hours, the 2 PM cutoff, going home and the day's totals). Both are autoloads, which means they're always running and every part of the game can read them.
- **The game actually has two clocks, and this is the most important finding.** The HUD clock moves 1.5 game minutes per unpaused second. But customers arriving, customer patience, staff serving customers and staff deciding loans **don't read that clock at all**: they count real unpaused seconds on their own. So stopping the HUD clock won't stop them. The slot system has to control both.
- **Most of the game only needs the day number, not the minute.** The calendar, weekends, holidays, the vault's daily close, the loan book, the 20-day portfolio report and the Regional review every 5 business days all count whole business days. They need **no change**, provided End of Day still happens once per day.
- **The minute-by-minute users are a short list:** customer arrivals (teller and staff windows), opening at 9:00, "too late to clock in" at 4:30 PM, closing at 5 PM, the 2 PM cutoff, the armored truck (10:30 AM plus a 45-minute wait), the Regional Manager's visit (10:00–11:30), the Regional review's "vacant desk-minutes", the vault witness's "minutes away", the day/night tint and the HUD.
- **One file is the hotspot.** `scripts/world/teller_room.gd` (1,261 lines) wires every role to the day. If you and your teammate both edit it on parallel branches you'll get merge conflicts. Phase A should move each role's slot wiring out into its own small adapter file.
- **Old saves can keep loading.** Saves only happen off shift and store `day` + `minutes`. A new save field (`slot`) can be added with a fallback that works out the slot from the old `minutes`. No version bump is needed.
- **Tests:** about **93 of the 491 tests** (in 24 of 47 suites) touch time directly. About 25–35 need real rewrites (mostly the clock, business-day, staffing-pressure, truck and Regional-visit tests); the rest need small edits, and much of that can be absorbed by updating the shared test helpers.
- **Balance gets roughly 2–3× slower.** Today a player chaining teller shifts can serve about 12–16 customers a day for up to about 1,200 XP. With 8 customers a day it's about 500 XP a day. Reputation is the bigger brake: a teller earns it almost only from the closing count (+2), so going from 3–4 counts a day to 1 makes Branch Manager (Reputation 60) take about 5 days instead of about 1.5.
- **Proposed plug-in point:** a new `DayFlow` autoload that walks through a slot list defined in one config file (`DaySchedule`). It announces `slot_started` / `slot_ended` / `slot_skipped` / `day_ended`. Each role "claims" the slot and later calls `DayFlow.finish_work(...)`. Events can `hold()` a slot open or `skip_slot()` it. `GameClock` becomes a read-only display, set to each slot's start time, so the roughly 40 places that read `GameClock` keep working.
- **Phase A is medium-large:** about 18–20 game files and about 1,000 changed lines plus tests. Do it as about 11 small commits behind a temporary on/off switch, the same pattern the project already uses for `INTERVIEW_ENABLED`.

---

## 2. How the current clock works

### In plain English
Imagine a wall clock that only ticks while you're walking around the bank. Open any desk screen or letter and the whole room freezes, clock included. Every real second of walking moves the clock 1.5 game minutes, so a full 8.5-hour bank day (8:30 AM–5 PM) takes roughly 5½ minutes of walking time.

Separately, each customer has a stopwatch for patience (50 real seconds), each customer line has a timer for "send the next customer", and each staff member has a stopwatch for "how long this service takes". These also freeze when a screen opens, but they **never look at the wall clock**. They only ask the wall clock "is the bank open?" (`BusinessDay.is_open()`).

### The technical detail

**`scripts/autoload/game_clock.gd` — `GameClock`**
- How it advances: `_process(delta)` calls `advance(delta * GAME_MINUTES_PER_SECOND)` every frame. `GAME_MINUTES_PER_SECOND = 1.5`. It pauses with the tree, so desk screens and letters stop it.
- Variables: `day` (business day number, from 1), `minutes` (minutes since midnight, a float), `start_date` (the date of Day 1).
- Constants: `START_DAY = 1`, `START_MINUTES = 510` (8:30 AM), `MINUTES_PER_DAY`.
- Functions: `advance()`, `reset()`, `date_of_day(n)`, `today_date()`, `time_text()`, `hud_text()`, `timestamp()` ("Day 3, Wed 7 Jan, 10:42 AM"), `day_of(stamp)` (reads the day back out of a timestamp), `format_time()`, `save_data()` / `load_data()`.
- **Signals: none.** Everything that cares about time *polls* it (asks every frame) instead of being told.

**`scripts/autoload/business_day.gd` — `BusinessDay`**
- Constants: `OPEN_MINUTES` 9:00, `CLOSE_MINUTES` 17:00, `LAST_CLOCK_IN_MINUTES` 16:30, `CUTOFF_MINUTES` 14:00.
- Questions it answers: `is_open()`, `doors_closed()`, `can_start_shift()`, `is_day_over()`, `is_after_cutoff()`, `posting_day()`, `cutoff_text()`, `closures_before_next_day()`.
- Day totals: `customers_served_by_player/staff`, `shifts_completed`, Score/Reputation/XP at the day's start, `after_cutoff` transactions, `staff_net_cash_cents`. These feed `summary()`.
- Moving days: `go_home_early()` sets `GameClock.minutes = 17:00`. `start_next_day()` sets the next day at 8:30 AM and fresh totals.
- **Signals: none.**

**`scripts/util/bank_calendar.gd` — `BankCalendar`**: pure date maths (weekends, Federal Reserve holidays, "observed" rules). It doesn't depend on minutes at all.

### How a day flows today (clock-in to End of Day)
1. **8:30 AM**: the day starts (new career, or after "Start Day N+1"). The player may walk around and clock in early.
2. **Clock-in** at a desk (the teller window, Loan Desk 1, or the Branch Manager desk). Refused after 4:30 PM (`can_start_shift()`). A teller does the opening drawer count first.
3. **9:00 AM**: `teller_room._check_branch_opening()` notices `is_open()` flipped to true and restarts every customer line's spawn timer, so the first customers come within a few game minutes.
4. **During a teller shift**: the player's line spawns one customer about every 10–20 unpaused seconds, faster when the staff windows are busy, up to **4 per shift** (`CUSTOMERS_PER_SHIFT_CAP`). Each customer abandons after 50 unpaused seconds. Staff windows run continuously at the same time.
5. **Clock-out**: allowed only once every customer of the shift is handled (or the doors have closed). The closing drawer count is graded, the career is **saved**, and `BusinessDay.shifts_completed += 1`. A shift is roughly 90 unpaused seconds, about 2¼ game hours, so about 3–4 shifts fit in a day.
6. **10:00–11:30 AM** on a review day: the Regional Manager walks in and stands outside the office. **10:30 AM** on a truck day: the armored truck crew arrives and waits 45 game minutes.
7. **2:00 PM**: teller transactions start posting on the next business day.
8. **5:00 PM**: the doors close. No new customers; people already inside are still served.
9. **End of Day**: `teller_room._check_end_of_day()` checks every frame for three things: past 5 PM, the player off shift, and the lobby empty. When all hold, `show_end_of_day()` runs: the truck day settles, the vault closes its day, the loan book closes its day, the Regional Manager's demotion or review comes if due (their letters first), and then the summary appears and is saved.
   - The **exit doormat** ("Go home") jumps straight to 5 PM, clears the lobby and shows the summary.
10. **"Start Day N+1"**: shows a weekend or holiday notice first if needed, then 8:30 AM the next business day, saved.

---

## 3. Dependency table

**Change needed** is for moving to slots with *minimal adapters* (Phase A), not for the later Teller and Loan redesigns.

### Core time
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `autoload/game_clock.gd` | Owns day and minutes; advances per frame | **Medium** | Stop `_process` advancing. `minutes` gets set to the current slot's start time by the new `DayFlow`. Keep `timestamp()`, `day_of()` and `format_time()` so records stay readable. |
| `autoload/business_day.gd` | Hours, cutoff, go home, next day, totals | **Medium** | `is_open()` becomes "a working slot is active"; `can_start_shift()` becomes "before Closing"; `is_day_over()` becomes "Closing reached". The cutoff works unchanged if `minutes` = slot start (1 PM < 2 PM < 3 PM). `go_home_early()` becomes "skip the remaining slots to Closing". |
| `util/bank_calendar.gd` | Dates, weekends, holidays | **None** | Day-level only. |
| **New** `DayFlow` + `DaySchedule` | Slot list and sequencing | **New** (Large) | See section 6. |

### Teller (player's window)
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `world/customer_queue.gd` | Spawn timer (`spawn_interval` 20 s, shortened by staffing pressure), `CUSTOMERS_PER_SHIFT_CAP` 4, `open_for_the_day()` at 9:00, only spawns while `is_open()` | **Medium** | The cap becomes per slot (about 2). Spawning should only happen inside a working slot. The arrival timer can stay as pacing *within* a slot. |
| `npc/customer_npc.gd` (patience) | `wait_seconds += delta`; abandons at `WAIT_ABANDON_SECONDS` 50 (unpaused seconds) | **None to small** | It never reads the clock. Decide whether patience still runs while time is "frozen" in a slot (open question). |
| `npc/patience_indicator.gd` | Visual "…", "!", "!!" from the patience share | **None** | Follows patience. |
| Complaints (`customer_queue.gd` `COMPLAINT_CHANCE` 20%) | Rolled at spawn | **None** | A complaint customer counts toward the slot's quota like any customer. |
| `ui/teller_screen.gd` | Clock-in refused after 4:30; timestamps on transactions and summaries; `posting_day()` and the cutoff label; clock-out gate (all customers handled); card-decline cooldown (real seconds) | **Medium** | The adapter reports "slot work done" when the slot's customers are handled. Clock-in belongs in Opening and clock-out at Closing (or per slot, see open questions). The cutoff label works as-is. |
| Opening / closing drawer counts (`drawer_count_screen.gd`) | No time use; triggered by clock-in and clock-out | **Small** | Move them into the Opening and Closing slots. The grading is unchanged. |
| `world/teller_room.gd` `_describe_remaining_shift_work`, `customers_still_to_arrive()` | Clock-out gate, "doors closed" exception | **Small** | Becomes "customers left in this slot". |
| `world/teller_desk.gd` | None | **None** | |

### Loan Officer
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `ui/loan_officer_screen.gd` | `APPLICATIONS_PER_SHIFT` 3; clock-in refused after 4:30; timestamps | **Small to medium** | 1 application per slot. The adapter reports done after the decision. |
| `world/teller_room.gd` `_update_player_walk_in()` | Next applicant walks in when the seat is free, every frame | **Small** | Only while the slot still has an application left. |
| `world/loan_desk_seat.gd`, `npc/loan_applicant_npc.gd` | Walking and speech only (`LINE_SECONDS` 3) | **None** | |
| `autoload/loan_desk_manager.gd` | `names_today` resets per `GameClock.day`; document dates use `today_date()` | **None** | Day-level. |
| `autoload/loan_book_manager.gd` | Loans settle over `SETTLE_DAYS` 20; report every `REPORT_INTERVAL_DAYS` 20; `close_day()` at End of Day | **None** | Day-level. Volume per day changes (see Balance). |
| `ui/loan_review_screen.gd` | Shows today's date for the document check | **None** | |

### Branch Manager
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `ui/branch_manager_screen.gd` | Clock-in refused after 4:30; vault reconciliation **once per shift**, required before clock-out; staff "minutes at the vault" in the shift summary | **Small to medium** | The Branch Manager has no natural "per slot" work. Simplest adapter: claim the slot and finish it with a "Done for this slot" button, or don't claim slots at all. Vault reconciliation moves to Closing. |
| `ui/staff_scheduling_screen.gd`, `autoload/schedule_manager.gd` | None | **None** | |
| `autoload/staff_review_manager.gd`, `ui/staff_review_screen.gd` | Timestamps on items; "serious items left unreviewed **at clock-out**" (−2 Reputation each) | **Small** | Decide whether that check happens at Closing or per slot. |
| `autoload/hiring_manager.gd`, `ui/hiring_screen.gd` | "New candidates come at the next clock-in" | **None to small** | Tied to clock-in, not to time. |
| `ui/cash_orders_screen.gd` | Today, tomorrow's date and forecast | **None** | Day-level. |
| `ui/vault_reconciliation_screen.gd`, `world/vault_door.gd` | None | **None** | |
| `world/vault_dual_control.gd` | Witness "minutes away" = `GameClock.minutes` difference | **Small** | With time frozen it would always say 0 min. Switch to real seconds or drop the line. |
| `world/armored_truck_visit.gd` | Arrives at **10:30 AM**, leaves after `WAIT_MINUTES` 45 (11:15) if not received | **Medium** | Becomes a slot event: arrives at the start of the 9 AM slot and counts as "missed" if that slot ends unreceived. It could `hold()` the slot instead (open question). |
| `autoload/vault_manager.gd` | `close_day()` once a day; orders for day + 1 | **None** | Day-level. |

### NPC staff
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `world/npc_customer_line.gd` | Arrivals every 12–18 s (scene: 15 s); service `StaffMember.service_seconds()` 4–10 s; ID ask and decide at 30% and 60% of the service; only spawns while `is_open()` | **Small (Phase A) / Large (if per slot)** | Phase A: works unchanged if `is_open()` means "working slot active". Staff output then depends on how long the player takes in a slot (open question). |
| `world/npc_loan_desk_worker.gd` | Decides every `loan_decision_seconds()` 15–40 s; 2–6 s gap between applicants; only while `is_open()` | **Small** | Same as above. |
| `data/staff_member.gd` | Speed stat → seconds; mistake and ID chances (no time) | **None** | Mistake *rates* don't depend on time; mistake *counts* do (volume). |
| Staffing pressure, `teller_room.staff_window_pressure()` | Shortens the player's arrival gap 20 s → 10 s | **Small** | Still meaningful within a slot. With a fixed per-slot quota it only changes pacing, not volume. |
| Cover teller (`teller_room.gd` `_start_cover`, `_end_cover`) | Starts and ends with the Loan Desk 1 shift | **Small** | Follows the Loan Officer's clock-in and clock-out. |
| `npc/staff_npc.gd` | Walking, speech timers | **None** | |

### ATM
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `world/atm.gd`, `ui/atm_screen.gd` | **Nothing** | **None** | The ATM's daily restock is in `VaultManager.close_day()`, which is day-level. |

### Day, calendar, end of day, Regional
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `world/teller_room.gd` `_process` | Every frame: `_check_branch_opening()` (9:00), `_update_regional_visit()` (10:00–11:30), `_check_end_of_day()` (past 5 PM + off shift + empty lobby) | **Medium to large** | The hotspot. These become reactions to `DayFlow` signals. The End of Day sequence in `show_end_of_day()` (truck, vault, loan book, demotion or review, letters, summary) stays, but is triggered from Closing. |
| Going home early (`exit_door.gd`, `_on_go_home_confirmed`) | Jumps the clock to 5 PM; clears the lobby | **Small** | Becomes "skip the remaining slots". Lost slots = lost customers and XP. |
| 2 PM posting cutoff | `GameClock.minutes >= 14:00` | **None** | Works if `minutes` = slot start. Add a test that 1 PM is before and 3 PM after. |
| `ui/end_of_day_screen.gd` | Shows the day's figures, closures, cutoff list | **None to small** | Maybe add "slots worked / skipped". |
| `autoload/regional_manager.gd` | Review every 5 business days (day-level); **`_process` samples vacant desk-minutes every frame** between 9:00 and 17:00 | **Small to medium** | Day schedule: none. Vacancy sampling: replace with "on each working `slot_ended`, add slot length × vacant desks" so the −2.5 per desk-hour formula keeps meaning. |
| `world/day_night_cycle.gd` | Tint from `GameClock.minutes` every frame | **Small** | Works as-is but jumps between slots. Optionally tween. |

### HUD, letters, hints
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `ui/hud.gd` | `GameClock.hud_text()` each frame | **Small** | Show the slot ("Wed, Day 3 · 11 AM") and maybe the slot's progress ("1 of 2 customers"). |
| `ui/discipline_letter_screen.gd` (all letters) | None (pauses the tree) | **None** | |
| `autoload/hint_manager.gd` (`OPENING_HOURS` hint text) | Text explains 9–5 hours and going home | **Small** | Rewrite the text for slots. |
| `world/onboarding_flow.gd` | None | **None** | Runs before the first slot. |
| `autoload/history_manager.gd`, `report_manager.gd` | `timestamp()` on records | **None** | All records in one slot share a time, which is fine. |

### Save / load, slots, pause, firing
| File / System | What it uses time for | Change needed | Notes |
|---|---|---|---|
| `util/save_game.gd` | Saves `clock` {day, minutes, start_date} and `business_day`; `time_for_save()` snapping | **Small** | Add `DayFlow` data (`slot` index, skipped slots). Old saves: work out the slot from `minutes`. `FORMAT_VERSION` can stay 1. |
| `ui/start_screen.gd` (3 save slots, on main) | Slot button shows "Day N · date · 10:42 AM" from the saved minutes | **Small** | Show the slot name instead. |
| `ui/pause_menu.gd` (Esc, on main) | "Clocked in → progress lost" rule | **Small, but a design decision** | If a teller shift becomes the whole day, quitting mid-day loses the whole day (see risks). |
| Termination / firing (`report_manager.gd`, on main) | None (counts mistakes) | **None** | Slower in days, same per customer. |
| `autoload/interview_manager.gd` (probation) | Counts **3 clean teller shifts** | **Small** | Needs a new meaning of "shift" (a day? a slot?). |
| `autoload/xp_manager.gd` | Promotion waits for clock-out | **Small** | Same rule; "clock-out" may become "slot end" or "Closing". |
| `util/career_reset.gd` | Resets GameClock and BusinessDay | **Small** | Add `DayFlow.reset()`. |

---

## 4. Tests affected

- **Total:** 47 suites, **491 tests**.
- **Tests that touch time directly:** about **93 tests in 24 suites** (they read or set `GameClock` or `BusinessDay`, poke spawn timers or service seconds, go home, start the next day, and so on). Biggest:

| Suite | Time-touching tests | Expected work |
|---|---|---|
| `vault_cash_test.gd` | 10 | Mostly small: day-level, sets the day number |
| `bank_calendar_test.gd` | 9 | Mostly none: date maths; the cutoff and save-across-weekend tests are small |
| `business_day_test.gd` | 7 of 11 | **Rewrite**: hours, 4:30 refusal, closing, go home, midnight fallback |
| `armored_truck_test.gd` | 7 | **Rewrite** the timing tests (10:30, 45-minute wait); the grading tests are unaffected |
| `game_clock_test.gd` | 6 of 7 | **Rewrite**: "time runs while the world runs", midnight rollover |
| `vault_dual_control_test.gd` | 6 | Small: the witness-minutes expectations |
| `regional_review_test.gd` | 6 | Small to medium: visit times, vacancy desk-minutes |
| `b2_opening_count_test.gd` | 6 | Small: clock-in at the right time or slot |
| `loan_walk_in_test.gd` | 5 | Small to medium: walk-ins per slot |
| `player_line_pressure_test.gd` | 3 of 5 | Medium: per-shift cap → per-slot cap |
| `save_load_test.gd` | 4 | Small, plus **new** old-save migration tests |
| Others (`staff_id_checks`, `loan_book`, `loan_desks`, `kyc`, `cover_teller`, `staff_review`, …) | 1–4 each | Small |

- **Indirect:** 24 suites call the shared helpers `clock_in()` / `clock_out()` in `tests/support/teller_room_suite.gd` (114 call sites). If clock-out moves to Closing, update the helper (for example, have `clock_out()` first advance `DayFlow` to Closing) and most of those tests won't need individual edits. The helper also stops the spawn timer and spawns customers by hand, which keeps working.
- **Rough estimate:** about **25–35 tests rewritten**, **40–60 small edits**, plus about **20–30 new tests** for `DayFlow` (slot order, signals, claims, skip, hold, cutoff between 1 PM and 3 PM, old-save mapping, going home skips slots).
- The two boot checks in `run_tests.sh` (main scene and `teller_room.tscn`) will catch a broken autoload order.

---

## 5. Balance numbers to re-tune

### What a day looks like now (rough, "good player" estimates)
| Thing | Now | Basis |
|---|---|---|
| Teller customers for the player | **about 12–16 per day** (3–4 shifts × 4) | `CUSTOMERS_PER_SHIFT_CAP` 4; about 90 unpaused s per shift ≈ 2¼ game hours; clock-in until 4:30 |
| Teller drawer counts | 3–4 opening + 3–4 closing per day | One of each per shift |
| Loan applications for the player | **3 per shift; many shifts per day** | Desk screens pause the clock, so a Loan Officer shift barely moves time. 10+ shifts a day are possible. **There's effectively no daily limit today.** |
| Staff teller customers | about 20 per window per day, about 40 branch-wide (about 60 with Window 3) | Arrivals every 12–18 s over about 320 unpaused s (9–5 at 1.5 min/s) |
| Staff loan decisions | about 7–13 per desk per day, about 20–35 branch-wide | 15–40 s each + 2–6 s gap + walking |
| Truck visits / Regional visits | At most 1 a day / 1 every 5 business days | Day-level |

### With slots (4 working slots)
| Thing | Slots | Change |
|---|---|---|
| Teller customers | **8 per day** (about 2 per slot) | About 50–65% of now |
| Drawer counts | 1 opening + 1 closing per day (if the shift = the day) | About ¼–⅓ of now |
| Loan applications | **4 per day** (1 per slot) | Far fewer than an unlimited now |
| Staff output | Depends on the open question about staff per slot | Could drop a lot if slots are short in real time |

### XP and Reputation per day (perfect play)
- XP = Score × 10 (`XP_PER_SCORE_POINT`).
- **Teller now:** per shift, 4 × +5 (customers) + 10 (perfect closing) = 30 Score = **300 XP**, **+2 Reputation**. Per day about **900–1,200 XP, +6–8 Reputation**.
- **Teller with slots:** 8 × 5 + 10 = 50 Score = **about 500 XP a day, +2 Reputation a day.**
- **Loan Officer now:** BEST = +10 Score (100 XP) and +1 Reputation per application, plus up to +2 per correct denial reason. Unlimited per day.
- **Loan Officer with slots:** about 400 XP and +4 Reputation a day.

### Promotion speed (important)
- **Loan Officer** (500 XP, Reputation 40; you start at 50 Reputation + 50 training XP): now about 2 teller shifts (half a day); slots about 1 day. *Probably fine.*
- **Branch Manager** (1,500 XP, Reputation 60): **Reputation is the bottleneck.** A teller only gains Reputation from a perfect closing count (+2). Now that's 5 perfect shifts (about 1.5 days); with 1 closing a day it's **5 days**. As a Loan Officer it's +1 per BEST decision: now quick; slots about 3 days.
- **Things to re-tune:** `XP_UNLOCK_THRESHOLD` 500, `XP_UNLOCK_THRESHOLD_BRANCH_MANAGER` 1500, `REPUTATION_UNLOCK_FLOOR_BRANCH_MANAGER` 60, `REPROMOTION_XP` 500, `PERFECT_COUNT_SCORE` 10 / `PERFECT_COUNT_REPUTATION` 2 (now only once a day), `CUSTOMER_REQUEST_CORRECT_SCORE` 5, `TRAINING_XP_SCORE_POINTS` 5, `BEST_DECISION_SCORE` 10 / `BEST_DECISION_REPUTATION` 1. You might add a small Reputation reward per clean slot.

### Reports, probation, firing
- `MISTAKES_PER_REPORT` 2, `REPORTS_FOR_TERMINATION` 3: unchanged per mistake, but with fewer customers a day firing takes more days. Probably fine.
- `PROBATION_CLEAN_SHIFTS` 3: "shift" needs a new meaning. If shift = day, probation lasts 3 days (now about 1 day).
- `DRAWER_MAX_CENTS` $3,350: tuned so about 1 shift in 4 goes over. With 8 customers between counts, it will go over **more often**. Re-simulate.
- `WAIT_ABANDON_SECONDS` 50, `spawn_interval` 20 and `MIN_INTERVAL_SHARE` 0.5: these become pacing *inside* a slot; re-check that 2 customers don't feel rushed or empty.

### Regional review (every 5 business days)
- **Vault** area: one count per day. Unchanged.
- **Vacant desks**: −2.5 per desk-**hour**, from desk-minutes sampled in real time. **Must be re-based on slots** (e.g. each working slot = 2 desk-hours per vacant desk), or it scores 100 forever.
- **Staff mistake rate**: rated from 10 pieces of work. Still reachable, but volume depends on the staff decision.
- **Abandonment**: share of staff-line customers who gave up. Depends on patience inside slots.
- **Cash management / truck**: `WAIT_MINUTES` 45 → "within the slot".
- `REVIEW_INTERVAL_DAYS` 5, loan book `REPORT_INTERVAL_DAYS` / `SETTLE_DAYS` 20: day-based, no change needed. Fewer loans per day makes the portfolio report rest on fewer loans; consider 10 days.

---

## 6. Proposed plug-in point

### Plain English first
Think of the new day as a **conveyor belt of boxes**: Opening, 9 AM, 11 AM, 1 PM, 3 PM, Closing. One new manager, **DayFlow**, moves the belt.

1. When a box arrives, DayFlow **announces** it ("the 11 AM slot has started"). It doesn't know or care which role is listening.
2. Whoever has work in that box **raises their hand** ("I have work here": a *claim*).
3. When they finish, they **put their hand down** ("my work for this slot is done").
4. When every raised hand is down, DayFlow announces "11 AM slot ended" and moves the belt to the next box.
5. A **special event** (a break-in cutscene, the armored truck) can either **hold** the belt ("don't move on until I'm done") or **throw a box away** ("skip the 1 PM slot": those customers and their XP are lost).
6. **GameClock** becomes just the *display*: DayFlow sets it to each box's start time, so the HUD, timestamps, the 2 PM cutoff and the calendar keep working without changes.

The slot list lives in **one config file**, so changing "9 AM, 11 AM, 1 PM, 3 PM" or "2 customers per slot" means editing one place.

Roles never call each other, and they never change the clock's insides. They only listen to DayFlow's announcements, and they only call `claim_work()` and `finish_work()`.

### Code sketch (GDScript, illustrative only)

**`scripts/config/day_schedule.gd`: the one config place**
```gdscript
class_name DaySchedule
extends RefCounted

enum Kind { OPENING, WORK, CLOSING }

## Edit here to change the day. `quota` is how much work each role does in a
## WORK slot. The role decides what "one unit" means.
const SLOTS: Array[Dictionary] = [
	{"id": &"opening", "label": "Opening", "start": 8 * 60 + 30, "kind": Kind.OPENING},
	{"id": &"am_9",    "label": "9 AM",    "start": 9 * 60,       "kind": Kind.WORK},
	{"id": &"am_11",   "label": "11 AM",   "start": 11 * 60,      "kind": Kind.WORK},
	{"id": &"pm_1",    "label": "1 PM",    "start": 13 * 60,      "kind": Kind.WORK},
	# The 2 PM cutoff (BusinessDay.CUTOFF_MINUTES) falls here, between 1 PM and 3 PM.
	{"id": &"pm_3",    "label": "3 PM",    "start": 15 * 60,      "kind": Kind.WORK},
	{"id": &"closing", "label": "Closing", "start": 17 * 60,      "kind": Kind.CLOSING},
]

const QUOTA: Dictionary = {&"teller": 2, &"loan_officer": 1, &"branch_manager": 1}

## For old saves: the slot a saved `minutes` falls in.
static func index_for_minutes(minutes: float) -> int:
	var found := 0
	for i in SLOTS.size():
		if minutes >= SLOTS[i]["start"]:
			found = i
	return found
```

**`scripts/autoload/day_flow.gd`: the conveyor belt (new autoload, after GameClock)**
```gdscript
extends Node

signal day_started(day: int)
signal slot_started(slot: Dictionary)          # roles claim work here
signal slot_ended(slot: Dictionary)            # finished normally
signal slot_skipped(slot: Dictionary, reason: String)  # lost: no work, no XP
signal day_ended(day: int)                     # Closing finished → End of Day

var index: int = 0
var skipped_today: Array[StringName] = []
var _claims: Dictionary = {}   # role -> true while that role still has work
var _holds: Dictionary = {}    # reason -> true while an event holds the slot

func current() -> Dictionary: return DaySchedule.SLOTS[index]
func is_work_slot() -> bool: return current()["kind"] == DaySchedule.Kind.WORK

# --- what roles call ---
func claim_work(role: StringName) -> void: _claims[role] = true
func finish_work(role: StringName) -> void:
	_claims.erase(role)
	_try_advance()

# --- what events call ---
func hold(reason: String) -> void: _holds[reason] = true
func release(reason: String) -> void:
	_holds.erase(reason)
	_try_advance()
func skip_slot(slot_id: StringName, reason: String) -> void:
	if not skipped_today.has(slot_id):
		skipped_today.append(slot_id)
	if current()["id"] == slot_id:   # skipping the one we're in ends it now
		_claims.clear()
		slot_skipped.emit(current(), reason)
		_next()

# --- inside ---
func _try_advance() -> void:
	if _claims.is_empty() and _holds.is_empty():
		slot_ended.emit(current())
		_next()

func _next() -> void:
	index += 1
	if index >= DaySchedule.SLOTS.size():
		day_ended.emit(GameClock.day)
		return
	_enter(index)

func _enter(i: int) -> void:
	index = i
	GameClock.minutes = DaySchedule.SLOTS[i]["start"]   # the only writer of minutes
	if skipped_today.has(DaySchedule.SLOTS[i]["id"]):
		slot_skipped.emit(DaySchedule.SLOTS[i], "skipped")
		_next()
		return
	slot_started.emit(DaySchedule.SLOTS[i])
	_try_advance.call_deferred()   # nobody claimed → move on (or wait: open question)

# reset(), save_data() {"slot": index, "skipped": ...}, load_data() with
# DaySchedule.index_for_minutes(old minutes) as the fallback.
```

**A role adapter (Teller), e.g. `scripts/world/teller_slot_adapter.gd`**
```gdscript
class_name TellerSlotAdapter
extends Node

var queue: CustomerQueue
var screen: TellerScreen
var _left: int = 0

func _ready() -> void:
	DayFlow.slot_started.connect(_on_slot_started)
	DayFlow.slot_skipped.connect(_on_slot_skipped)
	screen.customer_handled.connect(_on_customer_handled)  # served / left / abandoned

func _on_slot_started(slot: Dictionary) -> void:
	if slot["kind"] != DaySchedule.Kind.WORK or not screen.is_clocked_in():
		return
	_left = DaySchedule.QUOTA[&"teller"]
	DayFlow.claim_work(&"teller")
	queue.start_slot(_left)   # replaces the per-shift cap of 4

func _on_customer_handled(_c: CustomerNPC) -> void:
	_left -= 1
	if _left <= 0:
		DayFlow.finish_work(&"teller")

func _on_slot_skipped(_slot: Dictionary, _reason: String) -> void:
	queue.clear_lobby()   # those customers (and their XP) are lost
```

**How each role hooks in (minimal adapters)**
- **Teller**: `TellerSlotAdapter` (above). Opening slot = clock-in plus opening count. Each WORK slot = claim, about 2 customers, finish. Closing slot = closing count, then the shift summary.
- **Loan Officer**: `LoanSlotAdapter`. On a WORK `slot_started`, if clocked in at Loan Desk 1, `claim_work(&"loan_officer")` and allow 1 walk-in. On `LoanReviewScreen.decision_recorded`, `finish_work(&"loan_officer")`.
- **Branch Manager**: `ManagerSlotAdapter`. Simplest version: claim on each WORK slot and finish when the player presses "End this slot" in the hub. Vault reconciliation and the unreviewed-items check move to the Closing slot.
- **NPC staff (Phase A)**: no claims. `BusinessDay.is_open()` becomes `DayFlow.is_work_slot()`, so staff lines and loan desks work exactly while a working slot is active.
- **Events**:
  - Armored truck: on `slot_started(am_9)` the crew walks in, and a Branch Manager adds `hold("armored_truck")` until they're received (or a miss on `slot_ended`).
  - Regional visitor: appears on `slot_started(am_11)` on review days.
  - Break-in: `DayFlow.skip_slot(&"pm_1", "break-in")` after its cutscene.
  - Going home: skip every remaining WORK slot, then Closing.
- **End of Day**: `teller_room` listens to `DayFlow.day_ended` instead of polling for 5 PM in `_check_end_of_day()`.

**Why this is a good fit for the parallel branches:** the Teller redesign only edits `TellerSlotAdapter`, the teller screen and the customer queue; the Loan redesign only edits `LoanSlotAdapter` and the loan screens. Neither touches `DayFlow`, `DaySchedule` (except tuning numbers) or each other's files. `teller_room.gd` just creates the adapters (one line each), so it stops being a conflict point.

---

## 7. Phase A size, commit order, and risks

### Size
- **New:** `DaySchedule` (about 60 lines), `DayFlow` autoload (about 200–300 lines), three adapters (about 60–120 lines each).
- **Edited:** about 15–18 existing scripts: `game_clock`, `business_day`, `teller_room`, `customer_queue`, `teller_screen`, `loan_officer_screen`, `branch_manager_screen`, `armored_truck_visit`, `regional_manager`, `vault_dual_control`, `hud`, `day_night_cycle`, `start_screen`, `save_game`, `career_reset`, `interview_manager`, `hint_manager`, plus `project.godot` (autoload) and CLAUDE.md.
- **Estimate:** about **1,000–1,500 changed lines of game code**, about **1,000 lines of test changes and new tests**. That's medium-large: several focused agent sessions, not one prompt.

### Suggested commit order (each one leaves all tests green)
1. **Add `DaySchedule` and `DayFlow` (not used yet)**, with reset, save and load wired into `CareerReset` and `SaveGame`, and their own unit tests. No behaviour change.
2. **Add a temporary switch** `DayFlow.SLOTS_ENABLED = false` (like `INTERVIEW_ENABLED`). With it off, the old clock runs exactly as before. (Done, then removed in Phase A session 3b: the slot system is the only way a day runs.)
3. **`GameClock` and `BusinessDay` read slots when the switch is on:** no per-frame advance; `is_open`, `can_start_shift`, `is_day_over` and `go_home_early` go through `DayFlow`. Add the cutoff test (1 PM before, 3 PM after).
4. **End of Day from `DayFlow.day_ended`**: replace the per-frame `_check_end_of_day` and `_check_branch_opening` in `teller_room.gd`.
5. **Teller adapter** (per-slot quota, claim and finish, opening and closing counts in Opening and Closing).
6. **Loan Officer adapter.**
7. **Branch Manager adapter** (including vault reconciliation at Closing).
8. **Timed events → slot events:** armored truck, Regional visit, vacancy sampling per slot, vault witness time.
9. **Display:** HUD slot text, day/night per slot, start-screen slot label, opening-hours hint text.
10. **Save migration:** the `slot` field plus the old-save fallback, with tests that load a pre-slots save.
11. **Turn the switch on**, update the remaining tests and the `teller_room_suite` helpers, delete the old continuous-clock code and the switch, and update CLAUDE.md.

Then the Teller and Loan redesign branches start from that commit.

### Riskiest parts
1. **The hidden second clock.** Patience, arrivals, staff service and staff loan decisions run on real unpaused seconds, not on `GameClock`. "Freezing time inside a slot" does nothing to them unless you decide it should. Get this decision written down first.
2. **Saving mid-day.** Today saves only happen off shift, and a career is never saved mid-shift. If a teller shift becomes the whole day (Opening → Closing), quitting mid-day loses the day. Saving at each slot end would mean saving the drawer and shift state, which is new and a meaningful amount of work.
3. **The End of Day sequence** in `teller_room.show_end_of_day()` is order-sensitive: truck settle → vault close → loan book close → demotion or review → letters → summary → save. Moving its trigger must keep that order exactly, or reviews and reports can run twice or not at all.
4. **Soft-locks.** A slot waits for claims. Possible stalls:
   - The quota can't be met (all customers abandoned: count abandons as handled).
   - The player is off shift, so nobody claims and the belt moves instantly, or never moves.
   - A hold is never released.
   Plan for a fallback (a "Wait for next slot" action, or a debug key).
5. **`teller_room.gd` merge conflicts.** If Phase A leaves role wiring inside it, the parallel Teller and Loan branches will collide there. Extracting the adapters is part of the goal, not polish.
6. **Test timing.** Many room tests set `GameClock.minutes` directly or stop spawn timers. Once `DayFlow` is the only writer, those tests need a helper such as `go_to_slot(&"pm_3")`.
7. **Balance shock.** Branch Manager may take about 3× longer, mainly through Reputation. Playtest before the redesigns build on top of it.

---

## 8. Open questions for the team

**About time inside a slot**
1. Inside a slot, does **customer patience** still run while the player walks around? (Today it's 50 real seconds.) If yes, slowness is still punished. If no, nobody ever abandons.
2. Do **NPC staff work per slot** (a fixed number of customers or loans each, e.g. 4 per window per slot), or keep working in real seconds while a slot is active? The second is simpler, but staff output then depends on how slow the player is.
3. Inside a slot, do the player's **customers arrive one by one** (paced), or are the 2 customers there at the start of the slot?
4. **What ends a slot** when the player isn't working: off shift, on break, or standing in the vault? Does the belt wait forever, move on at once, or is there a "Wait for the next slot" button?

**About shifts**
5. Is a teller **shift the whole day** (one opening count, one closing count) or **one slot**? This decides drawer counts, the clock-out gate, probation's "3 clean shifts", the promotion-at-clock-out rule and the Branch Manager's "unreviewed at clock-out" penalty.
6. Can a player **switch roles mid-day**, e.g. teller in the 9 AM slot and Loan Desk at 11 AM (possible today with several shifts a day)?
7. What is the **Branch Manager's work for a slot**? A button? A short task list (review items, scheduling)? Nothing, with only Opening and Closing duties?

**About saving and leaving**
8. **When does the game save**: each slot end, or only at Closing and on "Start Day N+1"? (See risk 2.)
9. What does **"going home early"** mean now? Skip all remaining WORK slots and lose those customers and XP (as now)? Is it still allowed mid-shift?
10. What does **Esc → Back to Main Menu** do mid-day?

**About events**
11. **Special events**: do they skip the *current* slot or the *next* one? Can more than one slot be skipped? Is the player warned before a skip? Is there a penalty beyond lost XP?
12. **Armored truck**: does it *hold* the 9 AM slot until received (the player can't miss it), or can the slot end without it (a missed truck, as now)?
13. **Regional Manager visit**: which slot? Should it hold that slot?

**About balance**
14. Re-tune **promotion** (XP 500 / 1,500, Reputation 40 / 60), or add Reputation per clean slot?
15. Keep **"Day N" = one business day** (so the calendar, loan book and 5-day review keep their meaning)? Recommended: yes.
16. Should the **drawer limit** ($3,350) and **report thresholds** change now that there's one count a day?
17. Is the slot list fixed for every role, or could a role have its own slot quotas or extra slots? (The sketch supports per-role quotas in one config file.)
