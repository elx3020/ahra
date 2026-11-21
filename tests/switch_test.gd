extends SceneTree
## Headless suite for switch puzzles (puzzle/): World's switch state, weights, carrying, gravity
## zones on enemies and NPCs, plates, doors, energy switches, dispensers, weight memory and the
## demo. Run: Godot_console.exe --headless --path . -s res://tests/switch_test.gd
## Optional filter: `-- plate carry` runs only those sections.
## No WeightPlate / EnergySwitch / Door / Dispenser / Npc / GameArea / Channels static types here:
## they reach the World autoload, which -s scripts compile before (see CLAUDE.md). Their scripts
## and scenes are load()ed at runtime.

const SECTIONS := 10
const PLAYER := preload("res://player/player.tscn")
const BOX := preload("res://puzzle/box.tscn")
const BALL := preload("res://puzzle/ball.tscn")
const RUNNER := "res://enemy/runner/runner.tscn"
const NPC := "res://npc/npc.tscn"
const WARMUP_FRAMES := 3 ## WeightPlate.WARMUP (tests can't type WeightPlate)

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
	var all: Array[Callable] = [_test_world, _test_weight, _test_carry, _test_gravity, _test_plate, _test_door, _test_energy, _test_dispenser, _test_memory, _test_demo]
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
	_check(not orphan._get_configuration_warnings().is_empty(), "a channel no switch uses: warned (a typo would never open)")
	# no lifting through a closed door: the player pressed against it, a box against its far side
	player.teleport(Vector3(0, 1, 4.4)) # first: the push-out left the player where the weight goes
	player.facing = Vector3.BACK
	await _wait(10)
	var past := _weight(Vector3(0, 0.55, 5.75)) # 5 cm clear of the door
	await _wait(30)
	_check(_flat(past.global_position - player.global_position).length() < 1.45, "(the weight is within reach, only the door is between)")
	await _press(&"carry")
	_check(door.amount == 0.0 and player.held == null and past.carrier == null, "a weight behind a closed door can't be lifted through it")
	sections += 1


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


## A weight plate (2 x 0.3 x 2 slab) on channel `ch`; `rot` turns it onto a wall or ceiling.
func _plate(at: Vector3, ch: StringName, latch := false, rot := Vector3.ZERO) -> Area3D:
	var z: Area3D = load("res://puzzle/weight_plate.gd").new()
	z.channel = ch
	z.mode = 1 if latch else 0
	z.position = at
	z.rotation = rot
	course.add_child(z)
	var s := BoxShape3D.new()
	s.size = Vector3(2, 0.3, 2)
	z.add_shape(s)
	return z


## A door (4 x 3 x 0.4) on channel `ch`.
func _door(at: Vector3, ch: StringName) -> AnimatableBody3D:
	var d: AnimatableBody3D = load("res://puzzle/door.gd").new()
	d.channel = ch
	d.position = at
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(4, 3, 0.4)
	cs.shape = s
	d.add_child(cs)
	course.add_child(d)
	return d


## An energy switch (a 0.6 m box) on channel `ch`.
func _energy(at: Vector3, ch: StringName) -> AnimatableBody3D:
	var e: AnimatableBody3D = load("res://puzzle/energy_switch.gd").new()
	e.channel = ch
	e.position = at
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = s
	e.add_child(cs)
	course.add_child(e)
	return e


## A dispenser of boxes on channel `ch`, keeping `n` in play.
func _dispenser(at: Vector3, ch: StringName, n: int) -> Node3D:
	var d: Node3D = load("res://puzzle/dispenser.gd").new()
	d.channel = ch
	d.count = n
	d.position = at
	course.add_child(d)
	return d


## A bare GameArea named `area_name` (Player, Camera, HUD/Label, a floor), not in the tree yet: the
## caller adds its weights and dispensers first. The course goes away.
func _area(area_name: String) -> Node3D:
	if course:
		root.remove_child(course)
		course.queue_free()
		course = null
	var a: Node3D = load("res://world/area.gd").new()
	a.area_id = StringName(area_name)
	var floor := CSGBox3D.new()
	floor.size = Vector3(40, 1, 40)
	floor.position = Vector3(0, -0.5, 0)
	floor.use_collision = true
	a.add_child(floor)
	var p: Player = PLAYER.instantiate()
	p.name = "Player"
	p.position = Vector3(0, 1, 6)
	a.add_child(p)
	var cam := Camera3D.new()
	cam.name = "Camera"
	a.add_child(cam)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	a.add_child(hud)
	return a


func _weight_in(area: Node3D, node_name: String, at: Vector3) -> WeightBody:
	var b: WeightBody = BOX.instantiate()
	b.name = node_name
	b.position = at
	area.add_child(b)
	return b


func _dispenser_in(area: Node3D, at: Vector3, ch: StringName, n: int) -> Node3D:
	var d: Node3D = load("res://puzzle/dispenser.gd").new()
	d.name = "Dispenser"
	d.channel = ch
	d.count = n
	d.position = at
	area.add_child(d)
	return d


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
