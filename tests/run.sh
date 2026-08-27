#!/usr/bin/env bash
# Runs the pure-logic tests outside the Playdate simulator.
#
# The game's rules -- dice ranges, percentile scoring, the layout solver, the
# throw state machine -- are plain Lua and don't need a device to verify. This
# script rewrites the SDK's compound-assignment operators (+=, *=) into stock
# Lua 5.4, stubs the handful of `playdate.*` calls the logic touches, and runs
# the specs. Drawing is stubbed out; this checks behaviour, not pixels.
#
# Requires: lua5.4 and python3.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

python3 tests/transpile.py source "$OUT" > /dev/null

lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/numerals_spec.lua
lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/dice_spec.lua
lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/setup_spec.lua
lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/roll_spec.lua
lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/settings_spec.lua
lua5.4 -e "DIR='$PWD/tests' OUT='$OUT'" tests/history_spec.lua
