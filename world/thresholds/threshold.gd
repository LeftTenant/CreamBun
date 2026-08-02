class_name Threshold
extends Area2D
## A placed region a designer drags into an area scene to mark where the
## player leaves — a map edge, a doorway, or the lip of a pit.
##
## `destination` and `arrival` are the whole node (design §4). Everything
## else — running the freeze/fade/swap/place/reveal sequence, guarding
## against re-triggering the Threshold the player just spawned into — is
## owned by `world.gd`, which connects to this node's `area_entered` signal.
## Threshold itself has no `_ready()`, no signal connections, and no armed/
## re-entry state; adding any of that here would be scope creep into a later
## slice (World Thresholds slices.md, Slice 3).
##
## Physics: `collision_layer = interactable` (bit 2, value 4) — a Threshold
## is detected, not a detector — and `collision_mask = player_bounds` (bit 3,
## value 8), so only the player's art-sized `ThresholdBounds` collider
## (world-thresholds design §6) trips it, never the smaller movement
## capsule (`player`, bit 1, value 2).
##
## threshold.tscn's CollisionShape2D.shape sets `resource_local_to_scene =
## true`. This lives here, not as a `.tscn` comment, because
## ResourceSaver.save() (what an editor Ctrl+S does) strips ALL `;`-comment
## lines from a `.tscn` on its very next save — and a designer opening and
## resizing this exact scene per placement (see above) is expected editor
## workflow, not a rare event. Without the flag, every Threshold instanced
## from this template shares one RectangleShape2D: resizing one instance's
## CollisionShape2D would resize every other placed Threshold and dirty this
## template scene itself. (world_prop.gd avoids the same problem a different
## way, by allocating a fresh RectangleShape2D.new() per instance in code;
## here the flag is the fix instead, since there's no generation code for
## Thresholds.)
##
## Design reference: docs/features/world-thresholds/design.md §4


# ---------------------------------------------------------------------------
# Exported variables
# ---------------------------------------------------------------------------

## The area scene this Threshold leads to, as a path.
##
## A String, not a PackedScene, for the same reason the `neighbour_*` exports
## being replaced (world-collision design; still live in world_area.gd until
## World Thresholds Slice 4) use one: two area scenes holding live PackedScene
## references to each other deadlock Godot's resource loader at parse time,
## because loading either scene would require first loading the other. A path
## sidesteps this — it is only resolved with load() at crossing time, in
## world.gd, long after both scenes have already finished loading
## independently.
@export_file("*.tscn") var destination: String = ""

## The name of the Arrival (Marker2D) node inside `destination` to place the
## player on when they cross this Threshold.
@export var arrival: StringName = &""
