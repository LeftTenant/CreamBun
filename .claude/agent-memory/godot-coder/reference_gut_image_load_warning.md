---
name: gut-image-load-import-warning
description: Image.load() on a res:// path that already has a .import (texture) definition triggers an engine warning that GUT counts as a test failure, independent of any explicit assertion
type: reference
---

Calling `Image.load("res://some/imported/texture.png")` directly (bypassing
`load()`/the resource cache) emits the engine warning:

> Loaded resource as image file, this will not work on export: '<path>'.
> Instead, import the image file as an Image resource and load it normally
> as a resource.

Godot always emits this for any project image path that already has a
`.import` file mapping it to `CompressedTexture2D` (i.e. every ordinary
texture asset under `resources/`). It fires regardless of the image's pixel
dimensions or content — it is about the *loading technique*, not the data.

GUT's default unexpected-error tracking treats any engine warning/error
surfaced during a test as an automatic failure, layered on top of whatever
the test explicitly asserted. So a test can have its real `assert_eq(...)`
pass (visible in the GUT log's total `Asserts N/M` count being higher than
the reported failing-test count) while GUT still reports the test as
"failing" — the failure message shows only `Unexpected Errors: [1] ...`,
with no assertion-mismatch text.

**Why:** encountered on the world-collision Slice 2 tile-rescale task —
`tests/unit/resources/sprites/terrain/test_terrain_tile_dimensions.gd`
intentionally uses `Image.load()` to read the true on-disk pixel size
(bypassing the import cache), per its own docstring. This is a deliberate,
reasonable technique, but it collides with GUT's zero-tolerance-for-warnings
policy in this project's config.

**How to apply:** when a test reports failing but the failure body is only
an `Unexpected Errors:` block quoting an engine WARNING (not an assert
message), check the GUT log's `Asserts X/Y` line — if X is only a couple
short of Y, the content assertions likely passed and the "failure" is
environmental noise from this warning class, not a code defect. Don't
"fix" production code to chase it, and don't weaken the test's assertions —
flag it to the user as a pre-existing test/tooling friction. (This is
specifically about `Image.load()` vs. imported textures; it is not a
general GUT flakiness pattern.)
