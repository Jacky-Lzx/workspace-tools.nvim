#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
nvim --headless -u NONE -i NONE --noplugin -l tests/command_ownership.lua
WORKSPACE_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/workspace-tools.XXXXXX")
export WORKSPACE_TEST_DIR
trap 'rm -rf "$WORKSPACE_TEST_DIR"' EXIT HUP INT TERM
export NVIM_LOG_FILE="$WORKSPACE_TEST_DIR/nvim.log"
export XDG_STATE_HOME="$WORKSPACE_TEST_DIR/state"
export XDG_CACHE_HOME="$WORKSPACE_TEST_DIR/cache"
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/python.lua
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/core.lua
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/tasks.lua
python3 tests/tui.py
