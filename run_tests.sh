#!/usr/bin/env bash
# Runs the GDScript warning check, the full gdUnit4 test suite (tests/) and a
# headless boot smoke test. Used locally and by CI (.github/workflows/tests.yml).
#
#   GODOT_BIN=/path/to/godot ./run_tests.sh
#
# Fails (non-zero exit) if any script has a GDScript warning, any test fails,
# the boot run exits non-zero, or Godot prints an error (ERROR: /
# SCRIPT ERROR:) at any step.
set -uo pipefail

if [[ -z "${GODOT_BIN:-}" ]]; then
	echo "Set GODOT_BIN to the Godot 4.7.x executable (the _console.exe on Windows)." >&2
	exit 2
fi

cd "$(dirname "$0")"
logs="$(mktemp -d)"
status=0

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

echo "== Checking output for errors"
# Strip colour codes, then look for Godot's error lines in every step.
if sed 's/\x1b\[[0-9;]*m//g' "$logs/import.log" "$logs/warnings.log" "$logs/tests.log" "$logs/boot.log" \
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
