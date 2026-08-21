# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**BankSim** is a Godot project past initial scaffolding, with a first vertical slice implemented end-to-end in GDScript: a hiring interview mini-game, a top-down player/room, and a teller desk workflow (drawer counts, deposits/withdrawals, shift scoring, reputation). No `.csproj`/`.sln` exists yet — everything so far is GDScript, even though the project is configured for .NET (see below). `node_2d.tscn` is a leftover placeholder scene, no longer the entry point.

Treat any architectural description here as provisional — update this file as real structure changes, since it's still an early slice.

### Flow

`run/main_scene` is `scenes/ui/interview_screen.tscn` — the interview mini-game is the first thing the player sees. Hired/Hired-on-Probation transitions to `scenes/world/teller_room.tscn` (spawns the player in a small tile room with a `TellerDesk`); Rejected loops back to the first interview question. Interacting with the desk (`ui_accept` or `E`) opens `TellerScreen`, which pauses the tree and drives clock-in → deposits/withdrawals → clock-out → shift summary.

### Autoloads (`scripts/autoload/`)

Global singletons registered in `project.godot`'s `[autoload]` section, each a plain `Node` holding in-memory state (nothing persisted to disk yet) and a `*_changed`/`*_completed` signal for UI to react to:

- **ScoreManager** — `total_score`, a running per-session tally adjusted via `add_shift_score()`.
- **ReputationManager** — `reputation`, clamped to `[0, 100]`, adjusted via `add_reputation()`. `LOW_REPUTATION_THRESHOLD` gates a warning label; a Loan Officer role unlock is planned but not wired up.
- **InterviewManager** — resolves the interview mini-game's outcome (`resolve_outcome()`), exposes `Outcome` enum (`HIRED` / `HIRED_ON_PROBATION` / `REJECTED`), `HIRE_THRESHOLD`/`PROBATION_THRESHOLD` constants, and `is_on_probation` (set but not yet used by gameplay).

### Data resources (`scripts/data/`)

Small `Resource`-based structs, built in code rather than loaded from `.tres` files (no save/load need yet): `Account` (customer name + balance, mutated only via `deposit()`/`withdraw()`), `ShiftTransaction` (one deposit/withdrawal record), `InterviewQuestion`/`InterviewAnswer` (interview question text plus 2-4 scored answer choices, an answer can be `is_instant_reject`). `interview_questions_data.gd` is a static provider (`InterviewQuestionsData.get_questions()`) holding the actual 9-question interview script, kept separate from the data shape so content can grow independently.

### World & UI scripts (`scripts/world/`, `scripts/player/`, `scripts/ui/`)

- `player_movement.gd` — 8-direction `CharacterBody2D` movement (WASD/arrows), reads `Input.is_key_pressed` directly rather than via the InputMap.
- `room_builder.gd` — fills a `TileMapLayer` with a simple walled rectangular room at runtime (placeholder level, no hand-painted layout yet).
- `teller_desk.gd` — an `Area2D` that only detects player proximity + interact key and emits `interacted`; it doesn't know what happens next (`teller_room.gd` connects the signal to opening `TellerScreen`).
- `teller_room.gd` — room root, wires `TellerDesk.interacted` to `TellerScreen.show_screen()`.
- `interview_screen.gd`/`.tscn` — the interview mini-game UI (question label + dynamically-built answer buttons), tracks running score and an instant-reject flag across all questions, then hands both to `InterviewManager.resolve_outcome()`.
- `teller_screen.gd`/`.tscn` — the main teller desk UI: account selection/creation, deposit/withdraw, clock-in/out (each routes through `drawer_count_screen.gd` for a cash count), and a shift summary that posts to `ScoreManager`/`ReputationManager`.
- `drawer_count_screen.gd`/`.tscn` — denomination-based cash-counting mini-game; compares the player's count against an expected balance the caller supplies and classifies the result as Perfect/Minor/Major discrepancy. Doesn't manage its own pause state — the caller (`TellerScreen`) is expected to already have the tree paused.

## Engine configuration (`project.godot`)

- **Godot version**: 4.7, GL Compatibility rendering feature profile.
- **Renderer**: `gl_compatibility` on both desktop and mobile (not Forward+/Mobile).
- **Rendering device (Windows)**: `d3d12`.
- **.NET/C#**: enabled — `[dotnet] project/assembly_name="BankSim"`. When C# scripts are added, a `.sln`/`.csproj` will need to be generated (Godot does this automatically the first time a C# script is created in the editor, or via `dotnet new`).
- **Physics**: 3D physics engine is Jolt Physics (not the Godot default).
- **Display stretch**: `canvas_items` mode with `expand` aspect — this is a 2D-scaled project setup even though 3D physics (Jolt) is configured, so don't assume the project is purely 2D or purely 3D from this alone.

## Editing `project.godot`

This file is hand-editable but the header explicitly warns it's best edited via the Godot editor UI, since not all parameters are obvious/documented. Prefer making engine-setting changes through the editor when possible; when editing directly, keep the section/key format consistent with the existing file. A `project.godot.bak` backup exists from a prior editor save — don't treat it as a file to edit or keep in sync.

## Version control notes

- `.gitattributes` normalizes all text files to LF line endings.
- `.godot/` (Godot's local cache/import directory) is gitignored — never treat files under it as source.
- `.summer/local/` is gitignored — it holds local-only state for a "Summer Engine" tooling layer wrapping this repo (including its own nested bare git repo under `.summer/local/git/`). This is tooling-local, not project source; don't edit or commit through it.

## Development workflow

There is no build/lint/test tooling set up yet (no C# project file, no test framework, no CI config). Since there's no `.csproj`, C# scripts can't be compiled outside the Godot editor until one is generated. Running/testing changes currently means opening the project in the Godot 4.7 editor and using its Play/Run functionality; update this section once scripts, scenes, and a test setup exist.
