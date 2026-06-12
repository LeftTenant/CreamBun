extends Node
## Central signal bus for cross-system communication.
## Use GameEvents only for events that cross scene boundaries.
## For parent/child communication within a scene, use direct $Node references.

# Player
signal player_moved(position: Vector2)

# Game state
signal game_state_changed(old_state: int, new_state: int)

# Notebook lifecycle
# Emitted by the notebook UI when it opens/closes or the active tab changes.
# `tab` is the NotebookTab enum value defined in the notebook scene script.
signal notebook_opened(tab: int)
signal notebook_closed()
signal notebook_tab_changed(tab: int)

# Inventory
# inventory_changed fires after any add/remove/equip/unequip so listeners
# (e.g. the HUD weight bar) can refresh without knowing what changed.
# Signal parameters use untyped Variant for items because autoloads are loaded
# before GDScript class_name declarations are indexed — typed parameters would
# cause a parse error at startup. Callers cast to ItemData at their call sites.
signal inventory_changed()
signal item_equipped(item: Variant, slot: int)
signal item_unequipped(item: Variant, slot: int)
signal item_dropped(item: Variant, count: int)
signal item_recycled(item: Variant, yield_stacks: Array)
# inventory_full fires when add() returns a non-zero leftover; lets the HUD
# show a "bag is full" flash without the inventory system knowing about the HUD.
signal inventory_full(item: Variant)

# Map / fast travel
signal destination_visited(id: StringName)
signal fast_travel_requested(id: StringName)

# Quests
signal quest_added(id: StringName)
signal quest_updated(id: StringName)
signal quest_completed(id: StringName)

# Sessions / Stories
# StorySlot is also untyped for the same autoload-ordering reason as above.
signal story_created(slot: Variant)
signal story_loaded(slot: Variant)
signal story_switch_requested(slot_id: String)

# Currency
signal gold_changed(new_total: int)

# Game data lifecycle
# Emitted by PlayerData._load_resource() after new_game()/load_slot() so all
# listeners (HUD, open notebook tab) rebind to the fresh resource in one place.
signal player_data_loaded()
