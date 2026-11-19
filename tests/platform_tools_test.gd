@tool
extends "res://tests/editor_test.gd"
## Editor-side test of the Platform Tools plugin: edit mode toolbar, shape references (plane
## included), placing a track's anchors with viewport input (snapped / free / vertical, Esc,
## Enter, too few anchors), the 3D preview and its settings panel, the built
## PlatformTrackInstance (open, or closed by clicking the first anchor), the Shape Refs / Tracks
## menus (counts, select, remove, undo), grouping and the group's view settings.
## It changes the preview's editor settings and puts the user's values back at the end.
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
	var prefs := {} # the user's preview settings, restored at the end
	for st: Array in pt.TrackPreview.SETTINGS:
		prefs[st[0]] = pt.TrackPreview.value(st[0])
	pt.reset_look()

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

	# a plane reference is infinite: casts hit it anywhere, at any tilt
	var flat: ShapeReference = pt.add_shape_reference("Plane")
	check(flat.shapes()[0].shape is WorldBoundaryShape3D, "Plane reference: a WorldBoundaryShape3D")
	flat.position = Vector3(0, 3, 0)
	var far: Dictionary = flat.cast(Vector3(500, 10, -300), Vector3.DOWN)
	check(not far.is_empty() and far.position.distance_to(Vector3(500, 3, -300)) < 0.001, "plane: hit 580 m away from its origin")
	flat.rotation_degrees.x = 90.0 # now upright, facing +z
	var wall: Dictionary = flat.cast(Vector3(7, 5, 10), Vector3.FORWARD)
	check(not wall.is_empty() and wall.position.distance_to(Vector3(7, 5, 0)) < 0.001 and absf(wall.normal.z) > 0.99, "plane: tilted upright, hit from the side")
	hist.undo() # remove it: an infinite plane would catch every free anchor below
	check(flat.get_parent() == null, "plane reference removed (undo)")

	# the Shape Refs menu: count, select one to edit it, remove the selected ones
	await frames(1)
	check(pt._refs.text == "Shape Refs (2)", "toolbar counts the shape references (%s)" % pt._refs.text)
	var rmenu: PopupMenu = pt._refs.get_popup()
	rmenu.about_to_popup.emit()
	var cap_i := _item_for(rmenu, cap)
	check(cap_i >= 0 and rmenu.get_item_text(cap_i) == "CapsuleRef" and _item_for(rmenu, ref) >= 0, "Shape Refs menu lists each reference")
	rmenu.index_pressed.emit(cap_i)
	await frames(2)
	check(EditorInterface.get_selection().get_selected_nodes() == [cap] and EditorInterface.get_inspector().get_edited_object() == cap, "picking one selects it, the inspector edits it")
	rmenu.about_to_popup.emit()
	var rm_i := _remove_item(rmenu)
	check(rm_i >= 0 and not rmenu.is_item_disabled(rm_i) and rmenu.get_item_metadata(rm_i) == [cap], "Remove selected offers the selected reference")
	rmenu.index_pressed.emit(rm_i)
	await frames(1)
	check(cap.get_parent() == null and pt._refs.text == "Shape Refs (1)", "removed, count updated")
	hist.undo()
	await frames(1)
	check(cap.get_parent() == self and cap.owner == self and cap.shapes()[0].owner == self and pt._refs.text == "Shape Refs (2)", "undo puts it back, saved with the scene")

	# --- placing anchors ---
	_aim()
	var hit: Dictionary = pt.pick(cam, cam.unproject_position(Vector3(-3, 1, 0)), false)
	check(hit.snapped and hit.position.distance_to(Vector3(-3, 1, 0)) < 0.01, "pick snaps onto the reference's surface")
	pt.start_track()
	check(pt._finish.visible and pt._cancel.visible and not pt._group.visible, "placing shows Finish / Cancel")
	var pv: Node3D = pt._preview
	check(is_instance_valid(pv) and pv.get_parent() == self and pv.owner == null and not get_children().has(pv), "preview: an internal, unsaved child of the scene")
	_move(pt, Vector3(-3, 1, 0))
	var snap_col: Color = pt.TrackPreview.value("snap_color")
	check(pv.get_child_count() == 1 and pv.get_child(0).global_position.distance_to(Vector3(-3, 1, 0)) < 0.01 and pv.get_child(0).material_override.albedo_color.is_equal_approx(snap_col), "before the first anchor: a cursor where it would go, snap colour on a reference")
	_move(pt, Vector3(30, 0, 0))
	check(pv.get_child(0).material_override.albedo_color.is_equal_approx(pt.TrackPreview.value("cursor_color")), "free cursor colour off the reference")
	check(_click(pt, Vector3(-3, 1, 0)) == EditorPlugin.AFTER_GUI_INPUT_STOP, "clicks are taken while placing")
	_click(pt, Vector3(20, 1, 0)) # off the reference: horizontal plane through the last anchor
	_move(pt, Vector3(20, 5, 0), true)
	# 2 segments (placed path + next segment to the cursor) then 2 anchor markers and the cursor
	check(pv.get_child_count() == 5, "preview: path, next segment, 2 anchors, cursor (%d nodes)" % pv.get_child_count())
	var seg: MeshInstance3D = pv.get_child(0)
	check(seg.mesh is CylinderMesh and seg.global_position.distance_to(Vector3(8.5, 1, 0)) < 0.01 and absf(seg.global_basis.y.length() - 23.0) < 0.01, "path tube spans the first two anchors")
	check(seg.material_override.albedo_color.is_equal_approx(pt.TrackPreview.value("path_color")) and pv.get_child(1).material_override.albedo_color.is_equal_approx(pt.TrackPreview.value("next_color")), "path and next segment colours")
	check(pv.get_child(1).global_position.distance_to(Vector3(20, 3, 0)) < 0.01, "next segment runs to the cursor (Shift raises it)")
	pt.set_look("marker_size", 1.0)
	pt.set_look("marker_shape", 1)
	pt.set_look("opacity", 0.5)
	pt.set_look("on_top", false)
	var cursor: MeshInstance3D = pv.get_child(pv.get_child_count() - 1)
	check(cursor.mesh is BoxMesh and cursor.mesh.size.is_equal_approx(Vector3.ONE * 1.4), "settings: cube markers, size (cursor 1.4x)")
	check(not cursor.material_override.no_depth_test, "settings: Draw on top off, markers depth tested again")
	check(is_equal_approx(seg_alpha(pv), pt.TrackPreview.value("path_color").a * 0.5), "settings: opacity halves the alpha")
	pt.set_look("marker_shape", 2)
	cursor = pv.get_child(pv.get_child_count() - 1)
	check(cursor.mesh is SphereMesh and cursor.mesh.radial_segments == 4, "settings: diamond markers")
	pt._fill_look_panel()
	var swatch: ColorPickerButton = pt._look_grid.get_node("path_color")
	check(pt._look_grid.get_child_count() == pt.TrackPreview.SETTINGS.size() * 2 and swatch.edit_alpha, "panel: a row per setting, colours with alpha")
	swatch.color_changed.emit(Color(1, 0, 0, 0.5))
	check(pt.TrackPreview.value("path_color") == Color(1, 0, 0, 0.5) and pv.get_child(0).material_override.albedo_color.r == 1.0 and pv.get_child(0).material_override.albedo_color.g == 0.0, "panel: picking a colour saves it and recolours the preview")
	pt._look_grid.get_node("path_width").value = 0.5
	check(is_equal_approx(pv.get_child(0).mesh.top_radius, 0.25), "panel: path width")
	pt.reset_look()
	check(pt.TrackPreview.SETTINGS.all(func(st): return pt.TrackPreview.value(st[0]) == st[2]) and pv.get_child(pv.get_child_count() - 1).mesh is SphereMesh, "Reset to defaults")
	_click(pt, Vector3(20, 5, 0), true) # Shift: vertical plane facing the camera
	var a: PackedVector3Array = pt._anchors
	check(a.size() == 3 and a[0].distance_to(Vector3(-3, 1, 0)) < 0.01 and a[1].distance_to(Vector3(20, 1, 0)) < 0.01 and a[2].distance_to(Vector3(20, 5, 0)) < 0.01, "anchors: on the reference, free, free raised with Shift: %s" % [a])
	check(pt._status.text.begins_with("3 anchors"), "toolbar counts the anchors")
	_key(pt, KEY_ESCAPE)
	check(not pt._placing and _tracks(self).is_empty(), "Esc cancels, nothing built")
	await frames(1)
	check(not is_instance_valid(pv), "and the preview goes away")
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
	check(pt._preview == null, "finishing removes the preview")
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
	await frames(1)
	check(pt._tracks.text == "Tracks (1)", "toolbar counts the tracks (%s)" % pt._tracks.text)

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
	var tmenu: PopupMenu = pt._tracks.get_popup()
	tmenu.about_to_popup.emit()
	var ti := _item_for(tmenu, inst)
	check(ti >= 0 and tmenu.get_item_text(ti) == "Lift Group/Track", "Tracks menu lists each track under its group")
	tmenu.index_pressed.emit(ti)
	await frames(1)
	check(EditorInterface.get_selection().get_selected_nodes() == [inst], "picking a track selects it")

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

	# remove a track from the Tracks menu (selected through its path), then undo
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(path)
	await frames(1)
	tmenu.about_to_popup.emit()
	var trm := _remove_item(tmenu)
	check(trm >= 0 and tmenu.get_item_metadata(trm) == [inst], "Remove selected tracks offers the track holding the selected path")
	tmenu.index_pressed.emit(trm)
	await frames(1)
	check(inst.get_parent() == null and pt._tracks.text == "Tracks (0)", "track removed, count updated")
	hist.undo()
	await frames(1)
	check(inst.get_parent() == self and [inst, path, plat, plat.shapes()[0], seq].all(func(n): return n.owner == self) and pt._tracks.text == "Tracks (1)", "undo restores the track and everything in it")

	# closing a loop: click the first anchor again (3+ placed)
	EditorInterface.get_selection().clear()
	await frames(1)
	pt.start_track()
	var loop_pts := [Vector3(12, 0, 0), Vector3(20, 0, 0), Vector3(16, 0, -6)]
	for q in loop_pts:
		_click(pt, q)
	_move(pt, Vector3(12.05, 0, 0.05)) # a hair off the first anchor
	check(pt._hover.get("closes", false) and pt._hover.position.distance_to(loop_pts[0]) < 0.01, "near the first anchor the cursor snaps onto it")
	var pvc: Node3D = pt._preview
	check(pvc.get_child(pvc.get_child_count() - 1).material_override.albedo_color.is_equal_approx(pt.TrackPreview.value("close_color")), "and takes the close colour")
	_click(pt, Vector3(12.05, 0, 0.05))
	var lt: Node = EditorInterface.get_selection().get_selected_nodes()[0]
	check(not pt._placing and lt is PlatformTrackInstance and lt != inst, "clicking it builds the track")
	var lpath: Path3D = lt.paths()[0]
	check(lpath.curve.closed and lpath.curve.point_count == 3, "a closed path, 3 points (no duplicate of the first)")
	check(lt.platform().repeat == MovingPlatform.Repeat.RESTART and lt.platform().get_node("Sequence").laps == 1, "a loop: 1 lap, restart (round and round)")
	await frames(2)
	var lg := _ghosts(lt)
	check(lg.size() == 1 and lg[0].global_position.distance_to(loop_pts[0]) < 0.01, "a loop's ghost sits where a lap ends: its start")
	pt.start_track()
	_click(pt, Vector3(12, 0, 10))
	_click(pt, Vector3(20, 0, 10))
	_click(pt, Vector3(12, 0, 10))
	check(pt._placing and pt._anchors.size() == 3, "with only 2 anchors, the first one is just another anchor")
	pt.cancel_track()
	pt.start_track()
	pt._anchors = PackedVector3Array([Vector3(30, 0, 0), Vector3(36, 0, 0), Vector3(33, 0, 5), Vector3(30.1, 0, 0)])
	var et: PlatformTrackInstance = pt.finish_track()
	check(et.paths()[0].curve.closed and et.paths()[0].curve.point_count == 3, "Enter with the last anchor 0.1 m from the first: closed")
	await frames(1)
	check(pt._tracks.text == "Tracks (3)", "three tracks counted")

	var extra := MovingPlatform.new()
	inst.add_child(extra)
	check(not inst._get_configuration_warnings().is_empty(), "two platforms in a track: warning")
	extra.free()
	pt._toggle.button_pressed = false
	check(not pt._tools.visible, "edit mode off hides the tools")
	for k: String in prefs:
		pt.TrackPreview.set_value(k, prefs[k])
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


## Index of the menu entry for `node` (-1 if missing).
func _item_for(menu: PopupMenu, node: Node) -> int:
	for i in menu.item_count:
		var m: Variant = menu.get_item_metadata(i)
		if m is Node and m == node:
			return i
	return -1


## Index of the "Remove selected" entry (its metadata is the list to remove).
func _remove_item(menu: PopupMenu) -> int:
	for i in menu.item_count:
		if menu.get_item_metadata(i) is Array:
			return i
	return -1


func _move(pt, at: Vector3, shift := false) -> void:
	_aim()
	var e := InputEventMouseMotion.new()
	e.shift_pressed = shift
	e.position = cam.unproject_position(at)
	pt._forward_3d_gui_input(cam, e)


func seg_alpha(pv: Node3D) -> float:
	return pv.get_child(0).material_override.albedo_color.a


func _key(pt, key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	pt._forward_3d_gui_input(cam, e)


func _tracks(parent: Node) -> Array:
	return parent.get_children().filter(func(c): return c is PlatformTrackInstance)


func _ghosts(inst: Node) -> Array:
	return inst.get_children(true).filter(func(c): return c.get_index(true) >= inst.get_child_count() and c is Node3D and not c is Path3D and not c is MovingPlatform)
