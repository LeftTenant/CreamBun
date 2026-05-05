class_name MapState
extends Resource
## Persisted map progress for a single story slot.
## Tracks which destinations the player has discovered and any fog-of-war data.

## Destination ids that the player has visited at least once.
## These are the locations available for fast travel.
@export var visited_destinations: Array[StringName] = []

## Arbitrary fog-of-war data keyed by tile or chunk coordinate.
## Left as a plain Dictionary so the map system can store whatever granularity
## it needs without a schema change here. Phase 1 leaves this unused.
@export var fog_data: Dictionary = {}
