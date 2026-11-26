extends SceneTree
## Headless smoke test of the player controller.
## Run: Godot_console.exe --headless --path . -s res://tests/smoke_test.gd

var fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	ProjectSettings.set_setting(SlowMo.DISABLE, true) # suites count physics frames; tests/slowmo_test.gd covers the stops
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	var p: Player = demo.get_node("Player")
	await _wait(1)
	p.teleport(Vector3(-28, 1, 6)) # open floor, nothing in the way along +x
	await _wait(30)
	_check(p.state_name == &"idle" and p.is_on_floor(), "settles idle on floor")

	Input.action_press(&"jump")
	await _wait(3)
	_check(p.state_name == &"jump" and p.vspeed() > 0.0, "jump rises")
	await _wait(10)
	Input.action_release(&"jump")
	await _wait(60)
	_check(p.state_name == &"idle", "lands back to idle")

	Input.action_press(&"move_right")
	Input.action_press(&"move_down") # right+down = straight +x in iso
	await _wait(30)
	_check(p.state_name == &"walk" and absf(p.planar().length() - p.walk_speed) < 0.1, "walk speed")
	Input.action_press(&"run")
	await _wait(30)
	_check(p.state_name == &"run" and absf(p.planar().length() - p.run_speed) < 0.1, "run speed")
	var mud := EnvProfile.new()
	mud.mods.speed = -0.5
	p.add_env(mud)
	await _wait(30)
	_check(absf(p.planar().length() - p.run_speed * 0.5) < 0.1, "env -50% speed halves run speed")
	p.grant(&"speed", 0.2) # progression and env % add up against base: 1 + 0.2 - 0.5
	await _wait(30)
	_check(is_equal_approx(p.mult(&"speed"), 0.7) and absf(p.planar().length() - p.run_speed * 0.7) < 0.1, "progression +20% stacks with env -50%")
	p.remove_env(mud)
	await _wait(30)
	_check(absf(p.planar().length() - p.run_speed * 1.2) < 0.1, "progression bonus stays after leaving env")
	p.progression = StatMods.new()
	Input.action_release(&"run")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	await _wait(30)

	Input.action_press(&"dash")
	await _wait(4)
	Input.action_release(&"dash")
	_check(p.state_name == &"dash" and p.planar().length() > p.run_speed, "dash bursts")
	await _wait(30)

	var hot := EnvProfile.new()
	hot.temperature = EnvProfile.Temp.HOT
	p.add_env(hot)
	p.health = p.max_hp() * 0.2
	for i in 10:
		p.register_attack(false)
	await _wait(2)
	_check(p.anim == &"idle_hot_low_sad", "idle anim follows env/health/mood (got %s)" % p.anim)
	p.remove_env(hot)
	p.heal(100)

	p.velocity = Vector3(5, 3, 0)
	p.teleport(p.global_position + Vector3(0, 20, 0), Basis(Vector3.UP, PI / 2))
	_check(p.velocity.is_equal_approx(Vector3(0, 3, -5)), "teleport keeps (rotated) momentum")
	p.teleport(Vector3(-22, 1, 5))
	p.velocity = Vector3.ZERO
	await _wait(60)

	var y := p.global_position.y
	p.set_gravity_dir(Vector3.UP)
	await _wait(20)
	_check(p.global_position.y > y + 1.0 and p.state_name == &"jump", "flipped gravity falls up")

	# --- level bays (positions from demo.tscn) ---
	await _place(p, Vector3(220, 1, 3)) # Gravity bay, "ToWall" pad
	await _wait(60)
	_check(p.is_on_floor() and p.global_position.z < -6.0, "-z gravity pad: standing on back wall")

	await _place(p, Vector3(194, 1, -3)) # Teleport bay, PadA
	p.velocity = Vector3(8, 0, 0)
	await _wait(3)
	_check(p.global_position.y > 6.0 and p.velocity.x > 7.0, "teleport pad keeps momentum")

	await _place(p, Vector3(174, 1, 0)) # Cinematic trigger
	await _wait(5)
	_check(p.state_name == &"puppet", "cutscene trigger puppets player")
	await _wait(240)
	_check(p.state_name == &"idle" and p.global_position.x > 185.0, "puppet walked to marker and released")

	await _place(p, Vector3(116, 1, -3.3)) # Climb wall
	Input.action_press(&"move_up")
	await _wait(20)
	_check(p.state_name == &"climb", "pushing into climbable wall climbs")
	for i in 300:
		if p.state_name != &"climb":
			break
		await _wait(1)
	await _wait(12)
	Input.action_release(&"move_up")
	await _wait(40)
	_check(p.global_position.y > 6.5 and p.is_on_floor(), "ledge hop onto wall top")

	await _place(p, Vector3(140, 3, 0)) # Swing point overhead
	Input.action_press(&"grab")
	await _wait(5)
	_check(p.state_name == &"swing", "grab swing point in air")
	Input.action_release(&"grab")

	# --- wind, stamina ---
	await _place(p, Vector3(-28, 1, 6))
	var gale := EnvProfile.new()
	gale.wind = Vector3(-10, 0, 0)
	p.add_env(gale)
	await _wait(30)
	_check(p.is_on_floor() and is_equal_approx(p.velocity.x, -10.0 * p.wind_response_ground), "wind pushes on the ground too")
	p.remove_env(gale)

	await _place(p, Vector3(-28, 1, 6))
	p.stamina = 1.0
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	Input.action_press(&"run")
	await _wait(20)
	_check(p.exhausted and p.state_name == &"walk", "empty stamina forces walk")
	await _wait(roundi(p.exhaust_time * 60.0) - 30)
	_check(p.state_name == &"walk", "still walking during exhaustion timeout")
	await _wait(20)
	_check(not p.exhausted and p.state_name == &"run", "runs again after timeout")
	Input.action_release(&"run")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")

	# --- swimming, oxygen ---
	await _place(p, Vector3(100, 1, 3)) # Underwater bay floor; surface at y = 8
	await _wait(10)
	Input.action_press(&"jump")
	await _wait(5)
	_check(p.state_name == &"swim" and p.vspeed() > 0.0, "jump in deep water swims up")
	await _wait(150)
	_check(p.state_name == &"swim" and absf(p.water_depth() - p.float_depth) < 0.05, "swim up stops at the surface")
	Input.action_release(&"jump")
	Input.action_press(&"descend")
	await _wait(40)
	_check(p.water_depth() > 2.0, "descend swims down")
	Input.action_release(&"descend")
	Input.action_press(&"jump")
	await _wait(150)
	Input.action_release(&"jump")
	await _wait(2)
	Input.action_press(&"jump")
	await _wait(10)
	Input.action_release(&"jump")
	_check(p.state_name == &"jump" and p.global_position.y > 8.0, "jump at the surface leaps out")
	await _wait(60)

	await _place(p, Vector3(100, 1, 3))
	_check(p.water_depth() > Player.HEAD, "standing on the bottom is underwater")
	var o2 := p.oxygen
	await _wait(30)
	_check(p.oxygen < o2, "oxygen drains underwater")
	p.oxygen = 0.1
	await _wait(10)
	_check(p.state_name == &"death" and p.anim == &"death_drown", "no oxygen = drown death")
	await _wait(200)
	_check(p.state_name == &"idle" and p.global_position.distance_to(p.checkpoint) < 1.0, "respawn at checkpoint after drowning")

	# --- damage, i-frames, death ---
	await _place(p, Vector3(-28, 1, 6))
	p.invuln = 0.0
	var hp := p.health
	p.damage(10, p.global_position + Vector3(1, 0, 0))
	_check(p.state_name == &"hurt" and p.velocity.x < 0.0 and p.health == hp - 10.0, "damage = hurt state + knockback")
	p.damage(10)
	_check(p.health == hp - 10.0, "invulnerable right after a hit")
	await _wait(80)
	_check(p.invuln <= 0.0 and p.state_name == &"idle", "hurt and i-frames wear off")
	p.damage(p.health)
	_check(p.state_name == &"death" and p.anim == &"death_hit", "health 0 = hit death")
	await _wait(120)
	_check(p.state_name == &"idle" and p.health == p.max_hp(), "respawn with full health")

	await _place(p, Vector3(-20, -6, 0)) # above the void kill zone
	await _wait(30)
	_check(p.state_name == &"death" and p.anim == &"death_fall", "falling into the void = fall death")
	await _wait(80)
	_check(p.state_name == &"idle" and p.global_position.distance_to(p.checkpoint) < 1.0, "respawn at checkpoint after falling")

	# --- mixed: icy climbable wall + crosswind (MixClimb bay, wall x 235..245, top y 8) ---
	await _place(p, Vector3(237, 1, -3.3))
	Input.action_press(&"move_up")
	await _wait(30)
	_check(p.state_name == &"climb" and p.mult(&"traction") < 1.0 and p.env.wind.x > 0.0, "overlapping zones combine (icy + crosswind) while climbing")
	var x0 := p.global_position.x
	Input.action_release(&"move_up")
	var y0 := p.global_position.y
	await _wait(20)
	_check(p.state_name == &"climb" and p.global_position.y < y0 and p.global_position.x > x0, "hanging on icy wall slides down, wind drifts sideways")
	await _place(p, Vector3(244.4, 3, -3.3))
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	for i in 120:
		await _wait(1)
		if p.state_name != &"climb" and i > 5:
			break
	_check(p.state_name == &"jump" and p.vspeed() < 5.0, "blown off a side edge falls (no fake ledge hop)")
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")

	# --- mixed: underwater swing (MixSwing bay, pool x 252..264, anchor y 4) ---
	await _place(p, Vector3(258, 2, 0))
	await _wait(10)
	Input.action_press(&"grab")
	await _wait(4)
	_check(p.state_name == &"swing", "grab a swing point while swimming")
	var spd := p.velocity.length()
	Input.action_press(&"jump")
	await _wait(4)
	_check(p.state_name == &"jump" and p.velocity.length() > spd + 5.0, "slingshot release underwater")
	Input.action_release(&"jump")
	Input.action_release(&"grab")
	await _wait(60)

	await _place(p, Vector3(263.3, 3, 0))
	Input.action_press(&"jump")
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	await _wait(60)
	_check(p.global_position.is_finite() and p.water_zone == null, "swimming up out through a pool side stays sane")
	Input.action_release(&"jump")
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")

	# --- gravity -x: wall along z (Gravity bay, left wall surface at x 213) ---
	await _place(p, Vector3(216, 1, -2))
	await _wait(60)
	_check(p.is_on_floor() and p.up_direction.is_equal_approx(Vector3.RIGHT) and p.global_position.x < 214.5, "-x gravity pad: standing on the left wall")
	Input.action_press(&"move_up")
	for i in 120:
		await _wait(1)
		if p.gravity_dir == Vector3.DOWN:
			break
	Input.action_release(&"move_up")
	await _wait(60)
	_check(p.is_on_floor() and p.up_direction == Vector3.UP, "walk up the left wall onto the reset pad, drop to the floor")

	# --- mixed: swing across a gap while on the ceiling / on a -x wall ---
	var r := await _swing_cross(p, Vector3(273, 1, 0), [&"move_right", &"move_down"], Vector3(280, 4, 0), Vector3.RIGHT, 275.0)
	_check(r.up.is_equal_approx(Vector3.DOWN) and r.hang > 0.5, "ceiling: pad flips gravity, swing hangs toward the ceiling (+y) (%.2f)" % r.hang)
	_check(r.landed and r.pos.x > 284.6 and r.up.is_equal_approx(Vector3.DOWN), "ceiling: slingshot lands on the far ceiling slab")
	r = await _swing_cross(p, Vector3(297, 1, -6), [&"move_left"], Vector3(299, 2.5, 0), Vector3.BACK, -4.0)
	_check(r.up.is_equal_approx(Vector3.RIGHT) and r.hang > 0.5, "wall: pad sets -x gravity, swing hangs toward the wall (-x) (%.2f)" % r.hang)
	_check(r.landed and r.pos.z > 3.6 and r.up.is_equal_approx(Vector3.RIGHT), "wall: slingshot lands on the far wall")

	# --- zone shapes: every type triggers (a Checkpoint sets the respawn point on its floor) ---
	var kinds: Array[Shape3D] = [BoxShape3D.new(), SphereShape3D.new(), CapsuleShape3D.new(), CylinderShape3D.new(),
		HeightMapShape3D.new(), BoxMesh.new().create_convex_shape(), BoxMesh.new().create_trimesh_shape()]
	for i in kinds.size():
		var cp := Checkpoint.new()
		cp.add_shape(kinds[i])
		cp.position = Vector3(-60 + i * 6, 40, 30) # open air
		demo.add_child(cp)
		var b := cp.bounds()
		var want := cp.to_global(Vector3(b.get_center().x, b.position.y, b.get_center().z)) + Vector3.UP
		p.checkpoint = Vector3.ZERO
		await _place(p, cp.position + Vector3.UP * 3)
		for f in 90:
			await _wait(1)
			if p.checkpoint != Vector3.ZERO:
				break
		_check(p.checkpoint.is_equal_approx(want), "%s zone triggers, checkpoint on its floor" % kinds[i].get_class())
		cp.queue_free()
	var pool := EnvZone.new()
	var ball := SphereShape3D.new()
	ball.radius = 2.0
	pool.add_shape(ball, Vector3(0, 1, 0))
	pool.position = Vector3(0, 50, 0)
	demo.add_child(pool)
	_check(is_equal_approx(pool.surface_height(Vector3.UP), 53.0) and is_equal_approx(pool.surface_height(Vector3.RIGHT), 2.0), "round zone: surface height is the top of its shape")

	print("SMOKE: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


## Walks off a platform edge (any gravity), grabs `anchor`, pumps toward the far side and
## releases on the upswing. Returns {up, hang (best offset·gravity while swinging), landed, pos}.
func _swing_cross(p: Player, start: Vector3, acts: Array, anchor: Vector3, axis: Vector3, edge: float) -> Dictionary:
	await _place(p, start)
	await _wait(60) # gravity pad drops the player onto its surface
	var r := {up = p.up_direction, hang = -1.0, landed = false, pos = Vector3.ZERO}
	for a in acts:
		Input.action_press(a)
	var phase := 0
	for i in 600:
		await _wait(1)
		var along := p.global_position.dot(axis)
		if phase == 0 and along > edge - 0.3:
			Input.action_press(&"jump")
			phase = 1
		elif phase == 1:
			Input.action_release(&"jump")
			if p.global_position.distance_to(anchor) < 6.0:
				Input.action_press(&"grab")
				phase = 2
		elif phase == 2 and p.state_name == &"swing":
			r.hang = maxf(r.hang, (p.global_position - anchor).normalized().dot(p.gravity_dir))
			if along > anchor.dot(axis) + 1.0 and p.vspeed() > 0.0:
				Input.action_press(&"jump")
				phase = 3
		elif phase == 3:
			Input.action_release(&"jump")
			Input.action_release(&"grab")
			if p.is_on_floor():
				r.landed = true
				r.pos = p.global_position
				r.up = p.up_direction
				break
	for a in acts + [&"jump", &"grab"]:
		Input.action_release(a)
	return r


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
