class_name QuestData
extends Resource
## Data resource describing a single quest in the game.
## Create one .tres file per quest; load them into QuestLog at runtime.
##
## See: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#resources

## Unique identifier used in QuestLog.states and signals. Prefer &"snake_case".
@export var id: StringName = &""
## Short title shown in the quest list.
@export var title: String = ""
## Longer description shown in the quest detail panel.
@export var description: String = ""
## Ordered list of objective strings displayed as a checklist.
## Objectives are plain text for Phase 1; a richer model can be added later.
@export var objectives: Array[String] = []
## Main story quests use a different visual treatment in the notebook.
## Side quests default to false.
@export var is_main: bool = false
