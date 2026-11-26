# Slow Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brief hit-stops (player hurt, player hits), slow-motion areas and player-activated bullet
time, all multiplied into one `Engine.time_scale`, with menus, GUI, input and the camera on real
time.

**Architecture:** A static `SlowMo` class (like `CameraShake`) holds the three factors and returns
the scale. `World` applies it every frame from `SceneTree.process_frame` (which fires while
paused). Bullet time keeps the player at full speed by dividing the bullet factor out of the
player's own clock and its `move_and_slide` velocity.

**Tech Stack:** Godot 4.7.2, GDScript (static typing, `##` docs), Jolt physics, headless
`SceneTree` test scripts.

**Spec:** `docs/superpowers/specs/2026-11-26-slow-motion-design.md`

## Global Constraints

- Godot exe: `GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"`. Filter
  output with `NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"`.
  Always wrap runs in `timeout`.
- Run Godot with `--path .` from the worktree root
  (`F:/Godot/ahra/.claude/worktrees/slow-motion`). Never `cd` elsewhere.
- This worktree has no `.godot` cache. Before the first `-s` run, and after adding any
  `class_name` script, run `timeout 150 "$GODOT" --headless --path . --editor --quit-after 400`.
  That run also writes the `.uid` sidecars: commit them with their scripts.
- `SlowMo` must not reference the `World` autoload. Player, Enemy, Projectile call it, and `-s`
  tests compile them first.
- Test scripts must not statically type World-referencing classes (`Npc`, `Door`, `Dispenser`,
  `GameArea`, `Channels`...). Use `Node3D`, `load()` at runtime, and `root.get_node("World")`.
- Static typing and `##` doc comments throughout. Deliberate shortcuts get a `ponytail:` comment
  naming the ceiling.
- Don't edit `demo/builder/` or `.godot/editor/editor_layout.cfg`.
- Toggle key, verbatim: `ahra/time/disable_hit_stop` (default `false`).
- Feel table, verbatim (real seconds):

  | Feel | speed | hold | ramp |
  |------|-------|------|------|
  | SHOT | 0.3  | 0.04 | 0.04 |
  | HIT  | 0.12 | 0.07 | 0.05 |
  | HURT | 0.08 | 0.10 | 0.08 |
  | KILL | 0.05 | 0.14 | 0.10 |

- `MIN_SCALE := 0.02`. Real frame time is clamped to 0.1 s.
- Bullet time defaults: `bullet_capacity := 4.0`, `bullet_refill := 0.5`, `bullet_scale := 0.3`,
  `bullet_min := 0.5`. The ease between 1 and 0.3 takes about 0.15 s.
- Commit messages carry no attribution lines.

## Review Focus

1. **Scene change mid-effect:** a SceneDoor taken during a hit-stop or bullet time should arrive
   at full speed. Test in Task 3 (`realtime`).
2. **Pause mid-stop:** pausing the tree must give scale 1 and freeze the stop, and unpausing must
   resume it. Test in Task 1 (`rules`, driver part).
3. **Unpause with bullet time on:** the first frames after unpausing must not move the player
   1 / 0.3 too fast. Test in Task 5 (`bullet`).
4. **Jumping off a moving platform in bullet time:** the inherited platform speed must be scaled.
   Test in Task 5 (`bullet`).
5. **A trigger held down:** the left trigger is an axis. Holding it must not toggle bullet time
   every frame (`just_pressed` only). Test in Task 5 (`bullet`): an action held for 30 frames toggles
   once.

---

### Task 1: `SlowMo` core, the World driver, the toggle

**Files:**
- Create: `world/slow_mo.gd` (+ `.uid`)
- Modify: `world/world.gd` (`_ready`, a new driver method, `debug_text`)
- Modify: `project.godot` (`[ahra]`: `time/disable_hit_stop=false`)
- Create: `tests/slowmo_test.gd` (+ `.uid`)

**Interfaces:**
- Produces (`class_name SlowMo extends RefCounted`, static only):
  - `enum Feel { SHOT, HIT, HURT, KILL }` (later = stronger)
  - `const DISABLE := "ahra/time/disable_hit_stop"`, `const MIN_SCALE := 0.02`,
    `const BULLET_EASE := 0.15`, `const FEELS := {Feel.X: {speed, hold, ramp}}`
  - `static var area := 1.0`, `static var bullet_target := 1.0`, `static var bullet := 1.0`
    (the factor inside the last returned scale, 1 while paused), `static var real_delta := 0.0`,
    `static var stops := 0`, `static var stop := {}` (`{feel, age, frame}`, empty when none)
  - `static func add(feel: Feel) -> void`
  - `static func update(real_dt: float, paused: bool) -> float`
  - `static func clear() -> void`
- Produces (World): it drives `Engine.time_scale` every frame. `World.debug_text()` includes
  `"time ×%.2f" % Engine.time_scale`.

- [ ] **Step 1: Write the suite skeleton and the `rules` section**

Copy the shake suite's skeleton (`tests/shake_test.gd:1-33` and its `_wait`/`_check`/`_area`
helpers). Changes:
- `SECTIONS := 1`, sections list `[_test_rules]`, last line `print("SLOWMO: ", ...)`.
- At the start of `_run`: `ProjectSettings.set_setting(SlowMo.DISABLE, false)`.
- Before each section: `SlowMo.clear()`, `Engine.time_scale = 1.0`, `paused = false`.

`_test_rules` uses explicit deltas, **with no `await` between an `add` and its `update` calls** (the
World driver ages the stop on each real frame):
- `add(HIT)`: `stops == 1`, `update(0.0, false) ≈ 0.12`. `update(0.06, false) ≈ 0.12` (holding).
  After a total of 0.12 s, `stop.is_empty()` and `update(0.0, false) == 1.0`.
- **Same frame:** `add(HIT)` then `add(KILL)` gives `stop.feel == KILL` and `stops` up by 1 only.
  `add(SHOT)` after that leaves `stop.feel == KILL`.
- **Dropped:** `add(HIT)`, `await physics_frame`, then `add(KILL)` leaves `stop.feel == HIT` and
  `stops` unchanged.
- **Area:** `area = 0.5`, then `add(HIT)`: `update(0.0, false) ≈ 0.06`, and it's over after 0.12 s,
  the same as at area 1.
- **Floor:** `area = 0.05`, `bullet_target = 0.3`, a settled bullet and `add(KILL)` give exactly
  `MIN_SCALE`.
- **Bullet ease:** `bullet_target = 0.3`, then `update(0.1, false)` twice: the result ≈ 0.3 and
  `bullet ≈ 0.3`. A single `update(0.05, false)` gives a value strictly between 0.3 and 1.
- **Toggle:** with `DISABLE` true, `add(HIT)` leaves `stops` unchanged and `area = 0.5` still gives
  0.5. Reset `DISABLE` to false.
- **Paused:** `add(HIT)`, `update(0.05, true) == 1.0`, `bullet == 1.0` and `stop.age` unchanged.
  Then `update(0.0, false) ≈ 0.12`.
- `clear()`: `stop.is_empty()`, `area == 1`, `bullet_target == 1`, `bullet == 1`.
- **Driver** (Review Focus 2):
  - `add(HIT)`, `await process_frame` ×2: `Engine.time_scale` is about 0.12.
  - `paused = true`, `await process_frame` ×3: `Engine.time_scale == 1.0` and `stop.age`
    unchanged.
  - `paused = false`, `await process_frame` ×2: `Engine.time_scale < 1`.
  - Within 60 process frames, `Engine.time_scale == 1.0`.

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 150 "$GODOT" --headless --path . -s res://tests/slowmo_test.gd 2>&1 | grep -viE "$NOISE"`
Expected: a parse error naming `SlowMo` (or hanging until the timeout).

- [ ] **Step 3: Implement `world/slow_mo.gd`**

- The stop factor at `age`: `speed` while `age < hold`, then
  `lerpf(speed, 1.0, smoothstep(0.0, ramp, age - hold))`. The stop is over at `age >= hold + ramp`.
- `add` reads `DISABLE` from ProjectSettings. It replaces a running stop only when
  `stop.frame == Engine.get_physics_frames()` and the new feel's enum value is larger.
- `update` keeps a private `_level` (the eased bullet factor, kept while paused). It eases
  `_level` toward `bullet_target` with
  `move_toward(_level, bullet_target, real_dt * 0.7 / BULLET_EASE)`. Then `bullet = 1.0` if paused,
  else `_level`. It stores `real_delta = real_dt`.
- `clear()` also resets `_level`.
- The class doc says what `CameraShake`'s says: static only, must not reference World, the toggle
  is read in `add`.

- [ ] **Step 4: Driver and toggle**

- `World._ready`: `get_tree().process_frame.connect(_scale_time)`.
- `_scale_time()`:
  - Real seconds since its last call from `Time.get_ticks_usec()`: 0 on the first call, clamped to
    0.1.
  - `Engine.time_scale = SlowMo.update(real, get_tree().paused)`.
  - Doc it: the signal fires while paused, so World keeps its pausable process mode.
- `debug_text()`: add the time line.
- `project.godot` `[ahra]`: add `time/disable_hit_stop=false`.

- [ ] **Step 5: Refresh the class cache, run, pass**

Run the editor command from Global Constraints, then the suite.
Expected: every line `ok`, and the last line `SLOWMO: OK`.

- [ ] **Step 6: Commit**

```bash
git add world/slow_mo.gd world/slow_mo.gd.uid world/world.gd project.godot tests/slowmo_test.gd tests/slowmo_test.gd.uid
git commit -m "SlowMo: hit-stop feels and time scale composition, driven by World"
```

---

### Task 2: Hit hooks (hurt, melee, shots)

**Files:**
- Modify: `player/player.gd` (`damage`, `melee_hit`)
- Modify: `world/projectile.gd` (`_finish`)
- Modify: `tests/enemy_test.gd`, `tests/shake_test.gd`, `tests/smoke_test.gd`,
  `tests/switch_test.gd` (one line each)
- Test: `tests/slowmo_test.gd` (section `hits`)

**Interfaces:**
- Consumes: `SlowMo.add`, `SlowMo.stop`, `SlowMo.stops`, `SlowMo.Feel` (Task 1).

- [ ] **Step 1: Write the `hits` section**

Use `_area()`, with enemies from `res://enemy/enemy.tscn`. Each enemy gets
`set_physics_process(false)` so it never attacks, and `health = 100`. Wait 30 frames first. Place
two enemies at `p.global_position + p.facing * p.melee_reach ± p.facing.cross(p.up_direction) * 0.3`.
Checks:
- **Swing:** `Input.action_press(&"attack")`, 1 frame, release, then wait until
  `p.state_name != &"melee"`. Expected: `stops` up by exactly 1, `stop.feel == HIT`, and both
  enemies' health below 100. Within 60 frames `Engine.time_scale == 1.0`.
- **Killing swing:** set one enemy's `health = 0.1` (and its invuln to 0), wait for the stop to end,
  then swing. Expected: `stop.feel == KILL`.
- **Hurt:** after the stop ends, `p.damage(10)` gives `HURT`. After it ends and `p.invuln = 0`,
  `p.damage(p.health + 1)` gives `KILL`. Then `p.respawn()`.
- **Shot:** one fresh enemy 4 m along `p.facing`. `var b := p.shoot()`, then wait until
  `not is_instance_valid(b)` (≤ 60 frames). Expected: `stop.feel == SHOT`.
- **Enemy shot:** after the stop ends and `p.invuln = 0.0` (the respawn gave i-frames), instantiate `p.PROJECTILE`, add it to the area, call
  `setup(pos 5 m away, dir, 5.0, 0.0, enemy)`, then `b._finish(p)`. Expected: `stop.feel == HURT`
  (from `damage`), never SHOT.
- **Energy switch:** after the stop ends, a player-sourced projectile with `b._finish(t)`, where `t`
  is a Node3D with a runtime `GDScript` (`source_code = "extends Node3D\nfunc shot() -> void:\n\tpass"`,
  `reload()`). Expected: `stops` unchanged.
- **Input during a stop:** `SlowMo.add(HIT)`, `await physics_frame`, `Input.action_press(&"jump")`,
  `await physics_frame`. Expected: `p.jump_buffer > 0.0` or `p.vspeed() > 0.0`. Release.

Bump `SECTIONS`.

- [ ] **Step 2: Run the section and verify it fails**

Run: `timeout 150 "$GODOT" --headless --path . -s res://tests/slowmo_test.gd -- hits 2>&1 | grep -viE "$NOISE"`
Expected: FAIL lines on the `stops` / `feel` checks.

- [ ] **Step 3: Hooks**

- `Player.damage`: right after the `CameraShake.add` line,
  `SlowMo.add(SlowMo.Feel.KILL if amount >= health else SlowMo.Feel.HURT)`.
- `Player.melee_hit`: track whether any hit enemy's `state_name == &"death"` after its `hit`.
  After the loop, if `landed > 0`, `SlowMo.add(KILL if killed else HIT)`.
- `Projectile._finish`, Enemy branch: when `landed and source is Player` (guard with
  `is_instance_valid(source)`), `SlowMo.add(KILL if the enemy's state_name == &"death" else SHOT)`.

- [ ] **Step 4: Turn the stops off in the existing suites**

First line of `_run()` in `enemy_test`, `shake_test`, `smoke_test`, `switch_test` (after the
initial `await process_frame` where there is one): `ProjectSettings.set_setting(SlowMo.DISABLE,
true) # suites count physics frames; tests/slowmo_test.gd covers the stops`.

- [ ] **Step 5: Run, pass**

Run `slowmo_test` (all sections), then `enemy_test`, `shake_test`, `smoke_test`, `switch_test` with
the CLAUDE.md commands.
Expected: `SLOWMO: OK`, `ENEMIES: OK`, `SHAKE: OK`, `SMOKE: OK`, `SWITCHES: OK`.

- [ ] **Step 6: Commit**

```bash
git add player/player.gd world/projectile.gd tests/
git commit -m "Hit-stops on player hurt, melee and shots"
```

---

### Task 3: Real-time camera and GUI, reset on area load

**Files:**
- Modify: `world/area.gd` (`_ready`, `_process`)
- Modify: `world/world.gd` (`fade`)
- Test: `tests/slowmo_test.gd` (section `realtime`)

**Interfaces:**
- Consumes: `SlowMo.real_delta`, `SlowMo.clear()`, `SlowMo.add` (Task 1).

- [ ] **Step 1: Write the `realtime` section**

Use `_area()` and wait 30 frames. Each check starts with `SlowMo.add(KILL)` (0.24 s of stop) and
waits for it to end afterwards:
- **Shake:** `p.damage(10)` (HURT plus a JOLT). Record `Time.get_ticks_usec()`, wait 10 physics
  frames. Expected: the JOLT layer's `age` is within 0.05 s of the real elapsed time.
- **Follow:** `p.teleport(p.global_position + Vector3(3, 0, 0))`, then wait 15 physics frames.
  Expected: the camera moved more than 2 m toward the new target (the scaled delta would move it
  about 0).
- **Fade:** `World.fade(1.0, 0.15)` (not awaited), wait 15 physics frames (0.25 s real; on game
  time only about 0.08 s pass, so a scaled tween is still mid-way). Expected:
  `World.fade_rect.color.a == 1.0`. Then `World.fade(0.0, 0.0)`.
- **Area load** (Review Focus 1): `SlowMo.add(KILL)`, `SlowMo.bullet_target = 0.3`, then a fresh
  `_area()` and 3 process frames. Expected: `Engine.time_scale == 1.0` and `stop.is_empty()`.

Bump `SECTIONS`.

- [ ] **Step 2: Run the section and verify it fails**

Run: `... -s res://tests/slowmo_test.gd -- realtime`
Expected: FAIL on the shake, follow, fade and area-load checks.

- [ ] **Step 3: Implement**

- `GameArea._ready`: `SlowMo.clear()` next to `CameraShake.clear()`.
- `GameArea._process`: the follow lerp and `_shake(...)` take `SlowMo.real_delta`. Comment why
  not `delta`, and not `delta / Engine.time_scale` (wrong in a frame where the scale just changed).
- `World.fade`: `_fade_tween.set_ignore_time_scale(true)`.

- [ ] **Step 4: Run, pass**

Run `slowmo_test` and `shake_test`.
Expected: `SLOWMO: OK`, `SHAKE: OK`.

- [ ] **Step 5: Commit**

```bash
git add world/area.gd world/world.gd tests/slowmo_test.gd
git commit -m "Camera follow, shake and fade on real time; slow motion resets per area"
```

---

### Task 4: Slow areas

**Files:**
- Modify: `world/env_profile.gd` (export plus `combine`)
- Modify: `world/area.gd` (`_process`)
- Test: `tests/slowmo_test.gd` (section `area`)

**Interfaces:**
- Produces: `EnvProfile.time_scale: float` (`@export_range(0.05, 1.0)`, default 1.0, group
  "Time"). `combine` multiplies it.
- Consumes: `SlowMo.area` (Task 1).

- [ ] **Step 1: Write the `area` section**

- **combine:** two profiles with `time_scale = 0.5` combine to 0.25.
- **Setup:** `_area()`, 30 frames. Measure walking with `Input.action_press(&"move_right")`: after
  30 frames of walking, the mean per-tick displacement over 10 frames is `d_out`, and the mean
  `World.time` step is `w_out`. Release and stop.
- **Inside a zone:** an EnvZone built as in `shake_test._test_env` (box 30 × 4 × 30, profile
  `time_scale = 0.5`) around the player, 30 frames. Expected: `Engine.time_scale` ≈ 0.5 (±0.01),
  the `World.time` step ≈ 0.5 × `w_out`, and the walking displacement ≈ 0.5 × `d_out` (±10%).
- **Hit inside it:** `SlowMo.add(HIT)` and 2 process frames give `Engine.time_scale` ≈ 0.06. Wait
  for it to end.
- **Toggle:** with `DISABLE` true, `add` does nothing and the scale stays ≈ 0.5. Reset it.
- **Overlap:** a second identical zone gives ≈ 0.25.
- **Leaving:** teleport 40 m away, 5 frames. Expected: `Engine.time_scale == 1.0`.

Bump `SECTIONS`.

- [ ] **Step 2: Run the section and verify it fails**

Expected: the `combine` check errors on the missing property, or FAILs.

- [ ] **Step 3: Implement**

- `EnvProfile`: the export, and in `combine`: `out.time_scale *= e.time_scale`. Update the
  combine doc line.
- `GameArea._process`: `SlowMo.area = player.env.time_scale if player.env else 1.0`, next to the
  shake read.

- [ ] **Step 4: Run, pass**

Run `slowmo_test`, `shake_test` (env combine) and `smoke_test`.
Expected: OK on all.

- [ ] **Step 5: Commit**

```bash
git add world/env_profile.gd world/area.gd tests/slowmo_test.gd
git commit -m "Slow areas: EnvProfile.time_scale"
```

---

### Task 5: Bullet time

**Files:**
- Modify: `project.godot` (`[input]`: `bullet_time`)
- Modify: `player/player.gd` (exports, state, `_physics_process`, `slide()`, `debug_text`, the
  `move_and_slide()` call)
- Modify: `player/states/*.gd` (10 files: `move_and_slide()` → `slide()`; `jump.gd` carry)
- Modify: `player/player.tscn` (a `GaugeLayer/Gauges/Bullet` ProgressBar), `player/gauges.gd`
- Modify: `world/area.gd` (`HELP`: `V bullet time`)
- Test: `tests/slowmo_test.gd` (section `bullet`)

**Interfaces:**
- Consumes: `SlowMo.bullet`, `SlowMo.bullet_target`, `SlowMo.add` (Task 1). Task 4's area
  composition is unaffected.
- Produces (Player): `@export_group("Bullet time")` with `bullet_capacity := 4.0`,
  `bullet_refill := 0.5`, `bullet_scale := 0.3`, `bullet_min := 0.5`; `var bullet_meter: float`
  (starts full); `var bullet_on := false`; `func slide() -> void`.

- [ ] **Step 1: Write the `bullet` section**

`_area()`, 30 frames. `tap(action)` = `action_press`, 1 physics frame, `action_release`.
Walking measures as in Task 4 (`d0`, `w0`).
- **On:** `tap(&"bullet_time")`, 20 frames. Expected: `p.bullet_on`, `Engine.time_scale` ≈ 0.3
  (±0.01), the `World.time` step ≈ 0.3 × `w0`, and the walking displacement ≈ `d0` (±10%).
- **Drain:** over 60 frames, `bullet_meter` drops by ≈ 1.0 (±0.1). The gauge
  `GaugeLayer/Gauges/Bullet` is visible.
- **Hit during it:** `SlowMo.add(HIT)` and 2 process frames give `Engine.time_scale` ≈ 0.036.
  Wait for it to end.
- **Unpause** (Review Focus 3): `paused = true`, 3 process frames, `Engine.time_scale == 1.0`.
  Then `paused = false` and walk. Expected: each of the first 3 physics frames' displacement is
  ≤ 1.15 × `d0`.
- **Carry:** spawn `res://puzzle/box.tscn` in front, `p.lift()`. Walk 30 frames with bullet time
  on. Expected: `p.held` is still set, and
  `p.held.global_position.distance_to(p.global_position + p.up_direction * p.hold_height) < 0.05`.
  Then `p.put_down()`.
- **Off:** `tap(&"bullet_time")`, 20 frames. Expected: `not p.bullet_on` and
  `Engine.time_scale == 1.0`. Over 60 frames the meter rises by ≈ 0.5 (±0.1).
- **Held trigger** (Review Focus 5): hold `bullet_time` for 30 frames. Expected: `bullet_on`
  flipped exactly once (on). Release, then tap it off.
- **Empty:** on, then `p.bullet_meter = 0.05`, 10 frames. Expected: off.
- **Below minimum:** `p.bullet_meter = 0.3`, tap. Expected: stays off.
- **Death:** meter full, on, `p.die(&"hit")`, 2 frames. Expected: off and
  `SlowMo.bullet_target == 1.0`. `p.respawn()`, then 20 frames: `Engine.time_scale == 1.0`.
- **Puppet:** on, `p.change_state(&"puppet")`, 2 frames. Expected: off. Then
  `p.change_state(&"idle")`.
- **Platform jump** (Review Focus 4): a platform track built with `shake_test`'s
  `_track`/`_platform` helpers: a straight 30 m path along x, round trip, speed 4, no waits. Put
  the player on it, wait 30 frames, turn bullet time on, wait 20. Record
  `fv := p.floor_velocity.slide(p.up_direction).length()` (expect ≈ 4), then `tap(&"jump")`.
  Expected: `p.carry.length()` ≈ `fv × SlowMo.bullet` (±15%).

Bump `SECTIONS`.

- [ ] **Step 2: Run the section and verify it fails**

Expected: an error on the unknown action / property, or FAILs.

- [ ] **Step 3: Input action**

Append to `[input]` in `project.godot`:

```
bullet_time={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":86,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":4,"axis_value":1.0,"script":null)
]
}
```

- [ ] **Step 4: Player clock and `slide()`**

- `slide()`: `velocity /= SlowMo.bullet`, `move_and_slide()`, `velocity *= SlowMo.bullet`. Doc it:
  `move_and_slide` moves by the engine's scaled step, so the velocity is lifted out of bullet
  time.
- Replace every `move_and_slide()` in `player/` (11 calls; none uses the return value). Run
  `grep -rn "move_and_slide()" player/`: only the one inside `slide()` should remain.
- `_physics_process`: first line `delta /= SlowMo.bullet # the player's clock: bullet time is
  divided out, hit-stops and slow areas still slow it`.
- `jump.gd:13-14`: multiply the inherited `floor_velocity` (both the planar carry and the up part)
  by `SlowMo.bullet`.

- [ ] **Step 5: Toggle, meter, auto-off**

In `_physics_process`, after the timers:
- `just_pressed(&"bullet_time")` flips `bullet_on`. It only turns on when
  `bullet_meter >= bullet_min` and the state is not death or puppet.
- While on, `bullet_meter -= delta`, and at ≤ 0 it turns off. While off,
  `bullet_meter = minf(bullet_meter + bullet_refill * delta, bullet_capacity)`.
- Death or puppet turn it off.
- Last: `SlowMo.bullet_target = bullet_scale if bullet_on else 1.0`.
- `debug_text()`: `"bullet %.1f / %.1f s%s" % [bullet_meter, bullet_capacity, " (on)" if bullet_on else ""]`.
- A `ponytail:` comment at `slide()` or the toggle: a pushed weight moves on world time
  (`WeightBody.push_from`), so the player outpaces it in bullet time.

- [ ] **Step 6: Gauge and help**

- `player.tscn`: a `Bullet` ProgressBar under `GaugeLayer/Gauges`. Copy the `Oxygen` node's
  properties and give it a cyan `self_modulate`.
- `gauges.gd`: `value = bullet_meter / bullet_capacity`, visible while `< 0.999` or `bullet_on`.
- `GameArea.HELP`: append ` | V bullet time` to the first line.

- [ ] **Step 7: Run, pass**

Run `slowmo_test`, then `smoke_test`, `platform_test`, `puzzle_test`, `enemy_test`, `npc_test`,
`switch_test`, `shake_test` (every player state changed).
Expected: all OK.

- [ ] **Step 8: Commit**

```bash
git add project.godot player/ world/area.gd tests/slowmo_test.gd
git commit -m "Bullet time: V slows the world, the player keeps full speed, meter gauge"
```

---

### Task 6: Demo scene and docs

**Files:**
- Create: `demo/slowmo/slowmo.tscn`, `demo/slowmo/slowmo.gd` (+ `.uid`)
- Modify: `CLAUDE.md`
- Test: `tests/slowmo_test.gd` (section `demo`)

**Interfaces:**
- Consumes: everything above. `demo/shake/shake.tscn` and `demo/shake/shake.gd` are the templates.

- [ ] **Step 1: Write the `demo` section**

Load `res://demo/slowmo/slowmo.tscn` as the current scene (as `shake_test._test_demo` does), then
10 frames. Checks:
- `Bays/Hits` holds at least 2 `Enemy` nodes.
- `Bays/SlowArea/Zone.profile.time_scale == 0.4`.
- `Bays/BulletTime` holds at least 1 `Enemy` and a node with signal `slammed`.
- Teleport the player to `Bays/SlowArea/Zone`'s position, 30 frames. Expected:
  `Engine.time_scale` ≈ 0.4.
- Teleport back to `Bays/Hits/Start`. Calling `area._unhandled_input` with a pressed `KEY_9`
  `InputEventKey` flips `SlowMo.DISABLE`. Flip it back.
- Run 120 frames: no script errors (the sections counter guards silent failures).

Bump `SECTIONS`.

- [ ] **Step 2: Run the section and verify it fails**

Expected: FAIL / error, because the scene doesn't exist.

- [ ] **Step 3: Build the scene**

`slowmo.gd` extends GameArea like `shake.gd`:
- `help()`: `super() + "V bullet time | 9 hit slow-down (%s)\n\n"`, showing on/off from `DISABLE`.
- `_unhandled_input`: KEY_9 flips `SlowMo.DISABLE`, otherwise `super(e)`.

`slowmo.tscn`: copy the shake scene's root setup (WorldEnvironment, Sun, Camera, HUD/Label,
Player, Void, Floor). Each bay has a `Start` Marker3D and a `Label3D` explaining it:
- `Hits`: two `enemy/runner/runner.tscn` and one `enemy/brute/brute.tscn`. The label says melee,
  shoot, and key 1 for hurt.
- `SlowArea`: `Zone`, an EnvZone with an inline EnvProfile (`resource_name` "Slow", `time_scale`
  0.4) and a tinted colour. Over it, a platform track doing round trips, and a `Dispenser` (count
  3, `weight_scene` `res://puzzle/ball.tscn`) dropping balls into it.
- `BulletTime`: two runners, `CrusherA`/`CrusherB` copied from `demo/shake/shake.tscn` (with their
  Anvils), and a Dispenser of balls above a CSG slope. The label says to press V.

- [ ] **Step 4: Docs**

`CLAUDE.md`:
- **Test list:** the line
  `timeout 200 "$GODOT" --headless --path . -s res://tests/slowmo_test.gd 2>&1 | grep -viE "$NOISE"   # hit-stop, slow areas, bullet time, real-time camera/GUI, demo, ~1 min`.
  Add `SLOWMO` to the OK list, add the suite to "take section names" (`-- rules bullet`), and add
  the note that the hit suites turn `ahra/time/disable_hit_stop` on.
- **Architecture:** a **Slow motion (`world/slow_mo.gd`, `SlowMo`)** paragraph:
  - The three factors and how they multiply, the feels table location, the drop-while-running
    rule, and the toggle.
  - The World `process_frame` driver: pause gives 1.
  - The player's clock, `slide()`, and the platform carry.
  - Real-time camera follow, shake and fade.
  - **The GUI rule:** a menu pauses the tree; GUI animating while the game runs uses
    `set_ignore_time_scale` / `ignore_time_scale` timers.
  - A new trigger is one line, `SlowMo.add(SlowMo.Feel.HIT)`.
  - Must not reference World. Demo: `demo/slowmo/slowmo.tscn`.
- The GameArea paragraph says the camera follow and shake run on `SlowMo.real_delta`.

- [ ] **Step 5: Refresh the cache, then run everything**

Run the editor command (it also writes `slowmo.gd.uid` and catches `@tool` errors), then
`--quit-after 300 res://demo/slowmo/slowmo.tscn` (expect no errors), then all suites in CLAUDE.md
(the three editor-tool tests too: they load the player scene and project settings).
Expected: every suite prints `OK`.

- [ ] **Step 6: Commit**

```bash
git add demo/slowmo/ CLAUDE.md tests/slowmo_test.gd
git commit -m "Slow motion demo scene and docs"
```
