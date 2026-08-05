# Sandbox Mouse Input (Issue #41) — Test Plan

Issue: mouse events injected by the testing-sandbox plugin
(`mouse_move` / `mouse_button_press` / `mouse_button_release`) reached a
`Control` node's raw `button_down`/`button_up` state reliably, but
`BaseButton`'s completed `pressed` signal fired only intermittently across
repeated click cycles in the same session — not consistently absent, and not
a total routing failure. Keyboard-routed `press_action` / `release_action`
events work fine (they drive `_unhandled_input`, a different dispatch path
from GUI pointer events).

Every interactive `Control` in the project today lives inside the Notebook,
which sets `get_tree().paused = true` while open — so this bug has never been
isolated from that pause. The scope below is a **regression guard for the
sandbox's mouse plumbing itself**, independent of the notebook or any other
feature, plus a pointer at the pre-existing real-world symptom.

### E2E
- [x] A non-paused `Control` (plain `Button`) registers hover on `mouse_move` alone, before any button is pressed
- [x] A non-paused `Control` (plain `Button`) registers a full mouse-driven click — press, release, the `pressed` signal, and the resulting `button_pressed` toggle state — when driven via `mouse_move` / `mouse_button_press` / `mouse_button_release`
- [x] A second, independent click on the same `Control` registers correctly (rules out a one-shot fluke in either direction)

## Related / not re-covered here

`tests/e2e/notebook/settings_controls.md` is the pre-existing real-world
symptom (slider drag, `OptionButton` popup) and stays blocked until this bug
is fixed — its own file already documents the failed live attempt in detail.
It is not duplicated here; once the isolation scenario above proves the
sandbox's mouse plumbing works end-to-end, `settings_controls.md` becomes the
next thing to re-run to confirm the fix also holds for a paused, in-notebook
`Control`.
