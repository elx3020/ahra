extends SceneTree
## Headless suite for NPCs (npc/), World's story flags, NPC memory and fade, and the player's
## interactable pick. Run: Godot_console.exe --headless --path . -s res://tests/npc_test.gd
## Optional filter: `-- key leave` runs only those sections.
## No Npc / NpcTalk static types here: they reference the World autoload, which -s scripts
## compile before (see CLAUDE.md). NPC scenes are load()ed at runtime.

const SECTIONS := 2
const PLAYER := preload("res://player/player.tscn")

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
	var all: Array[Callable] = [_test_world, _test_overlap]
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
