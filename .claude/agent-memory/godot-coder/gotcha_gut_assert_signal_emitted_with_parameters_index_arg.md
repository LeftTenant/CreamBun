---
name: gotcha-gut-assert-signal-emitted-with-parameters-index-arg
description: GUT's assert_signal_emitted_with_parameters()'s 4th positional arg is an emission index, not a failure message
type: reference
---

Unlike almost every other GUT assert (`assert_eq`, `assert_true`, `assert_signal_emit_count`,
...), `assert_signal_emitted_with_parameters(object, signal_name, parameters, index=-1)`'s 4th
positional argument is an **emission index** (which past emission of the signal to check,
default -1 = most recent) — **not** a trailing description string, even though the convention
everywhere else in this codebase's tests is "last positional arg = optional failure message."

**Symptom if you pass a message string there anyway:** GUT throws real engine script errors, not
a clean assertion failure —
`Invalid operands 'String' and 'int' in operator '=='` (from `signal_watcher.gd`'s
`if(index == -1):`) followed by `Invalid call. Nonexistent function 'size' in base 'Nil'` (from
`diff_tool.gd`, since `get_signal_parameters()` returned null after the bad index comparison). The
GUT doc comment above the function (`addons/gut/test.gd`, ~line 1600) spells out the correct
4-arg form with an actual index example (`assert_signal_emitted_with_parameters(obj, 'some_signal',
[1, 2, 3], 0)`).

**How to apply:** never pass a 4th argument to `assert_signal_emitted_with_parameters()` unless it
is genuinely an emission index. Drop the trailing message entirely (matching
`test_player_data_foundation.gd`'s and `test_notebook_shell.gd`'s existing correct usage) rather
than trying to shoehorn a description in. If a message is wanted, split the check into
`assert_signal_emit_count(...)` (which *does* take a trailing message correctly) plus a plain
`assert_eq()` against `get_signal_parameters(...)`.
