# Enemy Areas, Sight and Off-Screen Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enemies roam shared patrol areas of any shape, spot the player only in plain view, chase within a shared chase area (a leash), return to patrol after giving up, and sleep off screen (no thinking, physics still on). The crowd demo uses all of it.

**Architecture:** `EnemyArea` is a `Zone` (any shape, Shape Tools editing) with `contains()` and `random_ground()`. `Enemy.step_toward` gains a `leash` area (its border counts as a ledge while the enemy is inside it) and a `hurry` flag. A new `patrol` state walks to random spots. `sees_target()` adds a line-of-sight ray, and pursuit falls back to `last_seen`. A `VisibleOnScreenNotifier3D` flips `asleep`; asleep enemies run a ray-free physics tick (`_doze`).

**Tech Stack:** Godot 4.7.2 GDScript, Jolt, headless `SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-11-20-enemy-areas-design.md` (builds on `docs/superpowers/specs/2026-11-20-enemy-system-design.md`)

## Global Constraints

- Godot `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` only. Static typing, `##` docs, `ponytail:` on deliberate shortcuts.
- New scripts get their `.uid` committed. Run the editor once after adding `class_name` scripts (`--editor --quit-after 400`).
- `Enemy` and `EnemyArea` never reference the `World` autoload.
- `@tool` scripts (`EnemyArea` is one, through `Zone`) create child nodes in `_ready`, not as member defaults.
- Point-inside tests only work for convex area shapes (box, sphere, capsule, cylinder, convex). Concave and height-map shapes get a config warning.
- Sleep is off when `DisplayServer.get_name() == "headless"`.
- Work on branch `feature/enemy-system` (up to date with `main`). Stage files by explicit path. `demo/enemies/crowd.*` is the user's scene; they asked for it to be updated.
- Preamble for every command:
  ```sh
  GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
  NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"
  ```
- Every new `_test_<name>` section goes into the `all` list in `_run()` before `_test_demo`, except `_test_crowd`, which goes after it.
  **RUN ENEMIES [sections]**: `timeout 400 "$GODOT" --headless --path . -s res://tests/enemy_test.gd [-- <section> ...] 2>&1 | grep -viE "$NOISE"`. It passes when the last line is `ENEMIES: OK`. Sections are named after `_test_<name>`, and `SECTIONS` is raised by one per new section.
- Report "headless only, game feel untested; on-screen detection can't be tested headless".

## Review Focus

1. An area with nowhere the enemy can stand (all deep water for a walker) → `random_ground` returns null and the enemy just idles: no hang, no errors (Task 1 test).
2. Patrol spots across a gap the enemy can't cross → it gives up those spots, roams its own side and never falls in (Task 2 test).
3. A patrol area freed while enemies use it → they stop roaming and idle, with no errors (Task 2 test).
4. An enemy spawned outside its chase area → the leash doesn't hold it, and it chases normally (Task 3 test).
5. A flyer asleep → it stays where it is and doesn't drop (Task 4 test).

---

### Task 1: EnemyArea and the Enemy's area exports

**Files:**
- Create: `world/enemy_area.gd`
- Modify: `enemy/enemy.gd` (exports, `rng`), `tests/enemy_test.gd`

**Interfaces:**
- Produces:
  - `@tool class_name EnemyArea extends Zone`. Default `color = Color(1, 0.6, 0.2, 0.08)`. Const `TRIES := 12`.
  - `contains(point: Vector3) -> bool`: point query with `collide_with_areas = true`, `collide_with_bodies = false`, up to 32 results; true when `r.collider == self`.
  - `random_ground(e: Enemy) -> Variant`: a feet point or null. Up to `TRIES` times:
    - pick a random point in `bounds()` using `e.rng`, converted with `to_global`;
    - cast down with `e.cast(top, bottom)`, where `top` and `bottom` are that point at the top and bottom of the bounds (global);
    - accept the hit when `contains(hit + e.up_direction * 0.5)`, and:
      - SWIM-only (`e.water_bound()`): `e.deep_water_at(hit)` is true;
      - otherwise: either the enemy can SWIM, or `e.deep_water_at(hit)` is false.
  - `_get_configuration_warnings()`: a warning per concave or height-map shape, plus Zone's own.
  - On `Enemy`:
    - "Senses" group: `@export var memory_time := 3.0`.
    - New "Areas" group: `@export var patrol_area: EnemyArea`, `@export var chase_area: EnemyArea`, `@export var patrol_pause := Vector2(1.0, 3.0)`, `@export var sleep_off_screen := true`, `@export var screen_margin := 4.0`.
    - `var rng := RandomNumberGenerator.new()`, `rng.randomize()` in `_ready`.
- Test helpers added to `tests/enemy_test.gd`:
  - `_boxed(size: Vector3) -> BoxShape3D`
  - `_area(at: Vector3, shape: Shape3D, rot_y := 0.0) -> EnemyArea`: adds to `course` first, then `add_shape(shape)`.

- [ ] **Step 1: Write `_test_areas` (SECTIONS = 13) and add it to the `all` list before `_test_demo`**

```gdscript
func _test_areas() -> void:
	_course()
	var box := _area(Vector3(0, 1, 0), _boxed(Vector3(8, 2, 4)), PI / 4)
	var ball := SphereShape3D.new()
	ball.radius = 3.0
	var sphere := _area(Vector3(20, 1, 0), ball)
	await _wait(2)
	_check(box.contains(Vector3(0, 1, 0)) and box.contains(Vector3(2.5, 1, -2.5)) and not box.contains(Vector3(2.5, 1, 2.5)), "contains: a box rotated 45 degrees")
	_check(sphere.contains(Vector3(22, 1, 0)) and not sphere.contains(Vector3(22.5, 1, 2.5)), "contains: a sphere")

	var pond := _area(Vector3(-20, 1, 8), _boxed(Vector3(10, 4, 6))) # x -25..-15, half over the water
	_water(Vector3(-17.5, 1.5, 8), Vector3(5, 3, 6)) # 3 m deep over the floor, x -20..-15
	var walker := _enemy(Vector3(-30, 1, -8), {sight_radius = 0.0})
	var fish := _enemy(Vector3(-17, 1, 8), {abilities = Enemy.Ability.SWIM, sight_radius = 0.0})
	await _wait(2)
	walker.rng.seed = 7
	fish.rng.seed = 7
	var dry := true
	var wet := true
	for i in 40:
		var g: Variant = pond.random_ground(walker)
		dry = dry and g != null and pond.contains(g + Vector3.UP * 0.5) and not walker.deep_water_at(g)
		var w: Variant = pond.random_ground(fish)
		wet = wet and w != null and fish.deep_water_at(w)
	_check(dry, "random_ground: inside the area, never under deep water for a walker")
	_check(wet, "random_ground: only under water for a SWIM-only enemy")
	var lake := _area(Vector3(-17.5, 1, 8), _boxed(Vector3(4, 2, 4))) # entirely over the water
	await _wait(2)
	_check(lake.random_ground(walker) == null, "random_ground: null when there's nowhere to stand")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES** `-- areas`. Expected: parse error, `EnemyArea` not found.

- [ ] **Step 3: Implement `world/enemy_area.gd` and the Enemy exports and `rng`**

- [ ] **Step 4: Register and run**

Run `timeout 150 "$GODOT" --headless --path . --editor --quit-after 400 2>&1 | grep -viE "$NOISE" | grep -i error` (expect nothing), then **RUN ENEMIES** `-- areas`. Expected: `ENEMIES: OK`.

- [ ] **Step 5: Commit**

```bash
git add world/enemy_area.gd world/enemy_area.gd.uid enemy/enemy.gd tests/enemy_test.gd
git commit -m "feat(enemy): EnemyArea zones and area exports"
```

---

### Task 2: Leash, relaxed roaming and the patrol state

**Files:**
- Create: `enemy/states/patrol.gd`
- Modify: `enemy/enemy.gd`, `enemy/states/idle.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `step_toward(point: Vector3, delta: float, leash: EnemyArea = null, hurry := true) -> StringName`. With `hurry` false: walk speed, no `run_cost`, no `fly_cost`.
  - `fly_toward(point: Vector3, delta: float, leash: EnemyArea = null) -> StringName`
  - `_walk(dir: Vector3, delta: float, hurry := true) -> void`
  - `leashed(leash: EnemyArea, feet_to: Vector3) -> bool`: true when `is_instance_valid(leash)`, the enemy is inside it (`leash.contains(global_position)`), and `not leash.contains(feet_to + up_direction * HALF_HEIGHT)`. In `step_toward`, each destination is tested with it before acting, and a leashed one falls through to the `&"blocked"` tail:
    - `open` / `water`: `p.point`
    - jump over a gap: `land`
    - dash: `land`
    - swing: `far`
    - jump onto a wall: `top`
    - climb: `p.point`
    - flyers: in `fly_toward`, `global_position + planar step * 0.6 - up*HALF_HEIGHT`, the next spot.
  - `&"patrol"` in `states`. `patrol.gd` keeps `_spot: Vector3`.
  - Idle: a random pause in `patrol_pause` (re-rolled on `enter`).

- [ ] **Step 1: Write `_test_patrol` (SECTIONS = 14)**

```gdscript
func _test_patrol() -> void:
	var calm := {sight_radius = 0.0, patrol_pause = Vector2(0.2, 0.4)}
	_course(Vector3(-30, 1, 0))
	var yard := _area(Vector3(5, 1, 0), _boxed(Vector3(10, 2, 8))) # x 0..10, z -4..4
	var a := _enemy(Vector3(5, 1, 0), calm.merged({patrol_area = yard}, true))
	var b := _enemy(Vector3(7, 1, 2), calm.merged({patrol_area = yard}, true))
	var jog := _enemy(Vector3(3, 1, -2), calm.merged({patrol_area = yard, abilities = Enemy.Ability.RUN}, true))
	a.rng.seed = 1
	b.rng.seed = 2
	jog.rng.seed = 3
	var spots: Array[Vector3] = []
	var inside := true
	var b_moved := false
	var relaxed := true
	for i in 600:
		await _wait(1)
		for e: Enemy in [a, b, jog]:
			inside = inside and absf(e.global_position.x - 5.0) <= 5.5 and absf(e.global_position.z) <= 4.5
		if a.state_name == &"idle" and (spots.is_empty() or spots[-1].distance_to(a.global_position) > 1.0):
			spots.append(a.global_position)
		b_moved = b_moved or b.global_position.distance_to(Vector3(7, 0.8, 2)) > 2.0
		relaxed = relaxed and jog.planar().length() <= jog.walk_speed + 0.2 and jog.stamina == jog.max_stamina
	_check(spots.size() >= 3, "patrol: visits several spots (%d)" % spots.size())
	_check(inside, "patrol: never leaves the patrol area")
	_check(b_moved, "two enemies share one patrol area")
	_check(relaxed, "roaming is at walk speed and costs no stamina, even for a runner")

	_course(Vector3(-30, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10)) # x -16..0
	_box(Vector3(9.5, -0.5, 0), Vector3(13, 1, 10)) # x 3..16: a 3 m gap
	var both := _area(Vector3(0, 1, 0), _boxed(Vector3(16, 3, 8)))
	var hop := _enemy(Vector3(-4, 1, 0), calm.merged({patrol_area = both, abilities = Enemy.Ability.JUMP, jump_height = 2.3, jump_reach = 6.5}, true))
	hop.rng.seed = 4
	var left := false
	var right := false
	for i in 900:
		await _wait(1)
		if is_instance_valid(hop) and hop.is_on_floor():
			left = left or hop.global_position.x < -1.0
			right = right or hop.global_position.x > 4.0
	_check(left and right and is_instance_valid(hop), "patrol uses its moves: a jumper roams both sides of a 3 m gap")

	_course(Vector3(-30, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_box(Vector3(13.5, -0.5, 0), Vector3(13, 1, 10)) # 7 m gap
	var wide := _area(Vector3(2, 1, 0), _boxed(Vector3(20, 3, 8)))
	var walker := _enemy(Vector3(-4, 1, 0), calm.merged({patrol_area = wide}, true))
	walker.rng.seed = 5
	await _wait(600)
	_check(is_instance_valid(walker) and walker.global_position.x < 0.6 and walker.global_position.y > 0.5, "spots across a gap it can't cross: it roams its own side, never falls in")

	_course(Vector3(-30, 1, 0))
	var pen := _area(Vector3(10, 1, 0), _boxed(Vector3(6, 2, 6)))
	var stray := _enemy(Vector3(-5, 1, 0), calm.merged({patrol_area = pen}, true))
	_check(await _wait_until(func() -> bool: return pen.contains(stray.global_position), 400), "an enemy outside its patrol area walks back in")
	pen.queue_free()
	await _wait(120)
	var still := stray.global_position
	await _wait(60)
	_check(stray.state_name == &"idle" and stray.global_position.distance_to(still) < 0.2, "its patrol area freed: no errors, it stops roaming")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES** `-- patrol`. Expected: `FAIL patrol: visits several spots (0)` and the other roaming checks fail. The freed-area check may pass already.

- [ ] **Step 3: Implement the leash and `hurry`**

The signatures and checked destinations are in Interfaces. Existing callers (pursuit, flee) keep the defaults for now; Task 3 passes `chase_area`.

- [ ] **Step 4: Implement `idle` and `patrol`**

- **idle**:
  - `enter`: `_pause = e.rng.randf_range(e.patrol_pause.x, e.patrol_pause.y)`.
  - `physics`: keeps its current spotting rule (Task 3 swaps in sight). After the pause, if `is_instance_valid(e.patrol_area)` → `&"patrol"`.
- **patrol**, `enter`:
  - `_spot` comes from `e.patrol_area.random_ground(e)`. When the enemy is outside the area, that also brings it back in, since every spot is inside.
  - null, or the area isn't valid → set a flag and return `&"idle"` on the first physics frame. Don't change state from `enter`.
  - `e.reset_watchdog()`.
- **patrol**, `physics`, in order:
  1. `e.flail` → `&""`.
  2. Area no longer valid → `&"idle"`.
  3. Spotting, the same rule as idle → `&"pursuit"`.
  4. Airborne, and not FLY and not swimming → `goal = &"patrol"`, `&"jump"`.
  5. `e.swimming()` → `goal = &"patrol"`, `&"swim"`. Swim already handles any goal: with no target, it holds.
  6. Planar distance to `_spot` < 0.5 → `&"idle"`.
  7. `step_toward(_spot, delta, e.patrol_area, false)`. `&"blocked"`, or `&""` with `not e.moving_on(delta)` → `&"idle"`. Otherwise return it.
- In `swim.gd`, the `not e.has_target()` branch only returns idle when `e.goal != &"patrol"`. A patrolling swimmer aims at `_spot`, so add `var aim_override: Variant = null` on Enemy, set by patrol before handing off to swim, and used by swim as `aim`.

- [ ] **Step 5: Run to verify it passes**

Run: **RUN ENEMIES** `-- patrol`, then a full **RUN ENEMIES**. Expected: `ENEMIES: OK` both times.

- [ ] **Step 6: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): patrol state roams shared areas with a leash"
```

---

### Task 3: Sight, last seen, chase leash

**Files:**
- Modify: `enemy/enemy.gd`, `enemy/states/idle.gd`, `enemy/states/patrol.gd`, `enemy/states/pursuit.gd`, `enemy/states/flee.gd`, `enemy/states/swim.gd`, `enemy/states/attack.gd`, `enemy/burrower/burrow_pursuit.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `sees_target() -> bool`:
    - `has_target()` and `dist_to_target() <= sight_radius` and `cast(global_position + up_direction * HEAD, target_pos() + up_direction * 0.3).is_empty()`;
    - cached in `_sees` for 0.2 s (`_sight_t`);
    - when true, sets `last_seen = target_pos()` and `seen_ago = 0.0`;
    - `seen_ago` grows by `delta` in `_physics_process`.
  - `var last_seen := Vector3.ZERO`, `var seen_ago := INF`.
- Rules:
  - Idle and patrol spot with `sees_target()` (plus `give_up <= 0`).
  - Pursuit's aim is `target_pos()` when `sees_target()`, else `last_seen`. It gives up (`give_up = give_up_time`, `cue(&"blocked")`, `&"idle"`) when it's not seeing and either the planar distance to `last_seen` is < 1.0 or `seen_ago > memory_time`.
  - The attack check also needs `sees_target()`.
  - Pursuit, flee and swim step with `leash = e.chase_area`.
  - Attack aborts to idle when `not e.sees_target()` and `e.seen_ago > 0.5`.
  - The burrower's travel step is blocked by `e.leashed(e.chase_area, hit.position)`, and it only accepts surface spots that are not leashed.

- [ ] **Step 1: Write `_test_sight_leash` (SECTIONS = 15)**

```gdscript
func _test_sight_leash() -> void:
	_course(Vector3(6, 1, 0))
	var wall := _box(Vector3(3, 1.5, 0), Vector3(0.5, 3, 30))
	var e := _enemy(Vector3(0, 1, 0), {sight_radius = 10.0, attack_damage = 0.0})
	await _wait(60)
	_check(e.state_name == &"idle", "a wall blocks sight: no chase inside sight_radius")
	wall.queue_free()
	_check(await _wait_until(func() -> bool: return e.state_name == &"pursuit", 40), "in plain view: the chase starts")

	_course(Vector3(4, 1, 0))
	var yard := _area(Vector3(-4, 1, 0), _boxed(Vector3(6, 2, 6)))
	var hunter := _enemy(Vector3(-4, 1, 0), {sight_radius = 12.0, lose_radius = 30.0, patrol_area = yard, attack_damage = 0.0})
	await _wait_until(func() -> bool: return hunter.state_name == &"pursuit", 60)
	_box(Vector3(8, 1.5, 0), Vector3(0.5, 3, 30))
	player.teleport(Vector3(12, 1, 0)) # behind the wall
	_check(await _wait_until(func() -> bool: return hunter.state_name == &"idle", 300) and hunter.global_position.x > 2.0, "out of sight: it goes to where it last saw the player, then gives up")
	_check(await _wait_until(func() -> bool: return yard.contains(hunter.global_position), 400), "then it walks back into its patrol area")

	_course(Vector3(10, 1, 0))
	var leash := _area(Vector3(0, 1, 0), _boxed(Vector3(8, 2, 8))) # x -4..4
	var kennel := _area(Vector3(-2, 1, 0), _boxed(Vector3(3, 2, 3)))
	var dog := _enemy(Vector3(-2, 1, 0), {sight_radius = 15.0, lose_radius = 30.0, chase_area = leash, patrol_area = kennel, attack_damage = 0.0})
	var loose := _enemy(Vector3(7, 1, 3), {sight_radius = 15.0, chase_area = leash, attack_damage = 0.0})
	var max_x := -INF
	var seen: Array[StringName] = []
	for i in 240:
		await _wait(1)
		max_x = maxf(max_x, dog.global_position.x)
		if dog.state_name not in seen:
			seen.append(dog.state_name)
	_check(&"pursuit" in seen and &"idle" in seen and max_x < 4.5, "chase area: up to the border, never across, then gives up (max x %.2f)" % max_x)
	_check(loose.has_target() and loose.dist_to_target() < loose.attack_range + 0.5, "an enemy outside its chase area isn't held by it")
	player.teleport(Vector3(30, 1, 0)) # out of sight range
	_check(await _wait_until(func() -> bool: return kennel.contains(dog.global_position), 400), "after giving up it goes back to its patrol area")

	_course(Vector3(6, 1, 0))
	var pit := _area(Vector3(-4, 1, 0), _boxed(Vector3(8, 2, 8))) # x -8..0
	var b: Burrower = _enemy(Vector3(-6, 1, 0), {sight_radius = 20.0, lose_radius = 30.0, chase_area = pit}, BURROWER)
	await _wait_until(func() -> bool: return b.burrowed, 120)
	await _wait_until(func() -> bool: return not b.burrowed, 300)
	_check(b.global_position.x < 0.5, "a burrower stays inside its chase area too")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES** `-- sight_leash`. Expected: `FAIL a wall blocks sight…` and the chase-area checks fail.

- [ ] **Step 3: Implement sight, `last_seen`, the pursuit rules and the leash wiring** (per Interfaces)

- [ ] **Step 4: Run to verify it passes**

Run: **RUN ENEMIES** `-- sight_leash`, then a full **RUN ENEMIES**. Expected: `ENEMIES: OK` both times. Earlier sections use open courses, so sight changes nothing for them. If one fails, check it for terrain between the enemy and the player before changing anything.

- [ ] **Step 5: Commit**

```bash
git add enemy/ tests/enemy_test.gd
git commit -m "feat(enemy): line of sight, last seen, chase area leash"
```

---

### Task 4: Off-screen sleep

**Files:**
- Modify: `enemy/enemy.gd`, `tests/enemy_test.gd`

**Interfaces:**
- Produces:
  - `var asleep := false` and `set_asleep(on: bool) -> void`.
  - `_ready`:
    - when `sleep_off_screen and DisplayServer.get_name() != "headless"`, add a `VisibleOnScreenNotifier3D` child;
    - its `aabb` is the capsule grown by `screen_margin`: `AABB(Vector3(-0.4, -HALF_HEIGHT, -0.4) - Vector3.ONE * screen_margin, Vector3(0.8, 2 * HALF_HEIGHT, 0.8) + Vector3.ONE * 2 * screen_margin)`;
    - connect `screen_entered` → `set_asleep(false)` and `screen_exited` → `set_asleep(true)`;
    - start with `asleep = true`.
  - `_physics_process`: when `asleep` and `state_name != &"death"`, run `_doze(delta)` and return. That skips timers, stats, the state, fall damage, orient and animate.
  - `_doze(delta)` uses no rays:
    - FLY, or `swimming()`: velocity eases to zero, `move_and_slide()`;
    - otherwise: `move_planar(Vector3.ZERO, 0.0, delta)`, `apply_gravity(delta)`, `move_and_slide()`.
  - `debug_text()` appends `"\nasleep"` while asleep.

- [ ] **Step 1: Write `_test_sleep` (SECTIONS = 16)**

```gdscript
func _test_sleep() -> void:
	_course(Vector3(3, 1, 0))
	var e := _enemy(Vector3(0, 1, 0), {sight_radius = 10.0, attack_damage = 0.0})
	_check(not e.asleep, "headless: enemies never sleep by default")
	e.set_asleep(true)
	await _wait(60)
	_check(e.state_name == &"idle" and e.asleep, "asleep: no chase with the player in plain view")
	e.set_asleep(false)
	_check(await _wait_until(func() -> bool: return e.state_name == &"pursuit", 30), "awake again: the AI resumes")

	_course(Vector3(-30, 1, 0))
	var deck := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = _boxed(Vector3(4, 0.5, 4))
	deck.add_child(cs)
	deck.position = Vector3(0, 3, 0)
	course.add_child(deck)
	var rider := _enemy(Vector3(0, 4.2, 0), {sight_radius = 0.0})
	var bird := _enemy(Vector3(8, 1, 0), {abilities = Enemy.Ability.FLY, sight_radius = 0.0})
	await _wait(90)
	rider.set_asleep(true)
	bird.set_asleep(true)
	var bird_y := bird.global_position.y
	for i in 120:
		deck.position.x += 2.0 / 60.0
		await _wait(1)
	_check(absf(rider.global_position.x - deck.position.x) < 0.5 and rider.global_position.y > 3.0, "asleep on a moving platform: carried along")
	_check(absf(bird.global_position.y - bird_y) < 0.2, "an asleep flyer stays where it is")

	_kill(Vector3(20, 0.5, 0), Vector3(3, 1, 3))
	var dozer := _enemy(Vector3(20, 5, 0), {sight_radius = 0.0})
	dozer.set_asleep(true)
	var causes := _deaths(dozer)
	_check(await _gone(dozer, 240) and causes == [&"fall"], "asleep: still falls, dies in a kill zone and frees itself")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES** `-- sleep`. Expected: parse error, `asleep` / `set_asleep` not found.

- [ ] **Step 3: Implement** (per Interfaces)

- [ ] **Step 4: Run to verify it passes**

Run: **RUN ENEMIES** `-- sleep`, then a full **RUN ENEMIES**. Expected: `ENEMIES: OK` both times.

- [ ] **Step 5: Commit**

```bash
git add enemy/enemy.gd tests/enemy_test.gd
git commit -m "feat(enemy): sleep off screen, physics keeps running"
```

---

### Task 5: Crowd demo, docs, full verification

**Files:**
- Modify: `demo/enemies/crowd.tscn`, `demo/enemies/crowd.gd`, `docs/enemies.md`, `CLAUDE.md`, `tests/enemy_test.gd`

**Interfaces:**
- Consumes: everything above.
- Produces: `crowd.tscn` gets an `Areas` node with:
  - `PatrolNE`: a box;
  - `PatrolNW`: a cylinder;
  - `PatrolSE`: a sphere, centred at ground level;
  - `PatrolSW`: a box plus a cylinder;
  - `Chase`: one large box, about 70 × 6 × 70, centred.

  The patrol areas cover their quadrant of the spawn grid. `crowd.gd` gives each runner the patrol area of its quadrant (by the sign of x and z) and `chase_area = $Areas/Chase`. `help()` shows `awake: N / COUNT`, where N is the enemies with `not asleep`.

- [ ] **Step 1: Write `_test_crowd` (SECTIONS = 17), run after `_test_demo` in the `all` list**

```gdscript
func _test_crowd() -> void:
	var crowd: Node = load("res://demo/enemies/crowd.tscn").instantiate()
	root.add_child(crowd)
	await _wait(5)
	var enemies := get_nodes_in_group(&"enemy")
	var start := enemies.map(func(n: Enemy) -> Vector3: return n.global_position)
	_check(enemies.all(func(n: Enemy) -> bool: return n.patrol_area != null and n.chase_area != null), "crowd: every runner has a patrol and a chase area")
	await _wait(240)
	var moved := 0
	for i in enemies.size():
		if is_instance_valid(enemies[i]) and (enemies[i] as Enemy).global_position.distance_to(start[i]) > 1.0:
			moved += 1
	_check(moved >= 25, "crowd: runners patrol (%d moved)" % moved)
	crowd.queue_free()
	sections += 1
```

- [ ] **Step 2: Run to verify it fails**

Run: **RUN ENEMIES** `-- crowd`. Expected: `FAIL crowd: every runner has a patrol and a chase area`.

- [ ] **Step 3: Update `crowd.tscn` and `crowd.gd`** (per Interfaces; keep the user's existing constants and grid logic)

- [ ] **Step 4: Docs**

- `docs/enemies.md`: a section, "Patrol, sight, chase areas and sleeping off screen", covering:
  - adding an `EnemyArea` and the supported shapes;
  - sharing one area between enemies;
  - `patrol_area`, `chase_area`, `patrol_pause` and `memory_time`;
  - how spotting (sight + `sight_radius`), the leash, giving up and returning fit together;
  - what keeps running while asleep, plus `sleep_off_screen`, `screen_margin` and `set_asleep`.
- Add `patrol` to the state diagram and the `anim` table.
- `CLAUDE.md` Enemies paragraph: `EnemyArea`, patrol, sight, leash, sleep.

- [ ] **Step 5: Full verification**

Run the full **RUN ENEMIES**, plus the smoke, platform and puzzle suites from CLAUDE.md, `--editor --quit-after 400`, and `--quit-after 600` on both `res://demo/enemies/enemies.tscn` and `res://demo/enemies/crowd.tscn`. Expected: every suite `: OK`, no `ERROR` / `SCRIPT ERROR` lines.

- [ ] **Step 6: Commit**

```bash
git add demo/enemies/crowd.tscn demo/enemies/crowd.gd docs/enemies.md CLAUDE.md tests/enemy_test.gd
git commit -m "feat(demo): crowd demo patrols shared areas and sleeps off screen; docs"
```
