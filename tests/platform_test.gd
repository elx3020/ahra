extends SceneTree
## Headless test of moving platforms (demo/platforms/platforms_a.tscn + _b): tracks, circuits,
## sequences, switches, riding.
## (no MovingPlatform/PlatformSwitch/PlatformProgram static types here: -s scripts compile before the World autoload exists)
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
	var ppt: Node3D = area.get_node("Bays/PingPong/Track") # round trips of 7 m at 2.5 m/s forever, 1 s waits: [1][2.8][1][2.8]
	var pp: Node3D = ppt.platform()
	_check(_x(ppt, 0.5, -3.5) and _x(ppt, 2.4, 0.0) and _x(ppt, 4.3, 3.5) and _x(ppt, 6.2, 0.0) and _x(ppt, 7.6, -3.5), "ping-pong: wait, out, wait, back, forever")
	var seqt: Node3D = area.get_node("Bays/Sequences/Track") # 30 m square: 2 laps at 6 m/s, then 2 at 2 m/s; 1 s start waits, 3 s end waits on the slow laps
	var seq: Node3D = seqt.platform()
	var far := Vector3(143.5, -0.25, 4) # half a lap from the start
	var fast: float = seqt.point_at(3.6).distance_to(seqt.point_at(3.5))
	var slow: float = seqt.point_at(20.6).distance_to(seqt.point_at(20.5))
	_check(seqt.point_at(3.5).is_equal_approx(far) and seqt.point_at(20.5).is_equal_approx(far) and seqt.point_at(6.5).is_equal_approx(Vector3(136.5, -0.25, -4))
		and is_equal_approx(fast, 0.6) and is_equal_approx(slow, 0.2), "sequences: 2 fast laps, start waits, then 2 slow laps")
	var circ: Node3D = area.get_node("Bays/Circuit/Circuit")
	var dur: float = circ._duration
	var step := 0.0
	var t := 0.0
	while t < 2.0 * dur:
		step = maxf(step, circ.point_at(t + 0.02).distance_to(circ.point_at(t)))
		t += 0.02
	_check(circ._get_configuration_warnings().is_empty() and step < 0.07 and circ.point_at(dur).is_equal_approx(Vector3(156.5, -0.25, -1))
		and circ.point_at(2.0 * dur).is_equal_approx(Vector3(156.5, -0.25, -5)), "circuit: 4 paths joined without a jump, ends on path D, plays back to the start (max step %.3f m)" % step)
	var loopt: Node3D = area.get_node("Bays/Loop/Track") # a full lap forever, 26 m, platforms = 3
	var loop: Array = loopt._riders
	_check(loop.size() == 3 and loop.all(func(r): return r.get_parent() == loopt), "loop: the track runs its platform and 2 copies")
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

	var el: Node3D = area.get_node("Bays/Elevator/Track/Platform") # [1.5][3][1.5][3] = 9 s
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
	var ice: Node3D = area.get_node("Bays/Surfaces/IceTrack/Platform")
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
	var lt: float = loopt.motion_time()
	area.get_node("Bays/Loop/Reverse").interact(p)
	await _wait(60)
	_check(loopt.motion_time() < lt and _spaced(loop), "one switch reverses the whole loop, spacing kept")

	var timed: Array = [area.get_node("Bays/Timed/BackTrack"), area.get_node("Bays/Timed/FrontTrack")] # 4 one-way legs of 1.4 s, 2 s stop after each: 13.6 s
	await _at_time(p, 13.6 * 1000.0 + 1.6) # back one stopped on its middle anchor until 3.4
	x0 = timed[0].platform().position.x
	await _wait(60)
	x1 = timed[0].platform().position.x
	await _wait(60)
	_check(absf(x0) < 0.01 and is_equal_approx(x0, x1) and not is_equal_approx(x1, timed[0].platform().position.x), "timed: stopped on the middle anchor, moving again after")
	var tt: Array = timed.map(func(t): return t.motion_time())
	area.get_node("Bays/Timed/Reverse").interact(p)
	await _wait(300)
	_check(timed[0].motion_time() < tt[0] and timed[1].motion_time() < tt[1], "one switch reverses both timed platforms")

	# --- power, delayed run ---
	var bridge: Node3D = area.get_node("Bays/Switch/Track1/Platform")
	var sw: Node = area.get_node("Bays/Switch/Switch")
	var y0 := bridge.position.y
	await _wait(30)
	_check(is_equal_approx(y0, bridge.position.y) and is_zero_approx(world.drive(&"platforms_a:bridge", false)), "switch platform waits until switched on")
	sw.interact(p)
	await _wait(120)
	var y1 := bridge.position.y
	_check(world.channels[&"platforms_a:bridge"].flip and y1 > y0 + 1.0, "power on: the bridge wave rises")
	sw.interact(p)
	await _wait(1)
	y1 = bridge.position.y
	await _wait(60)
	_check(not world.channels[&"platforms_a:bridge"].flip and is_equal_approx(y1, bridge.position.y), "power off: frozen in place")
	var wave := [1, 2, 3].map(func(i): return area.get_node("Bays/Switch/Track%d" % i).motion_time())
	_check(is_equal_approx(wave[1] - wave[0], 0.5) and is_equal_approx(wave[2] - wave[1], 0.5), "switch group keeps its offsets through on/off")

	var rush: Node3D = area.get_node("Bays/TimedSwitch/Track/Platform")
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
	_check(is_equal_approx(world.drive(&"platforms_a:rush", false), 6.0) and is_equal_approx(x0, rush.position.x), "timed switch: stops after 6 s of running")

	# --- run once (one way, 1 trip, then stop) ---
	var once: Node3D = area.get_node("Bays/RunOnce/Track/Platform")
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

	# --- speed and wait switches ---
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
	area.get_node("Bays/Sequences/StartWaitUp").interact(p)
	await _wait(1)
	_check(is_equal_approx(seqt._plan[0][0], 1.5) and is_equal_approx(seqt._plan[8][0], 3.0), "start wait +: every start wait is 1.5 s, end waits untouched")
	await _skip_to(seqt, 8) # the first slow lap's end wait
	_check(_entry(seqt) == 8, "program reaches its first 3 s end wait")
	area.get_node("Bays/Sequences/EndWaitDown").interact(p)
	var frames := 0
	while frames < 400 and _entry(seqt) == 8:
		await _wait(1)
		frames += 1
	_check(frames > 70 and frames < 110, "end wait -: the 3 s wait becomes 1.5 s (%d frames)" % frames)

	# --- gravity: ceiling and wall platforms carry the player ---
	var ceil: Node3D = area.get_node("Bays/Ceiling/Track/Platform")
	await _at_time(p, 9.0 * 3000.0 + 1.5) # [1][3.5][1][3.5]: moving right
	await _place(p, ceil.global_position - Vector3(0, 1.2, 0))
	p.set_gravity_dir(Vector3.UP)
	await _wait(20)
	var cx := ceil.global_position.x
	var px := p.global_position.x
	await _wait(30)
	_check(p.is_on_floor() and p.up_direction == Vector3.DOWN and absf((p.global_position.x - px) - (ceil.global_position.x - cx)) < 0.15 and ceil.global_position.x - cx > 0.5, "ceiling platform carries the player (gravity +y)")

	var wall: Node3D = area.get_node("Bays/Wall/Track/Platform")
	await _at_time(p, 9.0 * 4000.0 + 1.5)
	await _place(p, wall.global_position + Vector3(0, 0, 1.2))
	p.set_gravity_dir(Vector3.FORWARD)
	await _wait(20)
	cx = wall.global_position.x
	px = p.global_position.x
	await _wait(30)
	_check(p.is_on_floor() and p.up_direction == Vector3.BACK and absf((p.global_position.x - px) - (wall.global_position.x - cx)) < 0.15 and wall.global_position.x - cx > 0.5, "wall platform carries the player (gravity -z)")

	# --- scenes: leave, switch a channel elsewhere, come back ---
	var remote: Node3D = area.get_node("Bays/Remote/Track/Platform")
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
	remote = area.get_node("Bays/Remote/Track/Platform")
	p = area.get_node("Player")
	_check(area.name == &"PlatformsA" and p.global_position.distance_to(area.get_node("Bays/Remote/FromB").global_position) < 1.5, "door back to area A at the remote bay")
	_check(absf(world.drive(&"platforms_a:remote", false) - (world.time - on_at)) < 0.05 and not remote.position.is_equal_approx(start), "remote platform kept moving while the player was in area B")
	before = remote.position
	await _wait(30)
	_check(not remote.position.is_equal_approx(before), "and it is still moving")
	seqt = area.get_node("Bays/Sequences/Track")
	_check(seqt._rates.is_equal_approx(Vector3(1.5, 1.5, 0.5)), "speed/wait changes survive leaving and reloading the area")

	# --- end signals: the relay bay ---
	var lifts: Array = [area.get_node("Bays/Relay/LiftA"), area.get_node("Bays/Relay/LiftB")]
	var lift_y: Array = lifts.map(func(l): return l.platform().position.y)
	await _wait(30)
	_check(is_zero_approx(world.drive(&"platforms_a:relay", false)) and lifts.all(func(l): return l.platform().position.y == lift_y[lifts.find(l)]), "relay: both lifts wait for a signal")
	area.get_node("Bays/Relay/Go").interact(p)
	var go_at: float = world.time
	await _wait(150) # ferry: [0.5 wait][3.5 s across] -> its first sequence ends 4 s after GO
	_check(not world.channels.has(&"platforms_a:relay"), "not before the ferry's first sequence ends")
	await _wait(120)
	_check(world.channels[&"platforms_a:relay"].flip and absf(world.drive(&"platforms_a:relay", false) - (world.time - go_at - 4.0)) < 0.05 and not world.channels.has(&"platforms_a:relay_back"), "the end of its first sequence powers on the relay channel, on time (%.2f s)" % (world.time - go_at - world.drive(&"platforms_a:relay", false)))
	await _wait(90)
	_check(lifts.all(func(l): return absf(l.platform().position.y - lift_y[lifts.find(l)]) > 0.1), "one signal, two tracks: both lifts on its channel move")
	world.time += 30.0 # its second sequence ([4 s][3.5 s back]) ends 11.5 s after GO, during the skip
	await _wait(2)
	_check(absf(world.drive(&"platforms_a:relay_back", false) - (world.time - go_at - 11.5)) < 0.05, "the end of its second sequence signals the shuttle, back-dated across a clock skip")
	_check(world.signals.values() == [1, 1], "each signal sent once (%s)" % world.signals)

	# --- channel scopes ---
	var ch: GDScript = load("res://world/channels.gd")
	var go: Node = area.get_node("Bays/Relay/Go")
	_check(ch.key(go, &"relay_go") == &"platforms_a:relay_go" and ch.key(go, &"world:power") == &"world:power" and ch.relative(go, &"platforms_a:relay_go") == &"relay_go"
		and ch.relative(go, &"puzzles:p4") == &"puzzles:p4", "scopes: a plain name is the area's (platforms_a:...), a key stays as written")
	var pieces := [] # a set piece placed twice: same local names, its own scope each
	for i in 2:
		var piece: Node3D = load("res://world/platform_track_group.gd").new()
		piece.name = "Piece%d" % i
		piece.channel_scope = true
		var lift := _track([Vector3.ZERO, Vector3(4, 0, 0)], [[0, 1, true, 0]])
		lift.channel = &"lift"
		lift.starts_on = false
		lift.add_child(_platform())
		piece.add_child(lift)
		var power: Node = load("res://world/platform_switch.gd").new()
		power.channel = &"lift"
		piece.add_child(power)
		piece.position = Vector3(100 + 10 * i, 100, 180)
		area.add_child(piece)
		pieces.append(piece)
	await _wait(1)
	_check(ch.key(pieces[1].get_child(1), &"lift") == &"platforms_a:Piece1/lift", "a scoped group adds its name: platforms_a:Piece1/lift")
	pieces[0].get_child(1).interact(p)
	await _wait(60)
	_check(world.channels.has(&"platforms_a:Piece0/lift") and not world.channels.has(&"platforms_a:Piece1/lift") and pieces[0].get_child(0).motion_time() > 0.5
		and is_zero_approx(pieces[1].get_child(0).motion_time()), "placed twice: each copy's switch only drives its own lift")

	# --- platform shapes: any shape type; a surface zone wraps each shape ---
	var plat_script: GDScript = load("res://world/moving_platform.gd")
	var slow_ice := EnvProfile.new()
	slow_ice.mods.speed = -0.5
	var disc: Node3D = plat_script.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.0
	cyl.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	disc.add_child(cs)
	disc.surface = slow_ice
	disc.position = Vector3(120, 60, 120) # open air, no program: it stays put
	area.add_child(disc)
	var lump: Node3D = plat_script.new()
	var cs2 := CollisionShape3D.new()
	cs2.shape = BoxMesh.new().create_convex_shape()
	cs2.position = Vector3(0, 1, 0)
	lump.add_child(cs2)
	lump.surface = slow_ice
	lump.position = Vector3(140, 60, 120)
	area.add_child(lump)
	await _place(p, disc.global_position + Vector3(1.2, 1.5, 0))
	await _wait(40)
	_check(p.is_on_floor() and p.global_position.y > 60.25 and is_equal_approx(p.mult(&"speed"), 0.5), "cylinder platform: player stands on its top (y 60.25), its surface applies")
	var wrap: CollisionShape3D = disc.get_children().filter(func(c): return c is EnvZone)[0].shapes()[0]
	_check(wrap.shape is CylinderShape3D and is_equal_approx(wrap.shape.radius, 2.3) and is_equal_approx(wrap.shape.height, 1.1), "surface zone: the cylinder grown 0.3 m all round")
	wrap = lump.get_children().filter(func(c): return c is EnvZone)[0].shapes()[0]
	_check(wrap.shape is BoxShape3D and wrap.shape.size.is_equal_approx(Vector3(1.6, 1.6, 1.6)) and wrap.position.is_equal_approx(Vector3(0, 1, 0)), "surface zone: a convex shape gets its bounding box grown 0.3 m")

	# --- Platform Tools nodes at runtime: references vanish, tracks just run ---
	var ref: Node3D = load("res://world/shape_reference.gd").new()
	area.add_child(ref)
	await _wait(2)
	_check(not is_instance_valid(ref), "a ShapeReference removes itself in game")
	var group: Node3D = load("res://world/platform_track_group.gd").new() # as the Platform Tools build them
	var track := _track([Vector3.ZERO, Vector3(6, 0, 0)], [[0, 1, true, 0]])
	var rider: Node3D = _platform()
	track.add_child(rider)
	group.add_child(track)
	group.position = Vector3(100, 70, 120)
	group.rotation_degrees.y = 90.0 # the track runs along -z
	area.add_child(group)
	await _wait(2)
	var p0 := rider.global_position
	await _wait(60)
	var on_line := func(v: Vector3) -> bool: return absf(v.x - 100) < 0.01 and absf(v.y - 70) < 0.01 and v.z > 113.99 and v.z < 120.01
	_check(on_line.call(p0) and on_line.call(rider.global_position) and p0.distance_to(rider.global_position) > 0.5, "a track inside a rotated group rides its path, turned onto -z (%s -> %s)" % [p0, rider.global_position])

	# --- sequences: chained anchors, 3 ahead then 2 back; trips; one way / round trip ---
	var walk := _track([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 0)], [[0, 3, false, 1], [0, 1, false, 1]])
	walk.after_last = 0 # stop
	walk.add_child(_platform())
	walk.position = Vector3(100, 80, 140)
	area.add_child(walk)
	await _wait(1)
	var q2: Resource = walk.sequences[1]
	# [0.5 wait][3 s: 0 -> 6 m][0.5][0.5][2 s: 6 -> 2 m][0.5] at 2 m/s
	_check(q2.start_anchor == 3 and _px(walk, 0.4) == 0.0 and is_equal_approx(_px(walk, 2.0), 3.0) and is_equal_approx(_px(walk, 3.6), 6.0)
		and is_equal_approx(_px(walk, 5.5), 4.0) and is_equal_approx(_px(walk, 99.0), 2.0), "chained sequences: the second starts where the first left it (anchor 3), goes back to anchor 1, stops")
	var trips := _track([Vector3.ZERO, Vector3(4, 0, 0)], [[0, 1, false, 3]])
	trips.after_last = 0
	trips.add_child(_platform())
	area.add_child(trips)
	await _wait(1)
	var t3: Resource = trips.sequences[0]
	_check(t3.finish_anchor() == 1 and is_equal_approx(_px(trips, 99.0), 4.0) and is_equal_approx(trips._duration, 3 * 2.0 + 2 * (0.5 + 0.5)), "3 one-way trips alternate: out, back, out, ending at the end anchor")
	t3.round_trip = true
	trips._compile()
	_check(t3.finish_anchor() == 0 and is_zero_approx(_px(trips, 99.0)) and is_equal_approx(trips._duration, 3 * (0.5 + 2.0 + 0.5 + 2.0)), "3 round trips: there and back three times, ending at the start")

	# --- multipath: up a branch, back down, on along the main path ---
	var fork := _track([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0)], [[0, 1, false, 1], [0, 1, false, 1], [0, 0, false, 1], [0, 2, false, 1]])
	var branch := Path3D.new()
	branch.curve = Curve3D.new()
	branch.curve.add_point(Vector3(4, 0, 0)) # starts on the main path's anchor 1
	branch.curve.add_point(Vector3(4, 4, 0))
	fork.add_child(branch)
	fork.sequences[1].path = 1 # up the branch
	fork.sequences[2].path = 1 # back down
	fork.after_last = 0 # stop
	fork.add_child(_platform())
	fork.position = Vector3(120, 80, 140)
	area.add_child(fork)
	await _wait(1)
	var fq: Array = fork.sequences
	var at := func(t: float) -> Vector3: return fork.to_local(fork.point_at(t)).snapped(Vector3.ONE * 0.0001)
	# each [0.5 wait][2 s at 2 m/s][0.5]: main 0 -> 1, branch 0 -> 1, branch 1 -> 0, main 1 -> 2
	_check(fq[1].start_anchor == 0 and fq[2].start_anchor == 1 and fq[3].start_anchor == 1 and fork._get_configuration_warnings().is_empty(), "multipath: a sequence on another path starts at its anchor where the platform is (a junction)")
	_check(at.call(1.5) == Vector3(2, 0, 0) and at.call(4.5) == Vector3(4, 2, 0) and at.call(5.8) == Vector3(4, 4, 0) and at.call(7.5) == Vector3(4, 2, 0)
		and at.call(10.5) == Vector3(6, 0, 0) and at.call(99.0) == Vector3(8, 0, 0), "multipath: along the main path, up the branch and down, then on to the end")
	branch.curve.set_point_position(0, Vector3(4, 0, 1))
	_check(not fork._get_configuration_warnings().is_empty(), "a branch that doesn't meet the main path: warning")

	# --- circuit: tracks sharing one platform, played in turn ---
	var circuit: Node3D = load("res://world/platform_track_group.gd").new()
	circuit.circuit = true
	circuit.after_last = 2 # play backwards: the tracks don't close into a loop
	circuit.add_child(_track([Vector3.ZERO, Vector3(4, 0, 0)], [[0, 1, false, 1]]))
	circuit.add_child(_track([Vector3(4, 0, 0), Vector3(4, 0, 4)], [[0, 1, false, 1]]))
	circuit.add_child(_platform())
	circuit.position = Vector3(100, 90, 160)
	area.add_child(circuit)
	await _wait(1)
	var a1: Vector3 = circuit.point_at(1.5) - circuit.global_position # [0.5][2 s along A][0.5] [0.5][2 s along B][0.5]
	var b1: Vector3 = circuit.point_at(4.5) - circuit.global_position
	_check(a1.is_equal_approx(Vector3(2, 0, 0)) and b1.is_equal_approx(Vector3(4, 0, 2)) and not circuit.get_child(0).plays() and circuit._get_configuration_warnings().is_empty(), "circuit: the platform rides track A, then track B")

	print("PLATFORMS: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _x(track: Node3D, t: float, x: float) -> bool:
	return absf(_px(track, t) - x) < 0.001


## The track's platform x (track space) after t program seconds.
func _px(track: Node3D, t: float) -> float:
	return snappedf(track.to_local(track.point_at(t)).x, 0.0001)


## A track along `points` with sequences [start, end, round trip, trips] (speed 2, waits 0.5).
func _track(points: Array, sequences: Array) -> Node3D:
	var track: Node3D = load("res://world/platform_track_instance.gd").new()
	var line := Path3D.new()
	line.curve = Curve3D.new()
	for v: Vector3 in points:
		line.curve.add_point(v)
	track.add_child(line)
	for q: Array in sequences:
		var seq: Resource = load("res://world/platform_sequence.gd").new()
		seq.start_anchor = q[0]
		seq.end_anchor = q[1]
		seq.round_trip = q[2]
		seq.trips = q[3]
		track.sequences.append(seq)
	return track


func _platform() -> Node3D:
	var rider: Node3D = load("res://world/moving_platform.gd").new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	rider.add_child(cs)
	return rider


## Distance along the platform's (closed) path.
func _offset(pl: Node3D) -> float:
	var path: Path3D = pl.get_parent().path()
	return path.curve.get_closest_offset(path.to_local(pl.global_position))


func _spaced(loop: Array) -> bool:
	var d := loop.map(_offset)
	return absf(fposmod(d[1] - d[0], 26.0) - 26.0 / 3.0) < 0.05 and absf(fposmod(d[2] - d[1], 26.0) - 26.0 / 3.0) < 0.05


## Program entry (wait or lap) the platform is in now.
func _entry(pl: Node3D) -> int:
	return int(pl._locate(pl._fold(pl.motion_time() + pl._shifts[0])[2]).x)


## Jumps the world clock to just after the start of program entry `e` (forward channel).
func _skip_to(pl: Node3D, e: int) -> void:
	var now: float = pl.motion_time() + pl._shifts[0]
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
