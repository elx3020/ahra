extends SceneTree
## Headless suite for NPCs (npc/), World's story flags, NPC memory and fade, and the player's
## interactable pick. Run: Godot_console.exe --headless --path . -s res://tests/npc_test.gd
## Optional filter: `-- key leave` runs only those sections.
## No Npc / NpcTalk static types here: they reference the World autoload, which -s scripts
## compile before (see CLAUDE.md). NPC scenes are load()ed at runtime.

const SECTIONS := 16
const PLAYER := preload("res://player/player.tscn")
const NPC := "res://npc/npc.tscn"

var fails := 0
var sections := 0
var course: Node3D
var player: Player
var world: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the tree isn't running yet during _initialize
	world = root.get_node("World")
	var only := OS.get_cmdline_user_args()
	var all: Array[Callable] = [_test_world, _test_overlap, _test_data, _test_body, _test_key, _test_memory,
		_test_progression, _test_beats, _test_talk_overlap, _test_edges, _test_near, _test_leave, _test_review, _test_minors, _test_avoid, _test_demo]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			await t.call()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
	print("NPCS: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


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
	var b := _interactable(Vector3(2, 1, 0)) # radius 2 spheres overlap between x 0 and 2
	player.teleport(Vector3(0.5, 1, 0))
	await _wait(5)
	_check(player.interactables.size() == 2 and player.interactable == a, "in both zones: the nearer answers")
	player.teleport(Vector3(1.8, 1, 0))
	await _wait(5)
	_check(player.interactable == b, "nearer one changes as the player moves")
	player.teleport(Vector3(3.5, 1, 0)) # out of a, still in b
	await _wait(5)
	_check(player.interactables.size() == 1 and player.interactables[0] == b and player.interactable == b, "leaving one keeps the other")
	b.queue_free()
	await _wait(3)
	_check(player.interactable == null, "freed zone pruned")
	sections += 1


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
	var inter := NpcInteraction.new()
	inter.id = &"ch2"
	inter.needs = PackedStringArray(["ch2"])
	inter.once = true
	inter.steps = [say, s]
	_check(not inter.available({}, 0) and inter.available({"ch2": 1}, 0) and not inter.available({"ch2": 1}, 1), "needs and once")
	_check(inter.resource_name == "ch2 · key · once · needs ch2 · 2 steps", "interaction summary")
	_check(not _editor_fields(inter).has("distance"), "KEY hides distance")
	sections += 1


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
	_check(n.line != "Hi" and n.line != "", "re-instanced NPC remembers")
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
	_check(player.interactable == b.talk_zone and b.prompt.visible and not a.prompt.visible, "NPC with nothing to say is passed over")
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
	var bad: Node3D = load(NPC).instantiate()
	bad.interactions.assign([_talk(&"", []), _talk(&"d", [_step(NpcStep.Kind.LEAVE), _say(["late"])]), _talk(&"d", [_step(NpcStep.Kind.MOVE, {mark = &"Nowhere"}), _say([])])])
	var w: String = " ".join(bad._get_configuration_warnings())
	_check(["empty id", "duplicate id", "after leave", "mark", "no lines", "no steps"].all(func(k: String) -> bool: return w.contains(k)), "config warnings: " + w)
	var good: Node3D = load(NPC).instantiate()
	good.interactions.assign([_talk(&"ok", [_say(["Fine"])])])
	_check(good._get_configuration_warnings().is_empty(), "no warnings when all is well")
	bad.free()
	good.free()
	sections += 1


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
	await _wait(5) # the bark fires on approach
	_check(n.playing == bark, "barking when the player reaches the talk zone")
	await _press(&"interact")
	await _wait(3)
	_check(n.line == "Talk" and player.state_name == &"puppet", "interact during a bark starts the key talk")
	await _press(&"interact")
	await _wait(3)
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
	_check(darkest > 0.99 and is_zero_approx(world.fade_rect.color.a) and locked_at_black, "fades to black and back, player held meanwhile (darkest %.2f, end %.2f, held %s)" % [darkest, world.fade_rect.color.a, locked_at_black])
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

	# an unlocked leave (a bark) still holds the player through the fade
	var shy := _npc(Vector3(0, 1, 8), [_talk(&"shy", [_step(NpcStep.Kind.LEAVE, {fade = 0.1})], {trigger = NpcInteraction.Trigger.NEAR, locks_player = false})], {}, "Shy")
	await _wait(5)
	player.teleport(Vector3(2, 1, 8))
	var held := false
	for k in 20:
		await physics_frame
		held = held or player.state_name == &"puppet"
	await _wait(10)
	_check(held and not shy.present and player.state_name != &"puppet", "bark leave: player held during the fade, then released")
	sections += 1


## Regression tests for the final review's findings.
func _test_review() -> void:
	world.reset_story()
	_course()
	# 1: a leave cut short (its NPC freed, or removed, mid-fade) never leaves the screen black
	var cut := _npc(Vector3(-30, 1, 0), [_talk(&"bye", [_step(NpcStep.Kind.LEAVE, {fade = 0.3})])], {}, "Cut")
	await _wait(5)
	await _start_key(cut)
	await _wait(5)
	_check(world.fade_rect.color.a > 0.0, "leave fading")
	cut.queue_free()
	await _wait(40)
	_check(is_zero_approx(world.fade_rect.color.a) and player.state_name != &"puppet", "NPC freed mid-fade: screen back, player free")
	var gone := _npc(Vector3(-25, 1, 0), [_talk(&"bye", [_step(NpcStep.Kind.LEAVE, {fade = 0.3})])], {}, "Removed")
	await _wait(5)
	await _start_key(gone)
	await _wait(5)
	course.remove_child(gone)
	await _wait(40)
	_check(is_zero_approx(world.fade_rect.color.a) and player.state_name != &"puppet", "NPC removed mid-fade: screen back, player free")
	gone.free()

	# 2: an NPC that turns absent during its own talk lets the player go
	world.set_flag(&"here")
	var tmp := _npc(Vector3(-20, 1, 0), [_talk(&"t", [_say(["A"]), _say(["B"])])], {appears_if = PackedStringArray(["here"])}, "Tmp")
	await _wait(5)
	await _start_key(tmp)
	_check(player.state_name == &"puppet" and tmp.line == "A", "talking to an appears_if NPC")
	world.set_flag(&"here", 0)
	await _wait(3)
	_check(player.state_name != &"puppet" and tmp.playing == null, "it turns absent mid-talk: talk cut, player released")

	# 3: an absent NPC never fires a near interaction, not even on its first physics frame
	player.teleport(Vector3(21, 1, 0))
	await _wait(5)
	var hidden := _npc(Vector3(20, 1, 0), [_talk(&"b", [_say(["Boo"], {time = 0.2})], {trigger = NpcInteraction.Trigger.NEAR, locks_player = false, once = true})], {appears_if = PackedStringArray(["never_set"])}, "Hidden")
	await _wait(10)
	_check(world.npcs.get(hidden.memory_id(), {}).get("plays", {}).get("b", 0) == 0 and hidden.playing == null, "absent NPC: its once bark isn't used up")

	# 4: the press that closes a talk doesn't reach a neighbouring zone, whatever the node order
	var zone := _interactable(Vector3(3.2, 1, 6)) # the player at (1.5, 1, 6) is in it, nearer the NPC
	var used := [0]
	zone.used.connect(func(_p: Player) -> void: used[0] += 1)
	var first := _npc(Vector3(0, 1, 6), [_talk(&"t", [_say(["Only"])])], {}, "First")
	course.move_child(first, 0) # processes before the player
	await _wait(5)
	await _start_key(first)
	_check(first.line == "Only", "talking to the nearer NPC")
	await _press(&"interact")
	await _wait(5)
	_check(first.playing == null and used[0] == 0, "the closing press doesn't use the neighbouring zone")

	# 5: a talk that doesn't walk saves no position (moving the NPC in the editor still works)
	var still := _npc(Vector3(30, 1, 0), [_talk(&"t", [_say(["Hi"])])], {}, "Still")
	await _wait(5)
	await _start_key(still)
	await _press(&"interact")
	await _wait(3)
	_check(still.playing == null and not world.npcs[still.memory_id()].has("pos"), "a talk without walking saves no position")
	sections += 1


## The final review's minor findings.
func _test_minors() -> void:
	world.reset_story()
	_course()
	# the E prompt never shows over a neighbouring NPC while the player is in a talk
	var a := _npc(Vector3(0, 1, 0), [_talk(&"a", [_say(["A"])])], {}, "A")
	var b := _npc(Vector3(2.5, 1, 0), [_talk(&"b", [_say(["B"])])], {}, "B")
	await _wait(10)
	player.teleport(Vector3(1.0, 1, 0))
	await _wait(5)
	await _press(&"interact")
	await _wait(3)
	_check(a.line == "A" and not b.prompt.visible and player.interactable == null, "in a talk: no prompt on the neighbour, nothing to interact with")
	await _press(&"interact")
	await _wait(3)

	# a zone freed without an exit signal is dropped from the player's list
	var loose := Interactable.new()
	player.interactables.append(loose)
	loose.free()
	await _wait(3)
	_check(player.interactables.all(func(z: Variant) -> bool: return is_instance_valid(z)) and player.interactables.size() == 2, "freed zone pruned from the list")

	# a bark cut by the key talk doesn't carry its face and look into the talk, and reports finished
	var moody_bark := _talk(&"bark", [_step(NpcStep.Kind.FACE, {face = &"angry"}), _step(NpcStep.Kind.LOOK, {look = NpcStep.Look.AHEAD}),
		_say(["Grr"], {time = 3.0})], {trigger = NpcInteraction.Trigger.NEAR, locks_player = false})
	var moody := _npc(Vector3(12, 1, 0), [moody_bark, _talk(&"talk", [_say(["Calm"])])], {}, "Moody")
	var ended := [0]
	moody.finished.connect(func() -> void: ended[0] += 1)
	await _wait(5)
	player.teleport(Vector3(13.5, 1, 0))
	await _wait(5)
	_check(moody.playing == moody_bark and moody.face == &"angry", "barking angrily")
	await _press(&"interact")
	await _wait(3)
	_check(moody.line == "Calm" and moody.face == &"neutral" and moody.look_target != null and ended[0] == 1, "cut bark: face and look reset, finished reported")
	await _press(&"interact")
	await _wait(3)

	# NPCs spawned from code (no owner) each get their own memory
	var s1: Node3D = load(NPC).instantiate()
	s1.name = "Spawned1"
	course.add_child(s1)
	var s2: Node3D = load(NPC).instantiate()
	s2.name = "Spawned2"
	course.add_child(s2)
	await _wait(2)
	_check(s1.memory_id() != s2.memory_id() and s1.memory_id().ends_with("Spawned1"), "NPCs spawned from code have their own memory (%s, %s)" % [s1.memory_id(), s2.memory_id()])
	sections += 1


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
	w.cue.connect(func(c: StringName) -> void:
		if c == &"blocked":
			blocked[0] += 1)
	w.walk_to(w.marks[&"M"])
	await _wait(int((6.0 / w.walk_speed * 2.0 + 1.0) * Engine.physics_ticks_per_second) + 120)
	var d := _flat(w.global_position).distance_to(_flat(w.marks[&"M"]))
	_check(w.waiting and w.walking() and w.anim == &"wait" and d <= 1.4 and d >= 0.7 and blocked[0] == 1, "waits beside a taken mark past the timeout (%.2f m, %d blocked cues)" % [d, blocked[0]])
	player.teleport(Vector3(-20, 1, 8))
	var got := [false]
	w.arrived.connect(func() -> void: got[0] = true)
	_check(await _wait_until(func() -> bool: return got[0], 120) and not w.waiting and w.anim != &"wait", "arrives once the mark is free")

	# two NPCs swapping places: both arrive
	var p1 := _npc(Vector3(-6, 1, -8), [], {}, "P1", {"G": Vector3(12, -0.8, 0)})
	var p2 := _npc(Vector3(6, 1, -8), [], {}, "P2", {"G": Vector3(-12, -0.8, 0)})
	await _wait(5)
	var both := [0]
	for q: Node3D in [p1, p2]:
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
	_check(by_name.has("MaraDock") and not by_name.MaraDock.present and npcs.filter(func(n: Node) -> bool: return n.present).size() == 6, "only MaraDock absent at the start")
	_check(npcs.all(func(n: Node) -> bool: return n._get_configuration_warnings().is_empty()), "no config warnings")
	_check(npcs.all(func(n: Node) -> bool: return not n.present or n.is_on_floor()), "every present NPC stands on the floor")
	_check(load("res://demo/npcs/blip.tres") is AudioStreamWAV, "blip sound")
	_check(demo.area_id == &"npcs" and demo.help().contains("7 clear"), "area id and debug keys in the help")

	# a short playthrough: the bell changes Smith's lines; the Doorman steps aside for good
	player = demo.get_node("Player")
	await _talk_through(by_name.Ringer)
	_check(world.flag(&"bell_rang") == 1, "demo: the Ringer rings the bell")
	player.teleport(by_name.Smith.global_position + Vector3(0, 0, 1.5))
	await _wait(5)
	await _press(&"interact")
	await _wait(3)
	_check(by_name.Smith.line == "You rang the bell!", "demo: Smith's new line after the bell")
	await _talk_through(by_name.Smith)
	var aside: Vector3 = by_name.Doorman.marks[&"Aside"]
	await _talk_through(by_name.Doorman)
	_check(_flat(by_name.Doorman.global_position).distance_to(_flat(aside)) < 0.4, "demo: the Doorman steps aside")
	root.remove_child(demo)
	demo.free()
	demo = load("res://demo/npcs/npcs.tscn").instantiate()
	root.add_child(demo)
	await _wait(10)
	var doorman: Node3D = demo.get_node("Bays/Performer/Doorman")
	_check(_flat(doorman.global_position).distance_to(_flat(aside)) < 0.4, "demo: still aside after a reload")
	root.remove_child(demo)
	demo.queue_free()
	sections += 1


## Stands in front of `n` (NPCs face +z in the demo) and presses interact until the talk ends.
func _talk_through(n: Node3D) -> void:
	player.teleport(n.global_position + Vector3(0, 0, 1.5))
	await _wait(5)
	await _press(&"interact")
	for k in 40:
		await _wait(8)
		if n.playing == null:
			break
		await _press(&"interact")
	await _wait(3)


# --- course building ---------------------------------------------------------------

func _course(player_at := Vector3(-10, 1, 0)) -> void:
	if course:
		root.remove_child(course) # out of the tree now: the old player leaves its group at once
		course.queue_free()
	course = Node3D.new()
	course.name = "Course"
	root.add_child(course)
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 30))
	player = PLAYER.instantiate()
	player.position = player_at
	course.add_child(player)


func _box(at: Vector3, size: Vector3) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = at
	b.use_collision = true
	course.add_child(b)
	return b


func _interactable(at: Vector3) -> Interactable:
	var z := Interactable.new()
	z.position = at
	course.add_child(z)
	var s := SphereShape3D.new()
	s.radius = 2.0
	z.add_shape(s)
	return z


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
		n.add_child(mk)
	n.position = at
	course.add_child(n)
	n.owner = course
	return n


func _step(kind: NpcStep.Kind, props := {}) -> NpcStep:
	var s := NpcStep.new()
	s.kind = kind
	for k: String in props:
		s.set(k, props[k])
	return s


func _say(lines: Array, props := {}) -> NpcStep:
	var p := props.duplicate()
	p.lines = PackedStringArray(lines)
	return _step(NpcStep.Kind.SAY, p)


func _talk(id: StringName, steps: Array, props := {}) -> NpcInteraction:
	var i := NpcInteraction.new()
	i.id = id
	i.steps.assign(steps)
	for k: String in props:
		i.set(k, props[k])
	return i


## A short sine tone (16-bit mono, 22050 Hz).
func _tone(seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(seconds * rate) * 2)
	for i in int(seconds * rate):
		data.encode_s16(i * 2, int(sin(i * TAU * 440.0 / rate) * 8000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## The player steps into `n`'s Talk zone and presses interact.
func _start_key(n: Node3D) -> void:
	player.teleport(n.global_position + Vector3(1.5, 0, 0))
	await _wait(5)
	await _press(&"interact")
	await _wait(3)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## Names of the properties the inspector shows (after the object's _validate_property).
func _editor_fields(o: Object) -> Array:
	return o.get_property_list().filter(func(p: Dictionary) -> bool: return p.usage & PROPERTY_USAGE_EDITOR).map(func(p: Dictionary) -> String: return p.name)


# --- driving, waiting and checking ---------------------------------------------------

func _press(action: StringName) -> void:
	Input.action_press(action)
	await _wait(2)
	Input.action_release(action)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _wait_until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
