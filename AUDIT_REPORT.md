# BankSim Audit: what was fixed since the handoff

**Audited:** 2026-10-09 · **Baseline:** commit `4e2d2e4` (2026-09-23, the "last commit" named in HANDOFF.md) · **Audited state:** `main` at `22995ba`, working tree clean (no uncommitted changes).

**Method:** I read the code itself for every bug and did not rely on commit messages or comments. I also ran the game headless in Godot 4.7.2 (see section 5.3). This was a read-only review: the only file written is this report.

**Quick glossary**
- **Float:** a decimal number type. It can't store most cent values exactly (0.10 + 0.20 is not exactly 0.30), so money math in floats drifts.
- **Integer cents:** storing $12.34 as the whole number `1234`. This is exact.
- **Autoload:** a global script Godot loads at startup (`ScoreManager`, `XPManager`, and so on).
- **Signal:** Godot's "something happened" event that other scripts can listen to.
- **Headless:** running Godot with no window, which is useful for automated checks.
- **Y-sort:** drawing objects lower on screen in front of objects higher up, so characters walk *behind* a desk instead of over it.

---

## 1. Summary

- **14 bugs checked: 5 fixed correctly, 5 fixed but flawed, 4 not fixed.**
- Fixed correctly: B1 (stale serving state), B7 (F1 cheat), B8 (unlock check), B9 (debt-to-income), B12 (`.godot/` untracked).
- Fixed but flawed: B2 (scoring/gate), B3 (cents), B6 (customer requests), B10 (warnings), B13 (docs).
- Not fixed: B4 (HUD), B5 (y-sort/collision), B11 (typing), B14 (leftover files).
- **No automated tests exist,** so no Phase 0 criterion is fully met except untracking `.godot/`. The teammate also added two large features the handoff didn't ask for: disciplinary reports with termination, and NPC coworkers. The NPC feature introduces one new bug (section 4).

---

## 2. Bug verdicts, B1 to B14

| ID | Verdict | Where (file:line) | One-sentence reason |
|---|---|---|---|
| B1 | **FIXED CORRECTLY** | `teller_room.gd:326-328`, `teller_screen.gd:692-695`, `teller_screen.gd:1055-1060` | On clock-out the room clears the served customer and the screen, the payment-method lookup now checks `is_instance_valid`, and the selected account resets to a non-customer account. |
| B2 | **FIXED BUT FLAWED** | `teller_screen.gd:879-888`, `932-955`, `160-181`; `teller_room.gd:308-321` | The 45 s timer was removed and replaced with a "finish your customers first" gate rather than patched, but the opening count is only *shown*, not enforced, and the drawer count still outweighs customer service, so ignoring every customer still pays. |
| B3 | **FIXED BUT FLAWED** | `money_math.gd:1-12`, `drawer_count_screen.gd:155-172`, `teller_screen.tscn:117-119` vs `:458` | Discrepancy *comparisons* now use integer cents and cash amounts are whole dollars, but money is still *stored* as floats everywhere, and two places still create cent or sub-cent values. |
| B4 | **NOT FIXED** | `teller_screen.tscn:184` (`ScoreHudPanel` still a child of TellerScreen), `teller_room.tscn` | There is still no always-on HUD and no "Press E" prompt or tutorial, and the player still spawns at (384, 624). |
| B5 | **NOT FIXED** | `teller_room.tscn:76-77` | Only the new `Staff` layer is y-sorted. The room root isn't, the player still draws under furniture, and furniture still has no collision. CLAUDE.md even says "full-room y-sorting (B5) isn't done yet". |
| B6 | **FIXED BUT FLAWED** | `teller_screen.gd:449-480`, `542-543`, `365-368`, `323-337` | The game now checks the type, amount and account against what the customer asked for (parts a, b and c fixed), but the "stale account" problem (d) still happens mid-shift, and doing a request in two steps is graded as a mistake. |
| B7 | **FIXED CORRECTLY** | `teller_room.gd:396-402` | F1 now returns early unless `OS.is_debug_build()`, so it can't fire in a release export (the doc comment at lines 37-41 still calls it a TEMP cheat). |
| B8 | **FIXED CORRECTLY** | `xp_manager.gd:57-62` | XPManager now listens to `ReputationManager.reputation_changed` and re-runs both unlock checks, which safely fire only once. |
| B9 | **FIXED CORRECTLY** | `loan_application.gd:52-57`, `88-91`, `141-148`; `loan_applications_data.gd` | The teammate decided `existing_debt` is a *balance*, added a separate `monthly_debt_payments` field, and DTI is now monthly payments ÷ monthly income. That is the standard formula. |
| B10 | **FIXED BUT FLAWED** (partial) | `drawer_count_screen.gd:134`, `vault_reconciliation_screen.gd:151`, `approvals_screen.gd:135` | The untyped `abs()` calls became `absi()`, but the integer-division warnings are untouched, a new untyped `max()` was added, and stricter warnings weren't enabled. |
| B11 | **NOT FIXED** | `teller_room.gd:72-75` | The desks and screens are still typed as plain `Area2D`/`Control`, so `.interacted` and `.show_screen()` remain unsafe member access. |
| B12 | **FIXED CORRECTLY** | commit `3f8c93b` | All 48 `.godot/` files were removed from git tracking (`git ls-files .godot` returns 0), and `.gitignore` still ignores the folder. |
| B13 | **FIXED BUT FLAWED** (partial) | `CLAUDE.md`, `DEVLOG.md`, see section 3 | `interview_screen.gd`'s header and parts of CLAUDE.md were updated, but CLAUDE.md is still wrong in several places, DEVLOG.md hasn't changed since Sep 16, and 4 of the 7 stale comments listed in the handoff remain. |
| B14 | **NOT FIXED** | repo root, `assets/sprites/` | `node_2d.tscn`, `player_placeholder.png`, `teller_desk_placeholder.png` and `project.godot.bak` are all still tracked (I found no references to them). |

### The four points you asked me to watch

- **B2, timer patched or replaced?** It was replaced, not patched. `MIN_SHIFT_DURATION_SECONDS` and `Time.get_ticks_msec()` are gone from all three role screens. Clock-out now requires every customer of the shift (cap of 4) to be served, resolved or gone (`teller_room.gd:308-321`). Loan Officer clock-out needs 3 decisions, and Branch Manager clock-out needs a vault count. **But the scoring model was not replaced:** the drawer count still gives +10, while a correctly served customer gives +2.
- **B2, opening count validated?** Partly. `_begin_shift()` now *always* uses the assigned $50,000 float (`teller_screen.gd:934`), so a wrong opening count can no longer move the target. It also grades the opening count and shows the result. However, a wildly wrong opening count has no consequence: the shift starts anyway, with no recount, no score effect and no log entry.
- **B3, integer cents everywhere?** No, only at comparison time. See section 3.
- **B6, does the game check what the customer asked?** Yes. `_is_request_satisfied()` compares the net change on the customer's *own* account, in cents, against `intent_type`/`intent_amount`. It also requires any wrong-account transaction to be reversed. See section 3 for the gaps.
- **B7, gated behind `OS.is_debug_build()`?** Yes (`teller_room.gd:397`).

---

## 3. Fixes that need rework

### B2: scoring still rewards the drawer, not the customers
**What's wrong, in plain terms:** the anti-farming timer is gone, which is good. But the game still pays mostly for counting cash.
- A Perfect closing count gives **+10 Score, +2 Reputation, +100 XP** (`teller_screen.gd:160-166`).
- A correctly served customer gives **+2 Score, +0 Reputation** (`teller_screen.gd:178-181`).
- A customer who walks out because you ignored them costs **−2 Reputation and no Score or XP** (`teller_room.gd:69, 336-346`).
- So a player can clock in, ignore all 4 customers until they leave, then count the untouched drawer perfectly. That earns **+10 Score and +100 XP** for doing nothing (Reputation nets −6). Serving all four perfectly earns only +18 Score.
- The low-reputation unlock floors (40 and 60) limit how far this goes, but it is still the wrong incentive for a training product.
- The opening count is graded (`teller_screen.gd:946-951`) but has no consequence.

**What to change:**
1. Make customer outcomes the main score. For example, a customer leaving unserved should cost Score and XP, not just Reputation. Scale or cap the drawer bonus by customers actually served, and give no Perfect bonus if nobody was served.
2. Make the opening count matter. If the result is Major, require a recount or a supervisor sign-off before the shift starts, and log the variance to `HistoryManager`.
3. Add a test that "ignore everyone + Perfect count" scores below "serve everyone + Minor count".

### B3: cents only at the comparison step
**What's wrong:** `MoneyMath.to_cents()` (`money_math.gd`) converts float dollars to integer cents *just before* comparing. Its own header comment admits money is "stored as float dollars throughout". The remaining float storage:
- `Account.balance` (`account.gd:11`), `ShiftTransaction.amount`, `CustomerNPC.intent_amount`, and the drawer totals summed in `_calculate_expected_ending_balance()` (`teller_screen.gd:858-868`).
- The **Open New Account** starting balance still allows 1-cent steps (`teller_screen.tscn:458`, `step = 0.01`).
- New customer accounts get `randf_range(200.0, 2000.0)` balances (`customer_queue.gd:234`). These aren't even whole cents (e.g. $1234.5678...), and that value shows up in the balance label and the `can_withdraw` check.

Today this works, because all teller and ATM amounts are whole dollars, so the float sums stay exact. It's fragile, though: the first time someone adds coins or a cents amount, the drift comes back everywhere except the comparisons.

**What to change:** store every amount as `int` cents (`balance_cents`, `amount_cents`, `intent_cents`). Convert to dollars only for display, in one helper (e.g. `MoneyMath.format(cents)`). Make the Open Account spin box step $1, or convert its value to cents on entry. Round random customer balances to whole cents. Add a test that sums many transactions and checks the expected drawer to the exact cent.

### B6: the request check works, with three gaps
1. **Stale account between customers (part d of the original bug) still happens mid-shift.** After the last waiting customer is served, `advance_to_customer(null)` → `set_serving_customer(null)` (`teller_screen.gd:323-337`) leaves `account` pointing at that customer's account. `_refresh_account_list()` then can't find it in the dropdown, so the dropdown goes blank while the label still shows the old customer's name. Any deposit or withdrawal made now hits that customer's account ungraded and still moves the drawer. The reset only happens at clock-out (`_reset_account_selection()`, line 1055).
   *Fix:* call `_reset_account_selection()` (or select the demo account) inside `set_serving_customer()` whenever `customer == null`.
2. **Doing a request in two steps counts as a mistake.** If a customer asks to deposit $500 and the teller enters $200 and then $300, the first transaction already fails `_is_request_satisfied()`. That sets `was_mistake = true`, applies −3 Score and −2 Reputation, and counts toward a disciplinary report (`teller_screen.gd:471-476`). It might be intended, but it isn't documented, and it feeds termination.
   *Fix:* only flag a mistake when the transaction can't be part of a correct answer (wrong account, wrong type, or overshooting the amount), or add an explicit "Done" step that grades the visit.
3. **NPC staff can make a player's customer impossible to serve.** See section 4, item 2.

No B6 test exists.

### B10: compile warnings still present
`remaining / denom` (integer ÷ integer) still triggers the integer-division warning at `drawer_count_screen.gd:134` and `vault_reconciliation_screen.gd:151`. A new untyped `max(0, ...)` was added at `approvals_screen.gd:135`; use `maxi`. Stricter warnings are not enabled in `project.godot`.

### B13: docs still out of date
- **CLAUDE.md** still says:
  - "a Loan Officer role unlock is planned but not wired up" (it is wired up);
  - only 4 of the 8 autoloads are listed (AccountManager, XPManager, HistoryManager and ScheduleManager are missing);
  - the room is "a small tile room" and `room_builder.gd` builds "a simple walled rectangular room" (it's now a multi-zone branch floor);
  - nothing about MoneyMath, the clock-out gate, or the request grading.
  The new paragraphs it did gain are accurate.
- **DEVLOG.md:** no entry for any commit after `039762e` (Sep 16). That leaves 18 commits undocumented, including all of the Oct 7 work.
- **Stale comments the handoff listed, still present:**
  - `interview_manager.gd:14-16` (says 9 questions and about 26 points; the data file now has 10 questions);
  - `history_manager.gd:6-9` ("nothing reads this yet");
  - `drawer_count_screen.gd:78-80` ("all four inputs"; there are six);
  - `customer_npc.gd:134` (points to `scratch/gen_customer_sprites.py`, which is gitignored).
- **New stale comments:**
  - `teller_room.gd:37-41` still calls F1 a TEMP cheat to be removed "or gate it behind a debug-build check", which has now been done;
  - `npc_customer_line.gd:44` and `npc_loan_desk_worker.gd:39` say "used by tests", but no tests exist in the repo;
  - HANDOFF.md section 1 says the teller desk is at (560, 336); it moved to (464, 336).

---

## 4. Changes not in the handoff

All 16 new commits were made on 2026-10-07 by James2k8 (co-authored with Claude). Besides the bug fixes, they add:

1. **Disciplinary reports and termination** (`report_manager.gd`, `discipline_letter_screen.gd`, `career_reset.gd`, `disciplinary_report.gd`, plus a `reset()` on every autoload).
   - Every 2 mistaken customers = 1 written warning; 3 warnings = fired.
   - "Apply for a new job" wipes *all* progress and loads the interview.
   - This adds a fail state, which the handoff wanted (2.2), but: the interview it loads is the old *scored* one that can REJECT you. The handoff (3.3, 3.4.6) recommended making it non-scored.
   - Also, `is_on_probation` is still never read by gameplay.
2. **NPC coworkers**: 3 teller windows, staff NPCs, two NPC-served customer lines, and a background loan worker (`staff_npc.gd`, `npc_customer_line.gd`, `npc_loan_desk_worker.gd`, `staff_member.gd`, `schedule_manager.gd`). The player's desk moved from x=560 to x=464.
   - **New bug:** NPC-line customers draw from the same 36-name pool and reuse the same account by name (`customer_queue.gd:230-236` → `account_manager.gd:72`).
   - NPC lines run nonstop (one arrival every 12-18 s per window), and staff really deposit and withdraw on those accounts (`npc_customer_line.gd:134-136`).
   - So a customer in the *player's* line can have their balance drained by a same-named NPC customer after their withdrawal request was set. The player then gets "Insufficient funds" and can't satisfy the request. The customer blocks clock-out until they walk away, which costs −2 Reputation through no fault of the player.
   - *Fix:* give NPC lines their own accounts (a separate name pool, or never reuse a player-line account).
3. **Customers can point out mistakes and wait for a fix**, plus a Reverse Transaction button and the rule that wrong-account transactions must be reversed (commits `e502926`, `7f365f7`). This is an extension of B6.
4. **Queue movement pacing**: customers no longer overlap and leave through a side corridor (`customer_queue.gd:284-332`). This is visual only.
5. **Customer name pool grown from 10 to 36** (`34a69f3`).
6. **Loan review:** closing without deciding no longer uses up an application slot, and the same application comes back (`loan_review_screen.gd:111-120`, `loan_officer_screen.gd:131-132`). The Loan Officer and Branch Manager 45 s timers were replaced with work gates (consistent with B2).
7. **Shift summary shows customer results**, and unlock and warning banners stack in a top-left column (`e4fc55e`, `83629bd`).
8. **`project.godot`** gained the `ReportManager` autoload, and one setting was reordered by the editor (no value change).
9. **No files were deleted** except the 48 `.godot/` cache files (B12).

---

## 5. Design flaws and Phase 0 status

### 5.1 Design flaws (handoff 2.2)

| Flaw | Changed? |
|---|---|
| Scoring rewards the wrong thing | **Partly.** Customer requests are now graded (+2 or −3, with a −3 extra if left unfixed), but the drawer count (+10/+5/−5) still dominates. See B2 above. |
| No fail state, no persistence | **Fail state added** (termination after 3 reports). Reputation 0 still only shows a warning. **No persistence:** everything still resets on relaunch. |
| Staffing screen is decorative | **Partly fixed.** The schedule now decides which NPC sits at each desk, and their speed, skill and reliability set NPC service time and mistake rate. It still doesn't affect the *player's* queue (arrival rate or service), which is what the handoff suggested. |
| Unrealistic cash model | **Unchanged:** $1,000 and $500 bills, a $50,000 float, no coins (`drawer_count_screen.gd:21`, `teller_screen.gd:158`). Cash amounts are now whole dollars. |
| Wall-clock time | **Unchanged:** shift and transaction times still come from `Time.get_datetime_string_from_system()`. There is no sim clock or business-day calendar. The wall-clock *gates* were removed. |
| Orphaned interview | **Reconnected** through termination only. Still scored and can reject the player; `is_on_probation` is still unused. |

### 5.2 Phase 0 acceptance criteria (handoff 2.3)

| Criterion | Status |
|---|---|
| B1, B2, B3, B6, B7, B8, B9 fixed, each with an automated test | **Not done.** 4 of the 7 are fixed correctly (B1, B7, B8, B9); B2, B3 and B6 need rework. **Zero tests exist:** there is no `addons/`, `tests/`, gdUnit4, GUT or test script anywhere in the repo. |
| `--headless --quit-after 300` and the test suite run in CI with zero errors and warnings | **Partly.** The headless run is clean on this machine (5.3), but there is no CI config (no `.github/`) and no test suite. |
| `CLAUDE.md` and `DEVLOG.md` match the code | **Not done.** See B13. |
| `.godot/` untracked | **Done** (commit `3f8c93b`; 0 tracked files under `.godot/`). |
| Always-on HUD and interaction prompt | **Not done.** See B4. |

### 5.3 Headless run

- Godot was not on PATH. I found `C:\Users\La Yaung Moe\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` and installed nothing.
- `--headless --path . --quit-after 300`: **exit code 0, zero errors, zero warnings.** `git status` was still clean afterwards.
- Caveat: 300 frames of idle boot doesn't play a shift, so it can't catch gameplay bugs. That's what tests are for.
- I also tried a per-script parse check (`--check-only --script`). Every script that uses an autoload reported "Identifier not found". That is a known limitation of that mode, not a real error, and the real run above loads them fine. So compile *warnings* like B10's weren't captured by this run. You'd see them in the editor's Debugger/Errors panel.

---

## 6. Remaining work, in the order to do it

1. **Test setup and docs**
   - Add gdUnit4 (the handoff recommends v6.2.1 for Godot 4.7) under `addons/`, and a GitHub Actions workflow that runs `--headless --import`, the test suite, and `--headless --quit-after 300`.
   - Write one test per Phase 0 bug: B1, B2, B3, B6, B7, B8, B9.
   - Rewrite CLAUDE.md (all 8 autoloads, the real room, MoneyMath, the clock-out gate, request grading, the "no tests yet" note) and add DEVLOG entries for the Oct 7 commits.
   - Fix the stale comments listed under B13.
2. **Quick wins (B7, B8):** the code is already done. Add their tests (F1 does nothing when not a debug build; a reputation rise alone triggers the unlock) and update the F1 doc comment at `teller_room.gd:37-41`.
3. **Cents (B3):** switch storage to `int` cents end to end, fix the Open Account spin box step, round customer starting balances, and add an exact-sum test.
4. **Scoring cluster (B2, B6, B1):**
   - Make customer outcomes outweigh the drawer bonus, and make an abandoned customer cost Score and XP.
   - Enforce the opening count.
   - Reset `account` when no customer is being served.
   - Decide whether two-step transactions count as mistakes.
   - Give NPC lines their own accounts.
   - Add the B1 regression test.
5. **B9:** the formula is right. Add a test (e.g. $500/month payments on $60k/yr income = 10%). Later, add a housing payment and a total DTI as part of the Loan Officer rework, and keep labeling the bands as game balance, not lending rules.
6. **HUD and collision (B4, B5):** an always-on HUD `CanvasLayer`, a "Press E" prompt near desks, a first-run hint, y-sort on the room root, collision on furniture, and an outdoor tile at the entrance gap.
7. **Code cleanup (B10, B11, plus B14):** fix the integer-division and `max` warnings, turn on stricter GDScript warnings, give the desks `class_name`s and type the `@onready` vars in `teller_room.gd`, and delete the four leftover files.
