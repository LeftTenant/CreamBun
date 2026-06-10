class_name MapTab
extends NotebookTab
## The Map tab of the in-game notebook.
##
## Phase 1 shows placeholder content on both pages so the tab is navigable
## before the real map art is ready. The left page shows a "World Map" heading
## and a green ColorRect stand-in; the right page shows "Local Area" with a
## darker green ColorRect stand-in.
##
## Phase 2 will replace the left ColorRect with a GlobalMap instance showing
## the hand-drawn world map with MapDestination pins, and replace the right
## ColorRect with a LocalMap instance showing a static SubViewport snapshot
## with a fog-of-war overlay.
##
## Static layout (headings, placeholder rects, Phase 2 notes) lives in
## map_tab.tscn — see docs/refactors/notebook-ui-scene-migration.md.
## populate_left() / populate_right() instantiate that scene once, extract the
## LeftPage / RightPage subtrees, and reparent them into the Controls provided
## by notebook.gd. The same pattern is used in SettingsTab and InventoryTab.
##
## Design doc: docs/features/notebook/design.md §5.3 (Map tab)
## Refactor:   docs/refactors/notebook-ui-scene-migration.md


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The scene that holds the complete static layout for this tab.
# Loaded once at class parse time; Godot caches PackedScene objects so
# multiple instantiate() calls are cheap.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const TAB_SCENE: PackedScene = preload("res://ui/notebook/map/map_tab.tscn")


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# Cached LeftPage and RightPage VBoxContainers extracted from a single
# TAB_SCENE instance. Populated on the first populate_left() or
# populate_right() call and reused for the second call, so we only pay
# the instantiation cost once per MapTab lifetime.
var _left_page: VBoxContainer = null
var _right_page: VBoxContainer = null


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with a world-map placeholder.
## Instantiates map_tab.tscn (once), extracts the LeftPage VBoxContainer,
## and reparents it into parent. The VBoxContainer contains a section heading,
## a green ColorRect to represent the map area, and a "coming in Phase 2" note.
##
## The ColorRect gives the page a visual presence so it does not look broken;
## the muted green (#334D33 ≈ Color(0.2, 0.3, 0.2)) evokes a printed map.
##
## @param parent - the Control node that will hold left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the LeftPage VBox into the real page Control provided by notebook.gd.
	# _ensure_pages_built() already detached it from the temporary scene instance.
	# Guard against re-entry: if _left_page already has a parent (because
	# populate_left() was called twice on the same MapTab instance), detach it
	# first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	if _left_page.get_parent() != null:
		_left_page.get_parent().remove_child(_left_page)
	parent.add_child(_left_page)

	# Anchor the VBox to fill the parent page so children get a real width.
	# Without this, a plain Control parent won't resize its children automatically.
	# Negative right/bottom offsets apply a 10 px inset on all sides (rule 2, ui/CLAUDE.md).
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	_left_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_page.offset_left = 10
	_left_page.offset_top = 10
	_left_page.offset_right = -10
	_left_page.offset_bottom = -10


## Populate the right page with a local-area map placeholder.
## Instantiates map_tab.tscn (once), extracts the RightPage VBoxContainer,
## and reparents it into parent. The VBoxContainer contains a section heading,
## a dark-green ColorRect to represent the local map area, and a "coming in
## Phase 2" note.
##
## The slightly darker green (Color(0.15, 0.25, 0.15)) distinguishes the local
## map visually from the global map on the left page.
##
## @param parent - the Control node that will hold right-page content.
##                 Per NotebookTab contract: guard against null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the RightPage VBox into the notebook's right page Control.
	# Same anchoring + margin scheme as populate_left() for consistent insets.
	# Guard against re-entry: if _right_page already has a parent (because
	# populate_right() was called twice on the same MapTab instance), detach
	# it first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	if _right_page.get_parent() != null:
		_right_page.get_parent().remove_child(_right_page)
	parent.add_child(_right_page)
	_right_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right_page.offset_left = 10
	_right_page.offset_top = 10
	_right_page.offset_right = -10
	_right_page.offset_bottom = -10


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Instantiate TAB_SCENE once per MapTab lifetime, extract both page
## VBoxContainers, and discard the scene shell. Called at the start of each
## populate_* method so either method can be called first without ordering
## constraints.
##
## We detach the pages from the scene instance rather than reparenting the
## whole instance, because the notebook only needs the page subtrees and the
## bare MapTab root Control from the .tscn has no purpose at runtime.
## This is the same pattern used in SettingsTab._ensure_pages_built() and
## InventoryTab._ensure_pages_built().
func _ensure_pages_built() -> void:
	if _left_page != null:
		# Already extracted on a previous call; nothing to do.
		return

	# Instantiate the scene to get a fully-formed node tree with editor
	# properties (labels, colors, minimum sizes) already applied.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate
	var instance: Control = TAB_SCENE.instantiate() as Control

	# Grab references before detaching. Nodes are still children of instance
	# at this point, so get_node paths are relative to instance.
	_left_page = instance.get_node("LeftPage") as VBoxContainer
	_right_page = instance.get_node("RightPage") as VBoxContainer

	# Detach both pages so they survive when the shell is freed.
	# remove_child does not free the node — it simply unparents it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	instance.remove_child(_left_page)
	instance.remove_child(_right_page)

	# Clear the owner on both detached pages. After remove_child the nodes still
	# retain their .owner (the TAB_SCENE root). When add_child'd into a different
	# scene tree Godot emits an owner-inconsistency warning that GUT counts as a
	# test failure. Setting owner to null severs that link.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-owner
	_left_page.owner = null
	_right_page.owner = null

	# The bare MapTab Control shell is no longer needed.
	# queue_free() defers deletion to end-of-frame; safe because we removed all
	# nodes we care about before calling it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-queue-free
	instance.queue_free()
