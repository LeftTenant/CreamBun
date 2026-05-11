#!/usr/bin/env bash
# Self-bootstrapping launcher for the testing-sandbox MCP server.
#
# Why this script exists: Claude Code spawns the MCP server with the path
# configured in .mcp.json. We can't ask contributors to "remember to pip
# install mcp first" — so the launcher creates a project-local venv and
# installs requirements on first run, then re-execs the Python server.
# Subsequent runs detect the venv and skip straight to exec.
#
# Diagnostic output goes to stderr (Claude Code logs MCP server stderr).
# stdout is reserved for the MCP JSON-RPC stream.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$DIR/.venv"
PY="$VENV/bin/python"
REQ="$DIR/requirements.txt"
STAMP="$VENV/.installed-from"

# Pick the first available Python 3 interpreter on PATH for venv creation.
if command -v python3 >/dev/null 2>&1; then
    SYSTEM_PY="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    SYSTEM_PY="$(command -v python)"
else
    echo "[testing-sandbox] python3 not found on PATH; cannot start MCP server" >&2
    exit 127
fi

# Recreate the venv if it's missing or its Python is broken (e.g. user
# upgraded their system Python and broke the symlinks).
if [ ! -x "$PY" ]; then
    echo "[testing-sandbox] creating venv at $VENV (first-time setup)..." >&2
    rm -rf "$VENV"
    "$SYSTEM_PY" -m venv "$VENV" >&2
fi

# Reinstall requirements when the file changes (sha mismatch). This keeps the
# venv in sync without forcing a manual reinstall after pulling updates.
if [ -f "$REQ" ]; then
    REQ_HASH="$(shasum -a 256 "$REQ" 2>/dev/null | awk '{print $1}' || echo "")"
    PREV_HASH="$(cat "$STAMP" 2>/dev/null || echo "")"
    if [ "$REQ_HASH" != "$PREV_HASH" ]; then
        echo "[testing-sandbox] installing/updating Python deps..." >&2
        "$PY" -m pip install --quiet --upgrade pip >&2
        "$PY" -m pip install --quiet -r "$REQ" >&2
        echo "$REQ_HASH" > "$STAMP"
    fi
fi

exec "$PY" "$DIR/mcp_server.py" "$@"
