extends SceneTree
## Headless suite for switch puzzles (puzzle/): World's switch state, weights, carrying, gravity
## zones on enemies and NPCs, plates, doors, energy switches, dispensers, weight memory and the
## demo. Run: Godot_console.exe --headless --path . -s res://tests/switch_test.gd
## Optional filter: `-- plate carry` runs only those sections.
## No WeightPlate / EnergySwitch / Door / Dispenser / Npc / GameArea / Channels static types here:
## they reach the World autoload, which -s scripts compile before (see CLAUDE.md). Their scripts
## and scenes are load()ed at runtime.

const SECTIONS := 4
const PLAYER := preload("res://player/player.tscn")
const BOX := preload("res://puzzle/box.tscn")
const BALL := preload("res://puzzle/ball.tscn")
const RUNNER := "res://enemy/runner/runner.tscn"
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
	var all: Array[Callable] = [_test_world, _test_weight, _test_carry, _test_gravity]
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
	_check(moved[0] > 0.3 and moved[1] > moved[0] * 2.0, "walking into weights pushes them; the light one goes much farther (%.2f, %.2f)" % moved)
	_course(Vector3(0, 2, 0))
	var under := _weight(Vector3(0, 0.5, 0))
	await _wait(40)
	_check(_flat(under.global_position).length() < 0.05 and player.is_on_floor(), "standing on a weight doesn't push it")
	sections += 1


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
	await _wait(3) # CSG builds its collision a frame later
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
	await _wait(30) # it regenerates until the lift lands, then drains 0.12 a frame
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


## A weight (box by default) at `at`; `w` >= 0 sets its weight before it is ready.
func _weight(at: Vector3, scene: PackedScene = BOX, w := -1.0) -> WeightBody:
	var b: WeightBody = scene.instantiate()
	if w >= 0.0:
		b.weight = w
	b.position = at
	course.add_child(b)
	return b


## A zone of `script` (GravityZone, KillZone...) with one box shape.
func _zone(script: GDScript, at: Vector3, size: Vector3) -> Zone:
	var z: Zone = script.new()
	z.position = at
	course.add_child(z)
	var s := BoxShape3D.new()
	s.size = size
	z.add_shape(s)
	return z


## Puts the player at the origin facing +x with `w` 1 m in front, settled.
func _reset_lift(w: WeightBody) -> void:
	player.teleport(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	w.global_position = Vector3(1, 0.5, 0)
	w.linear_velocity = Vector3.ZERO
	await _wait(20)


## An NPC (loaded at runtime: Npc reaches the World autoload) named `npc_name`, so a re-instance
## with the same name finds the same memory.
func _npc(at: Vector3, npc_name := "") -> Node3D:
	var n: Node3D = load(NPC).instantiate()
	n.name = npc_name if npc_name else "Npc%d" % course.get_child_count()
	n.position = at
	course.add_child(n)
	return n


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
