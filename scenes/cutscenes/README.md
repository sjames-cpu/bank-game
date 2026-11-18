# Cutscenes

Every cutscene in the game is a JSON file here, played by the one shared
player, `Cutscenes` (`scripts/core/cutscene_runner.gd`). No role writes its
own cutscene code (ROLE_BOUNDARIES.md).

- `teller/`: the Teller's scenes (Liam)
- `loan/`: the Loan Officer's scenes (James)
- `shared/`: scenes for more than one role (changed on a `shared/` branch)

## A scene

```json
{
	"steps": [
		{"show": "staff_01", "side": "left"},
		{"say": "Morning! The vault's open.", "speaker": "Walter"},
		{"choice": "help", "prompt": "Help Walter count?", "options": ["Yes", "No"], "default": 0},
		{"fade": "out"}
	]
}
```

Step types (one per step):

| Step | What it does |
| --- | --- |
| `{"say": "text", "speaker": "Name"}` | a line; the player moves on with Enter, Space, a click or Next. `speaker` is optional |
| `{"show": "staff_01", "side": "left"}` | a character stands on the left or right |
| `{"hide": "staff_01"}` | a character on screen leaves |
| `{"fade": "out", "seconds": 0.5}` | fade to black (`out`) or back (`in`); `seconds` is optional (0.5) |
| `{"wait": 1.0}` | a pause, in seconds |
| `{"choice": "name", "prompt": "...", "options": ["A", "B"], "default": 0}` | two options; the answer (0 or 1) comes back under `name`, and `default` is what a skip picks |

Characters: `player`, `staff_01` to `staff_10`, `regional_manager`,
`guard_1`, `guard_2`, and the customer looks `customer_a` to `customer_c4`
(see `CutsceneScene.KNOWN_CHARACTERS`). They stand still: walking isn't
supported in version 1.

## Playing one

```gdscript
var result := await Cutscenes.play("res://scenes/cutscenes/teller/first_day.json")
if result.choices.get("help") == 0:
	pass # what the answer changes is your role's code
```

While it plays the game is paused and the current time slot is held. Esc
(or Skip) asks "Skip this scene?"; Yes ends it with every unanswered choice
at its default (`result.skipped` is true).

## Checking

`tests/cutscene_scene_test.gd` checks every `.json` file in this folder. A broken
scene fails the tests with a message naming the file and the step, for
example `res://scenes/cutscenes/teller/first_day.json: step 3: unknown
character "staff_11"`. The game also checks a scene before playing it and
plays nothing (with a warning) if it has a problem.
