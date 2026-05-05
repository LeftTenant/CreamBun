class_name LocalMap
extends Control
## Stub for the local area map shown on the right page of the Map tab.
##
## Phase 1: displays a placeholder ColorRect and label so the page is not
## blank while the real art is pending.
##
## Phase 2 will render a static SubViewport snapshot of the current area
## showing only terrain and significant landmarks (buildings, bridges, major
## trees, bodies of water) — not item-level detail. Because the map only shows
## terrain, it never needs to update when the world mutates (picked plants, etc.),
## making a static Texture2D snapshot sufficient. A fog-of-war bitmask overlay
## (Image/ImageTexture, one bit per explored chunk of ~8×8 tiles) is applied on
## top, and Cream Bun's current position is drawn as a small pin sprite.
##
## Design doc: docs/features/notebook/design.md §5.3 (Map tab — right page)
