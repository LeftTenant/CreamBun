"""Visual Testing Sandbox MCP server.

Exposes the in-Godot HTTP testing server (godot/testing_server.gd) as MCP
tools so Claude Code agents can drive the game programmatically. See
docs/testing-sandbox.md for the architecture.

Tools fall into three groups:

  Process management  — launch_game, stop_game
  Testing sandbox     — 1:1 proxies for the in-Godot HTTP commands
  GUT test runner     — run_gut_tests (headless), configure_godot, get_config

Configuration via environment variables (set in the plugin's .mcp.json):

    GODOT_PROJECT_PATH   absolute path to the project root containing
                         project.godot. Defaults to two levels above this
                         file, which is correct when the plugin lives at
                         <project>/plugins/godot-testing/.
    GODOT_BIN            path to a Godot 4 executable. If unset, we check
                         the persistent config file, then probe common
                         locations across macOS / Linux.
    TESTING_SERVER_PORT  port the in-Godot server is listening on
                         (default 9080).

The Godot binary path is persisted to server/.config.json after first
successful detection so that subsequent MCP server restarts skip the probe.
Use the configure_godot tool (or set GODOT_BIN) to override.

Run via stdio (Claude Code launches us automatically); not meant to be invoked
by hand. To smoke-test by hand, see the curl example in docs/testing-sandbox.md.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_CONFIG_PATH = Path(__file__).resolve().parent / ".config.json"


def _load_config() -> dict:
    """Read the persistent config file, returning {} on any failure."""
    try:
        return json.loads(_CONFIG_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def _save_config(config: dict) -> None:
    """Write the config dict to the persistent config file."""
    _CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")


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
    """Return the first Godot 4 binary we can find on this machine.

    Checks (in order): persistent config file, common install paths on
    macOS/Linux, then PATH lookup."""
    saved = _load_config().get("godot_bin", "")
    if saved and os.path.exists(saved):
        return saved

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

# Persist the discovered binary so future startups skip the probe.
if GODOT_BIN and os.path.exists(GODOT_BIN):
    _cfg = _load_config()
    if _cfg.get("godot_bin") != GODOT_BIN:
        _cfg["godot_bin"] = GODOT_BIN
        _save_config(_cfg)
        print(f"[testing-sandbox] saved Godot binary: {GODOT_BIN}", file=sys.stderr)

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
# Setup & configuration tools
# ---------------------------------------------------------------------------

@mcp.tool()
def get_config() -> dict:
    """Return the current plugin configuration: Godot binary path, project
    path, testing server port, and whether each was auto-detected or
    explicitly set."""
    env_bin = os.environ.get("GODOT_BIN", "")
    saved_bin = _load_config().get("godot_bin", "")
    return {
        "godot_bin": GODOT_BIN,
        "godot_bin_source": (
            "GODOT_BIN env var" if env_bin
            else "config file" if saved_bin and saved_bin == GODOT_BIN
            else "auto-detected" if GODOT_BIN
            else "not found"
        ),
        "godot_bin_exists": bool(GODOT_BIN) and os.path.exists(GODOT_BIN),
        "project_path": GODOT_PROJECT_PATH,
        "testing_server_port": PORT,
    }


@mcp.tool()
def configure_godot(godot_bin: str) -> dict:
    """Persistently set the Godot binary path. The path is saved to a config
    file so it survives MCP server restarts. Pass an empty string to clear
    the saved path and fall back to auto-detection on next restart."""
    global GODOT_BIN

    if godot_bin and not os.path.exists(godot_bin):
        raise RuntimeError(
            f"Path does not exist: {godot_bin}. "
            "Provide the absolute path to the Godot 4 executable."
        )

    cfg = _load_config()
    if godot_bin:
        cfg["godot_bin"] = godot_bin
        GODOT_BIN = godot_bin
    else:
        cfg.pop("godot_bin", None)
        GODOT_BIN = _detect_godot_bin()
    _save_config(cfg)

    return {
        "godot_bin": GODOT_BIN,
        "saved": bool(godot_bin),
        "message": (
            f"Saved Godot binary path: {GODOT_BIN}"
            if godot_bin
            else f"Cleared saved path; auto-detected: {GODOT_BIN or 'not found'}"
        ),
    }


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
            "Use the configure_godot tool or set GODOT_BIN in the plugin's "
            ".mcp.json to the absolute path of your Godot 4 executable."
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
# GUT test runner
# ---------------------------------------------------------------------------

@mcp.tool()
def run_gut_tests(
    directory: str = "",
    select: str = "",
    tests: list[str] | None = None,
    include_subdirs: bool = True,
    log_level: int = 1,
    inner_class: str = "",
    unit_test_name: str = "",
    timeout_seconds: int = 120,
) -> dict:
    """Run GUT tests headlessly and return the output.

    This is the primary way to execute unit and integration tests. The tool
    handles locating the Godot binary and building the correct command line —
    callers never need to know the binary path or construct Bash commands.

    Args:
        directory: GUT -gdir flag. Run all tests under this res:// directory
            (e.g. "res://tests/unit/"). Mutually exclusive with `tests`.
        select: GUT -gselect flag. Filter by filename within `directory`
            (e.g. "test_inventory_tab.gd").
        tests: GUT -gtest flag. List of specific res:// test file paths to
            run (e.g. ["res://tests/unit/test_foo.gd"]). Mutually exclusive
            with `directory`.
        include_subdirs: Include subdirectories when using `directory`.
        log_level: GUT -glog verbosity (0=errors only, 1=default, 2=verbose,
            3=debug).
        inner_class: GUT -ginner_class flag. Run only this inner test class.
        unit_test_name: GUT -gunit_test_name flag. Run only this specific
            test method.
        timeout_seconds: Max seconds to wait for the test run (default 120).

    Returns:
        {"output": "...", "returncode": 0, "passed": true}
    """
    if not GODOT_BIN or not os.path.exists(GODOT_BIN):
        raise RuntimeError(
            f"Godot binary not found ({GODOT_BIN or 'not configured'}). "
            "Use the configure_godot tool to set the path."
        )
    if not GODOT_PROJECT_PATH:
        raise RuntimeError("Project path not configured.")

    gut_script = "addons/gut/gut_cmdln.gd"
    gut_path = os.path.join(GODOT_PROJECT_PATH, gut_script)
    if not os.path.exists(gut_path):
        raise RuntimeError(
            f"GUT not found at {gut_script}. Install GUT via the Godot "
            "Asset Library or from https://github.com/bitwes/Gut"
        )

    cmd = [GODOT_BIN, "--headless", "--path", GODOT_PROJECT_PATH,
           "-s", f"res://{gut_script}"]

    if tests:
        cmd.append(f"-gtest={','.join(tests)}")
    elif directory:
        cmd.append(f"-gdir={directory}")
        if select:
            cmd.append(f"-gselect={select}")
        if include_subdirs:
            cmd.append("-ginclude_subdirs")

    if inner_class:
        cmd.append(f"-ginner_class={inner_class}")
    if unit_test_name:
        cmd.append(f"-gunit_test_name={unit_test_name}")

    cmd.append(f"-glog={log_level}")
    cmd.append("-gexit")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            cwd=GODOT_PROJECT_PATH,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(
            f"GUT test run timed out after {timeout_seconds}s. "
            "Try a narrower test selection or increase timeout_seconds."
        )

    output = result.stdout + result.stderr
    passed = result.returncode == 0

    return {
        "output": output,
        "returncode": result.returncode,
        "passed": passed,
    }


# ---------------------------------------------------------------------------
# Observation tools
# ---------------------------------------------------------------------------

@mcp.tool()
def screenshot(save_to: str = "") -> dict:
    """Capture the current viewport frame.

    Without `save_to`, returns {image: "<base64 PNG>"} — convenient for ad-hoc
    inspection but heavy on context (a typical frame is tens of KB of base64).

    With `save_to` set to an absolute filesystem path (or res:// / user:// URI),
    writes the PNG directly to disk on the Godot side and returns
    {saved: "<path>"}. Use this for baseline captures during scenario runs:
    read the resulting file back with the Read tool when visual review is
    needed.
    """
    return _send("screenshot", save_to=save_to)


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
