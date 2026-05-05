class_name GameSettings
extends Resource
## Player-controlled settings persisted across sessions.
## Stored as a Resource so SaveManager can write it alongside save data.
##
## Defaults match the design doc (section 3.2):
##   - All volumes at 1.0 (100 %).
##   - window_scale 2 = 2× the 640×480 viewport → 1280×960 window.
##   - text_speed 1.0 = normal speed.

## Master audio bus multiplier. Range 0.0–1.0.
@export var master_volume: float = 1.0
## Music bus multiplier. Relative to master_volume.
@export var music_volume: float = 1.0
## Sound effects bus multiplier. Relative to master_volume.
@export var sfx_volume: float = 1.0
## Integer window scale factor applied to the 640×480 base viewport.
## 2 means the window is 1280×960 by default.
@export var window_scale: int = 2
## Dialogue text reveal speed multiplier. 1.0 = normal, 2.0 = double speed.
@export var text_speed: float = 1.0
