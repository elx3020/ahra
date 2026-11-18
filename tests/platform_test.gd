extends SceneTree
## Headless test of moving platforms (demo/platforms/platforms_a.tscn + _b).
## (no MovingPlatform/PlatformSwitch static types here: -s scripts compile before the World autoload exists)
## Run: Godot_console.exe --headless --path . -s res://tests/platform_test.gd

const A := "res://demo/platforms/platforms_a.tscn"

var fails := 0
var world: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	world = root.get_node("World")
	var area: Node = load(A).instantiate()
	root.add_child(area)
	current_scene = area
	await _wait(2)
	var p: Player = area.get_node("Player")

	# --- timeline math ---
	var pp: Node3D = area.get_node("Bays/PingPong/Path/Platform") # 7 m, 2.5 m/s, wait 1 => leg 3.8 s
	_check(is_zero_approx(pp.distance(0.9)) and is_equal_approx(pp.distance(2.4), 3.5) and is_equal_approx(pp.distance(3.8), 7.0)
		and is_equal_approx(pp.distance(6.2), 3.5) and is_zero_approx(pp.distance(7.6)), "ping-pong: wait, go, wait, come back")
	var loop: Array = area.get_node("Bays/Loop/Path").get_children() # 26 m lap, 3 platforms
	await _at_time(p, 98765.4321)
	var d := loop.map(func(pl): return pl.distance(pl.motion_time()))
	_check(is_equal_approx(fposmod(d[1] - d[0], 26.0), 26.0 / 3.0) and is_equal_approx(fposmod(d[2] - d[1], 26.0), 26.0 / 3.0), "loop group still a third of a lap apart after a day of world time")

	# --- riding: carry, jump keeps momentum ---
	await _at_time(p, 7.6 * 1000.0) # ping-pong platform waiting at its start
	await _place(p, pp.global_position + Vector3(0, 1, 0))
	await _wait(90)
	_check(p.is_on_floor() and absf(p.global_position.x - pp.global_position.x) < 0.3 and pp.position.x > -3.0, "standing on a moving platform carries the player")
	Input.action_press(&"jump")
	await _wait(3)
	_check(p.state_name == &"jump" and absf(p.velocity.x - 2.5) < 0.3, "jumping off keeps the platform's speed")
	await _wait(20)
	Input.action_release(&"jump")
	for i in 90:
		await _wait(1)
		if p.is_on_floor():
			break
	_check(p.is_on_floor() and absf(p.global_position.x - pp.global_position.x) < 1.4 and p.global_position.y > 0.0, "straight-up jump lands back on the moving platform")

	var el: Node3D = area.get_node("Bays/Elevator/Path/Platform") # 6 m up, 2 m/s, wait 1.5 => 9 s round trip
	await _at_time(p, 9.0 * 1000.0)
	await _place(p, el.global_position + Vector3(0, 1, 0))
	await _wait(10)
	var airborne := 0
	var top := 0.0
	for i in 520:
		await _wait(1)
		airborne += 0 if p.is_on_floor() else 1
		top = maxf(top, p.global_position.y)
	_check(airborne == 0 and top > 6.5 and p.global_position.y < 1.5, "elevator up and down without losing the floor (airborne frames: %d)" % airborne)

	# --- surface class: the EnvZone rides along ---
	var ice: Node3D = area.get_node("Bays/Surfaces/IcePath/Platform")
	await _at_time(p, 9.0 * 2000.0 + 1.0) # 7 m at 2 m/s, wait 1: just starting to move
	await _place(p, ice.global_position + Vector3(0, 1, 0))
	await _wait(60)
	_check(p.mult(&"traction") < 0.5 and ice.position.x > -2.5, "ice platform: its zone moves with it and applies while riding")
	await _place(p, area.get_node("Bays/Surfaces/Start").global_position)
	await _wait(5)
	_check(is_equal_approx(p.mult(&"traction"), 1.0), "off the ice platform = normal traction")

	# --- activation ---
	var timed: Node3D = area.get_node("Bays/Timed/BackPath/Platform") # on 3 s / off 2 s
	await _at_time(p, 5.0 * 3000.0 + 3.2) # inside an off window
	var x0 := timed.position.x
	await _wait(60)
	var x1 := timed.position.x
	await _wait(60)
	_check(is_equal_approx(x0, x1) and not is_equal_approx(x1, timed.position.x), "timed: stopped in the off window, moving again after")

	var bridge: Node3D = area.get_node("Bays/Switch/Path1/Platform")
	var sw: Node = area.get_node("Bays/Switch/Switch")
	var y0 := bridge.position.y
	await _wait(30)
	_check(is_equal_approx(y0, bridge.position.y) and is_zero_approx(world.active_time(&"bridge")), "switch platform waits until switched on")
	sw.interact(p)
	await _wait(120)
	var y1 := bridge.position.y
	_check(world.is_on(&"bridge") and y1 > y0 + 1.0, "switch on: the bridge wave rises")
	sw.interact(p)
	await _wait(1)
	y1 = bridge.position.y
	await _wait(60)
	_check(not world.is_on(&"bridge") and is_equal_approx(y1, bridge.position.y), "switch off: frozen in place")
	var wave := (area.get_node("Bays/Switch").find_children("Platform", "MovingPlatform", true) as Array).map(func(pl): return pl.motion_time())
	_check(is_equal_approx(wave[1] - wave[0], 0.5) and is_equal_approx(wave[2] - wave[1], 0.5), "switch group keeps its offsets through on/off")

	var rush: Node3D = area.get_node("Bays/TimedSwitch/Path/Platform")
	area.get_node("Bays/TimedSwitch/Switch").interact(p)
	await _wait(60)
	_check(world.is_on(&"rush") and rush.position.x > -3.5, "timed switch: running")
	world.time += 6.0
	await _wait(1)
	x0 = rush.position.x
	await _wait(30)
	_check(not world.is_on(&"rush") and is_equal_approx(world.active_time(&"rush"), 6.0) and is_equal_approx(x0, rush.position.x), "timed switch: stops after 6 s of running")

	# --- gravity: ceiling and wall platforms carry the player ---
	var ceil: Node3D = area.get_node("Bays/Ceiling/Path/Platform")
	await _at_time(p, 9.0 * 3000.0 + 1.5) # 9 s round trip: moving right
	await _place(p, ceil.global_position - Vector3(0, 1.2, 0))
	p.set_gravity_dir(Vector3.UP)
	await _wait(20)
	var cx := ceil.global_position.x
	var px := p.global_position.x
	await _wait(30)
	_check(p.is_on_floor() and p.up_direction == Vector3.DOWN and absf((p.global_position.x - px) - (ceil.global_position.x - cx)) < 0.15 and ceil.global_position.x - cx > 0.5, "ceiling platform carries the player (gravity +y)")

	var wall: Node3D = area.get_node("Bays/Wall/Path/Platform")
	await _at_time(p, 9.0 * 4000.0 + 1.5)
	await _place(p, wall.global_position + Vector3(0, 0, 1.2))
	p.set_gravity_dir(Vector3.FORWARD)
	await _wait(20)
	cx = wall.global_position.x
	px = p.global_position.x
	await _wait(30)
	_check(p.is_on_floor() and p.up_direction == Vector3.BACK and absf((p.global_position.x - px) - (wall.global_position.x - cx)) < 0.15 and wall.global_position.x - cx > 0.5, "wall platform carries the player (gravity -z)")

	# --- scenes: leave, switch a channel elsewhere, come back ---
	var remote: Node3D = area.get_node("Bays/Remote/Path/Platform")
	var start := remote.position
	await _place(p, area.get_node("Bays/Remote/DoorToB").global_position)
	await _wait(10)
	_check(current_scene.name == &"PlatformsB" and current_scene.get_node("Player").global_position.distance_to(current_scene.get_node("FromA").global_position) < 1.5, "door loads area B at its spawn marker")
	current_scene.get_node("Switch").interact(current_scene.get_node("Player"))
	var on_at: float = world.time
	await _wait(150)
	var pb: Player = current_scene.get_node("Player")
	await _place(pb, current_scene.get_node("DoorToA").global_position)
	await _wait(10)
	area = current_scene
	remote = area.get_node("Bays/Remote/Path/Platform")
	p = area.get_node("Player")
	_check(area.name == &"PlatformsA" and p.global_position.distance_to(area.get_node("Bays/Remote/FromB").global_position) < 1.5, "door back to area A at the remote bay")
	_check(absf(world.active_time(&"remote") - (world.time - on_at)) < 0.05 and not remote.position.is_equal_approx(start), "remote platform kept moving while the player was in area B")
	var before := remote.position
	await _wait(30)
	_check(not remote.position.is_equal_approx(before), "and it is still moving")

	print("PLATFORMS: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


## Jumps the world clock with the player parked on solid ground: a platform teleported
## under the player would hand its one-step jump to the player as platform motion.
func _at_time(p: Player, t: float) -> void:
	await _place(p, Vector3(-7.5, 1, 4))
	world.time = t
	await _wait(1)


func _place(p: Player, pos: Vector3) -> void:
	p.respawn(pos)
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
