@tool
extends Node3D
## Editor-side test of ShapeSet nodes (Zone, MovingPlatform) + the Shape Tools plugin: Add Shape /
## Remove (with undo), inspector proxies, mesh redraw, resize handles, duplicate unsharing.
## It needs the editor, so it opens this scene there instead of running with -s:
## Godot_console.exe --headless --path . -e res://tests/shape_editor_test.tscn -- --shape-editor-test
## Opening the scene normally does nothing.

var failed := 0
var finished := false ## run() got to the end (a script error stops it silently)


func _ready() -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has("--shape-editor-test"):
		return
	await get_tree().create_timer(2.0).timeout
	await run()
	check(finished, "ran to the end")
	print("SHAPE EDITOR: ", "OK" if failed == 0 else "%d FAILED" % failed)
	# the editor saved this scene into its reopen list when it opened it: take it back out, so
	# your next editor session doesn't reopen it; then close it, dropping the test's edits
	var layout := EditorInterface.get_editor_paths().get_project_settings_dir().path_join("editor_layout.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(layout) == OK:
		var open: PackedStringArray = cfg.get_value("EditorNode", "open_scenes", PackedStringArray())
		open.erase(scene_file_path)
		cfg.set_value("EditorNode", "open_scenes", open)
		if cfg.get_value("EditorNode", "current_scene", "") == scene_file_path:
			cfg.set_value("EditorNode", "current_scene", open[-1] if open else "")
		cfg.save(layout)
	get_tree().quit(failed)
	EditorInterface.close_scene()


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failed += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run() -> void:
	var zone: Node3D = $Zone
	var plugin: GDScript = load("res://addons/shape_tools/plugin.gd")
	var insp = plugin.ShapeInspector.new()
	var ur := EditorInterface.get_editor_undo_redo()
	check(EditorInterface.is_plugin_enabled("shape_tools"), "plugin enabled")

	var sphere: CollisionShape3D = insp.add(zone, "Sphere")
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(zone))
	check(zone.shapes() == [sphere] and sphere.owner == self and sphere.position == Vector3.ZERO, "add sphere at origin, owned by scene")
	check(sphere.shape is SphereShape3D and sphere.shape.resource_local_to_scene, "sphere shape, local to scene")
	hist.undo()
	check(zone.shapes().is_empty(), "undo add")
	hist.redo()
	check(zone.shapes() == [sphere] and sphere.owner == self, "redo add")

	for kind in insp.SHAPES:
		insp.add(zone, kind)
	await frames(3)
	var kids: Array = zone.shapes()
	check(kids.size() == 8, "8 shapes, got %d" % kids.size())
	var names := kids.map(func(c): return str(c.name))
	check(names == ["Sphere", "Box", "Sphere2", "Capsule", "Cylinder", "HeightMap", "Convex", "Concave"], "names %s" % [names])
	check(zone.get_node("Convex").shape.points.size() > 0 and zone.get_node("Concave").shape.get_faces().size() > 0, "convex/concave start as a cube")
	var meshed := kids.all(func(c): return c.get_children(true).filter(func(m): return m.name == &"ShapeMesh" and m.mesh == c.shape.get_debug_mesh()).size() == 1)
	check(meshed, "one ShapeMesh per shape, showing its debug mesh")

	# proxies
	var props := zone.get_property_list().map(func(p): return p.name)
	check(props.has("shapes/add") and props.has("shapes/Capsule/shape") and props.has("shapes/Capsule/remove"), "inspector proxies listed")
	zone.set("shapes/Capsule/position", Vector3(1, 2, 3))
	check(zone.get_node("Capsule").position == Vector3(1, 2, 3) and zone.get("shapes/Capsule/position") == Vector3(1, 2, 3), "position proxy")
	zone.set("shapes/Capsule/shape", null)
	check(zone.get_node("Capsule").shape is CapsuleShape3D, "clearing via proxy is ignored")

	# editor redraw when a shape changes
	sphere.shape.radius = 3.0
	await frames(2)
	var mi: MeshInstance3D = sphere.get_children(true).filter(func(m): return m.name == &"ShapeMesh")[0]
	check(mi.mesh == sphere.shape.get_debug_mesh() and is_equal_approx(mi.mesh.get_aabb().size.x, 6.0), "mesh follows radius change")

	# remove + undo keeps index and owner
	var box: CollisionShape3D = zone.get_node("Box")
	var index := box.get_index()
	insp.remove(zone, box)
	check(not box.is_inside_tree() and zone.shapes().size() == 7, "remove box")
	hist.undo()
	check(box.get_parent() == zone and box.get_index() == index and box.owner == self, "undo remove: same index and owner")

	# inspector builds the menu and buttons
	EditorInterface.edit_node(zone)
	await frames(3)
	var found := {menu = false, remove = false}
	var stack: Array[Node] = [EditorInterface.get_inspector()]
	while stack:
		var n: Node = stack.pop_back()
		if n is MenuButton and n.text == "Add Shape":
			found.menu = true
		if n is Button and n.text == "Remove Capsule":
			found.remove = true
		stack.append_array(n.get_children())
	check(found.menu and found.remove, "inspector shows Add Shape menu and Remove buttons %s" % [found])

	# gizmo handles
	var gizmo := shape_gizmo(zone, plugin)
	check(gizmo != null, "zone has the Shapes gizmo")
	var gp = plugin.ShapeGizmo
	box.shape.size = Vector3(2, 2, 2)
	box.position = Vector3(5, 0, 0)
	await frames(2)
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	cam.global_position = Vector3(5, 10, 20)
	cam.look_at(box.global_position)
	var box_i: int = zone.shapes().find(box)
	var target := zone.global_transform * (box.transform * Vector3(0, 0, 3)) # z handle to 3 m
	var screen := cam.unproject_position(target)
	var id := box_i * 3 + 2
	var before = gizmo.get_plugin()._get_handle_value(gizmo, id, false)
	gizmo.get_plugin()._set_handle(gizmo, id, false, cam, screen)
	check(absf(box.shape.size.z - 6.0) < 0.05 and box.shape.size.x == 2.0, "drag box z handle to 3 m -> size.z 6 (got %s)" % box.shape.size)
	gizmo.get_plugin()._commit_handle(gizmo, id, false, before, false)
	hist.undo()
	check(box.shape.size == Vector3(2, 2, 2), "undo handle drag")
	hist.redo()
	check(absf(box.shape.size.z - 6.0) < 0.05, "redo handle drag")
	var cap: CollisionShape3D = zone.get_node("Capsule")
	var cap_i: int = zone.shapes().find(cap)
	cam.look_at(cap.global_position)
	screen = cam.unproject_position(zone.global_transform * (cap.transform * Vector3(0, 2.5, 0)))
	gizmo.get_plugin()._set_handle(gizmo, cap_i * 3 + 1, false, cam, screen)
	check(absf(cap.shape.height - 5.0) < 0.05, "drag capsule height handle -> 5 (got %s)" % cap.shape.height)
	check(gp.axes(BoxShape3D.new()) == [0, 1, 2] and gp.axes(SphereShape3D.new()) == [0] and gp.axes(HeightMapShape3D.new()).is_empty(), "handle axes per type")

	# Ctrl+D shares shapes: the copy gets its own
	var copy: Node3D = zone.duplicate()
	add_child(copy) # the editor's Ctrl+D: add, then set the owner
	copy.owner = self
	await frames(1)
	var own: bool = copy.shapes().all(func(c): return not zone.shapes().any(func(o): return o.shape == c.shape))
	check(own and copy.shapes().size() == zone.shapes().size(), "duplicate gets its own shapes")
	check(copy.shapes().all(func(c): return c.get_children(true).filter(func(m): return m.name == &"ShapeMesh").size() == 1), "duplicate: one mesh per shape")
	check(absf(zone.bounds().end.x - 6.0) < 0.05 and absf(zone.bounds().position.x + 3.0) < 0.05, "bounds span sphere (r 3) to moved box (x 6): %s" % zone.bounds())

	# moving platform: same tools, solid lit meshes
	var plat: Node3D = $Platform
	var pbox: CollisionShape3D = insp.add(plat, "Box")
	var pconvex: CollisionShape3D = insp.add(plat, "Convex")
	await frames(2)
	check(plat.shapes() == [pbox, pconvex] and pbox.owner == self, "platform: add box + convex")
	var pm: MeshInstance3D = pbox.get_children(true).filter(func(m): return m.name == &"ShapeMesh")[0]
	check(pm.mesh is BoxMesh and pm.mesh.size == pbox.shape.size and pm.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "platform: box drawn as a lit BoxMesh")
	var cm: MeshInstance3D = pconvex.get_children(true).filter(func(m): return m.name == &"ShapeMesh")[0]
	var arrays: Array = cm.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_NORMAL].size() == arrays[Mesh.ARRAY_VERTEX].size() and arrays[Mesh.ARRAY_VERTEX].size() >= 36, "platform: convex drawn from its faces with normals")
	var pgizmo := shape_gizmo(plat, plugin)
	check(pgizmo != null, "platform has the Shapes gizmo")
	pbox.shape.size = Vector3(2, 2, 2)
	await frames(2)
	cam.global_position = plat.global_position + Vector3(0, 10, 20)
	cam.look_at(plat.global_position)
	screen = cam.unproject_position(plat.global_transform * Vector3(2, 0, 0))
	pgizmo.get_plugin()._set_handle(pgizmo, 0, false, cam, screen)
	await frames(2)
	check(absf(pbox.shape.size.x - 4.0) < 0.05, "platform: drag box x handle to 2 m -> size.x 4 (got %s)" % pbox.shape.size)
	pm = pbox.get_children(true).filter(func(m): return m.name == &"ShapeMesh")[0]
	check(absf(pm.mesh.size.x - 4.0) < 0.05, "platform: mesh follows the resize")
	EditorInterface.edit_node(plat)
	await frames(3)
	check(find_text(EditorInterface.get_inspector(), "Add Shape"), "platform inspector shows Add Shape")
	insp.remove(plat, pconvex)
	check(plat.shapes() == [pbox], "platform: remove convex")
	finished = true


func shape_gizmo(node: Node3D, plugin: GDScript) -> EditorNode3DGizmo:
	for g in node.get_gizmos():
		if g.get_plugin() and g.get_plugin().get_script() == plugin.ShapeGizmo:
			return g
	return null


func find_text(root: Node, text: String) -> bool:
	var stack: Array[Node] = [root]
	while stack:
		var n: Node = stack.pop_back()
		if n is MenuButton and n.text == text:
			return true
		stack.append_array(n.get_children())
	return false
