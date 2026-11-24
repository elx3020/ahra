extends SceneTree
## Checks forest.gdshader against Blender: renders enviroment_test.tscn unlit (base colour only)
## through deep_forest.blend's camera and diffs it with Blender's base colour render of the same
## view (reference/blender_albedo.png: every Principled's Base Color routed to Emission, Standard
## view). Needs a window (no --headless):
##   godot --path . --resolution 1280x720 -s res://demo/enviroment/compare.gd
## Exit code 1 if the mean difference is over 3/255 (the port gives ~1.2; edges make up the rest).

func _initialize() -> void:
	var scene: Node3D = (load("res://demo/enviroment/enviroment_test.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 42.9 * 720.0 / 1280.0 # Blender ortho scale is the width
	cam.far = 1000.0
	cam.transform = Transform3D(Basis(Vector3(0.822114, 0.0, -0.569323),
			Vector3(-0.439134, 0.636441, -0.634117), Vector3(0.36234, 0.771325, 0.523227)),
			Vector3(51.38, 115.70, 77.55))
	scene.add_child(cam)
	cam.make_current()
	(scene.get_node("ToonOutline") as Node3D).visible = false
	(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.get_active_material(0)
		if m and m.resource_name in ["light_shaft", "sparkles"]: # hidden in the reference too
			mi.visible = false
	for i in 60:
		await process_frame
	var got := root.get_texture().get_image()
	var ref := Image.load_from_file(ProjectSettings.globalize_path("res://demo/enviroment/reference/blender_albedo.png"))
	var total := 0.0
	for y in got.get_height():
		for x in got.get_width():
			var a := got.get_pixel(x, y)
			var b := ref.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := total / (got.get_width() * got.get_height() * 3.0) * 255.0
	print("FOREST ALBEDO vs BLENDER: mean diff %.2f/255 -> %s" % [mean, "OK" if mean <= 3.0 else "FAILED"])
	quit(0 if mean <= 3.0 else 1)
