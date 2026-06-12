extends Node
## Live game state for the current save slot.
##
## A thin Node wrapper over PlayerDataResource — Godot autoloads must extend
## Node (or PackedScene), but ResourceSaver can only serialize Resource
## objects, not Node trees. This wrapper is the stable, always-reachable
## access point (PlayerData.inventory, PlayerData.gold, ...); the inner
## Resource is the unit that gets serialized to disk by SaveManager.
## See: https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html
##
## No direct field duplication: every forwarded property reads from / writes
## through to _resource. New-game and slot-load swap _resource in one call
## via _load_resource() — callers never see the swap because they always go
## through these properties.
##
## See docs/features/game-data/design.md §3, §9.1.

## Initialized inline so _resource is never null, even before any
## new_game()/load_slot() call (design §10).
var _resource: PlayerDataResource = PlayerDataResource.new()

## All items Cream Bun is carrying or wearing.
var inventory: Inventory:
	get:
		return _resource.inventory

## Quest progress, keyed by quest id.
var quest_log: QuestLog:
	get:
		return _resource.quest_log

## Discovered map destinations and fog data.
var map_state: MapState:
	get:
		return _resource.map_state

## Market currency. Setting this writes through to the inner resource.
var gold: int:
	get:
		return _resource.gold
	set(value):
		_resource.gold = value

# --- Phase 2 (add when their systems arrive) ---
# var player_stats: PlayerStats: get: return _resource.player_stats
# var known_recipes: Array[StringName]: get: return _resource.known_recipes
# var forage_state: ForageState: get: return _resource.forage_state


## Swap in a new resource (from SaveManager.new_game() or load_slot()) and
## notify listeners so they rebind to the fresh data.
func _load_resource(resource: PlayerDataResource) -> void:
	_resource = resource
	GameEvents.player_data_loaded.emit()


## Returns the serializable resource so SaveManager can write it to disk.
## Returns the exact instance currently held — not a copy.
func to_resource() -> PlayerDataResource:
	return _resource
