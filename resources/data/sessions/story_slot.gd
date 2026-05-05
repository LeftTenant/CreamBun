class_name StorySlot
extends Resource
## Metadata for a single save-file slot shown on the Sessions tab.
## The actual game save data lives elsewhere (SaveManager); StorySlot is
## only the "cover page" information the player sees when choosing a story.

## Stable identifier matching the save file on disk (e.g. "slot_1").
@export var slot_id: String = ""
## The name the player gives their story ("Cream Bun's Adventure").
@export var display_name: String = ""
## Background colour of the story card in the Sessions tab UI.
@export var cover_color: Color = Color.WHITE
## Index into a palette of decorative patterns painted on the card.
## 0 means plain (no pattern).
@export var cover_pattern: int = 0
## Unix timestamp (seconds) of when the story was first created.
@export var created_at: int = 0
## Unix timestamp (seconds) of the most recent play session.
@export var last_played: int = 0
## Total time played in seconds. Shown as "h mm" in the UI.
@export var play_seconds: int = 0
