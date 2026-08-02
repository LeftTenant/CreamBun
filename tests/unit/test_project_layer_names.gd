## test_project_layer_names.gd
## Unit tests for the named 2D physics layers added by Slice 2
## (world-collision design doc §11) — project.godot's [layer_names] section.
##
## `project.godot` currently names no physics layers, so every collision_layer
## / collision_mask checkbox in the editor is an unlabelled number. Slice 2
## names the first three:
##   2d_physics/layer_1 = "world"          — solid terrain + props, static
##   2d_physics/layer_2 = "player"         — Cream Bun
##   2d_physics/layer_3 = "interactable"   — Area2D triggers (doorways, forage
##                                           spots, NPCs) — declared now but not
##                                           built yet, per §11, so the layer
##                                           number isn't silently claimed later
##
## world-thresholds Slice 1 (design doc docs/features/world-thresholds/
## design.md §6) adds a fourth:
##   2d_physics/layer_4 = "player_bounds"  — the player's ThresholdBounds
##                                           Area2D, used only for Threshold
##                                           detection (§6: "reusing 'player'
##                                           would work ... but that makes
##                                           correctness depend on which
##                                           signal is connected rather than
##                                           on what the layers say")
##
## WHY ProjectSettings AND NOT raw file text: the on-disk [layer_names]
## section stores keys without the "layer_names/" prefix (the section header
## supplies it) — e.g. `2d_physics/layer_1="world"` — whereas the effective
## runtime setting is namespaced as "layer_names/2d_physics/layer_1". Reading
## the runtime value via ProjectSettings.get_setting() tests the thing that
## actually matters (what collision_layer/mask editors and code will see) and
## sidesteps ever having to keep a duplicated raw-text parser in sync with
## Godot's section-header-prefixing behavior. This mirrors the ProjectSettings
## approach used in test_display_settings.gd for keys whose on-disk text
## representation isn't a simple guaranteed literal.
##
## Design reference: docs/features/world-collision/design.md §11
## Test plan: docs/features/world-collision/slice-2-tile-geometry-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_project_layer_names.gd -gexit

class_name TestProjectLayerNames
extends GutTest


func test_layer_1_is_named_world() -> void:
	# Layer 1: solid terrain + props, static — WorldProp and the Solids
	# TileMapLayer both live here (design doc §11 table).
	assert_eq(
			ProjectSettings.get_setting("layer_names/2d_physics/layer_1", ""),
			"world",
			"2d_physics/layer_1 should be named 'world' — design doc §11"
	)


func test_layer_2_is_named_player() -> void:
	# Layer 2: Cream Bun. The Player node's collision_layer should live here.
	assert_eq(
			ProjectSettings.get_setting("layer_names/2d_physics/layer_2", ""),
			"player",
			"2d_physics/layer_2 should be named 'player' — design doc §11"
	)


func test_layer_3_is_named_interactable() -> void:
	# Layer 3: Area2D triggers — doorways, forage spots, NPCs. Named now, built
	# later (shared/interactable.gd is a future seam per design doc §11), so
	# the layer number is reserved and can't drift into meaning something else.
	assert_eq(
			ProjectSettings.get_setting("layer_names/2d_physics/layer_3", ""),
			"interactable",
			"2d_physics/layer_3 should be named 'interactable' — design doc §11"
	)


func test_layer_4_is_named_player_bounds() -> void:
	# Layer 4: the player's ThresholdBounds Area2D (world-thresholds design.md
	# §6) — the player's whole drawn extent, used only for Threshold
	# detection. Named rather than reusing "player" so correctness depends on
	# what the layers say, not on which signal (area_entered vs body_entered)
	# happens to be connected.
	assert_eq(
			ProjectSettings.get_setting("layer_names/2d_physics/layer_4", ""),
			"player_bounds",
			"2d_physics/layer_4 should be named 'player_bounds' — world-thresholds design doc §6"
	)
