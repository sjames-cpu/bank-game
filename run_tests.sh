#!/usr/bin/env bash
# Runs the generated-art check, the GDScript warning check, the full gdUnit4
# test suite (tests/) and headless boot smoke tests of the main scene (the
# start screen) and the teller room. Used locally and by CI
# (.github/workflows/tests.yml).
#
#   GODOT_BIN=/path/to/godot ./run_tests.sh
#
# Fails (non-zero exit) if the generated art is out of date (or no Python 3 is
# found to check it), any script has a GDScript warning, any test fails,
# either boot run exits non-zero, or Godot prints an error (ERROR: /
# SCRIPT ERROR:) at any step.
set -uo pipefail

if [[ -z "${GODOT_BIN:-}" ]]; then
	echo "Set GODOT_BIN to the Godot 4.7.x executable (the _console.exe on Windows)." >&2
	exit 2
fi

cd "$(dirname "$0")"
logs="$(mktemp -d)"
status=0

echo "== Checking generated art is current"
# The committed character sprites must match tools/art/generate_characters.py
# (see ART.md). PYTHON_BIN overrides the interpreter; otherwise the first of
# python / python3 that actually runs (the timeout skips the Windows Store
# python3 stub, which waits instead of running).
python_bin="${PYTHON_BIN:-}"
if [[ -z "$python_bin" ]]; then
	for candidate in python python3; do
		if command -v "$candidate" >/dev/null && timeout 10 "$candidate" -c "import sys" >/dev/null 2>&1; then
			python_bin="$candidate"
			break
		fi
	done
fi
if [[ -z "$python_bin" ]]; then
	echo "No Python 3 found for the art check; set PYTHON_BIN." >&2
	status=1
elif ! "$python_bin" tools/art/generate_characters.py --check; then
	echo "Generated art is out of date: run python tools/art/generate_characters.py" >&2
	status=1
fi

echo "== Importing project"
"$GODOT_BIN" --headless --path . --import >"$logs/import.log" 2>&1
import_exit=$?
if [[ $import_exit -ne 0 ]]; then
	cat "$logs/import.log"
	echo "Import failed (exit $import_exit)" >&2
	status=1
fi

echo "== Checking scripts for warnings"
# Warnings never print when a script loads, so raise every enabled warning to
# an error for one run (override.cfg, read by Godot at startup) and compile
# every script. The override is removed straight after, whatever happens.
trap 'rm -f override.cfg' EXIT
"$GODOT_BIN" --headless --path . -s res://tools/write_warnings_override.gd >"$logs/warnings.log" 2>&1
override_exit=$?
timeout 300 "$GODOT_BIN" --headless --path . -s res://tools/check_scripts.gd >>"$logs/warnings.log" 2>&1
check_exit=$?
rm -f override.cfg
cat "$logs/warnings.log"
if [[ $override_exit -ne 0 || $check_exit -ne 0 ]]; then
	echo "Script check failed (exit $override_exit/$check_exit)" >&2
	status=1
fi

echo "== Running tests"
# -c: report every failure instead of stopping a suite at the first one.
"$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	-a res://tests -c --ignoreHeadlessMode 2>&1 | tee "$logs/tests.log"
tests_exit=${PIPESTATUS[0]}
if [[ $tests_exit -ne 0 ]]; then
	echo "Tests failed (exit $tests_exit)" >&2
	status=1
fi

echo "== Headless boot (300 frames)"
"$GODOT_BIN" --headless --path . --quit-after 300 2>&1 | tee "$logs/boot.log"
boot_exit=${PIPESTATUS[0]}
if [[ $boot_exit -ne 0 ]]; then
	echo "Headless boot failed (exit $boot_exit)" >&2
	status=1
fi

echo "== Headless boot of the teller room (300 frames)"
# The main scene is the start screen, so boot the gameplay room directly too.
"$GODOT_BIN" --headless --path . res://scenes/world/teller_room.tscn --quit-after 300 2>&1 \
	| tee "$logs/room_boot.log"
room_boot_exit=${PIPESTATUS[0]}
if [[ $room_boot_exit -ne 0 ]]; then
	echo "Teller room boot failed (exit $room_boot_exit)" >&2
	status=1
fi

echo "== Checking output for errors"
# Strip colour codes, then look for Godot's error lines in every step.
if sed 's/\x1b\[[0-9;]*m//g' "$logs/import.log" "$logs/warnings.log" "$logs/tests.log" "$logs/boot.log" "$logs/room_boot.log" \
	| grep -E '^\s*(SCRIPT ERROR|USER ERROR|ERROR):' ; then
	echo "Godot printed errors (above)" >&2
	status=1
else
	echo "No errors printed."
fi

if [[ $status -eq 0 ]]; then
	echo "== ALL PASSED"
else
	echo "== FAILED" >&2
fi
exit $status
