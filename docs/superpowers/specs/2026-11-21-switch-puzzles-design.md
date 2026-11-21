# Switch puzzles design: weight plates, energy switches, doors, carriable weights

Date: 2026-11-21. Status: approved by the user 2026-11-21.

## Intent

AHRA needs puzzles where the player **moves things around to open the way forward**. This work
builds the backbone: **switches** that must all be on for a **door** to open. Most switches are
**weight plates**, pressed by anything that stands on them: the player, an enemy, an NPC, or a
**weight** (a box or a ball) that characters push by walking into it and that the player can pick
up, carry, put down and throw. A **dispenser** keeps a puzzle supplied with weights, replacing
the ones that fall or get destroyed, until the puzzle is solved. An **energy switch** is charged
by the player's ranged shot: it opens its door at once, and the door slides shut as the energy
runs out, slower for each extra shot.

Puzzles also use the **gravity zones**: enemies, NPCs and weights enter and leave changed gravity
through the same trigger zones as the player, so a weight can fall onto a plate on a ceiling or a
wall.

Weights have **weight**, like enemies: heavy ones are hard to push, move slowly and drain the
player's stamina while carried. That is the point of the stat: objects should feel heavy.

Like platforms, a door's switches **may sit in other areas**: the wiring is a channel name, and
all state lives in `World`, so it survives scene changes and is ready to be saved.

## Goals

- **Weight plates**, two modes:
  - **Hold**: on only while something rests on it.
  - **Latch**: springs back up when released, until **every switch on its channel is on at the
    same moment**; then all the channel's latch plates **lock** down for good.
- **What presses a plate**: the player, enemies, NPCs and weights resting on its face, whichever
  way gravity points (a ceiling plate is pressed by something that fell up onto it). One body is
  enough: no weight thresholds.
- **Energy switch**: hit by the player's ranged shot. Each shot adds `time_to_close` seconds of
  energy, up to `time_to_close × max_shots` (x2, x3...). The door opens at once and slides shut
  over the energy left.
- **Doors** open when every switch on their channel is on. Several doors may share a channel.
  A door closing on a body pushes it out of the doorway, to the nearer side (no crush deaths).
- **Cross-area wiring**: a door's switches may be in other areas, including areas not visited
  yet (the door still counts them, as off).
- **Weights** (box, ball): rigid bodies with a `weight`. Anyone walking into one pushes it; the
  heavier it is the slower it moves and the more it holds the pusher back. Balls roll.
- **Carrying** (player only): a `carry` key (R) picks up and puts down; a `throw` key (T) throws.
  Carrying drains stamina (faster when heavier), slows walking, and disables run, dash, grab
  (swing, climb), melee and shoot. The player **drops** what they carry when hurt, dying,
  entering deep water or running out of stamina.
- **Dispenser**: keeps `count` weights of its scene in play. A weight that is destroyed (kill
  zone, out of the area's bounds) is replaced after a delay. It stops for good once its channel
  is **solved** (all its switches are latch plates, locked). Other channels are never solved.
- **Gravity for everyone**: `GravityZone` sets the gravity of enemies, NPCs and weights, sticky
  like the player's (it stays until another zone changes it).
- **Memory**: plate states, locks, energy and weights' positions survive scene changes, so a box
  left on a hold plate in area A still holds a door open in area B, and is still on the plate
  when the player returns.
- Demo areas, a test suite, a guide (`docs/switches.md`) and the CLAUDE.md section.

## Non-goals

- Weight thresholds (heavy-only plates), plates that need N bodies. Later: one `min_weight`
  export.
- Enemies or NPCs carrying weights. They only push.
- Thrown weights hurting enemies, weights breaking under attacks, weights in water (floating,
  sinking) or affected by `EnvZone`s (wind, ice). Only gravity zones, kill zones and the area
  bounds reach weights.
- Swinging or rotating doors; doors only slide.
- Switches driving moving platforms (a plate powering a lift). The channel namespace is shared,
  so it can come later.
- Real meshes, animation or audio. Placeholders plus presentation hooks (`cue`, state fields).
- A dedicated editor plugin (placement menus, wire drawing). Pieces are placed as scenes; only
  the `channel` picker and the switch registry come from Platform Tools.
- A save system: the new `World` data is plain and joins the save list.

## Anti-goals (failure even if it "works")

- **Soft locks**: a puzzle left unsolvable because its weights are gone or stuck. The dispenser
  covers destroyed ones; carrying covers stuck ones.
- **A door opening early** because it doesn't know about a switch in an area not loaded yet.
- **Load flicker**: plates reading "released" for a frame while an area loads, closing a door or
  breaking an all-on moment.
- **Forgetting**: a lock undone, or a weight back at its dispenser, after a reload.
- **Crushing or trapping** a character in a closing door.
- **Carry exploits**: carrying through dash, swing or climb; a carried weight pressing plates or
  shoving things while held.

## Constraints

- Godot 4.7.2, GDScript, Jolt, physics interpolation on (`reset_physics_interpolation()` after
  any teleport), static typing, `##` docs, `.uid` sidecars kept with scripts.
- **Gravity can point anywhere**: use `up_direction` / `gravity_dir`, never `Vector3.UP` or
  `velocity.y`.
- **`-s` test compile order**: `Player`, `Enemy`, `Zone` and `Projectile` are compiled before
  autoloads exist, so they must not statically reference classes that use `World`. New pieces
  that use `World` (`WeightPlate`, `EnergySwitch`, `Door`, `Dispenser`) and `Npc` are reached by
  group or `has_method` from those scripts. `WeightBody` must not use `World` (like `Enemy`), so
  that `Player` and `Zone` can type it.
- `@tool` scripts create child nodes in `_ready` and guard runtime logic with
  `Engine.is_editor_hint()`.
- Don't touch the user's scenes (`demo/builder/`) or the editor layout. Existing demo scenes keep
  working unchanged.
- Fit the project's patterns: triggers are `Zone`s, bodies take shapes through `ShapeSet`,
  presentation reads state plus a `cue(name)` signal, channel names go through `Channels.key`.

## Approaches considered

**Wiring** (how a door knows its switches):

1. **The door lists its switches** (`switches: Array[Node]` picked in the inspector). Smallest
   and easiest to read, but a door and its switches must share an area.
2. **Channels, like platforms (picked by the user).** Switches and doors name a channel
   (`Channels.key`, the existing channel picker), `World` stores each switch's state. Wiring
   crosses areas, and state is already in `World`. Cost: a door can't see switches in areas not
   loaded, so the editor writes a **switch registry** (below).
3. Dropped: **doors as moving platforms** (a `PlatformTrackInstance` driven by `World.toggle` /
   `run`). The motion would be free, but "all switches on", latching and draining energy have no
   place in the channel model.

The user picked 2 because some of a door's switches may be in another area, as with platforms.

**Several latch plates**: (a) each locks the moment it is pressed, or (b) they spring back until
all are pressed at once, then lock together. The user picked (b): weights get a real job in
every multi-plate puzzle.

**Moving weights**: (a) push only, a melee hit breaks a weight so the dispenser replaces it;
(b) push and pull; (c) carry. The user picked (c) **plus** pushing by walking into weights, with
weight scaling both.

**Weights' physics**: `RigidBody3D` (picked, my call): Jolt gives rolling balls, tumbling and
stacking for free. A `CharacterBody3D` block would push more predictably (Sokoban feel) but
balls would have to fake rolling.

## Design

### Files

| Path | What |
|------|------|
| `puzzle/weight_plate.gd` | `WeightPlate` (`@tool`, extends `Zone`): hold / latch plate |
| `puzzle/energy_switch.gd`, `.tscn` | `EnergySwitch` (`@tool`, `StaticBody3D`): charged by shots |
| `puzzle/door.gd`, `.tscn` | `Door` (`@tool`, `AnimatableBody3D`): slides open |
| `puzzle/weight_body.gd` | `WeightBody` (`RigidBody3D`): weights; never uses `World` |
| `puzzle/box.tscn`, `puzzle/ball.tscn` | weight scenes (box: weight 12, ball: weight 4) |
| `puzzle/dispenser.gd` | `Dispenser` (`@tool`, `Node3D`) |
| `puzzle/switch_registry.gd` | `SwitchRegistry` resource class; `world/switch_registry.tres` the baked data |
| `world/world.gd` | + `switches`, `bodies`, switch helpers (below) |
| `world/zone.gd` | + NPC and weight hooks |
| `world/gravity_zone.gd` | sets any entering body's gravity |
| `world/kill_zone.gd` | destroys weights |
| `world/area.gd` | weights out of bounds; saves and restores weights |
| `world/projectile.gd` | charges what it hits (`shot()`) |
| `player/player.gd` (+ states) | carry, put down, throw, pushing, drops |
| `enemy/enemy.gd` | `set_gravity_dir`, pushing |
| `npc/npc.gd` | own gravity, `set_gravity_dir`, gravity in memory, pushing |
| `addons/platform_tools/` | channel picker on the new nodes; registry bake on scene save |
| `project.godot` | `carry` (R) and `throw` (T) actions |
| `demo/switches/switches_a.tscn`, `switches_b.tscn` (+ `.gd`) | demo areas |
| `tests/switch_test.gd` | runtime suite (`SWITCHES: OK`), with sections |
| `docs/switches.md`, `CLAUDE.md` | guide, architecture section, suite line |

The `puzzle/` folder mirrors `enemy/` and `npc/`. Names and folder are the builder's to adjust.

### World: switch state

```gdscript
## Switch state per placement: Channels.id(switch) -> {on = bool, locked = bool} for plates,
## {shot_at = float, end = float} for energy switches. Saved with the rest.
var switches := {}
## Weights' memory per placement (see Memory): Channels.id(...) -> state. Saved with the rest.
var bodies := {}
func press(channel: StringName, id: String, on: bool)   # a plate's state changed
func charge(channel: StringName, id: String, add: float, cap: float)  # a shot landed
func switch_on(id: String) -> bool       # plate: on or locked; energy: time < end
func openness(channel: StringName) -> float  # 0..1, what doors on the channel show
func solved(channel: StringName) -> bool  # every switch on it is a locked latch plate
```

- **Solved** means the doors are open for good: the channel's switches are all latch plates, all
  locked. A channel with any hold plate or energy switch is never solved, even after its latch
  plates lock (its doors still need the hold plates held), so its dispensers never stop: a
  weight lost after the lock is still replaced (no soft lock).

- A channel's switches = the **registry's** list for that key, plus any switch on that channel in
  the loaded scene (group `&"door_switch"`), so scenes built in code (tests) work without a bake.
- **Lock rule**: after every `press` or `charge`, if every switch on the channel is on, every
  latch plate on the channel (loaded or not) gets `locked = true`. Energy running out can't
  create an all-on moment, so checking on writes is enough.
- **`openness`**: 0 if any switch is off. Else the smallest energy fraction among the channel's
  energy switches, `(end - time) / (end - shot_at)`, or 1 if it has none. Because energy is stored
  as times, a door is right even when its switch's area isn't loaded or the clock skipped.
- An unvisited switch has no entry: off.

### Switch registry (cross-area counting)

A door must count switches in areas never loaded, so the switches of every saved scene are baked
into `world/switch_registry.tres` (`SwitchRegistry`: channel key -> `[[switch id, kind], ...]`,
kind = hold / latch / energy). The Platform Tools plugin rebuilds it on every scene save
(`EditorPlugin.scene_saved`) and when the editor starts, from the same `.tscn` scan
`channel_registry.gd` already does (`keys_in`): it adds node paths, area name and which script
the node uses. Rebuilt from all scenes every time, it never needs cleaning up. A `.tres`, not
JSON, so export includes it.

The new nodes' `channel` fields use the existing picker (`channel_property.gd`), and their
channels show in it. Platform and switch channels share one namespace (one name means one thing
in an area); they never affect each other.

### Weight plate (`WeightPlate`, extends `Zone`)

```gdscript
enum Mode { HOLD, LATCH }
@export var channel: StringName
@export var mode := Mode.HOLD
@export var on_color := Color(0.3, 1.0, 0.4, 0.5)
@export var locked_color := Color(1.0, 0.8, 0.3, 0.5)
var pressed := false   # something rests on it now
signal cue(name: StringName)  # press, release, lock
```

- Its shapes are the detection volume: a thin slab over the plate's face. Its "up" is its basis
  Y; plates on walls and ceilings are rotated plates.
- **What counts**: overlapping bodies that are the player, enemies, NPCs or weights, whose
  gravity points into the plate: `gravity_dir.dot(plate_up) < -0.7` (`-up_direction` for
  characters). A box shoved sideways against a wall plate doesn't count; a box that falls onto a
  ceiling plate under flipped gravity does. Carried weights have collision off, so never count.
- Each physics frame it reads `get_overlapping_bodies()`; on a change it calls `World.press`.
- **Warmup**: it doesn't read for the first few physics frames after `_ready` (as
  `MovingPlatform` does), while restored weights settle, and it stops writing in `_exit_tree`.
  An area unloading never releases its plates.
- Visual (placeholder): lit with `on_color` while on, `locked_color` when locked, the drawn
  slab sinks a little while pressed.

### Energy switch (`EnergySwitch`, `StaticBody3D`)

```gdscript
@export var channel: StringName
@export var time_to_close := 4.0  # seconds of energy per shot
@export var max_shots := 3        # the energy cap is time_to_close * max_shots
func shot() -> void               # called by Projectile
```

- A shot adds `time_to_close` to the energy left, capped, and sets `shot_at = now`. The door
  snaps open (over its `open_time`) and slides shut over what is left: more shots, slower slide.
- `Projectile._finish` calls `shot()` on anything that has it (`has_method`, not a type check,
  see Constraints). Only shots charge it, not melee.
- **Aim assist**: switches join group `&"aim_target"`; `Player.aim_dir()` considers that group
  next to enemies (same cone, range and line-of-sight test), so a small switch on iso terrain
  can be hit.
- Visual: an emissive core whose brightness is its energy fraction; `cue` on charge and empty.

### Door (`Door`, `AnimatableBody3D`)

```gdscript
@export var channel: StringName
@export var open_offset := Vector3(0, 3, 0)  # local slide when fully open
@export var open_time := 0.4                  # seconds to open, and to close when plates release
```

- Shapes through `ShapeSet` (solid lit mesh, like `MovingPlatform`).
- Each physics frame: target = `World.openness(channel)`. Opening moves toward it at
  `1 / open_time`. Closing follows the target exactly when the channel has energy switches (the
  slow energy slide), else at `1 / open_time`. Position = closed + `open_offset * amount`.
- On load it is placed at its current amount in `_ready`, before any physics move (no swept
  shove from closed to open).
- **Push-out**: before moving toward closed, it queries bodies overlapping its shapes at the next
  position and moves each out along the door's thinnest axis to the nearer side (a teleport by
  the overlap plus a margin, `reset_physics_interpolation`). Jolt doesn't push character bodies
  out of kinematic ones, so this is explicit.
- `cue`: open, close, locked (open for good because its channel is solved and it has no hold
  plates or energy switches).

### Weights (`WeightBody`, `RigidBody3D`)

```gdscript
@export var weight := 12.0           # mass; drives push speed, carry drain, throw distance
@export var gravity := 32.0          # same pull as the player
var gravity_dir := Vector3.DOWN
var carrier: Node3D                  # the player while carried
signal destroyed
func set_gravity_dir(dir: Vector3)   # wakes the body
func push(dir: Vector3, speed: float, strength: float)
func destroy()                       # emits destroyed, frees it
```

- **Sticky gravity**: `gravity_scale = 0`, and `constant_force = gravity_dir * gravity * mass`.
  `set_gravity_dir` updates it and wakes the body.
- **Pushing**: after `move_and_slide`, the player, enemies and NPCs call `push` on each weight in
  their slide collisions, with their planar velocity and a `push_strength` (player and NPC export;
  enemies use their `weight`). The weight's planar velocity moves toward
  `speed * clampf(strength / weight, 0.05, 1.0)` along `dir`. The pusher is blocked by the weight
  (Jolt treats it as a wall), so a heavy box naturally holds the pusher to its own slow speed.
  Friction (physics material) and linear damping rise with weight, so heavy boxes stop quickly
  and light balls roll on.
- Characters can stand on weights (stack boxes to reach a ledge).
- **Destroyed** by a `KillZone` and by leaving the area's bounds (`GameArea.bounds_radius`, the
  player's fall-death rule, which also catches weights lost upward under flipped gravity).
- Placeholder mesh through `ShapeSet` (lit, like platforms); `cue` on land (hard impact) and
  destroy.

### Carrying (player)

- New input actions `carry` (R) and `throw` (T). Gamepad bindings are the builder's call.
- `Player.held: WeightBody`, an overlay on the normal states, not a state of its own.
- **Pick up** (`carry` with nothing held): the nearest weight within `carry_reach` (1.2 m),
  within 60° of facing, from idle / walk / run (run ends), never the one the player stands on.
  Refused while exhausted.
- **While held**: the weight's collision is off and `freeze` on (kinematic), placed over the head
  along `up_direction` every physics frame. Walk speed × `1 / (1 + weight * carry_slow)`. Run,
  dash, grab (swing, climb), melee and shoot are ignored. Jump and interact work. Stamina doesn't
  regenerate and drains `carry_cost * weight / 10` per second.
- **Put down** (`carry` while holding): placed on the ground `carry_reach` in front (cast along
  gravity), gentle, no velocity. Refused (a `cue`) when there is no room.
- **Throw** (`throw` while holding): released from the hold point with velocity along facing plus
  a little up, `throw_speed * clampf(10 / weight, 0.3, 1.5)`.
- **Drop** (released in place, keeping the player's velocity) when hurt, dying, entering swim,
  going through a `SceneDoor` (the weight stays in its area), or at 0 stamina (then exhausted, as
  when running out).
- A released weight takes the player's current gravity.
- `anim`: `carry_idle`, `carry_walk`, plus `cue`s `lift`, `put_down`, `throw`.
- New player exports: `carry_reach`, `carry_cost`, `carry_slow`, `throw_speed`, `push_strength`.

### Dispenser (`Dispenser`, `Node3D`)

```gdscript
@export var channel: StringName     # stops once this channel is solved
@export var weight_scene: PackedScene
@export var count := 1
@export var respawn_delay := 2.0
```

- Keeps `count` of its weights alive. Spawned weights are its children with stable names
  (`Weight1`, `Weight2`...), so their memory ids are stable.
- A destroyed weight is replaced after `respawn_delay`, unless the channel is solved. The spawn
  point waits while it is blocked. Once solved, the weights already out stay.
- A weight spawned inside a gravity zone takes its gravity through the zone's enter signal.
- Visual: a hatch/pipe placeholder; `cue` on spawn.

### Gravity for enemies, NPCs and weights

- `GravityZone` calls `set_gravity_dir(gravity_dir)` on any entering body that has it (player,
  enemy, NPC, weight). `Zone` gets body hooks for NPCs and weights, reached by group and
  `has_method`, not by type (Constraints).
- **Enemies**: `set_gravity_dir` sets `up_direction`; their movement already splits along it.
  Climb, swing, fly and jump arcs get test coverage under flipped gravity. Enemies aren't saved,
  so a reload resets them to normal gravity.
- **NPCs**: their fall uses their own `gravity_dir` (magnitude of the project gravity) instead of
  `get_gravity()`. The visual's `Vector3.UP` is fixed. `gravity_dir` joins their memory, so a
  flipped NPC stays flipped after a reload. Marks are floor points cached at start: a walk's
  timeout snap is skipped when the NPC's gravity differs from the gravity its marks were cached
  under (no teleport from ceiling to floor).
- **Player**: unchanged (respawn still resets to down).

### Memory and area loading

- Plates write their state into `World.switches`; an area unloading leaves the last state there
  (warmup and `_exit_tree` rule above). So a hold plate in an unloaded area keeps the state it
  had when the player left.
- **Weights are remembered**: when an area unloads, every weight's position, rotation and
  gravity go into `World.bodies` by `Channels.id`; hand-placed weights that were destroyed are
  remembered as gone. Save while the weights are still in the tree (children leave the tree
  before their parent's `_exit_tree` runs, so read them earlier, e.g. on the area's
  `tree_exiting` or from `SceneDoor` before the scene change). Each `Dispenser` stores how many of its weights exist and
  their states. On load, `GameArea` restores weights before plates start reading (warmup), and
  dispensers recreate their saved weights, then top up.
- Enemies standing on a hold plate are not remembered: on return they're back home and the plate
  reads released.

### Presentation hooks

Everything visual is a placeholder. Real art reads: plate `pressed` / locked / `cue`; door
amount and `cue`; energy switch fraction and `cue`; weight `cue` (land, destroy); player `anim`
`carry_*` and carry `cue`s; dispenser `cue`. Same pattern as `Enemy` and `Npc`.

### Demo (`demo/switches/`)

Two `GameArea` scenes linked by `SceneDoor`s, with debug bays:

1. **Hold**: stand on a plate to open a door; a dispenser box keeps it down instead.
2. **Latch trio**: three latch plates, one dispenser with two boxes: player plus two boxes at
   once locks the door. A kill-zone pit beside it shows the dispenser replacing a box.
3. **Weight**: a heavy box (slow push, fast stamina drain) and a light ball (rolls away, long
   throw).
4. **Energy**: shoot the switch once, twice, three times: the door slides shut over 4, 8, 12 s;
   race through.
5. **Gravity**: throw a box into a gravity zone so it falls onto a ceiling plate; a runner and an
   NPC flip too.
6. **Lure**: a runner chases the player onto a hold plate; an NPC's routine walks over another.
7. **Cross-area**: a latch plate in `switches_b`, held by a box, plus a latch plate in
   `switches_a` lock a door in `switches_a`. Shows weight memory and the registry.

### Verification

`tests/switch_test.gd`, sections selectable after `--` like the enemy and NPC suites, last line
`SWITCHES: OK` or `N FAILED`. Covers: hold on/off; latch spring-back and all-at-once lock
(including a registry switch in an unloaded area keeping the door shut); energy stacking, cap
and slide; door push-out; dispenser refill, blocked spawn and stop when solved; carry, put down,
throw, stamina drain and drop at 0, drop when hurt; push speed by weight; gravity flips for a
weight, an enemy and an NPC, and a ceiling plate; reload memory (plates, locks, weights).
Registry bake: `platform_tools_test`. Existing suites keep passing. Game feel (push weight,
carry drag, throw arc) is untested: say so.

## Decided by the user

- Hold and latch plates; latch = all on at once, then they lock together (option b).
- Pressed by player, enemies, NPCs and weights.
- Dispenser keeps the right number of weights and stops once the puzzle is solved.
- Energy switch charged by the ranged attack, `time_to_close` × number of shots.
- Gravity zones affect enemies, NPCs and weights, entering and leaving like the player.
- Carrying with one key for pick up and put down, and its own key for throwing; pushing by
  walking into weights; weight drives push speed, friction and stamina drain.
- Dropping what you carry when hurt.
- Channel wiring (approach 2), because a door's switches can be in other areas.
- A carried weight is dropped at a `SceneDoor` and stays in its area (no carrying between areas).

## My calls (correct any)

- One body presses a plate; no weight thresholds.
- The energy switch is part of this system: on while it has energy.
- Each shot adds `time_to_close` up to the `max_shots` cap; the door snaps open, then slides shut.
- A closing door pushes bodies out of the doorway; no crushing.
- Plate locks, energy and weights' positions are remembered; enemies are not.
- Keys: R carry / put down, T throw.
- Stamina drains while carrying (not a one-off cost at pickup); no regen while carrying.
- Jump and interact work while carrying; walk speed drops with weight, jump height doesn't.
- A destroyed hand-placed weight is gone for good; only dispensers replace weights.
- "Solved" = every switch on the channel is a locked latch plate; mixed channels never stop
  their dispensers.
- The player can't lift the weight they stand on.
- `RigidBody3D` weights; doors slide only; the `puzzle/` folder.

## Left to the builder

Exact numbers (weights, drain, speeds, friction curve), the push velocity blend, the hold point
and put-down cast, how the registry scan reads script kinds, warmup frame count, placeholder
looks, gamepad bindings, the demo layout and bay numbering, the test section names, and filtering
the channel picker by kind (switch channels vs platform channels) if it helps.

## Risks

- **Jolt contact feel**: character vs rigid body pushing can jitter; boxes on moving platforms,
  standing on a box while pushing another, a carried box clipping through a low ceiling
  (collision off while held). Expect tuning.
- **Enemy moves under flipped gravity** (climb, swing, fly, solved jumps) were never exercised;
  the suite will find what breaks.
- **Registry gaps**: instanced sub-scenes aren't scanned (the same ceiling as
  `channel_registry.gd`), and scene files edited outside the editor need an editor start to
  rebake.
