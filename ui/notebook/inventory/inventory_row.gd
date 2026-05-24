class_name InventoryRow
extends Control
## A single row in the inventory right-page item list.
##
## Shows the item name, a count badge (only when count > 1), and the item
## weight. The row also acts as a drag source — the player can drag it onto
## an EquipmentSlot to equip the item.
##
## Static layout (SelectionRect, HBox, NameLabel, CountLabel, WeightLabel and
## all size/anchor/color properties) lives in inventory_row.tscn — this script
## only handles data binding, selection state, and drag logic.
##
## Call setup() after the node is in the scene tree so that @onready refs
## are guaranteed non-null before data is written.
##
## Drag-and-drop API:
##   https://docs.godotengine.org/en/stable/tutorials/ui/gui_drag_and_drop.html

## Emitted when the row is clicked with the left mouse button.
## Use this instead of connecting to the built-in `gui_input` signal — `gui_input`
## doesn't fire when the row sits inside a `ScrollContainer`, but the `_gui_input`
## override (which emits this signal) does.
signal selected(row: InventoryRow)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The ItemStack this row represents. Set by setup().
var _stack: ItemStack = null


# ---------------------------------------------------------------------------
# @onready vars
# ---------------------------------------------------------------------------
# All initialization happens via these @onready bindings and the setup() call.
# There is no _ready() override — none is needed.

# Background highlight rect shown when this row is selected.
# Declared in inventory_row.tscn as the first child (renders behind HBox),
# hidden by default, warm-cream tint (Color(1, 0.9, 0.6, 0.35)), with
# PRESET_FULL_RECT anchors and MOUSE_FILTER_PASS so clicks reach this node.
# https://docs.godotengine.org/en/stable/classes/class_colorrect.html
@onready var _selection_rect: ColorRect = $SelectionRect

# HBoxContainer holding name, count, and weight labels side by side.
# Declared in inventory_row.tscn with SIZE_EXPAND_FILL and PRESET_FULL_RECT.
# https://docs.godotengine.org/en/stable/classes/class_hboxcontainer.html
@onready var _hbox: HBoxContainer = $HBox

# Item name displayed on the left of the row.
# In the scene: SIZE_EXPAND_FILL so it pushes count and weight rightward;
# autowrap_mode = AUTOWRAP_WORD_SMART handles long display names gracefully
# per ui/CLAUDE.md rule 4.
@onready var _name_label: Label = $HBox/NameLabel

# Count badge shown only when stack.count > 1 (e.g. "×3"). Hidden in the
# scene file so single-item stacks never flash a stale badge before setup().
@onready var _count_label: Label = $HBox/CountLabel

# Weight shown on the right (e.g. "0.5 kg").
@onready var _weight_label: Label = $HBox/WeightLabel


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

# Godot calls `_gui_input` during the engine's built-in control-event dispatch.
# Unlike the `gui_input` *signal*, `_gui_input` fires reliably even when the
# control is inside a `ScrollContainer` that would otherwise consume the event
# for drag-to-scroll. We use this to detect left-clicks on the row and emit
# our own `selected` signal.
# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-private-method-gui-input
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			selected.emit(self)
			accept_event()


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Set or clear the visual selection indicator on this row.
##
## Call set_selected(true) when the player clicks this row, and
## set_selected(false) when a different row or slot is selected, or when
## the stack this row represents is fully depleted.
##
## @param value - true to show the highlight; false to hide it
func set_selected(value: bool) -> void:
	if _selection_rect != null:
		_selection_rect.visible = value


## Populate the row with data from stack and item.
## Must be called after the node is in the scene tree so _ready() has run.
##
## @param stack - the ItemStack (provides count and item_id)
## @param item  - the resolved ItemData (provides display_name and weight)
func setup(stack: ItemStack, item: ItemData) -> void:
	_stack = stack

	_name_label.text = item.display_name

	# Count badge: only meaningful when more than one is present.
	# Non-stackable items and single units omit the badge to keep the list clean.
	if stack.count > 1:
		_count_label.text = "x%d" % stack.count
		_count_label.visible = true
	else:
		_count_label.visible = false

	# Weight shows per-stack total so the player can see the real impact.
	# "%.2f kg" keeps two decimal places; cozy items rarely need more precision.
	_weight_label.text = "%.2f kg" % (item.weight * stack.count)


# ---------------------------------------------------------------------------
# Drag-and-drop overrides
# ---------------------------------------------------------------------------

## Godot calls this when the player begins dragging this control.
## Return a Dictionary payload that EquipmentSlot._can_drop_data() will inspect.
## Returning null cancels the drag — we cancel if there is no stack yet.
##
## We also create a simple Label preview so the player can see what they are
## dragging. set_drag_preview() hands ownership of the preview node to Godot;
## we must not free it ourselves.
##
## Return type is Variant (not Dictionary) because that is the signature
## required by Godot's drag-and-drop API.
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-_get-drag-data
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _stack == null:
		return null

	# Build a floating label preview so the player can see what they are holding.
	# Godot frees the preview node automatically after the drag ends.
	var preview: Label = Label.new()
	preview.text = _name_label.text if _name_label != null else _stack.item_id
	set_drag_preview(preview)

	# The payload dictionary is inspected by EquipmentSlot._can_drop_data().
	# "kind" lets other drop targets reject non-item payloads defensively.
	return {"kind": "item", "stack": _stack}
