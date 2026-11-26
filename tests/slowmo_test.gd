extends SceneTree
## Headless suite for slow motion (world/slow_mo.gd: hit-stops, slow areas, bullet time).
## Run: Godot_console.exe --headless --path . -s res://tests/slowmo_test.gd
## Optional filter: `-- rules bullet` runs only those sections.

const SECTIONS := 3
const PLAYER := preload("res://player/player.tscn")
const ENEMY := preload("res://enemy/enemy.tscn")

var fails := 0
var sections := 0
var area: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the tree isn't running yet during _initialize
	ProjectSettings.set_setting(SlowMo.DISABLE, false)
	var only := OS.get_cmdline_user_args()
	var all: Array[Callable] = [_test_rules, _test_hits, _test_realtime]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			SlowMo.clear()
			Engine.time_scale = 1.0
			paused = false
			await t.call()
	SlowMo.clear()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
	print("SLOWMO: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


## SlowMo's rules, with explicit deltas. No await between an add and its updates: the World driver
## ages the stop on every real frame.
func _test_rules() -> void:
	var n := SlowMo.stops
	SlowMo.add(SlowMo.Feel.HIT)
	_check(SlowMo.stops == n + 1, "a HIT starts a stop")
	_check(_near(SlowMo.update(0.0, false), 0.12), "a HIT slows the world to 0.12")
	_check(_near(SlowMo.update(0.06, false), 0.12), "it holds 0.12 through its hold")
	var mid := SlowMo.update(0.03, false) # 0.09 s: inside the ramp
	_check(mid > 0.12 and mid < 1.0, "then eases back (%.3f)" % mid)
	SlowMo.update(0.04, false) # 0.13 s: past hold 0.07 + ramp 0.05
	_check(SlowMo.stop.is_empty() and SlowMo.update(0.0, false) == 1.0, "it is over after hold + ramp")

	SlowMo.clear()
	n = SlowMo.stops
	SlowMo.add(SlowMo.Feel.HIT)
	SlowMo.add(SlowMo.Feel.KILL)
	_check(SlowMo.stop.feel == SlowMo.Feel.KILL and SlowMo.stops == n + 1, "a stronger feel in the same frame replaces the stop")
	SlowMo.add(SlowMo.Feel.SHOT)
	_check(SlowMo.stop.feel == SlowMo.Feel.KILL, "a weaker one in the same frame doesn't")

	SlowMo.clear()
	n = SlowMo.stops
	SlowMo.add(SlowMo.Feel.HIT)
	await physics_frame
	SlowMo.add(SlowMo.Feel.KILL)
	_check(SlowMo.stop.feel == SlowMo.Feel.HIT and SlowMo.stops == n + 1, "a later one is dropped while the stop runs")

	SlowMo.clear()
	SlowMo.area = 0.5
	SlowMo.add(SlowMo.Feel.HIT)
	_check(_near(SlowMo.update(0.0, false), 0.06), "a stop in a 0.5 area multiplies: 0.06")
	_check(_near(SlowMo.update(0.13, false), 0.5) and SlowMo.stop.is_empty(), "and lasts the same real time")

	SlowMo.clear()
	SlowMo.area = 0.05
	SlowMo.bullet_target = 0.3
	SlowMo.update(0.5, false)
	SlowMo.add(SlowMo.Feel.KILL)
	_check(SlowMo.update(0.0, false) == SlowMo.MIN_SCALE, "the product never goes under MIN_SCALE")

	SlowMo.clear()
	SlowMo.bullet_target = 0.3
	var half := SlowMo.update(0.05, false)
	_check(half > 0.3 and half < 1.0, "bullet time eases in (%.3f after 0.05 s)" % half)
	SlowMo.update(0.1, false)
	_check(_near(SlowMo.update(0.1, false), 0.3) and _near(SlowMo.bullet, 0.3), "and settles at its target within ~0.15 s")

	SlowMo.clear()
	ProjectSettings.set_setting(SlowMo.DISABLE, true)
	n = SlowMo.stops
	SlowMo.add(SlowMo.Feel.HIT)
	SlowMo.area = 0.5
	_check(SlowMo.stops == n and _near(SlowMo.update(0.0, false), 0.5), "the toggle stops hit-stops, not areas")
	ProjectSettings.set_setting(SlowMo.DISABLE, false)

	SlowMo.clear()
	SlowMo.add(SlowMo.Feel.HIT)
	var age: float = SlowMo.stop.age
	_check(SlowMo.update(0.05, true) == 1.0 and SlowMo.bullet == 1.0 and SlowMo.stop.age == age, "paused: scale 1, the stop doesn't age")
	_check(_near(SlowMo.update(0.0, false), 0.12), "unpaused: the stop carries on")
	SlowMo.clear()
	SlowMo.bullet_target = 0.3
	SlowMo.update(0.5, false)
	SlowMo.update(0.05, true)
	_check(SlowMo.bullet == 1.0, "paused: no bullet factor in the scale")
	SlowMo.update(0.0, false)
	_check(_near(SlowMo.bullet, 0.3), "unpaused: bullet time is back at once, no re-ease")

	SlowMo.add(SlowMo.Feel.HIT)
	SlowMo.area = 0.5
	SlowMo.clear()
	_check(SlowMo.stop.is_empty() and SlowMo.area == 1.0 and SlowMo.bullet_target == 1.0 and SlowMo.bullet == 1.0, "clear resets everything")

	# the World driver
	SlowMo.add(SlowMo.Feel.HIT)
	await process_frame
	await process_frame
	_check(absf(Engine.time_scale - 0.12) < 0.01, "World applies the scale (%.3f)" % Engine.time_scale)
	_check(root.get_node("World").debug_text().contains("time ×"), "World's debug text shows the scale")
	paused = true
	age = SlowMo.stop.age
	for i in 3:
		await process_frame
	_check(Engine.time_scale == 1.0 and SlowMo.stop.age == age, "paused tree: scale 1 and the stop frozen")
	paused = false
	await process_frame
	await process_frame
	_check(Engine.time_scale < 1.0, "unpaused tree: the stop resumes")
	await _until_full_speed()
	_check(Engine.time_scale == 1.0, "and ends")
	sections += 1


## The hooks: player hurt, melee swings, player shots.
func _test_hits() -> void:
	var a := _area()
	await _wait(30)
	var p: Player = a.get_node("Player")
	var side := p.facing.cross(p.up_direction)
	var front := p.global_position + p.facing * p.melee_reach
	var e1 := _enemy(front + side * 0.3)
	var e2 := _enemy(front - side * 0.3)
	await _wait(2)
	var n := SlowMo.stops
	await _tap(&"attack")
	await _until_stop(n)
	_check(SlowMo.stops == n + 1 and SlowMo.stop.get("feel") == SlowMo.Feel.HIT, "a swing into two enemies plays one HIT")
	_check(e1.health < 100.0 and e2.health < 100.0, "both enemies were hit")
	await _until_full_speed()
	_check(Engine.time_scale == 1.0, "and the world is back at full speed")

	await _wait(30) # melee cooldown
	e1.health = 0.1
	e1.invuln = 0.0
	e2.invuln = 0.0
	n = SlowMo.stops
	await _tap(&"attack")
	await _until_stop(n)
	_check(SlowMo.stop.get("feel") == SlowMo.Feel.KILL, "a killing swing plays KILL")
	await _until_full_speed()

	p.damage(10.0)
	_check(SlowMo.stop.get("feel") == SlowMo.Feel.HURT, "the player hurt plays HURT")
	await _until_full_speed()
	p.invuln = 0.0
	p.damage(p.health + 1.0)
	_check(SlowMo.stop.get("feel") == SlowMo.Feel.KILL, "the player killed plays KILL")
	await _until_full_speed()
	p.respawn()
	await _wait(10)

	e1.queue_free()
	e2.queue_free()
	var e3 := _enemy(p.global_position + p.facing * 4.0)
	await _wait(2)
	n = SlowMo.stops
	var b := p.shoot()
	for i in 60:
		if SlowMo.stops != n or not is_instance_valid(b):
			break
		await physics_frame
	_check(SlowMo.stop.get("feel") == SlowMo.Feel.SHOT, "a player shot hitting an enemy plays SHOT")
	await _until_full_speed()

	p.invuln = 0.0
	var enemy_shot: Node3D = p.PROJECTILE.instantiate()
	a.add_child(enemy_shot)
	enemy_shot.setup(p.global_position + Vector3(5, 0, 0), Vector3.LEFT, 5.0, 0.0, e3)
	enemy_shot._finish(p)
	_check(SlowMo.stop.get("feel") == SlowMo.Feel.HURT, "an enemy shot hurting the player plays HURT, not SHOT")
	await _until_full_speed()

	var target := Node3D.new()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nfunc shot() -> void:\n\tpass\n"
	s.reload()
	target.set_script(s)
	n = SlowMo.stops
	var switch_shot: Node3D = p.PROJECTILE.instantiate()
	a.add_child(switch_shot)
	switch_shot.setup(p.global_position + Vector3(5, 0, 0), Vector3.LEFT, 5.0, 0.0, p)
	switch_shot._finish(target)
	_check(SlowMo.stops == n, "a shot at an energy switch plays no stop")
	target.free()

	while not p.is_on_floor() or p.state_name != &"idle":
		await physics_frame
	SlowMo.add(SlowMo.Feel.HIT)
	await physics_frame
	Input.action_press(&"jump")
	await _wait(2) # physics_frame fires before the nodes run: the press is read one frame later
	_check(p.jump_buffer > 0.0 or p.vspeed() > 0.0, "a jump pressed during a stop still registers")
	Input.action_release(&"jump")
	await _until_full_speed()
	sections += 1


## The camera follow, the shake and the fade run on real time; a new area starts at full speed.
func _test_realtime() -> void:
	var a := _area()
	await _wait(30)
	var p: Player = a.get_node("Player")
	var cam: Camera3D = a.get_node("Camera")
	var w: Node = root.get_node("World")

	SlowMo.add(SlowMo.Feel.KILL)
	CameraShake.clear()
	p.damage(10.0) # its HURT is dropped (the KILL runs), its JOLT isn't
	var t0 := Time.get_ticks_usec()
	await _wait(10)
	var real := (Time.get_ticks_usec() - t0) / 1e6
	var jolt := CameraShake.layers.filter(func(l: Dictionary) -> bool: return l.feel == CameraShake.Feel.JOLT)
	_check(jolt.size() == 1 and absf(jolt[0].age - real) < 0.05, "the hurt shake ages in real time during a stop (%.3f s in %.3f s)" % [jolt[0].age if jolt else -1.0, real])

	await _until_full_speed()
	await _wait(60) # the knockback and the follow settle
	SlowMo.add(SlowMo.Feel.KILL)
	var before := cam.global_position
	p.teleport(p.global_position + Vector3(3, 0, 0))
	await _wait(15)
	_check(cam.global_position.distance_to(before) > 2.0, "the camera follows in real time during a stop (%.2f m of 3)" % cam.global_position.distance_to(before))

	await _until_full_speed()
	SlowMo.add(SlowMo.Feel.KILL)
	w.fade(1.0, 0.15)
	await _wait(15) # 0.25 s real; on game time only ~0.08 s pass
	_check(w.fade_rect.color.a == 1.0, "a fade runs in real time during a stop (alpha %.2f)" % w.fade_rect.color.a)
	w.fade(0.0, 0.0)

	await _until_full_speed()
	SlowMo.add(SlowMo.Feel.KILL)
	SlowMo.bullet_target = 0.3
	_area()
	for i in 3:
		await process_frame
	_check(Engine.time_scale == 1.0 and SlowMo.stop.is_empty(), "a new area starts at full speed")
	sections += 1


# --- building -----------------------------------------------------------------------

## A bare GameArea (floor, Player at (0, 1, 0), Camera, HUD/Label) as the current scene; frees the last one.
func _area() -> Node3D:
	if area:
		root.remove_child(area)
		area.queue_free()
	area = load("res://world/area.gd").new()
	var floor := CSGBox3D.new()
	floor.size = Vector3(60, 1, 60)
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


## An enemy at `at` that never acts on its own (the hits come from the test).
func _enemy(at: Vector3) -> Enemy:
	var e: Enemy = ENEMY.instantiate()
	e.position = at # before entering the tree: added at the origin, it overlaps the player there and Jolt flings it
	area.add_child(e)
	e.set_physics_process(false)
	e.health = 100.0
	return e


# --- waiting and checking -----------------------------------------------------------

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)


## Waits (at most 60 physics frames) until a stop starts after `n` had started.
func _until_stop(n: int) -> void:
	for i in 60:
		if SlowMo.stops != n:
			return
		await physics_frame

## Waits (real time, at most 1 s) until no slow-down is left.
func _until_full_speed() -> void:
	var t0 := Time.get_ticks_msec()
	while Engine.time_scale != 1.0 and Time.get_ticks_msec() - t0 < 1000:
		await physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
