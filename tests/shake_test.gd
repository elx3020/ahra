extends SceneTree
## Headless suite for the camera shake (world/camera_shake.gd and its sources).
## Run: Godot_console.exe --headless --path . -s res://tests/shake_test.gd
## Optional filter: `-- rule camera` runs only those sections.

const SECTIONS := 7
const PLAYER := preload("res://player/player.tscn")
const ENEMY := preload("res://enemy/enemy.tscn")
const BRUTE := preload("res://enemy/brute/brute.tscn")

var fails := 0
var sections := 0
var area: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the tree isn't running yet during _initialize
	var only := OS.get_cmdline_user_args()
	var all: Array[Callable] = [_test_rule, _test_camera, _test_hit, _test_env, _test_steps, _test_slam, _test_demo]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			CameraShake.clear()
			await t.call()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
	print("SHAKE: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _test_rule() -> void:
	var J := CameraShake.Feel.JOLT
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.5), "one shake of 0.5 = 0.5")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.75), "two equal shakes = 1 - (1 - a)^2")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.875), "three = 0.875")
	for i in 20:
		CameraShake.add(J, 0.9 if i == 19 else 0.3)
	CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(CameraShake.layers.size() == CameraShake.MAX_LAYERS and CameraShake.total <= 1.0, "cap: 8 layers, total <= 1")
	_check(CameraShake.layers.any(func(l: Dictionary) -> bool: return is_equal_approx(l.strength, 0.9)), "a full list replaces its weakest")
	CameraShake.clear()
	CameraShake.update(0.0, Vector3.ZERO, 0.0) # focus at the origin
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(100, 0, 0))
	_check(CameraShake.layers.is_empty(), "beyond the radius: no layer")
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(7, 0, 0))
	_check(CameraShake.layers.size() == 1 and is_equal_approx(CameraShake.layers[0].strength, 0.25), "linear falloff: half the 14 m radius = half")
	CameraShake.clear()
	CameraShake.add(J, 1.0)
	var t := 0.0
	while t < 0.31:
		CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
		t += 1.0 / 60.0
	_check(CameraShake.layers.is_empty(), "a JOLT is gone after its 0.3 s")
	# toggles
	var roll_seen := false
	CameraShake.add(J, 1.0)
	for i in 6:
		roll_seen = roll_seen or CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0).z != 0.0
	_check(not roll_seen, "tilt is off by default")
	ProjectSettings.set_setting(CameraShake.TILT, true)
	for i in 6:
		roll_seen = roll_seen or CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0).z != 0.0
	_check(roll_seen, "tilt on: the horizon rolls")
	ProjectSettings.set_setting(CameraShake.SLIDE, false)
	var off := CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	_check(off.x == 0.0 and off.y == 0.0, "slide off: no slide")
	ProjectSettings.set_setting(CameraShake.DISABLE, true)
	_check(CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0) == Vector3.ZERO, "master off: nothing")
	ProjectSettings.set_setting(CameraShake.TILT, false)
	ProjectSettings.set_setting(CameraShake.SLIDE, true)
	ProjectSettings.set_setting(CameraShake.DISABLE, false)
	sections += 1


func _test_camera() -> void:
	var a := _area()
	await _wait(120) # let the follow settle fully
	var p: Player = a.get_node("Player")
	var cam: Camera3D = a.get_node("Camera")
	var rest := cam.global_position
	var iso := Basis.from_euler(Vector3(deg_to_rad(-35.264), deg_to_rad(45.0), 0.0))
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	var moved := false
	for i in 8:
		await process_frame
		moved = moved or absf(cam.h_offset) + absf(cam.v_offset) > 0.0
	_check(moved and cam.global_position.is_equal_approx(rest), "slide lives in the offsets; the camera doesn't drift")
	ProjectSettings.set_setting(CameraShake.DISABLE, true)
	await process_frame
	_check(cam.h_offset == 0.0 and cam.v_offset == 0.0, "master off mid-shake: offsets back to exactly 0")
	ProjectSettings.set_setting(CameraShake.DISABLE, false)
	ProjectSettings.set_setting(CameraShake.TILT, true)
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	var tilted := false
	for i in 8:
		await process_frame
		if not cam.global_basis.is_equal_approx(iso):
			tilted = true
			_check(p.cam_basis().is_equal_approx(iso), "movement reads the steady basis while tilted")
			break
	_check(tilted, "tilt on: the camera rolls")
	ProjectSettings.set_setting(CameraShake.TILT, false)
	await process_frame
	_check(cam.global_basis.is_equal_approx(iso), "tilt off: back to the iso basis")
	var h: float = a.view_height()
	cam.fov *= 2.0
	_check(absf(a.view_height() / h - tan(deg_to_rad(cam.fov) / 2) / tan(deg_to_rad(cam.fov / 4))) < 0.01, "zoom: the view height follows the live fov")
	CameraShake.add(CameraShake.Feel.JOLT, 1.0)
	_area()
	await _wait(2)
	_check(CameraShake.layers.is_empty(), "a new area starts with no shake")
	sections += 1


func _test_hit() -> void:
	var a := _area()
	await _wait(30)
	var p: Player = a.get_node("Player")
	CameraShake.clear()
	p.damage(10.0)
	_check(CameraShake.layers.size() == 1 and CameraShake.layers[0].feel == CameraShake.Feel.JOLT
		and is_equal_approx(CameraShake.layers[0].strength, clampf(0.3 + 10.0 / p.max_hp(), 0.3, 1.0)), "a hit adds a JOLT scaled by damage")
	p.damage(10.0)
	_check(CameraShake.layers.size() == 1, "no new shake during i-frames")
	sections += 1


func _test_env() -> void:
	var s1 := EnvProfile.new()
	s1.shake = 0.5
	var s2 := EnvProfile.new()
	s2.shake = 0.5
	_check(is_equal_approx(EnvProfile.combine(EnvProfile.new(), [s1, s2]).shake, 0.75), "overlapping zones merge by the overlap rule")
	var a := _area()
	await _wait(30)
	var p: Player = a.get_node("Player")
	var storm := EnvProfile.new()
	storm.shake = 0.3
	var z: Node3D = load("res://world/env_zone.gd").new()
	z.profile = storm
	z.position = Vector3(0, 1, 0)
	a.add_child(z)
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 6)
	z.add_shape(box) # after add_child, as enemy_test's _zone does
	await _wait(45)
	_check(is_equal_approx(CameraShake.sustained_level, 0.3), "in a storm zone the sustained level reaches its shake")
	p.teleport(Vector3(12, 1, 0))
	await _wait(40)
	_check(CameraShake.sustained_level == 0.0, "after leaving it eases back to 0 within ~0.5 s")
	sections += 1


func _test_steps() -> void:
	var a := _area()
	await _wait(30)
	var brute: Enemy = BRUTE.instantiate()
	brute.show_debug = false
	brute.position = Vector3(-8, 1, 0)
	a.add_child(brute)
	var steps := [0, 0] # step cues, step cues with a fresh THUMP layer
	brute.cue.connect(func(n: StringName) -> void:
		if n == &"step":
			steps[0] += 1
			if _fresh_thump():
				steps[1] += 1)
	await _wait(10) # settle on the floor
	var start := brute.global_position
	var before: int = steps[0]
	await _wait(150)
	var walked := (brute.global_position - start).slide(Vector3.UP).length()
	_check(steps[0] - before > 0 and absi(steps[0] - before - int(walked / brute.stride)) <= 1,
		"about one step cue per stride walked (%d over %.1f m)" % [steps[0] - before, walked])
	_check(steps[1] == steps[0], "every step near the player adds a THUMP")
	before = steps[0]
	brute.global_position += Vector3(0, 0, 6)
	await _wait(2)
	_check(steps[0] - before <= 1, "a teleport doesn't fire a burst of steps")
	brute.queue_free()
	var light: Enemy = ENEMY.instantiate() # plain enemy: step_shake 0
	light.show_debug = false
	light.position = Vector3(8, 1, 0)
	a.add_child(light)
	var light_steps := [0, 0]
	light.cue.connect(func(n: StringName) -> void:
		if n == &"step":
			light_steps[0] += 1
			if _fresh_thump():
				light_steps[1] += 1)
	await _wait(120)
	_check(light_steps[0] > 0 and light_steps[1] == 0, "step_shake 0: steps but no shake")
	sections += 1


func _fresh_thump() -> bool:
	return CameraShake.layers.any(func(l: Dictionary) -> bool: return l.feel == CameraShake.Feel.THUMP and l.age == 0.0)


func _test_slam() -> void:
	var a := _area()
	await _wait(30)
	# a body moved by hand: fast for 10 frames, then stopped = one slam; a 2 m one-frame jump then still = none
	var pl: Node3D = _platform()
	pl.slam_shake = 0.6
	pl.position = Vector3(5, 3, 0)
	a.add_child(pl)
	var slams := []
	pl.slammed.connect(func(at: Vector3) -> void: slams.append(at))
	await _wait(5)
	for i in 10:
		pl.global_position += Vector3(0, -0.2, 0) # 12 m/s
		await physics_frame
	await _wait(5)
	_check(slams.size() == 1, "a hard stop after fast motion is one slam")
	_check(CameraShake.layers.any(func(l: Dictionary) -> bool: return l.feel == CameraShake.Feel.SLAM), "a slam shakes the camera")
	pl.global_position += Vector3(0, 2, 0)
	await _wait(5)
	_check(slams.size() == 1, "a one-frame jump (clock skip) then still: no slam")
	pl.queue_free()
	# a crusher: fast down 3 m at 12 m/s, 0.5 s wait; up at 2 m/s, 1 s wait; start over (cycle 3.25 s)
	var crusher: Node3D = _track([Vector3(0, 4, 0), Vector3(0, 1, 0)], [[0, 1, false, 1, 12.0, 0.0, 0.5], [1, 0, false, 1, 2.0, 0.0, 1.0]])
	crusher.position = Vector3(-5, 0, -5)
	var body: Node3D = _platform()
	body.slam_shake = 0.6
	crusher.add_child(body)
	a.add_child(crusher)
	var hits := []
	body.slammed.connect(func(at: Vector3) -> void: hits.append([Engine.get_physics_frames(), at]))
	await _wait(500) # over 2.5 cycles: 2 or 3 slams depending on the phase it loads at
	var spaced := hits.size() >= 2
	for i in range(1, hits.size()):
		spaced = spaced and absi(hits[i][0] - hits[i - 1][0] - 195) <= 3 # 3.25 s cycle = 195 frames
	_check(spaced, "a crusher slams once per cycle: never on its slow rise or on load (%d)" % hits.size())
	_check(hits.all(func(h: Array) -> bool: return absf(h[1].y - 1.0) < 0.1), "it slams at the bottom")
	sections += 1


func _test_demo() -> void:
	if area:
		root.remove_child(area)
		area.queue_free()
	area = load("res://demo/shake/shake.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	await _wait(10)
	var brute := area.get_node_or_null(^"Bays/Brute/Brute")
	_check(brute is Enemy and brute.step_shake > 0.0, "demo: a brute with step shake")
	var storm := area.get_node_or_null(^"Bays/Storm/Storm")
	_check(storm != null and storm.profile.shake > 0.0, "demo: a storm zone")
	var hits := [0]
	for c in area.get_node(^"Bays/Crushers").find_children("*", "AnimatableBody3D", true, false):
		if c.has_signal(&"slammed"):
			c.slammed.connect(func(_at: Vector3) -> void: hits[0] += 1)
	await _wait(240)
	_check(hits[0] >= 2, "demo: the crushers slam (%d)" % hits[0])
	sections += 1


# --- building -----------------------------------------------------------------------

## A bare GameArea (floor, Player at (0, 1, 0), Camera, HUD/Label) as the current scene; frees the last one.
func _area() -> Node3D:
	if area:
		root.remove_child(area)
		area.queue_free()
	area = load("res://world/area.gd").new()
	var floor := CSGBox3D.new()
	floor.size = Vector3(40, 1, 40)
	floor.position = Vector3(0, -0.5, 0)
	floor.use_collision = true
	area.add_child(floor)
	var p: Player = PLAYER.instantiate()
	p.name = "Player"
	p.position = Vector3(0, 1, 0)
	area.add_child(p)
	var cam := Camera3D.new()
	cam.name = "Camera"
	area.add_child(cam)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	area.add_child(hud)
	root.add_child(area)
	current_scene = area
	return area


## A track along `points` with sequences [start, end, round_trip, trips, speed, start_wait, end_wait].
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
		seq.speed = q[4]
		seq.start_wait = q[5]
		seq.end_wait = q[6]
		track.sequences.append(seq)
	return track


func _platform() -> Node3D:
	var rider: Node3D = load("res://world/moving_platform.gd").new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	rider.add_child(cs)
	return rider


# --- waiting and checking -----------------------------------------------------------

func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
