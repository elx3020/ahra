# NPC Avoidance and Routines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NPC walks steer around the player and other NPCs, wait at a destination the player stands on (arrive beside it when their own locked talk holds the player), never snap onto the player; and a ROUTINE trigger that loops when nothing else runs, cut by talks and barks and resumed at its step; plus a sweeper demo bay.

**Architecture:** All in `npc/npc.gd`'s walk (`_move`) and runner (`play`), plus one enum value in `NpcInteraction`. Steering is reactive (detour point beside the nearest obstacle ahead), no navmesh. A routine is an `NpcInteraction` with `trigger = ROUTINE` run by the same coroutine runner.

**Tech Stack:** Godot 4.7.2 GDScript, headless `SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-11-21-npc-avoidance-routine-design.md` (builds on `2026-11-20-npc-interaction-design.md`)

## Global Constraints

- Same as `docs/superpowers/plans/2026-11-20-npc-interaction.md` Global Constraints (Godot exe, `timeout`, no static `Npc` types in `-s` tests, `.uid` sidecars, `ponytail:` comments, stage by path, commit per task, don't push, "headless only, game feel untested").
- **RUN NPCS** = `timeout 400 "$GODOT" --headless --path . -s res://tests/npc_test.gd` (+ `-- <sections>`), passes on `NPCS: OK`.
- Values: clearance `1.0` m (NPC 0.35 + player 0.4 + 0.25), look-ahead `2.0` m, stop short at clearance + `0.3` m, waiting `anim = &"wait"`, `cue(&"blocked")` once per wait, routine resume one physics frame after an interaction ends.
- Only the player makes a destination "taken"; steering avoids the player and other present NPCs.

## Review Focus

1. Two NPCs walking toward each other → both detour and arrive; no face-to-face deadlock (Task 1 "avoid").
2. The player presses interact on a routine NPC that is waiting at a taken mark → the talk starts, `waiting` and `anim = &"wait"` are cleared, and the routine resumes afterwards (Task 2 "routine").
3. A routine NPC turns absent mid-routine (flag cleared) → it stops without errors; present again → the routine restarts (Task 2 "routine").
4. Reloading the area (re-instancing) a routine NPC → it starts at its saved spot and runs its routine again (Task 2 "routine").
5. A routine of instant steps only → no freeze (one loop per physics frame at most) and a config warning (Task 2 "routine").

---

### Task 1: Steering, waiting at a taken mark, safe snap

**Files:**
- Modify: `npc/npc.gd` (`_move`, `walk_to`, `stop_walk`, `_look_point`, `_animate`)
- Test: `tests/npc_test.gd` (section `avoid`)

**Interfaces:**
- Produces on `Npc`: `const CLEARANCE := 1.0`, `const LOOK_AHEAD := 2.0`, `const STOP_SHORT := 0.3`; `var waiting := false` (a walk paused at a taken destination; false whenever not walking); `func taken(point: Vector3) -> bool` (the player's planar distance to `point` < CLEARANCE); `cue(&"blocked")` emitted once when a wait starts; `anim == &"wait"` while waiting.
- Steering, each physics frame of a walk: obstacles are the player and every other present NPC (planar positions). Among those with `0 < ahead <= LOOK_AHEAD` (distance along the direction to the target) and lateral offset from the walk line `< CLEARANCE`, take the nearest; head for `obstacle + away * CLEARANCE` (`away` = the unit lateral direction from the obstacle toward the walk line's side the NPC is on; when the offset is under 0.05 m, the NPC's right, `dir.cross(up_direction)`) instead of the target. Skip an obstacle that sits within CLEARANCE of the target itself (that's the taken-destination case).
- Taken destination: when `taken(target)` and the NPC is within `CLEARANCE + STOP_SHORT` (planar) of the target: if `_locked`, arrive there (same arrival path: `arrived`, save); else stop, `waiting = true`, the timeout doesn't run, body faces the target, head looks at the player. Free again → `waiting = false`, walk on.
- Snap after the timeout: if `taken(target)`, don't snap; re-arm `_walk_left = 1.0`.

- [ ] **Step 1: Write the failing tests** (section `avoid`; marks are floor points, so pass local offsets with y −0.8)

```gdscript
func _test_avoid() -> void:
	world.reset_story()
	_course()
	# around a standing player: no snap, never touches
	var n := _npc(Vector3(-8, 1, 0), [], {}, "Around", {"T": Vector3(8, -0.8, 0)})
	player.teleport(Vector3(-4, 1, 0))
	await _wait(10)
	var r := await _walk_watch(n, n.marks[&"T"], 400)
	_check(r.arrived and r.frames < 5 * Engine.physics_ticks_per_second, "walks around a standing player (%d frames, no snap)" % r.frames)
	_check(r.closest > 0.7, "never runs into the player (closest %.2f m)" % r.closest)

	# waits at a taken mark past the timeout; arrives once the player leaves
	var w := _npc(Vector3(-8, 1, 8), [], {}, "Waiter", {"M": Vector3(6, -0.8, 0)})
	await _wait(5)
	player.teleport(w.marks[&"M"] + Vector3.UP)
	var blocked := [0]
	w.cue.connect(func(c: StringName) -> void: if c == &"blocked": blocked[0] += 1)
	w.walk_to(w.marks[&"M"])
	await _wait(int((6.0 / w.walk_speed * 2.0 + 1.0) * Engine.physics_ticks_per_second) + 120)
	var d := _flat(w.global_position).distance_to(_flat(w.marks[&"M"]))
	_check(w.waiting and w.walking() and w.anim == &"wait" and d <= 1.4 and d >= 0.7 and blocked[0] == 1, "waits beside a taken mark past the timeout (%.2f m)" % d)
	player.teleport(Vector3(-20, 1, 8))
	var got := [false]
	w.arrived.connect(func() -> void: got[0] = true)
	_check(await _wait_until(func() -> bool: return got[0], 120) and not w.waiting and w.anim != &"wait", "arrives once the mark is free")

	# two NPCs swapping places: both arrive
	var p1 := _npc(Vector3(-6, 1, -8), [], {}, "P1", {"G": Vector3(12, -0.8, 0)})
	var p2 := _npc(Vector3(6, 1, -8), [], {}, "P2", {"G": Vector3(-12, -0.8, 0)})
	await _wait(5)
	var both := [0]
	for q in [p1, p2]:
		q.arrived.connect(func() -> void: both[0] += 1)
		q.walk_to(q.marks[&"G"])
	_check(await _wait_until(func() -> bool: return both[0] == 2, 360), "two NPCs walking at each other both arrive")

	# locked talk, the held player on the mark: arrives beside it and the talk goes on
	var h := _npc(Vector3(10, 1, 6), [_talk(&"t", [_say(["Go"]), _step(NpcStep.Kind.MOVE, {mark = &"M"}), _say(["Here"])])], {}, "Holder", {"M": Vector3(1.5, -0.8, 0)})
	await _wait(5)
	await _start_key(h) # the player stands at the NPC + (1.5, 0, 0): on the mark
	await _press(&"interact")
	_check(await _wait_until(func() -> bool: return h.line == "Here", 180), "held player on the mark: arrives beside it")
	await _press(&"interact")
	await _wait(3)

	# the Performer case: the held player between the NPC and its mark
	var perf := _npc(Vector3(20, 1, -6), [_talk(&"show", [_say(["Watch"]), _step(NpcStep.Kind.MOVE, {mark = &"Far"}), _say(["Done"])])], {}, "Perf", {"Far": Vector3(8, -0.8, 0)})
	await _wait(5)
	await _start_key(perf)
	await _press(&"interact")
	var t0 := Engine.get_physics_frames()
	_check(await _wait_until(func() -> bool: return perf.line == "Done", 400) and Engine.get_physics_frames() - t0 < 5 * Engine.physics_ticks_per_second, "walks around the held player to its mark (no snap)")
	await _press(&"interact")
	sections += 1


## Walks `n` to `to`, returning {arrived, frames, closest (planar m to the player)}.
func _walk_watch(n: Node3D, to: Vector3, frames: int) -> Dictionary:
	var r := {arrived = false, frames = 0, closest = INF}
	n.arrived.connect(func() -> void: r.arrived = true, CONNECT_ONE_SHOT)
	n.walk_to(to)
	while not r.arrived and r.frames < frames:
		await physics_frame
		r.frames += 1
		r.closest = minf(r.closest, _flat(n.global_position).distance_to(_flat(player.global_position)))
	return r
```

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- avoid`: FAIL lines (pushes into the player / snaps, `waiting` missing).
- [ ] **Step 3: Implement** per the Interfaces in `npc.gd`. `_animate` gets a `wait` pose (a small idle sway); `_look_point` returns the player's head while `waiting`. `stop_walk` and every arrival clear `waiting`. Doc comments on `walk_to` describe steering and waiting.
- [ ] **Step 4: Run** `RUN NPCS` → `NPCS: OK` (all sections: the Performer demo walkthrough too).
- [ ] **Step 5: Commit** `npc/npc.gd`, `tests/npc_test.gd`: `fix(npc): walk around the player and other NPCs, wait at a taken mark`.

---

### Task 2: Routine trigger

**Files:**
- Modify: `npc/npc_interaction.gd`, `npc/npc.gd`
- Test: `tests/npc_test.gd` (section `routine`)

**Interfaces:**
- Consumes: Task 1 (`waiting`, walks).
- Produces on `NpcInteraction`: `enum Trigger { KEY, NEAR, ROUTINE }`; `_validate_property` shows `distance` only for NEAR and hides `locks_player` for ROUTINE; summary `"<id> · routine · ..."`.
- Produces on `Npc`:
  - `func play(i: NpcInteraction, from_step := 0) -> void`; `var step_at := 0` (index of the step running); a routine never locks (`_locked = i.locks_player and i.trigger != ROUTINE`).
  - Cutting (`start_talk`, a near bark firing while a routine plays): a cut routine remembers `step_at` as its resume step; the cut ends it the normal way (`_end`).
  - `func _resume_routine() -> void` (coroutine): waits one physics frame; returns unless present and `playing == null`; plays `choose(ROUTINE)`, from the remembered step if it's the same routine that was cut, else from 0. Called at the end of every `_end()`, at the end of `_start()`, and from `refresh_presence()` when the NPC is present and idle. A routine that completes its steps resets its resume step to 0 (it loops through `_end` → resume).
  - `_check_near` may fire while a routine plays (cutting it); a bark still can't cut a key talk.
  - Config warning containing `"takes time"` for a ROUTINE with no step that waits (SAY; ANIM or WAIT with time > 0; WAIT 0; MOVE with wait; SOUND with sound_wait).
- `waiting` and the `wait` anim are cleared by `_end` (via `stop_walk`) when a talk cuts a waiting routine.

- [ ] **Step 1: Write the failing tests** (section `routine`)

```gdscript
func _test_routine() -> void:
	world.reset_story()
	_course()
	var loop := _talk(&"loop", [_step(NpcStep.Kind.MOVE, {mark = &"A"}), _step(NpcStep.Kind.WAIT, {time = 0.2}),
		_step(NpcStep.Kind.MOVE, {mark = &"B"}), _step(NpcStep.Kind.WAIT, {time = 0.2})], {trigger = NpcInteraction.Trigger.ROUTINE})
	var make := func() -> Node3D: return _npc(Vector3(0, 1, -8), [loop, _talk(&"talk", [_say(["Busy!"])])], {}, "Sweeper",
		{"A": Vector3(4, -0.8, 0), "B": Vector3(-4, -0.8, 0)})
	var s: Node3D = make.call()
	var arrivals := [0]
	s.arrived.connect(func() -> void: arrivals[0] += 1)
	await _wait(10)
	_check(s.playing == loop and s.walking() and player.state_name != &"puppet", "the routine starts on its own and doesn't hold the player")
	_check(await _wait_until(func() -> bool: return arrivals[0] >= 3, 600), "it loops: A, B, A...")

	# a talk cuts it; afterwards it resumes at the step it was on
	await _wait_until(func() -> bool: return s.step_at == 2 and s.walking(), 400)
	await _start_key(s)
	_check(s.line == "Busy!" and player.state_name == &"puppet" and not s.walking(), "a talk cuts the routine")
	await _press(&"interact")
	await _wait(5)
	_check(s.playing == loop and s.step_at == 2 and s.walking(), "resumes at the step it was on (walking to B)")

	# waiting at a taken mark, then talked to: the wait is cleared, the routine resumes after
	await _wait_until(func() -> bool: return s.step_at == 0 and s.walking(), 400)
	player.teleport(s.marks[&"A"] + Vector3.UP)
	await _wait_until(func() -> bool: return s.waiting, 400)
	player.teleport(s.global_position + Vector3(1.0, 0, 0)) # into its Talk zone, off the mark
	await _wait(3)
	await _press(&"interact")
	await _wait(3)
	_check(s.line == "Busy!" and not s.waiting and s.anim != &"wait", "talking to a waiting routine NPC")
	await _press(&"interact")
	await _wait(5)
	_check(s.playing == loop and s.step_at == 0, "back to its routine")

	# absent mid-routine: stops; present again: restarts
	var ghost := _npc(Vector3(0, 1, 8), [_talk(&"g", [_step(NpcStep.Kind.WAIT, {time = 0.5})], {trigger = NpcInteraction.Trigger.ROUTINE})], {appears_if = PackedStringArray(["haunt"])}, "Ghost")
	await _wait(5)
	_check(ghost.playing == null, "absent: no routine")
	world.set_flag(&"haunt")
	await _wait(5)
	_check(ghost.playing != null, "present: the routine starts")
	world.set_flag(&"haunt", 0)
	await _wait(5)
	_check(ghost.playing == null and not ghost.present, "absent again: it stops")

	# progression picks the routine (list order), at its next loop
	var late := _talk(&"late", [_step(NpcStep.Kind.WAIT, {time = 0.2})], {trigger = NpcInteraction.Trigger.ROUTINE, needs = PackedStringArray(["late"])})
	var early := _talk(&"early", [_step(NpcStep.Kind.WAIT, {time = 0.2})], {trigger = NpcInteraction.Trigger.ROUTINE})
	var prog := _npc(Vector3(10, 1, 8), [late, early], {}, "Prog")
	await _wait(5)
	_check(prog.playing == early, "early routine first")
	world.set_flag(&"late")
	_check(await _wait_until(func() -> bool: return prog.playing == late, 60), "the late routine takes over")

	# a near bark fires during a routine, then the routine resumes
	var bark := _talk(&"bark", [_say(["Hi!"], {time = 0.3})], {trigger = NpcInteraction.Trigger.NEAR, locks_player = false})
	var chatty := _npc(Vector3(-20, 1, 8), [bark, _talk(&"r", [_step(NpcStep.Kind.WAIT, {time = 1.0})], {trigger = NpcInteraction.Trigger.ROUTINE})], {}, "Chatty")
	await _wait(5)
	player.teleport(Vector3(-17, 1, 8))
	await _wait(5)
	_check(chatty.playing == bark, "a bark cuts the routine")
	_check(await _wait_until(func() -> bool: return chatty.playing != null and chatty.playing.trigger == NpcInteraction.Trigger.ROUTINE, 60), "the routine resumes after the bark")

	# instant routine: no freeze, a warning
	var quick := _npc(Vector3(-20, 1, -8), [_talk(&"q", [_step(NpcStep.Kind.FACE, {face = &"happy"})], {trigger = NpcInteraction.Trigger.ROUTINE})], {}, "Quick")
	await _wait(30)
	var loops: int = world.npcs[quick.memory_id()].plays["q"]
	_check(loops > 0 and loops <= 31, "an instant routine loops at most once a frame (%d)" % loops)
	_check(" ".join(quick._get_configuration_warnings()).contains("takes time"), "and warns")

	# reload: back at its saved spot, running its routine
	var spot: Vector3 = s.global_position
	course.remove_child(s)
	s.free()
	s = make.call()
	await _wait(5)
	_check(s.playing == loop and _flat(s.global_position).distance_to(_flat(spot)) < 1.5, "reloaded: its routine runs again from where it stood")
	sections += 1
```

- [ ] **Step 2: Run to verify it fails** — `RUN NPCS -- routine`: parse error on `Trigger.ROUTINE` or FAIL lines.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run** `RUN NPCS` → `NPCS: OK`.
- [ ] **Step 5: Commit** `npc/npc_interaction.gd`, `npc/npc.gd`, `tests/npc_test.gd`: `feat(npc): routines (loop when idle, cut by talks and barks, resume)`.

---

### Task 3: Sweeper demo bay, docs, full verification

**Files:**
- Modify: `demo/npcs/npcs.tscn` (regenerated by the throwaway generator in the job tmp dir, extended with a sixth bay; the floor and bounds widened to cover it), `docs/npcs.md`, `CLAUDE.md`, `addons/npc_tools/plugin.gd` (a **Routine** template: ROUTINE, MOVE to `Mark`, WAIT 1 s, SAY "Hm hm hm." with `time`; id `routine`)
- Test: `tests/npc_test.gd` (section `demo`), `tests/npc_tools_test.gd`

**Interfaces:**
- Bay **Routine** (index 5): a **Sweeper** NPC looping four corner marks of a 6 × 6 m square (MOVE, `anim sweep` 1.5 s, a timed muttered line at two corners), a key talk ("Busy, busy!" with versions), label: "SWEEPER: a routine. Stand in her way: she walks around you. Stand on a corner: she waits."
- `docs/npcs.md`: ROUTINE in the interactions table and list-order example, "Walking around people" (steering, taken marks, the locked-talk rule, snap safety), the `wait` anim and `blocked` cue in the presentation tables, the demo bay. CLAUDE.md NPC paragraph: ROUTINE and steering in one sentence each.

- [ ] **Step 1: Failing tests**: demo section expects `"Sweeper"` among the NPCs (eight), present, `playing.trigger == ROUTINE` after 60 frames; editor test: `add_interaction(n, "routine")` → `trigger == ROUTINE`, `id == &"routine"`, five templates then (the existing `n.interactions.size()` checks move by one).
- [ ] **Step 2: Run** both suites → FAIL on the new checks.
- [ ] **Step 3: Implement**: template, generator bay, regenerate `npcs.tscn`, docs.
- [ ] **Step 4: Run every suite** (CLAUDE.md list + NPCS + NPC TOOLS), `--editor --quit-after 400`, `--quit-after 300 res://demo/npcs/npcs.tscn` → all OK, no script errors.
- [ ] **Step 5: Commit** `demo/npcs/npcs.tscn`, `addons/npc_tools/plugin.gd`, `docs/npcs.md`, `CLAUDE.md`, `tests/npc_test.gd`, `tests/npc_tools_test.gd`: `feat(demo): sweeper routine bay; docs`.
