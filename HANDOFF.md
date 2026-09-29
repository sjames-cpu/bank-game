# BankSim Handoff: Bug Fixes and the Path to a Sellable Bank-Training Simulation

**Prepared:** 2026-09-29 &nbsp;|&nbsp; **Repo state:** `main`, 9 commits, last commit 2026-09-23 &nbsp;|&nbsp; **Engine:** Godot 4.7.2 (GDScript only)

This document hands off two workstreams to whoever picks the project up next:

1. **Stabilize.** Fix the bugs and design flaws in the current vertical slice (Part 1).
2. **Productize.** Turn the game into a simulation that community banks and credit unions would pay for as staff training, using real roles, regulations and scenarios (Parts 2 to 8).

If you read nothing else, read the [Executive summary](#executive-summary) and the [Phased roadmap](#7-phased-roadmap).

---

## How to read the confidence tags

Every regulatory or market fact below carries a tag. **Do not put an untagged or `[UNV]` fact into the game or a sales deck without checking it.**

| Tag | Meaning |
|---|---|
| `[SRC]` | A research agent read the rule text or an official agency page (Cornell LII, CFPB, FinCEN, Federal Reserve, OCC, FDIC, uscurrency.gov). Still confirm with a compliance SME before shipping. |
| `[2ND]` | Secondary source only: law-firm summary, trade press, vendor page, or a search snippet. Treat as a lead. |
| `[UNV]` | Unverified: general knowledge, practice, or the agent's own inference. |
| `[CODE]` | Verified by reading this repo's code in this session. |
| `[RUN]` | Verified by actually running something in Godot 4.7.2 in this session. |

**Research limits.** Several primary sources (eCFR, Federal Register, the FFIEC BSA/AML manual) redirected to an interstitial page or returned 403 to the research agents, so a number of 2025-2026 rule changes rest on law-firm summaries. The agents also hit a session rate limit partway through; the final reports say what was cut short. The rules below were current as of 2026-09-29 and several are actively changing (see [3.5](#35-regulatory-flux-watch-list)).

**This game must never claim to be legal advice or a compliance program.** Every scenario needs sign-off from a qualified bank compliance professional before it ships (see [Open questions](#9-open-questions)).

---

## Executive summary

**What exists.** BankSim is a working GDScript slice: a top-down branch floor plan, a teller desk (deposits, withdrawals, drawer counts, complaints), a customer queue with walk-in NPCs, a Loan Officer desk, a Branch Manager desk (scheduling, approvals, vault count), an ATM, and XP/reputation progression. It boots cleanly in Godot 4.7.2 (headless run of 300 frames produced no errors or warnings [RUN]). It is a game, not yet a training product: scoring is driven almost entirely by cash-drawer accuracy, and none of the scenarios test the judgment calls banks actually train on.

**The product opportunity.** Banks must document training for BSA/AML, the Bank Protection Act, information security and, to get liability protection, elder-exploitation reporting under the Senior Safe Act `[SRC/2ND]`. Existing incumbents sell ~30-minute quiz-style courses; the closest gamified competitor is BVS, and VR vendors cover soft skills only `[2ND]`. A consequence-driven branch-day simulation focused on teller compliance judgment looks like an open niche, but that is the research team's inference, not a proven fact `[UNV]`.

**Recommended positioning.** Sell to community banks and credit unions under about $1B in assets, as a *supplement* to their existing LMS courses, for new-teller onboarding and for practicing BSA, robbery-response and elder-exploitation judgment. Distribute through state bankers associations and credit union leagues where possible.

**The five decisions that matter most:**

1. **Fix the scoring model first.** Today a "Perfect" shift is worth the same whether or not you served a customer, and the 45-second gate meant to stop that can be bypassed (B2 below). Training value comes from *decisions with consequences*, not cash counting.
2. **Build a data-driven scenario engine** (JSON scenarios validated in CI, rules stored as data with effective dates). Regulations are changing month to month; hard-coded rules will rot.
3. **Ship a teller-compliance vertical slice** of 6 to 8 scenarios (Section 3.3) before broadening to other roles.
4. **Deliver on the web, single-threaded, via SCORM** with a thin JavaScript bridge, plus a signed desktop build as fallback. Do not rely on client-side scoring for anything used as certification.
5. **Be honest about accessibility.** Godot's web export exposes no screen-reader accessibility tree today, so plan a parallel text-based alternative and a *partially conforming* VPAT.

---

## Contents

Section numbers below match the headings. Section 3 contains both the product definition (3.1 to 3.3) and the domain realism roadmap (3.4 to 3.5); there is no section 4.

1. [Environment and how to run](#1-environment-and-how-to-run)
2. [Part 1: Bugs and design flaws to fix](#2-part-1-bugs-and-design-flaws-to-fix)
3. [Part 2: Product definition](#3-part-2-product-definition) (3.1 problem, 3.2 goals, 3.3 non-goals)
   - [3.4 Domain realism roadmap](#34-domain-realism-roadmap) (regulatory reference, scenario library, example schema, role ladder)
   - [3.5 Regulatory flux watch-list](#35-regulatory-flux-watch-list)
5. [Part 4: Enterprise-readiness architecture](#5-part-4-enterprise-readiness-architecture)
6. [Part 5: Go-to-market and vendor due diligence](#6-part-5-go-to-market-and-vendor-due-diligence) (includes success metrics and user stories)
7. [Phased roadmap](#7-phased-roadmap)
8. [Risks](#8-risks)
9. [Open questions](#9-open-questions)
10. [Appendix A: file map](#appendix-a-file-map) / [B: sources](#appendix-b-sources)

---

## 1. Environment and how to run

- **Godot 4.7.2 (standard, non-Mono)** was installed with `winget install GodotEngine.GodotEngine` on 2026-09-29. The `godot` command aliases were **not** created (needs admin rights). Use the full path:
  `C:\Users\willi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe` (use `..._win64_console.exe` for terminal output).
- Commands that worked from the repo root: `--path . --editor` (open editor), `--path .` (run game), `--headless --path . --import --quit`, `--headless --path . --quit-after 300`.
- **No .NET SDK is installed** (runtime 8.0.21 only). Not needed: the project has no C# scripts. The C# web export is still unsupported in Godot 4 `[2ND]`, so **stay GDScript-only** and consider deleting the `[dotnet]` section of `project.godot`.
- **Controls:** WASD or arrow keys to move; E, Enter or Space to interact. F1 is a cheat key that unlocks all roles (see B7). The teller desk is at about (560, 336); the player spawns at (384, 624).
- **Repo hygiene:** 48 files under `.godot/` are tracked in git despite `.gitignore`. Any Godot run modifies three of them (`filesystem_cache10`, `project_metadata.cfg`, `uid_cache.bin`), so the tree looks dirty after a run. Decide whether to `git rm --cached -r .godot` (see B12).
- There is no automated testing today. Verification is manual.

---

## 2. Part 1: Bugs and design flaws to fix

Severity: **High** = breaks the training premise or is exploitable; **Med** = wrong behavior a player will notice; **Low** = polish or code health.

Verification: `[CODE]` means I read the code path; `[RUN]` means I ran a probe. Anything marked *static* was reported by an analysis agent that read the code but did not run it, and I did not re-verify it.

### 2.1 Bug list

| ID | Sev | Where | Problem | Fix |
|---|---|---|---|---|
| **B1** | Med | `teller_screen.gd:96, 330-333, 466`; `customer_queue.gd:106-110`; `teller_room.gd:65` | `end_shift()` frees every queued customer, but `TellerScreen._serving_customer` and `TellerRoom._customer_being_served` are never cleared. **This does not crash** `[RUN]`: a freed typed reference compares `== null` and `is_instance_valid()` is false in Godot 4.7.2, so `_current_payment_method()` silently falls back to Cash. The visible effects are a stale "Serving: X" label and `account` still pointing at the previous customer's account `[CODE]`. | On `shift_clocked_out`, call `teller_screen.set_serving_customer(null)`, clear `_customer_being_served`, and reset `account` to a neutral state. Add an `is_instance_valid` guard in `_current_payment_method()` anyway. |
| **B2** | High | `teller_screen.gd:123, 493-497, 539-547`; `teller_room.tscn:158` | **The 45 s "anti-farm" gate is bypassable, and the starting count is never validated.** The gate uses `Time.get_ticks_msec()` (ignores pause) but the `SpawnTimer` has no `process_mode` override (`teller_room.tscn:158`), so it stops while the tree is paused by the teller screen. Sit in the paused screen for 45 s, no customer spawns, clock out with a matching count for Perfect: +10 score, +2 reputation, +100 XP. Separately, `_begin_shift(total)` (line 539) adopts whatever total the player typed as `shift_start_balance`; `STARTING_EXPECTED_BALANCE` is only shown as a label. `[CODE]` | Do not patch the timer. Replace the model: score per served customer and per compliance decision (see 3.4). If a shift-length rule stays, count *sim time* or *customers served*, not wall-clock. Validate the opening count against the drawer's assigned float. |
| **B3** | Med | `teller_screen.tscn:113`; `drawer_count_screen.gd:21, 162`; `teller_screen.gd:559` | Cash amounts allow `$0.01` steps but the smallest denomination is `$1`, and Perfect requires `discrepancy == 0.0` (float equality). Any cash transaction with cents makes Perfect unreachable. `[CODE]` | Add coins to the drawer count, or restrict cash amounts to whole dollars. Compare money as integer cents. |
| **B4** | Med | `teller_screen.tscn:154-236`; `teller_room.tscn` | Score, reputation, XP, the low-reputation warning and unlock banners are children of `TellerScreen` and show only while it is open. There is no interaction prompt or controls hint anywhere, and the player spawns far from every desk. *static* | Add an always-on HUD `CanvasLayer`, an "Press E" prompt on desk proximity, and a first-run tutorial. |
| **B5** | Med | `teller_room.tscn` (Player at line 73, TellerDesk at 88) | No `y_sort_enabled` or `z_index` anywhere in the scene (grep found none). The player is drawn before the desks and decor, so they walk *under* furniture. Furniture has no collision (only wall tiles 1 and 3 do). `[CODE]` | Enable y-sort on the room root, add collision to furniture, and put the entrance gap (`room_builder.gd:41`) on an outdoor tile, not empty void. |
| **B6** | Med | `teller_room.gd:118-123`; `teller_screen.gd:243-257, 445`; `customer_queue.gd:193-210` | Several serving-flow flaws `[CODE]`: (a) any successful transaction counts as serving the front customer, regardless of type, amount or account; (b) `intent_type` and `intent_amount` are set at spawn but never read, so nothing checks the teller did what the customer asked; (c) after the first transaction, `set_serving_customer(null)` shows "No customer waiting" even when another customer is next; (d) `account` is not reset when there is no customer, so later visits act on the last customer's account while the dropdown shows blank. | Make the teller *complete the customer's actual request* and score the match. This is the core of the new scenario model (3.4). |
| **B7** | Low | `teller_room.gd:24-28, 198-202` | The F1 cheat (+100 reputation, +2000 XP) is live in every build, with no `OS.is_debug_build()` gate. `[CODE]` | Gate behind `OS.is_debug_build()` and strip from exports. It is unacceptable in a product a bank runs. |
| **B8** | Low | `xp_manager.gd:51-55, 57-72` | Unlock checks run only when XP changes, not when reputation changes. If reputation crosses the floor later, the unlock waits for the next XP event. `[CODE]` | Connect `ReputationManager.reputation_changed` to both unlock checks. |
| **B9** | High (accuracy) | `loan_application.gd:75-84` | `debt_to_income_ratio()` returns `existing_debt / annual_income`. Standard DTI is **monthly debt payments divided by gross monthly income**. The field appears to be a debt *balance*; confirm the field semantics before changing. A training product that teaches the wrong ratio is worse than no product. `[CODE]` (formula); field meaning needs confirming. | Model monthly obligations explicitly (see 3.5, Loan Officer). Do not teach 43% as a hard cap: the QM rule dropped that limit for a price-based test `[SRC]`. |
| **B10** | Low | `drawer_count_screen.gd:134`; `vault_reconciliation_screen.gd:151` | Integer division (`remaining / denom`) triggers a GDScript warning. Variant-returning `abs()`/`max()` calls at `teller_screen.gd:561` and `drawer_count_screen.gd:164` also lose typing. `[CODE]` | Use `@warning_ignore` deliberately or add casts; enable stricter warnings in project settings. |
| **B11** | Low | `teller_room.gd:57-63, 81, 89, 158, 173, 191` | Unsafe member access on `Area2D`/`Control`-typed variables (`.interacted`, `.show_screen`). *static* | Give the desks and screens `class_name` and type the `@onready` vars. |
| **B12** | Low | `.gitignore`, `.godot/` | `.godot/` is listed in `.gitignore` but 48 files under it are tracked, so every Godot run dirties the tree. `[CODE]` | `git rm -r --cached .godot`, commit, and confirm `.godot/` stays ignored. (Needs the owner's OK.) |
| **B13** | Low | various | Stale docs and comments: `CLAUDE.md` (lists 3 of 7 autoloads, says the Loan Officer unlock is unwired, describes a single small room), `DEVLOG.md` (stops before commits `6bb2876` and `4e2d2e4`), `interview_screen.gd:3-7` (says it is the main scene), `interview_manager.gd:14-16` (9 questions/26 points; actual 10/30), `history_manager.gd:6-9` (says nothing reads it; `approvals_screen.gd:127` does), `drawer_count_screen.gd:78-80` ("four inputs"; there are six), `customer_npc.gd:110` (cites a gitignored script). *static*, `CLAUDE.md` gaps `[CODE]` | Refresh `CLAUDE.md` and `DEVLOG.md` as part of Phase 0. |
| **B14** | Low | root | Leftovers: `node_2d.tscn`, `player_placeholder.png`, `teller_desk_placeholder.png`, `project.godot.bak`. | Delete after confirming nothing references them. |

### 2.2 Design flaws (not bugs, but they block the product)

- **Scoring rewards the wrong thing.** Score comes only from ending drawer accuracy (+10/+5/-5). Serving customers changes nothing except reputation via abandonment and complaints. `[CODE]` A training product must score *judgment*.
- **No fail state and no persistence.** Reputation at 0 only shows a warning label. All state is in memory and resets on relaunch. `[CODE]`
- **The staffing screen is decorative.** `ScheduleManager.schedule` is never read, and staff stats affect nothing. *static*
- **Unrealistic cash model.** The drawer uses $1000 and $500 bills and a $50,000 float (`teller_screen.gd:113`, `drawer_count_screen.gd:21`). US notes in circulation run from $1 to $100 `[UNV]` (the $500 and $1,000 notes were discontinued decades ago; confirm before citing), coins are missing entirely, and real drawer limits are set by each bank's policy `[UNV]`. Make the drawer float and denominations configurable per "institution profile."
- **The clock is wall-clock time.** `Time.get_datetime_string_from_system()` is used for shift times. Regulations count *business days* (CTR aggregation, Reg CC banking days, TRID business days). You need a sim clock with a business-day calendar (see 3.4).
- **The hiring interview is orphaned** (nothing loads it; `is_on_probation` is never read). Decide whether to rebuild it as a non-scored realistic job preview (see Non-goals: no scored pre-hire use without validation).

### 2.3 Acceptance criteria for Phase 0 (stabilization)

- [ ] B1, B2, B3, B6, B7, B8, B9 fixed, each with an automated test.
- [ ] `--headless --quit-after 300` and the full test suite run in CI with zero errors and zero new warnings.
- [ ] `CLAUDE.md` and `DEVLOG.md` match the code.
- [ ] `.godot/` untracked (owner's decision).
- [ ] A basic always-on HUD and interaction prompt exist.

---

## 3. Part 2: Product definition

### 3.1 Problem statement

Bank branch staff turn over quickly (reported non-officer turnover was 19.8% in 2023 `[2ND, Crowe survey]`; a widely repeated "60% of tellers leave within a year" figure is anecdotal and should be treated as a talking point only `[2ND]`). Every new hire must be trained on BSA/AML, robbery response, fraud and elder-exploitation red flags, and examiners expect *documented* training. Today that training is mostly ~30-minute quiz-style e-learning (ABA's Frontline course is free to ABA members `[2ND]`), which teaches rules but not the judgment calls under pressure where staff actually fail: a customer asks "what if I split the deposit?", an elderly customer is on the phone with a "Treasury agent", a cashier's check looks real. Banks need a repeatable, low-cost way to let new staff practice those moments safely and to prove they did.

### 3.2 Goals

1. **Judgment practice.** A new teller can rehearse the top 15 frontline scenarios (3.3) with realistic consequences and get feedback that cites the governing rule.
2. **Audit-ready evidence.** A training administrator can export who completed what, when, with what score, in a form that fits the bank's LMS and examiner requests (SCORM first, xAPI later).
3. **Accuracy people can trust.** Every rule in the game traces to a cited source, an effective date and a named compliance reviewer, and can be updated without a code release.
4. **Pilot-ready in a community bank.** The product passes a small institution's vendor review (security overview, SOC 2 roadmap, VPAT, no customer NPI).
5. **Measured learning.** Pilots produce our own data (time-to-competency in the sim, critical-error rate, learner confidence). Published meta-analyses show moderate effects for simulation games (Sitzmann 2011: +14% procedural knowledge, +20% self-efficacy) but none is about bank compliance, so we must not claim compliance-outcome improvements without pilot data `[2ND]`.

### 3.3 Non-goals (v1)

- **Not a replacement** for the bank's required LMS courses. Position as a supplement; the evidence says games work best that way `[2ND, Sitzmann 2011]`.
- **No scored pre-hire screening.** Using the sim for hire/no-hire decisions creates a validation and adverse-impact burden under the Uniform Guidelines (29 CFR 1607; four-fifths rule) `[2ND]`. A non-scored realistic job preview is much lower risk. An existing competitor already sells a teller assessment simulation (its predictive-validity claims were not verified) `[2ND]`.
- **No customer financial-literacy product.** Different buyer (marketing/community development) and an entrenched incumbent (Banzai) `[2ND]`.
- **No live customer data or core-banking integration.** The sim uses synthetic customers only, which keeps it out of GLBA scope for most reviews (confirm with the buyer) `[UNV]`.
- **No VR/AR, no C#, no multiplayer.**
- **Do not model Section 1071 data collection as live** before 2028 (see 3.5).

### 3.4 Domain realism roadmap

This is the heart of the plan: move from "a game with bank props" to "a bank-realistic decision simulator."

#### 3.4.1 Design principles

1. **Scenario-first.** A customer walks up with a *situation* (hidden facts, visible cues, a goal). The teller has real tools: ask questions, request ID, refuse, delay, escalate to a supervisor, refer to the BSA officer, place a hold, complete the transaction.
2. **Consequences, not just points.** Wrong choices create downstream events (a missed CTR data field becomes an examiner finding in the shift summary; tipping off a customer is a *critical error*).
3. **Feedback cites the rule.** After each scenario, show what the correct handling was, why, and the citation (with effective date).
4. **Rules are data.** Thresholds, deadlines and notice contents live in versioned JSON with `effective_date`, `source_url` and `reviewed_by`. The game reads them; it does not hard-code them.
5. **Critical-error concept.** Some behaviors fail a scenario outright regardless of score: tipping off a SAR subject, coaching a customer to avoid a CTR, returning a suspected counterfeit note, skipping ID on a reportable transaction.
6. **Sim clock and business days.** Model open/close, cutoffs, weekends and holidays.
7. **Neutral, respectful customers.** Avoid stereotyped names or profiles in suspicious-activity or OFAC scenarios; the research team's own OFAC seed used an ethnically marked name, which a fair-lending reviewer would flag. Vary names and let *behavior*, not identity, carry the red flags.

#### 3.4.2 Current model versus the target

| Area | Today | Target |
|---|---|---|
| Customer | Random name, cash or card, deposit or withdraw amount, 20% complaint | Scenario-driven profile: hidden facts, cues, an actual goal, a relationship history (new vs long-time customer) |
| Transaction types | Cash/card deposit and withdrawal only | Add checks (on-us, not-on-us, cashier's, third-party), money orders, wires, account opening, hold notices, disputes |
| Identity | None | ID check step: what to verify and record; mismatches; POA and joint-account authority |
| Regulatory tracking | None | Per-customer, per-business-day cash aggregation (CTR); monetary-instrument log; suspicious-activity referral log |
| Escalation | None | Supervisor call, BSA referral, security alarm, hold notice, refuse |
| Scoring | Drawer accuracy only | Competency dimensions (below) plus critical errors |
| Feedback | Shift summary with score | Per-scenario debrief with citations, plus a shift compliance report |
| Time | Real wall-clock | Sim clock with business days |
| Drawer | $50,000 float, $1,000 bills | Configurable float and denominations, coins, vault buy/sell |

**Proposed scoring dimensions** (replace the single score):
`Compliance judgment` · `Escalation and documentation` · `Customer experience` · `Cash accuracy` · `Ethics and integrity`. Each scenario declares which dimensions it scores and its critical-error list.

#### 3.4.3 Regulatory quick-reference (values the game will encode)

All rows are **for scenario authoring and SME review**, not legal advice.

| Topic | Rule or threshold | Citation | Conf. |
|---|---|---|---|
| CTR trigger | Currency transactions of more than $10,000, cash-in or cash-out counted separately (not netted), in one business day | 31 CFR 1010.310-313, 1020.310-313 | `[SRC]` |
| CTR aggregation | Multiple transactions by or on behalf of one person are one transaction if the bank knows; all domestic branches count as one institution; night/weekend deposits count as next business day | 31 CFR 1010.313(b) | `[SRC]` |
| CTR filing | Within 15 days; by BSA E-Filing; FinCEN Form 112 | 31 CFR 1010.306 | `[SRC]` (form name `[UNV]`) |
| CTR ID | Verify and record name, address, and ID of the presenter; record identity, account and SSN/TIN of anyone on whose behalf the transaction is made; "known customer" is not acceptable | 31 CFR 1010.312 | `[SRC]` |
| CTR exemptions | Phase I (banks, agencies, listed companies and subsidiaries); Phase II (non-listed businesses, account 2+ months, frequent large cash); designation due within 30 days; reviewed annually; ineligible: auto dealers, legal/medical/accounting practices, auctioneers, gaming, real estate brokers, pawnbrokers, title insurers | 31 CFR 1020.315 | `[SRC]` (Phase II detail `[UNV]`) |
| Structuring | Illegal to conduct or attempt transactions, in any amount, at any institution, to evade reporting; no single-day or single-bank $10,000 needed; a SAR is required only if the bank knows, suspects or has reason to suspect evasion | 31 USC 5324; FinCEN SAR FAQ (Oct 2025) | `[SRC]` |
| Teller must not coach | Do not tell a customer how to avoid a CTR; customers may be told the CTR requirement exists | 31 USC 5324(a)(3) (not fetched) | `[UNV]` |
| SAR timing | File within 30 days of initial detection; up to 30 more to identify a suspect; 60 total maximum | 31 CFR 1020.320 | `[SRC]` |
| SAR thresholds (bank) | Insider abuse: any amount; $5,000+ with an identifiable suspect; $25,000+ regardless; $5,000+ for suspected BSA violation or laundering; none for a robbery/burglary reported to police | 12 CFR 21.11(c); 31 CFR 1020.320 | `[SRC]` |
| SAR confidentiality | No bank employee may disclose a SAR or any information that would reveal its existence | 31 CFR 1020.320 | `[SRC]` |
| SAR FAQ (Oct 2025) | No mandatory continuing-activity review; if elected, timeline is Day 30 / 120 / 150; no requirement to document a no-file decision | FinCEN SAR FAQs Oct 2025 | `[SRC]` |
| Frontline escalation | Tellers refer to the BSA officer internally; they do not file SARs | practice | `[UNV]` |
| Monetary instruments | Cash purchases of bank checks, cashier's checks, money orders and traveler's checks of $3,000 to $10,000: record name, date, type, serials, amounts; verify identity; same-day purchases aggregate; keep 5 years | 31 CFR 1010.415 | `[SRC]` |
| CIP | Before opening: name, date of birth, address, ID number; verify by documents and/or non-documentary means; notice to customers; keep records 5 years after closing | 31 CFR 1020.220 | `[SRC]` |
| Beneficial ownership | Legal-entity customers: identify each 25%+ owner and one control person; certification at opening | 31 CFR 1010.230 | `[SRC]` |
| CIP/CDD relief | June 2025: banks may collect TIN details from a third party (optional). Feb 2026: beneficial owners need identifying only when a legal entity first opens an account | FinCEN orders | `[2ND]` |
| OFAC | Compare all listing details, most hits are false positives; SDN matches are blocked and reported within 10 business days; recordkeeping now 10 years (from 2025-03-12) | OFAC FAQ topic 1591; 31 CFR 501.603-604 | `[SRC]` (10-year `[2ND]`) |
| Reg CC amounts (from 2025-07-01) | Next-day minimum **$275**; cash withdrawal **$550**; new-account, large-deposit, repeated-overdraft **$6,725** | CFPB final rule (2024-05-13) | `[SRC]` |
| Reg CC availability | Next day for in-person cash deposits, electronic payments, Treasury/USPS/state-local government checks, cashier's/certified/teller's checks, on-us checks | 12 CFR 229.10 | `[SRC]` |
| Reg CC exceptions | New accounts (30 days); large deposits; redeposited checks; repeated overdrafts (6+ banking days in 6 months, or 2+ days at $6,725+); reasonable cause to doubt; emergency conditions | 12 CFR 229.13 | `[SRC]` |
| Reg CC hold notice | Must state account code, deposit date, amount delayed, reason, and availability date; give at deposit if in person | 12 CFR 229.13(g) | `[SRC]` |
| Reg E liability | $50 (or amount before notice) if reported within 2 business days; up to $500 later; unlimited for transfers after 60 days from the statement, only where timely notice would have prevented them | 12 CFR 1005.6 | `[SRC]` |
| Reg E errors | Notice within 60 days of the statement; investigate in 10 business days, or provisionally credit and take up to 45 days; 90 days for point-of-sale, foreign or new-account transfers | 12 CFR 1005.11 | `[SRC]` |
| Counterfeit handling | Do not return the note; delay the passer if safe; note description and plates; call police or Secret Service; initial and date; protect in an envelope; Form SSF 1604 to the processing facility if no leads; pen tests can be wrong | Federal Reserve FAQ; USSS Feb 2025 | `[SRC]` |
| Senior Safe Act | Immunity for good-faith reporting if the employee was trained; training covers identifying and reporting exploitation, privacy, and job fit; new hires within 1 year; keep training records | 12 USC 3423 | `[SRC]` |
| Elder exploitation | Behavioral and financial red flags; SAR key term `EFE FIN-2022-A002`; DOJ Elder Fraud Hotline 833-372-8311 | FinCEN FIN-2022-A002 | `[SRC]` |
| Crypto ATM scams | SAR key term `FIN-2025-CVCKIOSK`; red flag: large cash withdrawal because a caller said to deposit it in a kiosk | FinCEN Notice FIN-2025-NTC1 | `[SRC]` |
| Bank Protection Act | Security officer, opening/closing procedures, identification devices (bait money, camera), alarm, and *initial and periodic training* on employee conduct during and after a robbery | 12 USC 1882; 12 CFR 21.3, 208.61, 326 | `[SRC]` |
| Robbery best practice | Comply; trigger the alarm only when safe; observe and write descriptions separately; lock doors after; keep the note; call 911 | NY DFS letter; industry | `[2ND]` (lock-doors detail `[UNV]`) |
| Check fraud context | FinCEN alert on mail-theft check fraud (2023-02-27); SAR key term `FIN-2023-MAILTHEFT`; teller-visible red-flag list not retrieved | FIN-2023-Alert003 | `[SRC]` (red flags `[UNV]`) |
| Wells Fargo | 2016 CFPB order: about 1.5M possibly unauthorized deposit accounts and 565,443 unauthorized credit card applications; $100M CFPB penalty | CFPB 2016 order | `[SRC]` |
| Drawer controls | Drawer caps, excess-cash sales to the vault, dual control, balancing, variance tracking | industry practice | `[UNV]` (no numeric tolerances; get from SME) |

#### 3.4.4 Teller scenario library (top 15, ranked by frequency times risk)

Each is a seed for a JSON scenario. "Right" and "Wrong" are the choices to build. Anything marked `[UNV]` in the table above must be SME-confirmed first.

| # | Scenario | Tests | Right | Critical error |
|---|---|---|---|---|
| 1 | **Split cash deposits.** A landscaper deposits $6,000 at 10am and $5,500 at 3pm | CTR aggregation, ID capture | Aggregate to $11,500, collect ID data, process normally | Skipping ID because "known customer" |
| 2 | **"Should I split it up?"** Customer asks how to avoid the form | Structuring, no coaching, no tipping off | State the reporting requirement, do not advise, process normally, refer internally afterward | Coaching the customer; accusing them |
| 3 | **Elder on the phone with a "Treasury agent"** wanting $9,000 cash | Elder exploitation | Ask privately, separate from the caller, slow down, escalate, hold if policy and state law allow, refer to BSA/APS | Processing because "it's his money" |
| 4 | **Fake cashier's check / overpayment scam** and same-day cash back | Reg CC, customer warning | Warn that available funds is not cleared funds; consider a hold; refer | Handing over cash against uncleared funds |
| 5 | **New-account large check** ($9,000 to a 2-week-old account) | Reg CC exceptions, hold notice | Invoke exceptions, give the notice with required contents at the window, state the availability date | No notice; "it'll clear tomorrow" |
| 6 | **Crypto-kiosk withdrawal.** Customer says a caller told them to deposit cash | FinCEN kiosk red flags | Question, warn, escalate; note that split deposits can be structuring | Processing silently |
| 7 | **Washed or altered stolen check** at a new account | Mail-theft check fraud | Escalate before accepting | Accepting it |
| 8 | **Caller says "I'm her son" and wants the balance** | Authentication, pretexting | Decline, take a message, note it | Confirming the balance out of sympathy |
| 9 | **"Did you report me?"** | SAR confidentiality | Neither confirm nor deny; tell the BSA officer about the question | Saying "it wasn't a SAR" |
| 10 | **LLC account with a silent 30% owner** | CIP, beneficial ownership | Identify the 30% owner and one control person | Listing only the partners present |
| 11 | **Two $1,600 cash money orders** | Monetary-instrument log | Treat as $3,200; record required information | Treating them as separate |
| 12 | **Unauthorized debit charge** on a card lost two days ago | Reg E timing and intake | Freeze the card, log time of notice, start the dispute | "Wait for your statement" |
| 13 | **Robbery note at the counter** | Bank Protection Act | Comply, include bait money, alarm when safe, observe, lock doors after, 911 | Arguing, chasing, comparing stories |
| 14 | **Suspected counterfeit $100** | Security features | Hold it, alert a supervisor quietly, note description, call law enforcement | Handing it back |
| 15 | **Quota pressure to open unwanted accounts** | UDAAP, Wells Fargo lessons | Refuse, report the pressure through ethics/HR | Opening accounts to hit the number |

Also worth adding: a **drawer overage at close** (practice-based; the existing `drawer_count_screen` is a good base) and a **possible OFAC name match** at account opening (use a neutral name and let date-of-birth mismatch carry the lesson).

**Suggested first slice (Phase 1):** scenarios 1, 2, 3, 4, 5, 9 and 13. They cover CTR/structuring, SAR confidentiality, Reg CC, elder exploitation and robbery, and they give a clear demo story.

#### 3.4.5 Example scenario file (proposed schema)

```json
{
  "id": "tlr-ctr-aggregate-001",
  "schema_version": 1,
  "role": "teller",
  "title": "Two deposits, one business day",
  "competencies": ["compliance_judgment", "escalation_documentation"],
  "rule_refs": [
    {"id": "ctr-aggregation", "cite": "31 CFR 1010.313(b)", "effective": "existing", "source_url": "https://www.law.cornell.edu/cfr/text/31/1010.313"}
  ],
  "customer": {"archetype": "small_business_owner", "hidden": {"owner_is_presenter": true}},
  "beats": [
    {"t": "10:05", "say": "I'd like to deposit this cash.", "amount_cash_in": 6000},
    {"t": "15:10", "say": "Back again, one more deposit.", "amount_cash_in": 5500}
  ],
  "tools": ["request_id", "process", "escalate_supervisor", "refer_bsa", "refuse"],
  "expected": {"aggregate_cash_in": 11500, "ctr_required": true, "must": ["request_id", "record_presenter"]},
  "critical_errors": ["skip_id_known_customer", "advise_customer_on_avoiding_report"],
  "feedback": {
    "correct": "The two deposits total more than $10,000 in one business day, so a CTR is required...",
    "why_cite": "ctr-aggregation"
  },
  "reviewed_by": null,
  "reviewed_on": null
}
```

Content rules: scenario files carry `rule_refs` pointing at entries in a separate `rules.json` (values, effective dates, source URLs) so a rule change updates every scenario that cites it. A CI check rejects any scenario without a reviewer or that cites an expired rule.

#### 3.4.6 Role ladder (from the roles research)

Recommended order, with the three highest-value scenarios per role. Existing desks map onto the middle of this ladder.

| # | Role | Existing in game? | Top scenarios |
|---|---|---|---|
| 1 | **Teller / universal banker** | Yes (teller desk) | CTR/structuring; CIP and identity red flags; elder exploitation (see 3.4.4) |
| 2 | **Consumer loan officer** | Yes (Loan Officer desk, needs rework) | Adverse-action notice with specific reasons on a 30-day clock; prohibited-question or spousal-signature trap; consistency of exceptions across similar applicants |
| 3 | **Mortgage loan officer** | No | TRID clocks and a product change before closing; ATR analysis on a high-DTI borrower using the price-based QM test; HMDA data collection when the applicant declines |
| 4 | **Branch manager** | Yes (Branch Manager desk, needs rework) | Vault dual control and a surprise-count variance; robbery aftermath under the security program; payday-Friday staffing with a call-out and a control conflict |
| 5 | **BSA/AML analyst** | No | SAR or no-SAR on a structuring pattern with documentation; examiner asks for training records; insider-abuse referral |
| 6 | **Fraud analyst / contact-center rep** | No | Social-engineering caller; Reg E dispute; mule account with an elder victim |
| 7 | **Compliance officer** (capstone) | No | Respond to a rule change in policy and training; complaint trend signals a fair-lending problem; exam preparation |

Typical career progression the game can mirror `[2ND/UNV]`: teller -> universal/personal banker -> new-accounts or loan officer -> assistant branch manager -> branch manager; side moves into deposit operations or contact center -> fraud or BSA analyst -> BSA/compliance officer. BLS notes financial managers commonly come up from loan-officer-type roles with 5+ years' experience `[2ND]`.

**Role-specific rework of what already exists:**

- **Loan Officer** (`loan_application.gd`, `loan_review_screen.gd`, `loan_officer_screen.gd`). Replace the hidden Low/Medium/High tier grading with an underwriting worksheet: verified vs stated income, monthly debt obligations, DTI (front-end and back-end), LTV, credit-score band, collateral. Require the officer to *pick 2-4 specific principal reasons* for a denial (Reg B forbids "did not meet internal standards") `[SRC]` and to send the right notice(s). Add the spousal-signature and prohibited-question traps. Fix B9.
- **Branch Manager** (`branch_manager_screen.gd`, `vault_reconciliation_screen.gd`, `staff_scheduling_screen.gd`). Make scheduling matter (coverage by hour, breaks, dual-control needs, payday/first-of-month/Friday peaks `[UNV]`). Add vault dual control (two-person open), strap/bundle counts, surprise counts, and the annual security report. Wire `ScheduleManager.schedule` into the queue's arrival rate and service time.
- **Interview** (`interview_screen.gd`). Rebuild as a non-scored realistic job preview, or remove from the product.

#### 3.5 Regulatory flux watch-list

Rules are moving. **Design rule:** store every threshold and deadline as versioned data with an `effective_date`, and re-review content on a fixed cadence (suggest quarterly). All rows are as of 2026-09-29.

| Item | Status | Effect on the sim | Conf. |
|---|---|---|---|
| Section 1071 small-business lending data | Revised final rule published 2026-05-01; effective 2026-06-30; single compliance date **2028-01-01**; coverage threshold raised to 1,000 originations; small business defined at $1M revenue; litigation status unconfirmed | "Coming soon" module only; do not model live collection before 2028 | `[2ND]` |
| Reg B (ECOA) rule | Published 2026-04-22, effective 2026-07-21: removes the effects test (disparate impact) from Reg B, narrows "discouragement," restricts for-profit special purpose credit programs; disparate treatment and intentional proxy use remain prohibited; state law and Fair Housing Act case law may still apply. Adverse-action, spousal-signature and information-limit rules: no change found (absence of evidence) | Teach disparate treatment firmly; label disparate impact as "varies by law and regulator" | `[2ND]` |
| Fair-lending supervision | OCC (Bulletin 2025-16) and FDIC removed disparate impact from exam manuals; HUD proposals pending | Same as above | `[2ND]` |
| CRA | 2023 rule enjoined and never took effect; 1995 framework applies; new joint OCC/FDIC proposal about 2026-07-31, comments due **2026-10-13** | Mark "1995 rules, new proposal pending" | `[2ND]` |
| FinCEN AML/CFT program NPRM | Proposed April 2026 (four pillars including an ongoing employee training program); comments closed 2026-06-09; other agencies proposed parallel rules; not final; 31 CFR 1020.210 still governs | Design training around "risk-based and role-based," which persists | `[2ND]` |
| SAR FAQ | October 2025 FAQs relax continuing-activity expectations | Use the FAQ, not the old 90-day-cycle habit, as the baseline | `[SRC]` |
| CTR threshold | Still $10,000 as of Feb 2026; reform proposals pending; September 2026 status not confirmed | Make the threshold a data value | `[2ND]` |
| QM / ATR | General QM dropped the 43% DTI cap for a price-based test; 2026 thresholds include under 2.25 points for first liens of $137,958 or more; ATR review targeted Aug 2026, no completed change found | Do not teach 43% as a hard limit | `[SRC/2ND]` |
| Reg X loss mitigation | 2024 proposal; a final rule was targeted for Aug 2026; no evidence it was issued | Keep the collections module flexible | `[2ND]` |
| TPRM (vendor risk) guidance | Sept 2026 proposal would replace the June 2023 interagency guidance; comments due **2026-11-16**; existing guidance stays until finalized | Affects our vendor-review pack | `[2ND]` |
| CFPB funding/enforcement | Court rulings in 2026 required the CFPB to keep requesting funds; deregulatory agenda; reduced federal enforcement is likely while state AGs, private suits and prudential exams continue | Do not sell on "CFPB enforcement fear" | `[2ND]` |
| FFIEC Cybersecurity Assessment Tool | Retired 2025-08-31; banks map to NIST CSF 2.0 | Map our security overview to NIST CSF 2.0 | `[SRC/2ND]` |
| ADA Title II web rule | Adopts WCAG 2.1 AA but applies to state and local governments only (deadlines moved to April 2027/2028); does not bind private banks | Relevant to public colleges; for banks, VPAT is a procurement item | `[2ND]` |

---

## 5. Part 4: Enterprise-readiness architecture

These recommendations come from the technical research (Godot 4.7.2 docs and GitHub). Items marked `[UNV]` in the source report are noted; **run the three spikes at the end of this section before committing.**

### 5.1 Delivery: web-first, single-threaded, plus a desktop fallback

- **Export to the web with threads OFF** (the default since 4.3). Single-threaded export needs no cross-origin-isolation headers, which an LMS iframe can rarely provide `[SRC]`. Threads only buy Audio Stream mode and GDExtension, neither needed here.
- Use the **Compatibility renderer** (already configured; the only web renderer in Godot 4), `wasm32`, and the **standard (non-.NET) editor** for export; the .NET editor refuses web export `[SRC]`.
- Custom template to shrink size: the stock template's `.wasm` is about 33 MB uncompressed; a stripped custom template reached about 2.4-3.4 MB compressed `[2ND]`. Plan on 6-10 MB over the wire with the stock template `[UNV]`. **Measure load time on a real bank network and virtual desktop; no measured figures were found.**
- Serve `.wasm` as `application/wasm` with gzip or Brotli. If the LMS hosts the files you may not control this `[UNV]`.
- **Risk: WebGL2 may be unavailable** on GPU-less virtual desktops (Chrome's software fallback is deprecated) `[2ND]`. Add a runtime WebGL2 check with a clear error and offer the desktop build.
- **Desktop fallback:** signed Windows export wrapped in an MSI (WiX or similar) for silent install (`msiexec /i pkg.msi /qn`). Godot signs with SignTool or osslsigncode. EV certificates no longer bypass SmartScreen; Microsoft's Artifact Signing (formerly Trusted Signing) is the recommended service `[2ND]`. Check WiX's licensing (it asks for an open-source maintenance fee for revenue-generating use) with legal `[2ND]`. A desktop build **cannot call the LMS's SCORM API**, so it needs xAPI to an LRS or a completion code.
- Godot has no C#/web support (draft upstream work, no timeline) `[2ND]`. **Stay GDScript-only.**

### 5.2 LMS integration

- **SCORM first.** SCORM 1.2 has the widest LMS support and tracks completion and score only; SCORM 2004 (4th Edition) splits completion from success and allows a 64,000-character `suspend_data` (1.2 allows only 4,096) `[SRC]`. Banking LMSs the research confirmed: Cornerstone (under ABA's bank-branded LMS), BAI/ProSight Learning Manager, OnCourse Direct, BVS Monarch `[2ND]`. Confirm which the pilot bank uses.
- **Architecture:** put a **thin JavaScript bridge in a custom HTML shell** (`Html > Custom Html Shell`) and have Godot call only 3-4 functions on it (`lms.init()`, `lms.setProgress()`, `lms.complete(score, pass)`, `lms.commit()`) through `JavaScriptBridge`, guarded by `OS.has_feature("web")`. Use `scorm-again` (MIT, actively maintained) inside the shell `[2ND]`. Do **not** depend on the Godot SCORM addons found: one is Godot 3 and dormant, the other is a tiny single-maintainer plugin better used as reference code `[2ND]`.
- **Packaging:** generate `imsmanifest.xml` from the export folder in CI (must sit at the zip root). The manifest detail for 1.2 versus 2004 was not verified `[UNV]`.
- **Known SCORM traps:** content hosted on a different domain than the LMS cannot reach the API (same-origin); launching in a new window breaks API discovery `[SRC]`. Test in **SCORM Cloud and the bank's real LMS**.
- **Phase 2:** add xAPI (richer decision data) or cmi5. cmi5 needs an LRS-capable LMS and its bank support is unverified; no Godot xAPI/cmi5 addon exists `[2ND]`.
- **Resume state:** `user://` on web is IndexedDB, which can be blocked in private mode or third-party iframes `[SRC]`. Treat `user://` as a cache only; the source of truth for resume is SCORM `suspend_data` (mind the 4,096-character limit in 1.2) or the server. Keep saves compact and versioned.

### 5.3 Content pipeline

- **Author scenarios and rules as JSON** (validated in CI), loaded into typed `Resource` classes at runtime. Rationale: diff-friendly, editable by an L&D team without the Godot editor, and safer than loading external `.tres` files (which can carry scripts). This recommendation is reasoning only; no source was checked `[UNV]`.
- Godot has no built-in JSON Schema validation (not verified) `[UNV]`; write a GDScript validator and run it in CI and at load. Fail the build if a scenario lacks a reviewer, cites an unknown or expired rule, or references a missing asset.
- **Do not adopt Dialogic 2** (still alpha, breaks saves between releases). Consider **Dialogue Manager 4** only if branching-dialogue authoring becomes a real need, and confirm the plugin is not required at runtime `[2ND]`.
- **Localization:** use gettext `.po` files (plurals via `tr_n()`, contexts, Weblate/Transifex support) `[SRC]`. Accessibility names and descriptions are not included in POT generation (Godot issue #115366) `[2ND]`. RTL and CJK fonts not researched.

### 5.4 Testing and CI

- **gdUnit4** (v6.2.1, lists Godot 4.7; has a GitHub Action, scene runner and mocks) is the recommended framework. GUT 9.7.1 (branch `godot_4_7`) is a fine alternative. Neither was tested against this repo `[2ND]`. Pin engine and addon versions; GUT 9.7.0 broke on a 4.7 return-type change.
- **CI:** `abarichello/godot-ci` image tag `4.7.2-stable`. Commands: `--headless --import`, then `--export-release <preset> <path>`. Commit `export_presets.cfg` but **never commit signing credentials** `[2ND]`.
- **Add a browser smoke test:** Playwright loading the exported build against a mock SCORM API (our recommendation; no precedent researched).
- **First tests to write:** one per Phase 0 bug (B1, B2, B3, B6, B8, B9), then rule-engine unit tests (CTR aggregation across a business day, Reg CC hold selection, SAR threshold logic), then scenario-file validation.

### 5.5 Telemetry, integrity and security

- **Never trust client-side scores for certification.** SCORM values are whatever the client sends; anyone can call `LMSSetValue`. Godot scripts are decompilable (GDRE Tools), and PCK encryption requires a custom template, has publicly documented key extraction, and is a deterrent only `[2ND]`. For real certification, send answer events to a server you control and compute pass/fail there; use LMS completion as a convenience. Keep answer keys out of the client where certification matters.
- **Telemetry:** web `HTTPRequest` is subject to same-origin policy and needs CORS headers on your backend; the LMS's Content-Security-Policy may block outbound calls `[UNV]`. Flush events on each answer (background tabs pause `_process`). Send pseudonymous learner IDs supplied by the LMS; avoid free-text PII; state retention and purpose.
- **Data scope:** synthetic customers only; no NPI; minimal employee identifiers passed by the buyer's LMS or SSO.

### 5.6 Accessibility

- **Be candid.** Godot 4.5 added AccessKit screen-reader support (experimental) for Windows, macOS and Linux; the **web build is not listed** and the canvas exposes no accessibility tree today `[2ND]`. A conformance claim for WCAG 2.1 AA criteria that need one (1.1.1, 1.3.1, 4.1.2) is not supportable on web.
- **Plan:** (a) keyboard-only operation of every UI screen (Godot focus handling; `player_movement.gd` reads keys directly, so audit), (b) captions and non-color cues, a high-contrast theme, font scaling, (c) a **parallel accessible alternative** (HTML or text-mode version of the same scenarios and learning objectives), (d) a **partially conforming VPAT**, (e) NVDA/JAWS testing of the desktop build. Colorblind, contrast and UI-scaling guidance was not found in Godot-specific sources `[UNV]`.
- Note that a VPAT/WCAG statement is a procurement expectation for banks, not a legal mandate (the ADA Title II rule covers governments) `[2ND]`.

### 5.7 Proposed code layout

```
scripts/
  engine/                # NEW: scenario runner, rule engine, sim clock
    scenario_runner.gd
    rules_engine.gd      # reads rules.json (values + effective dates)
    sim_clock.gd         # business days, cutoffs, holidays
    compliance_log.gd    # per-customer aggregation, instrument log, referrals
  lms/                   # NEW
    lms_bridge.gd        # JavaScriptBridge wrapper (3-4 calls)
    telemetry.gd         # event queue + flush
    training_record.gd
content/
  rules.json
  scenarios/teller/*.json
  scenarios/loan/*.json
web/
  shell.html             # custom HTML shell + scorm-again glue
  build_scorm.py         # generates imsmanifest.xml + zip
tests/                   # gdUnit4
```

### 5.8 Spikes to run before committing (per the research)

1. **LMS spike:** a SCORM zip on SCORM Cloud, then in the pilot bank's real LMS, browser and virtual desktop.
2. **Accessibility spike:** NVDA/JAWS pass on the desktop and web builds.
3. **Performance spike:** measured download size and load time of the real export on a bank-like network.
4. *(Ours)* **SME spike:** have a bank compliance professional review the first 6-7 scenarios end to end before any pilot.

---

## 6. Part 5: Go-to-market and vendor due diligence

### 6.1 Market snapshot `[SRC/2ND as noted]`

- **Buyers exist and are consolidating.** 4,238 FDIC-insured institutions at 2Q26 (down 41 in the quarter; community banks are 90%) `[SRC]`; 4,214 federally insured credit unions at 6/30/2026 (down from 4,370 a year earlier) `[SRC]`. A shrinking count favors selling through associations and core/LMS partners.
- **Who buys** (best available evidence, a vendor blog): chief compliance officers, BSA officers and HR leads at institutions under $1B with 25-250 employees `[2ND]`. Retail-ops and L&D directors are probable budget owners for onboarding but no survey named them `[UNV]`.
- **Price anchors are low:** ABA Frontline is free to ABA members; one LMS vendor advertises from $5/user/month; a competitor's blog estimates $15-30/seat/month for bank-specific vendors `[2ND, weak]`. US average training spend was $874 per learner in 2025 `[SRC]`; the financial-services figures quoted elsewhere could not be traced.
- **Competitors:** ABA Frontline, BAI/ProSight (merged with RMA, announced Nov 2024), OnCourse Learning (part of Colibri Group, *not* Vector; the premise that OnCourse belongs to Vector is contradicted by OnCourse's own site), BVS Performance Solutions (Monarch LMS and a game-based product; the closest gamified competitor), Abrigo, Coggno. VR: Bank of America with Strivr (soft skills; no compliance content), a Strivr retail-banking bundle (Nov 2024). Pre-hire: Employment Technologies' teller simulation assessment `[2ND]`.
- **Differentiation** (inference, not proven): consequence-driven branch-day sim, replayable, runs on ordinary PCs with no headset, focused on compliance judgment with teller mechanics. No compliance-focused teller-workflow sim aimed at community banks was found `[UNV]`.

### 6.2 What a bank will ask a small vendor (minimum bar for a pilot)

This is the research team's synthesis of the usual community-bank vendor review, not a sourced standard `[UNV]`:

- Completed standard questionnaire (SIG Lite or similar).
- **SOC 2 Type II**, or Type I plus a dated roadmap. Type II needs a 6-12 month observation period, so start early.
- A recent third-party penetration-test summary.
- BCP/DR statement, cyber insurance, financial statements.
- A data-flow diagram showing **no customer NPI** and a defined minimal employee dataset.
- SSO (SAML/OIDC) and SCORM/xAPI export.
- A VPAT (partially conforming, honestly stated).
- Mapping to **NIST CSF 2.0** (the FFIEC Cybersecurity Assessment Tool was retired 2025-08-31).
- GLBA service-provider expectations (banks must diligence providers and contract for safeguards) `[SRC]`. The June 2023 interagency third-party guidance is being replaced (proposal Sept 2026), so check the new text for relief for small or low-criticality vendors `[2ND]`.

### 6.3 Packaging and pricing hypotheses

All `[UNV]` (public pricing was thin). Test in pilots:

- **Per-institution annual license tiered by employee count**, not per seat, to avoid the "free or $5/seat" comparison.
- **Paid pilot of 60-90 days** with one branch cohort and agreed metrics.
- **Association channel:** sell to state bankers associations and credit union leagues as a member benefit.
- Position as an **add-on to the existing LMS course**, never as a replacement.

### 6.4 Success metrics

Targets are hypotheses to be set with the first pilot bank, not commitments.

| Type | Metric | Hypothesis target |
|---|---|---|
| Leading | Pilot completion rate (assigned learners who finish the slice) | 80% or higher |
| Leading | Replay rate (learners who replay at least one scenario) | Track; expect meaningful replay if the design works |
| Leading | Critical-error rate per scenario, first attempt vs replay | Falls on replay |
| Leading | Learner self-reported confidence before vs after | Positive shift (Sitzmann reports +20% self-efficacy for games generally) |
| Leading | Time for a learner to reach competent on the 7-scenario slice | Establish baseline in the pilot |
| Lagging | Pilot-to-paid conversion | 1 of 3 pilots converts in year 1 |
| Lagging | Vendor-review pass rate | First review passes without a blocking finding |
| Lagging | Reduction in the bank's own frontline error or referral-quality metrics | Only claim if the pilot bank shares data |

### 6.5 User stories (P0)

- **Learner (new teller):** As a new teller, I want to handle a customer who tries to split a cash deposit so that I learn what to say and what never to say, and get feedback that cites the rule.
- **L&D administrator:** As a training administrator, I want the completion and score to appear in our LMS so that I can show an examiner who was trained on what and when.
- **BSA officer:** As a BSA officer, I want to see which scenarios staff fail most often so that I can target coaching.
- **Vendor-risk reviewer:** As a reviewer at the bank, I want a security overview and confirmation that no customer data is processed so that I can approve the vendor quickly.
- **Compliance SME (content owner):** As a compliance professional, I want to edit a scenario or a threshold and see who reviewed it and when so that content stays accurate as rules change.

---

## 7. Phased roadmap

Effort figures are rough T-shirt estimates for a small team (1-2 engineers plus part-time SME review). Adjust after Phase 0.

### Phase 0: Stabilize (S, about 1-2 weeks)
- Fix B1, B2, B3, B6, B7, B8, B9 with tests; add gdUnit4 and headless CI.
- Always-on HUD, interaction prompt, tutorial pass.
- Refresh `CLAUDE.md` and `DEVLOG.md`; delete leftovers; decide on untracking `.godot/`.
- **Exit:** CI green, zero warnings in the headless smoke run, docs match code.

### Phase 1: Teller compliance vertical slice (L, about 4-6 weeks)
- Build `engine/` (scenario runner, rules engine, sim clock, compliance log) and the JSON schema.
- Implement scenarios 1, 2, 3, 4, 5, 9 and 13 with competency scoring and critical errors.
- Add ID-check step, check deposits with Reg CC hold notices, escalation tools.
- **Exit:** a compliance SME has reviewed all 7 scenarios and their citations; a new player can complete the slice; scenario validation runs in CI.

### Phase 2: Pilot-ready (L, about 4-6 weeks, overlaps SOC 2 start)
- Custom HTML shell, `lms_bridge`, SCORM 1.2/2004 packaging, admin export, server-side answer logging.
- Accessibility alternative and partial VPAT; keyboard-only audit.
- Security pack: overview, data-flow diagram, pen test, BCP statement, questionnaire; begin SOC 2.
- Run the LMS, accessibility and performance spikes; signed desktop build.
- **Exit:** passes a real LMS and a community bank's vendor review; pilot agreement signed.

### Phase 3: Role expansion (XL, ongoing)
- Rework Loan Officer and Branch Manager (3.4.6); add BSA analyst, fraud/contact center, compliance-officer capstone.
- Add the "coming soon" modules for Section 1071 (2028) and track flux items.
- **Exit:** at least 3 roles with 20+ SME-reviewed scenarios.

### Phase 4: Scale (XL, ongoing)
- xAPI/cmi5 and LRS reporting, admin dashboards, localization, an authoring tool for L&D teams, association distribution, quarterly content-review cadence.

---

## 8. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| **Records, not learning, win the sale** | Examiners look for documented completion (Senior Safe Act, FFIEC training expectations, Bank Protection Act) `[2ND]` | SCORM records and admin export are P0, not polish |
| **Price anchors** | Free ABA content and $5-30/seat pricing make generic per-seat sales hard | Per-institution licensing; sell the sim as a supplement |
| **Vendor-review cost** | SOC 2 Type II takes months; TPRM guidance is being rewritten | Start SOC 2 in Phase 2; track the Nov 2026 comment deadline |
| **Regulatory flux** | AML program, Reg B, CRA, Reg X, CTR reform all moving | Rules as data with effective dates; quarterly review |
| **Content accuracy and liability** | A wrong rule in a bank-training product is a reputational and possibly legal problem | SME sign-off gate in CI; disclaimers; never claim legal advice |
| **Evidence gap** | Published effects are moderate with publication bias; none are about bank compliance | Collect our own pilot data; make no outcome claims until we have it |
| **Hiring-use liability** | Scored pre-hire use triggers validation duties | Non-goal; non-scored job preview only |
| **Technical unknowns** | WebGL2 on virtual desktops, canvas accessibility, SCORM in the bank's LMS, load time | Run the four spikes before committing |
| **Client-side score forgery** | SCORM scores are self-reported | Server-side verification for anything certifying |
| **Unverified research inputs** | Several regulatory items rest on law-firm summaries and search snippets | Treat every `[2ND]`/`[UNV]` as a lead; SME confirm before shipping |

---

## 9. Open questions

| # | Question | Owner | Blocking? |
|---|---|---|---|
| 1 | Who is the compliance SME who signs off scenarios, and what is the review workflow and cadence? | Business / compliance | **Yes** (before any pilot) |
| 2 | Which LMS, browser and virtual-desktop stack does the pilot bank actually run? | Pilot bank / IT | **Yes** (before Phase 2) |
| 3 | Is the product positioned as a supplement (recommended) or as the primary BSA course for small banks? | Product / legal | Yes |
| 4 | Do we sell through associations first, or direct to a founding bank? | Business | No |
| 5 | What are realistic teller drawer floats, denominations and variance tolerances (practice, not regulation)? | SME | No (config values) |
| 6 | Does a sim with no NPI escape SOC 2 requirements at a small bank, or will reviewers still ask? | Pilot bank / vendor-risk | No |
| 7 | What is the status of the Section 1071 litigation, the FinCEN AML final rule, and Reg X? | Compliance / legal | No (data-driven design absorbs it) |
| 8 | Should the hiring interview be rebuilt as a non-scored job preview or dropped? | Product | No |
| 9 | Legal review of WiX's licensing terms for revenue-generating use | Legal | No (desktop fallback only) |
| 10 | Is the fully untracked `.godot/` change acceptable to the repo owner? | Owner | No |
| 11 | Does `existing_debt` in `LoanApplication` mean a balance or a monthly payment? (decides the B9 fix) | Engineering | Yes (for B9) |

---

## Appendix A: file map

| Concern | Files |
|---|---|
| Room wiring, desk/ATM/queue signals, F1 cheat | `scripts/world/teller_room.gd` |
| Procedural floor plan (24x22 tiles) | `scripts/world/room_builder.gd` |
| Customer spawning, queue, abandonment | `scripts/world/customer_queue.gd`, `scripts/npc/customer_npc.gd` |
| Teller workflow, shift scoring, clock in/out | `scripts/ui/teller_screen.gd` (largest file, ~650 lines) |
| Cash-count mini-game | `scripts/ui/drawer_count_screen.gd`, `scripts/ui/vault_reconciliation_screen.gd` |
| Loan Officer | `scripts/ui/loan_officer_screen.gd`, `loan_review_screen.gd`, `scripts/data/loan_application.gd`, `loan_applications_data.gd` |
| Branch Manager | `scripts/ui/branch_manager_screen.gd`, `staff_scheduling_screen.gd`, `approvals_screen.gd` |
| Progression | `scripts/autoload/xp_manager.gd`, `score_manager.gd`, `reputation_manager.gd` |
| Shared data and history | `scripts/autoload/account_manager.gd`, `history_manager.gd`, `schedule_manager.gd` |
| Current content (in code) | `scripts/data/customer_complaints_data.gd`, `customer_dialogue_data.gd`, `interview_questions_data.gd`, `staff_roster_data.gd` |
| Theme | `themes/banking_theme.tres` |
| Main scene | `scenes/world/teller_room.tscn` (set in `project.godot`) |

## Appendix B: sources

Primary and near-primary pages the research agents read or cited (confidence tags in the body):

- CTR/structuring/SAR/CIP: Cornell LII pages for 31 CFR 1010.306, 1010.312, 1010.313, 1010.415, 1010.230, 1020.220, 1020.315, 1020.320, 1020.210, 12 CFR 21.3, 21.11, 208.61; FinCEN SAR FAQs (Oct 2025) `https://www.fincen.gov/system/files/2025-10/SAR-FAQs-October-2025.pdf`.
- OFAC: `https://ofac.treasury.gov/faqs/topic/1591`.
- Reg CC: `https://www.consumerfinance.gov/rules-policy/final-rules/availability-funds-and-collection-checks-regulation-cc-threshold-adjustments/`; 12 CFR 229.10 and 229.13 on LII.
- Reg E: 12 CFR 1005.6 and 1005.11 on LII.
- Counterfeit: `https://www.uscurrency.gov/denominations/100` (and /5, /10, /20, /50); `https://www.federalreserve.gov/faqs/currency_12597.htm`; Secret Service, Feb 2025.
- Elder exploitation: FinCEN FIN-2022-A002; FinCEN Notice FIN-2025-NTC1 (`https://www.fincen.gov/system/files/2025-08/FinCEN-Notice-CVCKIOSK.pdf`); interagency statement (Dec 2024); FINRA Senior Safe Act fact sheet.
- Check fraud: FinCEN alert FIN-2023-Alert003; FTC fake-check scam page.
- Robbery: 12 USC 1882; FBI Bank Crime Statistics 2023 (1,362 violations, including 1,263 robberies, 2023).
- Lending: CFPB Reg B 1002.5, 1002.7, 1002.9; Reg V 1022.72; Reg Z 1026.19; QM definition rule; Federal Register 2025-12-15 Reg Z thresholds; Reg X 1024.41.
- Reg change coverage (secondary): Mayer Brown, Greenberg Traurig, Venable, Nat Law Review, Consumer Finance Monitor summaries cited in the role research.
- Market: FDIC Quarterly Banking Profile 2Q26; NCUA Q2 2026 data summary; Training Magazine 2025; BAI/ProSight, ABA, OnCourse, BVS, Coggno vendor pages; PRNewswire (Bank of America/Strivr).
- Evidence: Sitzmann 2011; Wouters et al. 2013; Donovan and Radosevich 1999; Keith and Frese 2008.
- Technical: Godot docs (web export, JavaScriptBridge, custom HTML shell, gettext, command line, data paths), Godot 4.5 and 4.7 release notes, Godot GitHub issues and PRs, scorm.com (API discovery, run-time reference, manifest structure), `jcputney/scorm-again`, gdUnit4, GUT, `abarichello/godot-ci`, Microsoft SmartScreen documentation.

The individual URLs are attached to each claim in the four research reports this document was built from; if a claim matters, re-fetch its primary source before relying on it.
