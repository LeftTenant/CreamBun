class_name PlayerDataResource
extends Resource
## The complete mutable state of a single save/story slot.
##
## Serialized whole to user://slots/slot_<id>.tres by SaveManager via
## ResourceSaver. Static content (ItemData, QuestData, recipes, ...) is NOT
## stored here — only references by id (e.g. ItemStack.item_id, quest ids) —
## so content edits reach old saves without requiring a migration.
## See docs/features/game-data/design.md §5.
##
## Phase 1 ships only the four already-real pieces (inventory, quest_log,
## map_state, gold) plus save_version. Phase 2/3 fields are deliberately left
## as commented stubs below — see design §4 / §13.


## Bump when the schema changes in a way that needs migration on load.
const CURRENT_VERSION: int = 1

## Schema stamp written into every save. Read on load to migrate older files.
@export var save_version: int = CURRENT_VERSION

# --- Phase 1: already-real data, moved out of the notebook tabs ---

## All items Cream Bun is carrying or wearing. See resources/data/items/inventory.gd.
## Initialized inline so a default-constructed PlayerDataResource is never
## half-null — a loaded .tres file overwrites this default with its own data.
@export var inventory: Inventory = Inventory.new()

## Quest progress, keyed by quest id. See resources/data/quests/quest_log.gd.
@export var quest_log: QuestLog = QuestLog.new()

## Discovered map destinations + fog data. See resources/data/map/map_state.gd.
@export var map_state: MapState = MapState.new()

## Market currency. A plain int — no Resource needed for a single number.
@export var gold: int = 0

# --- Phase 2: declared when their systems arrive (do NOT build empty) ---

## Cozy life-sim stats (energy, mood). NO combat stats — CreamBun has no combat.
# @export var player_stats: PlayerStats = PlayerStats.new()

## Brewing recipe ids the player has learned. Recipe definitions are static .tres.
# @export var known_recipes: Array[StringName] = []

## Per-spot forage cooldowns: spot_id -> "ready again on day N".
# @export var forage_state: ForageState = ForageState.new()

# --- Phase 3: relationships, dialogue, calendar ---

## NPC affinity: npc_id (StringName) -> score (int).
# @export var relationships: Dictionary = {}

## What's already been said: dialogue/npc id -> arbitrary state.
# @export var dialogue_history: Dictionary = {}

## In-game day / season / time-of-day. Cozy pacing only.
# @export var calendar: CalendarState = CalendarState.new()


## Seed a brand-new game. Called by SaveManager.new_game().
## Replaces every sub-resource with a fresh instance (rather than clearing
## the existing ones in place) so any caller still holding a reference to the
## old inventory/quest_log/map_state is not silently mutated out from under it.
func reset_to_new_game() -> void:
	inventory = Inventory.new()
	quest_log = QuestLog.new()
	map_state = MapState.new()
	gold = 0
	save_version = CURRENT_VERSION
	_seed_starter_content()


## Re-attach runtime-only references after a load (see design §6.3).
## Phase 1: documented no-op. ItemStack.item is a non-exported runtime ref
## that survives only as item_id across a save/load round trip; re-linking it
## from an item registry waits for the ItemDatabase helper (design §13).
func rehydrate() -> void:
	pass


## Give the new player the intro quest and the default starter bag.
## This is the single source of truth for starter content — the values here
## previously lived as hand-seeded sample data in InventoryTab/QuestsTab
## _ready() and are being consolidated here (Slice 1).
func _seed_starter_content() -> void:
	# The foraging-book intro quest ships pre-completed with all three
	# objectives marked done, matching the shape QuestsTab._ready() used to
	# hand-seed (see ui/notebook/quests/quests_tab.gd).
	quest_log.states[&"the_foraging_book"] = {
		"status": QuestLog.Status.COMPLETED,
		"completed_objectives": [0, 1, 2],
	}

	# Starter bag: 3x Forest Leaf (stackable ingredient) + 1x Old Boots
	# (non-stackable, equippable). Field values mirror the sample ItemData
	# previously constructed in InventoryTab._ready()
	# (see ui/notebook/inventory/inventory_tab.gd).
	var leaf: ItemData = ItemData.new()
	leaf.id = &"sample_leaf"
	leaf.display_name = "Forest Leaf"
	leaf.weight = 0.5
	leaf.stackable = true
	leaf.max_stack = 99
	inventory.add(leaf, 3)

	var boots: ItemData = ItemData.new()
	boots.id = &"sample_boots"
	boots.display_name = "Old Boots"
	boots.weight = 0.8
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	inventory.add(boots, 1)
