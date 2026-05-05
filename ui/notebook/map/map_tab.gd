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
## Design doc: docs/features/notebook/design.md §5.3 (Map tab)


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with a world-map placeholder.
## Adds a VBoxContainer containing a section heading, a green ColorRect to
## represent the map area, and a "coming in Phase 2" note below it.
##
## The ColorRect gives the page a visual presence so it does not look broken;
## the muted green (#334D33 ≈ Color(0.2, 0.3, 0.2)) evokes a printed map.
##
## @param parent - the Control node that will hold left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	# VBoxContainer stacks the heading, placeholder rect, and note vertically.
	# https://docs.godotengine.org/en/stable/classes/class_vboxcontainer.html
	var vbox: VBoxContainer = VBoxContainer.new()
	parent.add_child(vbox)

	# Section heading — decorative, so focus_mode = NONE so Tab key skips it
	# and moves straight to the next interactive control.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-focusmode
	var heading: Label = Label.new()
	heading.text = "World Map"
	heading.focus_mode = Control.FOCUS_NONE
	vbox.add_child(heading)

	# Placeholder rect stands in for the GlobalMap TextureRect until Phase 2
	# art is ready. The muted green colour reads as "map territory" without
	# needing real art.
	# https://docs.godotengine.org/en/stable/classes/class_colorrect.html
	var map_rect: ColorRect = ColorRect.new()
	map_rect.color = Color(0.2, 0.3, 0.2)
	# custom_minimum_size guarantees the rect has a visible area even when the
	# parent Control has no layout constraints yet (e.g. in tests).
	map_rect.custom_minimum_size = Vector2(120.0, 80.0)
	vbox.add_child(map_rect)

	# Phase 2 note — tells the player (and the developer reading the code) what
	# will appear here once the art pass is complete.
	var note: Label = Label.new()
	note.text = "World map coming in Phase 2."
	note.focus_mode = Control.FOCUS_NONE
	vbox.add_child(note)


## Populate the right page with a local-area map placeholder.
## Adds a VBoxContainer containing a section heading, a dark-green ColorRect
## to represent the local map area, and a "coming in Phase 2" note.
##
## The slightly darker green (Color(0.15, 0.25, 0.15)) distinguishes the local
## map visually from the global map on the left page.
##
## @param parent - the Control node that will hold right-page content.
##                 Per NotebookTab contract: guard against null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	var vbox: VBoxContainer = VBoxContainer.new()
	parent.add_child(vbox)

	var heading: Label = Label.new()
	heading.text = "Local Area"
	heading.focus_mode = Control.FOCUS_NONE
	vbox.add_child(heading)

	# Slightly darker than the global map rect so the two placeholders are
	# visually distinct on the same spread.
	var map_rect: ColorRect = ColorRect.new()
	map_rect.color = Color(0.15, 0.25, 0.15)
	map_rect.custom_minimum_size = Vector2(120.0, 80.0)
	vbox.add_child(map_rect)

	var note: Label = Label.new()
	note.text = "Local map coming in Phase 2."
	note.focus_mode = Control.FOCUS_NONE
	vbox.add_child(note)
