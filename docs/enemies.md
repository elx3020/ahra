# Enemies

How the enemy system works, how to make a new enemy type, and how real animations, skeletal
meshes, sound and VFX hook into it later. The code lives in `enemy/`. The demo is
`demo/enemies/enemies.tscn` (open it and press F6). The tests are `tests/enemy_test.gd`.

## The pieces

- **`Enemy`** (`enemy/enemy.gd`) is a `CharacterBody3D` built like `Player`. It has one
  `RefCounted` script per state in `enemy/states/`, and `physics(delta)` returns the next state's
  name. It holds the stats, the motion helpers (`vspeed()`, `planar()`, `move_planar()`,
  `apply_gravity()`, `hold()`), the ground probe and the damage API.
- **`enemy/enemy.tscn`** is the base scene: a capsule `Collision`, plus a `Visual` node holding
  placeholder meshes. Every enemy type is an inherited scene of it.
- **`EnemyState`** (`enemy/enemy_state.gd`) has `enter(prev)`, `exit()` and `physics(delta)`.
  `e` is the enemy.
- **Zones reach enemies**: `Zone._enemy_entered/_enemy_exited`. `EnvZone` applies its profile
  (water, mud, wind...) and `KillZone` kills. Checkpoints, doors, cutscenes and gravity zones stay
  player-only.
- **The player's attacks**: `melee` (J / left mouse) is a player state that calls
  `Player.melee_hit()`. `shoot` (K / right mouse) fires a `Projectile` (`world/projectile.tscn`)
  with aim assist. Both call `Enemy.hit()`. They're placeholders until the combat system exists.

## How an enemy decides

```
idle --(player inside sight_radius, no give-up timer)--> pursuit
pursuit --(inside attack_range, attack_cd over)--> attack --> pursuit
pursuit --(mood < flee_mood)--> flee
pursuit --(player past lose_radius / gone)--> idle
pursuit --(step_toward says blocked)--> idle, with give_up = give_up_time
pursuit / flee --(gap, wall, water ahead)--> jump | dash | climb | swim | swing --> back to `goal`
any --hit()--> hurt (knockback, no ledge check) --> pursuit
any --stamina 0 / stun_on_hit / stun()--> stun --> idle
any --health 0, KillZone, drowning, 60 m below spawn--> death (frees itself)
level script --start_puppet()--> puppet --end_puppet()--> idle
```

**Reading the ground.** Each step of the chase, `step_toward(point, delta)` calls `probe(dir)`,
which looks just past the body's edge, about 1.3 m at walking speed. The probe ignores the player
and other enemies.

| Probe | What it found | What happens |
|-------|---------------|--------------|
| `open` | ground at most `safe_drop` lower | walk, or run with RUN (costs stamina) |
| `wall` | something steep; its `height`, whether it's `climbable` | CLIMB a climbable wall; JUMP onto it if `height <= jump_height - 0.3`; else blocked |
| `gap` | no ground within `safe_drop`; a `landing` further on | JUMP (solved arc), DASH (level landing), SWING (a SwingPoint overhead); else blocked |
| `water` | deep water over the ground, or below the edge | SWIM walks in; else blocked |

When blocked, the enemy gives up the chase and stays idle for `give_up_time` before trying again.
It never walks off a ledge or into water on its own. Only a push (hurt has no ledge check), a
stun in the air, or a fall can put it there. Flyers (`fly_toward`) climb walls up to
`hover_height + 6` and give up above that.

Jumps are calculated, not simulated. `solve_jump(to)` returns the launch velocity of a full-height
arc to the landing spot, or null when the spot is too high or beyond `jump_reach`. `jump_reach`
includes the run-up from where the probe saw the gap, so the widest gap an enemy clears is about
`jump_reach - 2.2` m.

## Stats (exports on Enemy)

| Group | Exports |
|-------|---------|
| (top) | `abilities` (flags: Jump, Dash, Fly, Run, Climb, Swim, Swing; give a type one or two) |
| Stats | `max_health`, `armor` (0–1, fraction blocked), `weight` (knockback = push / weight; under 1 m/s it doesn't move), `max_stamina`, `stamina_regen`, `max_oxygen`, `oxygen_regen`, `attack_cooldown`, `base_mood`, `flee_mood` (0 = never flees), `invuln_time`, `hurt_time`, `stun_time`, `stun_on_hit` |
| Senses | `sight_radius`, `lose_radius`, `attack_range`, `give_up_time` |
| Ground | `walk_speed`, `run_speed`, `accel`, `safe_drop`, `gravity`, `max_fall_speed`, `fall_damage_speed`, `fall_damage` |
| Moves | `jump_height`, `jump_reach`, `dash_speed`, `dash_distance`, `climb_speed`, `swim_speed`, `fly_speed`, `hover_height` |
| Costs | `run_cost`, `fly_cost` (per second), `dash_cost`, `attack_cost` |
| Attack | `attack_damage`, `attack_windup`, `attack_recover`, `attack_reach` |
| Look | `color` (tints the placeholder body), `show_debug` (state and stats on a label) |

Walking is the baseline and isn't an ability. A FLY enemy doesn't walk: it hovers and only
touches the ground when stunned. Mood is 0–1 aggression. It goes up 0.1 when the enemy lands a
hit, down 0.15 when it gets hurt, and drifts back to `base_mood` while idle, fleeing or stunned.

## Making an enemy type

1. **Scene**: Scene > New Inherited Scene from `enemy/enemy.tscn`, saved as
   `enemy/<type>/<type>.tscn`.
2. **Tune** the exports. That's all `enemy/runner/runner.tscn` does: RUN + JUMP, weight 3, and so
   on, with no script.
3. **Play a state differently** with a subclass that replaces the state script. This is
   `enemy/burrower/burrower.gd`:

   ```gdscript
   class_name Burrower
   extends Enemy

   func _init() -> void:
   	states[&"pursuit"] = preload("burrow_pursuit.gd").new() # dig, travel underground, surface
   	states[&"attack"] = preload("burrow_attack.gd").new()   # the surfacing burst, then stun
   ```

   A state script `extends EnemyState`, uses `e` for the enemy, and returns the next state's name.
   Useful helpers: `e.step_toward(point, delta)` (traversal with the ledge rules),
   `e.hold(delta)` (stop in place; flyers hover), `e.has_target()`, `e.dist_to_target()`,
   `e.face(point)`, `e.spend(stamina)`, `e.cast(from, to)` (a terrain ray),
   `e.deep_water_at(ground)`. To stun from inside a state, set `e.stun_for` and return `&"stun"`.
   Call `e.stun(seconds)` from outside.
4. **Emit cues** for anything sound or VFX should react to: `e.cue.emit(&"my_event")`.
5. **Test it**: add a section to `tests/enemy_test.gd`. `_enemy(at, {prop = value}, MY_SCENE)`
   spawns one on a course built with `_course()`, `_box()`, `_water()` and `_kill()`. Run one
   section with `-- my_section`.

Size note (`ponytail:`): `Enemy.HALF_HEIGHT` (0.8) and `HEAD` (0.6) are constants that assume
the 1.6 m capsule. The probe, water depth and jump solve all use them. Turn them into exports when
an enemy of another size shows up.

## Hooking up presentation

Gameplay never waits on presentation. Code drives all motion (no root motion), and timings live
in exports (`attack_windup`, `hurt_time`, `stun_time`...). Presentation only *reads* three
things:

- **`anim: StringName`**: what the enemy is doing right now. States set it every frame. Poll it.
- **`cue(name)`**: one-shot events (signal).
- **`died(cause)`**: `&"fall"`, `&"drown"` or `&"hit"`. The enemy frees itself after its death
  state (fall 1 s, drown 2.5 s, hit 1.5 s).

### `anim` values

| `anim` | Set by |
|--------|--------|
| `idle`, `fly` (a flyer idling) | idle |
| `walk`, `run` | pursuit / flee moving on open ground |
| `blocked` | the frame a chase gives up |
| `attack_windup`, `attack`, `attack_recover` | attack (base melee) |
| `hurt` | hurt (knockback) |
| `stun` | stun (resting / dropped) |
| `flee`, `cower` | flee (running / cornered or recovering far away) |
| `jump`, `fall` | jump state (a solved jump / a plain fall) |
| `dash`, `climb`, `swim`, `swing` | the move states |
| `flail` | a non-swimmer in deep water |
| `death_fall`, `death_drown`, `death_hit` | death |
| `burrow_in`, `burrowed`, `surface` | burrower only |

The player sets `p.anim` the same way, and it gained `melee`.

### `cue` names

`attack_windup`, `attack`, `hurt`, `stun`, `jump`, `land`, `dash`, `swing`, `blocked`, `death`,
plus the burrower's `burrow_in` and `surface`.

### Animations

Replace the placeholder `_animate()` (it squashes and tilts `Visual`) with an `AnimationTree`:

1. Add an `AnimationPlayer` with clips named after the `anim` values, and an `AnimationTree`
   whose root is an `AnimationNodeStateMachine` with one state per clip.
2. Set the tree's **callback mode to Physics**. States change in the physics tick, and physics
   interpolation smooths the rest.
3. Poll `anim` each physics frame and travel when it changes (see the presenter below). Override
   `_animate()` in the type's script with an empty function so the placeholder stops touching
   `Visual`.
4. Timed clips (windup, recover, stun) should be authored to the export's length, or scaled:
   `anim_tree.set("parameters/<state>/TimeScale/scale", clip_length / e.attack_windup)`.
5. Variants (a tired idle, a hurt-limp run) can read `e.health / e.max_health`, `e.mood` or
   `e.stamina` as blend parameters. The player's `idle_anim()` does the same with temperature,
   health and mood.

### Custom skeletal meshes

1. Import the `.glb` and instance it under `Visual`, replacing `Body` and `Nose`. The burrower's
   `Mound` is a separate mesh: keep it or swap it for a dirt effect.
2. **Forward is −Z.** The enemy turns its whole body toward `facing` (`_orient`).
3. **Feet at `Visual`'s origin.** `Visual` sits at y = −0.8, which is where the feet are.
   Scale the model to fit the capsule, radius 0.4 and height 1.6.
4. **The `CollisionShape3D` stays the gameplay shape.** The mesh is never used for collision.
5. **Attach points**: add `BoneAttachment3D` nodes for the hand, mouth or muzzle, with a
   `Marker3D` inside. Attack checks still use `attack_reach` from the body centre. An enemy that
   shoots later spawns a `Projectile` at its muzzle marker.
6. `color` only tints the placeholder material. A real mesh ignores it.

### Sound and VFX

Give each enemy scene one presenter child that listens and never changes gameplay state:

```gdscript
# enemy/enemy_presenter.gd: a child of an enemy scene
extends Node

@export var anim_tree: AnimationTree
@export var sounds: Dictionary[StringName, AudioStreamPlayer3D] = {} # cue name -> player
@export var effects: Dictionary[StringName, GPUParticles3D] = {}     # cue name -> one-shot particles
@export var death_effect: PackedScene                                 # spawned detached

@onready var enemy: Enemy = get_parent()
var _anim: StringName


func _ready() -> void:
	enemy.cue.connect(_on_cue)
	enemy.died.connect(_on_died)


func _physics_process(_delta: float) -> void:
	if anim_tree and enemy.anim != _anim:
		_anim = enemy.anim
		(anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).travel(_anim)


func _on_cue(name: StringName) -> void:
	if name in sounds:
		sounds[name].play()
	if name in effects:
		effects[name].restart()


func _on_died(_cause: StringName) -> void:
	if death_effect: # the enemy frees itself soon, so the effect must not be its child
		var fx: Node3D = death_effect.instantiate()
		enemy.get_parent().add_child(fx)
		fx.global_position = enemy.global_position
```

- **Footsteps and swooshes** belong on animation tracks (Audio or Call Method tracks in the
  clips), so they line up with the feet. Cues are for gameplay moments.
- **Looping sounds** (flying buzz, underground rumble) can follow `anim` in the presenter:
  start on `fly`/`burrowed`, stop otherwise.
- **3D audio**: use `AudioStreamPlayer3D` children so sound pans and fades with the camera.
- **Shots**: `world/projectile.tscn`'s `Mesh` child is the slot for the bullet look (a trail,
  emissive mesh, particles). For impacts, add an `impact` PackedScene export to `Projectile` and
  spawn it detached in `_finish()` before `queue_free()`.
- **Player**: the player's placeholder `_animate()` handles `melee` the same way, and the same
  presenter pattern works there (`anim` plus its own signals).
