"""Visual Testing Sandbox MCP server.

Exposes the in-Godot HTTP testing server (godot/testing_server.gd) as MCP
tools so Claude Code agents can drive the game programmatically. See
docs/testing-sandbox.md for the architecture.

Two tools wrap the OS process (launch_game, stop_game); the rest are 1:1
proxies for HTTP commands the Godot side already implements.

Configuration via environment variables (set in the plugin's .mcp.json):

    GODOT_PROJECT_PATH   absolute path to the project root containing
                         project.godot. Defaults to two levels above this
                         file, which is correct when the plugin lives at
                         <project>/plugins/godot-testing/.
    GODOT_BIN            path to a Godot 4 executable. If unset, we probe a
                         list of common locations across macOS / Linux.
    TESTING_SERVER_PORT  port the in-Godot server is listening on
                         (default 9080).

Run via stdio (Claude Code launches us automatically); not meant to be invoked
by hand. To smoke-test by hand, see the curl example in docs/testing-sandbox.md.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


def _default_project_path() -> str:
    """Walk up from this file looking for project.godot.

    The plugin canonically lives at <project>/plugins/godot-testing/server/, so
    the default is two parents up. We still walk to be resilient against
    contributors who relocate the plugin or use a non-standard layout."""
    here = Path(__file__).resolve()
    for candidate in [here.parent.parent.parent, *here.parents]:
        if (candidate / "project.godot").exists():
            return str(candidate)
    return ""


def _detect_godot_bin() -> str:
    """Return the first Godot 4 binary we can find on this machine."""
    # Order: explicit env var (handled by caller), then common locations on
    # macOS and Linux, then PATH lookup as last resort.
    candidates = [
        "/Applications/Godot.app/Contents/MacOS/Godot",
        "/Applications/Godot_mono.app/Contents/MacOS/Godot",
        "/usr/local/bin/godot4",
        "/usr/bin/godot4",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    for name in ("godot4", "godot"):
        found = shutil.which(name)
        if found:
            return found
    return ""


GODOT_PROJECT_PATH = os.environ.get("GODOT_PROJECT_PATH") or _default_project_path()
GODOT_BIN = os.environ.get("GODOT_BIN") or _detect_godot_bin()
PORT = int(os.environ.get("TESTING_SERVER_PORT", "9080"))
SERVER_URL = f"http://127.0.0.1:{PORT}"

# Single-process model: at most one Godot instance owned by this MCP server.
_godot_process: subprocess.Popen | None = None

mcp = FastMCP("testing-sandbox")


# ---------------------------------------------------------------------------
# HTTP helper
# ---------------------------------------------------------------------------

def _send(command: str, **params: Any) -> dict:
    """POST a command to the in-Godot HTTP server and return its JSON reply.

    Raises RuntimeError on transport failures or non-2xx status. The Godot side
    encodes domain errors as 4xx with a JSON {"error": "..."} body, which we
    surface verbatim so MCP callers see the message.
    """
    payload = {"command": command, **params}
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        SERVER_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        # Godot returns JSON for 4xx; pass it back so the agent sees the reason.
        try:
            return json.loads(e.read().decode("utf-8"))
        except Exception:
            raise RuntimeError(f"HTTP {e.code} from testing server") from e
    except urllib.error.URLError as e:
        raise RuntimeError(
            f"Could not reach testing server at {SERVER_URL}: {e.reason}. "
            "Is the game running? Try launch_game."
        ) from e


def _ping() -> bool:
    """True if the in-Godot server is reachable."""
    try:
        _send("get_game_state")
        return True
    except RuntimeError:
        return False


# ---------------------------------------------------------------------------
# Process management tools
# ---------------------------------------------------------------------------

@mcp.tool()
def launch_game(timeout_seconds: int = 30) -> dict:
    """Start Godot with the configured project. Blocks until the in-Godot
    testing server responds, or the timeout elapses. No-ops if a game is
    already running and reachable."""
    global _godot_process

    if _ping():
        return {"ok": True, "already_running": True}

    if not GODOT_PROJECT_PATH:
        raise RuntimeError(
            "Could not locate project.godot. Set GODOT_PROJECT_PATH in the "
            "plugin's .mcp.json to the absolute path of your project root."
        )
    if not GODOT_BIN or not os.path.exists(GODOT_BIN):
        raise RuntimeError(
            f"Could not find a Godot 4 binary (looked for: {GODOT_BIN or 'common paths and PATH'}). "
            "Set GODOT_BIN in the plugin's .mcp.json to the absolute path of "
            "your Godot 4 executable."
        )

    _godot_process = subprocess.Popen(
        [GODOT_BIN, "--path", GODOT_PROJECT_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if _ping():
            return {"ok": True, "pid": _godot_process.pid}
        if _godot_process.poll() is not None:
            raise RuntimeError(
                f"Godot exited before testing server became available "
                f"(returncode={_godot_process.returncode})"
            )
        time.sleep(0.25)

    raise RuntimeError(
        f"Testing server did not respond within {timeout_seconds}s. "
        "Check that the TestingServer autoload is registered and the build is debug."
    )


@mcp.tool()
def stop_game() -> dict:
    """Terminate the Godot process started by launch_game."""
    global _godot_process
    if _godot_process is None or _godot_process.poll() is not None:
        _godot_process = None
        return {"ok": True, "was_running": False}

    _godot_process.send_signal(signal.SIGTERM)
    try:
        _godot_process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        _godot_process.kill()
        _godot_process.wait(timeout=2)

    _godot_process = None
    return {"ok": True, "was_running": True}


# ---------------------------------------------------------------------------
# Observation tools
# ---------------------------------------------------------------------------

@mcp.tool()
def screenshot() -> dict:
    """Capture the current viewport frame. Returns {image: "<base64 PNG>"}."""
    return _send("screenshot")


@mcp.tool()
def get_game_state() -> dict:
    """Return the current GameState enum name, e.g. {state: "PLAYING"}."""
    return _send("get_game_state")


@mcp.tool()
def get_node_property(path: str, property: str) -> dict:
    """Read a property from a node in the active scene tree.

    `path` is relative to current_scene (e.g. "Player/Inventory").
    Returns {value: <any>}; objects are stringified for JSON safety."""
    return _send("get_node_property", path=path, property=property)


# ---------------------------------------------------------------------------
# Input injection tools
# ---------------------------------------------------------------------------

@mcp.tool()
def press_action(action: str) -> dict:
    """Press a named Input Map action (e.g. "move_left", "interact").

    Hold continues until you call release_action — combine with wait_frames
    to hold-for-N-frames."""
    return _send("press_action", action=action)


@mcp.tool()
def release_action(action: str) -> dict:
    """Release a previously-pressed Input Map action."""
    return _send("release_action", action=action)


@mcp.tool()
def press_key(keycode: int, duration_frames: int = 1) -> dict:
    """Press a physical keycode for N frames, then release. Use this only for
    keys not bound to an Input Map action (most tests should prefer
    press_action / release_action)."""
    return _send("press_key", keycode=keycode, duration_frames=duration_frames)


@mcp.tool()
def mouse_button_press(x: int, y: int, button: int = 1) -> dict:
    """Press a mouse button at viewport coordinates without releasing.

    `button`: 1=left, 2=right, 3=middle. Use this with mouse_move and
    mouse_button_release to perform drags."""
    return _send("mouse_button_press", x=x, y=y, button=button)


@mcp.tool()
def mouse_button_release(x: int, y: int, button: int = 1) -> dict:
    """Release a previously-pressed mouse button at viewport coordinates."""
    return _send("mouse_button_release", x=x, y=y, button=button)


@mcp.tool()
def mouse_move(x: int, y: int) -> dict:
    """Move the cursor to viewport coordinates."""
    return _send("mouse_move", x=x, y=y)


# ---------------------------------------------------------------------------
# Test setup tools
# ---------------------------------------------------------------------------

@mcp.tool()
def emit_game_event(signal_name: str, args: list | None = None) -> dict:
    """Emit a signal on the GameEvents autoload. Fails if the signal does not
    exist. Use to set up preconditions (e.g. add an inventory item) without
    playing through the flow that normally produces them."""
    return _send("emit_game_event", signal_name=signal_name, args=args or [])


@mcp.tool()
def load_scene(path: str) -> dict:
    """Replace the current scene. `path` must be a res:// resource path."""
    return _send("load_scene", path=path)


@mcp.tool()
def wait_frames(count: int = 1) -> dict:
    """Block until N frames have elapsed. Use after input to let UI / signals
    settle before screenshotting or asserting."""
    return _send("wait_frames", count=count)


@mcp.tool()
def reset_state() -> dict:
    """Reload the current scene and reset GameState to PLAYING. Does NOT reset
    autoload state (SaveManager, etc.) — for a clean autoload state, use
    stop_game + launch_game."""
    return _send("reset_state")


if __name__ == "__main__":
    mcp.run()
