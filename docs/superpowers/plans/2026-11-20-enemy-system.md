# Enemy System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An enemy backbone (shared states, stats, reactive traversal with seven abilities), minimal player melee + shooting, a runner and a burrower, a demo scene, and a guide for hooking up animation, meshes, sound and VFX.

**Architecture:** `Enemy` is a `CharacterBody3D` built like `Player`: one `RefCounted` script per state in `enemy/states/`, `physics(delta)` returns the next state's name. Pursuit reads the ground ahead each frame (`probe`) and either moves, hands off to a move state (jump, dash, climb, swim, swing), or gives up. Enemy types are inherited scenes of `enemy/enemy.tscn` that tune exports and may replace state scripts in `_init()`.

**Tech Stack:** Godot 4.7.2 GDScript, Jolt physics, headless `SceneTree` test scripts.

**Spec:** `docs/superpowers/specs/2026-11-20-enemy-system-design.md`

## Global Constraints

- Godot `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` only (not the 4.5/4.6 exes next to it).
- Static typing and `##` doc comments throughout; `ponytail:` comment on every deliberate shortcut.
- Every new script gets its `.uid` sidecar committed. Run the editor once after adding `class_name` scripts (`--editor --quit-after 400`): it writes the `.uid` files and registers the class for `-s` tests.
- `Enemy`, `EnemyState`, `Burrower` and `Projectile` must never reference the `World` autoload (they're compiled by `-s` scripts before autoloads exist).
- Use player-style motion: `vspeed()`, `set_vspeed()`, `planar()` and `up_direction`, never `velocity.y` or `Vector3.UP` in gameplay code (tests may use world axes).
- Don't touch `demo/demo.tscn`, `demo/builder/`, the user's uncommitted material files (`demo/materials/**`) or `.godot/editor/editor_layout.cfg`. Stage files by explicit path, never `git add -A`.
- Every Godot run goes through `timeout`, because a script error hangs Godot. Shell preamble for all commands below:
  ```sh
  GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
  NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"
  ```
- Enemy suite command (referred to as **RUN ENEMIES**):
  `timeout 400 "$GODOT" --headless --path . -s res://tests/enemy_test.gd 2>&1 | grep -viE "$NOISE"`
  It passes when the last line is `ENEMIES: OK`. A new test calling a missing method fails as a parse error, which shows up as an error line, or as a timeout (exit 124) with no `ENEMIES:` line.
- Report every result as "headless only, game feel untested".

## Review Focus

1. Two enemies chasing the same player bump into each other → both keep chasing; neither gives up (Task 2 test "two chasers").
2. Target straight above the enemy (player standing on its head) → no zero-length `normalized()` NaN, no crash (Task 2).
3. Target dies or is freed mid-chase → enemies go idle without errors (Task 2).
4. Hits on a dying or dead enemy (a second projectile, a melee into the corpse) → ignored, `died` emitted once (Task 3).
5. Environment changes mid-chase (mud EnvZone) → chase speed scales like the player's (Task 2).

---

### Task 1: Enemy body, base scene, idle/death/falling, zones reach enemies, test harness

**Files:**
- Create: `enemy/enemy.gd`, `enemy/enemy_state.gd`, `enemy/enemy.tscn`, `enemy/states/idle.gd`, `enemy/states/death.gd`, `enemy/states/jump.gd`, `tests/enemy_test.gd`
- Modify: `player/player.gd` (`_ready`: `add_to_group(&"player")`), `world/zone.gd` (`_on_body_entered/_exited`), `world/env_zone.gd`, `world/kill_zone.gd`

**Interfaces (Produces, used by every later task):**
- `class_name Enemy extends CharacterBody3D`
  - signals `died(cause: StringName)`, `cue(name: StringName)`, `puppet_arrived`
  - `enum Ability { JUMP = 1, DASH = 2, FLY = 4, RUN = 8, CLIMB = 16, SWIM = 32, SWING = 64 }`, `@export_flags("Jump", "Dash", "Fly", "Run", "Climb", "Swim", "Swing") var abilities := 0`
  - consts `HALF_HEIGHT := 0.8`, `HEAD := 0.6` (head above body centre), `KILL_DEPTH := 60.0`, `MIN_KNOCK := 1.0`
  - exports (all declared now; later tasks use them). Stats: `max_health := 50.0`, `armor := 0.0` (`@export_range(0, 1)`), `weight := 5.0`, `max_stamina := 100.0`, `stamina_regen := 25.0`, `max_oxygen := 4.0`, `oxygen_regen := 4.0`, `attack_cooldown := 1.2`, `base_mood := 0.6`, `flee_mood := 0.2`, `invuln_time := 0.3`, `hurt_time := 0.35`, `stun_time := 2.0`, `stun_on_hit := 0.0`. Senses: `sight_radius := 10.0`, `lose_radius := 16.0`, `attack_range := 1.6`, `give_up_time := 1.5`. Ground: `walk_speed := 3.0`, `run_speed := 6.0`, `accel := 40.0`, `safe_drop := 1.2`, `gravity := 32.0`, `max_fall_speed := 30.0`, `fall_damage_speed := 18.0`, `fall_damage := 2.0` (health per m/s over the threshold). Moves: `jump_height := 1.8`, `jump_reach := 4.0`, `dash_speed := 14.0`, `dash_distance := 4.0`, `climb_speed := 2.5`, `swim_speed := 3.0`, `fly_speed := 5.0`, `hover_height := 2.5`. Costs: `run_cost := 20.0`, `fly_cost := 10.0`, `dash_cost := 25.0`, `attack_cost := 15.0`. Attack: `attack_damage := 10.0`, `attack_windup := 0.35`, `attack_recover := 0.4`, `attack_reach := 1.8`. Look: `color := Color(0.85, 0.25, 0.2)`, `show_debug := true`.
  - runtime: `health`, `stamina`, `oxygen`, `mood: float`; `invuln`, `attack_cd`, `give_up: float`; `stun_for := 0.0`; `goal: StringName = &"idle"` (state a move returns to); `launch := Vector3.ZERO` (jump state applies it on enter); `move_to := Vector3.ZERO`; `swing_point: SwingPoint`; `target: Player`; `home: Vector3`; `facing := Vector3.FORWARD`; `anim: StringName = &"idle"`; `death_cause: StringName`; `env: EnvProfile`; `water_zone: EnvZone`; `puppet_target: Variant = null`; `states: Dictionary[StringName, EnemyState]`; `state: EnemyState`; `state_name: StringName`
  - `change_state(next: StringName) -> void`, `can(a: int) -> bool`
  - motion: `vspeed() -> float`, `set_vspeed(v: float) -> void`, `planar() -> Vector3`, `move_planar(dir: Vector3, speed: float, delta: float) -> void` (accelerates toward `dir * speed * mult(&"speed")` at `accel * mult(&"traction")`, updates `facing`), `apply_gravity(delta: float) -> void` (single gravity, no fall multiplier: `gravity * env.gravity_mult`, plus wind lift and `env.drag` damping, capped at `max_fall_speed`), `hold(delta: float, fall := false) -> void` (stop in place: planar slows to 0; ground enemies, or any enemy when `fall`, get gravity; a flyer otherwise settles toward `hover_height` above the ground below it; then `move_and_slide()`)
  - env: `mult(stat: StringName) -> float` (= `maxf(0, 1 + env.mods.get(stat))`), `add_env(e: EnvProfile)`, `remove_env(e: EnvProfile)` (same `EnvProfile.combine` pattern as Player, base `EnvProfile.new()`), `water_depth() -> float` (-INF outside water), `deep_water() -> bool` (`water_depth() > HEAD`), `flail(delta: float) -> bool`. That last one: when the enemy can't SWIM and is in deep water, set `anim = &"flail"`, `hold(delta, true)` and return true. Idle, pursuit and flee call it first and return `&""` when it's true.
  - stamina: `spend(amount: float) -> void` (lowers stamina, marks it drained this frame, which blocks regen next frame)
  - target: `has_target() -> bool` (re-fetches `get_tree().get_first_node_in_group(&"player")` when `target` isn't a valid instance; false when none or the player's `state_name` is `death` or `puppet`), `target_pos() -> Vector3`, `dist_to_target() -> float` (3D)
  - `die(cause: StringName) -> void` (ignored if already dead; sets `death_cause`, `health = 0`, `collision_layer = 0` with the mask kept so the body still lands, emits `cue(&"death")` and `died(cause)`, then `change_state(&"death")`)
- `class_name EnemyState extends RefCounted`: `var e: Enemy`, `enter(_prev: StringName)`, `exit()`, `physics(_delta: float) -> StringName`
- `enemy/enemy.tscn`: root `Enemy` (CharacterBody3D, script `enemy.gd`), `Collision` (CapsuleShape3D radius 0.4, height 1.6), `Visual` (Node3D at y -0.8) → `Body` (CapsuleMesh 0.4/1.6 at y 0.8, StandardMaterial3D `resource_local_to_scene = true`) and `Nose` (BoxMesh 0.2×0.2×0.3 at y 1.2, z -0.42). `_ready` applies `color` to the Body material.
- Zones: `Zone._enemy_entered(_e: Enemy)` / `_enemy_exited(_e: Enemy)` virtuals. `EnvZone` adds/removes its profile and sets/clears `e.water_zone` for water, exactly as for the player. `KillZone` calls `e.die(cause)`.
- Test harness in `tests/enemy_test.gd` (later tasks add `_test_*` sections): `var course: Node3D`, `var player: Player`, `var sections := 0`, and helpers:
  - `_course(player_at := Vector3(-30, 1, 0), with_floor := true) -> void`: removes the old course from `root` (`remove_child` + `queue_free`, so the old player leaves its group at once) and builds a new one. It contains a void KillZone at `(0, -15, 0)` sized `(200, 2, 200)`; with `with_floor`, a floor box at `(0, -0.5, 0)` sized `(80, 1, 30)` (top y = 0); a pad box `(4, 1, 4)` centred at `player_at - (0, 1.5, 0)`; and a `player.tscn` instance at `player_at`.
  - `_box(at: Vector3, size: Vector3, climbable := false) -> CSGBox3D` (centre `at`, `use_collision`, group `climbable` if asked)
  - `_water(at: Vector3, size: Vector3) -> EnvZone` (box shape via `add_shape`; profile `water = true`, `gravity_mult = 0.3`, `drag = 1.2`, like the demo's "Underwater")
  - `_kill(at: Vector3, size: Vector3) -> KillZone`
  - `_enemy(at: Vector3, props := {}, scene: PackedScene = ENEMY) -> Enemy`: sets `show_debug = false`, then each prop via `set()`, then `position`, *before* `add_child` so `_ready` sees them.
  - `_deaths(e: Enemy) -> Array` (connects `died`, returns the array the causes land in)
  - `_gone(e: Object, frames: int) -> bool` (awaits until the object is freed)
  - `_wait(frames: int)`, `_wait_until(cond: Callable, frames: int) -> bool`
  - `_watch(enemies: Array, frames: int) -> Array[StringName]` (distinct `state_name`s seen, in order of first appearance; skips freed enemies)
  - `_check(ok: bool, what: String)` (same output as the other suites)
  - `_run()` awaits each section, then `_check(sections == SECTIONS, "all sections ran")` (a script error inside a section silently ends its `await`), then `print("ENEMIES: ", ...)` and `quit(fails)`.

- [ ] **Step 1: Branch and commit the spec**

```bash
git switch -c feature/enemy-system
git add docs/superpowers/specs/2026-11-20-enemy-system-design.md docs/superpowers/plans/2026-11-20-enemy-system.md
git commit -m "docs: enemy system design and plan"
```

- [ ] **Step 2: Write the harness and `_test_core` (SECTIONS = 1)**

```gdscript
func _test_core() -> void:
	_course()
	var e := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0})
	await _wait(30)
	_check(e.state_name == &"idle" and e.is_on_floor(), "enemy settles idle on the floor")
	_check(e.health == e.max_health and e.stamina == e.max_stamina and e.oxygen == e.max_oxygen and e.mood == e.base_mood, "stats start full")
	_check(e.is_in_group(&"enemy") and player.is_in_group(&"player") and e.has_target() and e.target == player, "groups; the player is the target")
	var mud := EnvProfile.new()
	mud.mods.speed = -0.5
	e.add_env(mud)
	_check(is_equal_approx(e.mult(&"speed"), 0.5), "env stat mods reach enemies")
	e.remove_env(mud)

	_kill(Vector3(10, 0.5, 0), Vector3(3, 1, 3))
	var faller := _enemy(Vector3(10, 4, 0), {sight_radius = 0.0})
	var causes := _deaths(faller)
	var seen := await _watch([faller], 10)
	_check(&"jump" in seen, "airborne enemies are in the jump state")
	_check(await _gone(faller, 240) and causes == [&"fall"], "kill zone: death by fall, then freed")

	_water(Vector3(-10, 1.5, 0), Vector3(4, 3, 4))
	var sinker := _enemy(Vector3(-10, 1, 0), {sight_radius = 0.0, max_oxygen = 1.0})
	causes = _deaths(sinker)
	await _wait(10)
	_check(sinker.anim == &"flail" and sinker.oxygen < sinker.max_oxygen, "non-swimmer in deep water flails, oxygen drains")
	_check(await _gone(sinker, 300) and causes == [&"drown"], "non-swimmer drowns")

	var lost := _enemy(Vector3(20, 1, 0), {sight_radius = 0.0})
	causes = _deaths(lost)
	await _wait(5)
	lost.global_position = lost.home - Vector3(0, Enemy.KILL_DEPTH + 1.0, 0)
	await _wait(3)
	_check(causes == [&"fall"], "60 m below its spawn = death by fall")
	sections += 1
```

- [ ] **Step 3: Run it to make sure it fails**

Run: **RUN ENEMIES**. Expected: a load error for `res://enemy/enemy.tscn` / unknown `Enemy`, or a timeout. No `ENEMIES: OK`.

- [ ] **Step 4: Implement**

- `enemy_state.gd`, `enemy.gd`, `enemy.tscn` per the Interfaces block. `_ready`: stats full, `mood = base_mood`, `home = global_position`, `add_to_group(&"enemy")`, `env = EnvProfile.combine(EnvProfile.new(), _envs)`, back-references `s.e = self`, a debug `Label3D` child at y 1.3 (billboard, no depth test) if `show_debug`, then `change_state(&"idle")`. `states` member default preloads `idle`, `death`, `jump` (later tasks add entries here).
- `_physics_process`: count down the timers; stamina regen unless drained last frame; oxygen drains while `water_depth() > HEAD`, with `die(&"drown")` at 0, otherwise regen; mood drifts toward `base_mood` at 0.05/s while in `idle`, `flee` or `stun`; `die(&"fall")` when more than `KILL_DEPTH` below `home` along `up_direction`; run `state.physics`; `_orient(delta)` (player's slerp to `Basis.looking_at(facing, up_direction)`, facing kept planar); `_animate(delta)` placeholder squash/tilt of `Visual` per `anim` (`ponytail:` replace with AnimationTree); update the debug label (`state`, hp, stamina, mood, oxygen).
- `idle`: `flail` first; if not on floor and not FLY, set `goal = &"idle"` and return `&"jump"`; else `hold(delta)`, `anim = &"idle"` (`&"fly"` for flyers). Pursuit hand-off comes in Task 2.
- `jump` (airborne): on enter apply `launch` if non-zero (`cue(&"jump")`, `anim = &"jump"`), then clear it; otherwise `anim = &"fall"`. Physics: `apply_gravity`, `move_and_slide`. Once it has been in the air for at least 0.05 s and `is_on_floor()`, emit `cue(&"land")` and return `goal`.
- `death`: durations `{fall = 1.0, drown = 2.5, hit = 1.5}`, `anim = "death_" + cause`, `hold(delta, true)` each frame, `queue_free()` at the end.
- Zone hooks as in Interfaces. `Player._ready` gets `add_to_group(&"player")`.

- [ ] **Step 5: Register classes, then run**

Run: `timeout 150 "$GODOT" --headless --path . --editor --quit-after 400 2>&1 | grep -viE "$NOISE"` (no script errors), then **RUN ENEMIES**. Expected: every check `ok`, last line `ENEMIES: OK`.

- [ ] **Step 6: Existing suites still pass**

Run the smoke test and the puzzle test from CLAUDE.md. Expected: `SMOKE: OK`, `PUZZLES: OK`.

- [ ] **Step 7: Commit**

```bash
git add enemy/ tests/enemy_test.gd player/player.gd world/zone.gd world/env_zone.gd world/kill_zone.gd
git commit -m "feat(enemy): enemy body, idle/death/falling, zones reach enemies"
```

---

### Task 2: Senses, ground probe, pursuit, giving up

**Files:**
- Create: `enemy/states/pursuit.gd`
- Modify: `enemy/enemy.gd` (probe, `step_toward`, `water_at`), `enemy/states/idle.gd` (aggro), `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - inner class `Enemy.Probe`: `kind: StringName` (`&"open"`, `&"wall"`, `&"gap"`, `&"water"`), `height := 0.0` (wall top above the feet; `INF` when too tall to measure), `climbable := false`, `point := Vector3.ZERO` (wall hit point, or the probed edge point at feet height), `normal := Vector3.ZERO` (wall normal), `landing: Variant = null` (gap: far-side feet point or null)
  - `probe(dir: Vector3) -> Enemy.Probe`
  - `find_landing(dir: Vector3, near: float, far: float) -> Variant`: the first ground point, sampled every 0.5 m from `near` to `far` along `dir`, that isn't deep water; or null
  - `water_at(point: Vector3) -> EnvZone`: point query with `collide_with_areas`; returns the EnvZone whose profile has `water`, or null
  - `step_toward(point: Vector3, delta: float) -> StringName`: returns `&""` after moving, a move state name (later tasks), or `&"blocked"`. When it returns a move state it sets `goal = state_name` first.

- [ ] **Step 1: Write `_test_pursuit` (SECTIONS = 2)**

```gdscript
func _far_side(kind: String) -> void: # home plateau ends at x = 0; the player waits at x = 10
	match kind:
		"gap": _box(Vector3(10, -0.5, 0), Vector3(12, 1, 10)) # 4 m gap
		"wall":
			_box(Vector3(8, -0.5, 0), Vector3(16, 1, 10))
			_box(Vector3(2, 1.5, 0), Vector3(1, 3, 10)) # 3 m wall
		"water":
			_box(Vector3(8, -0.5, 0), Vector3(16, 1, 10))
			_water(Vector3(3, 1.5, 0), Vector3(4, 3, 10)) # 3 m deep over the floor
		"cliff": _box(Vector3(8, -2.5, 0), Vector3(16, 1, 10)) # 2 m drop, beyond safe_drop
		"step": _box(Vector3(8, -1.5, 0), Vector3(16, 1, 10)) # 1 m drop, within safe_drop


func _test_pursuit() -> void:
	_course(Vector3(-30, 1, 0))
	var e := _enemy(Vector3(-20, 1, 0), {sight_radius = 8.0, lose_radius = 14.0, attack_damage = 0.0})
	await _wait(20)
	_check(e.state_name == &"idle", "idle while the player is outside sight_radius")
	player.teleport(Vector3(-26, 1, 0))
	_check(await _wait_until(func() -> bool: return e.state_name == &"pursuit", 10), "pursuit once the player is inside sight_radius")
	await _wait(20)
	_check(absf(e.planar().length() - e.walk_speed) < 0.2, "chases at walk_speed without RUN")
	_check(await _wait_until(func() -> bool: return e.dist_to_target() < e.attack_range, 180) and e.state_name != &"idle", "closes in without reading the player as a wall") # pursuit, or attack from Task 4 on
	player.teleport(Vector3(0, 1, 0))
	_check(await _wait_until(func() -> bool: return e.state_name == &"idle", 60), "idle once the player is past lose_radius") # an attack under way finishes first

	_course(Vector3(30, 1, 0))
	var chase := {sight_radius = 60.0, lose_radius = 80.0, attack_damage = 0.0, max_stamina = 1000.0}
	var runner := _enemy(Vector3(20, 1, 2), chase.merged({abilities = Enemy.Ability.RUN}, true))
	var other := _enemy(Vector3(20, 1, -2), chase)
	await _wait(20)
	_check(absf(runner.planar().length() - runner.run_speed) < 0.2 and runner.stamina < runner.max_stamina, "RUN chases at run_speed and spends stamina")
	var mud := EnvProfile.new()
	mud.mods.speed = -0.5
	other.add_env(mud)
	await _wait(15)
	_check(absf(other.planar().length() - other.walk_speed * 0.5) < 0.2, "mud halves the chase speed")
	other.remove_env(mud)
	_check(&"idle" not in await _watch([runner, other], 300), "two chasers bump into each other without giving up")

	for kind in ["gap", "wall", "water", "cliff"]:
		_course(Vector3(10, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_far_side(kind)
		var b := _enemy(Vector3(-4, 1, 0), {sight_radius = 30.0, lose_radius = 40.0})
		var stopped := await _wait_until(func() -> bool: return b.state_name == &"idle", 150)
		await _wait(int(b.give_up_time * 60.0) - 15)
		_check(stopped and b.state_name == &"idle", "%s: gives up the chase and waits out give_up_time" % kind)
		await _wait(120)
		_check(is_instance_valid(b) and b.global_position.x < 1.2 and b.global_position.y > 0.5 and b.oxygen == b.max_oxygen, "%s: never crosses or falls in" % kind)
	_course(Vector3(10, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_far_side("step")
	var s := _enemy(Vector3(-4, 1, 0), {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0})
	_check(await _wait_until(func() -> bool: return s.global_position.x > 2.0, 240), "walks down a drop within safe_drop")

	_course(Vector3(-30, 1, 0))
	var under := _enemy(Vector3(0, 1, 0), {sight_radius = 10.0, attack_damage = 0.0})
	await _wait(10)
	player.teleport(Vector3(0, 3.2, 0)) # lands on the enemy's head
	await _wait(60)
	_check(under.global_position.is_finite() and under.velocity.is_finite(), "target straight above: no NaN")
	player.teleport(Vector3(3, 1, 0))
	await _wait(20)
	player.die(&"hit")
	_check(await _wait_until(func() -> bool: return under.state_name == &"idle", 5), "player dead: the chase stops")
	player.get_parent().remove_child(player)
	player.queue_free()
	await _wait(5)
	_check(under.state_name == &"idle" and not under.has_target(), "target freed: idle, no errors")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: parse error (`probe`/`pursuit` missing) or `FAIL ... pursuit once the player is inside sight_radius`.

- [ ] **Step 3: Implement `probe`, `find_landing`, `water_at`**

Rays and shape queries pass `exclude` = this enemy, the target and every node in group `enemy` (their RIDs). That's how probes ignore bodies. `feet = global_position - up * HALF_HEIGHT`, `look = 0.6 + planar().length() * 0.1`, `edge = feet + dir * (0.4 + look)`.

```
probe(dir):
  wall: rays forward from the knees (feet + up*0.3) and the chest (centre), length 0.4 + look.
        A hit with normal.dot(up) < 0.7 is a wall:
          top_from = hit + dir*0.3 + up*(jump_height + 0.5 relative to the feet)
          height = INF if intersect_point(top_from) is inside a body (wall taller than we measure)
                   else (ray down from top_from to feet level -> hit height above feet), INF if no hit
          climbable = collider is in group "climbable"
  ground: ray from edge + up*0.5 down to edge - up*(safe_drop + 0.05).
          hit -> water if water_at(hit + up*0.1) has surface - hit height > HALF_HEIGHT + HEAD, else open
          no hit -> water if water_at(edge - up*0.5) (deep water below the edge),
                    else gap with landing = find_landing(dir, 0.4 + look + 0.5, max(jump_reach, dash_distance))
find_landing: per sample point p = feet + dir*d, ray from p + up*(jump_height + 0.3) down to p - up*safe_drop,
              skipping samples whose start point is inside a body; first hit not in deep water wins.
```

- [ ] **Step 4: Implement `step_toward` (ground branch) and pursuit**

`step_toward(point, delta)`: `dir = (point - global_position).slide(up_direction)`. If its length is under 0.05, `hold(delta)` and return `&""` (Review Focus 2). Otherwise probe along the normalized dir: `open` → `move_planar(dir, run_speed if can(RUN) else walk_speed, delta)`, plus `spend(run_cost * delta)` while running, `apply_gravity`, `move_and_slide`, `anim` `&"run"` or `&"walk"`. `wall`, `gap` and `water` → `hold(delta)`, `anim = &"blocked"`, return `&"blocked"` (Tasks 5 to 7 add the ability branches here).

Pursuit physics, checks in this order: `flail`; target gone or `dist_to_target() > lose_radius` → `&"idle"`; airborne and not FLY → `goal = &"pursuit"`, `&"jump"`; within `attack_range` → `hold(delta)` and face the target (Task 4 turns this into the attack); otherwise `step_toward(target_pos(), delta)`. When that returns `&"blocked"`, set `give_up = give_up_time`, `cue(&"blocked")`, and return `&"idle"`. Idle gets: `has_target() and give_up <= 0 and dist_to_target() <= sight_radius` → `&"pursuit"`. Add `pursuit` to `states`.

- [ ] **Step 5: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): ground probe, pursuit, give up at gaps, walls and water"
```

---

### Task 3: Hits, hurt, stun, exhaustion, fall damage

**Files:**
- Create: `enemy/states/hurt.gd`, `enemy/states/stun.gd`
- Modify: `enemy/enemy.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `hit(damage: float, push: float, from: Vector3) -> void`, `stun(seconds: float) -> void` (sets `stun_for`, emits `cue(&"stun")`, `change_state(&"stun")`; for use from *outside* a state's physics). Inside a state, set `e.stun_for` and return `&"stun"`.

- [ ] **Step 1: Write `_test_combat` (SECTIONS = 3)**

```gdscript
func _test_combat() -> void:
	_course(Vector3(-30, 1, 0))
	var a := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0, max_health = 100.0, armor = 0.5, weight = 2.0})
	await _wait(10)
	a.hit(20.0, 20.0, a.global_position - Vector3(1, 0, 0))
	_check(is_equal_approx(a.health, 90.0), "armor 0.5 halves damage")
	_check(a.state_name == &"hurt" and absf(a.planar().length() - 10.0) < 0.5 and a.planar().x > 0.0, "knockback = push / weight, away from the hit")
	_check(a.mood < a.base_mood, "getting hurt lowers mood")
	a.hit(20.0, 20.0, a.global_position)
	_check(is_equal_approx(a.health, 90.0), "hits inside invuln_time are ignored")
	var heavy := _enemy(Vector3(0, 1, 5), {sight_radius = 0.0, weight = 40.0})
	await _wait(10)
	heavy.hit(5.0, 20.0, heavy.global_position - Vector3(1, 0, 0))
	await _wait(1)
	_check(heavy.planar().length() < 0.1 and heavy.health < heavy.max_health, "push / weight under 1 m/s: hurt but not moved")
	var causes := _deaths(heavy)
	await _wait(30)
	heavy.hit(999.0, 0.0, heavy.global_position)
	_check(causes == [&"hit"] and heavy.collision_layer == 0, "health 0: death by hit, body drops out of collision")
	heavy.hit(999.0, 0.0, heavy.global_position)
	_check(causes == [&"hit"], "hits on a dead enemy are ignored")

	_course(Vector3(-20, 1, 0), false)
	_box(Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	var shoved := _enemy(Vector3(2, 1, 0), {sight_radius = 0.0, weight = 2.0})
	causes = _deaths(shoved)
	await _wait(10)
	shoved.hit(1.0, 24.0, shoved.global_position - Vector3(1, 0, 0))
	_check(await _gone(shoved, 240) and causes == [&"fall"], "a push carries it off the ledge into the pit")

	_course(Vector3(-30, 1, 0))
	var high := _enemy(Vector3(0, 14, 0), {sight_radius = 0.0})
	var low := _enemy(Vector3(4, 2.5, 0), {sight_radius = 0.0})
	await _wait(120)
	_check(high.health < high.max_health and low.health == low.max_health, "hard landings cost health, short drops don't")

	_course(Vector3(30, 1, 0))
	var tired := _enemy(Vector3(0, 1, 0), {abilities = Enemy.Ability.RUN, max_stamina = 20.0, run_cost = 20.0, stun_time = 1.0, sight_radius = 60.0, lose_radius = 80.0})
	_check(await _wait_until(func() -> bool: return tired.state_name == &"stun", 120), "running out of stamina stuns")
	await _wait(5)
	_check(tired.planar().length() < 0.2 and tired.anim == &"stun", "a stunned ground enemy rests in place")
	_check(await _wait_until(func() -> bool: return tired.state_name != &"stun", 70) and tired.stamina == tired.max_stamina, "stun ends after stun_time with full stamina")

	_course(Vector3(-30, 1, 0))
	var s := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0})
	await _wait(10)
	s.stun(1.0)
	await _wait(30)
	s.hit(1.0, 0.0, s.global_position)
	_check(s.state_name == &"stun", "a hit during a stun doesn't end it")
	_check(await _wait_until(func() -> bool: return s.state_name != &"stun", 40), "...or restart it")
	var dizzy := _enemy(Vector3(0, 1, 4), {sight_radius = 0.0, stun_on_hit = 1.0})
	await _wait(10)
	dizzy.hit(1.0, 0.0, dizzy.global_position)
	_check(dizzy.state_name == &"stun", "stun_on_hit: a hit stuns instead of hurting")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: parse error (`hit`/`stun` not found).

- [ ] **Step 3: Implement**

- `hit()` follows the spec's "Damage and death API" in this order: ignore if dead, in `puppet`, or `invuln > 0`; `invuln = invuln_time`; `health -= damage * (1 - armor)`; `mood = maxf(mood - 0.15, 0)`; `cue(&"hurt")`; health ≤ 0 → `die(&"hit")` and return; `knock = push / weight`; `away = (global_position - from).slide(up)` normalized (fall back to `-facing`); `knock >= MIN_KNOCK` → `velocity = away * knock + up * knock * 0.4`. Then: if stunned, stay stunned; else if `stun_on_hit > 0`, `stun(stun_on_hit)`; else `change_state(&"hurt")` (a flinch in place when there's no knock).
- `hurt`: `anim = &"hurt"`, lasts `hurt_time`; planar slows at 8 m/s², gravity, `move_and_slide`, **no probe**. At the end: airborne and not FLY → `goal = &"pursuit"`, `&"jump"`; otherwise `&"pursuit"` if `has_target()`, else `&"idle"`.
- `stun`: `anim = &"stun"`, timer `stun_for`, `hold(delta, true)`. At the end `stamina = max_stamina`, return `&"idle"`.
- In `_physics_process`, before the state runs: `stamina <= 0` and the state isn't `stun`, `death` or `puppet` → `stun(stun_time)`.
- Fall damage: while airborne, keep the fastest downward speed; on landing, if it's above `fall_damage_speed`, lose `(speed - fall_damage_speed) * fall_damage` health (`die(&"fall")` at 0).
- Add `hurt` and `stun` to `states`.

- [ ] **Step 4: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 5: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): hit with armor and weight, hurt, stun, exhaustion, fall damage"
```

---

### Task 4: Attack, mood, flee, puppet

**Files:**
- Create: `enemy/states/attack.gd`, `enemy/states/flee.gd`, `enemy/states/puppet.gd`
- Modify: `enemy/enemy.gd`, `enemy/states/pursuit.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Tasks 1–3; `Player.damage(amount: float, from: Variant)`.
- Produces: `start_puppet(at: Vector3) -> void`, `end_puppet() -> void` (to idle); base `attack` state (other types replace it).

- [ ] **Step 1: Write `_test_attack_flee` (SECTIONS = 4)**

```gdscript
func _test_attack_flee() -> void:
	_course(Vector3(0, 1, 0))
	var e := _enemy(Vector3(3, 1, 0), {sight_radius = 10.0, attack_damage = 10.0, attack_cooldown = 1.5})
	var cues := []
	e.cue.connect(func(n: StringName) -> void: cues.append(n))
	var hp := player.health
	_check(await _wait_until(func() -> bool: return player.health < hp, 120), "attacks once in range")
	_check(player.health == hp - 10.0 and &"attack_windup" in cues and &"attack" in cues, "windup, strike for attack_damage, cues")
	_check(e.mood > e.base_mood and e.stamina < e.max_stamina, "a landed hit raises mood; attacking costs stamina")
	hp = player.health
	var frames := 0
	while player.health == hp and frames < 300:
		await _wait(1)
		frames += 1
	_check(frames >= int(e.attack_cooldown * 60.0), "the next strike waits out attack_cooldown (%d frames)" % frames)

	_course(Vector3(-30, 1, 0))
	var calm := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0, base_mood = 0.6})
	await _wait(5)
	calm.mood = 0.3
	await _wait(120)
	_check(calm.mood > 0.3 and calm.mood <= 0.6, "mood drifts back toward base_mood while idle")

	_course(Vector3(-5, 1, 0))
	var coward := _enemy(Vector3(0, 1, 0), {sight_radius = 20.0, lose_radius = 30.0, base_mood = 0.3, flee_mood = 0.2, attack_damage = 0.0})
	await _wait(10)
	coward.hit(1.0, 0.0, player.global_position)
	_check(await _wait_until(func() -> bool: return coward.state_name == &"flee", 30), "mood under flee_mood: flees")
	var d0 := coward.dist_to_target()
	await _wait(60)
	_check(coward.dist_to_target() > d0 + 2.0, "fleeing opens distance")

	_course(Vector3(-4, 1, 0), false)
	_box(Vector3(0, -0.5, 0), Vector3(10, 1, 6))
	var cornered := _enemy(Vector3(3, 1, 0), {sight_radius = 20.0, base_mood = 0.1, flee_mood = 0.2, attack_damage = 5.0})
	await _wait(120)
	_check(is_instance_valid(cornered) and cornered.global_position.y > 0.5 and cornered.state_name == &"flee", "cornered at the edge: holds its ground")
	player.teleport(cornered.global_position - Vector3(1.2, 0, 0))
	hp = player.health
	_check(await _wait_until(func() -> bool: return player.health < hp, 120), "cornered: attacks when the player comes close")

	_course(Vector3(-3, 1, 0))
	var actor := _enemy(Vector3(0, 1, 0), {sight_radius = 20.0})
	await _wait(5)
	var arrived := []
	actor.puppet_arrived.connect(func() -> void: arrived.append(true))
	actor.start_puppet(Vector3(6, 0, 0))
	var hp2 := actor.health
	actor.hit(10.0, 10.0, actor.global_position)
	_check(actor.health == hp2, "puppet ignores hits")
	var seen := await _watch([actor], 150)
	_check(arrived.size() == 1 and seen == [&"puppet"] and actor.global_position.x > 5.5, "puppet walks to its mark, ignores the player, emits puppet_arrived")
	actor.end_puppet()
	await _wait(2)
	_check(actor.state_name != &"puppet", "end_puppet hands back to the AI")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: parse error (`start_puppet` not found).

- [ ] **Step 3: Implement**

- `attack`: aborts to `&"idle"` on any frame the target is gone (`has_target()` false), so a dead or freed player stops it at once. Phases: windup (`attack_windup`, `anim = &"attack_windup"`, `cue(&"attack_windup")`, `hold`, face the target), strike (one check: target within `attack_reach` and `facing.dot(to_target_planar) > 0.5` → `target.damage(attack_damage, global_position)`, `mood = minf(mood + 0.1, 1)`; `cue(&"attack")` either way; `spend(attack_cost)`), recover (`attack_recover`, `anim = &"attack_recover"`), then `attack_cd = attack_cooldown` and return `&"pursuit"`.
- Pursuit: after the lose check add `mood < flee_mood` → `&"flee"`; in range with `attack_cd <= 0` → `&"attack"` (on cooldown it holds, as before).
- `flee`: `flail` first; airborne → `goal = &"flee"`, `&"jump"`; target gone or (`dist_to_target() > lose_radius` and `mood > flee_mood + 0.2`) → `&"idle"`. Otherwise `step_toward(global_position + away * 4.0, delta)` with `anim = &"flee"`. On `&"blocked"` it's cornered: hold, face the target, `anim = &"cower"`, and return `&"attack"` when in range with `attack_cd <= 0`.
- `puppet` / `start_puppet` / `end_puppet`: like the player's (planar distance < 0.3 → emit `puppet_arrived`, stop). Uses `move_planar` at `walk_speed`, gravity, no probe. `hit` is already ignored in puppet (Task 3).
- Add `attack`, `flee`, `puppet` to `states`.

- [ ] **Step 4: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 5: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): melee attack, mood, flee and cornered, puppet"
```

---

### Task 5: Jump and dash moves

**Files:**
- Create: `enemy/states/dash.gd`
- Modify: `enemy/enemy.gd` (`solve_jump`, `step_toward` branches), `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Tasks 1–4 (`jump` state applies `launch`; `probe().landing`, `probe().height`, `probe().point`, `probe().normal`).
- Produces:
  - `arc_to(to: Vector3, h: float) -> Vector3`: launch velocity of a ballistic arc from the body centre to the feet point `to`, peaking `h` above the start, under plain `gravity` (no env). The caller makes sure `h >= rise + 0.3`. Swing's release uses it directly.
  - `solve_jump(to: Vector3) -> Variant`: `arc_to(to, jump_height)`, or null when the jump can't make it (too high, or beyond `jump_reach`). Swim's leap reuses it.
  - Jump-state rule: a jump that starts with a `launch` uses plain `gravity`, with no env `gravity_mult` or drag, until it lands (the player's `launched` idea). Arcs then land where they were aimed, even when leaving water. Plain falls keep `apply_gravity`.
  - Take-off note: the probe looks about 1.3 m ahead at walking speed, so a jump starts that far before the edge. `jump_reach` therefore includes that run-up: a gap of about `jump_reach - 2.2` m is the widest an enemy clears (the runner's 6.5 gives about 4.3 m).

- [ ] **Step 1: Write `_test_jump_dash` (SECTIONS = 5)**

```gdscript
func _test_jump_dash() -> void:
	var base := {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0}
	var jumper := base.merged({abilities = Enemy.Ability.JUMP, jump_height = 2.3, jump_reach = 6.5}, true)
	var dasher := base.merged({abilities = Enemy.Ability.DASH, dash_distance = 6.0}, true)
	var runs := [ # props, far block centre, size, player at, crosses, label
		[jumper, Vector3(9.5, -0.5, 0), Vector3(13, 1, 10), Vector3(10, 1, 0), true, "JUMP clears a 3 m gap"],
		[jumper, Vector3(13.5, -0.5, 0), Vector3(13, 1, 10), Vector3(14, 1, 0), false, "JUMP refuses a 7 m gap"],
		[jumper, Vector3(8, 0.75, 0), Vector3(16, 1.5, 10), Vector3(8, 2.5, 0), true, "JUMP gets onto a 1.5 m wall"],
		[jumper, Vector3(8, 1.5, 0), Vector3(16, 3, 10), Vector3(8, 4, 0), false, "JUMP refuses a 3 m wall"],
		[dasher, Vector3(9.5, -0.5, 0), Vector3(13, 1, 10), Vector3(10, 1, 0), true, "DASH crosses a level 3 m gap"],
		[dasher, Vector3(13.5, -0.5, 0), Vector3(13, 1, 10), Vector3(14, 1, 0), false, "DASH refuses a 7 m gap"],
	]
	for r: Array in runs:
		_course(r[3], false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_box(r[1], r[2])
		var e := _enemy(Vector3(-4, 1, 0), r[0])
		var near_x: float = r[1].x - r[2].x / 2.0
		var top: float = r[1].y + r[2].y / 2.0
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(e) and e.global_position.x > near_x + 0.3 and e.global_position.y > top and e.is_on_floor(), 300)
		_check(crossed == r[4] and is_instance_valid(e) and (crossed or e.global_position.x < 1.2 and e.global_position.y > 0.5), r[5])
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: `FAIL JUMP clears a 3 m gap` (and the other crossing cases).

- [ ] **Step 3: Implement `arc_to`, `solve_jump` and the launched-jump gravity rule**

Jumps always use a full-height arc, so they look the same and the solve stays exact:

```
arc_to(to, h):
  g = gravity                                  # plain, see the jump-state rule
  d = (to + up*HALF_HEIGHT) - global_position
  rise = d.dot(up); flat = d.slide(up)
  vy = sqrt(2*g*h)
  t = vy/g + sqrt(2*(h - rise)/g)
  return flat.normalized()*(flat.length()/t) + up*vy   # flat ~0: up*vy only
solve_jump(to):
  rise = ((to + up*HALF_HEIGHT) - global_position).dot(up)
  if rise + 0.3 > jump_height: return null
  v = arc_to(to, jump_height)
  max_h = jump_reach / (2*sqrt(2*gravity*jump_height)/gravity)   # flat speed covering jump_reach on level ground
  return null if v.slide(up).length() > max_h else v
```

In `jump.gd`, a jump entered with a `launch` sets a `_launched` flag. While it's set, gravity is `gravity` along `-up_direction`, with no `env` multiplier and no drag. The flag clears on landing.

- [ ] **Step 4: Implement the `step_toward` branches and `dash`**

- `gap` with a landing: JUMP and `solve_jump(landing + dir*0.4)` isn't null → `launch = it`, return `&"jump"`. DASH, landing rise within `[-safe_drop, 0.3]` and flat distance + 0.4 ≤ `dash_distance` → `move_to = landing + dir*0.4`, return `&"dash"`.
- `wall` with JUMP and `height <= jump_height - 0.3`: `top = point + dir*0.6` raised to the wall top. If `solve_jump(top)` isn't null → `launch`, `&"jump"`.
- `dash`: on enter, `spend(dash_cost)`, `cue(&"dash")`, `anim = &"dash"`, direction toward `move_to`, length `minf(dash_distance, flat distance + 0.8)`. No gravity for `length / dash_speed` seconds, then `goal`, or `&"jump"` if airborne (goal unchanged).
- Add `dash` to `states`.

- [ ] **Step 5: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): solved jumps over gaps and onto walls, dash across gaps"
```

---

### Task 6: Climb and swim moves

**Files:**
- Create: `enemy/states/climb.gd`, `enemy/states/swim.gd`
- Modify: `enemy/enemy.gd`, `enemy/states/pursuit.gd`, `enemy/states/flee.gd`, `enemy/states/jump.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: `probe()` (`climbable`, `normal`, `point`), `solve_jump()`, `water_depth()`, `water_zone.surface_height(up)`.
- Produces: `climb` and `swim` states; the rule "SWIM + deep water → `&"swim"`" in pursuit, flee and jump.

- [ ] **Step 1: Write `_test_climb_swim` (SECTIONS = 6)**

```gdscript
func _pool() -> void: # banks at x < 0 and x > 6 (tops y = 0), pool floor y = -4, surface y = -0.3
	_box(Vector3(-8, -2.5, 0), Vector3(16, 5, 10))
	_box(Vector3(14, -2.5, 0), Vector3(16, 5, 10))
	_box(Vector3(3, -4.5, 0), Vector3(6, 1, 10))
	_water(Vector3(3, -2.15, 0), Vector3(6, 3.7, 10))


func _test_climb_swim() -> void:
	var base := {sight_radius = 40.0, lose_radius = 50.0, attack_damage = 0.0}
	for climbable in [true, false]:
		_course(Vector3(8, 5, 0))
		_box(Vector3(8, 2, 0), Vector3(8, 4, 10), climbable) # 4 m block, face at x = 4
		var c := _enemy(Vector3(0, 1, 0), base.merged({abilities = Enemy.Ability.CLIMB}, true))
		var up := await _wait_until(func() -> bool: return c.global_position.y > 4.5 and c.is_on_floor(), 400)
		_check(up == climbable, "CLIMB scales a climbable 4 m wall" if climbable else "CLIMB can't scale a plain wall")

	for swims in [true, false]:
		_course(Vector3(12, 1, 0), false)
		_pool()
		var w := _enemy(Vector3(-4, 1, 0), base.merged({abilities = Enemy.Ability.SWIM if swims else 0, max_oxygen = 30.0}, true))
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(w) and w.global_position.x > 6.5 and w.is_on_floor(), 600)
		_check(crossed == swims, "SWIM crosses the pool and climbs out" if swims else "no SWIM: stops at the pool")

	_course(Vector3(14, 1, 0), false)
	_pool()
	player.teleport(Vector3(3, -3, 0)) # stands on the pool floor (the player sinks when idle underwater)
	var diver := _enemy(Vector3(1, -2, 0), base.merged({abilities = Enemy.Ability.SWIM, max_oxygen = 2.0}, true))
	var causes := _deaths(diver)
	var low := INF
	for i in 300:
		await _wait(1)
		low = minf(low, diver.oxygen)
	_check(causes.is_empty() and low < diver.max_oxygen * 0.3 and diver.oxygen > low, "a swimmer low on oxygen surfaces to breathe instead of drowning")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: `FAIL CLIMB scales a climbable 4 m wall`, `FAIL SWIM crosses the pool...`.

- [ ] **Step 3: Implement climb**

- `step_toward`: `wall` with CLIMB, `climbable`, and target higher than the feet by more than 0.5 → `move_to = point`, return `&"climb"`. This check comes before the jump-onto-wall check.
- `climb`: `n` = probe normal (refreshed from `get_wall_normal()` while touching). Each frame `velocity = up.slide(n).normalized() * climb_speed - n * 1.0`, then `move_and_slide`. `anim = &"climb"`. When no wall is touched any more (past the top): `velocity = -n*3 + up*5`, return `&"jump"` (goal unchanged). `ponytail:` climbs up only; climbing down from edges comes when a level needs it.

- [ ] **Step 4: Implement swim**

- `step_toward`: `water` with SWIM → keep walking (the same move as `open`).
- Pursuit, flee and jump: `can(SWIM) and deep_water()` → `goal` = current goal (pursuit/flee keep their own name), return `&"swim"`. In pursuit this check comes before the attack-range check.
- `hold()`: a SWIM enemy in deep water (and `fall` false) stays put without gravity, like a flyer, so idle, attack and the cooldown wait don't sink it. Idle's "airborne → jump" rule skips it the same way it skips FLY.
- `swim`, gravity off: the 3D target is the target position (flee: a point 4 m away). Its height is clamped between the pool floor and `surface - 0.3`. When `oxygen < max_oxygen * 0.3` the height target becomes the surface (`surface_height(up) - HALF_HEIGHT + HEAD + 0.1`, head above water) until oxygen is back above 80%. Move toward it at `swim_speed * mult(&"swim")`, `move_and_slide`, `anim = &"swim"`. Exits: not in water any more → `goal`. Goal pursuit, target within `attack_range`, `attack_cd <= 0` and oxygen at or above 30% → `&"attack"`. Target on land (not in any water), wall ahead (`test_move` along the planar direction) and `solve_jump(top of the bank)` not null → `launch`, return `&"jump"`.
- Add `climb` and `swim` to `states`.

- [ ] **Step 5: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): climb climbable walls, swim with oxygen and leap out"
```

---

### Task 7: Swing and fly

**Files:**
- Create: `enemy/states/swing.gd`
- Modify: `enemy/enemy.gd` (`fly_toward`, branches), `enemy/states/idle.gd`, `enemy/states/stun.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: `find_landing()`, `arc_to()`, `hold()`, `SwingPoint` (`grab_radius`, `show_rope(to)`, `hide_rope()`, group `swing_point`).
- Produces: `fly_toward(point: Vector3, delta: float) -> StringName` (`&""` or `&"blocked"`), `swing` state.

- [ ] **Step 1: Write `_test_swing_fly` (SECTIONS = 7)**

```gdscript
func _test_swing_fly() -> void:
	var base := {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0}
	for anchor in [true, false]:
		_course(Vector3(12, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_box(Vector3(16, -0.5, 0), Vector3(16, 1, 10)) # 8 m gap
		if anchor:
			var sp := SwingPoint.new()
			sp.position = Vector3(4, 6, 0)
			sp.grab_radius = 8.0
			course.add_child(sp)
		var sw := _enemy(Vector3(-3, 1, 0), base.merged({abilities = Enemy.Ability.SWING}, true))
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(sw) and sw.global_position.x > 8.5 and sw.is_on_floor(), 400)
		_check(crossed == anchor, "SWING crosses an 8 m gap on a swing point" if anchor else "no swing point: SWING stops at the gap")

	_course(Vector3(14, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_box(Vector3(16, -0.5, 0), Vector3(16, 1, 10))
	var fl := _enemy(Vector3(-4, 1, 0), base.merged({abilities = Enemy.Ability.FLY, sight_radius = 0.0, hover_height = 2.5}, true))
	await _wait(120)
	var alt := fl.global_position.y - Enemy.HALF_HEIGHT
	_check(alt > 2.0 and alt < 3.0, "FLY hovers at hover_height (%.2f)" % alt)
	fl.sight_radius = 30.0
	_check(await _wait_until(func() -> bool: return fl.global_position.x > 9.0, 400), "FLY crosses an 8 m gap")
	fl.stun_on_hit = 1.0
	fl.hit(1.0, 0.0, fl.global_position)
	_check(fl.state_name == &"stun", "stun_on_hit stuns a flyer")
	_check(await _wait_until(func() -> bool: return fl.is_on_floor(), 90), "a stunned flyer drops to the ground")
	_check(await _wait_until(func() -> bool: return fl.global_position.y - Enemy.HALF_HEIGHT > 2.0, 200), "after the stun it flies back up")

	_course(Vector3(30, 1, 0))
	var winded := _enemy(Vector3(0, 1, 0), base.merged({abilities = Enemy.Ability.FLY, sight_radius = 60.0, lose_radius = 80.0, max_stamina = 10.0, fly_cost = 20.0, stun_time = 1.0}, true))
	_check(await _wait_until(func() -> bool: return winded.state_name == &"stun", 200), "a long flight ends in an exhaustion stun")
	_check(await _wait_until(func() -> bool: return winded.is_on_floor(), 90), "...and a drop to the ground")

	_course(Vector3(10, 1, 0))
	_box(Vector3(4, 10, 0), Vector3(1, 20, 30)) # 20 m wall across the floor
	var walled := _enemy(Vector3(-2, 1, 0), base.merged({abilities = Enemy.Ability.FLY}, true))
	var seen := await _watch([walled], 300)
	_check(&"idle" in seen and walled.global_position.x < 3.5, "FLY gives up at a wall too high to rise over")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: `FAIL SWING crosses...`, `FAIL FLY hovers...`.

- [ ] **Step 3: Implement swing**

- `step_toward`: `gap` when neither jump nor dash applies, with SWING: pick the nearest `swing_point` node within its `grab_radius` of `global_position`, at least 1 m above the feet, with a positive planar offset along `dir`. Landing: `find_landing(dir, 1.5, 2 * planar distance to the anchor + 1.5)`. Found → `swing_point = sp`, `move_to = landing + dir*0.4`, return `&"swing"`.
- `swing`: rope length `L` = distance to the anchor at enter; initial velocity `dir * 2.0`. Each frame: gravity, `move_and_slide`, then the rope constraint (pull back to `L`, remove the outward speed), `swing_point.show_rope(global_position)`, `anim = &"swing"`. Release once the bob is rising (`vspeed() > 0`) and its planar offset past the anchor along `dir` reaches 25% of the starting offset: set `launch = arc_to(move_to, maxf(rise + 1.0, 1.0))`, where `rise` is the height of `move_to` above the feet, and return `&"jump"`. Releasing early on a free arc keeps the bob from swinging into the far edge, which on a symmetric pendulum sits below the mirror point. `exit()` calls `hide_rope()`. `ponytail:` the rope mesh lives on the SwingPoint, so the player and an enemy on the same point share one rope.

- [ ] **Step 4: Implement fly**

- `step_toward` with FLY: `spend(fly_cost * delta)`, then return `fly_toward(point + up * hover_height, delta)`.
- `fly_toward`: gravity off. The desired point is kept at least `hover_height` above the ground under the enemy (ray down). Move toward it at `fly_speed * mult(&"speed")`, `move_and_slide`, `anim = &"fly"`. If a wall blocks the way (`is_on_wall()` while moving into it), raise the desired point. Altitude above the ground is capped at `hover_height + 6`. No planar progress for 1 s at that cap → `&"blocked"`.
- `hold()` for flyers (Task 1) already settles to `hover_height`, so idle hovers and climbs back up after a stun. Stun uses `hold(delta, true)`, so stunned flyers fall. Pursuit's "airborne → jump" rule already skips FLY.
- Add `swing` to `states`.

- [ ] **Step 5: Run to verify it passes**

Run: **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): swing across gaps, flying with hover and exhaustion drops"
```

---

### Task 8: Player melee and shooting

**Files:**
- Create: `player/states/melee.gd`, `world/projectile.gd`, `world/projectile.tscn`
- Modify: `player/player.gd`, `player/states/jump.gd`, `project.godot` (input actions), `world/area.gd` (`HELP`), `tests/enemy_test.gd`

**Interfaces:**
- Consumes: `Enemy.hit(damage, push, from)`, group `enemy`.
- Produces:
  - input actions `attack` (physical J, left mouse button, joypad axis 5 +1.0) and `shoot` (physical K, right mouse button, joypad axis 4 +1.0), deadzone 0.2, same format as the existing entries in `project.godot`
  - Player exports, group "Attack": `melee_damage := 10.0`, `melee_push := 24.0`, `melee_time := 0.3`, `melee_cooldown := 0.4`, `melee_reach := 1.0`, `melee_radius := 0.9`, `shoot_damage := 5.0`, `shoot_push := 6.0`, `shoot_speed := 30.0`, `shoot_cooldown := 0.35`, `shoot_range := 20.0`; vars `melee_cd`, `shoot_cd`
  - `Player.melee_hit() -> int`: sphere shape query (`melee_radius`) at `global_position + facing * melee_reach`, excluding self. Every distinct `Enemy` hit gets `hit(melee_damage, melee_push, global_position)`. Returns how many were hit.
  - `Player.shoot() -> Projectile`: spawns at `global_position + up_direction * 0.3 + facing * 0.6` under `get_parent()`, heading `aim_dir()`.
  - `Player.aim_dir() -> Vector3`: toward the nearest `enemy` within `shoot_range` whose planar direction is within 25° of `facing`, else `facing`.
  - `class_name Projectile extends Node3D`: `@export var speed := 30.0`, `@export var life := 1.5`; `setup(from: Vector3, dir: Vector3, damage: float, push: float, source: Node3D) -> void` (call after `add_child`; sets the global position and velocity, `reset_physics_interpolation()`)
  - `SHOOT_STATES := [&"idle", &"walk", &"run", &"jump", &"swim"]`

- [ ] **Step 1: Write `_test_player_attacks` (SECTIONS = 8)**

```gdscript
func _projectiles() -> Array:
	return course.get_children().filter(func(n: Node) -> bool: return n is Projectile)


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _wait(2)
	Input.action_release(action)


func _test_player_attacks() -> void:
	_check(InputMap.has_action(&"attack") and InputMap.has_action(&"shoot"), "attack and shoot input actions")
	_course(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	await _wait(20)
	var front := _enemy(Vector3(1.4, 1, 0), {sight_radius = 0.0, weight = 2.0})
	var back := _enemy(Vector3(-1.4, 1, 0), {sight_radius = 0.0})
	await _wait(10)
	await _press(&"attack")
	_check(player.state_name == &"melee", "attack starts the melee state")
	await _wait(30)
	_check(front.health == front.max_health - player.melee_damage and front.global_position.x > 1.6, "melee hits the enemy in front and pushes it")
	_check(back.health == back.max_health, "melee misses the enemy behind")
	_check(player.mood == 1.0, "a melee hit counts as a hit (mood)")
	player.melee_cd = 1.0
	await _press(&"attack")
	_check(player.state_name != &"melee", "no melee while on cooldown")
	front.queue_free()
	back.queue_free()

	var target := _enemy(Vector3(8, 1, 1.5), {sight_radius = 0.0}) # 11° off the facing
	await _wait(10)
	await _press(&"shoot")
	_check(_projectiles().size() == 1, "shoot spawns one projectile")
	_check(await _wait_until(func() -> bool: return target.health < target.max_health, 30), "aim assist: the shot hits an enemy 11° off the facing")
	await _wait(2)
	_check(_projectiles().is_empty(), "the projectile is freed on hit")
	target.queue_free()

	_box(Vector3(-6, 1, 0), Vector3(1, 2, 4))
	player.facing = Vector3.LEFT
	await _wait(20)
	await _press(&"shoot")
	_check(await _wait_until(func() -> bool: return _projectiles().is_empty(), 30), "a shot into a wall is freed")
	_check(is_equal_approx(player.mood, 2.0 / 3.0), "the miss counts (mood = hits / attacks)")
	player.damage(1.0, player.global_position + Vector3.RIGHT)
	await _press(&"shoot")
	_check(_projectiles().is_empty(), "no shooting while hurt")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: parse error (`Projectile` / `melee_cd` unknown).

- [ ] **Step 3: Implement**

- `project.godot`: the two actions. Use `InputEventMouseButton` with `button_index` 1 and 2 for the mouse.
- `melee` (PlayerState): enter → `anim = &"melee"`, `melee_cd = melee_cooldown`. Physics: on the ground `move_ground(move_input() * 0.3, walk_speed, delta)`, in the air `move_air(move_input(), delta)`; `apply_gravity`, `move_and_slide`. Once, at `melee_time * 0.4`: `register_attack(melee_hit() > 0)`. After `melee_time` → `recover_state()`.
- `ground_step` (after the dash check) and `jump.gd` (after the dash check): `Input.is_action_just_pressed(&"attack") and melee_cd <= 0.0` → `&"melee"`.
- `_physics_process`: count down `melee_cd` and `shoot_cd`. If `shoot` was just pressed, `shoot_cd <= 0` and `state_name in SHOOT_STATES` → `shoot()`, `shoot_cd = shoot_cooldown`.
- `_animate`: add `&"melee"` (for example `sc = Vector3(1.15, 0.9, 1.15)`, `tilt = -0.5`).
- `Projectile._physics_process`: each frame ray from the current position to `+ velocity * delta`, excluding the source's RID. An `Enemy` → `hit(damage, push, global_position)`; a `Player` → `damage(damage, global_position)`; anything else is a world hit; `life` running out is a miss. On finish: `if source is Player: source.register_attack(collider is Enemy)`, then `queue_free()`.
- `projectile.tscn`: root Node3D with the script, plus a `Mesh` MeshInstance3D child (SphereMesh radius 0.12, emissive unshaded yellow material).
- `GameArea.HELP` first line: append ` | J/LMB melee | K/RMB shoot`.

- [ ] **Step 4: Register and run**

Run the editor registration command from Task 1, then **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 5: Player suites still pass**

Run the smoke test and the puzzle test. Expected: `SMOKE: OK`, `PUZZLES: OK`.

- [ ] **Step 6: Commit**

```bash
git add player/ world/projectile.gd world/projectile.gd.uid world/projectile.tscn world/area.gd project.godot tests/enemy_test.gd
git commit -m "feat(player): melee attack and projectile shot with aim assist"
```

---

### Task 9: Runner and burrower

**Files:**
- Create: `enemy/runner/runner.tscn`, `enemy/burrower/burrower.tscn`, `enemy/burrower/burrower.gd`, `enemy/burrower/burrow_pursuit.gd`, `enemy/burrower/burrow_attack.gd`
- Modify: `tests/enemy_test.gd`

**Interfaces:**
- Consumes: everything above; `Player.melee_push`.
- Produces:
  - `runner.tscn`: inherited from `enemy.tscn` (`[node name="Runner" instance=ExtResource(...)]`). Overrides: `abilities = 9` (RUN | JUMP), `weight = 3.0`, `max_health = 40.0`, `walk_speed = 3.5`, `run_speed = 6.5`, `jump_height = 2.3`, `jump_reach = 6.5`, `run_cost = 20.0`, `stun_time = 2.0`, `max_oxygen = 3.0`, `sight_radius = 10.0`, `lose_radius = 16.0`, `color = Color(0.85, 0.25, 0.2)`.
  - `class_name Burrower extends Enemy`: exports `burrow_speed := 7.0`, `surface_radius := 1.5`, `burst_radius := 2.0`, `burst_damage := 20.0`, `rest_time := 2.5`; `var burrowed := false` (set through `set_burrowed(on: bool) -> void`, which saves and restores `collision_layer`/`collision_mask` (0 while burrowed), hides `Visual` and shows `Mound`). `_init()` replaces `states[&"pursuit"]` and `states[&"attack"]`.
  - `burrower.tscn`: inherited from `enemy.tscn`, script `burrower.gd`. Overrides: `abilities = 0`, `weight = 40.0`, `max_health = 120.0`, `armor = 0.3`, `flee_mood = 0.0`, `sight_radius = 12.0`, `lose_radius = 20.0`, `color = Color(0.5, 0.35, 0.2)`. Extra child `Mound` (MeshInstance3D, flattened SphereMesh radius 0.7, height 0.5, brown, at y -0.6, hidden).

- [ ] **Step 1: Write `_test_types` (SECTIONS = 9)**

```gdscript
const RUNNER := preload("res://enemy/runner/runner.tscn")
const BURROWER := preload("res://enemy/burrower/burrower.tscn")


func _test_types() -> void:
	_course(Vector3(-30, 1, 0))
	var r := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0}, RUNNER)
	await _wait(10)
	_check(r.abilities == (Enemy.Ability.RUN | Enemy.Ability.JUMP) and r.weight == 3.0, "runner: RUN + JUMP, weight 3")
	r.hit(1.0, player.melee_push, r.global_position - Vector3(1, 0, 0))
	_check(absf(r.planar().length() - player.melee_push / 3.0) < 0.1, "runner flies back from a melee push")

	_course(Vector3(12, 1, 0), false)
	_pool()
	var dunk := _enemy(Vector3(-0.8, 1, 0), {sight_radius = 0.0}, RUNNER)
	var causes := _deaths(dunk)
	await _wait(10)
	dunk.hit(1.0, player.melee_push, dunk.global_position - Vector3(1, 0, 0))
	_check(await _gone(dunk, 420) and causes == [&"drown"], "runner shoved into deep water drowns")

	_course(Vector3(6, 1, 0))
	_box(Vector3(0, 1.5, 0), Vector3(1, 3, 30)) # wall across the floor
	var b: Burrower = _enemy(Vector3(-6, 1, 0), {sight_radius = 20.0, lose_radius = 30.0}, BURROWER)
	var cues := []
	b.cue.connect(func(n: StringName) -> void: cues.append(n))
	_check(await _wait_until(func() -> bool: return b.burrowed, 120) and b.collision_layer == 0, "burrower digs in: no collision underground")
	var hp := player.health
	_check(await _wait_until(func() -> bool: return not b.burrowed, 300), "...and surfaces")
	_check(b.global_position.x > 0.5 and (b.global_position - player.global_position).slide(Vector3.UP).length() < b.surface_radius + 0.5, "it passed under the wall and came up next to the player")
	_check(await _wait_until(func() -> bool: return player.health < hp, 30) and &"surface" in cues, "the surfacing burst hurts the player")
	_check(await _wait_until(func() -> bool: return b.state_name == &"stun", 60), "then it rests (stun)")
	b.hit(10.0, player.melee_push, b.global_position - Vector3(1, 0, 0))
	_check(b.planar().length() < 0.1 and b.health < b.max_health and b.state_name == &"stun", "resting burrower takes damage, stays down, can't be pushed")

	for kind in ["water", "gap"]:
		_course(Vector3(10, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_far_side(kind)
		var b2: Burrower = _enemy(Vector3(-5, 1, 0), {sight_radius = 30.0, lose_radius = 40.0}, BURROWER)
		await _wait_until(func() -> bool: return b2.burrowed, 120)
		var seen := await _watch([b2], 240)
		_check(&"idle" in seen and b2.global_position.x < 1.2 and b2.global_position.y > 0.5, "burrower can't cross %s: surfaces on its side and gives up" % kind) # it retries after give_up_time, so it may be dug in again
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: load error for `runner.tscn` / unknown `Burrower`.

- [ ] **Step 3: Implement the runner**

Scene only, with the overrides listed in Interfaces. No script.

- [ ] **Step 4: Implement the burrower**

- `burrow_pursuit`, phases:
  - dig: 0.6 s, `cue(&"burrow_in")`, `anim = &"burrow_in"`, `set_burrowed(true)` on enter.
  - travel: `anim = &"burrowed"`. Each frame the next feet point is `feet + dir * burrow_speed * delta` toward the target (planar). Ray from `next + up*0.5` down to `next - up*safe_drop`, with the same excludes as `probe`. A ray starting inside a wall passes through it, which is how the burrower goes under walls. The step needs a hit that isn't deep water (`water_at(hit + up*0.1)`, same depth rule as `probe`). Otherwise it's **blocked**. On a hit, `global_position = hit + up*HALF_HEIGHT` (no `move_and_slide`).
  - surface: `set_burrowed(false)`, then return `&"attack"` when within `surface_radius` of the target (planar). On blocked, or after 8 s of travel: `give_up = give_up_time`, return `&"idle"`. Target lost or out of `lose_radius` → surface, return `&"idle"`.
  - `exit()` always calls `set_burrowed(false)`.
- `burrow_attack`: enter → `anim = &"surface"`, `cue(&"surface")`; target within `burst_radius` → `target.damage(burst_damage, global_position)` and `mood += 0.1`; `attack_cd = attack_cooldown`. After 0.4 s: `stun_for = rest_time`, return `&"stun"`.

- [ ] **Step 5: Register and run**

Run the editor registration command, then **RUN ENEMIES**. Expected: `ENEMIES: OK`.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): runner and burrower types"
```

---

### Task 10: Demo scene

**Files:**
- Create: `demo/enemies/enemies.tscn`
- Modify: `tests/enemy_test.gd`

**Interfaces:**
- Consumes: `world/area.gd` (GameArea needs children `Player`, `Camera`, `HUD/Label`, optional `Bays` with `Start` markers), `runner.tscn`, `burrower.tscn`, `kill_zone.gd`, `env_zone.gd`, `env_profile.gd`, `stat_mods.gd`.
- Produces: the scene with exactly 3 runners and 2 burrowers.

Deviation from the spec, noted on purpose: the runner and burrower *behaviours* are tested on code-built courses (Tasks 2–9). This task checks that the demo loads, populates and runs without errors, so the tests don't depend on the bay layout.

- [ ] **Step 1: Write `_test_demo` (SECTIONS = 10)**

```gdscript
func _test_demo() -> void:
	root.remove_child(course)
	course.queue_free()
	var demo: Node = load("res://demo/enemies/enemies.tscn").instantiate()
	root.add_child(demo)
	await _wait(60)
	var enemies := get_nodes_in_group(&"enemy")
	var burrowers := enemies.filter(func(n: Node) -> bool: return n is Burrower)
	_check(enemies.size() == 5 and burrowers.size() == 2, "demo: 3 runners and 2 burrowers")
	_check(enemies.all(func(n: Enemy) -> bool: return n.state_name == &"idle" and n.health == n.max_health), "all idle at full health at the start")
	demo.queue_free()
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES**. Expected: load error for `enemies.tscn`.

- [ ] **Step 3: Build `enemies.tscn`**

Root `Enemies` (Node3D, script `res://world/area.gd`), `WorldEnvironment` + `Sun` like `demo.tscn`, `Camera`, `HUD/Label`, a `Player` instance at the Runner bay start, and a `Void` KillZone under everything (y −14). Sub-resource `EnvProfile` "Water" (`water = true`, `gravity_mult = 0.3`, `drag = 1.2`). `Bays`, each with a `Label3D` (font 56, outline 14, billboard, no depth test) explaining what to try and a `Start` marker. Every enemy starts more than its `sight_radius` from the player's start and from the bay `Start` markers.
1. **Runner** (x = 0): a 20×20 plateau (top y = 0). East: a 3 m gap to a second plateau (it jumps). North: a 7 m gap (it stops). South: a pond, 3 m of water over a basin (it stops; push it in and it drowns). West: an open ledge over the void (shove it off). Two runners.
2. **Burrower** (x = 50): a 24×20 field cut by a 3 m wall the player can't cross (the burrower goes under it), a water channel along one side and a pit strip along the other. One burrower.
3. **Both** (x = 100): a 24×24 arena with a pit in the middle, one runner and one burrower.

- [ ] **Step 4: Run and check for errors**

Run: **RUN ENEMIES** (expected `ENEMIES: OK`), then `timeout 150 "$GODOT" --headless --path . --quit-after 600 res://demo/enemies/enemies.tscn 2>&1 | grep -viE "$NOISE"`. Expected: no `ERROR` / `SCRIPT ERROR` lines.

- [ ] **Step 5: Commit**

```bash
git add demo/enemies/enemies.tscn tests/enemy_test.gd
git commit -m "feat(demo): enemy demo with runner, burrower and mixed bays"
```

---

### Task 11: Docs, CLAUDE.md, full verification

**Files:**
- Create: `docs/enemies.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: the final names from Tasks 1–10 (`anim` values, `cue` names, `died`, the `Visual` node, `_animate`, exports, the `states` replacement pattern, `Projectile` scene).

- [ ] **Step 1: Write `docs/enemies.md`**

Sections, all using the real names from the code:
1. **Making an enemy type**: inherit `enemy/enemy.tscn`; tune exports (with a table of the groups); set `abilities`; replace states in `_init()` (the burrower as the example); emit `cue` for presentation; `died`.
2. **How an enemy decides**: the state list and transitions, probe kinds, how blocked → give up works, and that hurt has no ledge check.
3. **Animations**: a table of every `anim` value and which state sets it. Wiring an `AnimationTree` state machine keyed on `anim` (poll each physics frame, like `_animate`), and deleting `_animate()` once that exists. One-shots come from `cue`. Code drives motion; no root motion; gameplay never waits on an animation.
4. **Custom skeletal meshes**: import the glTF under `Visual` in place of `Body`/`Nose`, forward −Z, scale and offset so the feet sit at `Visual`'s origin. The `CollisionShape3D` stays the gameplay shape. Use `BoneAttachment3D` for markers (attack point, a projectile muzzle for future enemy shooters). The burrower's `Mound` is a separate mesh.
5. **Effects (sound, VFX)**: one presenter child per enemy that connects `cue` and maps names to `AudioStreamPlayer3D` / `GPUParticles3D` (example snippet). Death effects must be spawned detached (`top_level` or reparented to the area), because the enemy frees itself. `world/projectile.tscn` is the slot for shot and impact VFX. The player's `melee` anim follows the same pattern.

- [ ] **Step 2: Update `CLAUDE.md`**

Add to "Verifying changes" the line `timeout 400 "$GODOT" --headless --path . -s res://tests/enemy_test.gd 2>&1 | grep -viE "$NOISE"   # enemies + player attacks, ~3 min` and `ENEMIES` in the list of last-line names. Add an **Enemies** paragraph to Architecture: the `Enemy` body and states, probe and give-up, abilities, types as inherited scenes, the `_enemy_entered` zone hooks, player `melee`/`shoot`/`Projectile`, the demo scene path, and a pointer to `docs/enemies.md`.

- [ ] **Step 3: Full verification**

Run, from CLAUDE.md: smoke, platform, puzzle, shape editor, platform tools, enemy suites; `--editor --quit-after 400`; `--quit-after 600 res://demo/enemies/enemies.tscn`. Expected: every suite ends in `: OK`, and the two runs print no `ERROR` / `SCRIPT ERROR` lines.

- [ ] **Step 4: Commit**

```bash
git add docs/enemies.md CLAUDE.md
git commit -m "docs: enemy system guide; CLAUDE.md enemies section and suite"
```
