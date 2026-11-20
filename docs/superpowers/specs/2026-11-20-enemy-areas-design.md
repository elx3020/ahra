# Enemy patrol areas, chase areas, sight and off-screen sleep

Date: 2026-11-20. Status: draft for approval. Builds on
`docs/superpowers/specs/2026-11-20-enemy-system-design.md` (the enemy backbone, merged).

## Intent

Enemies today stand still until the player comes inside `sight_radius`, see through walls, and
chase anywhere. Levels need enemies that **guard places**:
- while they haven't spotted the player, they roam a patrol area;
- once they have, they chase it only so far, within a chase area;
- they lose the player when it's out of sight.

The areas are drawn in the editor, can take any shape, and several enemies can share one.

A level full of roaming enemies is expensive: the user's crowd demo has 250 runners. Enemies off
screen therefore **sleep**. Their thinking and ground checks stop, but physics keeps acting on
them, so they still ride moving platforms, fall and get pushed.

## Goals

- `EnemyArea`: a zone with any shape, editable with the Shape Tools plugin like every other
  `Zone`. Enemies reference it through two exports, `patrol_area` and `chase_area`. Any number of
  enemies can reference the same area, and one area can be both an enemy's patrol and chase area.
- **Patrol**: an enemy with a patrol area that hasn't spotted the player roams it. It picks a spot
  inside, gets there with its own moves (the same traversal as the chase: jumps, dashes, climbs,
  swims, swings, flies, with the same ledge and water rules), pauses, and picks the next.
- **Sight**: the enemy spots the player only when it is inside `sight_radius` **and** in plain
  view (no terrain on the line between them).
- **Losing the player**: out of sight, the enemy goes to where it last saw the player and gives up
  if it isn't there. Past `lose_radius` it gives up too, as today.
- **Chase area, a leash on the enemy** (the user chose this): the enemy chases anywhere inside
  its chase area. The border counts as a ledge, so it stops there, gives up, waits out
  `give_up_time` and goes back to patrolling.
- **Return**: after giving up, the enemy goes back into its patrol area and resumes roaming.
- **Off-screen sleep** ("freeze completely", as the user defined it): an enemy off screen, plus a
  margin, runs no states, no stats and no ground checks. It still runs gravity, drag, wind drift
  and `move_and_slide`, so it rides moving platforms, falls, drifts, and triggers zones (a
  KillZone kills it). A dying enemy finishes dying. It wakes up exactly where it is and carries on
  from the state it was in.
- **Crowd demo** (`demo/enemies/crowd.tscn`, the user's scene, which they asked to update): its
  250 runners get shared patrol areas in a few different shapes and a chase area, and sleep off
  screen.

## Non-goals

- Route planning (still reactive, as decided for the backbone).
- Off-screen enemies still roaming or walking home at a reduced rate. The user chose freezing.
- Concave and height-map area shapes. A point query can't tell whether a point is inside them (see
  Constraints). Areas use boxes, spheres, capsules, cylinders or convex shapes, and a config
  warning says so.
- Hearing, alert states, enemies alerting each other, patrol routes (fixed waypoints).
- Changing other bays of the enemy demo. Only the crowd demo is updated.

## Anti-goals

- A roaming enemy walking off a ledge, into water it can't swim in, or out of its patrol area on
  its own.
- An enemy stuck flipping between chasing and giving up at a chase border every frame. The
  existing `give_up_time` covers this.
- Sleeping enemies that hang in the air, drop through moving platforms, or ignore a pit or a kill
  zone.
- Headless tests breaking because nothing is ever "on screen".
- Enemies seeing through walls.

## Constraints

- Same project rules as the backbone: Godot 4.7.2, static typing, `##` docs, `.uid` sidecars
  committed, `ponytail:` on deliberate shortcuts, headless tests with `timeout`. `Enemy` and
  `EnemyArea` must not reference the `World` autoload.
- CSG collision is a hollow trimesh, and Jolt point queries only work against shapes with
  volume. "Is this point inside the area" therefore works for convex area shapes (box, sphere,
  capsule, cylinder, convex) and not for concave or height-map ones.
- `@tool` scripts create child nodes in `_ready`, not as member defaults (CLAUDE.md).
- Headless runs have no rendering, so a `VisibleOnScreenNotifier3D` never reports on screen. Sleep
  is off when `DisplayServer.get_name() == "headless"`.
- Performance: in the crowd demo only the enemies on screen think. Sight is a single ray, cached
  for 0.2 s.

## Approaches considered

- **Areas**
  - **Chosen:** an `EnemyArea` node built on `Zone`, so it gets any shape, the Shape Tools
    editing and colour drawing for free, and enemies reference it.
  - **Rejected:** a radius around the spawn point (can't take arbitrary shapes), and Godot
    navigation regions (need a baked navigation map, which was ruled out for chasing).
- **Off screen**
  - **Chosen:** a `VisibleOnScreenNotifier3D` per enemy sets an `asleep` flag, and a sleeping
    enemy runs a physics-only tick.
  - **Rejected:** `VisibleOnScreenEnabler3D` (it switches processing off entirely, so the enemy
    wouldn't ride platforms, which breaks the user's requirement), and slow off-screen updates (the
    user chose freezing).

## Design

### EnemyArea (`world/enemy_area.gd`)

`@tool`, `class_name EnemyArea extends Zone`. It's drawn in its `color` like any zone; the default
is a faint orange. It doesn't react to bodies entering, so it doesn't use the zone hooks. Its
shapes are `CollisionShape3D` children, edited with the Shape Tools inspector and handles.

- `contains(point: Vector3) -> bool`: a point query with `collide_with_areas`, true when this
  area is among the results.
- `random_ground(e: Enemy) -> Variant`: a random feet point inside the area that enemy `e` can
  stand or float at, or null after a fixed number of tries (about 12):
  - pick a random point in `bounds()` (zone space, then global), then cast down (`e.cast`) from
    the bounds' top to its bottom;
  - the hit must be inside the area (`contains(hit + up*0.5)`);
  - for a non-swimmer, the hit must not be under deep water (`e.deep_water_at`); for a SWIM-only
    enemy, the hit must be under water;
  - for a FLY enemy, the spot is the ground point, and the flyer goes to `hover_height` above it.
  - Randomness comes from the enemy's own `rng` (seedable, for tests).
- `_get_configuration_warnings()`: warn when a shape is concave or a height map.

### Enemy additions (`enemy/enemy.gd`)

- Exports, in a new "Areas" group: `patrol_area: EnemyArea`, `chase_area: EnemyArea`,
  `patrol_pause := Vector2(1.0, 3.0)` (seconds of pause at each spot, min and max),
  `sleep_off_screen := true`, `screen_margin := 4.0` (metres added around the body for the
  on-screen test). Sense exports: `memory_time := 3.0` (seconds a lost player is remembered).
- `var rng := RandomNumberGenerator.new()`, seeded randomly in `_ready` (tests set a seed).
- **Sight**: `sees_target() -> bool` is `has_target()`, within `sight_radius`, and `cast(eye,
  player chest)` is empty, so terrain blocks sight and bodies don't. The eye is the body centre
  plus `HEAD`. The result is cached for 0.2 s. `last_seen: Vector3` and `seen_ago: float` are
  updated whenever it's true.
- **Leash**: `step_toward(point, delta, leash: EnemyArea = null, hurry := true)`.
  - While the enemy is inside `leash`, a step or a move whose destination (probe edge point,
    jump landing, wall top, dash and swing landings, the flyer's next position) is outside the
    leash returns `&"blocked"`, like a ledge.
  - An enemy already outside its leash isn't blocked, so it can walk back in.
  - `hurry` false means walk speed with no `run_cost`, and no `fly_cost` for flyers. Roaming
    doesn't tire enemies out.
- **Sleep**:
  - `_ready` adds a `VisibleOnScreenNotifier3D` child, with its `aabb` set to the capsule grown by
    `screen_margin`. `screen_entered` and `screen_exited` set `asleep`.
  - `asleep` starts true when sleep is enabled (not headless, `sleep_off_screen` on). An enemy
    spawned on screen gets `screen_entered` on the first frame; one spawned off screen stays
    asleep.
  - `set_asleep(on: bool)` is public, for tests and level scripts.
  - While asleep and not dead, `_physics_process` runs only `_doze(delta)` and skips timers,
    stats, the state, `_fall_damage`, `_orient` and `_animate`. `_doze` does no rays:
    - a ground enemy: `move_planar(Vector3.ZERO, 0, delta)` (decelerate, plus wind drift),
      `apply_gravity(delta)`, `move_and_slide()`, so platform carry works as for the player;
    - a flyer, or a swimmer in water: velocity eases to zero, no gravity, `move_and_slide()`.
  - While dead, the death state runs as usual, so it frees itself.
- `debug_text()` adds "asleep" when it is.

### States

- **idle** (changed): stands as today for `patrol_pause` seconds (a random value in the range).
  Then, with a patrol area, it goes to `patrol`. It spots the player with `sees_target()` (plus
  the `give_up` timer, as today) → pursuit. With no patrol area it stands forever, as today.
- **patrol** (new, `enemy/states/patrol.gd`):
  - On enter it picks a spot. If the enemy is outside its patrol area, any spot inside brings it
    back. If none is found it goes to idle.
  - It moves with `step_toward(spot, delta, patrol_area, false)`. Spotting the player →
    pursuit. Arrival (planar distance under 0.5 m; a flyer at its hover point) → idle.
  - `&"blocked"`, or the watchdog → idle. The next pause picks a new spot.
  - Move hand-offs work as in the chase: `goal = &"patrol"`.
  - `anim` is `walk` (or `fly` or `swim`, set by the moves).
- **pursuit** (changed): steps with `leash = chase_area`.
  - When `sees_target()`: chase the player, as today.
  - Otherwise: head for `last_seen`. On arrival (planar under 1 m), or once `seen_ago >
    memory_time`, give up: `give_up = give_up_time` → idle.
  - The attack check is unchanged, and attacking needs sight. An enemy that loses sight of a
    player in attack range keeps going for `last_seen`.
- **flee** (changed): steps with `leash = chase_area`, so a cornered-at-the-border enemy holds
  its ground, as at any ledge.
- **swim**: same leash rule. Its aim when it has lost sight is `last_seen`.
- Moves (jump, dash, climb, swim, swing) return to `goal` as today. `goal` may now be `patrol`.

### Crowd demo (`demo/enemies/crowd.tscn` + `crowd.gd`)

- Four `EnemyArea` patrol areas in different shapes: a box, a cylinder, a sphere, and a
  two-shape area made of a box and a cylinder. Each is shared by a quarter of the runners.
- One large `EnemyArea` chase area shared by all of them, smaller than the floor, so you can
  watch them stop at its border.
- `crowd.gd` assigns `patrol_area` and `chase_area` when spawning and spreads each group inside
  its patrol area. The middle stays clear for the player, as today.
- A `Label3D` explains: roam, spot, chase to the border, lose sight; and that off-screen enemies
  sleep (the HUD shows how many are awake).
- `crowd.gd` adds an "awake: N / 250" line to the HUD (through `help()` or by appending to the
  label).

### Verification (`tests/enemy_test.gd`, new sections)

- **areas**: `contains` for a box and a sphere area (inside, outside, rotated area);
  `random_ground` returns points inside, never in deep water for a non-swimmer, and only in
  water for a SWIM-only enemy.
- **patrol**:
  - a seeded enemy with a patrol area visits at least 3 distinct spots and never leaves it
    (sampled every frame, 0.5 m tolerance);
  - a JUMP enemy's patrol area made of two plateaus across a 3 m gap: within N seconds it stands
    on both sides (seeded);
  - two enemies sharing one area both roam inside it;
  - an enemy placed outside its patrol area walks back in.
- **sight**:
  - a wall between them: not spotted inside `sight_radius`; without the wall, spotted;
  - the player hides behind a wall mid-chase: the enemy reaches `last_seen`, gives up and walks
    back into its patrol area.
- **leash**: the player stands outside the chase area. The enemy chases to the border and never
  crosses it (0.5 m tolerance), gives up, and returns to its patrol area.
- **sleep**:
  - `set_asleep(true)`: the state doesn't change while the player is in plain view and in range;
  - a sleeping enemy on an `AnimatableBody3D` moved by the test is carried with it;
  - a sleeping enemy walked off a ledge, or carried into a KillZone, falls or dies;
  - `set_asleep(false)` resumes the AI;
  - headless enemies are never asleep by default.
- **crowd demo**: loads with no errors; after a few seconds some runners have moved (patrolling).

Existing sections must keep passing, since idle, pursuit and step_toward changed. Re-run smoke,
platforms, puzzles and the enemy demo load. On-screen detection itself can't be tested headless;
the report says so, along with "game feel untested".

### Docs

`docs/enemies.md` gets a section on areas: how to add an `EnemyArea`, assign it to one or many
enemies, which shapes are supported, and how patrol, sight, chase leash and give-up fit together.
It also explains sleeping off screen: what keeps running, `sleep_off_screen`, `screen_margin`
and `set_asleep`. `CLAUDE.md`'s Enemies paragraph gets the new pieces.

## Left to the builder

Default colour, `random_ground` try count, arrival tolerances, the pause range defaults, area sizes
and layout in the crowd demo, and the HUD wording.
