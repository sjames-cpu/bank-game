# Time Slots — Decisions

**Status:** Confirmed by Liam (`lym221-not`) and James (`James2k8`) on 2026-11-16.
**Based on:** `TIME_SLOTS_IMPACT.md` (inspected `main` @ `574d0150`).

These are the agreed answers for switching from the continuous clock to visual-novel style time slots. If any of them needs to change later, edit this file in its own small pull request and tell the other person, because Phase A code is built on these answers.

---

## The day

```
Opening (8:30) → 9 AM → 11 AM → 1 PM → 3 PM → Closing (5 PM)
```

- Each working slot has a small, fixed amount of work (Teller: about 2 customers; Loan Officer: 1 application).
- The slot ends when that work is done. Time is frozen inside a slot, but the player can still walk around.
- Special events can skip slots; the player loses those customers and their XP.
- The 2 PM cutoff falls between the 1 PM and 3 PM slots.

## How the system fits together

- A new `DayFlow` autoload runs the day. A `DaySchedule` config holds the slot list and the per-role work amounts.
- `DayFlow` announces the day with signals: `slot_started`, `slot_ended`, `slot_skipped`, `day_ended`.
- Roles call `claim_work()` when they start a slot's work and `finish_work()` when it's done.
- Events call `hold()` / `release()` to pause slot progress, or `skip_slot()` to skip a slot.
- `GameClock` becomes a display only, set to each slot's start time.
- Each role connects through its own adapter: `TellerSlotAdapter`, `LoanSlotAdapter`, `ManagerSlotAdapter`. Roles never touch each other's files or the inside of `DayFlow`.

---

## The 17 decisions

### Inside a slot

1. **Patience keeps running** in real seconds inside a slot (paused while a screen is open). A customer who gives up and leaves counts as "handled", so the slot can still end.
2. **Staff do a fixed amount of work per slot**, for example 4 customers per teller window and 2 loan decisions per loan desk. Amounts live in the config.
3. **Customers arrive one by one** within a slot, not all at once, to keep the current pacing.
4. **If nobody claims a slot, it moves on at once.** Add a debug "skip slot" key for testing.

### Shifts and roles

5. **A shift is the whole day:** clock in at Opening, clock out at Closing.
6. **No role switching mid-day.** The player chooses their role at Opening.
7. **Branch Manager** gets an **"End this slot" button** for now, until the role is redesigned.

### Saving and leaving

8. **Save only at Closing / "Start Day N+1"** for now. No mid-day saves.
9. **Going home early is only allowed between slots.** It skips the remaining work slots, and the player loses those customers and their XP.
10. **Esc → Main Menu mid-day is allowed, with a warning** that the day will restart from Opening.

### Events

11. **The event decides which slot it costs.** Break-in: skip the 9 AM slot. Lights left on: lose 1 customer from the 9 AM slot. The cutscene itself is the warning; there is no extra penalty.
12. **The armored truck holds the 9 AM slot** until it is received (Branch Manager).
13. **The Regional visit happens in the 11 AM slot** and does not hold it.

### Balance and numbers

14. **+1 Reputation per clean slot.** Existing thresholds stay for now; re-tune after a playtest.
15. **Day N = one business day**, as now.
16. **Drawer limit and report thresholds stay unchanged** for now. They will be revisited in the Teller redesign.
17. **Every role uses the same slot list**, with per-role work amounts in the config.

---

## Build plan

All of Phase A happens on **one branch** (`shared/time-slots-foundation`), worked on by **one person at a time**, behind the temporary switch `SLOTS_ENABLED` (turned on for good and removed in session 3b, along with the old clock paths). It is merged into `main` before Phase B starts.

| Session | Commits from the impact check |
|---|---|
| 1 | 1. DayFlow and DaySchedule (unused) · 2. the `SLOTS_ENABLED` switch · 3. GameClock and BusinessDay · 4. End of Day from `day_ended` |
| 2 | 5. Teller adapter · 6. Loan adapter · 7. Manager adapter · 8. timed events (truck, Regional, vacancy, witness) |
| 3 | 9. display · 10. save migration · 11. switch on and cleanup |
| 4 | **Shared toolkit and boundaries** (added 2026-11-16): role folders, shared cutscene runner, per-role config / save sections / test helpers, pre-registered autoloads and input keys. See `ROLE_BOUNDARIES.md`. |

**Phase B** starts after session 4 is merged: Liam redesigns Teller and James redesigns Loan Officer, in parallel, on small separate branches. Branch Manager stays on its adapter for now.

## Things to watch (from the impact check)

- The hidden real-seconds clock (arrivals, patience, staff service and staff loan decisions never read `GameClock`).
- The End of Day order must stay: truck → vault → loan book → demotion/review → letters → summary → save.
- Soft-locks: a slot that can never finish.
- Tests that set the time directly (about 93 tests touch time).
- Balance shock: days give about 2–3x less progress until re-tuned.
