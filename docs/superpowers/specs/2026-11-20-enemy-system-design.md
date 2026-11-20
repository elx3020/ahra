# Enemy system design

Date: 2026-11-20. Status: draft for approval.

## Intent

AHRA needs enemies. This work builds the **backbone** that every later enemy type plugs into, plus
the smallest player combat that makes enemies playable, a demo with two distinct enemies, and a
guide for hooking up real animations, skeletal meshes, sound and particles later.

The point of the backbone: shared states and stats so a new enemy type is mostly tuning plus a few
small scripts, while each type can still *play* differently. One runs at you; another digs into the
ground and comes up somewhere else. Both go through the same states, and each fills them in its
own way.

## Goals

- Enemy states: **idle, pursuit, attack, hurt, stun, flee, death, puppet**, shared by all types and
  replaceable per type.
- Enemy stats: **health, stamina, mood, armor, weight, attack_cooldown, oxygen**.
- Traversal abilities: **jump, dash, fly, run, climb, swim, swing**. Each type has one or two.
- Reactive chasing: an enemy heads for the player and reads the ground in front of it each step.
  When it can't go on (a gap it can't clear, water it can't swim, a wall it can't get over), it
  **stops the chase** and doesn't fall in or drown.
- Enemies attack once the player is within a set distance.
- The player can **push** enemies with attacks. `weight` sets how far an enemy flies back; heavy
  enemies don't move. A push can send an enemy into a pit or into water.
- **Stun**: a timed opening for the player. Flyers drop to the ground; ground enemies rest.
- Player combat, deliberately minimal: one **melee** attack and one **ranged** attack (a projectile).
- Demo scene with two enemies: a **runner** and a **burrower**.
- A doc on hooking up animations, custom skeletal meshes and effects (sound, VFX/particles).

## Non-goals

- Route planning (navmesh, detours around walls). The user picked reactive chasing. An enemy won't
  walk around a wall to find a door.
- A combat system: combos, weapons, ammo, damage types, blocking. That comes later. The two player
  attacks are placeholders, enough to play the demo.
- Real animations, models, sounds or particles. Placeholders only, and the doc explains the hookup.
- Enemies under changed gravity (GravityZone). Enemies always fall world-down.
- Enemy persistence: dead enemies come back when the scene reloads, and nothing is saved.
- Enemies fighting each other, friendly fire, enemy projectiles.
- Patrols, wandering, noticing the player by sight lines or sound.

## Anti-goals (failure even if it "works")

- Enemies walking off ledges or into water on their own. Only a push, or being stunned in the air,
  should put them there.
- Enemies flickering between chasing and giving up every frame at an edge.
- Any change to how the player's existing moves feel. The player only gains two attacks.
- A new enemy type that needs edits to the shared code just to tune numbers or swap a behaviour.

## Constraints

- Godot 4.7.2, GDScript, Jolt physics, physics interpolation on. Static typing and `##` doc comments
  throughout; each new script gets a committed `.uid` sidecar (CLAUDE.md conventions).
- Follow the player's pattern: a `CharacterBody3D` with one `RefCounted` script per state,
  `physics(delta)` returns the next state's name or `&""`, motion split into vertical
  (`up_direction`) and planar.
- Verification is headless only (`tests/`). A script error hangs Godot, so always use `timeout`.
  `-s` test scripts compile typed dependencies before autoloads exist, so `Enemy` must not reference
  the `World` autoload. A new `class_name` only lands in the global class cache after an editor run
  (`--editor --quit-after`), so do one before the first `-s` run.
- Don't edit the user's own scenes (`demo/builder/`, and `demo/demo.tscn` beyond what's asked). The
  demo is a new scene.
- `ponytail:` comments mark deliberate shortcuts. Add one wherever this design cuts a corner.

## Approaches considered

1. **Enemy as its own body and state machine, built like the player (chosen).** `Enemy` is a
   `CharacterBody3D` with shared state scripts. Moves calculate their motion from a target (a jump
   solves its launch speed for the landing spot) instead of copying the player's input handling.
   Each type tunes exports and can replace any state. Trade-off: enemy movement code exists apart
   from the player's, so a gap the player clears isn't automatically one an enemy clears; it's set
   per type.
2. **Enemies steer the player's body through a virtual controller.** The player states read an
   "intent" instead of the keyboard, and enemies fill it from AI. Rejected: it rewrites every tuned
   player state, gives each enemy two state machines, and button timing (swing release, dash-jump)
   is less reliable than calculating the move.
3. **Enemies assembled from ability parts** (one child node per ability, asked in turn "can you get
   me past this?"). Rejected: the most plumbing for enemies that only have one or two abilities, and
   odd behaviours like burrowing still need code.

The user picked 1.

## Design

### Files

```
enemy/enemy.gd              class_name Enemy: body, stats, senses, ground probe, state machine, hit/stun/die
enemy/enemy_state.gd        class_name EnemyState: base state (back-reference `e: Enemy`)
enemy/states/               idle, pursuit, attack, hurt, stun, flee, death, puppet,
                            jump (also plain falling), dash, climb, swim, swing
enemy/runner/runner.tscn    runner: uses enemy.gd directly (no script of its own), tuned exports
enemy/burrower/burrower.tscn, burrower.gd, burrow_pursuit.gd, burrow_attack.gd
player/states/melee.gd      player melee attack state
world/projectile.gd + world/projectile.tscn
demo/enemies/enemies.tscn   demo area (root script: GameArea)
docs/enemies.md             making enemy types + hooking up animation, meshes, sound, VFX
tests/enemy_test.gd         headless suite, last line "ENEMIES: OK" / "N FAILED"
```

There's no fly state: flying is how a flyer moves in idle, pursuit and flee (see Traversal).

### The Enemy body

Built like `Player`: `states: Dictionary[StringName, EnemyState]` preloaded in `enemy.gd`,
`change_state()`, and a `_physics_process` that ticks timers and stats, runs `state.physics()`,
then orients the body and runs the placeholder animation. Movement helpers have the same names and
meaning as the player's: `vspeed()`, `set_vspeed()`, `planar()`, `move_planar()`,
`apply_gravity()`, `water_depth()`, `deep_water()`. They're written again in `enemy.gd` rather than
shared with Player. That's a builder-visible call: about 40 lines, kept separate so the player stays
untouched. Mark it `ponytail:` (shared base class once a third kind of body appears).

**Per-type behaviour.** A type is a scene: a `CharacterBody3D` with `enemy.gd` (or a subclass), a
`CollisionShape3D` and a `Visual` node. Tuning lives in the scene's exports. To make a state play
differently, a subclass replaces the state script in `_init()`:

```gdscript
extends Enemy
func _init() -> void:
	states[&"pursuit"] = preload("burrow_pursuit.gd").new()
	states[&"attack"] = preload("burrow_attack.gd").new()
```

**Abilities**: `@export_flags("Jump", "Dash", "Fly", "Run", "Climb", "Swim", "Swing") var abilities`,
with `can(flag) -> bool`. Walking on the ground is the baseline and isn't an ability. Exceptions:
a FLY enemy doesn't walk (it flies, and only touches the ground when stunned), and an enemy whose
only ability is SWIM never leaves water (it treats the shoreline like a ledge).

**Target**: the player, found through a new `player` group (one `add_to_group` line in
`Player._ready`). The target counts as gone while the player is in `death` or `puppet`; enemies then
drop back to idle.

### Stats (exports, grouped like the player's)

| Stat | Meaning |
|------|---------|
| `max_health` | Hit points. 0 means death by hit. |
| `armor` | 0–1, the fraction of incoming damage blocked. |
| `weight` | Knockback speed from a hit is `push / weight`. Below 1 m/s the hit doesn't move the enemy at all, so heavy enemies are effectively unpushable. |
| `max_stamina`, `stamina_regen` | Running, flying, dashing and attacking cost stamina (per-type costs: `run_cost`/s, `fly_cost`/s, `dash_cost`, `attack_cost`). Reaching 0 stuns the enemy for `stun_time`, and its stamina refills when the stun ends. Regen only runs while nothing is draining it. |
| `max_oxygen`, `oxygen_regen` | Drains while the head is under water (same depth test as the player's `HEAD`). 0 means death by drowning. Swimmers surface when it drops below 30%. |
| `mood` | 0–1 aggression, with a per-type starting value. +0.1 when the enemy lands a hit, −0.15 when it gets hurt, and it drifts back to the starting value over time while not chasing. Below `flee_mood` the enemy flees. `flee_mood = 0` means it never flees. |
| `attack_cooldown` | Seconds between attacks. |
| `invuln_time` | Hits are ignored for this long after a hit, so heavy enemies can't be stun-locked by rapid attacks. |
| `stun_on_hit` | Seconds of stun a hit causes (default 0). For flyers: shoot one down, then melee it on the ground. A hit during a stun doesn't restart it. |

Movement, sense and attack tuning are exports too: `walk_speed`, `run_speed`, `accel`,
`safe_drop` (the deepest drop it will walk off), `jump_height`, `jump_reach` (longest flat jump),
`dash_speed`, `dash_distance`, `climb_speed`, `swim_speed`, `fly_speed`, `hover_height`,
`sight_radius` (the chase starts inside it), `lose_radius` (the chase ends outside it),
`attack_range`, `attack_damage`, `attack_windup`, `attack_recover`, `give_up_time`.
`show_debug` adds a `Label3D` above the enemy showing state, health, stamina, mood and oxygen.

### Damage and death API

- `hit(damage, push, from: Vector3)`: the only way the player (or anything else) hurts an enemy.
  Ignored while dead, in puppet, or within `invuln_time`. Damage is `damage * (1 - armor)`, mood
  goes down, and the `hurt` cue fires. Then: health at 0 means `die(&"hit")`. If a stun is running,
  it stays stunned and still takes the knockback. Otherwise it enters `hurt` with velocity
  `away * push / weight` plus a small upward part, or flinches in place if the knockback is under
  1 m/s. If `stun_on_hit > 0`, it is stunned instead of hurt.
- `stun(seconds)`: callable by anything (exhaustion, hits, a type's own rules, level scripts).
- `die(cause)`: `&"fall"`, `&"drown"` or `&"hit"`, as on the player. It drops out of collision so the
  player can walk through the body, plays `death_<cause>`, emits `died(cause)` and frees itself
  after a cause-specific delay (same durations as the player's death state).
- Falls: landing faster than a threshold costs health in proportion to the speed. An enemy more
  than 60 m below its spawn point dies by fall: a backstop for scenes without a `Void` kill zone.

### States

All states return the next state's name. Shared behaviour:

- **idle**: stands still (flyers hover), regenerates, and its mood recovers. When the target is
  inside `sight_radius` and no give-up timer is running, it switches to pursuit.
- **pursuit**: if the target is outside `lose_radius` or gone, go to idle. If mood is under
  `flee_mood`, flee. If the target is within `attack_range` and the cooldown is over, attack.
  Otherwise `step_toward(target)` (see Traversal), which can hand off to a move state. When it
  reports **blocked**, the enemy **stops the chase**: it goes idle and starts a `give_up_time` timer
  (about 1.5 s) before it may chase again. That pause is the guard against edge flicker.
- **attack** (base, melee): stop and face the target (windup, `attack_windup`, cue
  `attack_windup`), then one strike check: target within reach and roughly in front →
  `Player.damage(attack_damage, global_position)`, cue `attack`, mood up. Then a recovery
  (`attack_recover`), cooldown starts, stamina is spent, back to pursuit.
- **hurt**: knockback slide with gravity and **no ledge check**. This is how a push sends an enemy
  into a pit. Short, then back to pursuit (or idle if the target is gone). If it's still airborne
  when the hurt ends, it falls (jump state, `goal` pursuit) and makes no decisions until it lands.
- **stun**: time-limited. Flyers switch gravity on and fall (into a pit, if that's what's below);
  ground enemies stand still. At the end, stamina refills, and flyers take off back to hover height.
- **flee**: `step_toward` a point away from the target, with the same ledge and water rules. When
  blocked (cornered), it stays put facing the player and attacks if the player comes within range.
  When it's outside `lose_radius` and mood has recovered past `flee_mood + 0.2`, it goes idle.
- **death**: see `die()`. Physics keeps running, so a body falling into a pit keeps falling.
- **puppet**: scripted control like the player's. `start_puppet(target_pos)` / `end_puppet()`,
  emits `puppet_arrived`. Ignores AI, damage and ledges; level scripts are responsible.

Move states (**jump, dash, climb, swim, swing**) remember which state handed off to them in `goal`
(`&"pursuit"` or `&"flee"`) and return there when the move ends.

A non-swimmer in deep water can't act: it flails, sinks under the water's drag, and drowns when its
oxygen runs out. If it ends up in shallow water, it recovers.

### Traversal (reactive)

`probe(dir)` looks just past the body's edge along the planar direction (about 0.8 m plus a bit
more with speed) and reports one of:

- **open**: ground ahead, at most `safe_drop` lower.
- **wall**: `test_move` hits something steep. It reports the wall's height (a ray cast down onto
  its top, up to `jump_height` plus margin) and whether it's `climbable`.
- **gap**: no ground within `safe_drop`. It also samples forward every 0.5 m, up to the longer of
  `jump_reach` and `dash_distance`, for a **landing spot**: ground that isn't deep water.
- **water**: ground ahead, but deep water over it, where the surface is more than head height above
  the ground. Water is found with a point query that includes areas (an `EnvZone` whose profile has
  `water`), and depth comes from `EnvZone.surface_height`.

Probes ignore the player and other enemies: they're bodies to bump into or attack, not terrain.
Otherwise an enemy closing in on the player would read the player as a wall and give up the chase.

`step_toward(point, delta)` turns the probe into a decision for ground enemies:

| Probe | Decision |
|-------|----------|
| open | Move: `run_speed` with RUN (drains stamina), otherwise `walk_speed`. |
| wall | CLIMB and climbable → `climb`. JUMP and wall height ≤ `jump_height` → `jump` onto its top. Else **blocked**. |
| gap | JUMP and a landing spot within the jump solve → `jump`. DASH and the landing is about level and within `dash_distance` → `dash`. SWING and a usable SwingPoint → `swing`. Else **blocked**. |
| water | SWIM → walk in (pursuit hands off to `swim` once the water is deep). Else **blocked**. |

Moves:

- **jump** solves the arc instead of simulating input. With a single gravity (no fall multiplier,
  so the solve is exact): apex `h = max(rise, 0) + clearance`, reject if `h > jump_height`; upward
  speed `sqrt(2gh)`; flight time from the apex to the landing height; horizontal speed =
  distance / time, reject if above the speed implied by `jump_reach` on flat ground. No steering in
  flight. On landing, return to `goal`. The jump state also handles plain falling (pushed off, or
  walked off a small drop).
- **dash**: fixed speed, no gravity, for `dash_distance`, spends `dash_cost`. If there's no floor at
  the end, it falls (jump state).
- **climb**: on a `climbable` wall, moves along it toward the target's height. At the top it hops
  over the ledge (like the player's ledge hop), then falls onto the top and returns to `goal`. Only
  upward climbs are entered from the ground. Climbing *down* from an edge is a `ponytail:` (add when
  a level needs it).
- **swim**: in deep water, moves in 3D toward the target, kept below the surface. It surfaces when
  oxygen is low, and when the target is on land and the bank ahead is low enough, it jumps out with
  the jump solve.
- **swing**: at a gap with a SwingPoint (`swing_point` group) within its `grab_radius` from the edge,
  and ground on the far side. It attaches and swings as a pendulum (for the look), and on release
  sets the launch velocity solved for the landing, the same as jump. That makes it reliable instead
  of timing-dependent.
- **fly** (no state): FLY enemies move in 3D toward a point `hover_height` above the target, gravity
  off, staying at least `hover_height` above the ground beneath them. Blocked by a wall → rise and
  try again, up to a cap; still blocked → **blocked**. Flying in pursuit drains `fly_cost`, so a
  long chase ends in an exhaustion stun and a drop to the ground.

Moving platforms: enemies ride them (Jolt carries a `CharacterBody3D`), and probes see the platform
where it is now. They don't plan jumps onto moving platforms.

`ponytail:` probes cost a few rays and a `test_move` per enemy per physics frame. Fine for tens of
enemies; throttle probing if a scene ever holds many more.

### World zones reach enemies

`Zone._on_body_entered/_exited` gain an `elif b is Enemy` branch calling new virtuals
`_enemy_entered(e)` / `_enemy_exited(e)` (default: nothing). Implemented by:

- `EnvZone`: `e.add_env(profile)` / `remove_env`, and sets/clears `e.water_zone` for water, exactly
  as for the player. Enemies read `env` for gravity_mult, drag, wind and water, and its stat mods
  through `mult(&"speed")` etc. (`1 + env%`, no progression), so mud slows enemies too.
- `KillZone`: `e.die(cause)`.

Checkpoint, Teleporter, SceneDoor, CutsceneTrigger, Interactable and GravityZone stay player-only.

### Presentation hooks (what the docs build on)

- `anim: StringName`, set by states like the player's (`idle`, `walk`, `run`, `jump`, `fall`,
  `dash`, `climb`, `swim`, `swing`, `fly`, `attack_windup`, `attack`, `attack_recover`, `hurt`,
  `stun`, `flee`, `cower`, `flail`, `blocked`, `death_fall`, `death_drown`, `death_hit`, plus
  type-specific ones such as `burrow_in`, `burrowed`, `surface`). It's polled every frame; meant for
  an AnimationTree.
- `signal cue(name: StringName)`: one-shot events for sound and VFX (`attack_windup`, `attack`,
  `hurt`, `stun`, `land`, `jump`, `death`, `burrow_in`, `surface`...). States emit them; presentation
  code listens. Gameplay never depends on them.
- `died(cause)` for spawners and scoring.
- A placeholder `_animate()` squashes and tilts the `Visual` node per `anim`, like the player's,
  marked `ponytail:` (replace with AnimationTree).

### Player combat (minimal)

- Input actions in `project.godot`: **`attack`** (J, left mouse, right trigger) and **`shoot`**
  (K, right mouse, left trigger). Bindings are a builder-visible call; the HUD help line in
  `GameArea.HELP` lists them.
- **Melee**: a new player state `melee`, entered from the ground states (`ground_step`) and the jump
  state when `attack` is pressed and `melee_cd` is over. It lasts `melee_time` (about 0.3 s), with
  slowed ground movement or kept air movement, and gravity on. At 40% of the swing there's a
  single hit check: a sphere shape query in front of the player (`melee_reach`, `melee_radius`).
  Each `Enemy` inside gets `hit(melee_damage, melee_push, global_position)`, once per swing. Then it
  recovers via `recover_state()`. Anim `melee`.
- **Ranged**: not a state, so the player can shoot while idle, walking, running, jumping or
  swimming (not climbing, swinging, dashing, hurt, dead, in puppet or interacting). On `shoot` with
  `shoot_cd` over, it spawns `world/projectile.tscn` in front of the chest. Aim is the facing
  direction, or toward the nearest enemy within a 25° cone and `shoot_range` (aim assist, so shots
  don't miss enemies above or below on iso terrain).
- **Projectile** (`world/projectile.gd`, scene with a small mesh for VFX later): straight line, no
  gravity, `speed`, `damage`, `push`, `life`, `source` (the shooter, ignored). Each physics frame it
  ray-casts from the last position to the next, so it never tunnels. Hitting an `Enemy` calls
  `hit()`, hitting the `Player` calls `damage()` (ready for enemy shooters later), and hitting the
  world frees it. `reset_physics_interpolation()` on spawn.
- **Player mood**: `Player.register_attack(hit)` already exists (mood = hit ratio over the last
  `mood_window` attacks, faked so far with debug keys 3/4). Each melee swing registers whether it hit
  any enemy, and each projectile registers on hit or when it expires or hits the world.
- New player exports in an "Attack" group: `melee_damage`, `melee_push`, `melee_time`,
  `melee_cooldown`, `melee_reach`, `melee_radius`, `shoot_damage`, `shoot_push`, `shoot_speed`,
  `shoot_cooldown`, `shoot_range`.

### The two demo enemies

**Runner** (`enemy/runner/runner.tscn`, plain `enemy.gd`). Shows the base states doing their default
job.
- Abilities RUN + JUMP. Light (`weight` about 3): a melee push (about 24) knocks it back about
  8 m/s, so it flies off ledges. Low health (about 40), no armor.
- Chases at a run slower than the player's (about 6.5 vs 8.5), jumps gaps up to about 4 m and walls
  up to about 1.8 m, and stops at wider gaps, higher walls and deep water.
- Running drains its stamina in about 5 s of chasing, then it rests stunned for about 2 s: the
  timed opening.
- Base melee attack (bite) at about 1.6 m, 10 damage.

**Burrower** (`enemy/burrower/`, `burrower.gd` replaces pursuit and attack). Shows a type playing the
shared states its own way.
- No traversal abilities. Heavy (`weight` about 40): melee and shots don't move it. Health about
  120, some armor. `flee_mood = 0`.
- **pursuit** = dig in (`burrow_in`, about 0.6 s, collision off, untouchable), then travel
  underground toward the player at `burrow_speed`. Only a dirt-mound visual shows on the surface.
  Underground it passes **under walls** but **not across gaps or water**: each step casts down at
  the next point, and needs ground within `safe_drop` that isn't deep water. When it's within about
  1.5 m of the player, or blocked, it surfaces. A blocked burrower surfaces and goes idle with the
  give-up timer.
- **attack** = the surfacing burst: damages the player within about 2 m (the player's own knockback
  applies), cue `surface`, then `stun(rest_time)` for about 2.5 s. That rest is the player's window.
  It then idles and digs in again.

### Demo scene (`demo/enemies/enemies.tscn`)

A `GameArea` root (Player, Camera, HUD/Label, Floor, a `Void` KillZone, `Bays`) with three bays:

1. **Runner**: two runners on a plateau with a 3 m gap (it jumps), a 7 m gap (it stops), a pond of
   deep water (it stops; push it in and it drowns) and a ledge over a pit (shove it off).
2. **Burrower**: a field split by a water channel and a pit strip. It travels under a wall to reach
   you, can't cross the channel or the pit, surfaces next to you and rests. Pushes don't move it.
3. **Both**: one of each, together.

Each bay has a `Label3D` explaining what to try, like the main demo. It's opened directly (F6 on
the scene). `demo/demo.tscn` isn't changed and doesn't link to it.

### Verification

`tests/enemy_test.gd`, a `SceneTree` script in the same style as the other suites (exit code =
failures, last line `ENEMIES: OK`). It loads the demo scene for the two enemies and builds small
courses in code (CSG boxes, an `EnvZone` water volume via `add_shape`, a SwingPoint, a climbable
wall) for the abilities the demo doesn't use. It checks:

- aggro inside `sight_radius`, idle outside; the chase stops outside `lose_radius`;
- runner: jumps the 3 m gap, stops at the 7 m gap and at deep water, and never falls in on its own;
- attack within range hurts the player and respects the cooldown;
- melee and projectile damage reduced by armor; knockback ∝ 1/weight; burrower not moved;
- runner shoved off the ledge dies by fall; shoved into the pond, drowns;
- stamina exhaustion stuns; `stun_on_hit` drops a flyer to the ground;
- low mood flees; cornered flee holds its ground;
- burrower travels under the wall, refuses the channel and the pit, surfaces near the player, rests;
- test-only configurations: a SWIM enemy crosses the water, CLIMB scales the wall, DASH crosses a
  level gap, SWING crosses the swing gap, FLY crosses a gap and hovers;
- puppet ignores AI and emits `puppet_arrived`; death frees the enemy and emits `died`.

The existing smoke and puzzle suites must still pass (the player gained a state, input actions and a
group). As always, game feel is untested and the final report says so.

### Docs

- **`docs/enemies.md`** covers two things. First, how to make a new enemy type: the scene layout,
  exports, abilities, replacing states, emitting cues. Second, how presentation hooks up later:
  - **animations**: an AnimationTree state machine keyed on `anim` (a table of every name);
    replacing `_animate()`; one-shots from `cue`; why gameplay never waits on animation
    (code drives motion, no root motion).
  - **custom skeletal meshes**: import a glTF under `Visual`, keep the `CollisionShape3D` as the
    gameplay shape, forward is −Z, scale and offset; `BoneAttachment3D` for markers (projectile
    muzzle, attack point).
  - **effects**: one presentation child node per enemy that maps `cue` names to
    `AudioStreamPlayer3D` / `GPUParticles3D`; spawning detached effects for death (the enemy frees
    itself); the projectile scene as the VFX slot for shots and impacts; the same pattern for the
    player's `melee` anim.
- **`CLAUDE.md`**: an Enemies section in Architecture, the new test command, and the zone hook.

## Left to the builder

Exact numbers (all of the "about" values above), probe distances and margins, the fall-damage
threshold, placeholder meshes and colours, bay layout details, the `Label3D` debug format, and
how the burrower's mound is drawn.
