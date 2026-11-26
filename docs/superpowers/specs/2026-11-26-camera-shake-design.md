# Camera shake — design

**Status:** draft 2026-11-26, waiting for approval.

## Why

Feedback and weight. The player should feel being hit; a stormy place should feel violent; heavy
things (a big enemy walking, a looping crusher trap) should feel heavy. It is one effect with one
entry point, so later triggers hook up in a line. It layers on top of whatever else the camera does
(the follow today, a zoom or move later). Like `ahra/animation/disable_squash_tilt`, it has global
toggles.

## Goals

- Sources today: the player taking a hit, an environment (sustained while the player is in a zone),
  a heavy enemy's footsteps, a heavy trap slamming (a crusher running in a loop).
- One public call for one-off shakes: `CameraShake.add(feel, strength, at, radius)`.
- Overlap: shakes add up, each extra one reduced (rule below), never past a cap, and each keeps its
  own feel, so a footstep in a storm still reads as a footstep.
- Two kinds of motion: **slide** (the view shifts sideways / up-down) and **tilt** (a small roll of
  the horizon), each toggled on its own: slide on, tilt off by default. A master switch turns
  everything off.
- Composable: the shake never moves where the camera rests and never fights the follow or a future
  zoom / move.

## Non-goals

- Controller rumble, sound, VFX (the `step` cue added here is where footstep sounds would hook).
- Bigger enemy bodies: the heavy demo enemy is the normal 1.6 m capsule (`Enemy.HALF_HEIGHT`
  ponytail).
- An options menu: toggles are project settings, which code can flip at runtime.
- Saving shake state (presentation only; cleared per area).
- Shake from NPCs, fall landings, or platforms in general (only those given a slam strength).

## Anti-goals

- Messy stacking: five shakes at once must not read as chaos.
- Camera drift: after a shake the camera is exactly where the follow put it.
- Gameplay wobble: tilt must not bend camera-relative movement.
- False shakes: none on area load or after a `World.time` skip.

## Constraints

- `GameArea._process` lerps `cam.global_position` from its current value, so a shake written into
  the position would feed back into the follow: the shake needs its own layer.
- `CameraShake` must not reference the `World` autoload (Enemy, MovingPlatform and `-s` tests
  compile it before autoloads exist).
- The camera is a perspective camera, 10° FOV, about 5.7 × `size` away, updated in `_process`, physics
  interpolation off. `Player.cam_basis()` reads its basis for camera-relative input.
- Area scenes keep a plain `Camera` child: no scene restructuring.

## Approaches

- **A. One shared level** (one number every source raises, decaying; one noise drives the motion).
  Smallest, but every source looks the same. Rejected: sources can't be told apart.
- **B. Layered shakes, each with its own feel (picked).** Each trigger adds a short-lived layer with
  its own strength, length and motion; layers are summed with a diminishing rule. About twice A's
  code.
- **C. A camera addon** (Phantom Camera noise emitters). It takes over the camera follow GameArea
  already does, and adds a dependency. Dropped.

## Design

### `CameraShake` (`world/camera_shake.gd`)

A static-only class. State: the active layers, the sustained level, the last focus point and the
last applied roll.

```gdscript
enum Feel { JOLT, THUMP, SLAM, SWAY }
static func add(feel: Feel, strength: float, at: Variant = null, radius := 0.0) -> void
static func update(delta: float, focus: Vector3, sustained: float) -> Vector3 ## x, y: slide (fraction of view height), z: roll (radians)
static func steady(b: Basis) -> Basis ## b with the last applied roll taken out
static func clear() -> void
```

- `strength` is 0..1 (clamped). `at` is the world point the shake comes from; with it, strength
  falls off linearly to 0 at `radius` from the last focus point (the player); `radius` 0 means the
  feel's default radius. `at == null`: felt everywhere. A shake that arrives weaker than ~0.02 adds
  no layer (far footsteps cost nothing).
- **Feels** are a preset table in code (one place to tune; a new feel is a new row). Starting values,
  to be tuned by playing:

  | Feel  | Used by        | Motion                                              | Length    | Default radius |
  |-------|----------------|-----------------------------------------------------|-----------|----------------|
  | JOLT  | player hit     | sharp jitter on all axes, fast decay                | 0.3 s     | — (global)     |
  | THUMP | footsteps      | one downward dip and back, a little jitter          | 0.2 s     | 14 m           |
  | SLAM  | crusher        | a deep downward dip, then a rattling tail           | 0.6 s     | 18 m           |
  | SWAY  | environment    | slow wandering on x / y and roll, never ends        | sustained | — (global)     |

  Smooth jitter comes from Godot's built-in `FastNoiseLite`, each layer reading it at its own seed.
- A layer's **intensity** now = strength × its envelope at its age; its **motion** = intensity × its
  feel's unit motion (x, y, roll).
- **Sustained layer:** one SWAY layer whose strength eases (~0.5 s) toward `sustained`, so entering
  or leaving a storm doesn't pop.
- **Overlap rule:** each frame, sort layers by intensity, strongest first. Layer k's motion is
  scaled by what the stronger ones left: `scale_k = Π_{j<k} (1 − i_j)`. The strongest plays in full,
  every extra one adds less, and the total intensity `1 − Π(1 − i)` never passes 1. Two shakes of
  0.5 give 0.75, three give 0.875; a storm of 0.3 plus a footstep of 0.2 gives 0.44.
- **Output:** slide = combined (x, y) × `MAX_SLIDE` (fraction of the view height, ~0.025); roll =
  combined roll × `MAX_TILT` (~1.5°). Toggles apply here, read every call: master off, or slide
  off, zeroes the slide; tilt off zeroes the roll. Layers keep ageing while off.
- At most 8 layers; when full, the weakest is replaced (`ponytail:` comment).

### Applying it (`GameArea`)

In `_process`, after the follow:

- `var s := CameraShake.update(delta, player position, player.env.shake)`.
- View height at the player, from the camera's live `fov` and its distance to the player. The shake
  then reads the same at any zoom.
- **Slide:** `cam.h_offset = s.x × view height`, `cam.v_offset = s.y × view height`. These are
  Godot's built-in view shift: the camera node doesn't move, so the follow and any future move or
  zoom code never meet the shake.
- **Tilt:** `cam.global_basis = _steady_basis * Basis(Vector3.BACK, s.z)`, where `_steady_basis`
  is the iso rotation set in `_ready`. `ponytail:` future code that rotates the camera sets
  `_steady_basis`, not the camera.
- `_ready` calls `CameraShake.clear()`: nothing carries across a scene change.
- `Player.cam_basis()` returns `CameraShake.steady(cam.global_basis)`, so movement never tilts.
- The gauges (`unproject_position`) shake with the world, as they should; the HUD label doesn't.

### Sources

1. **Player hit:** in `Player.damage`, after the guards (i-frames don't shake again) and before
   the death branch (a killing hit shakes too): `CameraShake.add(JOLT, clampf(0.3 + amount /
   max_hp(), 0.3, 1.0))`. Enemy attacks, projectiles and debug key 1 all go through `damage`.
2. **Environment:** `EnvProfile.shake` (0..1). `combine` merges overlapping zones by the same rule
   (`1 − Π(1 − s)`). GameArea reads `player.env.shake` each frame. Enemies' env ignores it.
3. **Heavy enemy footsteps:** Enemy exports (group "Shake"): `step_shake := 0.0` (0 = none) and
   `stride := 1.4` m. While on the floor, the enemy adds up how far it moved along the floor; every
   `stride` it emits `cue(&"step")` and, if `step_shake > 0`, calls `CameraShake.add(THUMP,
   step_shake, global_position)`. This is independent of the placeholder animation and its toggle.
4. **Heavy trap (crusher):** MovingPlatform exports (group "Slam"): `slam_shake := 0.0` (0 = none)
   and `slam_speed := 5.0` m/s. At runtime, each physics frame the platform measures its speed from
   its position change. A frame where it was moving at least `slam_speed` and is now nearly stopped
   (< ¼ of it) is a slam: `CameraShake.add(SLAM, slam_shake, global_position)`. A crusher is then
   built from existing tracks: one sequence one-way down fast, one one-way up slow, `after_last`
   start over. Only the fast stroke stops hard enough. A circuit corner keeps its speed, so it
   isn't a stop. Guards: no detection during `_warmup` or on the first frame after it; a frame
   faster than 100 m/s is a teleport (clock skip), and resets the measurement (`ponytail:`).
   Platform copies (`platforms` > 1) each slam. Doors extend MovingPlatform and call `super`, so a
   door given a slam strength thuds when it shuts fast (a bonus, not tested).

### Toggles (`project.godot`, `[ahra]`)

- `camera/disable_shake=false`: the master switch, the same polarity as
  `animation/disable_squash_tilt`.
- `camera/shake_slide=true`
- `camera/shake_tilt=false`

### Hooking up future triggers

Any signal: `thing.some_signal.connect(func(_a): CameraShake.add(CameraShake.Feel.SLAM, 0.6,
thing.global_position))`. Anything continuous: an EnvZone whose profile has `shake` (an earthquake
is a big zone). A new kind of motion is a new row in the feel table. CLAUDE.md gets a paragraph
saying this.

## Demo

A new scene, `demo/shake/shake.tscn` (a GameArea, with its own script for help text and the keys
9 = slide on/off, 0 = tilt on/off, - = master on/off), with bays:

- **Storm:** an EnvZone with shake 0.3 and a light wind.
- **Brute:** `enemy/brute/brute.tscn`, inherited from `enemy/enemy.tscn`, exports only (like the
  runner): slow, heavy (weight 40, health 150), `step_shake` 0.35, `stride` 1.6, dark colour. It
  chases and attacks, so it covers footsteps and hits.
- **Crushers:** two crushers side by side, out of phase (fast down at 12 m/s with a 0.5 s end
  wait; up at 2 m/s with a 1 s end wait; start over; `slam_shake` 0.6). Standing between them shows
  overlap; walking away shows falloff.
- Key 1 (damage) already works in every area.

## Tests

`tests/shake_test.gd` (`-s`, sections by name like the enemy suite), last line `SHAKE: OK`:

- **rule:** two equal shakes ≈ `1 − (1 − a)²`; many shakes never pass 1; `at` beyond `radius` adds
  nothing; master off → zero output; slide off → zero slide; tilt off (default) → zero roll; tilt
  on → roll.
- **hit:** `damage` adds a JOLT layer; a second hit during i-frames adds none.
- **env:** in a shake zone the sustained level rises, and after leaving it eases back to 0.
- **steps:** walking a brute N m gives about N / stride `step` cues and layers near the player;
  with `step_shake` 0, no layers.
- **slam:** one crusher cycle gives exactly one slam (the down stroke), none on the slow rise, none
  on area load, none after a `World.time` skip (player placed elsewhere first, per the gotcha).
- **camera:** during a shake the camera's `global_position` matches the follow exactly (the shake
  lives in the offsets); with tilt on, `Player.cam_basis()` equals the steady basis.

These check logic only. How it feels is tuned by playing the demo, which the tests don't cover.
CLAUDE.md: add the suite to the test list, and a Camera shake paragraph to Architecture.

## Left to the builder

- The preset numbers, envelope curves and noise setup.
- Thresholds (minimum layer strength, "stopped" factor, teleport speed).
- The demo layout.
- Whether `CameraShake` extends `Object` or `RefCounted` (static-only either way).

## Calls made in this design (not discussed)

- The master toggle is named `disable_shake`, matching the animation toggle's polarity; slide and
  tilt are named for what they turn on.
- Feels are code presets, not inspector resources.
- Falloff is linear, with a default radius per feel, measured from the player.
- Overlapping environment zones merge by the same rule as overlapping shakes.
- Slams are found from the platform's own speed drop, not from the track's timing.
- Platforms get no `cue` signal (Door already declares its own).
- Movement reads the steady (untilted) camera basis.
- Demo: a new scene with a brute enemy type; docs as a CLAUDE.md paragraph, not a separate guide.
