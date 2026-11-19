extends SceneTree
## Headless test of the PBR material showcase (demo/materials/materials.tscn): the materials load,
## the clock drives sun, moon and lamps, the GUI slider sets the time, G switches SDFGI <-> VoxelGI.
## Run: Godot_console.exe --headless --path . -s res://tests/materials_test.gd

var fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var demo: Node3D = load("res://demo/materials/materials.tscn").instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	var spheres := demo.get_node("Spheres").get_children()
	_check(spheres.size() == 19 and spheres.all(func(m: MeshInstance3D) -> bool: return m.material_override is StandardMaterial3D),
		"19 spheres, each with its PBR material")

	demo.hours_per_second = 0.0
	var sun: DirectionalLight3D = demo.get_node("Sun")
	var moon: DirectionalLight3D = demo.get_node("Moon")
	var lamp: Light3D = demo.get_node("Lamps").get_child(0)
	demo.hour = 12.0
	await process_frame
	_check(sun.visible and sun.light_energy > 0.5 and not moon.visible and not lamp.visible and sun.global_basis.z.y > 0.5, "noon: sun high, moon and lamps off")
	demo.hour = 8.0
	await process_frame
	var morning := -sun.global_basis.z # where the light travels
	demo.hour = 16.0
	await process_frame
	_check(morning.x < 0.0 and -sun.global_basis.z.x > 0.0, "the sun shines from the east (+X) in the morning, from the west in the afternoon")
	demo.hour = 0.0
	await process_frame
	_check(not sun.visible and moon.visible and lamp.visible and lamp.light_energy > 0.0, "midnight: moon and lamps on, sun off")
	var slider: HSlider = demo.get_node("%TimeSlider")
	slider.value = 18.5
	_check(is_equal_approx(demo.hour, 18.5), "the time slider sets the hour")

	var env: Environment = demo.env
	var vgi: VoxelGI = demo.get_node("VoxelGI")
	_check(env.sdfgi_enabled and not vgi.visible, "SDFGI by default")
	_press_g()
	_check(not env.sdfgi_enabled and vgi.visible, "G switches to VoxelGI")
	_press_g()
	_check(env.sdfgi_enabled and not vgi.visible, "G switches back to SDFGI")

	print("MATERIALS: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


func _press_g() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_G
	e.pressed = true
	root.push_input(e)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
