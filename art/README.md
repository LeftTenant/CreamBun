# Art Guidelines

This folder holds the original source assets for CreamBun. Resources derived from these files
(imported fonts, tilesets, sprites) live under `resources/` — never reference `art/` from game
code or Godot project configuration files at runtime.

---

## Sprite and Tile Size Rule

**Author all world tiles and character/object sprites in multiples of 16 px** (16, 32, 48, 64, …).
The base tile is **16×16 px**.

### Why 16 px?

The game renders at a **320×180** base viewport. 16 divides 320 exactly: 320 ÷ 16 = **20 tiles
wide**. This means every row of world tiles lines up to a clean pixel boundary, there are no
fractional-pixel gaps, and integer scaling (2×, 3×, 4× …) keeps every sprite perfectly sharp at
any window size.

### The 0.25-tile vertical quirk

180 ÷ 16 = **11.25** — the viewport is *not* an exact number of tiles tall. That trailing 0.25
(4 px) is deliberate and harmless:

- The world **scrolls** via a `Camera2D`. The camera shows a 180 px-tall slice of a much larger
  map, so the viewport never needs to contain a whole number of tiles from top to bottom. The
  camera simply moves and the 4 px remainder is invisible during play.
- If you ever need a background that fills the *exact* screen height, design it as a **180 px**
  art piece (not "11.25 tiles"). UI is measured in raw pixels, not tiles.

### UI is different — raw pixels, not tiles

The notebook book-frame, HUD elements, and other UI art are sized in **pixels**, not tile units.
The 16-tile grid is for the game world. The notebook, for example, is designed at roughly
280×160 px to fit inside the 320×180 viewport with margins — that has nothing to do with tiles.

### Quick reference

| Concept | Value |
|---|---|
| Base tile | 16×16 px |
| Viewport width | 320 px = 20 tiles exactly |
| Viewport height | 180 px = 11.25 tiles (camera absorbs the remainder) |
| Sprite sizes | 16, 32, 48, 64, … (multiples of 16 only) |
| UI sizes | Raw pixels (not tile multiples) |

### What to avoid

- **Non-multiples** (e.g. 24×24, 40×40) — these cause sub-pixel misalignment when the tile grid
  and sprite edges don't coincide, especially visible on diagonal iso tiles.
- **Changing the tile size** — 16 px is the project standard. If a future system needs tiles
  that divide 180 evenly (e.g. 12 px or 9 px), that is a project-level decision, not an art
  guideline change. Raise it with the team rather than quietly authoring at a different size.

---

## Optional tooling — pixel-plugin (Aseprite)

The `.aseprite` sources in this folder can be driven from Claude Code by
[pixel-plugin](https://github.com/willibrandon/pixel-plugin), which creates, animates, and exports
pixel art through natural language. It is **entirely optional** — nothing in the game, the build,
or the test suite depends on it, and you only want it if you actually edit sprites.

It is deliberately *not* vendored into this repo (unlike `plugins/godot-testing/`, which ships a
GDScript file the project needs at runtime and so has to live here). pixel-plugin is a third-party
tool with its own upstream, so we install it per-developer and let it update itself.

### Prerequisites

**Aseprite must already be installed**, and the plugin drives your local copy. It is a paid app —
buy it at [aseprite.org](https://www.aseprite.org/) or build it from source. Without it the plugin
loads but can't do anything.

### Install

Either run the slash command:

```
/plugin marketplace add willibrandon/pixel-plugin
/plugin install pixel-plugin@pixel-plugin
```

…or add this to your **`.claude/settings.local.json`** (per-developer, gitignored — do not put it
in the tracked `.claude/settings.json`, which would enable it for teammates who may not own
Aseprite):

```json
{
  "extraKnownMarketplaces": {
    "pixel-plugin": {
      "source": { "source": "github", "repo": "willibrandon/pixel-plugin" }
    }
  },
  "enabledPlugins": {
    "pixel-plugin@pixel-plugin": true
  }
}
```

Merge those keys alongside whatever is already in the file — don't replace it. Add `"ref": "v0.5.0"`
(or any tag) inside `source` if you'd rather pin a version than track the default branch.

### Working with it

Anything it generates still has to obey the rules above — **multiples of 16 px for world sprites**,
raw pixels for UI. The plugin does not know this project's conventions, so state the size you want
explicitly rather than accepting whatever it picks.

Keep authoring `.aseprite` sources in `art/` and exporting the derived PNG into `resources/` — the
plugin doesn't change that split, and game code must still never reference `art/` (see the top of
this file).
