extends SceneTree
## Headless smoke test of the player controller.
## Run: Godot_console.exe --headless --path . -s res://tests/smoke_test.gd

var fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
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
	p.envs.append(mud)
	await _wait(30)
	_check(absf(p.planar().length() - p.run_speed * 0.5) < 0.1, "env -50% speed halves run speed")
	p.grant(&"speed", 0.2) # progression and env % add up against base: 1 + 0.2 - 0.5
	await _wait(30)
	_check(is_equal_approx(p.mult(&"speed"), 0.7) and absf(p.planar().length() - p.run_speed * 0.7) < 0.1, "progression +20% stacks with env -50%")
	p.envs.erase(mud)
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
	p.envs.append(hot)
	p.damage(80)
	for i in 10:
		p.register_attack(false)
	await _wait(2)
	_check(p.anim == &"idle_hot_low_sad", "idle anim follows env/health/mood (got %s)" % p.anim)
	p.envs.erase(hot)
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

	print("SMOKE: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _place(p: Player, pos: Vector3) -> void:
	p.set_gravity_dir(Vector3.DOWN)
	p.velocity = Vector3.ZERO
	p.change_state(&"idle")
	p.teleport(pos)
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
