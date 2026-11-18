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

	# --- program math ---
	var pp: Node3D = area.get_node("Bays/PingPong/Path/Platform") # 2 laps of 7 m at 2.5 m/s, 1 s lap wait: [1][2.8][1][2.8]
	_check(_x(pp, 0.5, -3.5) and _x(pp, 2.4, 0.0) and _x(pp, 4.3, 3.5) and _x(pp, 6.2, 0.0) and _x(pp, 7.6, -3.5), "ping-pong: wait, out, wait, back (2 laps)")
	var seq: Node3D = area.get_node("Bays/Sequences/Path/Platform") # 30 m circuit: 2 laps at 6 m/s, then 2 at 2 m/s; waits 1 s/lap, 3 s/sequence
	var far := Vector3(143.5, -0.25, 4) # half a lap from the start
	var fast: float = seq.point_at(3.6).distance_to(seq.point_at(3.5))
	var slow: float = seq.point_at(23.6).distance_to(seq.point_at(23.5))
	_check(seq.point_at(3.5).is_equal_approx(far) and seq.point_at(23.5).is_equal_approx(far) and seq.point_at(6.5).is_equal_approx(Vector3(136.5, -0.25, -4))
		and is_equal_approx(fast, 0.6) and is_equal_approx(slow, 0.2), "sequences: 2 fast laps, lap waits, then 2 slow laps")
	var circ: Node3D = area.get_node("Bays/Circuit/Platform")
	var dur: float = circ._duration
	var step := 0.0
	var t := 0.0
	while t < 2.0 * dur:
		step = maxf(step, circ.point_at(t + 0.02).distance_to(circ.point_at(t)))
		t += 0.02
	_check(circ._get_configuration_warnings().is_empty() and step < 0.07 and circ.point_at(dur).is_equal_approx(Vector3(156.5, -0.25, -1))
		and circ.point_at(2.0 * dur).is_equal_approx(Vector3(156.5, -0.25, -5)), "circuit: 4 paths joined without a jump, ends on path D, plays back to the start (max step %.3f m)" % step)
	var loop: Array = area.get_node("Bays/Loop/Path").get_children() # 26 m lap, 3 platforms
	await _at_time(p, 98765.4321)
	_check(_spaced(loop), "loop group still a third of a lap apart after a day of world time")

	# --- riding: carry, jump keeps momentum ---
	await _at_time(p, 7.6 * 1000.0 + 0.5) # ping-pong in its first lap wait, leaves in 0.5 s
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

	var el: Node3D = area.get_node("Bays/Elevator/Path/Platform") # [1.5][3][1.5][3] = 9 s
	await _at_time(p, 9.0 * 1000.0 + 0.5)
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
	await _at_time(p, 9.0 * 2000.0 + 1.0) # [1][3.5][1][3.5]: starting to move
	await _place(p, ice.global_position + Vector3(0, 1, 0))
	await _wait(60)
	_check(p.mult(&"traction") < 0.5 and ice.position.x > -2.5, "ice platform: its zone moves with it and applies while riding")
	await _place(p, area.get_node("Bays/Surfaces/Start").global_position)
	await _wait(5)
	_check(is_equal_approx(p.mult(&"traction"), 1.0), "off the ice platform = normal traction")

	# --- reverse switches ---
	await _at_time(p, 7.6 * 2000.0 + 2.0) # ping-pong 2.5 m out, going right
	var x0 := pp.position.x
	await _wait(10)
	var x1 := pp.position.x
	area.get_node("Bays/PingPong/Reverse").interact(p)
	await _wait(1)
	var x2 := pp.position.x
	await _wait(30)
	_check(x1 > x0 and absf(x2 - x1) < 0.1 and pp.position.x < x2 - 0.5, "reverse: no jump, the platform heads back the way it came")
	var lt: float = loop[0].motion_time()
	area.get_node("Bays/Loop/Reverse").interact(p)
	await _wait(60)
	_check(loop[0].motion_time() < lt and _spaced(loop), "one switch reverses the whole loop group, spacing kept")

	var timed: Array = [area.get_node("Bays/Timed/BackPath/Platform"), area.get_node("Bays/Timed/FrontPath/Platform")] # on 3 s / off 2 s
	await _at_time(p, 5.0 * 3000.0 + 3.2) # back one inside an off window
	x0 = timed[0].position.x
	await _wait(60)
	x1 = timed[0].position.x
	await _wait(60)
	_check(is_equal_approx(x0, x1) and not is_equal_approx(x1, timed[0].position.x), "timed: stopped in the off window, moving again after")
	var tt: Array = timed.map(func(pl): return pl.motion_time())
	area.get_node("Bays/Timed/Reverse").interact(p)
	await _wait(300)
	_check(timed[0].motion_time() < tt[0] and timed[1].motion_time() < tt[1], "one switch reverses both timed platforms")

	# --- power, delayed run ---
	var bridge: Node3D = area.get_node("Bays/Switch/Path1/Platform")
	var sw: Node = area.get_node("Bays/Switch/Switch")
	var y0 := bridge.position.y
	await _wait(30)
	_check(is_equal_approx(y0, bridge.position.y) and is_zero_approx(world.drive(&"bridge", false)), "switch platform waits until switched on")
	sw.interact(p)
	await _wait(120)
	var y1 := bridge.position.y
	_check(world.channels[&"bridge"].flip and y1 > y0 + 1.0, "power on: the bridge wave rises")
	sw.interact(p)
	await _wait(1)
	y1 = bridge.position.y
	await _wait(60)
	_check(not world.channels[&"bridge"].flip and is_equal_approx(y1, bridge.position.y), "power off: frozen in place")
	var wave := (area.get_node("Bays/Switch").find_children("Platform", "MovingPlatform", true) as Array).map(func(pl): return pl.motion_time())
	_check(is_equal_approx(wave[1] - wave[0], 0.5) and is_equal_approx(wave[2] - wave[1], 0.5), "switch group keeps its offsets through on/off")

	var rush: Node3D = area.get_node("Bays/TimedSwitch/Path/Platform")
	x0 = rush.position.x
	area.get_node("Bays/TimedSwitch/Switch").interact(p)
	await _wait(60)
	_check(is_equal_approx(rush.position.x, x0), "timed switch: still waiting out its 1.5 s delay")
	await _wait(60)
	_check(rush.position.x > x0 + 0.5, "timed switch: running after the delay")
	world.time += 6.0
	await _wait(1)
	x0 = rush.position.x
	await _wait(30)
	_check(is_equal_approx(world.drive(&"rush", false), 6.0) and is_equal_approx(x0, rush.position.x), "timed switch: stops after 6 s of running")

	# --- run once (repeat: none) ---
	var once: Node3D = area.get_node("Bays/RunOnce/Path/Platform")
	area.get_node("Bays/RunOnce/Power").interact(p)
	world.time += 100.0
	await _wait(2)
	x0 = once.position.x
	_check(is_equal_approx(x0, 3.5), "run once: crossed once and stays at the end")
	area.get_node("Bays/RunOnce/Reverse").interact(p)
	await _wait(30)
	_check(once.position.x < x0 - 0.5, "run once: reverse brings it back at once (no unwinding of the parked time)")
	world.time += 100.0
	await _wait(2)
	area.get_node("Bays/RunOnce/Reverse").interact(p)
	await _wait(60)
	_check(once.position.x > -3.0, "run once: back at the start, reverse sends it out again at once")

	# --- speed and wait switches (shared waits) ---
	await _at_time(p, 50.0 * 100.0 + 2.0) # first fast lap, 6 m in
	var o0 := _offset(seq)
	await _wait(30)
	var base := fposmod(_offset(seq) - o0, 30.0) # metres per 30 frames at x1
	var before := seq.position
	area.get_node("Bays/Sequences/SpeedUp").interact(p)
	await _wait(1)
	var jump := seq.position.distance_to(before)
	o0 = _offset(seq)
	await _wait(30)
	var ratio := fposmod(_offset(seq) - o0, 30.0) / base
	_check(jump < 0.25 and absf(ratio - 1.5) < 0.05, "speed +: no jump, 1.5x along the path (x%.2f)" % ratio)
	area.get_node("Bays/Sequences/LapWaitUp").interact(p)
	await _wait(1)
	_check(is_equal_approx(seq._plan[0][0], 1.5) and is_equal_approx(seq._plan[4][0], 3.0), "lap wait +: every lap wait is 1.5 s, sequence waits untouched")
	await _skip_to(seq, 4) # the first sequence wait
	_check(_entry(seq) == 4, "program reaches its first sequence wait")
	area.get_node("Bays/Sequences/SequenceWaitDown").interact(p)
	var frames := 0
	while frames < 400 and _entry(seq) == 4:
		await _wait(1)
		frames += 1
	_check(frames > 70 and frames < 110, "sequence wait -: the 3 s wait becomes 1.5 s (%d frames)" % frames)

	# --- gravity: ceiling and wall platforms carry the player ---
	var ceil: Node3D = area.get_node("Bays/Ceiling/Path/Platform")
	await _at_time(p, 9.0 * 3000.0 + 1.5) # [1][3.5][1][3.5]: moving right
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
	_check(absf(world.drive(&"remote", false) - (world.time - on_at)) < 0.05 and not remote.position.is_equal_approx(start), "remote platform kept moving while the player was in area B")
	before = remote.position
	await _wait(30)
	_check(not remote.position.is_equal_approx(before), "and it is still moving")
	seq = area.get_node("Bays/Sequences/Path/Platform")
	_check(seq._rates.is_equal_approx(Vector3(1.5, 1.5, 0.5)), "speed/wait changes survive leaving and reloading the area")

	print("PLATFORMS: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _x(pl: Node3D, t: float, x: float) -> bool:
	return absf(pl.point_at(t).x - pl.get_parent().global_position.x - x) < 0.001


## Distance along the platform's (closed) path.
func _offset(pl: Node3D) -> float:
	var path: Path3D = pl.get_parent()
	return path.curve.get_closest_offset(path.to_local(pl.global_position))


func _spaced(loop: Array) -> bool:
	var d := loop.map(_offset)
	return absf(fposmod(d[1] - d[0], 26.0) - 26.0 / 3.0) < 0.05 and absf(fposmod(d[2] - d[1], 26.0) - 26.0 / 3.0) < 0.05


## Program entry (wait or lap) the platform is in now.
func _entry(pl: Node3D) -> int:
	return int(pl._locate(pl._fold(pl.motion_time() + pl._shift)[2]).x)


## Jumps the world clock to just after the start of program entry `e` (forward channel, no schedule).
func _skip_to(pl: Node3D, e: int) -> void:
	var now: float = pl.motion_time() + pl._shift
	var f: Array = pl._fold(now)
	var target: float = pl._unfold(f[0], false, pl._time_at(Vector2(e, 0)) + 0.05)
	if target < now:
		target += pl._duration
	world.time += target - now
	await _wait(1)


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
