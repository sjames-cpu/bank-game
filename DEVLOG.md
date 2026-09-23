# BankSim — Development Log

Living record of what's been built, session by session. Update this alongside `CLAUDE.md` as new work lands; `CLAUDE.md` describes current architecture, this file describes how it got there.

## Where things stand (as of 2026-09-16)

BankSim has grown from a single teller-desk vertical slice into a multi-role bank simulation with a proper branch floor plan and a real visual identity:

- **Roles/desks**: Teller (deposits/withdrawals, complaints), Loan Officer (credit checks, application grading), Branch Manager (staff scheduling, approvals, vault reconciliation), plus a standalone ATM.
- **World layout**: a full branch floor plan — a back-office row (Vault, Manager's Office, Conference Room, Accounting) plus one open floor (Marketing/Loan bullpen, Teller Area, Waiting Lounge) — built procedurally in `room_builder.gd`.
- **Visual identity**: a modern-office palette (grey-blue open floor, brick-and-wood back offices, cream desks with monitors) with ambient props (plants, wall clock, archive bookshelf, printer, whiteboards, water cooler), and a 4-direction idle/walk animation for the player.
- **World systems**: a customer queue with NPCs that walk in, wait, and can abandon the line; a day/night cycle.
- **Shared data layer**: `AccountManager` autoload so Teller and ATM operate on the same account records.
- **Progression**: `ScoreManager`, `ReputationManager`, `XPManager`, `HistoryManager` (decision/event log), `ScheduleManager`.
- **Content**: a set of realistic customer complaint scenarios. The hiring interview content exists (`InterviewQuestionsData`) but is disabled as the entry point — see Session 4.
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

## Session 4 — Sep 16, 2026: Player animation, full branch layout, modern-office redesign
*(commit `039762e`)*

- **Player animation** — the player is now an `AnimatedSprite2D` with idle/walk loops for down/up/side facing (side mirrors for left via `flip_h`), driven by a facing-state tracker in `player_movement.gd` that only restarts the animation when the resolved state actually changes (no restart-jitter) and scales walk speed to actual movement speed.
- **Full branch floor plan** — `teller_room`'s single small placeholder room is replaced with a proper multi-zone layout built procedurally in `room_builder.gd`: a back-office row (Vault / Manager's Office / Conference Room / Accounting), each with one door gap, walled off from one open floor (Marketing+Loan bullpen, Teller Area, Waiting Lounge near the entrance). Every desk, the ATM, and the customer queue moved to match. `Camera2D` zoom dropped from 2x to 1x, which had been magnifying everything more than intended.
- **Visual redesign** — went through two full palette passes (a navy/gold "traditional bank" look, then a muted retro-tile look) before landing on a modern-office identity matching a floor-plan reference image: grey-blue open floor and light walls in the bullpen, brick walls and wood floors in the back offices, cream desks with blue-screened monitors and black rolling chairs. Added ambient props the reference suggested: potted plants, a wall clock, an archive bookshelf, a printer, wall-mounted whiteboards, and a water cooler. Every piece kept its original footprint/position from the layout pass, so only the artwork changed.
- **Interview disabled as the entry point** — `run/main_scene` now boots straight into `teller_room` instead of the hiring interview, since the interview is being rebuilt from scratch. `InterviewManager`/`interview_screen` are untouched and still work standalone; `is_on_probation` stays at its default `false` until it's reconnected.
- **Tooling**: added three Godot-specialist subagents (`godot-specialist`, `godot-gdscript-specialist`, `godot-shader-specialist`) to `.claude/agents/`, cherry-picked from the open-source Claude-Code-Game-Studios framework for architecture/code-quality/shader consults going forward.

---

## Notes for next session

- No `.csproj`/`.sln` yet — everything is still GDScript despite the project being configured for .NET.
- No persistence: `AccountManager`, `ScoreManager`, `ReputationManager`, `HistoryManager`, etc. are all in-memory only, reset on relaunch.
- The hiring interview needs to be rebuilt from scratch and reconnected as (or after) the entry point; `is_on_probation` is unused until then.
- The redesigned office reads sparser than the reference it's modeled on — same furniture count as before, just reskinned. Worth revisiting if it should be denser.
- No automated tests/CI — verification is manual, via the Godot editor's Play/Run.
