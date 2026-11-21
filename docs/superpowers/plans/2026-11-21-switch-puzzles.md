# Switch Puzzles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Weight plates (hold / latch), energy switches charged by shots, doors that open when every switch on their channel is on, weights (box, ball) that characters push and the player carries and throws, dispensers that keep a puzzle supplied, and gravity zones that flip enemies, NPCs and weights, all remembered across areas.

**Architecture:** Switch state lives in `World.switches`, keyed per placement (`Channels.id`), and switches and doors meet on a channel key (`Channels.key`) like platforms. A door counts the switches of its channel from a registry the editor bakes from every saved scene (`world/switch_registry.tres`) plus the switches loaded right now, so switches in unvisited areas count as off. Weights are `RigidBody3D`s with their own sticky gravity; `GameArea` writes their state into `World.bodies` every physics frame and restores it on load. `Door` and `EnergySwitch` reuse `MovingPlatform` as "a solid body shaped by `ShapeSet`".

**Tech Stack:** Godot 4.7.2 GDScript, Jolt physics, headless `SceneTree` test scripts, editor test harness `tests/editor_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-21-switch-puzzles-design.md`

## Global Constraints

- Godot `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` only. Shell preamble for every command below:
  ```sh
  GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
  NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"
  ```
- Every Godot run goes through `timeout` (a script error hangs Godot).
- **RUN SWITCHES** = `timeout 400 "$GODOT" --headless --path . -s res://tests/switch_test.gd 2>&1 | grep -viE "$NOISE"`; append `-- <section> ...` to run only those sections. Passes when the last line is `SWITCHES: OK`.
- **EDITOR ONCE** = `timeout 150 "$GODOT" --headless --path . --editor --quit-after 400`. Run it in a fresh worktree before any `-s` test, and after adding a `class_name` script (writes the `.uid` sidecar, registers the class). Commit every `.uid`.
- **`-s` compile order** (CLAUDE.md gotcha): tests never static-type `WeightPlate`, `EnergySwitch`, `Door`, `Dispenser`, `Npc`, `GameArea` or `Channels` (all reach the `World` autoload); they `load()` scripts and scenes at runtime and fetch World via `root.get_node("World")`. `WeightBody`, `Player`, `Enemy`, `Zone`, `GravityZone`, `KillZone`, `Projectile` never reference `World` or those classes statically: reach them by group (`&"npc"`, `&"door_switch"`, `&"aim_target"`) or `has_method`.
- Gravity can point anywhere: use `up_direction` / `gravity_dir`, never `Vector3.UP` or `velocity.y` in gameplay code.
- `World.switches` and `World.bodies` keys are `String`; registry kinds are the Strings `"hold"`, `"latch"`, `"energy"`.
- `Door`, `EnergySwitch`, `WeightPlate`, `Dispenser` are script-only nodes (like `Zone` and `MovingPlatform`): the registry tells kinds apart by script path (`res://puzzle/weight_plate.gd` + `mode`, `res://puzzle/energy_switch.gd`).
- Static typing, `##` doc comments, a `ponytail:` comment on every deliberate shortcut. `@tool` scripts guard runtime logic with `Engine.is_editor_hint()` and create child nodes in `_ready`, never as member defaults.
- Spec values: box `weight` 12, ball 4; weight `gravity` 32; push speed `speed * clampf(strength / weight, 0.05, 1.0)`; plate counts a body when `gravity_dir.dot(plate_up) < -0.7`; `time_to_close` 4.0, `max_shots` 3; door `open_offset` `(0, 3, 0)`, `open_time` 0.4; `carry_reach` 1.2 m within 60° of facing; drain `carry_cost * weight / 10` stamina/s; walk × `1 / (1 + weight * carry_slow)`; throw speed `throw_speed * clampf(10 / weight, 0.3, 1.5)`; dispenser `count` 1, `respawn_delay` 2.0; keys R `carry`, T `throw`.
- Plan values (spec left them to the builder): `carry_cost` 6.0, `carry_slow` 0.03, `throw_speed` 12.0, `hold_height` 1.5, player and NPC `push_strength` 6.0 (enemies push with their `weight`), plate `WARMUP` 3 physics frames, weight `linear_damp = weight * 0.05`, friction `clampf(0.4 + weight * 0.02, 0.4, 1.0)`.
- Don't touch `demo/demo.tscn`, `demo/builder/`, `.godot/editor/editor_layout.cfg`. Stage by explicit path, never `git add -A`. Commit after each task; don't push.
- Report every result as "headless only, game feel untested".

## Review Focus

1. A door, plate or switch with an empty channel, or a door whose channel has no switches at all → it stays shut, no script errors, a configuration warning says why (Task 5, `door`).
2. The world clock jumping far ahead (an area away for minutes, a clock skip) with energy charged → openness is clamped to 0..1, the door is shut, never negative or above 1 (Task 1, `world`).
3. A weight freed by other code (scene reload, a plain `queue_free`) while carried or while counted by a dispenser → `held` clears without errors and the dispenser replaces it (Task 3 `carry`, Task 7 `dispenser`).
4. Lifting a weight off a hold plate → the plate releases and its door closes; a carried weight never counts (Task 5, `plate`).
5. Something resting on a dispenser's spawn spot → the spawn waits until it is clear, never spawns inside a body (Task 7, `dispenser`).

---

### Task 1: World switch state and the registry resource

**Files:**
- Create: `puzzle/switch_registry.gd`
- Modify: `world/world.gd`
- Create: `tests/switch_test.gd`

**Interfaces:**
- Produces (`SwitchRegistry`, `class_name`, `extends Resource`): `const PATH := "res://world/switch_registry.tres"`; `@export var channels := {}` (channel key String → `Array` of `[switch id: String, kind: String]`).
- Produces (World):
  - `var switches := {}`: plate `{on = bool, locked = bool}`, energy `{shot_at = float, end = float}`.
  - `var bodies := {}` (filled by Tasks 2 and 7).
  - `var registry: SwitchRegistry`, loaded from `SwitchRegistry.PATH` in `_ready` when it exists, else `SwitchRegistry.new()`.
  - `func switches_of(channel: StringName) -> Array`: the registry's entries for the channel plus every node in group `&"door_switch"` whose `Channels.key(n, n.channel) == channel`, as `[n.switch_id(), n.kind()]`, de-duplicated by id.
  - `func press(channel: StringName, id: String, on: bool) -> void`, `func charge(channel: StringName, id: String, add: float, cap: float) -> void`, `func switch_on(id: String) -> bool`, `func energy(id: String) -> float` (0..1), `func openness(channel: StringName) -> float` (0..1), `func solved(channel: StringName) -> bool`.
  - `debug_text()` gains a `switches:` line.
- Produces (test harness `tests/switch_test.gd`): `fails`, `sections`, `course: Node3D`, `player: Player`, `world: Node`; helpers `_course(player_at := Vector3(-10, 1, 0))`, `_box(at, size) -> CSGBox3D`, `_press(action)`, `_wait(frames)`, `_wait_until(cond, frames) -> bool`, `_check(ok, what)`, the section runner with the `--` filter and `SECTIONS`, all copied in shape from `tests/npc_test.gd`. Each section increments `sections`; `SECTIONS` grows as tasks add sections (10 at the end: `world`, `weight`, `carry`, `gravity`, `plate`, `door`, `energy`, `dispenser`, `memory`, `demo`). Tests add their own `"t:..."` registry keys and never clear the registry.

- [ ] **Step 1: Write the failing test** (section `world`)

```gdscript
func _test_world() -> void:
	var reg: Dictionary = world.registry.channels
	reg["t:hold"] = [["t:H", "hold"]]
	world.press(&"t:hold", "t:H", true)
	_check(world.openness(&"t:hold") == 1.0 and world.switch_on("t:H"), "hold on: open")
	world.press(&"t:hold", "t:H", false)
	_check(world.openness(&"t:hold") == 0.0, "hold released: shut")
	reg["t:trio"] = [["t:A", "latch"], ["t:B", "latch"], ["u:Far", "latch"]]
	world.press(&"t:trio", "t:A", true)
	world.press(&"t:trio", "t:A", false)
	_check(not world.switch_on("t:A"), "a latch springs back while the others are off")
	world.press(&"t:trio", "t:A", true)
	world.press(&"t:trio", "t:B", true)
	_check(world.openness(&"t:trio") == 0.0 and not world.switches["t:A"].locked, "a switch in an unvisited area keeps the door shut")
	world.switches["u:Far"] = {on = true, locked = false} # its area left it held
	world.press(&"t:trio", "t:B", false)
	world.press(&"t:trio", "t:B", true)
	_check(world.switches["t:A"].locked and world.switches["u:Far"].locked and world.solved(&"t:trio"), "all on at once: every latch locks, loaded or not")
	world.press(&"t:trio", "t:A", false)
	_check(world.switch_on("t:A") and world.openness(&"t:trio") == 1.0, "a locked latch stays on")
	reg["t:mix"] = [["t:L", "latch"], ["t:M", "hold"]]
	world.press(&"t:mix", "t:L", true)
	world.press(&"t:mix", "t:M", true)
	world.press(&"t:mix", "t:M", false)
	_check(world.switches["t:L"].locked and not world.solved(&"t:mix") and world.openness(&"t:mix") == 0.0, "mixed: the latch locks, never solved, the hold plate still matters")
	reg["t:zap"] = [["t:E", "energy"]]
	world.charge(&"t:zap", "t:E", 4.0, 12.0)
	_check(world.openness(&"t:zap") == 1.0 and world.energy("t:E") == 1.0, "a shot opens at once")
	world.time += 2.0
	_check(is_equal_approx(world.openness(&"t:zap"), 0.5), "half the energy left: half open")
	for i in 3:
		world.charge(&"t:zap", "t:E", 4.0, 12.0)
	_check(is_equal_approx(world.switches["t:E"].end - world.time, 12.0), "shots stack up to the cap")
	world.time += 6.0
	_check(is_equal_approx(world.openness(&"t:zap"), 0.5), "slides shut over what is left")
	world.time += 1000.0
	_check(world.openness(&"t:zap") == 0.0 and not world.switch_on("t:E") and world.energy("t:E") == 0.0, "clock skip: empty and shut, never negative")
	reg["t:le"] = [["t:L2", "latch"], ["t:E2", "energy"]]
	world.charge(&"t:le", "t:E2", 4.0, 12.0)
	world.press(&"t:le", "t:L2", true)
	_check(world.switches["t:L2"].locked, "energy counts toward the all-on moment")
	_check(world.openness(&"t:none") == 0.0 and not world.solved(&"t:none"), "a channel with no switches: shut, not solved")
	_check(world.debug_text().contains("switches:"), "HUD lists switches")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails.** EDITOR ONCE, then `RUN SWITCHES -- world`. Expected: parse errors (`registry`, `press` not found).
- [ ] **Step 3: Implement `SwitchRegistry` and the World API.** `charge`: left = `maxf(end - time, 0)`, `end = time + minf(left + add, cap)`, `shot_at = time`. After every `press` and `charge`, if every switch of the channel is on, set `locked = true` on each latch entry (create missing entries). `openness`: 0 when the list is empty or any switch is off, else the smallest energy fraction `clampf((end - time) / (end - shot_at), 0, 1)` among energy switches, or 1. `solved`: non-empty, all latch, all locked. A missing entry is off. `# ponytail:` on `switches_of` (scans the group on every call; cache per frame if puzzles get big).
- [ ] **Step 4: Run** `RUN SWITCHES -- world` → `SWITCHES: OK`.
- [ ] **Step 5: Commit** `puzzle/switch_registry.gd(.uid)`, `world/world.gd`, `tests/switch_test.gd`: `feat(world): switch state, lock rule, energy and the switch registry`.

---

### Task 2: Weights: body, scenes, gravity, kill zones, pushing

**Files:**
- Create: `puzzle/weight_body.gd`, `puzzle/box.tscn`, `puzzle/ball.tscn`
- Modify: `world/zone.gd`, `world/gravity_zone.gd`, `world/kill_zone.gd`, `player/player.gd` (`_physics_process`, new `push_strength` export)
- Test: `tests/switch_test.gd` (section `weight`)

**Interfaces:**
- Produces (`WeightBody`, `@tool`, `class_name`, `extends RigidBody3D`, group `&"weight"`, never references `World`):
  - `@export var weight := 12.0` (sets `mass`), `@export var gravity := 32.0`, `@export var color := Color(0.75, 0.6, 0.4)`.
  - `var gravity_dir := Vector3.DOWN`, `var carrier: Node3D`, `var gone := false`, `var dispensed := false`.
  - `signal destroyed`, `signal cue(name: StringName)` (`land` on an impact over 6 m/s, `destroy`).
  - `func set_gravity_dir(dir: Vector3) -> void`: `gravity_scale = 0`, `constant_force = gravity_dir * gravity * mass`, wakes the body.
  - `func push(dir: Vector3, speed: float, strength: float) -> void`: planar velocity (relative to its own up) toward `dir * speed * clampf(strength / weight, 0.05, 1.0)`.
  - `static func push_from(body: CharacterBody3D, strength: float, speed: float) -> void`: for each slide collision of `body` whose collider is a `WeightBody` without a `carrier`, if the normal slid along `body.up_direction` is longer than 0.5 (side contact, not standing on it), calls `push(-that_normal.normalized(), speed, strength)`.
  - `func destroy() -> void`: `gone = true`, emits `cue(&"destroy")` and `destroyed`, `queue_free()`.
  - `func state() -> Dictionary` → `{pos = Vector3, basis = Basis, gravity = Vector3}`; `func restore(s: Dictionary) -> void`.
  - Visual: `ShapeSet.setup(self, mat, true)` in `_ready` (a lit mesh of its shapes, as `MovingPlatform` does).
- Produces (Zone): `func _npc_entered(_n: Node3D)`, `func _npc_exited(_n: Node3D)`, `func _weight_entered(_w: WeightBody)`, `func _weight_exited(_w: WeightBody)`. Dispatch order in `_on_body_entered`/`_exited`: `Player`, `Enemy`, `WeightBody`, then `b.is_in_group(&"npc")`.
- Produces (GravityZone): `_weight_entered` calls `w.set_gravity_dir(gravity_dir)` (enemies and NPCs come in Task 4). KillZone: `_weight_entered` calls `w.destroy()`.
- Produces (Player): `@export var push_strength := 6.0` (group "Carry", created here); `_physics_process` calls `WeightBody.push_from(self, push_strength, walk_speed)` right after `state.physics(delta)`.
- `puzzle/box.tscn`: `WeightBody` root, `CollisionShape3D` with a 1 × 1 × 1 `BoxShape3D`, weight 12. `puzzle/ball.tscn`: `SphereShape3D` radius 0.45, weight 4, `color = Color(0.45, 0.6, 0.8)`.
- Test helpers added: `_weight(at: Vector3, scene := BOX, w := -1.0) -> WeightBody` (`w` ≥ 0 sets `weight` before `add_child`); `_zone(script: GDScript, at: Vector3, size: Vector3) -> Zone`; `const BOX := preload("res://puzzle/box.tscn")`, `const BALL := preload("res://puzzle/ball.tscn")`.

- [ ] **Step 1: Write the failing test** (section `weight`)

```gdscript
func _test_weight() -> void:
	_course()
	var b := _weight(Vector3(0, 2, 0))
	await _wait(60)
	_check(b.linear_velocity.length() < 0.1 and absf(b.global_position.y - 0.5) < 0.05, "falls and rests on the floor")
	_check(is_equal_approx(b.mass, 12.0) and b.gravity_scale == 0.0 and b.is_in_group(&"weight"), "mass = weight, own gravity")
	_box(Vector3(0, 8.5, 0), Vector3(6, 1, 6)) # ceiling, underside at y 8
	b.set_gravity_dir(Vector3.UP)
	await _wait(60)
	_check(absf(b.global_position.y - 7.5) < 0.1, "flipped: falls up onto the ceiling and stays")
	var gz: GravityZone = _zone(GravityZone, Vector3(10, 2, 0), Vector3(3, 4, 3))
	gz.gravity_dir = Vector3.UP
	var c := _weight(Vector3(10, 0.5, 0))
	await _wait(5)
	_check(c.gravity_dir == Vector3.UP, "a gravity zone sets a weight's gravity on entry")
	var gone := [false]
	var k := _weight(Vector3(-20, 3, 0))
	k.destroyed.connect(func() -> void: gone[0] = true)
	_zone(KillZone, Vector3(-20, 0.5, 0), Vector3(3, 1, 3))
	await _wait(40)
	_check(gone[0] and not is_instance_valid(k), "a kill zone destroys a weight")
	# pushing: the same walk into a heavy box and a light ball
	var moved: Array[float] = []
	for scene_w: Array in [[BOX, 30.0], [BALL, 4.0]]:
		_course(Vector3(-3, 1, 0))
		var w := _weight(Vector3(0, 0.5, 0), scene_w[0], scene_w[1])
		await _wait(20)
		Input.action_press(&"move_right")
		await _wait(90)
		Input.action_release(&"move_right")
		await _wait(30)
		moved.append(w.global_position.x)
	_check(moved[0] > 0.3 and moved[1] > moved[0] * 2.0, "walking into weights pushes them; the light one goes much farther")
	_course(Vector3(0, 2, 0))
	var under := _weight(Vector3(0, 0.5, 0))
	await _wait(40)
	_check(_flat(under.global_position).length() < 0.05 and player.is_on_floor(), "standing on a weight doesn't push it")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- weight`: `res://puzzle/box.tscn` missing.
- [ ] **Step 3: Implement** `WeightBody`, the two scenes, the Zone hooks, GravityZone/KillZone overrides and the player's push call, per Interfaces. `_ready` (runtime only): `mass = weight`, `linear_damp = weight * 0.05`, a `PhysicsMaterial` with friction `clampf(0.4 + weight * 0.02, 0.4, 1.0)`, `set_gravity_dir(gravity_dir)`, `contact_monitor = true`, `max_contacts_reported = 4` (for the `land` cue).
- [ ] **Step 4: Run** EDITOR ONCE, `RUN SWITCHES -- world weight` → `SWITCHES: OK`; `timeout 150 "$GODOT" --headless --path . -s res://tests/smoke_test.gd 2>&1 | grep -viE "$NOISE"` → `SMOKE: OK`.
- [ ] **Step 5: Commit** `puzzle/weight_body.gd(.uid)`, `puzzle/box.tscn`, `puzzle/ball.tscn`, `world/zone.gd`, `world/gravity_zone.gd`, `world/kill_zone.gd`, `player/player.gd`, `tests/switch_test.gd`: `feat(puzzle): weights with their own gravity, pushed by walking into them`.

---

### Task 3: Carrying, putting down, throwing

**Files:**
- Modify: `project.godot` (actions `carry` = R, physical keycode 82; `throw` = T, 84; no gamepad binding yet)
- Modify: `player/player.gd`, `player/states/jump.gd`, `player/states/swim.gd`, `world/scene_door.gd`, `world/area.gd` (`HELP` mentions `R carry / put down | T throw`)
- Test: `tests/switch_test.gd` (section `carry`)

**Interfaces:**
- Consumes: `WeightBody` (Task 2).
- Produces (Player, group "Carry"): `@export var carry_reach := 1.2`, `carry_cost := 6.0` (stamina/s per 10 weight), `carry_slow := 0.03`, `throw_speed := 12.0`, `hold_height := 1.5`; `var held: WeightBody`; `signal cue(name: StringName)` (`lift`, `put_down`, `throw`, `blocked`).
  - `func weight_in_reach() -> WeightBody`: nearest group `&"weight"` body whose planar centre distance is ≤ `carry_reach + 0.25` (so a weight just put down can be lifted again), within 60° of `facing`, not the floor collider under the player, not carried.
  - `func lift() -> bool`: only from `idle`/`walk`/`run` and not `exhausted`; sets `held`, `held.carrier = self`, `freeze_mode = FREEZE_MODE_KINEMATIC`, `freeze = true`, saves and zeroes its `collision_layer`/`collision_mask`; `cue(&"lift")`.
  - `func put_down() -> bool`: the spot `carry_reach` in front, raised along `up_direction` by half the weight's bounds height; refused (returns false, `cue(&"blocked")`, weight stays held) when an `intersect_shape` of the weight's shapes there hits anything but the player; else releases with zero velocity, `cue(&"put_down")`.
  - `func throw_held() -> void`: releases at the hold point with velocity `(facing + up_direction * 0.5).normalized() * throw_speed * clampf(10.0 / held.weight, 0.3, 1.5) + planar()`.
  - `func drop_held() -> void`: releases in place with the player's velocity. All releases restore layers, unfreeze, `set_gravity_dir(gravity_dir)` (the player's), clear `carrier` and `held`.
  - `func carry_factor() -> float`: `1 / (1 + held.weight * carry_slow)`, or 1.
- Behaviour: `_physics_process`, before `state.physics`: `carry` just pressed → `put_down()` if holding, else `lift()`; `throw` just pressed while holding → `throw_held()`. After `state.physics`: if `held` was freed, clear it; else place it at `global_position + up_direction * hold_height` with the player's basis. `move_ground` multiplies speed by `carry_factor()`. `can_run()` is false while holding. `ground_step` skips dash, attack and climb while holding; `jump.gd` skips attack, dash and grab; `swim.gd` `enter` calls `drop_held()`; shoot is skipped while holding. `_tick_stats`: no regen while holding; drains `carry_cost * held.weight / 10 * mult(&"stamina_cost")` per second; at 0 → `exhausted`, `exhaust_t = exhaust_time`, `drop_held()`. `damage()` and `die()` call `drop_held()` first. `SceneDoor._player_entered` calls `p.drop_held()` before changing scene. `anim`: `carry_idle` / `carry_walk` replace `idle`/`walk` while holding.

- [ ] **Step 1: Write the failing test** (section `carry`)

```gdscript
func _test_carry() -> void:
	_course(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	var b := _weight(Vector3(1, 0.5, 0))
	await _wait(30)
	await _press(&"carry")
	_check(player.held == b and b.freeze and b.collision_layer == 0 and b.carrier == player, "carry lifts the weight in front")
	await _wait(2)
	_check((b.global_position - player.global_position).dot(player.up_direction) > 1.2, "held over the head")
	var s0 := player.stamina
	await _wait(60)
	_check(absf((s0 - player.stamina) - 7.2) < 1.0, "drains carry_cost * weight / 10 per second")
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _wait(40)
	_check(player.state_name == &"walk" and absf(player.planar().length() - 4.5 / 1.36) < 0.3, "no running; walk slowed by weight")
	Input.action_release(&"run")
	Input.action_release(&"move_right")
	await _press(&"dash")
	await _press(&"attack")
	_check(player.state_name in [&"idle", &"walk"] and player.held == b, "dash and melee ignored while carrying")
	await _wait(20)
	var x0 := player.global_position.x
	await _press(&"carry")
	await _wait(30)
	_check(player.held == null and not b.freeze and absf(b.global_position.x - x0 - 1.2) < 0.4, "carry again puts it down in front")
	await _press(&"carry")
	_box(player.global_position + Vector3(1.2, 0.5, 0), Vector3(0.5, 3, 3))
	await _press(&"carry")
	_check(player.held == b, "no room in front: put down refused")
	player.set_gravity_dir(Vector3.UP)
	player.drop_held()
	_check(b.gravity_dir == Vector3.UP, "a released weight takes the player's gravity")
	player.respawn(Vector3(0, 1, 0))
	await _wait(30)
	var throws: Array[float] = []
	for s: PackedScene in [BOX, BALL]:
		_course(Vector3(0, 1, 0))
		player.facing = Vector3.RIGHT
		var w := _weight(Vector3(1, 0.5, 0), s)
		await _wait(30)
		await _press(&"carry")
		await _press(&"throw")
		await _wait(90)
		throws.append(w.global_position.x)
	_check(throws[0] > 3.0 and throws[1] > throws[0] + 2.0, "throw flies; the lighter weight farther")
	_course(Vector3(0, 1, 0))
	var h := _weight(Vector3(1, 0.5, 0))
	await _wait(30)
	player.facing = Vector3.RIGHT
	await _press(&"carry")
	player.damage(5)
	_check(player.held == null and not h.freeze, "hurt: drops it")
	await _wait(60)
	await _reset_lift(h) # player back at the origin facing +x, h 1 m in front, settled
	player.stamina = 0.5
	await _press(&"carry")
	await _wait(10)
	_check(player.held == null and player.exhausted, "out of stamina: drops it, exhausted")
	await _reset_lift(h)
	await _press(&"carry")
	_check(player.held == null, "can't lift while exhausted")
	player.exhausted = false
	player.stamina = player.max_sp()
	await _press(&"carry")
	_check(player.held == h, "lifts again once rested")
	h.queue_free()
	await _wait(3)
	_check(player.held == null, "a carried weight freed by other code: held clears")
	var under := _weight(Vector3(5, 0.5, 0))
	player.teleport(Vector3(5, 1.8, 0))
	await _wait(30)
	await _press(&"carry")
	_check(player.held == null, "never lifts the weight it stands on")
	sections += 1
```

(`_reset_lift(w)`: `player.teleport(Vector3(0, 1, 0))`, `player.facing = Vector3.RIGHT`, `w.global_position = Vector3(1, 0.5, 0)`, `w.linear_velocity = Vector3.ZERO`, wait 20 frames.)

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- carry`: `held` not found.
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run** EDITOR ONCE, `RUN SWITCHES -- world weight carry` → `SWITCHES: OK`; smoke suite → `SMOKE: OK`; `timeout 150 "$GODOT" --headless --path . -s res://tests/puzzle_test.gd 2>&1 | grep -viE "$NOISE"` → `PUZZLES: OK`.
- [ ] **Step 5: Commit** `project.godot`, `player/player.gd`, `player/states/jump.gd`, `player/states/swim.gd`, `world/scene_door.gd`, `world/area.gd`, `tests/switch_test.gd`: `feat(player): carry, put down and throw weights`.

---

### Task 4: Gravity zones and pushing for enemies and NPCs

**Files:**
- Modify: `enemy/enemy.gd`, `npc/npc.gd`, `world/gravity_zone.gd`
- Test: `tests/switch_test.gd` (section `gravity`)

**Interfaces:**
- Consumes: Zone hooks and `WeightBody.push_from` (Task 2).
- Produces (Enemy): `func set_gravity_dir(dir: Vector3) -> void` (`up_direction = -dir.normalized()`); `_physics_process` calls `WeightBody.push_from(self, weight, run_speed)` after `state.physics`; `_exclude()` also lists group `&"weight"` bodies, so probes see a weight as open ground and a chasing enemy walks into it (and pushes it) instead of giving up or jumping it.
- `# ponytail:` in `enemy.gd` near `set_gravity_dir`: climb, swing, fly and solved jumps under flipped gravity are untested (only walking and chasing on a ceiling are); mirror an `enemy_test` course upside down when a puzzle needs them.
- Produces (Npc): `var gravity_dir := Vector3.DOWN`; `func set_gravity_dir(dir: Vector3) -> void` (sets `gravity_dir`, `up_direction`, `_moved = true`); `@export var push_strength := 6.0`; `_move` falls along `gravity_dir * get_gravity().length()` instead of `get_gravity()`; `save_position` stores `m.gravity = gravity_dir`; `_start` restores it (`set_gravity_dir`) before the position; `_physics_process` calls `WeightBody.push_from(self, push_strength, walk_speed)` after `_move`. The walk-timeout snap only happens when `up_direction` matches the up the marks were cached under (`_marks_up`, dot > 0.99); otherwise the walk ends where the NPC stands (counts as arrived). `_visual.position` already uses local `Vector3.UP`: leave it.
- Produces (GravityZone): `_enemy_entered(e)` → `e.set_gravity_dir(gravity_dir)`; `_npc_entered(n)` → `n.set_gravity_dir(gravity_dir)` (duck-typed).
- Test helpers added: `const RUNNER := "res://enemy/runner/runner.tscn"`, `const NPC := "res://npc/npc.tscn"`; `_npc(at, npc_name := "") -> Node3D` (load, name, `add_child`), as in `tests/npc_test.gd`.

- [ ] **Step 1: Write the failing test** (section `gravity`)

```gdscript
func _test_gravity() -> void:
	world.reset_story()
	_course(Vector3(-30, 1, 0))
	_box(Vector3(0, 10.5, 0), Vector3(80, 1, 30)) # ceiling, underside at y 10
	var e: Enemy = load(RUNNER).instantiate()
	e.position = Vector3(5, 1, 0)
	course.add_child(e)
	var n := _npc(Vector3(-5, 1, 0), "Flipper")
	var gz: GravityZone = _zone(GravityZone, Vector3(0, 1, 0), Vector3(20, 2, 6))
	gz.gravity_dir = Vector3.UP
	await _wait(120)
	_check(e.up_direction.is_equal_approx(Vector3.DOWN) and e.is_on_floor() and e.global_position.y > 8.5, "an enemy flips and stands on the ceiling")
	_check(n.up_direction.is_equal_approx(Vector3.DOWN) and n.is_on_floor() and n.global_position.y > 8.5, "an NPC flips too")
	n.save_position()
	_check(world.npcs[n.memory_id()].gravity == Vector3.UP, "NPC memory keeps its gravity")
	course.remove_child(n)
	n.free()
	var again := _npc(Vector3(-5, 1, 0), "Flipper")
	await _wait(10)
	_check(again.gravity_dir == Vector3.UP and again.global_position.y > 8.5, "re-instanced NPC is back on the ceiling, still flipped")
	player.teleport(Vector3(-2, 1, 0)) # into the zone: up to the ceiling as well
	await _wait(45)
	var gap := e.global_position.distance_to(player.global_position)
	await _wait(90)
	_check(player.up_direction.is_equal_approx(Vector3.DOWN) and e.global_position.distance_to(player.global_position) < gap - 2.0, "a flipped enemy chases a flipped player along the ceiling")
	# pushing: an enemy chasing the player shoves a box in its way; an NPC walking to a mark does too
	_course(Vector3(-6, 1, 0))
	var box := _weight(Vector3(0, 0.5, 0))
	var chaser: Enemy = load(RUNNER).instantiate()
	chaser.position = Vector3(3, 1, 0)
	course.add_child(chaser)
	await _wait(150)
	_check(box.global_position.x < -0.3, "an enemy walking into a weight pushes it")
	_course(Vector3(-20, 1, 10))
	var box2 := _weight(Vector3(0, 0.5, 0))
	var walker := _npc(Vector3(3, 1, 0), "Walker")
	await _wait(10)
	walker.walk_to(Vector3(-4, 0, 0))
	await _wait(150)
	_check(box2.global_position.x < -0.3, "an NPC walking into a weight pushes it")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- gravity`: enemy and NPC never flip.
- [ ] **Step 3: Implement** per Interfaces. If the runner doesn't chase toward −x as set up, move the player so the box lies on the chase line; keep the assertion.
- [ ] **Step 4: Run** `RUN SWITCHES` → `SWITCHES: OK`; `timeout 300 "$GODOT" --headless --path . -s res://tests/enemy_test.gd 2>&1 | grep -viE "$NOISE"` → `ENEMIES: OK`; `timeout 300 "$GODOT" --headless --path . -s res://tests/npc_test.gd 2>&1 | grep -viE "$NOISE"` → `NPCS: OK`.
- [ ] **Step 5: Commit** `enemy/enemy.gd`, `npc/npc.gd`, `world/gravity_zone.gd`, `tests/switch_test.gd`: `feat(world): gravity zones flip enemies and NPCs; they push weights`.

---

### Task 5: Weight plates and doors

**Files:**
- Create: `puzzle/weight_plate.gd`, `puzzle/door.gd`
- Modify: `world/moving_platform.gd` (doc comment only: Door and EnergySwitch reuse it as a solid `ShapeSet` body)
- Test: `tests/switch_test.gd` (sections `plate`, `door`)

**Interfaces:**
- Consumes: World API (Task 1), `WeightBody` (Task 2), carrying (Task 3).
- Produces (`WeightPlate`, `@tool`, `class_name`, `extends Zone`, group `&"door_switch"`):
  - `enum Mode { HOLD, LATCH }`, `@export var channel: StringName`, `@export var mode := Mode.HOLD`, `@export var on_color := Color(0.3, 1.0, 0.4, 0.5)`, `@export var locked_color := Color(1.0, 0.8, 0.3, 0.5)`, `const WARMUP := 3`.
  - `var pressed := false`, `signal cue(name: StringName)` (`press`, `release`, `lock`).
  - `func kind() -> String` (`"hold"` / `"latch"`), `func switch_id() -> String` (`Channels.id(self)`), `func is_on() -> bool` (`World.switch_on`), `func counts(b: Node3D) -> bool` (player, enemy, NPC or weight without a `carrier`, whose gravity, `-up_direction` for characters, satisfies `dot(global_basis.y) < -0.7`).
  - Runtime `_physics_process`: after `WARMUP` frames, `pressed = get_overlapping_bodies().any(counts)`; on a change, `World.press(Channels.key(self, channel), switch_id(), pressed)` and a `cue`. Never writes in `_exit_tree`. Colour: `locked_color` when locked, `on_color` when on, else `color`; while on, its drawn mesh (the Zone's internal `ShapeMesh` child) sits 0.05 m lower along the plate's up. Configuration warning when `channel` is empty.
- Produces (`Door`, `@tool`, `class_name`, `extends MovingPlatform`):
  - `@export var channel: StringName`, `@export var open_offset := Vector3(0, 3, 0)`, `@export var open_time := 0.4`, `var amount := 0.0`, `signal cue(name: StringName)` (`open`, `close`, `locked`), `func locked() -> bool` (`World.solved`).
  - Runtime: `_ready` stores the closed position and snaps `amount` to `World.openness(...)` (no first-frame sweep). Each physics frame: target = `World.openness(Channels.key(self, channel))`; opening `amount = move_toward(amount, target, delta / open_time)`; closing `amount = maxf(target, amount - delta / open_time)` (follows a slow energy slide exactly, else closes in `open_time`). Position = closed + `basis * open_offset * amount`.
  - Push-out, before a closing move: `intersect_shape` with each of its shapes at the new transform; every `CharacterBody3D` or `WeightBody` hit is moved along the door's thinnest local axis perpendicular to `open_offset`, to the side its centre is on, to `half thickness + 0.6` m from the door's centre plane (`Player.teleport` for the player, `global_position` + `reset_physics_interpolation()` otherwise).
  - Configuration warnings: empty `channel`; no other warning from `MovingPlatform` (override `_get_configuration_warnings`).
- Test helpers added: `_plate(at: Vector3, ch: StringName, latch := false, rot := Vector3.ZERO) -> Area3D` (load `res://puzzle/weight_plate.gd`, a 2 × 0.3 × 2 box shape, `rotation = rot`), `_door(at: Vector3, ch: StringName) -> AnimatableBody3D` (load `res://puzzle/door.gd`, a 4 × 3 × 0.4 box shape).

- [ ] **Step 1: Write the failing tests** (sections `plate`, `door`)

```gdscript
func _test_plate() -> void:
	world.reset_story()
	_course(Vector3(-10, 1, 0))
	var hold := _plate(Vector3(0, 0.15, 0), &"p_hold")
	await _wait(10)
	_check(not hold.pressed and hold.kind() == "hold" and hold.is_in_group(&"door_switch"), "empty hold plate")
	player.teleport(Vector3(0, 1, 0))
	await _wait(10)
	_check(hold.pressed and world.switch_on(hold.switch_id()), "the player presses it")
	player.teleport(Vector3(-10, 1, 0))
	await _wait(10)
	_check(not hold.pressed, "stepping off releases it")
	var b := _weight(Vector3(0.8, 1.5, 0)) # on the plate's +x half
	await _wait(40)
	_check(hold.pressed, "a weight presses it")
	player.teleport(Vector3(1.9, 1, 0)) # off the plate, 1.1 m from the weight
	player.facing = Vector3.LEFT
	await _wait(10)
	await _press(&"carry")
	await _wait(5)
	_check(player.held == b and not hold.pressed, "lifting the weight off releases it; carried weights never count")
	player.drop_held()
	b.queue_free()
	player.teleport(Vector3(-10, 1, 0))
	var e: Enemy = load(RUNNER).instantiate()
	e.position = Vector3(0, 1, 0)
	course.add_child(e)
	e.start_puppet() # stands still instead of chasing the player off the plate
	await _wait(20)
	_check(hold.pressed, "an enemy presses it")
	e.queue_free()
	var n := _npc(Vector3(0, 1, 0))
	await _wait(20)
	_check(hold.pressed, "an NPC presses it")
	n.queue_free()
	_box(Vector3(15.5, 1.5, 0), Vector3(1, 3, 3)) # a wall, face at x 15
	var wall := _plate(Vector3(14.85, 1, 0), &"p_wall", false, Vector3(0, 0, deg_to_rad(90))) # face points -x, slab x 14.7..15
	var shoved := _weight(Vector3(13.8, 0.5, 0))
	shoved.linear_velocity = Vector3(3, 0, 0)
	await _wait(30)
	_check(not wall.pressed, "a weight shoved sideways against a wall plate doesn't count")
	shoved.set_gravity_dir(Vector3.RIGHT)
	await _wait(30)
	_check(wall.pressed, "with gravity into the plate it counts")
	_box(Vector3(30, 8.5, 0), Vector3(6, 1, 6))
	var ceiling := _plate(Vector3(30, 7.85, 0), &"p_ceil", false, Vector3(deg_to_rad(180), 0, 0))
	var up := _weight(Vector3(30, 0.5, 0))
	up.set_gravity_dir(Vector3.UP)
	await _wait(60)
	_check(ceiling.pressed, "a weight that fell up onto a ceiling plate presses it")
	world.registry.channels["t:warm"] = []
	world.switches["/root/Course/Warm"] = {on = true, locked = false}
	var warm := _plate(Vector3(-25, 0.15, 0), &"t:warm")
	warm.name = "Warm"
	await _wait(1)
	_check(world.switch_on("/root/Course/Warm"), "warmup: a loading plate doesn't release its saved state at once")
	await _wait(WARMUP_FRAMES + 2)
	_check(not world.switch_on("/root/Course/Warm"), "after warmup it reads what is really on it")
	# latch trio: springs back until both are on at once, then locks
	var la := _plate(Vector3(40, 0.15, 0), &"p_latch", true)
	var lb := _plate(Vector3(44, 0.15, 0), &"p_latch", true)
	player.teleport(Vector3(40, 1, 0))
	await _wait(10)
	player.teleport(Vector3(37, 1, 0))
	await _wait(10)
	_check(not la.is_on(), "a latch springs back while the other is off")
	_weight(Vector3(44, 1.5, 0))
	player.teleport(Vector3(40, 1, 0))
	await _wait(40)
	player.teleport(Vector3(37, 1, 0))
	await _wait(10)
	_check(la.is_on() and lb.is_on() and world.solved(&"p_latch"), "both on at once: both lock, solved")
	sections += 1


func _test_door() -> void:
	_course(Vector3(-10, 1, 0))
	_plate(Vector3(0, 0.15, 0), &"d_hold")
	var door := _door(Vector3(0, 1.5, 5), &"d_hold")
	await _wait(10)
	_check(door.amount == 0.0 and door._get_configuration_warnings().is_empty(), "shut, no warnings")
	player.teleport(Vector3(0, 1, 0))
	await _wait(30)
	_check(door.amount == 1.0 and door.position.is_equal_approx(Vector3(0, 4.5, 5)), "opens by open_offset within open_time")
	player.teleport(Vector3(0, 1, 5)) # in the doorway
	await _wait(40)
	_check(door.amount == 0.0 and absf(player.global_position.z - 5.0) > 0.7, "closing pushes the player out of the doorway, no crush")
	var lonely := _door(Vector3(10, 1.5, 5), &"")
	var orphan := _door(Vector3(20, 1.5, 5), &"nobody")
	await _wait(10)
	_check(lonely.amount == 0.0 and not lonely._get_configuration_warnings().is_empty() and orphan.amount == 0.0, "no channel / no switches: shut, warned, no errors")
	sections += 1
```

(`const WARMUP_FRAMES := 3` in the test mirrors `WeightPlate.WARMUP`; tests can't type `WeightPlate`.)

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- plate door`: `res://puzzle/weight_plate.gd` missing.
- [ ] **Step 3: Implement** `WeightPlate` and `Door` per Interfaces.
- [ ] **Step 4: Run** EDITOR ONCE, `RUN SWITCHES` → `SWITCHES: OK`; `timeout 150 "$GODOT" --headless --path . -s res://tests/platform_test.gd 2>&1 | grep -viE "$NOISE"` → `PLATFORMS: OK`.
- [ ] **Step 5: Commit** `puzzle/weight_plate.gd(.uid)`, `puzzle/door.gd(.uid)`, `world/moving_platform.gd`, `tests/switch_test.gd`: `feat(puzzle): weight plates (hold, latch) and doors`.

---

### Task 6: Energy switch, shots and aim assist

**Files:**
- Create: `puzzle/energy_switch.gd`
- Modify: `world/projectile.gd` (`_finish`), `player/player.gd` (`aim_dir`)
- Test: `tests/switch_test.gd` (section `energy`)

**Interfaces:**
- Consumes: World `charge`/`energy` (Task 1), `Door` (Task 5).
- Produces (`EnergySwitch`, `@tool`, `class_name`, `extends MovingPlatform`, groups `&"door_switch"` and `&"aim_target"`): `@export var channel: StringName`, `@export var time_to_close := 4.0`, `@export var max_shots := 3`, `@export var on_color := Color(0.4, 0.85, 1.0)`; `signal cue(name: StringName)` (`charge`, `empty`); `func shot() -> void` (`World.charge(key, switch_id(), time_to_close, time_to_close * max_shots)`); `func kind() -> String` (`"energy"`), `func switch_id() -> String`, `func fraction() -> float` (`World.energy`). Visual: colour lerps `color` → `on_color` and emission follows `fraction()`. Warning when `channel` is empty.
- Produces (Projectile): `_finish` calls `target.shot()` when `target.has_method(&"shot")`, and counts it as landed.
- Produces (Player): `aim_dir()` also considers group `&"aim_target"` nodes, same range, 25° cone and line of sight (a ray from the chest excluding the player that hits that node).
- Test helper added: `_energy(at: Vector3, ch: StringName) -> AnimatableBody3D` (load `res://puzzle/energy_switch.gd`, a 0.6 m box shape).

- [ ] **Step 1: Write the failing test** (section `energy`)

```gdscript
func _test_energy() -> void:
	_course(Vector3(0, 1, 0))
	var sw := _energy(Vector3(0.8, 1.3, -8), &"e_ch") # slightly off the facing line
	var door := _door(Vector3(6, 1.5, 0), &"e_ch")
	player.facing = Vector3.FORWARD
	await _wait(10)
	var to: Vector3 = (sw.global_position - (player.global_position + player.up_direction * 0.3)).normalized()
	_check(player.aim_dir().dot(to) > 0.99 and sw.kind() == "energy", "aim assist finds the switch")
	await _press(&"shoot")
	await _wait(45) # the shot's flight, then open_time
	_check(door.amount > 0.8 and absf(door.amount - sw.fraction()) < 0.02, "a shot opens the door at once; it then follows the energy")
	await _wait_until(func() -> bool: return sw.fraction() <= 0.5, 240)
	_check(absf(door.amount - 0.5) < 0.05, "half the energy gone: half shut")
	for i in 3:
		await _press(&"shoot")
		await _wait(25)
	var e: Dictionary = world.switches[sw.switch_id()]
	_check(is_equal_approx(e.end - e.shot_at, 12.0), "more shots stack, capped at time_to_close x max_shots")
	var end_before: float = e.end
	player.teleport(Vector3(0.8, 1, -7)) # melee range of the switch
	await _press(&"attack")
	await _wait(30)
	_check(world.switches[sw.switch_id()].end == end_before, "melee doesn't charge it")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- energy`: script missing.
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run** EDITOR ONCE, `RUN SWITCHES` → `SWITCHES: OK`; enemy suite → `ENEMIES: OK` (aim assist and projectile changed); `timeout 150 "$GODOT" --headless --path . -e res://tests/shape_editor_test.tscn -- --shape-editor-test 2>&1 | grep -viE "$NOISE"` → `SHAPE EDITOR: OK`.
- [ ] **Step 5: Commit** `puzzle/energy_switch.gd(.uid)`, `world/projectile.gd`, `player/player.gd`, `tests/switch_test.gd`: `feat(puzzle): energy switch charged by shots, in aim assist`.

---

### Task 7: Dispenser and weight memory

**Files:**
- Create: `puzzle/dispenser.gd`
- Modify: `world/area.gd`
- Test: `tests/switch_test.gd` (sections `dispenser`, `memory`)

**Interfaces:**
- Consumes: `WeightBody` (`state`, `restore`, `destroyed`, `dispensed`), World `bodies`, `solved` (Tasks 1, 2).
- Produces (`Dispenser`, `@tool`, `class_name`, `extends Node3D`): `@export var channel: StringName`, `@export var weight_scene: PackedScene = preload("res://puzzle/box.tscn")`, `@export var count := 1`, `@export var respawn_delay := 2.0`; `signal cue(name: StringName)` (`spawn`); `func weights() -> Array[WeightBody]` (its live children).
  - Children are named `Weight1`…`WeightN` (lowest free index) with `dispensed = true`.
  - Memory: `World.bodies[Channels.id(self)] = {alive = PackedStringArray}`, updated on every spawn and loss; a lost weight's own entry (`Channels.id(self) + "/" + name`) is erased. Runtime `_ready` recreates the remembered names first (positions come from `GameArea`, below).
  - `_physics_process`: prune freed children (a plain `queue_free` counts as lost); each lost weight starts a `respawn_delay` timer; when `World.solved(Channels.key(self, channel))` (empty channel: never), no timers run and nothing spawns. Missing weights with no timer (the initial top-up) spawn at once. At most one spawn per physics frame, and only when an `intersect_shape` of the weight's shapes at the dispenser's position hits nothing.
- Produces (GameArea): `_ready` restores every group `&"weight"` node from `World.bodies[Channels.id(w)]` (`{gone = true}` → `queue_free`, else `restore`), and for weights not `dispensed` connects `destroyed` → `World.bodies[id] = {gone = true}`. `_physics_process` writes `w.state()` for every weight that isn't `gone`. `_process`: a weight farther than `bounds_radius` from `bounds_center` is `destroy()`ed.
- Test helpers added: `_dispenser(at: Vector3, ch: StringName, n: int) -> Node3D` (load `res://puzzle/dispenser.gd`); `_area(area_name: String) -> Node3D`: a `load("res://world/area.gd").new()` with `area_id`, children `Player` (instanced, at `(0, 1, 6)`), `Camera` (`Camera3D`), `HUD/Label` (`CanvasLayer` + `Label`), and a 40 × 1 × 40 floor; not added to the tree (the caller adds children first); the course is removed first.

- [ ] **Step 1: Write the failing tests** (sections `dispenser`, `memory`)

```gdscript
func _test_dispenser() -> void:
	_course(Vector3(-10, 1, 0))
	world.registry.channels["d_ch"] = [["t:DL", "latch"]]
	var d := _dispenser(Vector3(0, 1, 0), &"d_ch", 2)
	await _wait(30)
	_check(d.weights().size() == 1, "one at a time: the second waits for the spot")
	d.weights()[0].global_position = Vector3(4, 0.5, 0)
	await _wait(30)
	_check(d.weights().size() == 2 and d.weights().all(func(w: WeightBody) -> bool: return w.dispensed), "spot clear: the second comes out")
	d.weights()[1].destroy() # Weight2, the one resting on the spawn spot
	await _wait(60)
	_check(d.weights().size() == 1, "a lost weight waits respawn_delay")
	await _wait(90)
	_check(d.weights().size() == 2, "then it is replaced (and rests on the spot)")
	d.weights()[0].queue_free() # Weight1, away from the spot, freed by other code
	await _wait(200)
	_check(d.weights().size() == 1, "a plain queue_free counts as lost; the spawn waits while the spot is taken")
	d.weights()[0].global_position = Vector3(-4, 0.5, 0)
	await _wait(10)
	_check(d.weights().size() == 2, "spot clear: replaced")
	world.press(&"d_ch", "t:DL", true)
	d.weights()[0].destroy()
	await _wait(200)
	_check(world.solved(&"d_ch") and d.weights().size() == 1, "solved: no more replacements")
	sections += 1


func _test_memory() -> void:
	var area := _area("mem")
	var hand := _weight_in(area, "Hand", Vector3(3, 0.5, 2))
	var spare := _weight_in(area, "Spare", Vector3(-3, 0.5, 2))
	var d := _dispenser_in(area, Vector3(0, 1, -4), &"", 1)
	root.add_child(area)
	await _wait(30)
	hand.global_position = Vector3(5, 0.5, -2)
	spare.destroy()
	d.weights()[0].global_position = Vector3(-5, 0.5, -2)
	await _wait(30)
	root.remove_child(area) # like a scene change
	area.free()
	area = _area("mem")
	hand = _weight_in(area, "Hand", Vector3(3, 0.5, 2))
	spare = _weight_in(area, "Spare", Vector3(-3, 0.5, 2))
	d = _dispenser_in(area, Vector3(0, 1, -4), &"", 1)
	root.add_child(area) # children are ready before the area: the dispenser recreates, then the area restores
	await _wait(5)
	_check(hand.global_position.distance_to(Vector3(5, 0.5, -2)) < 0.1, "a hand-placed weight is back where it was left")
	_check(not is_instance_valid(spare), "a destroyed hand-placed weight stays gone")
	_check(d.weights().size() == 1 and d.weights()[0].global_position.distance_to(Vector3(-5, 0.5, -2)) < 0.1, "a dispensed weight is back where it was left, no extra spawn")
	area.bounds_radius = 20.0
	hand.global_position = Vector3(0, -30, 0)
	await _wait(5)
	_check(not is_instance_valid(hand), "out of the area's bounds: destroyed")
	root.remove_child(area)
	area.free()
	sections += 1
```

(`_weight_in(area, node_name, at)` and `_dispenser_in(area, at, ch, n)` are `_weight`/`_dispenser` adding to `area` (not yet in the tree) instead of `course`; the dispenser is named `Dispenser`, so ids repeat across the rebuild.)

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- dispenser memory`: script missing.
- [ ] **Step 3: Implement** `Dispenser` and the `GameArea` changes per Interfaces. `# ponytail:` on the memory write (every weight every physics frame; write only awake bodies if weights get many).
- [ ] **Step 4: Run** EDITOR ONCE, `RUN SWITCHES` → `SWITCHES: OK`; puzzle suite → `PUZZLES: OK`; `timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/demo.tscn` shows no errors.
- [ ] **Step 5: Commit** `puzzle/dispenser.gd(.uid)`, `world/area.gd`, `tests/switch_test.gd`: `feat(puzzle): dispensers; weights remembered across scene changes`.

---

### Task 8: Editor: switch registry bake and channel pickers

**Files:**
- Modify: `addons/platform_tools/channel_registry.gd`, `addons/platform_tools/plugin.gd`, `addons/platform_tools/channel_property.gd`
- Create: `world/switch_registry.tres` (written by the bake; committed)
- Test: `tests/platform_tools_test.gd`

**Interfaces:**
- Consumes: `SwitchRegistry` (Task 1), the four node scripts (Tasks 5–7).
- Produces (`channel_registry.gd`):
  - `static func _nodes(text: String, path: String) -> Array`: the parse `keys_in` does today, returning per node `{path = String, prefix = String, props = Dictionary, script = String}` (`script` resolved from `ExtResource` ids to `res://` paths; `""` when none). `keys_in` is rebuilt on it, unchanged in behaviour.
  - `static func switches_in(text: String, path: String) -> Array` → `[[channel key, switch id, kind], ...]`: nodes whose `script` is `res://puzzle/weight_plate.gd` (`mode = 1` → `"latch"`, else `"hold"`) or `res://puzzle/energy_switch.gd` (`"energy"`), with a non-empty `channel`; id = area name + `":"` + node path (as `Channels.id`). `# ponytail:` instanced sub-scenes aren't read (same ceiling as `keys_in`).
  - `static func bake() -> bool`: scans every saved `.tscn` (`_scene_files`), builds `SwitchRegistry.channels`, saves `SwitchRegistry.PATH` only when the data changed; returns whether it saved.
  - `channels()` also lists the open scene's `WeightPlate`, `EnergySwitch`, `Door`, `Dispenser` channels.
- Produces (plugin): `_enter_tree` calls `ChannelRegistry.bake()` and connects `scene_saved` to a handler that calls it; `_exit_tree` disconnects. `ChannelInspector._can_handle` also accepts `WeightPlate`, `EnergySwitch`, `Door`, `Dispenser`. `channel_property.gd`: `allow_none` is false for `PlatformSwitch`, `WeightPlate`, `EnergySwitch`, `Door` (true for `Dispenser`).

- [ ] **Step 1: Write the failing test** (in `tests/platform_tools_test.gd`, after the existing channel registry checks)

```gdscript
	# --- switch registry ---
	var scene_text := '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://puzzle/weight_plate.gd" id="1_p"]\n[ext_resource type="Script" path="res://puzzle/energy_switch.gd" id="2_e"]\n\n[node name="Room" type="Node3D"]\n\n[node name="A" type="Area3D" parent="."]\nscript = ExtResource("1_p")\nchannel = &"gate"\nmode = 1\n\n[node name="H" type="Area3D" parent="Bay"]\nscript = ExtResource("1_p")\nchannel = &"gate"\n\n[node name="Z" type="AnimatableBody3D" parent="Bay"]\nscript = ExtResource("2_e")\nchannel = &"other:gate"\n'
	var reg_script = load("res://addons/platform_tools/channel_registry.gd")
	check(reg_script.switches_in(scene_text, "res://x/room.tscn") == [["room:gate", "room:A", "latch"], ["room:gate", "room:Bay/H", "hold"], ["other:gate", "room:Bay/Z", "energy"]], "registry: plates and energy switches, ids and kinds")
	reg_script.bake()
	check(load(SwitchRegistry.PATH) is SwitchRegistry, "bake writes the switch registry")
	check(not reg_script.bake(), "an unchanged bake doesn't rewrite the file")
	var plate: Node = load("res://puzzle/weight_plate.gd").new()
	check(pt._channel_inspector._can_handle(plate), "the channel picker handles weight plates")
	plate.free()
```

- [ ] **Step 2: Run to verify it fails.** `timeout 150 "$GODOT" --headless --path . -e res://tests/platform_tools_test.tscn -- --platform-tools-test 2>&1 | grep -viE "$NOISE"`: `switches_in` not found.
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run** the platform tools suite → `PLATFORM TOOLS: OK`; EDITOR ONCE leaves `world/switch_registry.tres` present; `RUN SWITCHES` → `SWITCHES: OK`.
- [ ] **Step 5: Commit** the three addon files, `world/switch_registry.tres`, `tests/platform_tools_test.gd`: `feat(platform-tools): bake the switch registry; channel picker on puzzle nodes`.

---

### Task 9: Demo areas

**Files:**
- Create: `demo/switches/switches_a.tscn`, `demo/switches/switches_b.tscn`, `demo/switches/switches.gd` (+ `.uid`)
- Modify: `world/switch_registry.tres` (re-baked)
- Test: `tests/switch_test.gd` (section `demo`)

**Interfaces:**
- Consumes: everything above; `GameArea` (`Bays`, `help()`, `SceneDoor`).
- Produces: `switches.gd extends GameArea`; `help()` adds `R carry / put down | T throw | K shoot switches`. `switches_a` (`area_id = &"switches_a"`) and `switches_b` (`area_id = &"switches_b"`), linked both ways by `SceneDoor`s with spawn markers. `switches_a` bays (nodes under `Bays`, each with a `Start` marker), per the spec: `Hold`, `LatchTrio` (with a kill-zone pit), `Weight` (a box with `weight = 30` and a ball), `Energy`, `Gravity` (ceiling plate), `Lure` (a runner, an NPC routine over a plate), `CrossArea` (a latch plate with channel `cross` and the door with channel `cross`). `switches_b` holds the other latch plate, channel `switches_a:cross`, with a dispenser beside it. So the registry lists exactly two switches under `switches_a:cross`. Prototype shapes only (CSG with collision).

- [ ] **Step 1: Write the failing test** (section `demo`)

```gdscript
func _test_demo() -> void:
	if course:
		root.remove_child(course)
		course.queue_free()
		course = null
	world.registry = load("res://world/switch_registry.tres")
	var cross: Array = world.registry.channels.get("switches_a:cross", [])
	_check(cross.size() == 2 and cross.any(func(s: Array) -> bool: return String(s[0]).begins_with("switches_b:")), "registry: the cross-area door counts the plate in switches_b")
	var demo: Node = load("res://demo/switches/switches_a.tscn").instantiate()
	root.add_child(demo)
	await _wait(30)
	var bays: Array = demo.get_node("Bays").get_children().map(func(b: Node) -> String: return String(b.name))
	_check(["Hold", "LatchTrio", "Weight", "Energy", "Gravity", "Lure", "CrossArea"].all(func(n: String) -> bool: return n in bays), "demo: the seven bays")
	var cross_door: Node = demo.find_children("*", "AnimatableBody3D").filter(func(n: Node) -> bool: return n.get("channel") == &"cross")[0]
	_check(cross_door.amount == 0.0, "the cross-area door is shut while the far plate is unvisited")
	var warned := demo.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.has_method(&"_get_configuration_warnings") and not n._get_configuration_warnings().is_empty())
	_check(warned.is_empty(), "no configuration warnings")
	demo.queue_free()
	sections += 1
```

- [ ] **Step 2: Run to verify it fails.** `RUN SWITCHES -- demo`: scene missing.
- [ ] **Step 3: Build the scenes and script** (by hand or with a throwaway generator in `$CLAUDE_JOB_DIR/tmp`; commit only the scenes). Open both in the editor once (EDITOR ONCE after saving) so the bake picks them up.
- [ ] **Step 4: Run** `RUN SWITCHES` → `SWITCHES: OK`; `timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/switches/switches_a.tscn` and the same for `switches_b.tscn` show no errors.
- [ ] **Step 5: Commit** `demo/switches/*`, `world/switch_registry.tres`, `tests/switch_test.gd`: `feat(demo): switch puzzle areas`.

---

### Task 10: Docs, CLAUDE.md, full verification

**Files:**
- Create: `docs/switches.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write `docs/switches.md`**: placing plates, doors, energy switches and dispensers; channels and cross-area wiring (and that saving a scene re-bakes the registry); latch vs hold and what "solved" means; weights, weight tuning and carrying numbers; gravity zones on everything; memory and what isn't remembered (enemies); presentation hooks (`pressed`, `amount`, `fraction()`, `cue`s, player `carry_*` anims).
- [ ] **Step 2: Update `CLAUDE.md`**: a **Switch puzzles** architecture section (one paragraph, like Enemies and NPCs); `World` gains `switches`, `bodies` and the registry in the save list; the suite line `timeout 400 "$GODOT" --headless --path . -s res://tests/switch_test.gd ... # plates, doors, energy, weights, carry, dispensers, gravity, memory` and `SWITCHES` in the last-line list; the sections note (`-- plate carry`); `WeightPlate`, `EnergySwitch`, `Door`, `Dispenser` join the "don't static-type in tests" list; `GravityZone` now flips enemies, NPCs and weights.
- [ ] **Step 3: Full verification.** EDITOR ONCE (no errors), then every suite in CLAUDE.md: smoke, platforms, puzzles, enemies, NPCs, switches, shape editor, platform tools, NPC tools → each prints `OK`. `--quit-after 300` on `demo/demo.tscn`, `demo/switches/switches_a.tscn`, `switches_b.tscn` → no errors.
- [ ] **Step 4: Commit** `docs/switches.md`, `CLAUDE.md`: `docs: switch puzzles guide; CLAUDE.md section and suite`.
