# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

AHRA: a Godot 4.7 GDScript prototype of isometric 3D platformer mechanics (Jolt physics, physics interpolation on, D3D12 on Windows). Main scene: `res://demo/demo.tscn`. No build or lint step; the editor is `C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe` (older 4.5/4.6 exes sit next to it, don't use them).

## Verifying changes (headless)

Tests are `SceneTree` scripts in `tests/`. One script = one suite; there is no per-case filter. Exit code = number of failed checks; the last line prints `SMOKE|PLATFORMS|PUZZLES: OK` or `N FAILED`.

```sh
GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"   # godot-git-plugin log spam

timeout 150 "$GODOT" --headless --path . -s res://tests/smoke_test.gd    2>&1 | grep -viE "$NOISE"   # player controller, ~45 s
timeout 150 "$GODOT" --headless --path . -s res://tests/platform_test.gd 2>&1 | grep -viE "$NOISE"   # moving platforms (demo/platforms)
timeout 300 "$GODOT" --headless --path . -s res://tests/puzzle_test.gd   2>&1 | grep -viE "$NOISE"   # walkthrough of all 10 puzzles, ~3 min

timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/demo.tscn   # load/run a scene, watch for errors
timeout 150 "$GODOT" --headless --path . --editor --quit-after 400             # catch errors in @tool scripts
```

Run the suites that cover what you touched after any player/world change. They check physics and logic only; game feel is untested, so say so.

Gotchas:
- A script error stops the test before `quit()` and Godot hangs forever: always wrap in `timeout`.
- `-s` scripts compile their statically typed dependencies before autoloads exist. In test scripts don't static-type classes that reference the `World` autoload (`MovingPlatform`, `PlatformSwitch`); use `Node3D`, and fetch World via `root.get_node("World")`.
- Tests drive the game with `Input.action_press/release` and wait in physics frames. For timing-sensitive moves (swing release, jump/dash), probe a grid of frame timings rather than guessing.
- Skipping `World.time` while the player stands on a platform teleports the platform and flings the player (Jolt applies the jump as platform motion): place the player elsewhere first.

## Architecture

**`World` autoload (`world/world.gd`)**: state that survives scene changes. `World.time` is the world clock (advances in `_physics_process`, so it pauses with the tree). `World.channels` holds per-channel platform state changed by switches. Saving the game is meant to be saving `time` + `channels` (plain data) plus `Player.progression`. `World.spawn` names the marker the next area places the player at.

**Player (`player/player.gd`)**: a `CharacterBody3D` with a state machine of `RefCounted` `PlayerState` objects, one script per state in `player/states/`, preloaded into `Player.states`. `physics(delta)` returns the next state's name or `&""`. States hold a back-reference `p` and call shared helpers on the player (`ground_step`, `move_air`, `apply_gravity`, `landed_state`, `recover_state`...). Adding a state = new script + entry in `states`.
- Gravity can point anywhere (`set_gravity_dir`; walls and ceilings are walkable). Motion is split into vertical (along `up_direction`) and planar. Use `vspeed()`, `set_vspeed()`, `planar()`; never `velocity.y` or `Vector3.UP`.
- Stats: the `@export`s on Player are base values; gameplay reads them through `mult(stat)` = `1 + progression% + environment%` (additive). The percentages live in `StatMods` resources (`player/stat_mods.gd`); a new stat is a new `@export var` there, and `StatMods.names()` picks it up by reflection.
- Animation is a placeholder: states set `p.anim` and `_animate()` squashes/tilts the capsule. Meant to be replaced by an AnimationTree keyed on `anim`.

**Environment**: `EnvProfile` (`world/env_profile.gd`) is a resource with stat mods plus world physics (gravity mult, drag, wind, water, temperature). `EnvZone`s push and pop profiles on the player; overlapping zones are blended by `EnvProfile.combine` on top of `Player.ambient`.

**Zones (`world/zone.gd`)**: `@tool` `Area3D` base that builds its own box collision and translucent debug mesh from `size`. Every trigger (EnvZone, GravityZone, KillZone, Checkpoint, Teleporter, SceneDoor, CutsceneTrigger, Interactable → PlatformSwitch) extends it and overrides `_player_entered` / `_player_exited`. Because these are `@tool`, their code runs in the editor; guard runtime-only logic with `Engine.is_editor_hint()`.

**Moving platforms (`world/moving_platform.gd`)**: an `AnimatableBody3D` whose position is a pure function of time, never stepped incrementally. Its program is its `PlatformSequence` children played in order, each following a `Path3D`. The program clock is `World.drive(channel, starts_on)`, so platforms are already in place when an area loads and stay in sync across areas. `PlatformSwitch` actions (POWER, RUN, REVERSE, SPEED, LAP_WAIT, SEQUENCE_WAIT) only mutate `World.channels` through `World.toggle/run/reverse/set_rates`; platforms re-derive their position from that. Rate changes are rebased (`_shift`) to keep motion continuous. Collision stays off for the first physics frames while Jolt moves the body from the scene origin to its place.

**Areas (`world/area.gd`, `GameArea`)**: root script of each playable scene. It expects children `Player`, `Camera`, `HUD/Label` and optionally `Bays` (debug warp targets, each with an optional `Start` marker). It runs the iso camera follow, the debug HUD (`Player.debug_text()` + `World.debug_text()`), debug keys and bay warps (`[ ]`, Backspace), and the out-of-bounds fall death. Each scene subclasses it (`demo/demo.gd`, `demo/puzzles/puzzles.gd`). `SceneDoor` sets `World.spawn` and changes scene; platforms_a and platforms_b link to each other this way.

## Conventions

- `ponytail:` comments mark deliberate shortcuts with a known ceiling (e.g. unrotated zones only, no cutscene timeout). Read them before extending that code.
- Each script has a committed `.uid` sidecar; keep it with the script when moving or renaming (do moves in the editor, or `git mv` both files).
- Static typing and `##` doc comments are used throughout; input actions are defined in `project.godot`.
