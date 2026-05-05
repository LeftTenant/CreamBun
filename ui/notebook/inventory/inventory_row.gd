class_name InventoryRow
extends Control
## A single row in the inventory right-page item list.
##
## Shows the item name, a count badge (only when count > 1), and the item
## weight. The row also acts as a drag source — the player can drag it onto
## an EquipmentSlot to equip the item.
##
## Call setup() after adding this node to the scene tree so that _ready()
## has already run and child nodes exist.
##
## Drag-and-drop API:
##   https://docs.godotengine.org/en/stable/tutorials/ui/gui_drag_and_drop.html


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The ItemStack this row represents. Set by setup().
var _stack: ItemStack = null

# Item name displayed on the left of the row.
var _name_label: Label

# Count badge shown only when stack.count > 1 (e.g. "×3").
# Hidden for non-stackable items and stacks of exactly one.
var _count_label: Label

# Weight shown on the right (e.g. "0.5 kg").
var _weight_label: Label


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Use an HBoxContainer to lay name, count, and weight side by side.
	# The layout is built in _ready() so the .tscn stays minimal.
	# https://docs.godotengine.org/en/stable/classes/class_hboxcontainer.html
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "HBox"
	# Expand to fill the row's width so weight aligns to the right edge.
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	# Expand so it pushes count and weight to the right.
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.focus_mode = Control.FOCUS_NONE
	hbox.add_child(_name_label)

	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.focus_mode = Control.FOCUS_NONE
	# Hidden until setup() finds count > 1.
	_count_label.visible = false
	hbox.add_child(_count_label)

	_weight_label = Label.new()
	_weight_label.name = "WeightLabel"
	_weight_label.focus_mode = Control.FOCUS_NONE
	hbox.add_child(_weight_label)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

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
