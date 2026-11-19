# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

AHRA: a Godot 4.7 GDScript prototype of isometric 3D platformer mechanics (Jolt physics, physics interpolation on, D3D12 on Windows). Main scene: `res://demo/demo.tscn`. No build or lint step; the editor is `C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe` (older 4.5/4.6 exes sit next to it, don't use them).

## Verifying changes (headless)

Tests are `SceneTree` scripts in `tests/`. One script = one suite; there is no per-case filter. Exit code = number of failed checks; the last line prints `SMOKE|PLATFORMS|PUZZLES|SHAPE EDITOR|PLATFORM TOOLS: OK` or `N FAILED`.

```sh
GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"   # godot-git-plugin log spam

timeout 150 "$GODOT" --headless --path . -s res://tests/smoke_test.gd    2>&1 | grep -viE "$NOISE"   # player controller, ~45 s
timeout 150 "$GODOT" --headless --path . -s res://tests/platform_test.gd 2>&1 | grep -viE "$NOISE"   # moving platforms (demo/platforms)
timeout 300 "$GODOT" --headless --path . -s res://tests/puzzle_test.gd   2>&1 | grep -viE "$NOISE"   # walkthrough of all 10 puzzles, ~3 min
timeout 150 "$GODOT" --headless --path . -e res://tests/shape_editor_test.tscn -- --shape-editor-test 2>&1 | grep -viE "$NOISE"       # Shape Tools plugin
timeout 150 "$GODOT" --headless --path . -e res://tests/platform_tools_test.tscn -- --platform-tools-test 2>&1 | grep -viE "$NOISE"   # Platform Tools plugin
# editor tests need the editor, so they open a scene instead of -s; they share tests/editor_test.gd

timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/demo.tscn   # load/run a scene, watch for errors
timeout 150 "$GODOT" --headless --path . --editor --quit-after 400             # catch errors in @tool scripts
```

Run the suites that cover what you touched after any player/world change. They check physics and logic only; game feel is untested, so say so.

Gotchas:
- A script error stops the test before `quit()` and Godot hangs forever: always wrap in `timeout`.
- `-s` scripts compile their statically typed dependencies before autoloads exist. In test scripts don't static-type classes that reference the `World` autoload (`PlatformProgram`, `PlatformTrackInstance`, `PlatformTrackGroup`, `PlatformSwitch`); use `Node3D`, and fetch World via `root.get_node("World")`.
- Tests drive the game with `Input.action_press/release` and wait in physics frames. For timing-sensitive moves (swing release, jump/dash), probe a grid of frame timings rather than guessing.
- Skipping `World.time` while the player stands on a platform teleports the platform and flings the player (Jolt applies the jump as platform motion): place the player elsewhere first.

## Architecture

**`World` autoload (`world/world.gd`)**: state that survives scene changes. `World.time` is the world clock (advances in `_physics_process`, so it pauses with the tree). `World.channels` holds per-channel platform state changed by switches. Saving the game is meant to be saving `time` + `channels` (plain data) plus `Player.progression`. `World.spawn` names the marker the next area places the player at.

**Player (`player/player.gd`)**: a `CharacterBody3D` with a state machine of `RefCounted` `PlayerState` objects, one script per state in `player/states/`, preloaded into `Player.states`. `physics(delta)` returns the next state's name or `&""`. States hold a back-reference `p` and call shared helpers on the player (`ground_step`, `move_air`, `apply_gravity`, `landed_state`, `recover_state`...). Adding a state = new script + entry in `states`.
- Gravity can point anywhere (`set_gravity_dir`; walls and ceilings are walkable). Motion is split into vertical (along `up_direction`) and planar. Use `vspeed()`, `set_vspeed()`, `planar()`; never `velocity.y` or `Vector3.UP`.
- Stats: the `@export`s on Player are base values; gameplay reads them through `mult(stat)` = `1 + progression% + environment%` (additive). The percentages live in `StatMods` resources (`player/stat_mods.gd`); a new stat is a new `@export var` there, and `StatMods.names()` picks it up by reflection.
- Animation is a placeholder: states set `p.anim` and `_animate()` squashes/tilts the capsule. Meant to be replaced by an AnimationTree keyed on `anim`.

**Environment**: `EnvProfile` (`world/env_profile.gd`) is a resource with stat mods plus world physics (gravity mult, drag, wind, water, temperature). `EnvZone`s push and pop profiles on the player; overlapping zones are blended by `EnvProfile.combine` on top of `Player.ambient`.

**Shapes (`world/shape_set.gd`, `ShapeSet`)**: zones and moving platforms take their shape from their `CollisionShape3D` children (any shape type, several allowed). `ShapeSet` holds the shared logic as static helpers: drawing each shape (an internal `ShapeMesh` child: see-through debug mesh for zones, lit solid mesh for platforms), `bounds()`, editor redraw polling (`setup`/`refresh`), giving Ctrl+D copies their own shape resources, and the inspector rows (proxy properties `shapes/<child>/<property>` returned from the node's `_get_property_list/_get/_set`). The Shape Tools editor plugin (`addons/shape_tools`, enabled in `project.godot`) draws the Shapes section (Add Shape menu, Remove buttons, both undoable) and resize handles for every shape while the node is selected.

**Zones (`world/zone.gd`)**: `@tool` `Area3D` base, shaped through `ShapeSet` and drawn in its translucent `color`. Code that needs a size reads `bounds()` (AABB of all shapes); zones built in code get shapes via `add_shape()`. Every trigger (EnvZone, GravityZone, KillZone, Checkpoint, Teleporter, SceneDoor, CutsceneTrigger, Interactable → PlatformSwitch) extends it and overrides `_player_entered` / `_player_exited`. Because these are `@tool`, their code runs in the editor; guard runtime-only logic with `Engine.is_editor_hint()`.

**Moving platforms**: positions are a pure function of time, never stepped incrementally, so platforms are in place when an area loads and stay in sync across areas. Roles:
- `PlatformTrackInstance` (`world/platform_track_instance.gd`), a track: one Path3D child, a `sequences` array, and its `MovingPlatform` child.
- `PlatformSequence` (`world/platform_sequence.gd`, a Resource): moves the platform between two anchors of the track's path. It has trips (0 = forever), one way or round trip (one-way trips alternate direction), speed, a start wait (before each departure) and an end wait (on each arrival). Each sequence starts where the previous one left the platform: the track keeps `start_anchor` in step and read-only. On a closed path, start = end is a full lap.
- `PlatformTrackGroup` (`world/platform_track_group.gd`): organises tracks. With `circuit` on, its tracks share the group's `MovingPlatform`, which plays each track's sequences in child order.
- `PlatformProgram` (`world/platform_program.gd`), the base of track and group: the program math (`_compile` → `_plan`, `_fold`, `point_at`) and the timing settings: `after_last` (stop / start over / play backwards), `offset`, `platforms` (evenly spaced internal copies), `channel`, `starts_on`, `preview`, `show_track`. A track inside a circuit hides them (`plays()` is false).
- `MovingPlatform` (`world/moving_platform.gd`): only the body: shapes through `ShapeSet` (a `surface` EnvZone wraps each one, grown 0.3 m), colour, and collision kept off for the first physics frames while Jolt moves it from the scene origin to its place.

The clock is `World.drive(channel, starts_on)`. `PlatformSwitch` actions (POWER, RUN, REVERSE, SPEED, START_WAIT, END_WAIT) only mutate `World.channels` through `World.toggle/run/reverse/set_rates`; programs re-derive positions from that, and rate changes are rebased per platform (`_shifts`) to keep motion continuous.

**Platform Tools (`addons/platform_tools`)**: one icon menu in the 3D toolbar ("Platform Track builder": Shape Refs, Tracks with New Track first, Preview Settings), plus a second icon menu while tracks are selected (Play in Editor, Group, Switch, Reconnect). These act on the track, or on its circuit for circuit tracks. Shape Refs adds a `ShapeReference` (`world/shape_reference.gd`, an editor-only guide that frees itself in game; `cast()` hits any shape via its debug mesh's `TriangleMesh`). Plane references are `WorldBoundaryShape3D` (infinite; cast analytically). New Track takes viewport clicks (`_forward_3d_gui_input`, forwarding always on) as anchors, snapped onto references or on a plane through the last anchor, previewed in 3D by `addons/platform_tools/track_preview.gd` (an internal child of the edited scene while placing; its look is editor settings under `platform_tools/preview/`, edited from Preview Settings), and builds a track with a box platform doing round trips forever. The track draws a ghost of the platform at its path end, and config warnings enforce the structure. Clicking the first anchor again (3+ placed) closes the loop: a full lap forever. Inside a circuit, a new track runs once and is joined to its neighbours. The Shape Refs (N) / Tracks (N) submenus list, select and remove those nodes (removal restores owners on undo). Play in Editor sets `preview` on the selected tracks' programs. Switch adds a `PlatformSwitch` to the selected track and puts the programs on its channel. Channels come from `addons/platform_tools/channel_registry.gd`: project-wide (World channels are global), built from every saved `.tscn`'s `channel = &"..."` lines plus the open scene's nodes, so a new name is refused if any scene already uses it (sharing = picking it from the list); the inspector's `channel` field on tracks, circuits and switches uses the same picker (`channel_picker.gd`, `channel_property.gd`). Group moves selected tracks into a `PlatformTrackGroup`; its `show_paths` / `show_destination` are read by its tracks each editor frame. The group's inspector `circuit` checkbox calls `set_circuit`: the first track's platform moves under the group, the others go, each track gets a single run from its first anchor to its last, and neighbouring ends meet halfway (`join_circuit`, also last → first when the circuit starts over). Turning it off gives each track a copy of the platform. Reconnect re-joins the ends. All undoable.

**Areas (`world/area.gd`, `GameArea`)**: root script of each playable scene. It expects children `Player`, `Camera`, `HUD/Label` and optionally `Bays` (debug warp targets, each with an optional `Start` marker). It runs the iso camera follow, the debug HUD (`Player.debug_text()` + `World.debug_text()`), debug keys and bay warps (`[ ]`, Backspace), and the out-of-bounds fall death. Each scene subclasses it (`demo/demo.gd`, `demo/puzzles/puzzles.gd`). `SceneDoor` sets `World.spawn` and changes scene; platforms_a and platforms_b link to each other this way.

## Conventions

- `ponytail:` comments mark deliberate shortcuts with a known ceiling (e.g. unrotated zones only, no cutscene timeout). Read them before extending that code.
- Each script has a committed `.uid` sidecar; keep it with the script when moving or renaming (do moves in the editor, or `git mv` both files).
- Static typing and `##` doc comments are used throughout; input actions are defined in `project.godot`.
- In `@tool` scripts create child nodes in `_ready`, not as member defaults (`var _x := Node.new()`): a script reload in the editor re-runs member defaults and leaks those nodes.
