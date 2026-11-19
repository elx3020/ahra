@tool
extends "res://tests/editor_test.gd"
## Editor-side test of the Platform Tools plugin: edit mode toolbar, shape references, placing a
## track's anchors with viewport input (snapped / free / vertical, Esc, Enter, too few anchors),
## the built PlatformTrackInstance, undo, grouping and the group's view settings.
## Godot_console.exe --headless --path . -e res://tests/platform_tools_test.tscn -- --platform-tools-test

var cam: Camera3D


func _init() -> void:
	flag = "--platform-tools-test"
	label = "PLATFORM TOOLS"


func run() -> void:
	var pt = _find_plugin()
	check(pt != null, "Platform Edit toolbar found")
	check(not pt._tools.visible, "tools hidden until edit mode is on")
	pt._toggle.button_pressed = true
	check(pt._tools.visible and not pt._finish.visible, "edit mode shows the tools (Finish only while placing)")
	var ur := EditorInterface.get_editor_undo_redo()
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(self))
	cam = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()

	# --- shape reference ---
	var ref: ShapeReference = pt.add_shape_reference("Box")
	check(ref.get_parent() == self and ref.owner == self and ref.shapes().size() == 1 and ref.shapes()[0].owner == self, "shape reference added, saved with the scene")
	check(ref.shapes()[0].shape.size == Vector3(4, 4, 4), "box reference starts at 4x Godot's default")
	check(EditorInterface.get_selection().get_selected_nodes() == [ref], "new reference is selected")
	await frames(2)
	check(ref.get_gizmos().any(func(g): return g.get_plugin() and g.get_plugin().get_script() == load("res://addons/shape_tools/plugin.gd").ShapeGizmo), "reference gets the Shape Tools handles")
	ref.position = Vector3.ZERO
	ref.shapes()[0].shape.size = Vector3(10, 2, 10) # top face at y 1, x/z within +-5
	var cap: ShapeReference = pt.add_shape_reference("Capsule")
	check(is_equal_approx(cap.shapes()[0].shape.radius, 2.0) and is_equal_approx(cap.shapes()[0].shape.height, 8.0), "capsule reference: radius and height scaled")
	cap.position = Vector3(0, 0, -40) # out of the way

	# --- placing anchors ---
	_aim()
	var hit: Dictionary = pt.pick(cam, cam.unproject_position(Vector3(-3, 1, 0)), false)
	check(hit.snapped and hit.position.distance_to(Vector3(-3, 1, 0)) < 0.01, "pick snaps onto the reference's surface")
	pt.start_track()
	check(pt._finish.visible and pt._cancel.visible and not pt._group.visible, "placing shows Finish / Cancel")
	check(_click(pt, Vector3(-3, 1, 0)) == EditorPlugin.AFTER_GUI_INPUT_STOP, "clicks are taken while placing")
	_click(pt, Vector3(20, 1, 0)) # off the reference: horizontal plane through the last anchor
	_click(pt, Vector3(20, 5, 0), true) # Shift: vertical plane facing the camera
	var a: PackedVector3Array = pt._anchors
	check(a.size() == 3 and a[0].distance_to(Vector3(-3, 1, 0)) < 0.01 and a[1].distance_to(Vector3(20, 1, 0)) < 0.01 and a[2].distance_to(Vector3(20, 5, 0)) < 0.01, "anchors: on the reference, free, free raised with Shift: %s" % [a])
	check(pt._status.text == "3 anchors", "toolbar counts the anchors")
	_key(pt, KEY_ESCAPE)
	check(not pt._placing and _tracks(self).is_empty(), "Esc cancels, nothing built")
	pt.start_track()
	_click(pt, Vector3(-3, 1, 0))
	_key(pt, KEY_ENTER)
	check(not pt._placing and _tracks(self).is_empty(), "one anchor + Enter: aborted, nothing built")

	pt.start_track()
	var pts := [Vector3(-3, 1, 0), Vector3(20, 1, 0), Vector3(20, 5, 0)]
	_click(pt, pts[0])
	_click(pt, pts[1])
	_click(pt, pts[2], true)
	_key(pt, KEY_KP_ENTER)
	var built := _tracks(self)
	check(built.size() == 1, "Enter builds one track")
	var inst: PlatformTrackInstance = built[0]
	var path: Path3D = inst.get_node("Path")
	var plat: MovingPlatform = inst.platform()
	var seq: PlatformSequence = plat.get_node("Sequence")
	check(inst.global_position.distance_to(pts[0]) < 0.01 and inst.paths() == [path], "instance sits at the first anchor, one path")
	check(path.curve.point_count == 3 and range(3).all(func(i): return path.to_global(path.curve.get_point_position(i)).distance_to(pts[i]) < 0.01), "path runs through the anchors")
	check(plat.shapes().size() == 1 and plat.shapes()[0].shape is BoxShape3D and plat.shapes()[0].shape.size == Vector3(3, 0.5, 3), "default box platform")
	check(seq.path == path and seq.laps == 2 and plat.get_children().filter(func(c): return c is PlatformSequence).size() == 1, "one loop sequence (2 laps) on the path")
	check([inst, path, plat, plat.shapes()[0], seq].all(func(n): return n.owner == self), "all of it saved with the scene")
	check(inst._get_configuration_warnings().is_empty(), "no configuration warnings")
	check(EditorInterface.get_selection().get_selected_nodes() == [inst], "new track is selected")
	await frames(3)
	check(plat.global_position.distance_to(pts[0]) < 0.01, "platform waits at the first anchor")
	var ghosts := _ghosts(inst)
	check(ghosts.size() == 1 and ghosts[0].global_position.distance_to(pts[2]) < 0.01, "ghost platform at the path's end")
	hist.undo()
	check(_tracks(self).is_empty(), "undo removes the track")
	hist.redo()
	check(_tracks(self) == [inst] and inst.owner == self and seq.owner == self, "redo brings it back")

	# --- group ---
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(plat) # its platform: still counts as the track
	await frames(2)
	check(pt._group.visible, "Group button shows when a track (or a part of it) is selected")
	EditorInterface.get_selection().clear()
	await frames(2)
	check(not pt._group.visible, "and hides without one")
	EditorInterface.get_selection().add_node(inst)
	await frames(2)
	var before := inst.global_transform
	var group: PlatformTrackGroup = pt.create_group("Lift Group")
	check(group.name == &"Lift Group" and group.owner == self and group.get_parent() == self, "group created with its name")
	check(inst.get_parent() == group and inst.owner == self and inst.global_transform.is_equal_approx(before), "track moved in, same place in the world")
	check(group.global_position.distance_to(before.origin) < 0.01, "group centred on its tracks")
	group.show_paths = false
	group.show_destination = false
	group.preview = true
	await frames(2)
	check(not path.visible and _ghosts(inst).is_empty() and plat.preview, "group hides paths and ghosts, previews its platforms")
	group.show_paths = true
	group.show_destination = true
	group.preview = false
	await frames(2)
	check(path.visible and _ghosts(inst).size() == 1 and not plat.preview, "and back")

	# new track into the selected (rotated) group
	group.rotation_degrees.y = 90.0
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(group)
	await frames(1)
	_aim()
	pt.start_track()
	var pts2 := [Vector3(30, 0, 10), Vector3(36, 0, 10)]
	_click(pt, pts2[0])
	_click(pt, pts2[1])
	var inst2: PlatformTrackInstance = pt.finish_track()
	var path2: Path3D = inst2.get_node("Path")
	check(inst2.get_parent() == group and range(2).all(func(i): return path2.to_global(path2.curve.get_point_position(i)).distance_to(pts2[i]) < 0.01), "track built inside the selected rotated group, anchors where clicked")
	hist.undo()
	check(not is_instance_valid(inst2) or inst2.get_parent() == null, "undo the second track")
	group.rotation_degrees.y = 0.0
	hist.undo() # the group
	check(inst.get_parent() == self and inst.global_transform.is_equal_approx(before) and group.get_parent() == null, "undo the group: track back in place, group gone")

	var extra := MovingPlatform.new()
	inst.add_child(extra)
	check(not inst._get_configuration_warnings().is_empty(), "two platforms in a track: warning")
	extra.free()
	pt._toggle.button_pressed = false
	check(not pt._tools.visible, "edit mode off hides the tools")
	finished = true


func _find_plugin() -> EditorPlugin:
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	while stack:
		var n: Node = stack.pop_back()
		if n is Button and n.text == "New Track":
			return n.pressed.get_connections()[0].callable.get_object()
		stack.append_array(n.get_children())
	return null


## The editor moves its camera between frames: aim it right before using it.
func _aim() -> void:
	cam.global_position = Vector3(0, 15, 25)
	cam.look_at(Vector3(5, 0, 0))


func _click(pt, at: Vector3, shift := false) -> int:
	_aim()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.shift_pressed = shift
	e.position = cam.unproject_position(at)
	var r: int = pt._forward_3d_gui_input(cam, e)
	var up := e.duplicate()
	up.pressed = false
	pt._forward_3d_gui_input(cam, up)
	return r


func _key(pt, key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	pt._forward_3d_gui_input(cam, e)


func _tracks(parent: Node) -> Array:
	return parent.get_children().filter(func(c): return c is PlatformTrackInstance)


func _ghosts(inst: Node) -> Array:
	return inst.get_children(true).filter(func(c): return c.get_index(true) >= inst.get_child_count() and c is Node3D and not c is Path3D and not c is MovingPlatform)
