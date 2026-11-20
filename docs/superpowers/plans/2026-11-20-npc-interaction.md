# NPC Interaction System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NPCs with ordered lists of key/near interactions made of steps (say, anim, face, look, move, sound, wait, flag, leave), billboard bubbles, memory of what they said and where they stand, progression flags, leaving behind a fade, an NPC Tools editor plugin, a prototype-shape demo, and a presentation guide.

**Architecture:** `World` gains story `flags`, per-placement NPC memory `npcs` and a screen `fade`. `Npc` is a `CharacterBody3D` with no state machine: idle (head follows the player) or running one `NpcInteraction` as an `await` coroutine over its `NpcStep`s. Key interactions start through `NpcTalk`, an `Interactable` zone; the player now picks the nearest usable zone among all it stands in. Data are `@tool` Resources edited in the inspector, like `PlatformSequence`.

**Tech Stack:** Godot 4.7.2 GDScript, Jolt physics, headless `SceneTree` test scripts, editor test harness `tests/editor_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-20-npc-interaction-design.md`

## Global Constraints

- Godot `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` only. Shell preamble for every command below:
  ```sh
  GODOT="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
  NOISE="git_plugin|git-plugin|GDExtension|copying library|FileAccess::exists"
  ```
- Every Godot run goes through `timeout` (a script error hangs Godot).
- **RUN NPCS** = `timeout 400 "$GODOT" --headless --path . -s res://tests/npc_test.gd 2>&1 | grep -viE "$NOISE"`; append `-- <section> ...` to run only those sections. Passes when the last line is `NPCS: OK`.
- After adding a `class_name` script, run the editor once (`timeout 150 "$GODOT" --headless --path . --editor --quit-after 400`) so it writes the `.uid` sidecar and registers the class for `-s` tests. Commit every `.uid`.
- `Npc` and `NpcTalk` reference the `World` autoload: `-s` tests never static-type them and load their scenes with `load()` at runtime (no `preload`). `NpcInteraction`, `NpcStep`, `Interactable` and `Player` must never reference `World` (tests type them). `Enemy` must not reference NPC code.
- `World.flags` and `World.npcs` keys are always `String` (convert `StringName` with `String()`).
- NPCs fall world-down (`get_gravity()`); never touch `GravityZone` support.
- Static typing, `##` doc comments, `ponytail:` comment on every deliberate shortcut. `@tool` scripts guard runtime logic with `Engine.is_editor_hint()` and create child nodes in `_ready`, never as member defaults.
- Spec values: near `distance` default `4.0`, re-arm beyond `distance + 1.0`, `notice_distance` `6.0`, head yaw clamp ±75°, pitch ±35°, arrival within `0.3` m, walk timeout `distance / speed * 2 + 1` s, fade `0.4` s, unlocked line time `1.0 + 0.04 * chars` s, unlocked `WAIT 0` = `1.0` s, blink every 2-5 s.
- Don't touch `demo/demo.tscn`, `demo/builder/`, `.godot/editor/editor_layout.cfg`. Stage by explicit path, never `git add -A`. Commit after each task; don't push.
- Report every result as "headless only, game feel untested".

## Review Focus

1. The NPC is freed (or its scene unloaded) during a locked talk or a leave → the player is released and the fade cleared, never left puppeted behind black (Task 4 "edges", Task 5 "leave").
2. The inspector's "add element" leaves `null` entries in `interactions` and `steps` → they are skipped, no errors (Task 4 "edges").
3. `once` interactions with an empty `id` → each is still remembered on its own (memory key falls back to `#<index>`) (Task 4 "edges").
4. `World.reset_story()` (the demo's debug clear) while NPCs exist → departed NPCs come back, `appears_if` copies vanish, without a reload (Task 5 "leave").
5. A `move` or `look` naming a missing mark, or a `sound` that never reports `finished` (headless dummy audio) → the step is skipped or times out; the talk always ends (Task 4 "beats").

---

### Task 1: World flags, NPC memory and fade; nearest usable interactable

**Files:**
- Modify: `world/world.gd`
- Modify: `world/interactable.gd`
- Modify: `player/player.gd` (vars near line 98, `_physics_process` at line 161)
- Create: `tests/npc_test.gd`

**Interfaces:**
- Produces (World): `signal flags_changed`; `var flags := {}` (String → int); `var npcs := {}` (String → `{plays = {}, gone = false}`, plus `pos: Vector3`, `facing: Vector3` once saved); `var fade_rect: ColorRect`; `func flag(name: StringName) -> int`; `func set_flag(name: StringName, value := 1) -> void` (emits `flags_changed`); `func npc_memory(id: String) -> Dictionary` (creates the entry, returns it by reference); `func reset_story() -> void` (clears `flags` and `npcs`, emits `flags_changed`); `func fade(to_alpha: float, time := 0.4) -> void` (awaitable).
- Produces (Interactable): `func can_interact() -> bool` (true). `_player_entered` / `_player_exited` add to / erase from `p.interactables`.
- Produces (Player): `var interactables: Array[Interactable] = []`; `p.interactable` is reassigned every physics frame, before `state.physics`, to the nearest valid entry whose `can_interact()` is true (or `null`); freed entries are pruned.
- Produces (tests/npc_test.gd harness): `fails`, `sections`, `course: Node3D`, `player: Player`, `world: Node`; helpers `_course(player_at := Vector3(-10, 1, 0))` (floor `CSGBox3D` 80×1×30 at y −0.5, player), `_box(at, size) -> CSGBox3D`, `_press(action)`, `_wait(frames)`, `_wait_until(cond, frames) -> bool`, `_check(ok, what)`, and the section runner with `--` filter, all copied in shape from `tests/enemy_test.gd`. Each section increments `sections`; `SECTIONS` is the total and grows as tasks add sections.

- [ ] **Step 1: Write the failing tests** (`tests/npc_test.gd`, sections `world` and `overlap`)

```gdscript
func _test_world() -> void:
	world.reset_story()
	var changed := [0]
	world.flags_changed.connect(func() -> void: changed[0] += 1)
	world.set_flag(&"bell")
	_check(world.flag(&"bell") == 1 and world.flags.has("bell") and changed[0] == 1, "set_flag stores a String key, emits once")
	world.set_flag(&"bell", 0)
	_check(world.flag(&"bell") == 0 and world.flag(&"nope") == 0, "0 clears; unset reads 0")
	var m: Dictionary = world.npc_memory("t:Npc")
	_check(m.plays.is_empty() and m.gone == false, "new memory entry")
	m.plays["intro"] = 1
	_check(world.npc_memory("t:Npc").plays["intro"] == 1, "memory returned by reference")
	world.reset_story()
	_check(world.flags.is_empty() and world.npcs.is_empty() and changed[0] == 3, "reset_story clears both and emits")
	_check(world.fade_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE and (world.fade_rect.get_parent() as CanvasLayer).layer >= 100, "fade overlay on top, click-through")
	await world.fade(1.0, 0.1)
	_check(is_equal_approx(world.fade_rect.color.a, 1.0), "fade to black")
	await world.fade(0.0, 0.1)
	_check(is_zero_approx(world.fade_rect.color.a), "fade back")
	_check(world.debug_text().contains("flags:"), "HUD shows flags")
	sections += 1


func _test_overlap() -> void:
	_course()
	var a := _interactable(Vector3(0, 1, 0))
	var b := _interactable(Vector3(2, 1, 0))  # radius 2 spheres overlap between x 0 and 2
	player.teleport(Vector3(0.5, 1, 0))
	await _wait(5)
	_check(player.interactables.size() == 2 and player.interactable == a, "in both zones: the nearer answers")
	player.teleport(Vector3(1.8, 1, 0))
	await _wait(5)
	_check(player.interactable == b, "nearer one changes as the player moves")
	player.teleport(Vector3(3.5, 1, 0))  # out of a, still in b
	await _wait(5)
	_check(player.interactables.size() == 1 and player.interactables[0] == b and player.interactable == b, "leaving one keeps the other")
	b.queue_free()
	await _wait(3)
	_check(player.interactable == null, "freed zone pruned")
	sections += 1
```

`_interactable(at) -> Interactable`: `Interactable.new()`, position `at`, added to `course`, `add_shape(SphereShape3D)` radius 2.

- [ ] **Step 2: Run to verify it fails**

Run: RUN NPCS. Expected: parse errors on `npc_memory` / `interactables`, or a timeout with no `NPCS:` line.

- [ ] **Step 3: Implement**

- `world.gd`: the Interfaces above. `_ready` creates a `CanvasLayer` (`layer = 100`) holding a full-rect black `ColorRect` with alpha 0 and `MOUSE_FILTER_IGNORE` (`fade_rect`). `fade` tweens `fade_rect.color:a` and awaits `finished` (sets the alpha at once when `time <= 0`). `debug_text()` appends `"\nflags: " + "a=1, b=2"` (or `none`). Update the header doc: saving the game = `time`, `channels`, `signals`, `flags`, `npcs`.
- `interactable.gd`: `can_interact()`, list add/erase; keep `p.interactable = null` on exit when it was this zone.
- `player.gd`: `interactables` var and `_pick_interactable() -> Interactable` called at the top of `_physics_process`'s state step.

- [ ] **Step 4: Run to verify it passes**

Run: RUN NPCS. Expected: `NPCS: OK`. Then the smoke and puzzle suites (CLAUDE.md commands): `SMOKE: OK`, `PUZZLES: OK`.

- [ ] **Step 5: Commit**

```bash
git add world/world.gd world/interactable.gd player/player.gd tests/npc_test.gd tests/npc_test.gd.uid
git commit -m "feat(world): story flags, NPC memory, fade; player picks the nearest usable interactable"
```

---

### Task 2: Interaction and step resources

**Files:**
- Create: `npc/npc_step.gd`, `npc/npc_interaction.gd` (+ `.uid`)
- Test: `tests/npc_test.gd` (section `data`)

**Interfaces:**
- Produces `NpcStep` (`@tool`, `class_name NpcStep extends Resource`):
  - `enum Kind { SAY, ANIM, FACE, LOOK, MOVE, SOUND, WAIT, FLAG, LEAVE }`, `enum Look { PLAYER, MARK, AHEAD }`
  - exports, in this order: `kind := Kind.SAY`, `lines: PackedStringArray`, `time := 0.0`, `anim: StringName`, `face: StringName`, `look := Look.PLAYER`, `mark: StringName`, `run := false`, `wait := true` (MOVE: wait for arrival), `sound: AudioStream`, `sound_wait := false` (SOUND: wait for its end), `flag: StringName`, `value := 1`, `fade := 0.4`
  - `const FIELDS := {Kind.SAY: ["lines", "time"], Kind.ANIM: ["anim", "time"], Kind.FACE: ["face"], Kind.LOOK: ["look", "mark"], Kind.MOVE: ["mark", "run", "wait"], Kind.SOUND: ["sound", "sound_wait"], Kind.WAIT: ["time"], Kind.FLAG: ["flag", "value"], Kind.LEAVE: ["flag", "fade"]}`; `_validate_property` drops `PROPERTY_USAGE_EDITOR` from every export not in `FIELDS[kind]` (except `kind`); the `kind` setter calls `notify_property_list_changed()`.
  - `func summary() -> String`; every setter refreshes `resource_name = summary()`.
  - `func pick_line(last: int) -> int`: a random index of `lines`, never `last` when there are 2+ lines (−1 when empty).
  - `func say_time(text: String) -> float`: `time` if > 0, else `1.0 + 0.04 * text.length()`.
- Produces `NpcInteraction` (`@tool`, `class_name NpcInteraction extends Resource`):
  - `enum Trigger { KEY, NEAR }`; exports `id: StringName`, `trigger := Trigger.KEY`, `distance := 4.0` (hidden for KEY), `needs: PackedStringArray`, `once := false`, `locks_player := true`, `steps: Array[NpcStep]`
  - `func available(flags: Dictionary, plays: int) -> bool`: every `needs` name has `flags.get(name, 0) > 0`, and not (`once` and `plays > 0`)
  - `func summary() -> String`; setters refresh `resource_name`.

- [ ] **Step 1: Write the failing tests** (section `data`; these classes may be static-typed)

```gdscript
func _test_data() -> void:
	var s := NpcStep.new()
	s.lines = PackedStringArray(["Hello, stranger.", "Hi.", "Yo."])
	_check(s.resource_name == 'say "Hello, stranger." (+2)', "say summary")
	var shown := _editor_fields(s)
	_check(shown.has("lines") and shown.has("time") and not shown.has("mark") and not shown.has("sound"), "SAY shows only its fields")
	s.kind = NpcStep.Kind.MOVE
	s.mark = &"Well"
	s.run = true
	shown = _editor_fields(s)
	_check(shown.has("mark") and shown.has("wait") and not shown.has("lines"), "MOVE shows its fields")
	_check(s.resource_name == "move → Well (run)", "move summary")
	var say := NpcStep.new()
	say.lines = PackedStringArray(["a", "b", "c"])
	var last := -1
	var seen := {}
	for i in 30:
		var n := say.pick_line(last)
		if n == last:
			_check(false, "line repeated back to back")
		seen[n] = true
		last = n
	_check(seen.size() == 3, "versions: all three show up, never twice in a row")
	_check(is_equal_approx(say.say_time("12345"), 1.2), "line time from length")
	var i := NpcInteraction.new()
	i.id = &"ch2"
	i.needs = PackedStringArray(["ch2"])
	i.once = true
	i.steps = [say, s]
	_check(not i.available({}, 0) and i.available({"ch2": 1}, 0) and not i.available({"ch2": 1}, 1), "needs and once")
	_check(i.resource_name == "ch2 · key · once · needs ch2 · 2 steps", "interaction summary")
	_check(not _editor_fields(i).has("distance"), "KEY hides distance")
	sections += 1
```

`_editor_fields(o: Object) -> Array`: names of `o.get_property_list()` entries with `PROPERTY_USAGE_EDITOR` (properties are filtered through `_validate_property`).

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- data`: parse error (`NpcStep` unknown).
- [ ] **Step 3: Implement both resources** per the Interfaces. Summary formats for the other kinds: `anim wave 1.0s` / `anim wave`, `face happy`, `look player` / `look mark Well` / `look ahead`, `move → Well` (+ ` (run)`, ` (no wait)`), `sound <file name or "none">`, `wait key` (time 0) / `wait 1.5s`, `flag bell_rang = 1`, `leave` / `leave → mara_at_dock`. Interaction: `<id or "?"> · key|near 4 m · once · locks|free (near only when it differs from its default) · needs a, b · N steps`; parts that are default are left out (the test's exact string is the KEY case).
- [ ] **Step 4: Run the editor once** (registers the classes), then `RUN NPCS -- data` → `NPCS: OK`.
- [ ] **Step 5: Commit** `npc/npc_step.gd`, `npc/npc_interaction.gd`, their `.uid`s, `tests/npc_test.gd`: `feat(npc): interaction and step resources`.

---

### Task 3: The NPC body: scene, marks, walking, position memory, presence, head and face

**Files:**
- Create: `npc/npc.gd`, `npc/npc.tscn` (+ `.uid`)
- Create: `npc/npc_talk.gd` (stub in this task: `@tool class_name NpcTalk extends Interactable`, `can_interact()` returns false until Task 4)
- Test: `tests/npc_test.gd` (section `body`; harness helper `_npc`)

**Interfaces:**
- Consumes: `World.npc_memory`, `World.flag`, `World.flags_changed` (Task 1); `NpcInteraction` (Task 2).
- Produces `Npc` (`@tool`, `class_name Npc extends CharacterBody3D`, in group `&"npc"` at runtime and in the editor):
  - signals `arrived`, `cue(name: StringName)`, `finished`
  - exports `interactions: Array[NpcInteraction]`, `appears_if: PackedStringArray`, `notice_distance := 6.0`, `walk_speed := 2.5`, `run_speed := 5.0`, `color` (tints the body material)
  - state `anim: StringName = &"idle"`, `face: StringName = &"neutral"`, `look_target: Variant = null` (global `Vector3` or null), `speaking := false`, `facing := Vector3.FORWARD`, `present := true`, `marks: Dictionary` (`StringName` → global `Vector3`), `playing: NpcInteraction` (Task 4), `line := ""` (Task 4)
  - nodes `head: Node3D` (`Visual/Head`), `talk_zone` (`Talk`, an `NpcTalk`), `bubble: Label3D`, `prompt: Label3D`, `voice: AudioStreamPlayer3D`
  - `func memory_id() -> String` (`Channels.id(self)`), `func memory() -> Dictionary` (`World.npc_memory(memory_id())`)
  - `func walk_to(point: Vector3, running := false) -> void`, `func stop_walk() -> void`, `func walking() -> bool`
  - `func refresh_presence() -> void`, `func save_position() -> void`, `func player() -> Player` (first node of group `&"player"`, cached)
- Scene `npc/npc.tscn` (prototype shapes, like `enemy/enemy.tscn`): `Npc` (script) → `Collision` (capsule r 0.35, h 1.6), `Visual` (y −0.8: `Body` capsule mesh with a local-to-scene material; `Head` Node3D at the neck with `Skull` sphere r 0.28, `EyeL`, `EyeR`, `Mouth` box meshes), `Talk` (`NpcTalk`, one `CollisionShape3D` sphere r 2.0, `color` alpha 0.08), `Bubble` (`Label3D`: billboard enabled, `no_depth_test`, autowrap with a fixed `width`, outline, above the head, hidden), `Prompt` (`Label3D` "E", billboard, hidden), `Voice` (`AudioStreamPlayer3D`), `Marks` (`Node3D`).

- [ ] **Step 1: Write the failing tests** (section `body`)

Harness helper, no static `Npc` type:

```gdscript
const NPC := "res://npc/npc.tscn"

## Props and marks (name -> local offset) are set before _ready. owner = course gives each NPC
## its own memory id (Channels.id), so re-instancing with the same name finds the same memory.
func _npc(at: Vector3, interactions := [], props := {}, npc_name := "", marks := {}) -> Node3D:
	var n: Node3D = load(NPC).instantiate()
	n.name = npc_name if npc_name else "Npc%d" % course.get_child_count()
	n.interactions.assign(interactions)
	for k: String in props:
		n.set(k, props[k])
	for m: String in marks:
		var mk := Marker3D.new()
		mk.name = m
		mk.position = marks[m]
		n.get_node("Marks").add_child(mk)
	n.position = at
	course.add_child(n)
	n.owner = course
	return n
```

```gdscript
func _test_body() -> void:
	world.reset_story()
	_course()
	var n := _npc(Vector3(0, 1, 0), [], {}, "Walker", {"A": Vector3(5, 0, 0), "B": Vector3(0, 0, 5)})
	await _wait(20)
	_check(n.is_on_floor() and n.present and n.anim == &"idle" and n.face == &"neutral" and n.is_in_group(&"npc"), "settles idle, present")
	var a: Vector3 = n.marks[&"A"]
	_check(a.distance_to(Vector3(5, 1, 0)) < 0.01, "marks cached in global space")
	n.walk_to(a)
	await _wait(5)
	_check(n.anim == &"walk" and n.walking(), "walking")
	var got := [false]
	n.arrived.connect(func() -> void: got[0] = true)
	await _wait_until(func() -> bool: return got[0], 240)
	_check(got[0] and _flat(n.global_position).distance_to(_flat(a)) < 0.3 and n.marks[&"A"] == a, "arrives; marks stay put")
	_check(n.facing.dot(Vector3.RIGHT) > 0.9, "faces its motion")
	var mem: Dictionary = world.npcs[n.memory_id()]
	_check(mem.pos.distance_to(n.global_position) < 0.01 and mem.facing.dot(n.facing) > 0.99, "arrival saves position and facing")

	# re-instance: comes back where it stood, marks where they were placed
	var spot: Vector3 = n.global_position
	course.remove_child(n)
	n.free()
	var again := _npc(Vector3(0, 1, 0), [], {}, "Walker", {"A": Vector3(5, 0, 0)})
	await _wait(2)
	_check(again.global_position.distance_to(spot) < 0.05 and again.facing.dot(Vector3.RIGHT) > 0.9, "saved position restored on load")
	_check(again.marks[&"A"].distance_to(Vector3(5, 1, 0)) < 0.01, "marks cached before the restore")
	var fresh := _npc(Vector3(-4, 1, 3), [], {}, "Fresh")
	await _wait(2)
	_check(_flat(fresh.global_position).distance_to(Vector3(-4, 0, 3)) < 0.05 and not world.npcs.get(fresh.memory_id(), {}).has("pos"), "never moved: placed spot")

	# blocked walk snaps after distance / speed * 2 + 1 s
	_box(Vector3(2.5, 1, -6), Vector3(0.5, 3, 4))
	var stuck := _npc(Vector3(0, 1, -6), [], {}, "Stuck", {"C": Vector3(5, 0, 0)})
	await _wait(10)
	var done := [false]
	stuck.arrived.connect(func() -> void: done[0] = true)
	stuck.walk_to(stuck.marks[&"C"])
	var limit := int((5.0 / stuck.walk_speed * 2.0 + 1.0) * Engine.physics_ticks_per_second) + 30
	_check(await _wait_until(func() -> bool: return done[0], limit) and _flat(stuck.global_position).distance_to(_flat(stuck.marks[&"C"])) < 0.05, "blocked walk snaps to the mark")

	# appears_if
	var later := _npc(Vector3(6, 1, 6), [], {appears_if = PackedStringArray(["door_open"])}, "Later")
	await _wait(2)
	_check(not later.present and not later.visible and later.get_node("Collision").disabled, "absent until its flag")
	world.set_flag(&"door_open")
	await _wait(2)
	_check(later.present and later.visible and not later.get_node("Collision").disabled, "appears when the flag is set")

	# head look: toward the player within notice distance, clamped, straight when far
	player.teleport(again.global_position + Vector3(3, 0, -3))
	await _wait(60)
	var to := _flat(player.global_position - again.head.global_position).normalized()
	_check(_flat(-again.head.global_basis.z).normalized().dot(to) > 0.98 or absf(again.head.rotation.y) >= deg_to_rad(74.0), "head turns toward the player (or hits the clamp)")
	_check(absf(again.head.rotation.y) <= deg_to_rad(75.5) and absf(again.head.rotation.x) <= deg_to_rad(35.5), "head clamp")
	player.teleport(again.global_position + Vector3(-20, 0, 0))
	await _wait(60)
	_check(absf(again.head.rotation.y) < 0.05, "far player: head straight")
	sections += 1
```

`_flat(v) -> Vector3`: `Vector3(v.x, 0, v.z)`.

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- body`: load error (no `npc.tscn`).
- [ ] **Step 3: Implement `npc/npc.gd` and `npc/npc.tscn`**
  - `_ready`: add to group; `_cache_marks()` **first**; then at runtime restore `memory().pos/facing` if saved (teleport, orient, `reset_physics_interpolation()`), connect `World.flags_changed` → `refresh_presence`, `refresh_presence()`.
  - `refresh_presence()`: `present` = every `appears_if` flag set and not `memory().gone`; absent → `visible = false`, `Collision.disabled = true`, `talk_zone.set_deferred("monitoring", false)`, stop walking. Editor: always present.
  - `_physics_process` (runtime): gravity from `get_gravity()`, planar velocity toward the walk target (accel like the enemy puppet), `move_and_slide()`, arrival within 0.3 m → stop, `save_position()`, `cue.emit(&"arrive")`, `arrived.emit()`; timeout `dist / speed * 2 + 1` s → teleport to the target, same arrival path. `anim` = `walk`/`run` while moving and `idle` after (when no interaction set another). Orient the body toward `facing` like `Enemy`.
  - Head: target = interaction override (Task 4) else player head when within `notice_distance` else `null`; rotate `head` in `Visual`'s frame toward it, yaw clamped ±75°, pitch ±35°, eased `1 - exp(-8 * delta)`; `null` eases to zero.
  - `_animate(delta)` in the physics tick, `ponytail:` stand-in for an AnimationTree: body squash/bob/tilt for `idle`, `walk`, `run`, `talk`, `wave`, `nod`, `shake`, `bow`, `jump`, `point`, `shrug`; eyes/mouth scale and tilt for `neutral`, `happy`, `sad`, `angry`, `surprised`, `thinking`; blink every 2-5 s; mouth flaps while `speaking`.
- [ ] **Step 4: Run the editor once, then `RUN NPCS -- body`** → `NPCS: OK`. Also `timeout 150 "$GODOT" --headless --path . --editor --quit-after 400` shows no errors from `npc.gd`.
- [ ] **Step 5: Commit** `npc/npc.gd`, `npc/npc.tscn`, `npc/npc_talk.gd`, `.uid`s, `tests/npc_test.gd`: `feat(npc): NPC body with marks, walking, position memory, presence, head look`.

---

### Task 4: Running interactions: key talks, steps, beats, memory, bubble, prompt, warnings

**Files:**
- Modify: `npc/npc.gd`, `npc/npc_talk.gd`
- Test: `tests/npc_test.gd` (sections `key`, `memory`, `progression`, `beats`, `talk_overlap`, `edges`; helpers `_say(lines, props := {}) -> NpcStep`, `_step(kind, props := {}) -> NpcStep`, `_talk(id, steps, props := {}) -> NpcInteraction`)

**Interfaces:**
- Consumes: Task 1-3 interfaces; `Player.start_puppet()` / `end_puppet()` / `state_name`.
- Produces on `Npc`:
  - `playing: NpcInteraction` (null when idle), `line: String` (bubble text without the `▸`)
  - `func key_of(i: NpcInteraction) -> String`: `i.id`, or `"#%d" % interactions.find(i)` when empty
  - `func choose(trigger: NpcInteraction.Trigger) -> NpcInteraction`: first non-null entry with that trigger that is `available(World.flags, memory().plays.get(key_of(i), 0))`
  - `func start_talk() -> void`: cuts an unlocked interaction (`stop_walk`, bubble hidden) and plays `choose(KEY)`
  - `func play(i: NpcInteraction) -> void` (coroutine; counts the play at start; a run token makes a cut coroutine stop after its next await)
  - `func _get_configuration_warnings() -> PackedStringArray`
- Produces on `NpcTalk`: `npc` (the parent), `can_interact()` (= npc present, not playing a locked interaction, not the physics frame an interaction ended on, `choose(KEY) != null`), `interact(p) -> float` (`npc.start_talk.call_deferred()`, returns `0.0`). The ended-frame check keeps the press that closes a talk from reopening it when the player processes after the NPC.
- Step semantics (spec table): SAY shows `line` and `bubble.text = line + " ▸"` while waiting for the key, `speaking = true`, `cue(&"say")`, then hides the bubble; unlocked waits `say_time(line)`. ANIM/FACE persist. LOOK sets the head override (PLAYER: player head; MARK: `marks[mark] + Vector3.UP * 1.5`; AHEAD: none). MOVE `walk_to(marks[mark], run)`, awaits `arrived` when `wait`. SOUND plays on `voice`; with `sound_wait` it waits for `finished` **or** `sound.get_length()` seconds, whichever first. WAIT: `time`, or the key (locked) / 1 s (unlocked) when 0. FLAG: `World.set_flag(flag, value)`. LEAVE: Task 5 (until then: warning and skip). A null step or a step that can't run (missing mark, no sound, no lines) → `push_warning` and skip.
- Key reading: in `_physics_process`, `Input.is_action_just_pressed(&"interact")` on a frame after the one the talk started → emit internal `_advanced`.
- Locked: `player().start_puppet()`, NPC `facing` toward the player, `player().end_puppet()` at the end. End of every interaction: `anim = &"idle"`, `face = &"neutral"`, look override cleared, bubble hidden, `speaking = false`, `save_position()`, `playing = null`, `finished.emit()`.
- `_exit_tree` at runtime: if a locked interaction (or a leave) is running, release the player and `World.fade(0.0, 0.0)`.
- `prompt.visible` = present and `player().interactable == talk_zone` and not playing a locked interaction.
- Warnings (one string each, test checks a keyword): `empty id`, `duplicate id`, `after leave`, `mark` (missing mark name), `no lines`, `no steps`. Mark names are checked against the `Marks` children, not the runtime `marks` cache (warnings run in the editor and on NPCs outside the tree).

- [ ] **Step 1: Write the failing tests**

```gdscript
func _start_key(n: Node3D) -> void: # player into the Talk zone, press interact
	player.teleport(n.global_position + Vector3(1.5, 0, 0))
	await _wait(5)
	await _press(&"interact")
	await _wait(3)


func _test_key() -> void:
	world.reset_story()
	_course()
	var n := _npc(Vector3(0, 1, 0), [_talk(&"t", [_say(["One"]), _say(["Two"])])])
	await _wait(10)
	player.teleport(n.global_position + Vector3(1.5, 0, 0))
	await _wait(5)
	_check(player.interactable == n.talk_zone and n.prompt.visible, "in Talk: interactable and prompt")
	await _press(&"interact")
	await _wait(3)
	_check(player.state_name == &"puppet" and n.playing != null and n.line == "One", "talk starts on line 1 (start press doesn't skip it)")
	_check(n.bubble.visible and n.bubble.text.ends_with("▸") and not n.prompt.visible, "bubble waits for the key; prompt hidden")
	await _press(&"interact")
	await _wait(2)
	_check(n.line == "Two", "one press, one line")
	await _press(&"interact")
	await _wait(3)
	_check(n.playing == null and player.state_name != &"puppet" and not n.bubble.visible, "end: player released, bubble hidden")
	await _wait(10)
	_check(n.playing == null, "the closing press doesn't reopen the talk")
	sections += 1


func _test_memory() -> void:
	world.reset_story()
	_course()
	var make := func() -> Node3D: return _npc(Vector3(0, 1, 0), [_talk(&"intro", [_say(["Hi"])], {once = true}), _talk(&"chat", [_say(["A", "B", "C"])])], {}, "Mem")
	var n: Node3D = make.call()
	await _wait(10)
	await _start_key(n)
	_check(n.line == "Hi", "first talk: the once intro")
	await _press(&"interact")
	await _wait(3)
	var last := ""
	var repeated := false
	var seen := {}
	for k in 20:
		await _start_key(n)
		repeated = repeated or n.line == last
		last = n.line
		seen[n.line] = true
		await _press(&"interact")
		await _wait(3)
	_check(not seen.has("Hi") and seen.size() == 3 and not repeated, "intro never again; versions vary, never back to back")
	_check(world.npcs[n.memory_id()].plays["intro"] == 1 and world.npcs[n.memory_id()].plays["chat"] == 20, "plays counted")
	course.remove_child(n)
	n.free()
	n = make.call()
	await _wait(10)
	await _start_key(n)
	_check(n.line != "Hi", "re-instanced NPC remembers")
	await _press(&"interact")
	sections += 1


func _test_progression() -> void:
	world.reset_story()
	_course()
	var n := _npc(Vector3(0, 1, 0), [_talk(&"ch2", [_say(["New"])], {needs = PackedStringArray(["ch2"])}), _talk(&"old", [_say(["Old"])])])
	await _wait(10)
	await _start_key(n)
	_check(n.line == "Old", "flag unset: skipped")
	await _press(&"interact")
	await _wait(3)
	world.set_flag(&"ch2")
	await _start_key(n)
	_check(n.line == "New", "flag set: the higher entry wins")
	await _press(&"interact")
	await _wait(3)
	var mute := _npc(Vector3(0, 1, -8), [_talk(&"x", [_say(["X"])], {needs = PackedStringArray(["never"])})])
	await _wait(5)
	await _start_key(mute)
	_check(not mute.talk_zone.can_interact() and not mute.prompt.visible and player.state_name != &"puppet", "nothing to say: no prompt, press does nothing")
	sections += 1


func _test_beats() -> void:
	world.reset_story()
	_course()
	var steps := [_step(NpcStep.Kind.ANIM, {anim = &"wave"}), _step(NpcStep.Kind.FACE, {face = &"happy"}), _say(["Look"]),
		_step(NpcStep.Kind.MOVE, {mark = &"A", wait = false}), _say(["Walking"]),
		_step(NpcStep.Kind.LOOK, {look = NpcStep.Look.MARK, mark = &"B"}), _step(NpcStep.Kind.MOVE, {mark = &"Nope"}),
		_step(NpcStep.Kind.SOUND, {sound = _tone(0.3), sound_wait = true}), _step(NpcStep.Kind.FLAG, {flag = &"seen_show"}),
		_step(NpcStep.Kind.MOVE, {mark = &"B"}), _say(["Done"])]
	var n := _npc(Vector3(0, 1, 0), [_talk(&"show", steps)], {}, "Show", {"A": Vector3(4, 0, 0), "B": Vector3(4, 0, 4)})
	await _wait(10)
	await _start_key(n)
	_check(n.anim == &"wave" and n.face == &"happy" and n.line == "Look", "a beat: anim, face and line together")
	await _press(&"interact")
	await _wait(10)
	_check(n.walking() and n.line == "Walking", "move without wait: talks while walking")
	await _press(&"interact")
	await _wait_until(func() -> bool: return n.line == "Done", 600)
	_check(n.line == "Done" and world.flag(&"seen_show") == 1, "missing mark skipped, sound wait ends, flag set")
	_check(_flat(n.global_position).distance_to(_flat(n.marks[&"B"])) < 0.3, "move with wait arrives before the next line")
	_check(n.look_target != null and n.look_target.distance_to(n.marks[&"B"] + Vector3.UP * 1.5) < 0.01, "look at a mark")
	await _press(&"interact")
	await _wait(3)
	_check(n.anim == &"idle" and n.face == &"neutral" and n.playing == null, "reset at the end")
	_check(world.npcs[n.memory_id()].pos.distance_to(n.global_position) < 0.05, "end of talk saves position")
	sections += 1


func _test_talk_overlap() -> void:
	world.reset_story()
	_course()
	var a := _npc(Vector3(0, 1, 0), [_talk(&"a", [_say(["A"])])])
	var b := _npc(Vector3(2.5, 1, 0), [_talk(&"b", [_say(["B"])])])
	await _wait(10)
	player.teleport(Vector3(1.0, 1, 0))
	await _wait(5)
	_check(player.interactable == a.talk_zone and a.prompt.visible and not b.prompt.visible, "nearer NPC answers, alone shows the prompt")
	a.interactions[0].needs = PackedStringArray(["never"])
	await _wait(2)
	_check(player.interactable == b.talk_zone and b.prompt.visible, "NPC with nothing to say is passed over")
	sections += 1


func _test_edges() -> void:
	world.reset_story()
	_course()
	var n := _npc(Vector3(0, 1, 0), [null, _talk(&"", [null, _say(["Once"])], {once = true}), _talk(&"", [_say(["Twice"])], {once = true})])
	await _wait(10)
	await _start_key(n)
	_check(n.line == "Once", "null entries skipped")
	await _press(&"interact")
	await _wait(3)
	await _start_key(n)
	_check(n.line == "Twice", "empty ids remembered apart (#1, #2)")
	await _press(&"interact")
	await _wait(3)
	var gone := _npc(Vector3(0, 1, -8), [_talk(&"t", [_say(["Bye"])])])
	await _wait(5)
	await _start_key(gone)
	_check(player.state_name == &"puppet", "locked")
	gone.queue_free()
	await _wait(3)
	_check(player.state_name != &"puppet" and is_zero_approx(world.fade_rect.color.a), "NPC freed mid-talk releases the player")
	var bad := load(NPC).instantiate()
	bad.interactions.assign([_talk(&"", []), _talk(&"d", [_step(NpcStep.Kind.LEAVE), _say(["late"])]), _talk(&"d", [_step(NpcStep.Kind.MOVE, {mark = &"Nowhere"}), _say([])])])
	var w: String = " ".join(bad._get_configuration_warnings())
	_check(["empty id", "duplicate id", "after leave", "mark", "no lines", "no steps"].all(func(k: String) -> bool: return w.contains(k)), "config warnings")
	bad.free()
	sections += 1
```

`_tone(seconds) -> AudioStreamWAV`: 16-bit mono 22050 Hz sine. `_say(lines, props)` is `_step(NpcStep.Kind.SAY, {lines = PackedStringArray(lines)})` merged with `props`.

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- key memory progression beats talk_overlap edges`: failures or parse errors (`playing`, `choose`).
- [ ] **Step 3: Implement** per the Interfaces in `npc.gd` and `npc_talk.gd`.
- [ ] **Step 4: Run** `RUN NPCS` (all sections) → `NPCS: OK`; smoke and puzzle suites still OK.
- [ ] **Step 5: Commit** `npc/npc.gd`, `npc/npc_talk.gd`, `tests/npc_test.gd`: `feat(npc): key talks, steps and beats, memory, progression, bubble and prompt`.

---

### Task 5: Near barks and leaving

**Files:**
- Modify: `npc/npc.gd`
- Test: `tests/npc_test.gd` (sections `near`, `leave`)

**Interfaces:**
- Consumes: Task 4 runner (`play`, `start_talk`, `choose`), `World.fade`, `World.set_flag`, `memory().gone`.
- Produces: near triggers in `_physics_process` while present and `playing == null`: for each non-null NEAR interaction in list order that is available and armed, with the player within `distance` → disarm it and `play` it (first match only). Every frame, any NEAR interaction whose player distance is beyond `distance + 1.0` re-arms. All start armed.
- Produces: LEAVE step: lock the player if the interaction didn't (`start_puppet`), `await World.fade(1.0, step.fade)`, `memory().gone = true`, `World.set_flag(step.flag)` when set (else emit `World.flags_changed` through `refresh_presence()`), absent, `await World.fade(0.0, step.fade)`, `end_puppet()`, end the interaction (no further steps), `cue(&"leave")`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func _test_near() -> void:
	world.reset_story()
	_course()
	var bark := _talk(&"bark", [_say(["Hey"], {time = 0.3})], {trigger = NpcInteraction.Trigger.NEAR, locks_player = false})
	var n := _npc(Vector3(0, 1, 0), [bark, _talk(&"talk", [_say(["Talk"])])])
	var plays := func() -> int: return world.npcs.get(n.memory_id(), {}).get("plays", {}).get("bark", 0)
	await _wait(10)
	_check(plays.call() == 0, "far: nothing")
	player.teleport(Vector3(3, 1, 0))
	await _wait(5)
	_check(n.playing == bark and n.line == "Hey" and player.state_name != &"puppet", "near: barks without locking")
	await _wait(60)
	_check(n.playing == null and plays.call() == 1, "bark ends on its timer, no refire while staying")
	player.teleport(Vector3(4.5, 1, 0))
	await _wait(5)
	player.teleport(Vector3(3, 1, 0))
	await _wait(5)
	_check(plays.call() == 1, "inside distance + 1 m: still disarmed")
	player.teleport(Vector3(6, 1, 0))
	await _wait(5)
	player.teleport(Vector3(3, 1, 0))
	await _wait(5)
	_check(plays.call() == 2, "re-armed after leaving distance + 1 m")
	player.teleport(Vector3(12, 1, 0))
	await _wait(60)
	_check(n.playing == null, "walking away mid-bark: it still ends")
	player.teleport(Vector3(1.5, 1, 0))
	await _wait(5) # bark fires on approach
	await _press(&"interact")
	await _wait(3)
	_check(n.line == "Talk" and player.state_name == &"puppet", "interact during a bark starts the key talk")
	await _press(&"interact")
	sections += 1


func _test_leave() -> void:
	world.reset_story()
	_course()
	var make := func() -> Node3D: return _npc(Vector3(0, 1, 0), [_talk(&"bye", [_say(["Bye"]), _step(NpcStep.Kind.LEAVE, {flag = &"mara_at_dock", fade = 0.1})])], {}, "Mara")
	var mara: Node3D = make.call()
	var copy := _npc(Vector3(10, 1, 0), [], {appears_if = PackedStringArray(["mara_at_dock"])}, "MaraDock")
	await _wait(10)
	_check(not copy.present, "copy absent at first")
	await _start_key(mara)
	await _press(&"interact")
	var darkest := 0.0
	var locked_at_black := false
	for k in 30:
		await physics_frame
		darkest = maxf(darkest, world.fade_rect.color.a)
		if world.fade_rect.color.a > 0.99:
			locked_at_black = player.state_name == &"puppet"
	await _wait(10)
	_check(darkest > 0.99 and is_zero_approx(world.fade_rect.color.a) and locked_at_black, "fades to black and back, player held meanwhile")
	_check(not mara.present and not mara.visible and mara.get_node("Collision").disabled and copy.present, "gone; the copy appears")
	_check(world.flag(&"mara_at_dock") == 1 and player.state_name != &"puppet" and mara.playing == null, "flag set, player released")
	course.remove_child(mara)
	mara.free()
	mara = make.call()
	await _wait(3)
	_check(not mara.present, "still gone after reload")
	world.reset_story()
	await _wait(3)
	_check(mara.present and not copy.present, "reset_story: back, copy gone")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- near leave`: FAIL lines (no near trigger, LEAVE skipped).
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run** `RUN NPCS` → `NPCS: OK`.
- [ ] **Step 5: Commit** `npc/npc.gd`, `tests/npc_test.gd`: `feat(npc): near barks and leaving with a fade`.

---

### Task 6: NPC Tools editor plugin

**Files:**
- Create: `addons/npc_tools/plugin.cfg`, `addons/npc_tools/plugin.gd` (+ `.uid`)
- Modify: `project.godot` (`[editor_plugins] enabled` gains `"res://addons/npc_tools/plugin.cfg"`)
- Create: `tests/npc_tools_test.tscn`, `tests/npc_tools_test.gd` (+ `.uid`), on `tests/editor_test.gd`, flag `--npc-tools-test`, label `NPC TOOLS`

**Interfaces:**
- Consumes: `Npc` (group `&"npc"`, `interactions`, `Marks`), `NpcInteraction`, `NpcStep`.
- Produces (plugin, `@tool extends EditorPlugin`; toolbar `MenuButton` with tooltip `"NPC builder"` in `CONTAINER_SPATIAL_EDITOR_MENU`, plus a second `MenuButton` shown only while an `Npc` is selected):
  - `func npc_scenes() -> PackedStringArray`: `res://npc/npc.tscn` plus every `res://npc/<dir>/<dir>.tscn`
  - `func create_type(type_name: String, open := true) -> String`: path `res://npc/<snake>/<snake>.tscn` of a new scene inherited from `npc.tscn` (`instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)`, root renamed to PascalCase, `pack`, `ResourceSaver.save`, filesystem scan, `open_scene_from_path` when `open`); `""` when the name is empty or the file exists
  - `func add_npc(scene_path: String) -> Node3D`: instance under the edited scene root at the surface below the view centre, unique name, owner set, undoable, selected
  - `func all_npcs() -> Array`, `func remove_nodes(nodes: Array) -> void` (undoable, owners restored on undo; same shape as Platform Tools)
  - `func add_interaction(npc: Node3D, template: String) -> NpcInteraction`; templates `"talk_once"` (KEY, once, two SAY steps), `"talk"` (KEY, one SAY with three lines), `"bark"` (NEAR, `locks_player = false`, one SAY), `"leave"` (KEY, once, SAY then LEAVE). Ids `talk`, `talk2`, ... / `bark`, `bark2` / `leave`, ... unique on that NPC. Undoable with `add_do_property`/`add_undo_property` on `interactions` (a new array each time).
  - `func start_mark(npc: Node3D) -> void` (next viewport click places, Esc cancels, via `_forward_3d_gui_input` with forwarding always on), `func place_mark(npc: Node3D, at: Vector3) -> Marker3D` (child of `Marks`, names `Mark`, `Mark2`, ..., owner set, undoable)
  - `func pick_surface(from: Vector3, dir: Vector3, fallback_y: float) -> Vector3`: editor `direct_space_state.intersect_ray`, else the horizontal plane at `fallback_y` (the NPC's feet: its y − 0.8)
  - `var _npc_menu: MenuButton`: the selected-NPC menu (the test reads its `visible`)
- Menu items: builder icon → **New NPC** ▸ (one entry per `npc_scenes()`), **New NPC Type…** (name dialog), **NPCs (N)** ▸ (select / Remove); selected-NPC icon → **Add Interaction** ▸ (Talk once, Talk, Bark, Leave), **Add Mark**.

- [ ] **Step 1: Write the failing editor test** (`run()` checks; find the plugin by the `"NPC builder"` tooltip as `platform_tools_test.gd`'s `_find_plugin` does)

```gdscript
	var nt = _find_plugin()
	check(nt != null, "NPC builder icon found")
	var path: String = nt.create_type("Test Guard", false)
	check(path == "res://npc/test_guard/test_guard.tscn" and FileAccess.file_exists(path), "type scene written")
	var ps: PackedScene = load(path)
	check(ps.get_state().get_base_scene_state() != null and ps.instantiate() is Npc, "inherits npc.tscn")
	check(nt.create_type("Test Guard", false) == "" and nt.npc_scenes().has(path), "duplicate refused; listed")
	var ur := EditorInterface.get_editor_undo_redo()
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(self))
	var n: Node3D = nt.add_npc("res://npc/npc.tscn")
	check(n.get_parent() == self and n.owner == self and nt.all_npcs() == [n] and EditorInterface.get_selection().get_selected_nodes() == [n], "NPC added, saved, selected")
	await frames(1)
	check(nt._npc_menu.visible, "selected-NPC menu shows")
	var t1: NpcInteraction = nt.add_interaction(n, "talk_once")
	var t2: NpcInteraction = nt.add_interaction(n, "talk")
	var b: NpcInteraction = nt.add_interaction(n, "bark")
	var l: NpcInteraction = nt.add_interaction(n, "leave")
	check(t1.id == &"talk" and t1.once and t1.steps.size() == 2 and t2.id == &"talk2" and t2.steps[0].lines.size() == 3, "talk templates")
	check(b.trigger == NpcInteraction.Trigger.NEAR and not b.locks_player and l.steps[-1].kind == NpcStep.Kind.LEAVE and l.once, "bark and leave templates")
	hist.undo()
	check(n.interactions.size() == 3, "undo add interaction")
	hist.redo()
	var m1: Marker3D = nt.place_mark(n, Vector3(3, 0, 0))
	var m2: Marker3D = nt.place_mark(n, Vector3(0, 0, 3))
	check(m1.get_parent() == n.get_node("Marks") and m1.name == &"Mark" and m2.name == &"Mark2" and m1.owner == self and m1.global_position.is_equal_approx(Vector3(3, 0, 0)), "marks placed")
	check(nt.pick_surface(Vector3(50, 10, 50), Vector3.DOWN, -0.8).is_equal_approx(Vector3(50, -0.8, 50)), "no collider: plane at the feet")
	var body := StaticBody3D.new() # box top at y 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	await physics_frames(2)
	check(absf(nt.pick_surface(Vector3(0, 10, 0), Vector3.DOWN, -0.8).y - 1.0) < 0.01, "ray hits a collider")
	hist.undo() # mark 2
	hist.undo() # mark 1
	check(n.get_node("Marks").get_child_count() == 0, "undo marks")
	for k in 4: # the four interactions, then the NPC itself
		hist.undo()
	hist.undo()
	check(not is_instance_valid(n) or n.get_parent() == null, "undo add NPC")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())
	finished = true
```

- [ ] **Step 2: Run to verify it fails** — `timeout 150 "$GODOT" --headless --path . -e res://tests/npc_tools_test.tscn -- --npc-tools-test 2>&1 | grep -viE "$NOISE"`: `NPC builder icon found` FAIL.
- [ ] **Step 3: Implement the plugin** per the Interfaces, following `addons/platform_tools/plugin.gd` (`_add`/`_attach`/`_select`/`remove_nodes`/`_icon`; copy those helpers, they are a few lines). Enable it in `project.godot`.
- [ ] **Step 4: Run** the NPC Tools suite → `NPC TOOLS: OK`; the Shape Tools and Platform Tools suites still OK; `--editor --quit-after 400` shows no errors.
- [ ] **Step 5: Commit** `addons/npc_tools/*`, `project.godot`, `tests/npc_tools_test.*`: `feat(npc): NPC Tools editor plugin`.

---

### Task 7: Demo scene

**Files:**
- Create: `demo/npcs/npcs.tscn`, `demo/npcs/npcs.gd` (+ `.uid`), `demo/npcs/blip.tres` (`AudioStreamWAV`, a ~0.12 s generated tone; write it once with a throwaway script in `$CLAUDE_JOB_DIR/tmp`, commit only the `.tres`)
- Test: `tests/npc_test.gd` (section `demo`)

**Interfaces:**
- Consumes: everything above; `GameArea` (`help()`, `_unhandled_input`, `Bays`).
- Produces: `npcs.gd extends GameArea` with `area_id = &"npcs"`; `help()` adds `7 clear story flags and NPC memory | 8 reload scene`; key 7 → `World.reset_story()`, key 8 → `get_tree().reload_current_scene()`; both call `super` for other keys.
- Bays (each with a `Start` marker), per the spec: **Greeter** (near bark, once intro with wave + happy, repeat with three versions); **Progression** (Smith with a `needs bell_rang` talk listed above "Come back when the bell has rung", Ringer whose talk ends with `flag bell_rang`); **Performer** (locked talk across 3 marks, one `move` with `wait = false`, `look` at a mark, faces, anims, `blip.tres` sounds) and **Doorman** (once talk walks him aside from a 2 m gap in a wall; the gap leads somewhere visible); **Leaver** (Mara: leave with `flag mara_at_dock`) and **Dock** (MaraDock with `appears_if mara_at_dock`, its own lines).

- [ ] **Step 1: Write the failing test** (section `demo`)

```gdscript
func _test_demo() -> void:
	world.reset_story()
	if course:
		root.remove_child(course)
		course.queue_free()
		course = null
	var demo: Node = load("res://demo/npcs/npcs.tscn").instantiate()
	root.add_child(demo)
	await _wait(60)
	var npcs := get_nodes_in_group(&"npc")
	var by_name := {}
	for n: Node in npcs:
		by_name[String(n.name)] = n
	_check(["Greeter", "Smith", "Ringer", "Performer", "Doorman", "Mara", "MaraDock"].all(func(k: String) -> bool: return by_name.has(k)), "demo: the seven NPCs")
	_check(not by_name.MaraDock.present and npcs.filter(func(n: Node) -> bool: return n.present).size() == 6, "only MaraDock absent at the start")
	_check(npcs.all(func(n: Node) -> bool: return n._get_configuration_warnings().is_empty()), "no config warnings")
	_check(load("res://demo/npcs/blip.tres") is AudioStreamWAV, "blip sound")
	demo.queue_free()
	sections += 1
```

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- demo`: load error.
- [ ] **Step 3: Build the scene and script.** Writing the `.tscn` by hand or generating it with a throwaway script are both fine; commit the `.tscn`. Prototype shapes only (CSG with collision for floors, walls, the dock).
- [ ] **Step 4: Run** `RUN NPCS` → `NPCS: OK`, and `timeout 150 "$GODOT" --headless --path . --quit-after 300 res://demo/npcs/npcs.tscn` shows no errors.
- [ ] **Step 5: Commit** `demo/npcs/*`, `tests/npc_test.gd`: `feat(demo): NPC demo`.

---

### Task 8: Docs, CLAUDE.md, full verification

**Files:**
- Create: `docs/npcs.md`
- Modify: `CLAUDE.md` (architecture section **NPCs** after Enemies; test commands for `npc_test.gd` and the NPC Tools suite; `NPCS|NPC TOOLS` in the result-line list; the World paragraph mentions `flags`, `npcs`, `fade`; the `-s` gotcha lists `Npc`, `NpcTalk`)

**Interfaces:**
- Consumes: the finished system. `docs/npcs.md` sections: authoring (list order is priority, `once`, versions, `needs`, leaving and copies, marks, moved NPCs stay moved, the tool and its templates), flags, NPC memory and saving, `anim`/`face`/`cue` value tables, and the presentation hookup from the spec's Docs section (AnimationTree on `anim` with Physics callback; `LookAtModifier3D` on the head bone targeting a node moved to `look_target`, influence eased to 0 on `null`; face animations named after `face` values plus blink and mouth flap from `speaking`; a presenter child for `cue`). Same voice and shape as `docs/enemies.md`.

- [ ] **Step 1: Write `docs/npcs.md` and the CLAUDE.md edits.**
- [ ] **Step 2: Run every suite** (CLAUDE.md commands plus the two new ones): `SMOKE`, `PLATFORMS`, `PUZZLES`, `ENEMIES`, `NPCS`, `SHAPE EDITOR`, `PLATFORM TOOLS`, `NPC TOOLS` all `OK`; `--editor --quit-after 400` and `--quit-after 300 res://demo/npcs/npcs.tscn` without errors.
- [ ] **Step 3: Commit** `docs/npcs.md`, `CLAUDE.md`: `docs: NPC guide; CLAUDE.md NPC section and suites`.
