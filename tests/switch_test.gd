extends SceneTree
## Headless suite for switch puzzles (puzzle/): World's switch state, weights, carrying, gravity
## zones on enemies and NPCs, plates, doors, energy switches, dispensers, weight memory and the
## demo. Run: Godot_console.exe --headless --path . -s res://tests/switch_test.gd
## Optional filter: `-- plate carry` runs only those sections.
## No WeightPlate / EnergySwitch / Door / Dispenser / Npc / GameArea / Channels static types here:
## they reach the World autoload, which -s scripts compile before (see CLAUDE.md). Their scripts
## and scenes are load()ed at runtime.

const SECTIONS := 1
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
	var all: Array[Callable] = [_test_world]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			await t.call()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
	print("SWITCHES: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


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


# --- building the course -------------------------------------------------------------

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


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


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
