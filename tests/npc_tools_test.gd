@tool
extends "res://tests/editor_test.gd"
## Editor-side test of the NPC Tools plugin: the builder icon, New NPC Type (an inherited scene),
## New NPC (instanced, selected, undoable), the selected-NPC menu, the Add Interaction templates,
## Add Mark (saved with the scene) and the surface pick under the cursor.
## Godot_console.exe --headless --path . -e res://tests/npc_tools_test.tscn -- --npc-tools-test


func _init() -> void:
	flag = "--npc-tools-test"
	label = "NPC TOOLS"


func run() -> void:
	var nt = _find_plugin()
	check(nt != null, "NPC builder icon found")
	if nt == null:
		return
	EditorInterface.get_selection().clear()
	await frames(1)
	check(not nt._npc_menu.visible, "selected-NPC menu hidden with nothing selected")

	var path: String = nt.create_type("Test Guard", false)
	check(path == "res://npc/test_guard/test_guard.tscn" and FileAccess.file_exists(path), "type scene written")
	var ps: PackedScene = load(path)
	var inst := ps.instantiate()
	check(ps.get_state().get_base_scene_state() != null and inst is Npc and inst.name == &"TestGuard", "inherits npc.tscn (base state %s, Npc %s, name %s)" % [ps.get_state().get_base_scene_state() != null, inst is Npc, inst.name])
	inst.free()
	check(nt.create_type("Test Guard", false) == "" and nt.create_type("", false) == "" and nt.npc_scenes().has(path) and nt.npc_scenes().has("res://npc/npc.tscn"), "duplicate and empty names refused; types listed")

	var ur := EditorInterface.get_editor_undo_redo()
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(self))
	var n: Node3D = nt.add_npc("res://npc/npc.tscn")
	check(n is Npc and n.get_parent() == self and n.owner == self and n.scene_file_path == "res://npc/npc.tscn", "NPC instanced into the scene, saved as an instance")
	check(n.get_node("Visual").owner != self, "the instance's own nodes stay the instance's")
	check(nt.all_npcs() == [n] and EditorInterface.get_selection().get_selected_nodes() == [n], "listed and selected")
	await frames(1)
	check(nt._npc_menu.visible, "selected-NPC menu shows")

	var t1: NpcInteraction = nt.add_interaction(n, "talk_once")
	var t2: NpcInteraction = nt.add_interaction(n, "talk")
	var b: NpcInteraction = nt.add_interaction(n, "bark")
	var l: NpcInteraction = nt.add_interaction(n, "leave")
	check(t1.id == &"talk" and t1.once and t1.steps.size() == 2 and t2.id == &"talk2" and t2.steps[0].lines.size() == 3, "talk templates")
	check(b.trigger == NpcInteraction.Trigger.NEAR and not b.locks_player and b.id == &"bark" and l.steps[-1].kind == NpcStep.Kind.LEAVE and l.once and l.id == &"leave", "bark and leave templates")
	check(n.interactions.size() == 4 and n._get_configuration_warnings().is_empty(), "four interactions, no warnings")
	hist.undo()
	check(n.interactions.size() == 3, "undo add interaction")
	hist.redo()
	check(n.interactions.size() == 4, "redo add interaction")

	var m1: Marker3D = nt.place_mark(n, Vector3(3, 0, 0))
	var m2: Marker3D = nt.place_mark(n, Vector3(0, 0, 3))
	check(m1.get_parent() == n and m1.name == &"Mark" and m2.name == &"Mark2" and m1.owner == self and m1.global_position.is_equal_approx(Vector3(3, 0, 0)), "marks placed")
	check(EditorInterface.get_selection().get_selected_nodes() == [n], "the NPC stays selected while placing marks")
	var saved := PackedScene.new()
	saved.pack(self)
	var names := []
	for k in saved.get_state().get_node_count():
		names.append(saved.get_state().get_node_name(k))
	check(names.has(&"Mark") and names.has(&"Mark2"), "marks are saved with the scene")
	check(nt.pick_surface(Vector3(50, 10, 50), Vector3.DOWN, -0.8).is_equal_approx(Vector3(50, -0.8, 50)), "no collider: plane at the feet")
	var body := StaticBody3D.new() # box top at y 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	await physics_frames(2)
	check(absf(nt.pick_surface(Vector3(0, 10, 0), Vector3.DOWN, -0.8).y - 1.0) < 0.01, "ray hits a collider")
	body.free()

	nt.start_mark(n)
	check(nt._marking == n, "Add Mark waits for a click")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	nt._forward_3d_gui_input(EditorInterface.get_editor_viewport_3d(0).get_camera_3d(), esc)
	check(nt._marking == null, "Esc cancels Add Mark")

	hist.undo() # mark 2
	hist.undo() # mark 1
	check(n.get_children().all(func(c: Node) -> bool: return not c is Marker3D), "undo marks")
	for k in 4: # the four interactions...
		hist.undo()
	hist.undo() # ...then the NPC itself
	check(n.get_parent() == null and nt.all_npcs().is_empty(), "undo add NPC")

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())
	EditorInterface.get_resource_filesystem().scan()
	finished = true


func _find_plugin() -> EditorPlugin:
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	while stack:
		var n: Node = stack.pop_back()
		if n is MenuButton and n.tooltip_text == "NPC builder":
			for c in n.get_popup().about_to_popup.get_connections():
				if c.callable.get_object() is EditorPlugin:
					return c.callable.get_object()
		stack.append_array(n.get_children())
	return null
