class_name NotebookTab
extends Control
## Base class for all notebook tab scenes.
## Each tab extends this and overrides populate_left / populate_right.
## The root notebook scene calls these when it swaps page content.
##
## In Phase 1 both methods are no-ops. Subclasses in later phases will
## add their UI by appending child nodes to the given parent Control so
## the notebook's page layout stays in control of the physical page bounds.


## Called by the notebook when this tab becomes active.
## Subclasses should populate the left page with their content here.
## @param parent - the Control node that will hold left-page children.
##                 May be null in unit tests; implementations must guard.
func populate_left(parent: Control) -> void:
	pass


## Called by the notebook when this tab becomes active.
## Subclasses should populate the right page with their content here.
## @param parent - the Control node that will hold right-page children.
##                 May be null in unit tests; implementations must guard.
func populate_right(parent: Control) -> void:
	pass
