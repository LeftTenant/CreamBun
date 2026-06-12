extends Node
## Reads and writes PlayerDataResource save slots and GameSettings to disk.
##
## SaveManager is now purely I/O — it does NOT hold live game state. Live
## state lives in the PlayerData autoload (autoloads/player_data.gd); this
## autoload only constructs/serializes/deserializes PlayerDataResource and
## GameSettings instances and hands them to PlayerData.
## See docs/features/game-data/design.md §6.2.

## Per-slot save files live under this directory, one PlayerDataResource per
## story slot (design §6.1). Phase 1 uses a single default slot id — no
## user://slots/index.tres multi-slot index yet (design §6.1 Phase 2).
const SLOT_DIR := "user://slots/"

## Per-device preferences (volumes, window scale, text speed). Independent of
## any save slot — see design §5: "GameSettings stays out of PlayerData."
const SETTINGS_PATH := "user://settings.tres"

## Per-device preferences, shared by all save slots. Declared but NOT
## eagerly constructed: it stays null until load_settings() populates it, so
## a SaveManager instance that never reaches _ready() (e.g. in a unit test
## that constructs the script directly without adding it to the tree) makes
## no GameSettings the test didn't ask for.
var settings: GameSettings = null


func _ready() -> void:
	# Launch wiring (design §10): load per-device settings, then seed
	# PlayerData with a brand-new game so PlayerData._resource holds starter
	# content (foraging-book quest completed, starter bag) before any
	# notebook tab can open and read it. This lives in SaveManager._ready()
	# for now because SaveManager is the autoload that owns "what happens on
	# launch" for persistence — once the main menu's New Story/Continue flow
	# exists (design §10), it will call new_game()/load_slot() instead and
	# this _ready() hook can be removed.
	load_settings()
	new_game()


## Build a brand-new game. Called from the main menu's "New Story" flow (and,
## for now, on launch — see _ready()). Constructs a fresh PlayerDataResource,
## seeds it with starter content via reset_to_new_game() BEFORE handing it to
## PlayerData, then swaps it into the PlayerData autoload, which emits
## player_data_loaded so all listeners rebind.
func new_game() -> void:
	var data := PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)


## Load a slot from disk into the PlayerData autoload. Returns false if the
## file is missing — PlayerData._resource is left unchanged in that case so
## the caller can fall back to new_game().
## ResourceLoader.exists(): https://docs.godotengine.org/en/stable/classes/class_resourceloader.html#class-resourceloader-method-exists
func load_slot(slot_id: String) -> bool:
	var path: String = _slot_path(slot_id)
	if not ResourceLoader.exists(path):
		return false

	# CACHE_MODE_REPLACE forces a genuinely fresh deserialization from disk.
	# Without it, ResourceLoader returns Godot's cached resource for `path` if
	# one is already registered there — and save_slot() registers exactly that
	# cache entry as a side effect: ResourceSaver.save(PlayerData.to_resource(), path)
	# stamps the LIVE in-memory resource's `resource_path` to `path`. A plain
	# ResourceLoader.load(path) here would then hand back that SAME live
	# instance — any in-memory mutation made after save_slot() (but before this
	# load_slot()) would "win", which is the opposite of what "switch story"
	# should do. CACHE_MODE_REPLACE discards that cache entry and reads the
	# file fresh, so the saved-on-disk values are what come back.
	# https://docs.godotengine.org/en/stable/classes/class_resourceloader.html#class-resourceloader-method-load
	var loaded: PlayerDataResource = ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_REPLACE) as PlayerDataResource
	if loaded == null:
		return false

	# Re-link runtime-only references (e.g. ItemStack.item) — currently a
	# documented no-op until ItemDatabase exists (design §6.3, §13).
	loaded.rehydrate()
	PlayerData._load_resource(loaded)
	return true


## Write the current PlayerDataResource to its slot file, creating SLOT_DIR
## if it does not exist yet.
## DirAccess.make_dir_recursive_absolute(): https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-make-dir-recursive-absolute
## ResourceSaver.save(): https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html#class-resourcesaver-method-save
func save_slot(slot_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	ResourceSaver.save(PlayerData.to_resource(), _slot_path(slot_id))


## Load per-device settings from disk. On first run (no settings.tres yet),
## assigns a fresh GameSettings with its documented defaults so `settings` is
## never left null after this call.
func load_settings() -> void:
	if ResourceLoader.exists(SETTINGS_PATH):
		settings = ResourceLoader.load(SETTINGS_PATH) as GameSettings
	if settings == null:
		settings = GameSettings.new()


## Write the current per-device settings to disk.
func save_settings() -> void:
	if settings != null:
		ResourceSaver.save(settings, SETTINGS_PATH)


## Build the on-disk path for a given save slot id, e.g.
## _slot_path("default") -> "user://slots/slot_default.tres".
func _slot_path(slot_id: String) -> String:
	return "%sslot_%s.tres" % [SLOT_DIR, slot_id]
