# Old-save generator

`make_old_saves_test.gd` writes sample saves in the **current** save format
into `tests/data/old_saves/`, where `tests/old_saves_test.gd` loads every
one into today's game. That's how we know a player's old save still works
after the format changes.

## When to use it

Run it **just before** you change the save format, that is, before you raise
`SaveGame.FORMAT_VERSION` in `scripts/util/save_game.gd`:

1. Run the generator (below). It writes `v<current version>_<kind>.json`:
   a career at the start of a day, at an End of Day, during onboarding, and
   a Branch Manager at an End of Day.
2. Commit those files.
3. Now change the format, raise `FORMAT_VERSION`, and make `SaveGame` still
   read the old version (`MIN_FORMAT_VERSION`).
4. Add a test to `tests/old_saves_test.gd` for each new sample, and update
   the README in `tests/data/old_saves/`.

You don't need it for changes that only add a new saved field with a default
(a save without the field loads as a new game would). Those don't change the
format version.

It never overwrites a file that already exists: the committed samples are a
record of what older versions of the game wrote. The version 1 samples and
`v2_switch_off_mid_day.json` were made by an earlier version of this script,
while the game's clock still ran, and can't be made again.

## Running it

From the project folder, in Git Bash:

```sh
"$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    -a res://tools/old_saves/make_old_saves_test.gd --ignoreHeadlessMode
```

It prints `Wrote ...` or `Kept ...` for each file. It's written as a gdUnit4
test so the game's autoloads are running, but it isn't part of the normal
test run: `run_tests.sh` only runs `tests/`.
