# Camera Shake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A layered camera shake (slide + optional tilt) fed by player hits, environment zones, heavy enemy footsteps and slamming platforms, with global toggles.

**Architecture:** `CameraShake` is a static-only class holding short-lived layers, each with its own feel. They're combined strongest-first, each later one scaled by what the stronger ones left. `GameArea._process` turns the result into the camera's built-in `h_offset`/`v_offset` (slide) and a roll on top of a stored steady basis (tilt). Sources call `CameraShake.add(...)`; environments feed a sustained level through `EnvProfile.shake`.

**Tech Stack:** Godot 4.7.2 GDScript, Jolt, headless `SceneTree` test scripts.

**Spec:** `docs/superpowers/specs/2026-11-26-camera-shake-design.md`

## Global Constraints

- Godot exe: `/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe`. Wrap every run in `timeout`; filter noise with `grep -viE "git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"`.
- `CameraShake` must not reference the `World` autoload. In `tests/shake_test.gd`, don't static-type `GameArea`, `PlatformTrackInstance`, `PlatformSequence`, `MovingPlatform`, `EnvZone` subclasses that touch World: `load()` their scripts and use `Node3D`/`Node`. `Player`, `Enemy`, `CameraShake` and `EnvProfile` may be typed.
- Project settings, in `[ahra]` of `project.godot` next to `animation/disable_squash_tilt=false`: `camera/disable_shake=false`, `camera/shake_slide=true`, `camera/shake_tilt=false`. Read them every call with `ProjectSettings.get_setting(key, default)`.
- Starting values: `MAX_SLIDE = 0.025` (fraction of the view height), `MAX_TILT = 0.026` rad (~1.5°), at most 8 layers, layers weaker than 0.02 aren't added, sustained level eases at 2 per second (0 → 1 in 0.5 s).
- Feels: JOLT 0.3 s, global; THUMP 0.2 s, radius 14 m; SLAM 0.6 s, radius 18 m; SWAY sustained, global.
- New scripts get their `.uid` sidecar from one editor run (`timeout 150 "$GODOT" --headless --path . --editor --quit-after 400`); commit the sidecars with the scripts.
- `@tool` scripts (MovingPlatform, EnvProfile is a Resource): guard runtime-only code with `Engine.is_editor_hint()`.
- Static typing and `##` doc comments; mark shortcuts with `ponytail:` comments.
- Work on a branch `camera-shake` (the repo is on `main`).

## Review Focus

- Turning a toggle off mid-shake: the offsets and roll must go back to exactly 0, not freeze at the last value (test in Task 2).
- A scene change mid-shake: the new area starts with no layers (test in Task 2).
- Many heavy sources at once (several brutes, crushers): never more than 8 layers, total intensity ≤ 1 (test in Task 1).
- A zoom (a changed `fov`): the shake keeps its size on screen, because the view height is recomputed live (test in Task 2).
- An enemy teleported (respawn, puppet snap) must not fire a burst of footsteps (test in Task 5).

---

### Task 1: `CameraShake` core, toggles, overlap rule

**Files:**
- Create: `world/camera_shake.gd`
- Modify: `project.godot` (`[ahra]`)
- Test: `tests/shake_test.gd`

**Interfaces:**
- Produces:
  - `class_name CameraShake extends RefCounted` (static only).
  - `enum Feel { JOLT, THUMP, SLAM, SWAY }`.
  - `const DISABLE := "ahra/camera/disable_shake"`, `const SLIDE := "ahra/camera/shake_slide"`, `const TILT := "ahra/camera/shake_tilt"`.
  - `const MAX_SLIDE := 0.025`, `const MAX_TILT := 0.026`, `const MAX_LAYERS := 8`, `const MIN_STRENGTH := 0.02`.
  - `static var layers: Array[Dictionary]`, where each entry is `{feel: Feel, strength: float, age: float, seed: int}`.
  - `static var sustained_level := 0.0`, `static var focus := Vector3.ZERO`, `static var roll := 0.0` (the last roll returned), `static var total := 0.0` (combined intensity after the last update).
  - `static func add(feel: Feel, strength: float, at: Variant = null, radius := 0.0) -> void`
  - `static func update(delta: float, at_focus: Vector3, sustained: float) -> Vector3` returns (x, y) slide as a fraction of the view height and z roll in radians, after toggles.
  - `static func steady(b: Basis) -> Basis` returns `b * Basis(Vector3.BACK, -roll)`.
  - `static func clear() -> void` empties the layers and resets `sustained_level`, `roll` and `total` to 0.

- [ ] **Step 1: Write the test harness and the failing `rule` section**

`tests/shake_test.gd` follows `tests/enemy_test.gd`: `extends SceneTree`, `const SECTIONS := 1`, `const PLAYER := preload("res://player/player.tscn")`, `const ENEMY := preload("res://enemy/enemy.tscn")` (Task 5 adds `BRUTE`), `_run()` with the `--` section filter, `_check`, `_wait`, and a last line `print("SHAKE: ", "OK" if fails == 0 else "%d FAILED" % fails)` then `quit(fails)`. Each section starts with `CameraShake.clear()`.

```gdscript
func _test_rule() -> void:
	var J := CameraShake.Feel.JOLT
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.5), "one shake of 0.5 = 0.5")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.75), "two equal shakes = 1 - (1 - a)^2")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.875), "three = 0.875")
	for i in 20:
		CameraShake.add(J, 0.9 if i == 19 else 0.3)
	CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(CameraShake.layers.size() == CameraShake.MAX_LAYERS and CameraShake.total <= 1.0, "cap: 8 layers, total <= 1")
	_check(CameraShake.layers.any(func(l: Dictionary) -> bool: return is_equal_approx(l.strength, 0.9)), "a full list replaces its weakest")
	CameraShake.clear()
	CameraShake.update(0.0, Vector3.ZERO, 0.0) # focus at the origin
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(100, 0, 0))
	_check(CameraShake.layers.is_empty(), "beyond the radius: no layer")
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(7, 0, 0))
	_check(is_equal_approx(CameraShake.layers[0].strength, 0.25), "linear falloff: half the 14 m radius = half")
	CameraShake.clear()
	CameraShake.add(J, 1.0)
	var t := 0.0
	while t < 0.31:
		CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0); t += 1.0 / 60.0
	_check(CameraShake.layers.is_empty(), "a JOLT is gone after its 0.3 s")
	# toggles
	var roll_seen := false
	CameraShake.add(J, 1.0)
	for i in 6:
		var s := CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
		roll_seen = roll_seen or s.z != 0.0
	_check(not roll_seen, "tilt is off by default")
	ProjectSettings.set_setting(CameraShake.TILT, true)
	for i in 6:
		roll_seen = roll_seen or CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0).z != 0.0
	_check(roll_seen, "tilt on: the horizon rolls")
	ProjectSettings.set_setting(CameraShake.SLIDE, false)
	var off := CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	_check(off.x == 0.0 and off.y == 0.0, "slide off: no slide")
	ProjectSettings.set_setting(CameraShake.DISABLE, true)
	_check(CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0) == Vector3.ZERO, "master off: nothing")
	ProjectSettings.set_setting(CameraShake.TILT, false); ProjectSettings.set_setting(CameraShake.SLIDE, true); ProjectSettings.set_setting(CameraShake.DISABLE, false)
	sections += 1
```

- [ ] **Step 2: Run it and check it fails**

Run: `timeout 150 "$GODOT" --headless --path . -s res://tests/shake_test.gd 2>&1 | grep -viE "$NOISE"`
Expected: a parse error, because `CameraShake` doesn't exist yet. The timeout ends the run.

- [ ] **Step 3: Implement `world/camera_shake.gd` and the three settings in `project.godot`**

- `add`: clamp the strength to 0..1. If `at` is given, multiply by `clampf(1 - focus.distance_to(at) / r, 0, 1)`, where `r` is `radius`, or the feel's default when `radius` is 0. Drop the shake if the result is below `MIN_STRENGTH`. When the list is full, replace the weakest layer if the new one is stronger, otherwise drop it. The seed is `randi()`.
- Feel presets live in one `const FEELS` dictionary: length, default radius, and noise frequency. Envelope: `(1 - age / length)²`, so intensity at age 0 equals strength. Unit motion (x, y, roll) per feel:
  - JOLT: noise at 25 Hz on each axis.
  - THUMP: y = `-sin(PI * age / length)`, plus 0.2 × noise on x and roll.
  - SLAM: y dips like THUMP over the first quarter of its length, then noise at 18 Hz.
  - SWAY: noise at 3 Hz plus 0.3 × noise at 9 Hz.
  
  Noise comes from one static `FastNoiseLite`, sampled at `(seed + axis × 1000, age × frequency)`.
- `update`: set `focus = at_focus`. Ease `sustained_level` toward `sustained` with `move_toward(.., .., 2.0 * delta)`, and age the layers by `delta`, dropping the expired ones. Then combine:

```gdscript
# strongest first; each layer scaled by what the stronger ones left
var live := [] # [intensity, motion] for every layer plus the SWAY layer at sustained_level (when > 0)
live.sort_custom(func(a, b): return a[0] > b[0])
var left := 1.0
var out := Vector3.ZERO
for l in live:
	out += l[1] * left          # l[1] is intensity × unit motion
	left *= 1.0 - l[0]
total = 1.0 - left
```

  Return `Vector3(out.x * MAX_SLIDE, out.y * MAX_SLIDE, out.z * MAX_TILT)`. Zero x/y when `DISABLE` is on or `SLIDE` is off, and zero z when `DISABLE` is on or `TILT` is off. Store the returned z in `roll`.
  
  The SWAY layer's age is `Time.get_ticks_msec() / 1000.0`, so its noise keeps running. Add a `ponytail:` comment on the cap: replacing the weakest layer is the ceiling, so a real queue is needed if sources ever exceed 8 at once.

- [ ] **Step 4: Run it and check it passes**

Run the Step 2 command. Expected: every `rule` line is `ok`, then `SHAKE: OK`.

- [ ] **Step 5: Generate the uid and commit**

```bash
timeout 150 "$GODOT" --headless --path . --editor --quit-after 400 2>&1 | grep -viE "$NOISE" | grep -i error
git add world/camera_shake.gd world/camera_shake.gd.uid tests/shake_test.gd tests/shake_test.gd.uid project.godot
git commit -m "Add CameraShake: layered shakes, overlap rule, toggles"
```

---

### Task 2: Apply the shake to the camera (GameArea), steady movement basis

**Files:**
- Modify: `world/area.gd` (`_ready`, `_process`)
- Modify: `player/player.gd:255-257` (`cam_basis`)
- Test: `tests/shake_test.gd` (section `camera`)

**Interfaces:**
- Consumes: `CameraShake.update`, `CameraShake.steady`, `CameraShake.clear` (Task 1).
- Produces:
  - `GameArea.view_height() -> float` = `2 × cam.global_position.distance_to(player_position) × tan(deg_to_rad(cam.fov) / 2)`.
  - `GameArea._steady_basis: Basis`.
  - An `_area()` builder in `tests/shake_test.gd`: an area node with a floor, Player, Camera and HUD/Label, copied from `tests/switch_test.gd:583-603`. It's added to `root` and set as `current_scene`, and the player is at (0, 1, 0). Later tasks reuse it.

- [ ] **Step 1: Write the failing `camera` section**

```gdscript
func _test_camera() -> void:
	var a := _area(); await _wait(120) # let the follow settle fully
	var p: Player = a.get_node("Player"); var cam: Camera3D = a.get_node("Camera")
	var rest := cam.global_position
	var iso := Basis.from_euler(Vector3(deg_to_rad(-35.264), deg_to_rad(45.0), 0.0))
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	var moved := false
	for i in 8:
		await process_frame
		moved = moved or absf(cam.h_offset) + absf(cam.v_offset) > 0.0
	_check(moved and cam.global_position.is_equal_approx(rest), "slide lives in the offsets; the camera doesn't drift")
	ProjectSettings.set_setting(CameraShake.DISABLE, true); await process_frame
	_check(cam.h_offset == 0.0 and cam.v_offset == 0.0, "master off mid-shake: offsets back to exactly 0")
	ProjectSettings.set_setting(CameraShake.DISABLE, false)
	ProjectSettings.set_setting(CameraShake.TILT, true)
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	var tilted := false
	for i in 8:
		await process_frame
		if not cam.global_basis.is_equal_approx(iso):
			tilted = true
			_check(p.cam_basis().is_equal_approx(iso), "movement reads the steady basis while tilted")
			break
	_check(tilted, "tilt on: the camera rolls")
	ProjectSettings.set_setting(CameraShake.TILT, false); await process_frame
	_check(cam.global_basis.is_equal_approx(iso), "tilt off: back to the iso basis")
	var h: float = a.view_height()
	cam.fov *= 2.0
	_check(absf(a.view_height() / h - tan(deg_to_rad(cam.fov) / 2) / tan(deg_to_rad(cam.fov / 4))) < 0.01, "zoom: the view height follows the live fov")
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	_area(); await _wait(2)
	_check(CameraShake.layers.is_empty(), "a new area starts with no shake")
	sections += 1
```

`_area()` frees the previous area first (`root.remove_child` + `queue_free`, as `_course` in enemy_test does). Bump `SECTIONS` to 2.

- [ ] **Step 2: Run it and check it fails**

Run: `timeout 150 "$GODOT" --headless --path . -s res://tests/shake_test.gd -- camera 2>&1 | grep -viE "$NOISE"`
Expected: an error, because `view_height` doesn't exist.

- [ ] **Step 3: Implement it**

- `area.gd _ready`: `CameraShake.clear()`. After `cam.rotation_degrees = …`, store `_steady_basis = cam.global_basis`.
- `area.gd _process`, after the follow lines:
  - `var s := CameraShake.update(delta, player.get_global_transform_interpolated().origin, player.env.shake if player.env else 0.0)`
  - `cam.h_offset = s.x * view_height()` and `cam.v_offset = s.y * view_height()`
  - `cam.global_basis = _steady_basis * Basis(Vector3.BACK, s.z)`
  - Add a `ponytail:` comment: code that rotates the camera sets `_steady_basis`, not the camera.
- `env_profile.gd`: add the export now, so `player.env.shake` exists. Use a new `@export_group("Camera")` with `@export_range(0.0, 1.0) var shake := 0.0 ## camera shake while the player is in a zone with this profile`. Task 4 adds its `combine` rule and its test.
- `player.gd cam_basis()`: `return CameraShake.steady(cam.global_basis) if cam else Basis.IDENTITY`.

- [ ] **Step 4: Run it, then check the player suite**

Run the Step 2 command, then `timeout 150 "$GODOT" --headless --path . -s res://tests/smoke_test.gd 2>&1 | grep -viE "$NOISE" | tail -3`.
Expected: `SHAKE: OK` and `SMOKE: OK`.

- [ ] **Step 5: Commit**

```bash
git add world/area.gd player/player.gd tests/shake_test.gd world/env_profile.gd
git commit -m "Apply camera shake through view offsets and a steady-basis roll"
```

---

### Task 3: Player hit

**Files:**
- Modify: `player/player.gd:639-654` (`damage`)
- Test: `tests/shake_test.gd` (section `hit`)

**Interfaces:**
- Consumes: `CameraShake.add` (Task 1), `_area()` (Task 2).

- [ ] **Step 1: Write the failing `hit` section**

```gdscript
func _test_hit() -> void:
	var a := _area(); await _wait(30)
	var p: Player = a.get_node("Player")
	CameraShake.clear()
	p.damage(10.0)
	_check(CameraShake.layers.size() == 1 and CameraShake.layers[0].feel == CameraShake.Feel.JOLT
		and is_equal_approx(CameraShake.layers[0].strength, clampf(0.3 + 10.0 / p.max_hp(), 0.3, 1.0)), "a hit adds a JOLT scaled by damage")
	p.damage(10.0)
	_check(CameraShake.layers.size() == 1, "no new shake during i-frames")
	sections += 1
```

Bump `SECTIONS` to 3.

- [ ] **Step 2: Run it and check it fails**

Run: `… -s res://tests/shake_test.gd -- hit`. Expected: `FAIL a hit adds a JOLT…`.

- [ ] **Step 3: Implement it**

In `damage`, after the first guard and before `drop_held()`, add `CameraShake.add(CameraShake.Feel.JOLT, clampf(0.3 + amount / max_hp(), 0.3, 1.0))`. This placement covers the killing hit too.

- [ ] **Step 4: Run it and check it passes**

Expected: `SHAKE: OK`.

- [ ] **Step 5: Commit**: `git commit -am "Shake the camera when the player is hit"`

---

### Task 4: Environment shake

**Files:**
- Modify: `world/env_profile.gd` (export + `combine`)
- Test: `tests/shake_test.gd` (section `env`)

**Interfaces:**
- Produces: in `combine`, `out.shake = 1.0 - (1.0 - out.shake) * (1.0 - e.shake)`.
- Consumes: `EnvProfile.shake` (exported in Task 2), `CameraShake.sustained_level` (Task 1), `_area()` (Task 2).

- [ ] **Step 1: Write the failing `env` section**

```gdscript
func _test_env() -> void:
	var s1 := EnvProfile.new(); s1.shake = 0.5
	var s2 := EnvProfile.new(); s2.shake = 0.5
	_check(is_equal_approx(EnvProfile.combine(EnvProfile.new(), [s1, s2]).shake, 0.75), "overlapping zones merge by the overlap rule")
	var a := _area(); await _wait(30)
	var p: Player = a.get_node("Player")
	var storm := EnvProfile.new(); storm.shake = 0.3
	var z: Node3D = load("res://world/env_zone.gd").new()
	z.profile = storm; z.position = Vector3(0, 1, 0); a.add_child(z)
	var box := BoxShape3D.new(); box.size = Vector3(6, 4, 6)
	z.add_shape(box) # after add_child, as enemy_test's _zone does
	await _wait(45)
	_check(is_equal_approx(CameraShake.sustained_level, 0.3), "in a storm zone the sustained level reaches its shake")
	p.teleport(Vector3(12, 1, 0))
	await _wait(40)
	_check(CameraShake.sustained_level == 0.0, "after leaving it eases back to 0 within ~0.5 s")
	sections += 1
```

Bump `SECTIONS` to 4. The `_area()` floor is 40 × 40, so the player still has floor at (12, 1, 0).

- [ ] **Step 2: Run it and check it fails**

Run: `… -- env`. Expected: `FAIL overlapping zones merge by the overlap rule`. The sustained checks may already pass, because Task 2 wired `player.env.shake`.

- [ ] **Step 3: Implement the `combine` line**

- [ ] **Step 4: Run it and check it passes**: `SHAKE: OK`.

- [ ] **Step 5: Commit**: `git commit -am "Environment zones can shake the camera (EnvProfile.shake)"`

---

### Task 5: Heavy enemy footsteps and the brute

**Files:**
- Modify: `enemy/enemy.gd` (exports, `_physics_process`)
- Create: `enemy/brute/brute.tscn`
- Test: `tests/shake_test.gd` (section `steps`)

**Interfaces:**
- Produces:
  - Enemy `@export_group("Shake")` with `step_shake := 0.0` (0..1, 0 = none) and `stride := 1.4` (m).
  - The cue `&"step"`, emitted after the step's `CameraShake.add`.
  - `enemy/brute/brute.tscn`: an inherited scene of `enemy/enemy.tscn` with exports only. Values: `abilities = 0`, `weight = 40.0`, `max_health = 150.0`, `walk_speed = 1.8`, `attack_damage = 20.0`, `attack_windup = 0.6`, `step_shake = 0.35`, `stride = 1.6`, `color = Color(0.35, 0.3, 0.4, 1)`.
- Consumes: `CameraShake.add` (Task 1), `_area()` (Task 2).

- [ ] **Step 1: Write the failing `steps` section**

```gdscript
func _test_steps() -> void:
	var a := _area(); await _wait(30)
	var brute: Enemy = BRUTE.instantiate() # const BRUTE := preload("res://enemy/brute/brute.tscn")
	brute.show_debug = false; brute.position = Vector3(-8, 1, 0); a.add_child(brute)
	var steps := [0, 0] # cues, cues with a fresh THUMP layer
	brute.cue.connect(func(n: StringName) -> void:
		if n == &"step":
			steps[0] += 1
			if CameraShake.layers.any(func(l: Dictionary) -> bool: return l.feel == CameraShake.Feel.THUMP and l.age == 0.0):
				steps[1] += 1)
	var start := brute.global_position
	await _wait(150)
	var walked := (brute.global_position - start).slide(Vector3.UP).length()
	_check(steps[0] > 0 and absi(steps[0] - int(walked / brute.stride)) <= 1, "about one step cue per stride walked")
	_check(steps[1] == steps[0], "every step near the player adds a THUMP")
	var before: int = steps[0]
	brute.global_position += Vector3(0, 0, 6)
	await _wait(2)
	_check(steps[0] - before <= 1, "a teleport doesn't fire a burst of steps")
	var light: Enemy = ENEMY.instantiate() # plain enemy: step_shake 0
	light.show_debug = false; light.position = Vector3(8, 1, 0); a.add_child(light)
	var light_thumps := [0]
	light.cue.connect(func(n: StringName) -> void:
		if n == &"step" and CameraShake.layers.any(func(l: Dictionary) -> bool: return l.feel == CameraShake.Feel.THUMP and l.age == 0.0):
			light_thumps[0] += 1)
	brute.queue_free()
	await _wait(120)
	_check(light_thumps[0] == 0, "step_shake 0: steps but no shake")
	sections += 1
```

Bump `SECTIONS` to 5. Both enemies chase the player at (0, 1, 0) with the default `sight_radius` of 10. The light enemy's 120-frame chase covers about 6 m.

- [ ] **Step 2: Run it and check it fails**

Run: `… -- steps`. Expected: an error, because `brute.tscn` doesn't exist.

- [ ] **Step 3: Implement it**

In `Enemy._physics_process`, after `state.physics`, keep `_step_from: Vector3` (set in `_ready`) and `_strode: float`. While `is_on_floor()`:
- Add up `(global_position - _step_from).slide(up_direction).length()`.
- A single frame that moves more than 2 m is a teleport: reset `_strode` to 0 and don't count it. Add a `ponytail:` comment on it.
- When `_strode >= stride`: subtract `stride`; if `step_shake > 0`, call `CameraShake.add(CameraShake.Feel.THUMP, step_shake, global_position)`; then `cue.emit(&"step")`.
- Set `_step_from = global_position` every frame.

Write `brute.tscn` like `enemy/runner/runner.tscn`. Update the `cue` doc comment in `enemy.gd:15` and `docs/enemies.md`'s cue list to mention `step`.

- [ ] **Step 4: Run it, then the enemy suite**

Run `… -- steps`, then `timeout 300 "$GODOT" --headless --path . -s res://tests/enemy_test.gd 2>&1 | grep -viE "$NOISE" | tail -3`.
Expected: `SHAKE: OK` and `ENEMIES: OK`.

- [ ] **Step 5: Commit**

```bash
timeout 150 "$GODOT" --headless --path . --editor --quit-after 400 2>&1 | grep -viE "$NOISE" | grep -i error
git add enemy/ docs/enemies.md tests/shake_test.gd
git commit -m "Heavy enemies shake the camera with each footstep; add the brute"
```

---

### Task 6: Slamming platforms (crusher)

**Files:**
- Modify: `world/moving_platform.gd` (exports, signal, `_physics_process`)
- Test: `tests/shake_test.gd` (section `slam`)

**Interfaces:**
- Produces:
  - `signal slammed(at: Vector3)` on MovingPlatform, emitted right after the slam's `CameraShake.add`. This is a small addition to the spec, there for future hooks such as sound, and for the test. It doesn't clash with Door's `cue`.
  - `@export_group("Slam")` with `slam_shake := 0.0` (0..1, 0 = none) and `slam_speed := 5.0` (m/s).
- Consumes: `CameraShake.add` (Task 1), `_area()` (Task 2). The `_track` and `_platform` helpers are copied from `tests/platform_test.gd:400-422`, with `speed`, `start_wait` and `end_wait` set per sequence.

- [ ] **Step 1: Write the failing `slam` section**

```gdscript
func _test_slam() -> void:
	var a := _area(); await _wait(30)
	# manual body: fast for 10 frames, then stop = one slam; a 2 m one-frame jump, then still = none
	var pl: Node3D = _platform(); pl.slam_shake = 0.6; pl.position = Vector3(5, 3, 0); a.add_child(pl)
	var slams := []
	pl.slammed.connect(func(at: Vector3) -> void: slams.append(at))
	await _wait(5)
	for i in 10:
		pl.global_position += Vector3(0, -0.2, 0); await physics_frame # 12 m/s
	await _wait(5)
	_check(slams.size() == 1, "a hard stop after fast motion is one slam")
	pl.global_position += Vector3(0, 2, 0)
	await _wait(5)
	_check(slams.size() == 1, "a one-frame jump (clock skip) then still: no slam")
	pl.queue_free()
	# a crusher: fast down 3 m at 12 m/s, 0.5 s wait; up at 2 m/s, 1 s wait; start over (cycle 3.25 s)
	var crusher: Node3D = _track([Vector3(0, 4, 0), Vector3(0, 1, 0)], [[0, 1, false, 1, 12.0, 0.0, 0.5], [1, 0, false, 1, 2.0, 0.0, 1.0]])
	crusher.position = Vector3(-5, 0, -5)
	var body: Node3D = _platform(); body.slam_shake = 0.6
	crusher.add_child(body); a.add_child(crusher)
	var hits := []
	body.slammed.connect(func(at: Vector3) -> void: hits.append([Engine.get_physics_frames(), at]))
	await _wait(500) # over 2.5 cycles: 2 or 3 slams depending on the phase it loads at
	var spaced := hits.size() >= 2
	for i in range(1, hits.size()):
		spaced = spaced and absi(hits[i][0] - hits[i - 1][0] - 195) <= 3 # 3.25 s cycle = 195 frames
	_check(spaced, "a crusher slams once per cycle: never on its slow rise or on load (%d)" % hits.size())
	_check(hits.all(func(h: Array) -> bool: return absf(h[1].y - 1.0) < 0.1), "it slams at the bottom")
	sections += 1
```

Bump `SECTIONS` to 6. `_track` sequence arrays are `[start, end, round_trip, trips, speed, start_wait, end_wait]`. `after_last` keeps its START_OVER default.

- [ ] **Step 2: Run it and check it fails**

Run: `… -- slam`. Expected: an error, because there's no `slam_shake` property.

- [ ] **Step 3: Implement it**

In `MovingPlatform._physics_process`, rename `_delta` to `delta`. In the runtime branch, once `_warmup` is over and `slam_shake > 0`:
- Measure `speed = global_position.distance_to(_last_pos) / delta`.
- Count `_fast_frames`: consecutive frames with `speed >= slam_speed`.
- A frame with `speed < 0.25 * slam_speed` after `_fast_frames >= 3` is a slam: call `CameraShake.add(CameraShake.Feel.SLAM, slam_shake, global_position)`, then `slammed.emit(global_position)`.
- Reset `_fast_frames` on any slow frame.
- Store `_last_pos`. On the first frame after the warmup, only store it.

The 3-frame rule is what rejects a one-frame clock-skip jump. Add a `ponytail:` comment: strokes shorter than 3 frames (0.05 s) never slam.

- [ ] **Step 4: Run it, then the platform and switch suites**

Run `… -- slam`, then `platform_test.gd` and `switch_test.gd` (doors extend MovingPlatform), each tailed to its last line.
Expected: `SHAKE: OK`, `PLATFORMS: OK`, `SWITCHES: OK`.

- [ ] **Step 5: Commit**: `git commit -am "Slamming platforms shake the camera (crusher)"`

---

### Task 7: Demo scene, docs, full regression

**Files:**
- Create: `demo/shake/shake.tscn` and `demo/shake/shake.gd`
- Modify: `CLAUDE.md`
- Test: `tests/shake_test.gd` (section `demo`)

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `demo/shake/shake.gd` is `extends GameArea`. `help()` returns `super() + "9 slide on/off | 0 tilt on/off | - shake on/off\n\n"`.
  - `_unhandled_input(e)` flips `CameraShake.SLIDE`, `TILT` and `DISABLE` on `KEY_9`, `KEY_0` and `KEY_MINUS`, and passes everything else to `super(e)`.

- [ ] **Step 1: Write the failing `demo` section**

```gdscript
func _test_demo() -> void:
	var a: Node3D = load("res://demo/shake/shake.tscn").instantiate()
	root.add_child(a); current_scene = a
	await _wait(10)
	_check(a.get_node("Bays/Brute/Brute") is Enemy and a.get_node("Bays/Brute/Brute").step_shake > 0.0, "demo: a brute with step shake")
	_check(a.get_node("Bays/Storm/Storm").profile.shake > 0.0, "demo: a storm zone")
	var hits := [0]
	for c in a.get_node("Bays/Crushers").find_children("*", "AnimatableBody3D", true, false):
		if c.has_signal(&"slammed"):
			c.slammed.connect(func(_at: Vector3) -> void: hits[0] += 1)
	await _wait(240)
	_check(hits[0] >= 2, "demo: the crushers slam")
	sections += 1
```

Bump `SECTIONS` to 7.

- [ ] **Step 2: Run it and check it fails**: `… -- demo`. Expected: an error, because the scene doesn't exist.

- [ ] **Step 3: Build the scene**

Model the scene on `demo/enemies/enemies.tscn`: a WorldEnvironment, a DirectionalLight3D, a floor CSGBox3D (60 × 1 × 20, top at y 0), a KillZone void, Player at (-20, 1, 0), and the `Camera` authored orthographic with size 14. Add HUD/Label and a `Bays` node with three bays 20 m apart on x, each with a `Start` marker:
- `Bays/Storm` (x -20): `Storm`, an EnvZone 10 × 4 × 10 whose profile is named "Storm", with `shake = 0.3` and `wind = Vector3(2, 0, 0)`.
- `Bays/Brute` (x 0): `Brute`, an instance of `enemy/brute/brute.tscn`.
- `Bays/Crushers` (x 20): two PlatformTrackInstance nodes 3 m apart. Each has a Path3D from (0, 4, 0) to (0, 1, 0) and the two sequences from Task 6 (12 m/s down with a 0.5 s end wait, 2 m/s up with a 1 s end wait). The second track has `offset = 1.6`. Each MovingPlatform is a 2 × 1 × 2 box with `slam_shake = 0.6`. Add a Label3D: "stand between them: overlap | walk away: falloff".

  Saving the scene in the editor isn't needed: headless runs read the `.tscn` directly.

Update `CLAUDE.md`:
- Add the `shake_test.gd` line to the test list (`# camera shake: overlap rule, camera layer, hit, env, steps, slam, demo`), and add `SHAKE` to the OK list.
- Add a **Camera shake** paragraph to Architecture, covering `CameraShake.add`, the feels, the overlap rule, offsets + steady basis, the sources and their exports, the toggles, and how to hook a new signal in one line.

- [ ] **Step 4: Run the whole shake suite, the demo scene and every suite GameArea touches**

```sh
timeout 150 "$GODOT" --headless --path . --editor --quit-after 400 2>&1 | grep -viE "$NOISE" | grep -i error
timeout 200 "$GODOT" --headless --path . -s res://tests/shake_test.gd 2>&1 | grep -viE "$NOISE" | tail -3
timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/shake/shake.tscn 2>&1 | grep -viE "$NOISE"
for t in smoke platform puzzle enemy npc switch; do timeout 400 "$GODOT" --headless --path . -s res://tests/${t}_test.gd 2>&1 | grep -viE "$NOISE" | tail -1; done
```

Expected:
- No errors from the editor run or the demo run.
- The last lines read `SHAKE: OK`, `SMOKE: OK`, `PLATFORMS: OK`, `PUZZLES: OK`, `ENEMIES: OK`, `NPCS: OK` and `SWITCHES: OK`.

Report that game feel (preset numbers) is untested and is tuned by playing `demo/shake/shake.tscn`.

- [ ] **Step 5: Commit**

```bash
git add demo/shake/ tests/shake_test.gd CLAUDE.md
git commit -m "Camera shake demo scene and docs"
```
