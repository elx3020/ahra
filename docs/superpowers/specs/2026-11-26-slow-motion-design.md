# Slow motion (hit-stop, slow areas, bullet time): design

**Status:** draft 2026-11-26, waiting for approval.

## Why

Impact. When the player lands a hit or gets hurt, the 3D world dips into slow motion for a fraction
of a second, so the hit reads. A heavier hit (a kill) holds longer than a quick one (a shot).
The same time scale also serves longer slow motion: a place where time runs slow, and a
player-activated bullet time where the world slows and the player keeps full speed. One owner
combines all three, so they never fight. Like the camera shake, the hit effect has a global
toggle in Project Settings.

## Goals

- **Hit-stop**: the player getting hurt, or a player attack landing on an enemy, slows the world
  briefly. It comes in feels (a preset table like CameraShake's), each with its own depth and
  length.
- **No overlap**: while a hit-stop runs, new ones are dropped, not queued. One swing that hits two
  enemies plays one stop. The next one can start only once the current one is over.
- **Slow areas**: an `EnvZone` whose profile has `time_scale < 1` slows the whole game while the
  player is inside it.
- **Bullet time**: the player presses V (or the gamepad's left trigger) to slow the world to 0.3
  while the player moves at full speed. V again stops it. It drains a meter shown next to the
  stamina bar, refills while off, and stops when the meter is empty. It gets its own demo bay.
- **Composable**: the three multiply. A hit inside a slow area dips below the area's speed. A hit
  in bullet time dips below 0.3.
- Menus and the GUI are not slowed. Input is never missed.
- Toggle `ahra/time/disable_hit_stop` turns off the hit-stops only. Slow areas and bullet time are
  gameplay, not comfort, so the toggle leaves them alone.
- Camera shake and camera follow run on real time.

## Non-goals

- Audio pitch or speed (the project has no audio yet; `AudioServer.playback_speed_scale` is the
  hook later).
- Hit-stop from anything other than player melee, player shots and the player being hurt (thrown
  weights, hazards, enemies hurting each other).
- Bullet time as a progression stat (`StatMods`). Its numbers are plain Player exports for now.
- Slow areas that slow only what is inside them. The area slows the whole game while the player is
  in it.
- Saving any of it. A hit-stop or bullet time doesn't survive a scene change.
- A pause menu. None exists yet; this design only makes sure one won't be slowed.

## Anti-goals

- Lost input: a press during a slow-down must still register.
- Stuck slow motion: after a scene change, a pause, or the player's death, the game is back at
  full speed (or at the new area's speed).
- Stacked stops: two stops back to back from one attack, or a stop that never ends because hits
  keep extending it.
- A slowed GUI: a fade or a future menu dragging because a hit landed just before it opened.
- The camera lagging behind a full-speed player in bullet time, or the hurt shake stretched into a
  slow wobble.

## Constraints (found in Godot 4.7.2, probed headless)

- `Engine.time_scale` is the only knob that slows everything at once: Jolt bodies (weights),
  `World.time` (so platforms stay a function of the clock and in sync), enemies, NPCs, tweens and
  timers.
- At `time_scale` 0.1, physics still ticks 60 times per real second, each tick with delta 1/600.
  So `Input.is_action_just_pressed` in `_physics_process` never misses a press.
- Tweens with `set_ignore_time_scale(true)` and timers made with `ignore_time_scale` run on real
  time.
- `SceneTree.process_frame` still fires while the tree is paused.
- `move_and_slide` always moves by the engine's (scaled) physics step, whatever the script's
  `delta` says.
- `SlowMo` must not reference the `World` autoload. Player, Enemy and Projectile call it, and `-s`
  tests compile them before autoloads exist. Same rule as CameraShake.

## Approaches

**Hit-stop**
- **A. `Engine.time_scale` (picked).** One global knob slows physics, the clock, animation and
  tweens together. GUI opts out per tween.
- **B. A game clock every system multiplies by.** Jolt rigid bodies can't be slowed this way
  without scaling their velocities and gravity by hand. Rejected.
- **C. Pausing the tree (freeze frames).** It freezes instead of slowing, stops input handling in
  paused nodes, and can't compose with longer slow motion. Rejected.

**Longer slow motion**: chosen in conversation, B of these:
- A. Only a connection point (a sustained factor stuck at 1 for now). Smallest, but the
  composition is never tested.
- **B. Slow areas through `EnvProfile.time_scale` (picked)**, the existing home for "while the
  player is in this place", blended like the other env fields.
- C. B plus a timed hold API for an ability. Bullet time now covers the ability case, through its
  own factor.

**Bullet time**: one sensible way. The world slows through `Engine.time_scale`, and the player
divides the bullet factor out of its own clock. Slowing each system by hand fails for the same
reason as hit-stop B. A separate physics world for the player would break its collisions with
everything. Its limit was chosen in conversation: **a meter** (toggle on V, drains, refills while
off), over a fixed burst with a cooldown or holding V.

## Design

### `SlowMo` (`world/slow_mo.gd`)

A static-only class, like CameraShake. It owns the three factors and returns the time scale.

```gdscript
enum Feel { SHOT, HIT, HURT, KILL } ## later = stronger (same-frame tie-break)
const DISABLE := "ahra/time/disable_hit_stop"
const MIN_SCALE := 0.02

static var area := 1.0          ## the player's env time_scale, set by GameArea every frame
static var bullet_target := 1.0 ## set by the Player: bullet_scale while on, 1 while off
static var bullet := 1.0        ## bullet factor inside the last returned scale (1 while paused)
static var real_delta := 0.0    ## the last update's unscaled frame time
static var stops := 0           ## hit-stops started (tests read it)

static func add(feel: Feel) -> void
static func update(real_dt: float, paused: bool) -> float ## the next Engine.time_scale
static func clear() -> void
```

- **Feels** are a preset table in code. Each feel slows the world to `speed`, holds it for `hold`
  seconds, then eases back to 1 over `ramp` seconds (smoothstep). All of these are real seconds,
  whatever the other factors are doing. Starting values, to be tuned by playing:

  | Feel | Used by                                          | speed | hold   | ramp   |
  |------|--------------------------------------------------|-------|--------|--------|
  | SHOT | a player shot hits an enemy                      | 0.3   | 0.04 s | 0.04 s |
  | HIT  | a melee swing lands (any number of enemies)      | 0.12  | 0.07 s | 0.05 s |
  | HURT | the player is hurt                               | 0.08  | 0.10 s | 0.08 s |
  | KILL | a player attack kills an enemy, or the player dies | 0.05 | 0.14 s | 0.10 s |

- **`add(feel)`**: does nothing when the toggle is on. While a stop runs, the new one is dropped,
  with one exception: if the running stop started in this same physics frame
  (`Engine.get_physics_frames()` stamp) and the new feel is stronger (later in the enum), the new
  one replaces it. So a hit and a hurt in one frame play the stronger. A stop is over at
  `age >= hold + ramp`, and only then can the next one start. `stops += 1` on each start.
- **`update(real_dt, paused)`**:
  - While paused, it returns 1.0, doesn't age the stop, and sets `bullet = 1`. A pause menu is
    never slowed, and the stop resumes after unpausing.
  - Otherwise it ages the stop by `real_dt` and eases the bullet factor toward `bullet_target`
    (about 0.15 s from full speed to 0.3).
  - It returns `max(MIN_SCALE, stop_factor × area × bullet)`, and stores `bullet` and
    `real_delta`.
- **`clear()`**: no stop, `area` = 1, bullet target and level = 1. GameArea calls it on load.

### The driver (`World`)

`World._ready` connects `get_tree().process_frame` to a method that measures real time
(`Time.get_ticks_usec()`, clamped to 0.1 s so a load hitch doesn't skip ahead) and sets
`Engine.time_scale = SlowMo.update(real, get_tree().paused)`. The signal fires while paused, so
World keeps its pausable process mode and `World.time` still stops with the tree.

Ordering: the engine computes each frame's steps from the scale set in the previous
`process_frame`, and the player's physics in that frame reads the `SlowMo.bullet` stored at the
same time. So the player always divides by the factor the engine actually used, including the
frame after an unpause.

`World.debug_text()` adds a line such as `time ×0.30`.

### Hooks

1. **Player hurt**: `Player.damage`, next to the JOLT shake, after the guards (i-frames don't
   stop again): `SlowMo.add(KILL if the hit kills else HURT)`. Enemy attacks, enemy projectiles
   and debug key 1 all go through `damage`.
2. **Melee**: `Player.melee_hit()`, after its loop: if `landed > 0`, `SlowMo.add(KILL if any hit
   enemy is now in state death else HIT)`. It runs once per swing, so two enemies give one stop.
3. **Shots**: `Projectile._finish`, enemy branch, only when `source is Player` and the hit
   landed: `SlowMo.add(KILL if the enemy died else SHOT)`. Shots at energy switches don't stop.

### Slow areas (`EnvProfile`)

- A new export, `@export_range(0.05, 1.0) var time_scale := 1.0`, in a "Time" group. `combine`
  multiplies it (like `gravity_mult`), so two overlapping 0.5 zones give 0.25.
- GameArea's `_process` sets `SlowMo.area = player.env.time_scale` (1 when there is no env), next
  to where it reads `player.env.shake`. An enemy's own env ignores it.

### Bullet time (Player)

- Input action `bullet_time`: V (physical keycode) and the joypad left trigger (axis 4).
- Exports, group "Bullet time":
  - `bullet_capacity := 4.0`: meter capacity, in player seconds.
  - `bullet_refill := 0.5`: meter seconds regained per second while off (empty to full in 8 s).
  - `bullet_scale := 0.3`: world speed while on.
  - `bullet_min := 0.5`: the meter needed to start, so an empty meter doesn't flicker it on and
    off.
- State: `bullet_meter`, `bullet_on`. A plain flag, not a PlayerState: it's orthogonal to
  movement.
- In `_physics_process`:
  - **First line:** `delta /= SlowMo.bullet`. Every state, cooldown, buffer, stamina tick and
    `_animate` then runs on the player's clock (hit-stops and areas still slow it, bullet time
    doesn't).
  - **Toggle:** on `just_pressed`, flip `bullet_on` (start only if `bullet_meter >= bullet_min`
    and not in death or puppet).
  - **Meter:** while on, `bullet_meter -= delta`. At 0 it turns off. While off it refills.
  - **Auto-off:** `bullet_on` turns off whenever the state is death or puppet (cutscenes and
    locked talks).
  - **Target:** `SlowMo.bullet_target = bullet_scale if bullet_on else 1.0`.
- **`slide()`**: a new helper that does `velocity /= SlowMo.bullet`, `move_and_slide()`, then
  `velocity *= SlowMo.bullet`. It replaces all 11 `move_and_slide()` calls in `player/`. No caller
  uses the return value.
- **Platform carry**: `floor_velocity` is in world time. Where the jump state inherits it
  (`p.carry`, and the up part), multiply by `SlowMo.bullet`. Otherwise a jump off a slowed
  platform in bullet time would fling the player 1 / 0.3 too far.
- A carried weight is already placed by the player each tick, so it keeps up. A thrown weight
  flies on world time.
- The death respawn starts with bullet time off. A new scene gets a fresh Player and
  `SlowMo.clear()`.
- **Gauge**: `player.tscn` gets a third ProgressBar next to Stamina and Oxygen (a distinct tint).
  `gauges.gd` shows it while not full or while on.
- `Player.debug_text()` shows the meter, e.g. `bullet 2.4 / 4.0 s (on)`.
- `GameArea.HELP` gets `V bullet time`.

### Real-time camera and GUI

- `GameArea._process` uses `SlowMo.real_delta` for the camera follow lerp and for
  `CameraShake.update` (not `delta`, and not `delta / Engine.time_scale`, which is wrong in a frame
  where the scale just changed). The JOLT plays at full speed during a hit-stop, and the camera
  keeps up with a full-speed player.
- `World.fade`'s tween gets `set_ignore_time_scale(true)`.
- Rule for future GUI (a line in CLAUDE.md): a menu pauses the tree (and the scale becomes 1 on its
  own). GUI that animates while the game runs uses real time (`set_ignore_time_scale`, or timers
  with `ignore_time_scale`).
- The HUD label and gauges don't use delta, so they're unaffected.

### Toggle (`project.godot`, `[ahra]`)

`time/disable_hit_stop=false`, read in `add` (a running stop finishes).

## Demo

A new scene, `demo/slowmo/slowmo.tscn`, a GameArea with its own script `slowmo.gd`. Its help text
covers V and key 9 (hit-stop toggle on/off, like the shake demo's keys). Bays:

- **Hits:** a few runners and a brute to melee and shoot. Key 1 shows HURT.
- **Slow area:** a tinted EnvZone with `time_scale` 0.4 over a platform doing round trips, and a
  Dispenser dropping balls through it. Walking in slows everything, the player included.
- **Bullet time:** runners that charge, two crushers like the shake demo's, and a Dispenser
  spilling balls down a slope. Press V and walk through.

## Tests

`tests/slowmo_test.gd` (`-s`, sections by name), last line `SLOWMO: OK`:

- **rules**, calling `update` with explicit deltas:
  - A stop starts and is over after `hold + ramp` real seconds, also while `area` is 0.5.
  - A second `add` during a stop is dropped (`stops` unchanged).
  - A stronger `add` in the same physics frame replaces the first.
  - The scale = stop factor × area × bullet, never below `MIN_SCALE`.
  - The toggle on: `add` does nothing, and the area still slows.
  - Paused: the scale is 1 and the stop doesn't age. `clear()` resets everything.
- **hits:**
  - One melee swing into two runners: `stops` +1 exactly, and the scale goes below 1 and back to 1.
  - A killing swing uses KILL.
  - `damage` uses HURT.
  - A player shot hitting an enemy uses SHOT. An enemy shot or an energy switch adds no SHOT.
  - A jump pressed during a stop still sets the jump buffer.
- **area:**
  - In a 0.5 zone (built in code), `World.time` advances half as much per physics tick, and the
    player covers half the distance per tick.
  - Two overlapping zones give 0.25. Leaving restores 1.
- **bullet:**
  - V: after the ease, `World.time` advances about 0.3× per tick while the player walks the same
    distance per tick as without bullet time.
  - The meter drains, and an empty meter turns it off. V again turns it off, and it refills.
  - It won't start below `bullet_min`.
  - Death and puppet turn it off.
  - A carried weight stays at the hold point.
  - A hit-stop during bullet time gives about 0.3 × the stop's speed.
- **demo:** `demo/slowmo/slowmo.tscn` loads and runs without errors, with its three bays.

The suites that land hits or call `damage` (`enemy_test`, `shake_test`, `smoke_test`,
`switch_test`) set `ahra/time/disable_hit_stop` to true at start. They count physics frames, and
a stop would change how much game time those frames cover. All existing suites still pass.

These check logic only. How it feels is tuned by playing the demo, which the tests don't cover.
CLAUDE.md: add the suite to the test list, a Slow motion paragraph to Architecture, and the GUI
rule.

## Left to the builder

- The preset numbers, the bullet-time ease and the meter defaults.
- The demo layout and the gauge tint.
- Whether `SlowMo` extends `Object` or `RefCounted` (static-only either way).
- Checking in the windowed demo whether shader `TIME` (wind, water) follows the slow-down. If it
  doesn't and it reads wrong, a `game_time` global shader uniform is the fix (note it, don't build
  it unasked).

## Known ceilings (`ponytail:` comments)

- Pushing a weight in bullet time: `WeightBody.push_from` sets the weight's speed on world time, so
  the player outpaces the box it pushes.
- Enemy and NPC timers are all world time. Nothing in the world can opt out of bullet time.

## Calls made in this design (not discussed)

- Hit-stops are dropped while one runs, not queued. One exception: a stronger feel in the same
  physics frame replaces the running one.
- Feel order (SHOT < HIT < HURT < KILL) decides that tie. A player death uses KILL.
- The three factors multiply, with a 0.02 floor.
- Hit-stop lengths are in real seconds. The meter drains on the player's clock (so a slow area or a
  hit-stop drains it more slowly).
- Bullet time: the world at 0.3, a 4 s meter refilling in 8 s, 0.5 s needed to start, an ease of
  about 0.15 s, keys V and the left trigger.
- Shots fly at world speed once fired, and thrown weights fly on world time.
- Bullet time ends on death, cutscenes and locked talks, and scene changes.
- The toggle only covers hit-stops.
- The driver lives in World on `process_frame`. Pausing gives scale 1.
- The camera follow joins the shake on real time.
- A slow area slows the whole game while the player is inside it.
- The demo is a new scene with three bays, like `demo/shake/`. Docs go in CLAUDE.md, not a
  separate guide.
