# Test plan — Issue #26: notebook page-cycle key collides with UI focus key

## Bug
`notebook.gd` `_unhandled_input()` binds page cycling to the built-in
`ui_focus_next` (Tab) / `ui_focus_prev` (Shift+Tab) actions. Because the binding
lives in `_unhandled_input`, it only fires when no Control has focus. Once any
Control (e.g. a Settings slider) is focused, that control consumes Tab first for
normal focus navigation, so page cycling silently breaks.

## Fix under test
- New input actions `notebook_page_next` (PageUp) and `notebook_page_prev`
  (PageDown) replace the Tab/Shift+Tab page-cycling bindings.
- Tab/Shift+Tab are freed for normal UI focus navigation.

## Checklist — integration tests (tests/integration/notebook/test_notebook_shell.gd)

- [x] `test_notebook_page_cycle_actions_exist` — `InputMap.has_action` is true for
      both `notebook_page_next` and `notebook_page_prev`.
      (FAILS pre-fix: actions don't exist in project.godot.)
- [x] `test_notebook_input_page_next_cycles_forward` — PageUp from INVENTORY(0)
      advances `_current_tab` to MAP(1).
      (FAILS pre-fix: notebook.gd ignores notebook_page_next.)
- [x] `test_notebook_input_page_prev_cycles_backward_with_wrap` — PageDown from
      INVENTORY(0) wraps backward to SESSIONS(4).
      (FAILS pre-fix: notebook.gd ignores notebook_page_prev.)
- [x] `test_notebook_input_ui_focus_does_not_change_tab` — `ui_focus_next` and
      `ui_focus_prev` leave `_current_tab` unchanged while the notebook is open.
      (FAILS pre-fix: those actions still cycle the tab.)

## Expected
All four FAIL against current code (proving the bug), and PASS after the fix.
