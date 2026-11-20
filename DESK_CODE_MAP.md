# Desk-code map: `scripts/world/teller_room.gd`

**Step 1 of the desk-code extraction. Read-only map. Do not commit this file.**

- Inspected commit: **`caae289`** (`main`, "Merge loan/multi-day-applications"), on 2026-11-20.
- `teller_room.gd` at that commit: **1,343 lines** (not 1,189: see "Surprises" just below).

---

## 0. Surprises (read these first)

1. **The branch in the prompt is gone.** `shared/time-slots-foundation` was merged into `main` (PR #1) and deleted, locally and on GitHub. Everything it held is in `main`, so I inspected the latest `main` instead. I fast-forwarded your local `main` to GitHub's (`1b24fa3` → `caae289`, 9 commits from James: multi-day loan applications). None of those 9 commits touch `teller_room.gd`. No branch was created and nothing was committed.
2. **The file is 1,343 lines, not 1,189.** James's two visual pull requests added about 150 lines (world visuals, use glows, the interface motion driver). Those lines are Room-only, not role code.
3. **Tests call the room's private functions directly.** For example, `room._on_loan_officer_desk_interacted()` is called **44 times in 21 test files**. Twelve of those 21 files are not loan tests: they're shared or Teller tests. That matters for "Loan first": moving the function without leaving a stand-in would mean editing Liam's and shared test files. See section 6.
4. **The rules say a role branch must not edit `teller_room.gd`.** That's ROLE_BOUNDARIES section 5, rule 6, and the file is listed as shared. So this extraction is shared work: a `shared/...` branch, or a direct commit to `main` under the new rules, with a heads-up to James either way. The new files land in role folders that are owned (`scripts/roles/loan/` is James's), so James should agree to the Loan half, or do it.
5. **Signal order is load-bearing.** Five things listen to the teller screen's `shift_clocked_out`, and the career save must stay **last**. A careless move could reorder them. See risk 1.
6. **A stale comment.** `TellerSlotAdapter`'s header says it's "Placed in the room by teller_room.gd". It's actually placed by `SlotWiring`. It's harmless, but worth fixing when the Teller half moves.
7. **The Loan half is small.** Only about 60 lines of `teller_room.gd` are Loan-only. Most "loan desk" code in the room is really **staff** code: the three loan desk workers, breaks and the cover teller. Those belong to the room's staff system, which every role relies on.

---

## How to read the labels

| Label | Meaning |
|---|---|
| **Teller** | Only the Teller role uses it (Liam). |
| **Loan** | Only the Loan Officer role uses it (James). |
| **Manager** | Only the Branch Manager (frozen; don't move). |
| **Shared** | More than one role relies on it, *by design* (staff, the day, saves, vault). Stays in the room. |
| **Room-only** | Belongs to the room itself: nodes, camera, HUD prompt, visuals, notices, debug keys. Stays. |
| **MIXED** | Contains pieces of more than one role tangled together; explained each time. |

---

## 1. Inventory of `teller_room.gd`

### 1a. Header comment and constants

| Lines | Name | Label | Notes |
|---|---|---|---|
| 1–88 | Header doc comment | Room-only | 88 lines of history, partly out of date (it says "the Loan Desk" instead of Loan Desk 1, for example). It should be split up along with the code: each moved piece takes its own explanation with it. |
| 90–92 | `DEBUG_UNLOCK_KEY`, `DEBUG_LOAN_OFFICER_KEY`, `DEBUG_LOAN_OFFICER_REPUTATION` | Room-only | The F1 and F2 cheats. The name says "Loan Officer", but the code only raises XP and Reputation through XPManager. It isn't loan desk code. |
| 97 | `debug_cheats_enabled` (var) | Room-only | Read by SlotDayController, OnboardingFlow and 8 test uses. |
| 100 | `PLAYER_TELLER_WINDOW` | **MIXED** | The Teller's window name, but the cover teller (staff code) also uses it at line 992, and the prompt uses it. Keep it in the room, or have the cover code read it from the Teller controller. |
| 108 | `ABANDONMENT_REPUTATION_PENALTY` | **Teller** | Used only by `_on_customer_abandoned`. A number, so per Phase B rule 4 it really belongs in `TellerConfig`. **That would be a change, not a move**: see risk 4. |
| 113 | `ABANDONMENT_SCORE_PENALTY` | **Teller** | Same as above. It's defined from `TellerScreen.CUSTOMER_REQUEST_WRONG_SCORE`. |
| 152–153 | `DESK_NOTICE_SECONDS`, `_desk_notice_token` | Room-only | The timed notice over the room. |
| 157 | `WINDOW_STAFFED_TEXT` | Manager / Room | The Player Teller Window after promotion. |
| 158 | `LOAN_DESK_STAFFED_TEXT` | Manager / Room | Loan Desk 1 after promotion. It's shown at a loan desk but is about promotion, so it stays. |
| 159 | `UNASSIGNED_DESK_TEXT` | Room-only | |
| 161 | `WINDOW_COVERED_TEXT` | **MIXED** | The cover teller (staff, started by a **Loan** clock-in) at the **Teller** window. Stays with the cover code. |
| 162 | `MANAGER_DESK_REMINDER` | Manager / Room | |
| 164 | `STAFF_NPC_SCENE` | Shared | Also read by RegionalVisitSlot and ArmoredTruckVisit. |
| 483–486 | `VAULT_NEEDS_SHIFT_TEXT`, `VAULT_RECONCILED_TEXT`, `VAULT_WAITING_PROMPT` | Shared (vault) | |
| 577 | `VAULT_GAP` | Room-only | |
| 653 | `MARKER_GAP` | Room-only | |

### 1b. Node references (`@onready`; these stay as nodes in `teller_room.tscn`, only code moves)

| Line | Name → node | Label | Who else reads it |
|---|---|---|---|
| 115 | `teller_screen` → `UI/TellerScreen` | **Teller** (screen) | SlotWiring (3 uses), the vault code, the prompt, status, cover, and 11 test uses. |
| 116 | `teller_desk` → `TellerDesk` | **Teller** (desk) | Visuals, the prompt, and 36 test uses. |
| 117 | `loan_officer_desk` → `LoanOfficerDesk` | **Loan** (desk) | Visuals, the prompt, the staff desk map (line 171), and 20 test uses. |
| 118 | `loan_officer_screen` → `UI/LoanOfficerScreen` | **Loan** (screen) | SlotWiring (3 uses), `is_player_on_shift`, status, and 57 test uses. |
| 119–120 | `branch_manager_desk`, `branch_manager_screen` | Manager | Frozen. |
| 121 | `customer_queue` → `CustomerQueue` | **Teller** (the player's line) | SlotWiring (TellerSlotAdapter), the opening and lobby checks (shared), and tests through `get_node("CustomerQueue")`. |
| 122–123 | `atm`, `atm_screen` | Room-only | |
| 124–125 | `staff_layer`, `staff_break_area` | Shared | |
| 126–128 | `window1_npc_line`, `window2_line`, `window3_line` | Shared (staff lines) | `window3_line` is also the cover teller's line and Teller Window 3's. |
| 130 | `loan_desk_worker` (Loan Desk 1's worker) | **MIXED** | A *staff* worker; the Loan role pauses it at clock-in. 17 test uses. |
| 132 | `loan_desk_workers` (all three) | Shared (staff) | SlotWiring (StaffSlotPacer) and 20 test uses. |
| 133, 135 | `desk_notice`, `desk_notice_label` | Room-only | |
| 134, 140–142 | `player`, `camera`, `room_layer`, `exit_door` | Room-only | |
| 136–139 | `letter_screen`, `hud`, `pause_menu` | Room-only | |
| 144–149 | `vault_door`, `vault_transfer_screen`, `armored_truck_screen`, `end_of_day_screen`, `onboarding_screen` | Shared / Room-only | `vault_transfer_screen` is Teller-owned (the file), but it's opened by the shared vault door. |
| 167–174 | `_desk_for_slot` (desk node per staff slot) | Shared (staff) | 1 test use. |

### 1c. Other variables

| Line | Name | Label | Notes |
|---|---|---|---|
| 177 | `_staff_by_slot` | Shared (staff) | 25 test uses in 14 files. |
| 186, 188 | `cover_npc`, `_cover_leaving` | **MIXED** | The cover teller: staff, started by Loan, at the Teller window. 14 test uses. |
| 192 | `_player_desk_slots` | Shared (staff breaks) | |
| 194 | `_customer_being_served` | **Teller** | 2 test uses (`b1_clock_out_test`, `business_day_test`). |
| 202 | `_customers_awaiting_farewell` | **Teller** | |
| 206, 208 | `vault_control`, `_vault_notice_shown` | Shared (vault) | |
| 210 | `armored_visit` | Shared (event) | |
| 212 | `onboarding_flow` | Room-only | |
| 215 | `ui_motion` | Room-only | |
| 337 | `loan_seats` (an applicant seat per desk) | **MIXED (mostly Loan)** | The seats are James's `LoanDeskSeat`, but **all three** desks get one, and the two staff desks' seats are used by the staff workers. 6 test uses (`loan_walk_in`, `world_visuals`). |
| 385 | `_was_open` | Shared (the day) | |
| 637–651 | `highlighted`, `attention_markers`, `use_glows`, `zones`, `wall_signs`, `feedback`, `_prompt_key`, `_prompt_prefix` | Room-only | Visuals. |

### 1d. Functions

| Lines | Function | Label | What it does / why that label |
|---|---|---|---|
| 217–319 | `_ready()` | **MIXED** | Wires everything. Roughly: 222–243 **Teller** wiring (teller screen and queue signals); 244–245 **Loan** (desk and unlock hint); 247–251 Manager; 253–276 vault, truck, End of Day and staff lines (Shared); 278–282 **Loan Desk 1 clock signals → staff breaks** (MIXED); 289–300 **loan seats and review hooks** (Loan, with the staff workers getting seats too); 301–319 Room. |
| 321–323 | `_show_arrival_hints()` | Room-only | |
| 325–332 | `_process()` | **MIXED** | Calls `_update_player_walk_in()` (**Loan**) first, then Room and Shared updates. |
| 339–341 | `player_loan_seat()` | **Loan** | Used by SlotWiring (gives LoanSlotAdapter its seat), `loan_needs_player`, and 14 test uses in 8 files. |
| 345–351 | `_update_player_walk_in()` | **Loan** | The pile's next applicant walks in. |
| 355–362 | `_on_loan_application_shown()` | **Loan** | Seats the applicant when the review opens. |
| 365–368 | `_on_loan_decision_recorded()` | **Loan** | The applicant reacts and leaves. |
| 374–377 | `customers_still_to_arrive()` | **Teller** | Reads `customer_queue`. Used by `_describe_remaining_shift_work` and 1 test. |
| 380–381 | `is_player_on_shift()` | Shared | Asks all three screens. Used by SlotDayController, End of Day and the doormat prompt. |
| 390–395 | `_check_branch_opening()` | Shared | Restarts every line's timer at opening (player and staff lines). |
| 398–402 | `is_lobby_empty()` | Shared | |
| 407–413 | `_check_end_of_day()` | Shared | |
| 425–449 | `show_end_of_day()` | Shared | It calls `LoanBookManager.close_day()`, an autoload, not desk code, so that stays. |
| 460–465 | `_on_branch_manager_demoted()` | Manager / Shared | |
| 469–478 | `_on_next_day_requested()`, `_on_shift_completed()`, `_on_staff_customer_served()` | Shared | `_on_shift_completed` is connected to **all three** screens' clock-outs. |
| 491–512 | `_on_vault_door_interacted()` | **MIXED** | One door for three roles: a teller's transfer, the Manager's reconciliation and the armored truck. It stays shared and reads the teller screen's shift state. |
| 516–547 | `_on_vault_ready_to_open()`, `_on_armored_truck_screen_closed()`, `_on_vault_call_called_off()`, `_update_vault_notice()` | Shared (vault) | |
| 552–595 | `vault_witness_candidates()`, `_line_for_slot()`, `vault_witness_spot()`, `route_to_vault()` | Shared (vault and staff) | Used by VaultDualControl and ArmoredTruckSlot. |
| 599–602 | `room_bounds()` | Room-only | |
| 607–632 | `_interactables()`, `interactable_in_range()`, `_update_interaction_prompt()` | Room-only | |
| 655–720 | `_usable_prompt_prefix()`, `_build_world_visuals()`, `_highlight_sprite()`, `_highlight_box()`, `_add_marker()`, `_set_highlighted()`, `_on_camera_zoom_changed()` | Room-only | Visuals. |
| 724–725 | `teller_needs_player()` | **Teller** | The marker over the teller window. |
| 727–729 | `loan_needs_player()` | **Loan** | The marker over Loan Desk 1. |
| 731–732 | `manager_needs_player()` | Manager | |
| 736–741 | `vault_attention()` | **MIXED** | The truck (Manager) or the drawer over its limit (**Teller**, `teller_screen.drawer_limit_warning()`). |
| 744–768 | `atm_in_use()`, `vault_in_use()`, `update_use_glows()`, `_update_attention_markers()` | Room-only | |
| 772–811 | `interaction_prompt_text()` | **MIXED** | One function with a branch per desk: 774–782 **Teller**, 783–791 **Loan**, the rest Room, Manager and vault. The Teller branch also checks the cover teller (MIXED). |
| 817–834 | `describe_shift_status()` | **MIXED** | 819–826 **Teller** part, 827–829 **Loan** part, 830–831 Manager part. |
| 839–843 | `_hint_first_customer()` | **Teller** | |
| 848–882 | `_place_staff()`, `_place_slot_staff()`, `_assign_staff_to_work()` | Shared (staff) | It gives each loan desk worker its staff member (881: `work_source`). |
| 890–891 | `staff_window_pressure()` | **MIXED** | It reads the *staff* lines, but its only use is pacing the **Teller**'s own line (`customer_queue.arrival_pressure`). 6 test uses (`player_line_pressure_test`). I suggest keeping it in the room as staff information that the Teller reads. |
| 897–913 | `_update_staff_lines()`, `_on_schedule_confirmed()` | Shared (staff) | |
| 918–962 | `_on_player_clocked_in(slot)`, `_on_player_clocked_out(slot)` | **MIXED** | Generic names, but only bound to Loan Desk 1. They do three things: staff breaks (Shared), pausing and releasing Loan Desk 1's worker and its seat (Loan and staff), and starting and ending the cover teller (staff at the Teller window). They also call `XPManager.begin_/end_player_shift`, the held-promotion rule. 1 test use each. |
| 967–1031 | `is_window_covered()`, `_start_cover()`, `_end_cover()`, `_send_cover_to_break()`, `_dismiss_cover()`, `_end_cover_now()` | **MIXED** | The cover teller: a staff member at the **Teller** window while the player works **Loan** Desk 1. It reads `teller_screen.shift_state` (line 975). I suggest keeping it in the room for now (see section 5). |
| 1033–1057 | `_desk_spot()`, `_break_spot_for()`, `_route_to_break()` | Shared (staff) | 3–5 test uses each. |
| 1069–1080 | `_on_teller_desk_interacted()` | **MIXED (mostly Teller)** | 1072–1077: the promotion and cover gates (Room and staff); 1078–1080: open the teller screen with the front customer (**Teller**). 3 test uses, one in `teller_suite.gd`. |
| 1086–1137 | `_on_teller_customer_request_satisfied()`, `_on_teller_customer_left_unfixed()`, `_on_teller_complaint_resolved()`, `_on_teller_customer_refused()`, `_serve_current_customer()` | **Teller** | The serving flow. |
| 1143–1147 | `_on_teller_screen_closed()` | **Teller** | Farewells. 1 test use (`world_visuals_test`). |
| 1157–1178 | `_describe_remaining_shift_work()` | **Teller** | The clock-out gate (reads `ShiftSlotAdapter.clock_out_refusal()`). Also used by the prompt. |
| 1183–1185 | `_on_teller_shift_clocked_out()` | **Teller** | |
| 1193–1204 | `_on_customer_abandoned()` | **Teller** | Score, Reputation, the history record and the screen note. |
| 1210–1218 | `_on_loan_officer_desk_interacted()` | **MIXED (mostly Loan)** | 1213–1215: the promotion gate (Room and Manager); 1216–1218: the unlock check, then open the screen (**Loan**). **44 test uses in 21 files.** |
| 1220–1221 | `_on_loan_officer_unlocked()` | **Loan** | The one-time hint. |
| 1225–1249 | `_staffed_desk_text()`, `_show_desk_notice()`, `_show_notice()`, `show_timed_notice()`, `_hide_desk_notice()` | Room-only | `show_timed_notice` is used by SlotDayController and ArmoredTruckVisit. |
| 1253–1267 | `_on_branch_manager_desk_interacted()`, `_on_branch_manager_unlocked()`, `_on_branch_manager_clocked_in()` | Manager | Frozen. |
| 1272–1275 | `save_career()` | Shared | Used by the pause menu, OnboardingFlow and 6 test uses. |
| 1284–1297 | `_apply_branch_manager_desks()`, `_update_branch_manager_desk_availability()` | Manager / Shared | |
| 1304–1307 | `_on_atm_interacted()` | Room-only | |
| 1320–1343 | `_unhandled_input()`, `apply_debug_key()` | Room-only | F1 and F2. |

**Signals:** `teller_room.gd` declares **no signals of its own**. It only connects to other nodes' signals.

---

## 2. Other files that mix roles (listed, not mapped)

| File | What is mixed |
|---|---|
| `scripts/core/slot_wiring.gd` (shared) | It hands each role's adapter its pieces: Teller (`customer_queue`, `teller_screen`), Loan (`loan_officer_screen`, `player_loan_seat()`), and the clock signals of all three screens. That's mixed on purpose, as the one place the roles get connected. |
| `scripts/ui/hud.gd` (shared) | The slot line and status are role-neutral (through SlotStatus), but a few references to loan and manager unlock hints and statuses remain. |
| `scripts/ui/end_of_day_screen.gd` (shared) | The summary has a Teller section (after-cutoff transactions) and a Loan section (loan events). |
| `scripts/ui/branch_manager_screen.gd` (Manager) | Reads teller and loan work for its summary, Approvals and staff review. Manager by nature; frozen. |
| `scripts/ui/approvals_screen.gd`, `staff_review_screen.gd`, `scripts/autoload/staff_review_manager.gd` | Manager screens that judge teller **and** loan records. Mixed by design. |
| `scripts/world/npc_customer_line.gd` (shared) | Staff teller lines. It's also the cover teller's line on the player's lane (Teller window). |
| `scripts/world/npc_loan_desk_worker.gd` (James's) | Staff loan desks, including Loan Desk 1's worker, which the room pauses for the player. A little manager awareness. |
| `scripts/world/vault_dual_control.gd` (shared) | The vault door's witness rules for the Teller's transfers, the Manager's reconciliation and the truck. |
| `scripts/autoload/xp_manager.gd`, `report_manager.gd`, `history_manager.gd`, `schedule_manager.gd`, `business_day.gd` | Career-wide systems with teller, loan and manager branches inside (unlocks, reports, record roles, desk slots, the day's counts). Mixed by design; not desk code. |
| `scripts/npc/staff_npc.gd` (shared) | Teller and loan staff behaviour together (`work_source`). |
| `scripts/ui/teller_screen.gd` (Liam's, 1,698 lines) | **Not mixed.** It's pure Teller (only 1 mention of the manager). It's just big. |

---

## 3. Connections: what each Teller and Loan piece touches

### Loan pieces

| Piece | Calls or reads elsewhere | Called by | Would break if moved naively? |
|---|---|---|---|
| `loan_seats` + seat creation (`_ready` 289–297) | `LoanDeskSeat.new()`, `staff_layer` (seats walk applicants on the Staff layer), each worker's `slot_name`, `seat` and `active` | — | **Yes, if created after `SlotWiring.install()`**: SlotWiring reads `room.player_loan_seat()` at the end of `_ready()`. The seats must exist first. They're also given to the **staff** workers, so their creation is partly staff wiring. |
| `player_loan_seat()` | `loan_seats` | SlotWiring, `loan_needs_player`, `_update_player_walk_in`, the two review hooks, **14 test uses in 8 files** | Yes, for tests and SlotWiring, unless the room keeps a one-line stand-in. |
| `_update_player_walk_in()` | `loan_officer_screen.is_clocked_in()`, `.applications_left()`, `LoanDeskManager.current_player_application()`, seat | `_process()` (first thing each frame) | **Frame order**: today it runs before the prompt update. If the new node runs it from its own `_process()`, it runs after the room's in the same frame. That's a tiny ordering change, so call it from the room's `_process()` to stay identical. |
| `_on_loan_application_shown()` / `_on_loan_decision_recorded()` | seat | Connected in `_ready` to `loan_officer_screen.loan_review_screen` signals | No, if the connections move with them. |
| `_on_loan_officer_desk_interacted()` | `loan_officer_screen.visible` / `show_screen()`, `XPManager`, `_show_desk_notice()` (Room) | `loan_officer_desk.interacted`, **44 test calls in 21 files** | **Yes, for tests**: 12 of those 21 files aren't loan tests. The promotion gate also uses Room helpers. |
| `_on_loan_officer_unlocked()` | `hud.show_hint_once()` | `XPManager.loan_officer_unlocked` | No. |
| `loan_needs_player()` | seat, `loan_officer_screen` | `_update_attention_markers()` | No, if the room asks the new node. |
| The Loan branch of `interaction_prompt_text()` and `describe_shift_status()` | `loan_officer_screen`, `XPManager` thresholds | The room's prompt and HUD line; 18 and 7 test uses of the whole functions | No, if the room's function still exists and asks the node for its part. |

**Not moving with Loan:** `loan_desk_worker` / `loan_desk_workers`, `_on_player_clocked_in/out`, and the cover teller. They're staff code that both roles' days depend on (SlotWiring, StaffSlotPacer, vault witnesses, promotion and demotion).

### Teller pieces

| Piece | Calls or reads elsewhere | Called by | Would break if moved naively? |
|---|---|---|---|
| Teller wiring in `_ready` (222–243) | `teller_screen` signals → HUD hints, `customer_queue.start_shift/end_shift`, `XPManager.begin/end_player_shift`, `InterviewManager.begin/end_teller_shift`, `_on_shift_completed` (save), `remaining_shift_work`, `arrival_pressure` | — | **Yes, if the order of the `shift_clocked_out` connections changes.** The order today: `customer_queue.end_shift` → `_on_teller_shift_clocked_out` → `XPManager.end_player_shift` → `InterviewManager.end_teller_shift` → `_on_shift_completed` (**save, last**). Then `SlotWiring` adds `PlayerShift.report_clock_out` after all of them. |
| `_customer_being_served`, `_customers_awaiting_farewell` | — | The serving flow; **2 test reads** | Yes, for 2 tests. |
| `_on_teller_desk_interacted()` | `teller_screen.visible` / `show_screen()`, `customer_queue.get_front_customer()`, `_hint_first_customer()`, the cover and promotion gates (Room and staff) | `teller_desk.interacted`; **3 test calls** (one in `teller_suite.gd`, which every teller test uses indirectly) | Yes, for 3 places. The gates must stay in the room. |
| The serving flow (1086–1147) | `customer_queue.serve_front_customer()` / `send_customer_off()`, `teller_screen.advance_to_customer()`, `BusinessDay.note_customer_served_by_player()` | `teller_screen` signals | No, if the connections move too. |
| `_describe_remaining_shift_work()` | `ShiftSlotAdapter.clock_out_refusal()`, `customer_queue`, `teller_screen.has_uncompleted_transactions()`, `customers_still_to_arrive()` | `teller_screen.remaining_shift_work` (a Callable), the Teller prompt branch | No, if the Callable points at the new node. |
| `customers_still_to_arrive()` | `BusinessDay.doors_closed()`, `customer_queue` | the above, **1 test** | Yes, for 1 test. |
| `_on_customer_abandoned()` | ScoreManager, ReputationManager, HistoryManager, `teller_screen.note_customer_abandoned()` | `customer_queue.customer_abandoned` | No. Nothing else in `scripts/` listens to that signal on the player's queue. |
| `_on_teller_shift_clocked_out()` | `teller_screen.set_serving_customer(null)` | `teller_screen.shift_clocked_out` (2nd in order) | **Order**, as above. |
| `_hint_first_customer()` | `hud`, `KycPolicy.requires_id()` | The serving flow | No. It needs a reference to the HUD. |
| `teller_needs_player()`, the Teller branch of the prompt and status | `teller_screen.shift_state`, `customer_queue.queue` | Room markers, prompt, HUD | No, if the room asks the new node. |
| `staff_window_pressure()` (stays) | the staff lines | `customer_queue.arrival_pressure` | — |

**Reads of the Teller from shared code that stay in the room:**
- the vault door: `teller_screen.shift_state`, at lines 498 and 806
- `vault_attention()`: `drawer_limit_warning()`
- `is_player_on_shift()`
- the cover teller (line 975)

These would read through the Teller controller later, or keep reading `teller_screen` directly, which still exists as a node.

---

## 4. How the slot adapters connect to `teller_room.gd` today

**None of the three adapters knows about the room.** `SlotWiring.install(room)`, the last line of the room's `_ready()`, creates each one as a child of the room and hands it what it needs:

| Adapter | Given by SlotWiring | Talks to |
|---|---|---|
| `TellerSlotAdapter` (`scripts/roles/teller/`) | `queue = room.customer_queue`, `screen = room.teller_screen` | DayFlow (claim, finish, skip), PlayerShift, the queue's `begin_batch()` |
| `LoanSlotAdapter` (`scripts/roles/loan/`) | `screen = room.loan_officer_screen`, `seat = room.player_loan_seat()` | DayFlow, PlayerShift, the screen's `applications_per_shift`, the seat's `send_off()` on a skip |
| `ManagerSlotAdapter` (`scripts/roles/manager/`) | nothing (it builds its own `EndSlotBar`) | DayFlow, PlayerShift, ReputationManager |

SlotWiring also connects each screen's `shift_clocked_in/out` to `PlayerShift.report_clock_in/out(role)`, after the room's own connections.

So an adapter only needs the room's **node references** (`customer_queue`, `teller_screen`, `loan_officer_screen`) and the **seat**. If those stay reachable at the same names, SlotWiring and the adapters need **no change**.

---

## 5. Proposed destination

### The design (the simplest one I can see)

Make one small **desk controller** per role, in that role's folder. Each controller is a plain `Node` that the room creates in `_ready()`, the same way it already creates `VaultDualControl`, `ArmoredTruckVisit` and `OnboardingFlow` (a name, `room = self`, `add_child`). The room keeps every node in the scene, every shared system and the gates that are about promotion or staff. It talks to each controller through a handful of plain functions.

```
teller_room.gd (shared)           scripts/roles/loan/loan_desk_controller.gd (James)
  _ready():                          var room: TellerRoom
    loan_desk = LoanDeskController   setup(): makes the 3 seats, hooks the review screen
    loan_desk.setup()  # before        open_desk()      # unlock check + show_screen
    SlotWiring.install(self)           update_walk_in() # called from room._process
  _process(): loan_desk.update_walk_in()   needs_player() -> bool
  prompt / status / markers ask:     prompt_text(key) -> String
    loan_desk.prompt_text(key) ...   status_part() -> String
                                     player_seat() -> LoanDeskSeat

                                  scripts/roles/teller/teller_desk_controller.gd (Liam)
                                     var room: TellerRoom
                                     setup(): connects the teller screen + queue signals,
                                              IN THE SAME ORDER as today
                                     open_desk()      # front customer + show_screen + hint
                                     remaining_shift_work() -> String
                                     customers_still_to_arrive() -> int
                                     needs_player(), prompt_text(key), status_part()
```

**Why this shape:**
- **Each role's code lives in a file that role owns.** James never opens the Teller file, and Liam never opens the Loan one.
- **The room still owns the nodes,** so `teller_room.tscn`, every node path (`room.get_node("CustomerQueue")`, `"UI/TellerScreen"`), SlotWiring and the adapters stay unchanged.
- **The gates stay in the room** (promotion notice, cover-teller notice), because they're about the Manager and staff, not the role. The room checks them first, then calls `teller_desk.open_desk()` / `loan_desk.open_desk()`.
- **No new autoload, input action or scene,** so it stays within the Phase B rules (apart from the shared-file edit itself, see Surprise 4).

**Why not put it in the existing slot adapters:** they're each role's link to DayFlow (time slots). Mixing desk interaction into them would make one file do two jobs, and SlotWiring creates them *after* the room needs the seats.

### Where each piece goes

| Piece (lines) | Destination |
|---|---|
| `loan_seats`, `player_loan_seat()`, seat creation (289–297), `_update_player_walk_in()`, `_on_loan_application_shown()`, `_on_loan_decision_recorded()`, review hooks (298–300) | `scripts/roles/loan/loan_desk_controller.gd` (new) |
| `_on_loan_officer_desk_interacted()` lines 1216–1218 (unlock check + `show_screen()`), `_on_loan_officer_unlocked()`, `loan_needs_player()`, the Loan branch of the prompt (786–791) and of the status (827–829) | the same file |
| `_on_loan_officer_desk_interacted()` lines 1211–1215 (re-entry guard and promotion gate) | stays in the room, then calls `loan_desk.open_desk()` |
| Teller wiring (222–243), `_customer_being_served`, `_customers_awaiting_farewell`, the serving flow (1086–1147), `_describe_remaining_shift_work()`, `_on_teller_shift_clocked_out()`, `_on_customer_abandoned()` + its two constants, `customers_still_to_arrive()`, `_hint_first_customer()`, `teller_needs_player()`, the Teller branch of the prompt (779–782) and status (819–826) | `scripts/roles/teller/teller_desk_controller.gd` (new) |
| `_on_teller_desk_interacted()` lines 1070–1077 (guard, promotion and cover gates) | stays in the room, then calls `teller_desk_controller.open_desk()` |
| `PLAYER_TELLER_WINDOW` | stays in the room (the cover teller and the prompt use it). Or it moves to the Teller controller and the room reads `TellerDeskController.PLAYER_TELLER_WINDOW`. Your call (question 6). |
| `staff_window_pressure()`, the cover teller, `_on_player_clocked_in/out`, staff placement and routes, vault, End of Day, visuals, debug keys | **stay in the room** (Shared or Room-only). A later, separate "staff floor" extraction could take the staff and cover code (about 210 lines). That's out of scope here. |

### Keeping the old names working (recommended for the pure move)

Leave **one-line stand-ins** in the room for the names that tests and SlotWiring call:

```gdscript
func player_loan_seat() -> LoanDeskSeat: return loan_desk.player_seat()
func _on_loan_officer_desk_interacted() -> void: ...gate...; loan_desk.open_desk()   # already in the room
func customers_still_to_arrive() -> int: return teller_desk_controller.customers_still_to_arrive()
```

With stand-ins, the move needs **almost no test edits** (section 6). They can be removed later, in their own commit, when each owner updates their own tests.

---

## 6. Tests

### Shared helpers (`tests/support/...`)

| Helper | References to moved pieces | Change needed? |
|---|---|---|
| `support/shared/room_suite.gd` | None of the moved pieces (it uses `letter_screen`, `end_of_day_screen`, the vault door and the window lines) | No |
| `support/teller/teller_suite.gd` | `room._on_teller_desk_interacted()` (line 66), `room.get_node("UI/TellerScreen")` | No, if the room keeps `_on_teller_desk_interacted` (it does, as the gate) |
| `support/loan/loan_suite.gd` | `room.vault_transfer_screen` only | No |
| `support/shared/character_fx_suite.gd` | `room._staff_by_slot` (stays) | No |

### Test files that use the pieces being moved

| Room name used | Files | Uses | If a stand-in is kept | If not |
|---|---|---|---|---|
| `_on_loan_officer_desk_interacted()` | 21 (business_day, cover_teller, game_clock, loan_book, loan_desks, loan_edge, loan_pile, loan_request, loan_return, loan_slots, loan_walk_in, loan_worksheet, manager_slots, regional_review, role_days, save_load, shift_slots, slot_status, teller_slots, ui_motion, world_visuals) | 44 | 0 (the function stays as the gate) | 0 (same) |
| `player_loan_seat()` | 8 (business_day, loan_edge, loan_request, loan_return, loan_slots, loan_walk_in, role_days, world_visuals) | 14 | 0 | 14 lines |
| `loan_seats` | 2 (loan_walk_in, world_visuals) | 6 | 0 if the room keeps a `loan_seats` stand-in (a getter) | 6 lines |
| `_on_teller_desk_interacted()` | 3 (cover_teller, regional_review, teller_suite) | 3 | 0 | 0 |
| `_customer_being_served` | 2 (b1_clock_out, business_day) | 2 | **2 lines** (a private variable; a stand-in property is possible but odd) | 2 lines |
| `_on_teller_screen_closed()` | 1 (world_visuals) | 1 | 0 with a stand-in | 1 line |
| `customers_still_to_arrive()` | 1 (business_day) | 1 | 0 | 1 line |
| `staff_window_pressure()` (stays) | 1 | 6 | 0 | 0 |
| `customer_queue`, `teller_screen`, `loan_officer_screen`, desks and workers (all stay) | many | many | 0 | 0 |

**Estimate:**
- **With stand-ins:** about **2 test lines in 2 files** (`_customer_being_served`), or none if a stand-in property is added for it too.
- **Without stand-ins:** about **25 lines in about 12 files**, and some of those files are owned by the other role or shared (`world_visuals_test`, `business_day_test` and `role_days_test` hold both Loan and Teller lines).

**New tests:** two small suites that build the room and check each controller exists and is wired: `tests/loan_desk_controller_test.gd` (James's) and `tests/teller_desk_controller_test.gd` (Liam's). That follows the rule to "add permanent tests when you verify". The existing ~780 tests are the real proof that nothing changed.

---

## 7. Proposed commit plan

Every commit: full `./run_tests.sh` (`== ALL PASSED`) before committing, then check CI after pushing. The work goes on a shared branch (or `main` if you both say so), with a heads-up to James before starting.

**Session A: Loan** (branch `shared/loan-desk-extraction`, or James does it on his side)
1. **Add `LoanDeskController` with the seats and the walk-in.** Move `loan_seats`, seat creation, `player_loan_seat()`, `_update_player_walk_in()` and the two review hooks. The room creates the controller *before* `SlotWiring.install()` and keeps `player_loan_seat()` and `loan_seats` as one-line stand-ins. `_process()` calls `loan_desk.update_walk_in()` at the same spot. Expected test edits: 0.
2. **Move the desk interaction, unlock hint, marker check and prompt and status parts.** The room's `_on_loan_officer_desk_interacted()` keeps its guard and promotion gate and calls `open_desk()`. `interaction_prompt_text()` and `describe_shift_status()` ask the controller for the Loan part. Expected test edits: 0.
3. **Add `tests/loan_desk_controller_test.gd`; update CLAUDE.md** (Loan Officer and room sections) and the room's header comment.

**Session B: Teller** (branch `shared/teller-desk-extraction`)
4. **Add `TellerDeskController` with the serving flow.** Move `_customer_being_served`, the farewells, the five serving handlers and `_on_teller_screen_closed()`, plus their signal connections. Expected test edits: 2 lines (`_customer_being_served`), or 0 with a stand-in.
5. **Move the clock-out gate, abandonment, hints and `customers_still_to_arrive()`.** This includes the `shift_clocked_in/out` wiring, **in the same order** (write a test that records the order and checks the save comes last). `teller_screen.remaining_shift_work` points at the controller.
6. **Move the prompt, status and marker parts; the room's `_on_teller_desk_interacted()` keeps only its gates.**
7. **Add `tests/teller_desk_controller_test.gd`; update CLAUDE.md** (Teller and room sections), fix the stale `TellerSlotAdapter` comment, and trim the room's header comment.

**Optional Session C** (each owner, on their own role branch, later): remove the stand-ins and point each role's own tests at the controller. Liam does the Teller tests and James the Loan tests. Shared test files get a heads-up.

**Where to split sessions:** A and B are each one session (3–4 commits, about 4 full test runs of 7–8 minutes each). Don't combine them. If Session A goes smoothly, B can follow the same pattern.

---

## 8. Risks and open questions for you to decide

1. **Signal order (risk).** Moving the teller screen's `shift_clocked_out` connections into the controller must keep today's order, with the save last: `customer_queue.end_shift` → `_on_teller_shift_clocked_out` → `XPManager.end_player_shift` → `InterviewManager.end_teller_shift` → `_on_shift_completed` (save) → `PlayerShift.report_clock_out` (SlotWiring). Suggestion: the controller's `setup()` connects them in that exact order, and a test checks it.
2. **Which branch?** The prompt's branch no longer exists. Options: a new `shared/...` branch from `main` (recommended), or straight to `main` under the new rules. My agent rules say I commit to `main` only if the prompt says "commit to main" in words.
3. **Who does the Loan half?** The new file is in James's folder and the code is his role's. Should James's agent do Session A, or yours with his OK? Either way, the rules need a heads-up to James before `teller_room.gd` is edited.
4. **Abandonment numbers (−3 Score, −2 Reputation).** Phase B rule 4 says role numbers live in `TellerConfig`. Moving them there is tidy, but it is a change, not a pure move. Do it now in its own commit (the values stay the same), or later?
5. **Keep stand-ins for old names?** Recommended for the pure move (almost no test edits). Remove them later per role.
6. **`PLAYER_TELLER_WINDOW`:** keep it in the room (the cover teller uses it) or move it to the Teller controller?
7. **The cover teller, `_on_player_clocked_in/out` and `loan_desk_worker`:** these are staff code that sits between Loan and Teller. I suggest leaving them in the room for now and maybe doing a later "staff floor" extraction. Do you agree?
8. **`staff_window_pressure()`:** it reads staff lines but only paces the Teller's line. Keep it in the room (suggested) or move it to Teller?
9. **Frame order of the walk-in:** have the room's `_process()` call `loan_desk.update_walk_in()` at the same spot (suggested, identical behaviour), or let the controller run its own `_process()` (simpler, but one frame step later in order)?
10. **The vault door and `vault_attention()`** read the teller screen directly. They can keep doing that (the node stays). Fine, or should they go through the Teller controller?

---

## 9. Expected size of `teller_room.gd`

| After | Lines (approx.) | How |
|---|---|---|
| Today | 1,343 | |
| Loan move | ~1,290 | about 65 lines out, about 12 back (creating the controller, stand-ins, calls) |
| Teller move | ~1,100–1,120 | about 220 lines out, about 25 back |
| Optional: stand-ins removed, header comment trimmed | ~1,000–1,050 | |

**Plain truth:** the two moves take the room down by about **15–18%**, not by half. What remains is mostly **not role code**: staff placement, breaks and the cover teller (~210 lines), the vault door and witnesses (~120), the world visuals James added (~170), End of Day and the day checks (~80), and the 88-line header comment. Making the room genuinely small would take later extractions of the staff floor and the visuals. Those are shared work, outside this plan.

---

## Notes for the next session

- Start from `main` at or after **`caae289`**. Re-check `wc -l scripts/world/teller_room.gd` and `git log -- scripts/world/teller_room.gd`, because James's visual work has changed this file twice in a week. If it moved, re-check the line numbers above.
- Send the heads-up to James first (the room is shared, and the Loan file goes in his folder).
- Create each controller in the room's `_ready()` **before** `SlotWiring.install(self)` (SlotWiring reads the seat).
- Keep `_process()` order identical: the walk-in first.
- Keep the teller clock-out connection order identical, with the save last (risk 1). Add a test for it.
- Commit `.uid` files with each new script (`*.gd.uid` is tracked).
- The full `./run_tests.sh` takes about 7–8 minutes now (~780 tests). Run it before every commit.
- Update CLAUDE.md in the same commits (the room, Teller and Loan sections), and fix the stale "Placed in the room by teller_room.gd" comment in `TellerSlotAdapter`.
- This file (`DESK_CODE_MAP.md`) is untracked. Don't `git add -A` it by accident.
