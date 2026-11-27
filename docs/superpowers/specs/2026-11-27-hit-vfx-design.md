# Hit VFX (events, rule sets, particle effects): design

**Status:** draft 2026-11-27, waiting for approval.

## Why

Hits need to read. When the player, an enemy or a moving object hits something, a particle effect
plays where it happened, and which effect plays depends on the whole situation: what was done
(a shot, a cut, a slam), the state around it (the player's health and mood, the zone they're in,
the platform they stand on) and what got hit (stone, metal, wood, flesh). The player is the centre
piece and gets the richest rules. Enemies get a fixed set per type. A crusher has one effect. A
box being dragged shows the ground it scrapes over.

The gameplay code reports *events*, not effects, so audio can listen to the same events later
without touching the emitters again.

Spawning must never hitch. Today the first shot of a session can drop frames: Godot 4.4+ compiles
a scene's surface pipelines the first frame that scene is in the tree, and `projectile.tscn` is
preloaded (`player/player.gd:15`) but first instanced when the player first shoots. Later sessions
are smooth because the D3D12 driver caches pipelines on disk; "sometimes never, even the first
time" is that cache being warm already. Every particle scene would have the same problem.

## Goals

- **One call per hit site**, in the style of `CameraShake.add` / `SlowMo.add`:
  `Fx.emit(source, action, at, normal, target, extra)`.
- **Events carry tags**: the action, the source's context, and the result (what was hit). Rules
  match on tags.
- **Layered rules**: every matching rule plays its effect; a rule marked `exclusive` plays and
  stops the rules after it. Rules are ordered, so specific exclusive rules go first.
- **Rule sets live with their emitter**: a `vfx: VfxSet` export on Player, Enemy (per type scene),
  MovingPlatform and WeightBody (box and ball scenes). A set can `include` shared sets (common
  surface impacts). Swapping an effect = editing a `.tres` or changing an export.
- **The thing hit reacts on its own**: a shot hitting an enemy is two events, the player's
  `shot_hit` (player's set) and the enemy's `hurt` (the enemy type's set); both play. They draw
  different things, so nothing doubles: the **attacker's set draws the impact** on what was hit
  (keyed on the target's surface and tags: flesh blobs on a runner, sparks on the metal brute), the
  **target's set draws its own reaction** (a flinch, a death burst, the player's hurt ring and
  low-health layer), never the surface impact again. Likewise an enemy hitting the player: the
  enemy's `attack_hit` draws its strike, the player's `hurt` its reaction. *(Builder-check call.)*
- **Sustained effects** for dragged weights: the effect follows the box while it slides and
  switches when the ground under it changes.
- **Effects are scenes**: a `Node3D` root with `GPUParticles3D` children (other nodes allowed, e.g.
  a light flash). No script on the effect.
- **Global toggle** `ahra/vfx/disable` and **quality** `ahra/vfx/quality` (Low / Mid / High), project
  settings read at every spawn, like the shake and hit-stop toggles.
- **No first-spawn hitch**: every effect scene an area can play, plus the projectile, is put in the
  tree once while the area loads.
- **A demo** `demo/vfx/vfx.tscn` with simple, clearly different effects for every scenario.
- **An authoring aid**: the debug HUD shows the last events and their tags, so writing a rule means
  reading the tags off the screen.

## Non-goals

- Audio. Only the hook: `Fx.emit` is where an `Sfx.play(e)` line goes later, on the same events.
- Decals (bullet holes, scorch marks).
- Effects for events nobody asked for: footsteps, jumps, swims, doors, dispensers, NPCs.
- Surface detection from textures or `PhysicsMaterial`. Surfaces are tags put on nodes by hand.
- An editor plugin for rules. Sets and rules are edited in the inspector.
- Pooling (see Latency): built only if measurement shows instancing itself costs real time.
- Changing gameplay: a melee swing that hits a wall still counts as a miss for mood.

## Anti-goals

- A hitch the first time any effect plays.
- Effects left running: a drag effect that keeps emitting after the box stopped, was carried or
  was freed; effects surviving a scene change.
- Hit sites that build effects themselves. They only emit events.
- `Fx` / `Vfx` referencing the `World` autoload (Enemy, WeightBody, MovingPlatform and Projectile
  call them; `-s` tests compile those before autoloads exist).
- Editing `demo/demo.tscn` (it has the user's uncommitted changes) or `demo/builder/`.

## Constraints (Godot 4.7.2)

- Pipeline precompilation (docs, "Reducing stutter from shader compilations"): the surface step
  runs "when a frame is about to be drawn and 3D objects were instanced on the scene tree for the
  first time", "even if it's completely invisible or outside of the camera's view". The docs don't
  say whether `GPUParticles3D` draw passes and process materials are covered, so the warm-up is
  verified with the pipeline-compilation monitors in a windowed run.
- `GPUParticles3D.amount_ratio` scales how many particles emit without reallocating the buffers
  (`amount` would rebuild them).
- Particles run on scaled time: a hit-stop freezes a fresh burst for the stop's length, bullet
  time slows it. That's wanted, not worked around.
- Physics interpolation is on: effects placed by code call `reset_physics_interpolation()`.
- Headless runs use the dummy renderer: pipeline counters read 0 there, so the latency check
  needs a windowed run (as the GI screenshots do, see memory `headless-testing`).

## Approaches

1. **Each emitter owns its rule set (picked).** Hit sites call `Fx.emit`; tags are gathered from
   the action, `source.fx_tags()` and the target's surface; `Vfx` plays the source's `vfx` set,
   which can include shared sets; the thing hit fires its own event. Sets live with what they
   belong to (inherited enemy scenes carry theirs). Costs a few small resource files.
2. **One central table** of every rule, each naming its source kind. One place to look, but enemy
   types can't carry their own effects and the player's rules swamp everyone else's. Rejected.
3. **A listener node per scene** hooked to the existing `cue` signals. Godot-native, but cues are
   bare names (no context, surface or position) and a shot hitting a wall has no node to listen
   from. Rejected.

Rule matching: **layers** (every match plays, `exclusive` stops the rest) over **first match
wins**, so each context (low health, a zone) is authored once instead of once per combination.
Picked by the user.

## Design

### Files

All new code in `vfx/` (like `enemy/`, `npc/`, `puzzle/`):

| File | What |
|------|------|
| `vfx/fx.gd` | `Fx`, static: builds events (`emit`, `hold`), the tag helpers, recent-events debug text |
| `vfx/fx_event.gd` | `FxEvent`, RefCounted: `action`, `tags` (set), `at`, `normal`, `source`, `target` |
| `vfx/vfx.gd` | `Vfx`, static: plays events from rule sets, sustained effects, quality, toggle, warm-up |
| `vfx/vfx_set.gd` | `VfxSet`, Resource: `rules: Array[VfxRule]`, `include: Array[VfxSet]` |
| `vfx/vfx_rule.gd` | `VfxRule`, Resource: `all`, `none`, `effect`, `exclusive`, `align_to_normal` |
| `vfx/effects/*.tscn` | the effect scenes |
| `vfx/sets/*.tres` | the rule sets (player, impacts, runner, brute, burrower, crusher, box, ball) |
| `docs/vfx.md` | the guide (adding an effect, a rule, a surface; the tag table) |

### Events and tags

`Fx.emit(source: Node3D, action: StringName, at: Vector3, normal := Vector3.ZERO,
target: Object = null, extra: Array[StringName] = [])` builds an `FxEvent` and hands it to
`Vfx.play(e)` (later also `Sfx.play(e)`). Tags are a flat set of StringNames:

| Role | Tags | Where from |
|------|------|-----------|
| action | `shot_fired`, `shot_hit`, `shot_fizzle`, `melee_hit`, `attack_hit`, `hurt`, `death`, `slam`, `land`, `drag` | the call |
| extra | `kill` (this hit killed), anything an emitter adds | the call |
| context | `hp_low` / `hp_mid` / `hp_full`, `mood_sad` / `mood_calm` / `mood_happy`, `env_<profile>` per active EnvProfile (`resource_name`, snake_case), `cold` / `hot`, `air`, `water`, `bullet_time`, `floor_<surface>`, `on_<tag>` per `fx_tags` of the floor | `source.fx_tags()` if the source has it (Player only for now) |
| result | `<surface>`, each entry of the target's `fx_tags`, `enemy` / `player` / `weight` by group | `target` |

- **Surface** = metadata `surface` (StringName) on the node or its nearest ancestor that has it;
  none = `default`. Tagging a level's root once tags everything under it; a child overrides.
  Defaults set on the type scenes: Player and Enemy roots `flesh`, box `wood`, ball `metal`.
- **`fx_tags`** = metadata (PackedStringArray) on the node or its nearest ancestor: extra
  identity, e.g. a platform tagged `lift_a` makes a player standing on it carry `on_lift_a`, an
  armoured enemy type tagged `armored` adds `armored` to hits on it.
- Hit tiers reuse Player's existing `_tier()` (the same thresholds as its idle anim keys).
- For `hurt` and `death` the target is the one hurt, so its surface is the result.

### Emitters

| Where | Event | at / normal / target |
|-------|-------|---------------------|
| `Player.shoot` | player `shot_fired` | muzzle / aim dir / none |
| `Projectile._finish` | source's `shot_hit` (`kill` if it killed) | ray hit point / hit normal / collider |
| `Projectile` life out | source's `shot_fizzle` | where it is / -velocity / none |
| `Player.melee_hit` | player `melee_hit` per enemy that landed (`kill` if it died) | point on the enemy toward the player / toward the player / enemy |
| `Player.melee_hit`, nothing landed | player `melee_hit` on a surface: a ray along `facing` at chest height, reach `melee_reach + melee_radius`, skipping characters | hit point / hit normal / collider |
| `Player.damage` | player `hurt`, or `death` when it kills | player's centre / toward the source / player |
| `Enemy.hit` (landed) | enemy `hurt`, or `death` | point toward `from` / toward `from` / enemy |
| `enemy/states/attack.gd` hit | enemy `attack_hit` | player's centre / toward the enemy / player |
| `MovingPlatform._slam` | platform `slam` | the leading face (motion direction before the stop) / -motion / what a short ray from that face hits |
| `WeightBody` `land` cue | weight `land` | contact / up / the body hit |
| `WeightBody` sliding | weight `drag` via `Fx.hold` (below) | ground contact / up / floor collider |

A source freed before its projectile lands (or a projectile with no source) uses the default set.

### Rule sets and matching

- `VfxRule`: `all: Array[StringName]` (every tag present), `none: Array[StringName]` (none
  present), `effect: PackedScene`, `exclusive := false`, `align_to_normal := true` (the effect's +Y
  along the normal; zero normal = the source's up). `@tool` with a `resource_name` summary like
  `shot_hit metal → sparks` (as the NPC resources do), so lists read in the inspector.
- `VfxSet`: own `rules`, then each `include` in order, flattened (a depth limit guards include
  cycles). Walk in order: each match plays; an exclusive match plays and stops the walk.
- The source's set is `source.vfx` if it has one, else `Vfx.DEFAULT` (`vfx/sets/impacts.tres`, the
  shared surface impacts).
- "More than one set" for an enemy type = more rules in its one set, keyed on extra tags.

### Playing an effect

- Parent: the current scene (the area), so a scene change frees everything.
- Placed at `at`, aligned, `reset_physics_interpolation()`, then quality applied.
- Freed after its longest child's `lifetime / speed_scale` plus a pad, on a game-time timer (so a
  hit-stop holds it too).
- **Quality** (`ahra/vfx/quality`, int enum Low=0 / Mid=1 / High=2, default High): every
  `GPUParticles3D` gets `amount_ratio` × (0.35 / 0.65 / 1.0); nodes in group `vfx_high` are removed
  below High, `vfx_mid` below Mid. Read at each spawn, so it flips live.
- **Toggle** (`ahra/vfx/disable`): `Vfx.play` returns early. `Fx` still builds and records events
  (the HUD and future audio keep working).
- `Vfx.clear()` on area load (alongside `CameraShake.clear()` / `SlowMo.clear()`).

### Sustained effects (drag)

`Fx.hold(source, action, at, normal, target)` is called every physics frame while the thing lasts.
`Vfx` keeps the matched effects alive per source and action, moving them to `at`. A frame without a
refresh sets their emitters' `emitting = false` and frees them after their lifetime (the trail fades
out, it doesn't pop). When the matched rules change (new ground), the old effects stop and the new
ones start. A freed source stops its effects the same way. Held effect scenes loop
(`one_shot = false`).

WeightBody holds `drag` while: not carried, a short ray along `gravity_dir` finds ground, and its
planar speed (across its own up) is over `DRAG_SPEED` (about 1 m/s). The ball's set and the box's
set differ, so rolling and scraping can look different.

### Latency (warm-up)

- `GameArea._ready` calls `Vfx.warm(self)`: it collects every `VfxSet` reachable from the area's
  nodes (`vfx` exports, `Vfx.DEFAULT`, includes), the weight scenes Dispensers spawn, and
  `Player.PROJECTILE`, and instances each scene once, with every quality layer and its emitters on,
  far outside the view. They're freed after two rendered frames.
- Proven in a windowed run. **Pass** = after the warm-up, the first spawn of every effect and the
  first shot add nothing to the *surface* and *draw* pipeline-compilation monitors, and no frame
  around the spawn takes over 25 ms. *Specialization* compiles may still rise: they run in the
  background while the ubershader draws, so they don't stall. *(Builder-check call.)*
- Fallbacks, in order, if it fails: (1) warm in the camera's view instead, scaled to 0.001 so
  nothing shows, still for two frames; (2) keep the warmed instances alive as a pool of hidden,
  already-drawn effects and reuse them. Each step is taken only if the counters say the previous
  one isn't enough. *(Builder-check call.)*
- Pooling is not built. The windowed check also measures the CPU time of instancing each demo
  effect. If one costs over 1 ms, add a pool (`ponytail:` comment where it would go).

### Demo `demo/vfx/vfx.tscn`

A `GameArea` subclass (`demo/vfx/vfx.gd`) with bays:
1. **Shots**: walls tagged `stone`, `metal`, `wood`, plus a runner (flesh) and a brute whose type
   scene has surface `metal`: shots spark on it instead of splattering.
2. **Melee**: pillars of each surface and an enemy within reach.
3. **Context**: an EnvZone with its own profile (a layer only inside it), the existing debug keys
   1/2 (damage/heal → `hp_low` layer), 3/4 (mood → `mood_happy` layer), and a moving platform with
   `fx_tags = ["crystal"]`: shots fired while standing on it add a crystal layer (`on_crystal`).
4. **Crusher**: a slam crusher (like `demo/shake`) that kicks up a dust ring.
5. **Drag**: a box and a ball on stone, sand and metal lanes (dust, sand spray, sparks).

Keys 9 (toggle VFX) and 0 (cycle quality), shown in the HUD with the last events' tags.

Effects (simple, unshaded billboards and small meshes, each clearly different): muzzle flash,
impact stone (grey puff + chips), impact metal (fast orange sparks + flash), impact wood
(tumbling splinters), impact flesh (red blobs), impact default (white puff), shot fizzle, enemy
death burst, player hurt ring, low-health embers layer, happy-mood sparkles layer, zone layer,
crystal layer, slam dust ring, drag dust / sand / sparks loops. Each has at least one `vfx_high`
and one `vfx_mid` child, so the quality levels are visible.

### Tests

- `tests/vfx_test.gd` (headless `-s`, sections like the other suites): `rules` (all/none, layers,
  exclusive, include order, cycle guard), `tags` (player context from hp/mood/env/floor, surface
  and `fx_tags` lookup through ancestors, `default`), `emit` (each emitter in the table fires its
  event with the expected tags, inspected through `Fx`'s recent events and the spawned instances'
  `scene_file_path`), `quality` (amount ratios and group removal per level, toggle spawns
  nothing), `hold` (a dragged box starts, swaps on a new lane, stops when it stops, when carried and
  when freed), `warm` (an area load instanced every effect of its sets once).
- `tests/vfx_warm_check.gd`: the windowed latency check above, run by hand (not headless).
- Existing suites that touch the changed hit sites: smoke, enemy, switch, shake, slowmo.

## Left to the builder

- Effect looks, timings and colours within "simple and clearly different".
- Exact positions and normals in the emitter table where a call site makes a better one obvious.
- `DRAG_SPEED`, the ground ray length, the free pad, the quality ratios' fine values.
- Where the warm-up instances sit, decided from the windowed counters.
- HUD layout of the recent-event tags.
- Registering the two settings: they go in `project.godot` `[ahra]` like the others (commit only
  those lines: the file has an uncommitted user change), and `ahra/vfx/quality` should show as a
  Low/Mid/High dropdown if an enabled editor plugin can register its property info cheaply.
- CLAUDE.md: a Vfx section in Architecture and the suite line in Verifying changes.
