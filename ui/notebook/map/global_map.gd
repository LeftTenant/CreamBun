class_name GlobalMap
extends Control
## Stub for the global world map shown on the left page of the Map tab.
##
## Phase 1: displays a placeholder ColorRect and label so the page is not
## blank while the real art is pending.
##
## Phase 2 will replace this with a TextureRect of the hand-drawn world map.
## MapDestination .tres resources will be positioned as child TextureButtons
## over their world_position coordinates. Unvisited destinations will display
## a faint "?" label instead of their name. Clicking a destination will show
## a tooltip with a "Travel here" button that emits
## GameEvents.fast_travel_requested(id) and closes the notebook.
## The player's current position will be shown as a small Cream Bun sprite
## placed beside the destination pin (not replacing it).
##
## Design doc: docs/features/notebook/design.md §5.3 (Map tab — left page)
