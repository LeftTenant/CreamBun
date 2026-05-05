class_name PagePanel
extends PanelContainer
## A single notebook page with a paper background.
##
## Used for both the left and right pages inside the book frame. Phase 1 is
## purely structural — the panel holds whatever content the active tab injects.
## Phase 2 will add a StyleBoxTexture with paper texture art.
##
## The minimum size is half the 320×180 viewport minus margins, so both pages
## fit side-by-side inside the book frame without stretching.


func _ready() -> void:
	# Half of the 320×180 design viewport, leaving room for the tab strip and
	# outer margins. Chosen to match the design doc §9 pixel-perfect note.
	custom_minimum_size = Vector2(128, 90)
