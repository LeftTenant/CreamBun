# Equip Slot Selected-Text Contrast (Issue #45) — Test Plan

### Unit
- [x] Filled + selected slot: `ItemNameLabel` gets a runtime `font_color` override equal to theme `ink` (`#3b2f2a`), not the `.tscn`-baked `ink_muted`
- [x] Filled + selected, then `set_selected(false)`: `ItemNameLabel` renders `ink_muted` again (re-applied, not cleared — removal would fall through to engine-default white, since `base_theme.tres` sets no `Label/font_color` default)
- [x] Filled, never selected: `ItemNameLabel` still renders in `ink_muted` (no regression to the existing unselected look)
- [x] Slot becomes empty via `setup(slot, null)` while previously selected+filled: no stale `ink` override survives the unequip
