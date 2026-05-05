class_name QuestLog
extends Resource
## Tracks the player's progress through every quest.
## Stored as a Dictionary so it round-trips cleanly through SaveManager.
##
## Usage:
##   log.states[&"intro_quest"] = QuestLog.Status.ACTIVE
##   log.states[&"intro_quest"] = QuestLog.Status.COMPLETED

## The three states a quest can be in.
## HIDDEN quests are known to the game but not yet visible to the player
## (used for quests that unlock after meeting a character or reaching an area).
enum Status {
	ACTIVE,
	COMPLETED,
	HIDDEN,
}

## Maps quest id (StringName) → Status (int).
## Quests not present in this dictionary are treated as HIDDEN by the UI.
@export var states: Dictionary = {}
