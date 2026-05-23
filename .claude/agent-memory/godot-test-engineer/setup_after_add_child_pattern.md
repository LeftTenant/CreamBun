---
name: setup()-after-add_child() pattern for data-driven nodes
description: Nodes that build child nodes in _ready() must be added to the tree before calling their setup/configure method, otherwise child references are null.
type: feedback
---

When a node creates its own child nodes in `_ready()` (e.g. StoryCard builds Label, ColorRect, Button in `_ready()`), callers must follow this order:

1. `parent.add_child(node)` — triggers `_ready()`, creating child nodes
2. `node.setup(data)` — safe to update child refs now

Calling `setup()` before `add_child()` will crash because the child node vars are still null.

**Why:** _ready() is only called once the node enters the scene tree. Any method that writes to child node properties must run after that.

**How to apply:** In tests, always use `add_child_autofree(StoryCard.new())` before calling `card.setup(slot)`. In production code (e.g. SessionsTab.populate_left), call `parent.add_child(card)` then `card.setup(_default_slot)` in that order — the comment in sessions_tab.gd documents this explicitly.
