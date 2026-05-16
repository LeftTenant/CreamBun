class_name InventoryRow
extends Control
## A single row in the inventory right-page item list.

## Emitted when the row is clicked with the left mouse button.
## Use this instead of connecting to the built-in `gui_input` signal — `gui_input`
## doesn't fire when the row sits inside a `ScrollContainer`, but the `_gui_input`
## override (which emits this signal) does.
signal selected(row: InventoryRow)
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

# Background highlight rect shown when this row is selected.
# Created in _ready() as the first child (so it draws behind the HBox),
# hidden by default, revealed by set_selected(true).
# https://docs.godotengine.org/en/stable/classes/class_colorrect.html
var _selection_rect: ColorRect


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# SIZE_EXPAND_FILL makes this row fill the full width of the parent VBoxContainer.
	# Without this, the Control's clickable area is only as wide as its text content,
	# so mouse clicks near the right edge of the page won't register on the row.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-size-flags-horizontal
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Give every row a minimum height of 20px so it is always comfortably clickable.
	custom_minimum_size = Vector2(0, 20)

	# mouse_filter = STOP (the default) is required for _gui_input to fire at all.
	# Without it, clicks pass through this control to ancestors without calling
	# _gui_input. The default is already STOP, but stating it explicitly makes the
	# intent clear for future readers.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-mouse-filter
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Selection highlight — must be the first child so it renders behind all
	# content children. We use PRESET_FULL_RECT to anchor it to the four
	# corners of this Control so it always fills the row regardless of height.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-preset
	_selection_rect = ColorRect.new()
	_selection_rect.name = "SelectionRect"
	# A warm cream tint at 35% opacity is visible but stays within the cozy palette.
	_selection_rect.color = Color(1.0, 0.9, 0.6, 0.35)
	_selection_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# mouse_filter PASS lets clicks fall through to this Control's own _gui_input
	# handler instead of being consumed by the ColorRect child.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-mousefilter
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	_selection_rect.visible = false
	add_child(_selection_rect)

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
