class_name MapDestination
extends Resource
## A named location that can appear as a pin on the notebook map tab.
## Visited destinations can be fast-travelled to from the map.
##
## Create one .tres per location; add them to a MapRegistry resource or
## load them as a folder at startup.

## Unique identifier used in MapState and fast-travel signals.
@export var id: StringName = &""
## Human-readable label shown under the map pin.
@export var display_name: String = ""
## Position in world-space (pixels). Used to place the pin on the map image.
@export var world_position: Vector2 = Vector2.ZERO
## The scene to transition to when fast-travelling to this destination.
## Null means the destination is display-only (e.g. a distant landmark).
@export var local_scene: PackedScene
## Optional icon drawn on the map pin. Null uses the default pin sprite.
@export var pin_icon: Texture2D
