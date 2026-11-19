extends SceneTree
## Headless walkthrough of demo/puzzles/puzzles.tscn: solves each puzzle the intended way
## (mostly real inputs and physics; trivial hops are placements, waits are clock skips).
## (no MovingPlatform/PlatformSwitch static types here: -s scripts compile before the World autoload exists)
## Run: Godot_console.exe --headless --path . -s res://tests/puzzle_test.gd

const SCENE := "res://demo/puzzles/puzzles.tscn"
const RIGHT: Array[StringName] = [&"move_right", &"move_down"] # +x in the iso view (floor and ceiling)

var fails := 0
var world: Node
var area: Node
var p: Player


func _initialize() -> void:
	_run()


func _run() -> void:
	world = root.get_node("World")
	area = load(SCENE).instantiate()
	root.add_child(area)
	current_scene = area
	await _wait(2)
	p = area.get_node("Player")

	# --- 1 lift-off: the always-on lifts and ferry line up regularly ---
	var o := _o(0)
	var lift1: Node3D = _n(0, "LiftTrack1") # the tracks: their program math
	var ferry: Node3D = _n(0, "FerryTrack")
	var lift2: Node3D = _n(0, "LiftTrack2")
	var up_meets := 0
	var across_meets := 0
	for i in 2400: # 2 minutes in 0.05 s steps
		var t := i * 0.05
		var l1: Vector3 = lift1.point_at(t + lift1.offset) - o
		var f: Vector3 = ferry.point_at(t + ferry.offset) - o
		var l2: Vector3 = lift2.point_at(t + lift2.offset) - o
		up_meets += int(l1.y > 3.2 and f.x < 13.0)
		across_meets += int(f.x > 19.0 and l2.y < 3.6)
	_check(up_meets > 20 and across_meets > 20, "1: lift 1 meets the ferry and the ferry meets lift 2, again and again (%d / %d)" % [up_meets, across_meets])
	await _at_time(0, 600.0) # lift 2 waiting low (all three share a 6 s cycle)
	await _place(lift2.platform().global_position + Vector3(0, 1, 0))
	await _wait(200)
	await _hold(RIGHT, 50)
	_check(_reached(1), "1: ride lift 2 up and step onto puzzle 2")

	# --- 2 drawbridges: bridge 2 to the middle, ride bridge 1, reverse bridge 2 from on top ---
	o = _o(1)
	var b1: Node3D = _n(1, "Bridge1Track/Bridge1")
	var b2: Node3D = _n(1, "Bridge2Track/Bridge2")
	_n(1, "Bridge2Power").interact(p)
	await _wait(280)
	_check(absf(b2.global_position.x - o.x - 25.5) < 0.1, "2: bridge 2 power: it comes to the middle and stays")
	await _place(b1.global_position + Vector3(0, 1, 0))
	b1.get_node("Go").interact(p)
	await _wait(270)
	_check(absf(p.global_position.x - o.x - 17.5) < 0.3 and p.is_on_floor(), "2: GO on bridge 1 carries the player out")
	await _place(b2.global_position + Vector3(0, 1, 0)) # the 5 m hop across
	b2.get_node("Back").interact(p)
	await _wait(270)
	await _hold(RIGHT, 60)
	_check(_reached(2), "2: REVERSE on bridge 2 carries the player to puzzle 3")

	# --- 3 dash lanes: a dash-jump lands on lane 1 as it crosses the middle ---
	o = _o(2)
	await _at_time(2, 6.8 * 500.0 + 0.95) # lane 1 reaches the middle ~0.95 s from now
	await _place(o + Vector3(2.0, 1, 0))
	await _wait(2)
	for a in RIGHT + [&"run"]:
		Input.action_press(a)
	await _wait(4)
	Input.action_press(&"dash")
	await _wait(2)
	Input.action_release(&"dash")
	Input.action_press(&"jump")
	for i in 120:
		await _wait(1)
		if i == 14:
			Input.action_release(&"jump")
		if i > 20 and (p.is_on_floor() or p.state_name == &"death"):
			break
	_release_all()
	var lane1: Node3D = _n(2, "Lane1Track/Lane1")
	_check(p.is_on_floor() and absf(p.global_position.x - lane1.global_position.x) < 2.2, "3: dash-jump over 10 m of void onto a passing lane")

	# --- 4 express: too slow at x1, fast enough at x3 ---
	o = _o(3)
	await _warp_key(KEY_4)
	var express: Node3D = _n(3, "FerryTrack/Ferry")
	_n(3, "Run").interact(p)
	await _wait(340)
	_check(express.global_position.y - o.y < 3.5, "4: at x1 the ferry stops far below the exit when RUN ends")
	_n(3, "Reverse").interact(p)
	_n(3, "Run").interact(p)
	await _wait(340)
	_check(absf(express.global_position.x - o.x - 6.5) < 0.1, "4: REVERSE + RUN brings it back to the dock")
	_n(3, "Reverse").interact(p)
	for i in 4:
		_n(3, "SpeedUp").interact(p)
	await _place(express.global_position + Vector3(0, 1, 0))
	_n(3, "Run").interact(p)
	await _wait(340)
	await _hold(RIGHT, 50)
	_check(world.rates(&"puzzles:p4").x == 3.0 and _reached(4), "4: at x3 it reaches the top in time")

	# --- 5 grand circuit: ride all 6 paths and both loops, step off at the top ---
	o = _o(4)
	var circ: Node3D = _n(4, "Circuit") # the circuit group: 6 tracks, one platform
	var dur: float = circ._duration
	var step := 0.0
	var t5 := 0.0
	while t5 < 2.0 * dur:
		step = maxf(step, circ.point_at(t5 + 0.02).distance_to(circ.point_at(t5)))
		t5 += 0.02
	_check(circ._get_configuration_warnings().is_empty() and step < 0.15, "5: 6 paths joined without a jump (max step %.3f m)" % step)
	await _at_time(4, 2.0 * dur * 20.0) # docked, about to leave
	await _place(circ.platform().global_position + Vector3(0, 1, 0))
	var airborne := 0
	for i in roundi((dur - 1.0) * 60.0):
		await _wait(1)
		airborne += 0 if p.is_on_floor() else 1
	await _hold(RIGHT, 50)
	_check(airborne < 5 and _reached(5), "5: rode the whole circuit (airborne frames: %d) and stepped off at the top" % airborne)

	# --- 6 layovers: 2.5 s stops are too slow, no stops make it ---
	o = _o(5)
	var train: Node3D = _n(5, "Circuit") # 6 tracks, one platform: the train
	_check(train.point_at(18.0).y - o.y < 4.1, "6: with 2.5 s stops the train is still low when its 18 s run ends")
	_n(5, "StopsDown").interact(p)
	_n(5, "StopsDown").interact(p)
	await _place(train.platform().global_position + Vector3(0, 1, 0))
	_n(5, "Run").interact(p)
	await _wait(1080)
	await _hold(RIGHT, 50)
	_check(world.rates(&"puzzles:p6").z == 0.0 and _reached(6), "6: no stops: the train reaches the top in 18 s")

	# --- 7 swing ferry: ball A onto the ferry track, ferry to ball B onto the exit ---
	o = _o(6)
	var stand_in := _catch(o + Vector3(26, -0.25, 0), Vector3(4, 0.5, 30)) # the ferry, held in the middle
	await _wait(2)
	await _swing(o + Vector3(3.6, 1, 0), _n(6, "SwingA").global_position, false, 52)
	_check(p.is_on_floor() and absf(p.global_position.x - o.x - 26.0) < 2.0, "7: swing from ball A lands on the ferry's track")
	await _swing(o + Vector3(27.5, 1, 0), _n(6, "SwingB").global_position, false, 48)
	stand_in.queue_free()
	_check(_reached(7), "7: ferry to ball B, swing up onto the exit")

	# --- 8 switch above: RUN on the ceiling, drop back down, ride ---
	o = _o(7)
	await _place(o + Vector3(-2.5, 1, -2.5)) # magenta pad
	await _wait(50)
	_check(p.up_direction == Vector3.DOWN and p.is_on_floor() and p.global_position.y - o.y > 6.5, "8: flip pad: standing on the ceiling")
	p.teleport(o + Vector3(-2.5, 7.1, 2.5))
	await _wait(3)
	_n(7, "Run").interact(p)
	p.teleport(o + Vector3(2.5, 7.1, 2.5)) # white pad
	await _wait(40)
	_check(p.up_direction == Vector3.UP and p.is_on_floor(), "8: white pad drops the player back on the pad")
	var fb: Node3D = _n(7, "FerryTrack/Ferry")
	await _place(fb.global_position + Vector3(0, 1, 0))
	await _wait(780)
	await _hold(RIGHT, 50)
	_check(_reached(8), "8: the ferry left after the 4 s delay with the player on it")

	# --- 9 gravity run: ceiling ferry, fall onto the back wall, wall ferry, drop ---
	o = _o(8)
	await _place(o + Vector3(-2.5, 1, -2.5))
	await _wait(50)
	p.teleport(o + Vector3(5.0, 7.1, 0))
	await _wait(3)
	world.time = 10.0 * 300.0 # ceiling ferry waiting at the ceiling's edge (cycle 1 + 4 + 1 + 4)
	await _wait(1)
	await _hold(RIGHT, 22)
	await _wait(260)
	await _hold(RIGHT, 140)
	await _wait(40)
	_check(p.up_direction == Vector3.BACK and p.is_on_floor(), "9: ceiling ferry across, orange pad: standing on the back wall")
	await _walk_until([&"move_right"], func(): return p.global_position.x - o.x > 44.0)
	world.time = 10.0 * 300.0 # wall ferry waiting at the wall's edge (cycle 1 + 4 + 1 + 4)
	await _wait(1)
	await _hold([&"move_right"], 20)
	await _wait(60)
	await _hold([&"move_right"], 20) # to the ferry's leading edge
	await _wait(220)
	await _walk_until([&"move_right"], func(): return p.up_direction == Vector3.UP)
	await _wait(60)
	_check(_reached(9), "9: wall ferry across, white pad drops the player on puzzle 10")

	# --- 10 clockwork: power the lift, move the ball, dash-jump, swing to the finish ---
	o = _o(9)
	_n(9, "LiftPower").interact(p)
	var lift: Node3D = _n(9, "Circuit/Lift")
	await _place(lift.global_position + Vector3(0, 1, 0))
	for i in 600:
		await _wait(1)
		if p.global_position.y - o.y > 9.85: # paused level with the ledge
			break
	await _hold(RIGHT, 30)
	await _wait(10)
	_check(p.is_on_floor() and p.global_position.x - o.x > 16.0 and p.global_position.y - o.y > 9.5, "10: the powered lift brings the player up to the ledge")
	_n(9, "BallPower").interact(p)
	await _wait(300)
	await _swing(o + Vector3(20, 10, 0), _n(9, "BallTrack/BallCarrier/Ball").global_position, true, 28)
	_check(_reached(10), "10: dash-jump to the moved ball and swing onto the finish")

	# --- checkpoints and teleport keys ---
	p.die(&"fall")
	await _wait(150)
	_check(p.global_position.distance_to(_o(10) + Vector3(0, 1, 0)) < 1.0, "death respawns at the last checkpoint")
	await _warp_key(KEY_3)
	_check(p.global_position.distance_to(_o(2) + Vector3(0, 1, 1.5)) < 1.0 and _reached(2), "key 3 teleports to puzzle 3 (and checkpoints it)")
	await _warp_key(KEY_0)
	_check(p.global_position.distance_to(_o(9) + Vector3(0, 1, 1.5)) < 1.0, "key 0 teleports to puzzle 10")

	print("PUZZLES: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _o(i: int) -> Vector3:
	return area.get_node("Bays").get_child(i).global_position


func _n(i: int, path: String) -> Node:
	return area.get_node("Bays").get_child(i).get_node(path)


func _reached(i: int) -> bool:
	return p.checkpoint.distance_to(_o(i) + Vector3(0, 1, 0)) < 0.1


func _warp_key(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	area._unhandled_input(e)
	await _wait(5)


## Run, (dash-)jump, grab `anchor` once in reach, let go with jump `rel` frames into the swing.
func _swing(start: Vector3, anchor: Vector3, dash: bool, rel: int) -> void:
	await _place(start)
	await _wait(2)
	for a in RIGHT + [&"run"]:
		Input.action_press(a)
	await _wait(8)
	if dash:
		Input.action_press(&"dash")
		await _wait(2)
		Input.action_release(&"dash")
	Input.action_press(&"jump")
	var grabbed := -1
	for i in 400:
		await _wait(1)
		if i == 14:
			Input.action_release(&"jump")
		if grabbed < 0 and p.state_name == &"jump" and p.global_position.distance_to(anchor) < 6.9:
			Input.action_press(&"grab")
			grabbed = 0
		elif grabbed >= 0 and p.state_name == &"swing":
			grabbed += 1
			if grabbed == rel:
				Input.action_press(&"jump")
		elif grabbed > 0:
			Input.action_release(&"grab")
			Input.action_release(&"jump")
			if p.is_on_floor():
				break
		if p.state_name == &"death":
			break
	_release_all()
	await _wait(3)


func _catch(pos: Vector3, size: Vector3) -> Node:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	area.add_child(body)
	return body


## Jumps the world clock with the player parked on puzzle i's pad (never while riding:
## a platform teleported under the player would fling it).
func _at_time(i: int, t: float) -> void:
	await _place(_o(i) + Vector3(0, 1, 1.5))
	world.time = t
	await _wait(1)


func _walk_until(actions: Array, done: Callable, frames := 600) -> void:
	for a in actions:
		Input.action_press(a)
	for i in frames:
		await _wait(1)
		if done.call():
			break
	for a in actions:
		Input.action_release(a)


func _hold(actions: Array, frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	await _wait(frames)
	for a in actions:
		Input.action_release(a)


func _release_all() -> void:
	for a in [&"move_right", &"move_down", &"run", &"jump", &"dash", &"grab"]:
		Input.action_release(a)


func _place(pos: Vector3) -> void:
	p.respawn(pos)
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
