extends SceneTree
## Headless suite for NPCs (npc/), World's story flags, NPC memory and fade, and the player's
## interactable pick. Run: Godot_console.exe --headless --path . -s res://tests/npc_test.gd
## Optional filter: `-- key leave` runs only those sections.
## No Npc / NpcTalk static types here: they reference the World autoload, which -s scripts
## compile before (see CLAUDE.md). NPC scenes are load()ed at runtime.

const SECTIONS := 4
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
	var all: Array[Callable] = [_test_world, _test_overlap, _test_data, _test_body]
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
		n.get_node("Marks").add_child(mk)
	n.position = at
	course.add_child(n)
	n.owner = course
	return n


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
