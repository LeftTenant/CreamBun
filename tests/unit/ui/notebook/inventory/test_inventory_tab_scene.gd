## test_inventory_tab_scene.gd
## Scene-as-data contract tests for the Inventory tab scene (inventory_tab.tscn).
##
## WHAT THESE TESTS GUARD
## ----------------------
## inventory_tab.tscn declares the full static layout as saved editor nodes.
## These tests load the .tscn and walk the resulting tree to assert that the
## named nodes the script depends on are present and of the correct type.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between inventory_tab.gd and inventory_tab.tscn is not enforced by
## the type system — find_child("WeightLabel", true, false) returns null at runtime
## with no editor warning if the node was accidentally renamed or deleted. A test
## that loads the PackedScene and walks the instantiated tree catches that breakage
## at CI time rather than during manual QA.
##
## --- SLICE 3 DATA SOURCE NOTE ---
## InventoryTab no longer builds sample data in _ready() — populate_right()
## reads PlayerData.inventory directly (design §7.4, §13). These tests are
## about scene STRUCTURE (named nodes, types), not bag contents, so
## before_each() gives PlayerData a plain PlayerDataResource.new() (empty
## inventory, no reset_to_new_game() seeding). This confirms populate_left/
## populate_right/null-parent handling all still work against an empty
## PlayerData-backed inventory, independent of any starter-bag content.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_inventory_tab_scene.gd -gexit

class_name TestInventoryTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/inventory/inventory_tab.tscn"

# The six slot names that populate_left() depends on to build the equipment
# silhouette. Asserting them as a constant list makes additions visible as a diff.
const SLOT_NAMES: Array[String] = [
	"Slot_BACKPACK",
	"Slot_CLOTHING",
	"Slot_BOOTS",
	"Slot_GLOVES",
	"Slot_GOGGLES",
	"Slot_NECKLACE",
]


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Give PlayerData a plain, empty resource before every test. These tests
## assert on scene STRUCTURE, not bag contents — an empty inventory keeps
## that distinction clear and isolates this file from any starter-bag seeding
## performed elsewhere. Per CLAUDE.md's dependency-injection guidance for
## autoload tests.
func before_each() -> void:
	PlayerData._load_resource(PlayerDataResource.new())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated InventoryTab root node added as a child of the test
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


## Walk root's subtree depth-first and collect every node that satisfies
## type_check. Used because named nodes may live at any depth inside the layout
## hierarchy — a shallow get_child(0) would miss grandchildren.
##
## @param root       the node whose subtree to search
## @param type_check Callable(Node) -> bool; returns true for matching nodes
## @return Array of matching nodes in depth-first order
func _find_nodes_of_type(root: Node, type_check: Callable) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		if type_check.call(child):
			result.append(child)
		result.append_array(_find_nodes_of_type(child, type_check))
	return result


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# If the .tscn file is corrupt, mis-formatted, or references a missing
	# resource, load() returns null. This is the cheapest possible check and
	# gates every subsequent test: if load fails there is no point instantiating.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"inventory_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene declares a node named LeftPage of type Control / VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_left_page() -> void:
	# LeftPage is the subtree root that populate_left() reparents into the
	# notebook book's page. If it is renamed or deleted the tab's left side
	# will be permanently blank with no runtime error.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LeftPage", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'LeftPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'LeftPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a node named RightPage of type Control / VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_right_page() -> void:
	# RightPage is the subtree root that populate_right() reparents. Mirrors
	# the LeftPage contract but for the scrollable item list side.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RightPage", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RightPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'RightPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares exactly the 6 named equipment slot placeholders
# ---------------------------------------------------------------------------

func test_scene_declares_all_six_equipment_slot_placeholders() -> void:
	# populate_left() builds EquipmentSlot nodes named Slot_BACKPACK … Slot_NECKLACE.
	# These names are the stable contract between the tab script and the scene
	# layout. A missing or misspelled name would silently produce a detached slot
	# that never receives drag-drop events. We assert on each name individually so
	# the failure message identifies which slot is missing rather than just "not 6".
	var instance: Control = _make_scene_instance()

	for slot_name: String in SLOT_NAMES:
		var node: Node = instance.find_child(slot_name, true, false)
		assert_not_null(node,
				"inventory_tab.tscn must declare a node named '%s'" % slot_name)


# ---------------------------------------------------------------------------
# Test 5 — Scene declares a node named RowsContainer of type VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_rows_container() -> void:
	# RowsContainer is the VBoxContainer that populate_right() appends
	# InventoryRow instances into. Without it, the item list has nowhere to
	# render and the scroll container would be permanently empty.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RowsContainer", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RowsContainer'")
	if node == null:
		return
	assert_true(node is VBoxContainer,
			"'RowsContainer' must be a VBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 6 — Scene declares a node named ScrollContainer of type ScrollContainer
# ---------------------------------------------------------------------------

func test_scene_declares_scroll_container() -> void:
	# ScrollContainer wraps RowsContainer so long item lists don't overflow the
	# right page. If it is absent the item list will extend past the page boundary
	# with no scrollbar — a silent layout regression.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ScrollContainer", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'ScrollContainer'")
	if node == null:
		return
	assert_true(node is ScrollContainer,
			"'ScrollContainer' must be a ScrollContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 7 — Scene declares a node named EquipButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_equip_button() -> void:
	# EquipButton's pressed signal is connected to _do_equip() by populate_right().
	# Without this node the Equip action is completely unavailable via mouse
	# (keyboard shortcut still works, but the button is missing).
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("EquipButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'EquipButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'EquipButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 8 — Scene declares a node named ThrowButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_throw_button() -> void:
	# ThrowButton's pressed signal is connected to _do_throw(). Mirrors EquipButton.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ThrowButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'ThrowButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'ThrowButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 9 — Scene declares a node named RecycleButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_recycle_button() -> void:
	# RecycleButton's pressed signal is connected to _do_recycle(). The tab also
	# stores a ref to this button in _recycle_button so it can be disabled when
	# nothing recyclable is selected — the stable name is required for that lookup.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RecycleButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RecycleButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'RecycleButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 10 — Scene declares a Label named WeightLabel
# ---------------------------------------------------------------------------

func test_scene_declares_weight_label() -> void:
	# WeightLabel is the node that _update_weight_label() patches with the
	# current carry weight text. Without this stable name the named-node lookup
	# would miss it and the weight display would silently never update.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WeightLabel", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'WeightLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'WeightLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 11 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# NotebookTab's contract requires populate_left / populate_right to guard
	# against null. This test confirms the guard holds. A crash here would abort
	# the notebook _show_tab flow if the controller ever passes a missing page.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab,
			"inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return
	# No assertion beyond "no crash" — GUT records an error automatically if
	# an uncaught exception is thrown.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 12 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors test 11 for the right-page populate method.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab,
			"inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")


# ---------------------------------------------------------------------------
# Test 13 — populate_right() against an empty PlayerData.inventory renders
#           zero rows and a zero-weight header (no crash, no stale sample data)
# ---------------------------------------------------------------------------

func test_populate_right_with_empty_player_data_inventory_renders_no_rows() -> void:
	# before_each() seeds PlayerData with a plain PlayerDataResource.new() —
	# an empty Inventory (no stacks, nothing equipped). Since InventoryTab no
	# longer constructs sample_leaf/sample_boots in _ready(), populate_right()
	# must render zero InventoryRow children and a "Weight: 0.0 / ..." header,
	# not the old hardcoded sample data.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab, "inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return

	var parent: Control = add_child_autofree(Control.new())
	tab.populate_right(parent)

	var rows_container: Node = parent.find_child("RowsContainer", true, false)
	assert_not_null(rows_container, "RowsContainer must exist after populate_right()")
	if rows_container != null:
		assert_eq(rows_container.get_children().size(), 0,
				"populate_right() with an empty PlayerData.inventory must render zero InventoryRow children")

	var weight_label: Node = parent.find_child("WeightLabel", true, false)
	assert_not_null(weight_label, "WeightLabel must exist after populate_right()")
	if weight_label != null:
		assert_eq((weight_label as Label).text, "Weight: 0.0 / ∞",
				"an empty inventory with no backpack equipped must show 'Weight: 0.0 / ∞'")


# ---------------------------------------------------------------------------
# Test 14 — InventoryTab has no _inventory field after migration
# ---------------------------------------------------------------------------

func test_inventory_tab_has_no_inventory_field() -> void:
	# design §7.4 / §13 (Slice 3): InventoryTab stops owning data. The
	# self-owned `_inventory: Inventory` field must be removed entirely —
	# populate_right() reads PlayerData.inventory directly instead. Checking
	# get_property_list() (rather than `tab._inventory` directly, which would
	# fail to compile if the field is removed — exactly the point) confirms
	# no script-level property named "_inventory" remains on the instance.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab, "inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return

	var property_names: Array[String] = []
	for prop: Dictionary in tab.get_property_list():
		property_names.append(prop.get("name", ""))

	assert_false(property_names.has("_inventory"),
			"InventoryTab must not declare a self-owned '_inventory' field after the Slice 3 migration")


# ---------------------------------------------------------------------------
# Test 15 — current_weight()/lookup resolves the seeded starter bag to a
#           non-zero weight via the temporary local registry
# ---------------------------------------------------------------------------

func test_starter_bag_resolves_to_non_zero_weight_via_local_registry() -> void:
	# design §13: a temporary local item registry (seeded from the stacks
	# present in PlayerData.inventory) stands in for the future ItemDatabase
	# helper. After populate_right() with a freshly-seeded starter bag
	# (3x sample_leaf @ 0.5kg + 1x sample_boots @ 0.8kg = 2.3kg, see
	# _seed_starter_content()), the rendered weight header must reflect that
	# non-zero total — proving the registry resolved both item ids to weights.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)

	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab, "inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return

	var parent: Control = add_child_autofree(Control.new())
	tab.populate_right(parent)

	var weight_label: Node = parent.find_child("WeightLabel", true, false)
	assert_not_null(weight_label, "WeightLabel must exist after populate_right()")
	if weight_label != null:
		assert_eq((weight_label as Label).text, "Weight: 2.3 / ∞",
				"the starter bag (3x sample_leaf @ 0.5kg + 1x sample_boots @ 0.8kg) must total 2.3kg")


# ---------------------------------------------------------------------------
# Test 16 — an unknown item_id in PlayerData.inventory.stacks is skipped
#           gracefully (no crash, no row, weight unaffected)
# ---------------------------------------------------------------------------

func test_unknown_item_id_in_stacks_is_skipped_gracefully() -> void:
	# design §13: the temporary local registry may not have an entry for an
	# item added to PlayerData.inventory by another system before the
	# registry catches up (e.g. a future foraging system adding a brand-new
	# ItemData id this tab has never seen). _build_right_page() must skip such
	# a stack — no row, no crash — exactly as it already does when
	# _item_registry.get(...) returns null (see the `if item == null: continue`
	# guard in _build_right_page()).
	#
	# We construct an ItemStack with an item_id the registry cannot know about
	# and a null runtime `item` ref (simulating an unhydrated stack loaded from
	# save — see ItemStack's doc comment on the non-exported `item` field).
	var mystery_stack: ItemStack = ItemStack.new()
	mystery_stack.item_id = &"totally_unknown_item"
	mystery_stack.count = 1
	mystery_stack.item = null
	PlayerData.inventory.stacks.append(mystery_stack)

	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab, "inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return

	var parent: Control = add_child_autofree(Control.new())
	# If this raises an error GUT records a failure automatically — the core
	# assertion of this test is "no crash".
	tab.populate_right(parent)

	var rows_container: Node = parent.find_child("RowsContainer", true, false)
	assert_not_null(rows_container, "RowsContainer must exist after populate_right()")
	if rows_container != null:
		for child: Node in rows_container.get_children():
			var row: InventoryRow = child as InventoryRow
			if row != null and row._stack != null:
				assert_ne(row._stack.item_id, &"totally_unknown_item",
						"a stack with an unrecognized item_id must not produce a rendered InventoryRow")

	var weight_label: Node = parent.find_child("WeightLabel", true, false)
	assert_not_null(weight_label, "WeightLabel must exist after populate_right()")
	if weight_label != null:
		assert_eq((weight_label as Label).text, "Weight: 0.0 / ∞",
				"an unresolvable stack must contribute 0 weight to the header")


# ---------------------------------------------------------------------------
# Test 17 — _ready() connects _on_inventory_changed to
#           GameEvents.inventory_changed exactly once
# ---------------------------------------------------------------------------

func test_ready_connects_inventory_changed_exactly_once() -> void:
	# design §7.4: InventoryTab connects to GameEvents.inventory_changed in
	# _ready() so an open tab refreshes live. _ready() can run more than once
	# for a node re-added to the tree (e.g. a future notebook flow that
	# detaches and reattaches tabs) — the connection must be guarded with
	# is_connected() so re-running _ready() does not register a duplicate
	# connection. A duplicate connection would cause _on_inventory_changed (and
	# therefore _refresh_both_pages()) to run twice per emitted signal.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab, "inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		autofree(instance)
		return

	add_child_autofree(tab)

	# _ready() already ran once via add_child(). Call it again directly to
	# simulate the re-entry scenario the guard protects against.
	tab._ready()

	# Count how many of GameEvents.inventory_changed's connections target this
	# tab's handler. get_connections() returns an Array of Dictionaries with
	# "signal", "callable", and "flags" keys.
	# https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-get-connections
	var connections: Array = GameEvents.inventory_changed.get_connections()
	var matching: int = 0
	for connection: Dictionary in connections:
		var callable: Callable = connection.get("callable")
		if callable.get_object() == tab:
			matching += 1

	assert_eq(matching, 1,
			"GameEvents.inventory_changed must have exactly one connection to this tab's handler, even after _ready() runs twice")
