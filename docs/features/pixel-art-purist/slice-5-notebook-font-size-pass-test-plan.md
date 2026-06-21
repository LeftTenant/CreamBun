# Slice 5 — Notebook Font-Size Pass (Body 8 / Heading 16) — Test Plan

Source design: `docs/refactors/pixel-art-purist-size-and-theme.md` §6.3, §3, §4
Slice spec: `docs/features/pixel-art-purist/slices.md` — Slice 5

## Background for reviewers

The base theme (Slices 1–2) establishes Default Font Size = 8 and a `Heading` Label type
variation at size 16. This slice's job is purely assignment: heading Labels get
`theme_type_variation = "Heading"`; body Labels get NO per-node font-size override so they
inherit 8 from the theme cascade. The only existing violations found by reading the scenes are
in `equipment_slot.tscn`, which hard-codes `theme_override_font_sizes/font_size = 12` on
`SlotLabel` and `= 10` on `ItemNameLabel` — both must be removed.

**User decisions on judgment calls (recorded 2026-06-16):**
- `SlotLabel` in `equipment_slot.tscn` is **BODY 8, NOT heading.** Remove its hardcoded
  `font_size = 12` override so it inherits 8 from the theme. Differentiate it from
  `ItemNameLabel` by **color only**: SlotLabel uses `ink`, ItemNameLabel uses `ink_muted`.
  Both drop their hardcoded `font_size` overrides.
- `CompletedSeparator` in `quests_tab.tscn` is **BODY 8** with `ink_muted` color, NOT a heading.
- Tab titles and the close hint ("I to open/close • Esc to close") are **DEFERRED to a
  separate task**. They do not yet exist as Labels in any scene and are out of scope for
  Slice 5. Do not add them; do not test for them.

The `notebook.gd` reparent pattern (only `LeftPage`/`RightPage` subtrees are mounted at runtime)
means that any `theme_type_variation` set on a Label inside those subtrees takes effect at
runtime; variations on the editor-preview root of a tab scene do not cascade into the game.

---

### E2E

- [ ] Open the notebook at a 1× window (320×180 effective viewport); navigate to the Inventory
  tab and confirm that heading text (e.g. "Equipment") reads visibly larger than body text
  (e.g. inventory row names, the weight readout), and that body-8 text is legible
  (individual characters are distinguishable, not blurred or crushed to solid blocks).
- [ ] Open the notebook at 1× and navigate to the Quests tab; confirm quest title text reads at
  heading size and description / objective bullet text reads at body size.
- [ ] Open the notebook at 1× and navigate to the Map tab; confirm "World Map" and "Local Area"
  headings read at heading size and placeholder notes read at body size.
- [ ] Open the notebook at 1× and navigate to the Settings tab; confirm section headings
  ("Audio", "Gameplay", "Display") read at heading size and slider-caption labels read at body
  size.
- [ ] Open the notebook at 1× and navigate to the Sessions tab; confirm Story name labels read
  at heading size and secondary labels ("Last played: …") read at body size.

_Note: tab title Labels and the close hint Label are deferred to a separate task and are not
part of this slice's E2E coverage._

---

### Integration

- [ ] Open the notebook via `open_notebook_inventory` input action; verify the Inventory tab
  renders with the theme cascade active (the `Book` Panel in `notebook.tscn` carries the base
  theme and all descendant Labels inherit it without each tab needing its own theme assignment).
- [ ] Switch tabs using `notebook_page_next`; verify the incoming tab's Labels reflect the same
  theme cascade (no Labels in the new tab revert to a default Godot font or un-themed size).

---

### Unit

The unit assertions below are all scene-as-data checks: load the `PackedScene`, instantiate it,
walk named nodes, and assert properties. No autoload or runtime state is needed.

**`equipment_slot.tscn` — fix existing font-size overrides and differentiate by color**

- [ ] `SlotLabel` (path `HBox/TextVBox/SlotLabel`) has no `theme_override_font_sizes/font_size`
  set (the hardcoded override of 12 has been removed so it inherits the base-theme default of 8).
- [ ] `ItemNameLabel` (path `HBox/TextVBox/ItemNameLabel`) has no
  `theme_override_font_sizes/font_size` set (the hardcoded override of 10 has been removed).
- [ ] `SlotLabel` has NO `theme_type_variation` set (it is body text at 8; differentiated from
  `ItemNameLabel` by color, not size).
- [ ] `SlotLabel` has `theme_override_colors/font_color` set to the `ink` palette value
  (`#3b2f2a` / Color(0.231, 0.184, 0.165, 1.0)).
- [ ] `ItemNameLabel` has no `theme_type_variation` set (body text at 8).
- [ ] `ItemNameLabel` has `theme_override_colors/font_color` set to the `ink_muted` palette value
  (`#7a6a5d` / Color(0.478, 0.416, 0.365, 1.0)).

**`inventory_tab.tscn` — headings vs body on Inventory tab**

- [ ] `LeftPage/EquipmentHeader` Label has `theme_type_variation` set to `"Heading"` (the
  "Equipment" section header is a heading; it receives size 16 via the variation).
- [ ] `LeftPage/EquipmentHeader` Label has no `theme_override_font_sizes/font_size` set (size
  comes only from the variation, not a hard override).
- [ ] `RightPage/WeightLabel` Label has no `theme_type_variation` set (weight readout is body
  text at size 8).
- [ ] `RightPage/WeightLabel` Label has no `theme_override_font_sizes/font_size` set.

**`inventory_row.tscn` — all body text**

- [ ] `HBox/NameLabel` has no `theme_type_variation` set and no `theme_override_font_sizes`.
- [ ] `HBox/CountLabel` has no `theme_type_variation` set and no `theme_override_font_sizes`.
- [ ] `HBox/WeightLabel` has no `theme_type_variation` set and no `theme_override_font_sizes`.

**`map_tab.tscn` — headings vs body on Map tab**

- [ ] `LeftPage/WorldMapHeading` Label has `theme_type_variation` set to `"Heading"` ("World
  Map" is a page heading).
- [ ] `LeftPage/WorldMapHeading` Label has no `theme_override_font_sizes/font_size` set.
- [ ] `LeftPage/WorldMapNote` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes` (placeholder note is body text).
- [ ] `RightPage/LocalAreaHeading` Label has `theme_type_variation` set to `"Heading"` ("Local
  Area" is a page heading).
- [ ] `RightPage/LocalAreaHeading` Label has no `theme_override_font_sizes/font_size` set.
- [ ] `RightPage/LocalMapNote` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes`.

**`quests_tab.tscn` — headings vs body on Quests tab**

- [ ] `LeftPage/CompletedSeparator` Label has NO `theme_type_variation` set (it is body text
  at 8, differentiated from quest rows by `ink_muted` color only, not size).
- [ ] `LeftPage/CompletedSeparator` Label has no `theme_override_font_sizes/font_size` set.
- [ ] `LeftPage/CompletedSeparator` Label has `theme_override_colors/font_color` set to the
  `ink_muted` palette value.
- [ ] `RightPage/QuestDetail/TitleLabel` Label has `theme_type_variation` set to `"Heading"`
  (quest title is a heading).
- [ ] `RightPage/QuestDetail/TitleLabel` Label has no `theme_override_font_sizes/font_size` set.
- [ ] `RightPage/QuestDetail/DescriptionLabel` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes` (description is body text).
- [ ] `RightPage/QuestDetail/ObjectivesContainer/SampleObjective1` and `SampleObjective2` Labels
  have no `theme_type_variation` set and no `theme_override_font_sizes` (objective bullets are
  body text).
- [ ] `RightPage/Placeholder` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes` (the "Select a quest…" placeholder is body text).

**`quest_row.tscn` — quest list row (body text)**

- [ ] `TitleLabel` has no `theme_type_variation` set and no `theme_override_font_sizes` (quest
  row title in the list is body text; the detail pane's `TitleLabel` is the heading).

**`settings_tab.tscn` — section headings vs field captions**

- [ ] `LeftPage/AudioLabel` Label has `theme_type_variation` set to `"Heading"` ("Audio" is a
  section heading).
- [ ] `LeftPage/MasterVolumeLabel`, `MusicVolumeLabel`, `SfxVolumeLabel` Labels have no
  `theme_type_variation` set and no `theme_override_font_sizes` (volume slider captions are body
  text).
- [ ] `RightPage/GameplayLabel` Label has `theme_type_variation` set to `"Heading"` ("Gameplay"
  is a section heading).
- [ ] `RightPage/DisplayLabel` Label has `theme_type_variation` set to `"Heading"` ("Display" is
  a section heading).
- [ ] `RightPage/TextSpeedLabel` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes` (slider caption, body text).

**`sessions_tab.tscn` — Sessions tab**

- [ ] `RightPage/Placeholder` Label has no `theme_type_variation` set and no
  `theme_override_font_sizes` (the "Select a Story…" placeholder is body text).

**`story_card.tscn` — Story card**

- [ ] `NameLabel` has `theme_type_variation` set to `"Heading"` (the Story name is the heading
  of its card).
- [ ] `LastPlayedLabel` has no `theme_type_variation` set and no `theme_override_font_sizes`
  (secondary metadata, body text).

_Note: Tab title Labels and the close hint Label are DEFERRED to a separate task. They do not
exist in any scene as of Slice 5 and are out of scope. No tests are written for them here._

---

## Judgment calls and scope notes

**body-8 legibility risk.** At 320×180, size-8 monogram glyphs are 3 px wide × 6 px tall.
This is the worst-case size and may prove too small for comfortable reading during playtest. The
E2E item for the Inventory tab targets this risk directly. If the e2e screenshot reveals that
body-8 is visually indistinguishable or unreadable, the correct escalation is to ask the user
whether to bump the entire body default to 16 (changing `Default Font Size` in `base_theme.tres`)
— do not silently introduce size 12 or any non-multiple of 8/16, as the design explicitly rejects
non-multiples. Changing the body default is a Slice 1 resource edit, not a per-node override.

**SlotLabel — resolved as body+ink (2026-06-16).** `SlotLabel` is body text at 8, differentiated
from `ItemNameLabel` by `ink` vs `ink_muted` color only. No `Heading` variation is applied.

**`CompletedSeparator` — resolved as body+ink_muted (2026-06-16).** The "— Completed —" label
is body text at 8 with `ink_muted` color. No `Heading` variation is applied.

**Tab title and close hint — deferred (2026-06-16).** These Labels do not yet exist in any
scene and are explicitly out of scope for Slice 5. They will be designed and added in a
separate task, at which point their typography decisions will be recorded in a new test plan.

**`quest_row.tscn` `TitleLabel` — body, not heading.** The list-row title displays a quest name
in the left-page quest list. At size 8 this will be small but matches every other row in the
list. The heading treatment is reserved for the detail-pane `TitleLabel` (in `quests_tab.tscn`),
not the row. If playtest shows the row title is too small to scan quickly, the correct fix is
a color or weight differentiation within body-8 (e.g. `ink` vs `ink_muted`), not a size change.

**`notebook.tscn` cascade point already confirmed.** The theme is set on `Book` (the `Panel`
node), which cascades to `Pages`, `LeftPage`, and `RightPage`. Tab content is reparented into
`LeftPage`/`RightPage` at runtime, so it inherits from that cascade. No per-tab `theme` property
is needed; the unit test for the cascade point is covered in Slice 2's test plan.
