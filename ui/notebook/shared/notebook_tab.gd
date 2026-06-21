class_name NotebookTab
extends Control
## Base class for all notebook tab scenes.
## Each tab extends this and overrides populate_left / populate_right.
## The root notebook scene calls these when it swaps page content.
##
## In Phase 1 both methods are no-ops. Subclasses in later phases will
## add their UI by appending child nodes to the given parent Control so
## the notebook's page layout stays in control of the physical page bounds.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Uniform inset (in pixels) applied to both pages of every tab.
## All four edges (left, top, right, bottom) use this value so the margins
## between page content and the notebook's outer edge, and between page
## content and the centre Divider, are identical.
##
## Defined here — not in individual tab files — so there is a single place to
## change the inset for all tabs at once and it cannot drift between tabs.
const PAGE_INSET: int = 8


# ---------------------------------------------------------------------------
# Protected helpers
# ---------------------------------------------------------------------------

## Anchor [param page] to fill its parent and inset its content by PAGE_INSET
## on all sides, so every tab gets identical, symmetric page margins.
##
## WHY this helper exists:
## Without explicit anchoring, a plain Control parent (like LeftPage /
## RightPage in notebook.tscn) does not resize its children — the VBox would
## shrink to minimum size and potentially overflow the page boundary.
## Calling PRESET_FULL_RECT sets all four anchors to their extremes so the
## VBox tracks the parent Control's full rect, then the positive left/top and
## negative right/bottom offsets pull each edge inward by PAGE_INSET pixels.
## (Negative right/bottom values reduce because anchors sit at 1.0 and the
## offset is subtracted — see ui/CLAUDE.md rules 1 & 2.)
##
## Centralising the call here prevents the per-tab populate_left/right methods
## from each duplicating the same 5-line block with a hardcoded value that
## can drift independently.
##
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
func _apply_page_inset(page: Control) -> void:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left   =  PAGE_INSET
	page.offset_top    =  PAGE_INSET
	page.offset_right  = -PAGE_INSET
	page.offset_bottom = -PAGE_INSET


# ---------------------------------------------------------------------------
# Public methods (override in subclasses)
# ---------------------------------------------------------------------------

## Called by the notebook when this tab becomes active.
## Subclasses should populate the left page with their content here.
## @param parent - the Control node that will hold left-page children.
##                 May be null in unit tests; implementations must guard.
func populate_left(parent: Control) -> void:
	pass


## Called by the notebook when this tab becomes active.
## Subclasses should populate the right page with their content here.
## @param parent - the Control node that will hold right-page children.
##                 May be null in unit tests; implementations must guard.
func populate_right(parent: Control) -> void:
	pass
