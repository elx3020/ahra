# NPC Walk "Needs Room" Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `MOVE` step with complaint `lines` refuses to walk while the player stands within `room` of its way: the NPC says a line, the interaction ends uncounted, the NPC stays put.

**Architecture:** Two fields on `NpcStep` (reuse `lines`, add `room`), one geometry helper `Npc.in_way`, and an early branch in `Npc._do`'s `MOVE` that reuses the `SAY` body (extracted to `_say`) and then ends the run like `LEAVE` does, after taking the play back.

**Tech Stack:** Godot 4.7.2 GDScript; headless `-s` suite `tests/npc_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-21-npc-move-room-check-design.md`

## Global Constraints

- Empty `lines` on a `MOVE` = no check; the walk behaves exactly as before.
- `room` default `1.0` m, planar distance from the player to the segment NPC → mark (the mark end counts).
- Checked once, when the `MOVE` step starts; never re-checked mid-walk.
- On a complaint: say one line like `SAY` (locked: waits for interact, `▸`; unlocked: `say_time`), then end the interaction there; the play count for it goes down by one (floor 0); earlier steps stay done.
- Summary: `move → Aside (room 1.2 m)` when the step has lines (other suffixes unchanged).
- Demo Doorman: lines `You're in my way. Step back a bit.`, room `1.2`.
- Static typing, `##` docs; don't static-type `Npc` in tests; keep `.uid` sidecars (no new scripts here).
- Don't touch `demo/builder/` or `.godot/editor/editor_layout.cfg`. Commit locally, don't push.

## Review Focus

1. A routine whose walk complains (player parked on its way): it restarts its loop each time, one complaint per `say_time`, never a same-frame loop, no errors. → Task 1 test.
2. A talk cutting a routine mid-complaint: the complaint neither ends nor refunds the cut run twice; the routine resumes at the `MOVE` (re-checks) after the talk. → Task 1 test.
3. A `MOVE` with lines but a missing mark: still warns and is skipped (mark check first), no complaint. → Task 1 test.
4. No player in the tree: `in_way` is false (no crash). → guard in Task 1, review only.
5. A `NEAR` bark that complains: shows for its time and ends; its re-arm rule is unchanged. → review only.

---

### Task 1: The room check

**Files:**
- Modify: `npc/npc_step.gd` (FIELDS, ALL, `lines` doc, new `room`, MOVE summary)
- Modify: `npc/npc.gd` (`in_way`, `_say` extracted from `_do` SAY, MOVE branch)
- Test: `tests/npc_test.gd` (new section `room`, `SECTIONS` 18 → 19, listed before `_test_demo`)

**Interfaces:**
- Produces: `NpcStep.room: float` (= 1.0); `FIELDS[Kind.MOVE] == ["mark", "run", "wait", "lines", "room"]`; `Npc.in_way(point: Vector3, room: float) -> bool`; `Npc._say(s: NpcStep, run: int) -> void` (awaitable; the old SAY body).

- [ ] **Step 1: Write the failing test** `_test_room()` in `tests/npc_test.gd` (helpers `_npc`, `_step`, `_say`, `_talk`, `_start_key`, `_press`, `_wait`, `_wait_until`, `_flat`, `_editor_fields` exist):

```gdscript
## A MOVE with lines refuses to walk while the player is within `room` of its way.
func _test_room() -> void:
	world.reset_story()
	_course()
	var mv := _step(NpcStep.Kind.MOVE, {mark = &"M", lines = PackedStringArray(["You're in my way."]), room = 1.2})
	_check(mv.resource_name == "move → M (room 1.2 m)", "summary: " + mv.resource_name)
	_check(_editor_fields(mv).has("lines") and _editor_fields(mv).has("room") and not _editor_fields(_say(["x"])).has("room"), "MOVE shows lines and room")
	var t := _talk(&"t", [_say(["Want me to move?"]), mv, _say(["Done"])], {once = true})
	var n := _npc(Vector3(0, 1, 8), [t], {}, "Mover", {"M": Vector3(4, -0.8, 0)})
	await _wait(5)
	var start := _flat(n.global_position)
	# in_way: the segment, the mark end counts, beyond the mark doesn't
	player.teleport(n.marks[&"M"] + Vector3(0, 0.8, 0))
	await _wait(3)
	_check(n.in_way(n.marks[&"M"], 1.0), "standing on the mark is in the way")
	player.teleport(n.marks[&"M"] + Vector3(2.5, 0.8, 0))
	await _wait(3)
	_check(not n.in_way(n.marks[&"M"], 1.0), "beyond the mark isn't")
	# on the line: complains, stays, the once talk isn't spent
	await _start_key(n) # player at +1.5 x: on the line
	_check(n.line == "Want me to move?", "talk starts")
	await _press(&"interact")
	await _wait(3)
	_check(n.line == "You're in my way." and not n.walking(), "complains instead of walking")
	await _press(&"interact")
	await _wait(3)
	_check(n.playing == null and player.state_name != &"puppet" and _flat(n.global_position).distance_to(start) < 0.1, "the talk ends there, the NPC stays, the player is free")
	_check(n.choose(NpcInteraction.Trigger.KEY) == t, "the once talk isn't spent")
	# clear of the way: walks, finishes, the once talk is spent
	player.teleport(n.global_position + Vector3(0, 0, 1.5))
	await _wait(5)
	await _press(&"interact")
	await _wait(3)
	await _press(&"interact")
	_check(await _wait_until(func() -> bool: return n.line == "Done", 300), "clear: walks and goes on")
	await _press(&"interact")
	await _wait(3)
	_check(n.choose(NpcInteraction.Trigger.KEY) == null, "finished: the once talk is spent")
	# no lines: no check
	var plain := _npc(Vector3(20, 1, 8), [_talk(&"p", [_say(["Hi"]), _step(NpcStep.Kind.MOVE, {mark = &"M"})])], {}, "Plain", {"M": Vector3(4, -0.8, 0)})
	await _start_key(plain)
	await _press(&"interact")
	await _wait(3)
	_check(plain.walking() or plain.playing == null, "no lines: walks as before")
	await _wait_until(func() -> bool: return plain.playing == null, 400)
	# lines but a missing mark: warns and skips, no complaint
	var lost := _npc(Vector3(-20, 1, 8), [_talk(&"l", [_step(NpcStep.Kind.MOVE, {mark = &"Nope", lines = PackedStringArray(["Hey"])}), _say(["After"])])], {}, "Lost")
	await _start_key(lost)
	_check(lost.line == "After", "a missing mark is skipped, no complaint")
	await _press(&"interact")
	await _wait(3)
	# a routine that complains restarts its loop, one complaint per say_time; a talk cuts it mid-complaint
	var chore := _talk(&"c", [_step(NpcStep.Kind.MOVE, {mark = &"M", lines = PackedStringArray(["Excuse me!"])}), _step(NpcStep.Kind.WAIT, {time = 0.2})], {trigger = NpcInteraction.Trigger.ROUTINE})
	var busy := _npc(Vector3(0, 1, -8), [chore, _talk(&"k", [_say(["Yes?"])])], {}, "Busy", {"M": Vector3(4, -0.8, 0)})
	player.teleport(busy.global_position + Vector3(1.5, 0, 0))
	var says := 0
	var was := ""
	for k in 180: # 3 s: "Excuse me!" shows 1.44 s each time
		await physics_frame
		if busy.line == "Excuse me!" and was != "Excuse me!":
			says += 1
		was = busy.line
	_check(says >= 2 and says <= 3 and busy.playing == chore, "a routine complains, then starts over (%d complaints in 3 s)" % says)
	await _press(&"interact")
	await _wait(3)
	_check(busy.line == "Yes?", "a talk cuts the routine mid-complaint")
	await _press(&"interact")
	await _wait(5)
	_check(busy.playing == chore and busy.step_at == 0, "after the talk the routine is back at its walk")
	sections += 1
```

Add `_test_room` to the `all` list before `_test_demo`; `SECTIONS := 19`.

- [ ] **Step 2: Run it to verify it fails**

Run: `TAIL=30 bash $JOB/tmp/gd.sh 300 -s res://tests/npc_test.gd -- room`
Expected: FAIL (parse error on `room`/`in_way`, or failed checks) — Godot may hang on a script error, the timeout ends it.

- [ ] **Step 3: Implement in `npc/npc_step.gd`**

`FIELDS[Kind.MOVE]` = `["mark", "run", "wait", "lines", "room"]`; `"room"` appended to `ALL`; `lines` doc adds "MOVE: said instead of walking while the player is within `room` of the way (none: no check)"; `@export var room := 1.0` with setter `_named()`, doc "MOVE with lines: metres the player must keep from the way (the line from the NPC to the mark)"; MOVE summary appends `" (room %.1f m)" % room` when `lines` isn't empty (after the run/no-wait suffixes).

- [ ] **Step 4: Implement in `npc/npc.gd`**

- `func in_way(point: Vector3, room: float) -> bool` (next to `taken`): false without a player; else the planar distance from the player to the segment `global_position → point` (all three slid onto the plane of `up_direction`, `Geometry3D.get_closest_point_to_segment`) is `< room`.
- `_say(s: NpcStep, run: int)`: the current SAY body moved verbatim; SAY calls `await _say(s, run)`.
- MOVE, after the missing-mark check:

```gdscript
			if not s.lines.is_empty() and in_way(marks[s.mark], s.room): # not with the player there: say so, stop here
				await _say(s, run)
				if run != _run:
					return
				var plays: Dictionary = memory().plays
				plays[key_of(playing)] = maxi(plays.get(key_of(playing), 0) - 1, 0) # not counted: tried again next time
				_run += 1
				_end()
				return
```

- [ ] **Step 5: Run it to verify it passes**

Run: `TAIL=30 bash $JOB/tmp/gd.sh 300 -s res://tests/npc_test.gd -- room`
Expected: `NPCS: OK`, exit 0. Then `bash $JOB/tmp/gd.sh 150 --editor --quit-after 400` shows no script errors.

- [ ] **Step 6: Commit**

```bash
git add npc/npc_step.gd npc/npc.gd tests/npc_test.gd
git commit -m "feat(npc): a walk with lines needs room, else the NPC complains and stays"
```

### Task 2: Doorman, docs

**Files:**
- Modify: `demo/npcs/npcs.tscn` (text edit, no regeneration: `Resource_1hhkr` gets `lines`, `room = 1.2`, resource_name `move → Aside (room 1.2 m)`; the Performer bay label's Doorman line adds `stand in his way and he grumbles`)
- Modify: `$JOB/tmp/gen_npc_demo.gd` (throwaway generator kept in sync: `_move` takes optional `lines`/`room`, the Doorman's step and label)
- Modify: `tests/npc_test.gd` (`_test_demo`, before `_talk_through(by_name.Doorman)`)
- Modify: `docs/npcs.md` (MOVE row of the step table; one sentence after the walking paragraph; demo item 3), `CLAUDE.md` (NPC paragraph, one clause)

**Interfaces:**
- Consumes: Task 1's `NpcStep.room`, MOVE `lines`, `Npc.walking()`.

- [ ] **Step 1: Write the failing test** in `_test_demo`, before `var aside := ...`:

```gdscript
	var door: Node3D = by_name.Doorman
	var home := _flat(door.global_position)
	for off in [Vector3(0.6, 0, 1.2), Vector3(1.2, 0, 1.0)]: # in front, right of centre: he'd wedge on the wall end
		player.teleport(door.global_position + off)
		await _wait(5)
		await _press(&"interact")
		for k in 4:
			await _wait(8)
			if door.line == "You're in my way. Step back a bit.":
				break
			await _press(&"interact")
		_check(door.line == "You're in my way. Step back a bit." and not door.walking(), "demo: the Doorman grumbles when the player is in his way (%s)" % off)
		await _press(&"interact")
		await _wait(5)
		_check(door.playing == null and _flat(door.global_position).distance_to(home) < 0.2, "demo: ...and stays in the gap")
```

The existing `_talk_through(by_name.Doorman)` (player at +1.5 z, 1.29 m from his way) still steps him aside.

- [ ] **Step 2: Run it to verify it fails**

Run: `TAIL=30 bash $JOB/tmp/gd.sh 300 -s res://tests/npc_test.gd -- demo`
Expected: FAIL on "demo: the Doorman grumbles..." (he walks).

- [ ] **Step 3: Edit the scene, generator and docs** as listed under Files. Docs MOVE row: fields `` `mark`, `run`, `wait`, `lines`, `room` ``; Does: "walks to the mark; with `lines`, only if the player isn't within `room` of its way: else says one and the interaction ends there, uncounted (a `once` talk plays again)". Sentence after the walking paragraph: "To have an NPC refuse instead of squeezing past (the Doorman in his doorway), give the walk `lines` and a `room`." CLAUDE.md: after "the timeout snap never lands on the player." add "A MOVE with `lines` first checks the player isn't within `room` of its way, else says one and ends the interaction uncounted."

- [ ] **Step 4: Run it to verify it passes**

Run: `TAIL=30 bash $JOB/tmp/gd.sh 300 -s res://tests/npc_test.gd -- demo`
Expected: `NPCS: OK`. Then the full NPC suite (all 19 sections) and `--quit-after 300 res://demo/npcs/npcs.tscn` with no errors.

- [ ] **Step 5: Commit**

```bash
git add demo/npcs/npcs.tscn tests/npc_test.gd docs/npcs.md CLAUDE.md
git commit -m "feat(demo): the Doorman needs room to step aside; docs"
```
