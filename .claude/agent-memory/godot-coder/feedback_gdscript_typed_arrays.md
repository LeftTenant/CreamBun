---
name: GDScript typed arrays of inner enum types
description: Array[SomeClass.SomeEnum] is not valid in GDScript 4 — use plain Array instead
type: feedback
---

GDScript 4 does not support typed arrays of inner enum types such as `Array[ItemData.EquipSlot]`. This causes a parse error.

**Why:** Inner enums declared inside a class (e.g. `enum EquipSlot { ... }` inside `ItemData`) are not first-class types for GDScript's typed array syntax. Only top-level class names and primitive types are accepted.

**How to apply:** Use `Array` (untyped) for local variables that hold an array of inner enum constants. Add a comment explaining why. The loop variable can be typed as `: int` since GDScript enums are int aliases at runtime, and GDScript's parameter type checking accepts an int for an enum-typed parameter.
