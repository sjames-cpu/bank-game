# BankSim — Development Log

Living record of what's been built, session by session. Update this alongside `CLAUDE.md` as new work lands; `CLAUDE.md` describes current architecture, this file describes how it got there.

## Where things stand (as of 2026-09-15)

BankSim has grown from a single teller-desk vertical slice into a multi-role bank simulation:

- **Roles/desks**: Teller (deposits/withdrawals, complaints), Loan Officer (credit checks, application grading), Branch Manager (staff scheduling, approvals, vault reconciliation), plus a standalone ATM.
- **World systems**: a customer queue with NPCs that walk in, wait, and can abandon the line; a day/night cycle.
- **Shared data layer**: `AccountManager` autoload so Teller and ATM operate on the same account records.
- **Progression**: `ScoreManager`, `ReputationManager`, `XPManager`, `HistoryManager` (decision/event log), `ScheduleManager`.
- **Content**: a rewritten 9-question hiring interview and a set of realistic customer complaint scenarios.
- **Polish**: a shared `banking_theme.tres` across all screens, panel-overflow fixes, and a round of exploit-hardening.

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

---

## Notes for next session

- No `.csproj`/`.sln` yet — everything is still GDScript despite the project being configured for .NET.
- No persistence: `AccountManager`, `ScoreManager`, `ReputationManager`, `HistoryManager`, etc. are all in-memory only, reset on relaunch.
- `is_on_probation` (from `InterviewManager`) is tracked but not yet used by gameplay.
- No automated tests/CI — verification is manual, via the Godot editor's Play/Run.
