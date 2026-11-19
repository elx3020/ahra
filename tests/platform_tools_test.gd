@tool
extends "res://tests/editor_test.gd"
## Editor-side test of the Platform Tools plugin: the toolbar's two icon menus (builder, selected
## tracks: Play in Editor, Group, Switch), shape references (plane
## included), placing a track's anchors with viewport input (snapped / free / vertical, Esc,
## Enter, too few anchors), the 3D preview and its settings panel, the built
## PlatformTrackInstance (open, or closed by clicking the first anchor), the Shape Refs / Tracks
## menus (counts, select, remove, undo), grouping and the group's view settings, the channel
## registry, adding a switch (channel picker, collisions refused), the inspector's channel
## dropdown, circuit mode (inspector checkbox, joined ends, new track into a circuit, Reconnect),
## grid snap, anchors dragged with the Path3D tools landing on references, and the timing preview.
## It changes the preview's editor settings and puts the user's values back at the end.
## Godot_console.exe --headless --path . -e res://tests/platform_tools_test.tscn -- --platform-tools-test

var cam: Camera3D


func _init() -> void:
	flag = "--platform-tools-test"
	label = "PLATFORM TOOLS"


func run() -> void:
	var pt = _find_plugin()
	check(pt != null, "Platform Track builder icon found")
	EditorInterface.get_selection().clear()
	await frames(1)
	check(pt._main.text == "" and _shown(pt) == [pt._main], "toolbar: just the builder icon (nothing selected, not placing)")
	check([&"Path3D", &"AnimatableBody3D", &"Play", &"Groups", &"Signals", &"Tools", &"Curve3D"].all(func(i): return EditorInterface.get_editor_theme().has_icon(i, &"EditorIcons")), "menu icons exist in the editor theme")
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
	var main: PopupMenu = _open(pt)
	check(main.get_item_text(0) == "Shape Refs (2)" and main.get_item_submenu_node(0) == pt._refs and main.get_item_text(1) == "Tracks (0)" and main.get_item_submenu_node(1) == pt._tracks, "builder menu: Shape Refs and Tracks submenus, counted (%s, %s)" % [main.get_item_text(0), main.get_item_text(1)])
	var rmenu: PopupMenu = pt._refs
	var cap_i := _item_for(rmenu, cap)
	check(cap_i >= 0 and rmenu.get_item_text(cap_i) == "CapsuleRef" and _item_for(rmenu, ref) >= 0, "Shape Refs menu lists each reference")
	rmenu.index_pressed.emit(cap_i)
	await frames(2)
	check(EditorInterface.get_selection().get_selected_nodes() == [cap] and EditorInterface.get_inspector().get_edited_object() == cap, "picking one selects it, the inspector edits it")
	_open(pt)
	var rm_i := _remove_item(rmenu)
	check(rm_i >= 0 and not rmenu.is_item_disabled(rm_i) and rmenu.get_item_metadata(rm_i) == [cap], "Remove selected offers the selected reference")
	rmenu.index_pressed.emit(rm_i)
	await frames(1)
	check(cap.get_parent() == null and _open(pt).get_item_text(0) == "Shape Refs (1)", "removed, count updated")
	hist.undo()
	await frames(1)
	check(cap.get_parent() == self and cap.owner == self and cap.shapes()[0].owner == self and _open(pt).get_item_text(0) == "Shape Refs (2)", "undo puts it back, saved with the scene")

	# --- placing anchors ---
	_aim()
	var hit: Dictionary = pt.pick(cam, cam.unproject_position(Vector3(-3, 1, 0)), false)
	check(hit.snapped and hit.position.distance_to(Vector3(-3, 1, 0)) < 0.01, "pick snaps onto the reference's surface")
	_open(pt)
	check(pt._tracks.get_item_text(0) == "New Track", "Tracks menu: New Track first")
	pt._tracks.index_pressed.emit(0)
	check(pt._placing and _shown(pt) == [pt._main, pt._status, pt._finish, pt._cancel], "New Track starts placing; the toolbar adds the anchor count, Finish and Cancel")
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
	main = _open(pt)
	check(main.get_item_text(main.item_count - 1) == "Preview Settings...", "builder menu: Preview Settings last")
	main.index_pressed.emit(main.item_count - 1)
	check(pt._look_popup.visible, "it opens the settings panel")
	var swatch: ColorPickerButton = pt._look_grid.get_node("path_color")
	check(pt._look_grid.get_child_count() == pt.TrackPreview.SETTINGS.size() * 2 and swatch.edit_alpha, "panel: a row per setting, colours with alpha")
	swatch.color_changed.emit(Color(1, 0, 0, 0.5))
	check(pt.TrackPreview.value("path_color") == Color(1, 0, 0, 0.5) and pv.get_child(0).material_override.albedo_color.r == 1.0 and pv.get_child(0).material_override.albedo_color.g == 0.0, "panel: picking a colour saves it and recolours the preview")
	pt._look_grid.get_node("path_width").value = 0.5
	check(is_equal_approx(pv.get_child(0).mesh.top_radius, 0.25), "panel: path width")
	pt.reset_look()
	check(pt.TrackPreview.SETTINGS.all(func(st): return pt.TrackPreview.value(st[0]) == st[2]) and pv.get_child(pv.get_child_count() - 1).mesh is SphereMesh, "Reset to defaults")
	pt._look_popup.hide()
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
	var seq: PlatformSequence = inst.sequences[0]
	check(inst.global_position.distance_to(pts[0]) < 0.01 and inst.path() == path, "instance sits at the first anchor, one path")
	check(path.curve.point_count == 3 and range(3).all(func(i): return path.to_global(path.curve.get_point_position(i)).distance_to(pts[i]) < 0.01), "path runs through the anchors")
	check(plat.shapes().size() == 1 and plat.shapes()[0].shape is BoxShape3D and plat.shapes()[0].shape.size == Vector3(3, 0.5, 3), "default box platform")
	check(inst.sequences.size() == 1 and seq.start_anchor == 0 and seq.end_anchor == 2 and seq.round_trip and seq.trips == 0, "one sequence: round trips between the first and last anchor, forever")
	check([inst, path, plat, plat.shapes()[0]].all(func(n): return n.owner == self), "all of it saved with the scene")
	check(inst._get_configuration_warnings().is_empty(), "no configuration warnings")
	check(EditorInterface.get_selection().get_selected_nodes() == [inst], "new track is selected")
	await frames(3)
	check(plat.global_position.distance_to(pts[0]) < 0.01, "platform waits at the first anchor")
	var ghosts := _ghosts(inst)
	check(ghosts.size() == 1 and ghosts[0].global_position.distance_to(pts[2]) < 0.01, "ghost platform at the path's end")
	hist.undo()
	check(_tracks(self).is_empty(), "undo removes the track")
	hist.redo()
	check(_tracks(self) == [inst] and inst.owner == self and inst.sequences == [seq], "redo brings it back")
	await frames(1)
	check(_open(pt).get_item_text(1) == "Tracks (1)", "builder menu counts the tracks (%s)" % _open(pt).get_item_text(1))

	# --- editing the path: an anchor dragged with the Path3D tools lands on the reference under it ---
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(path)
	await frames(1)
	_aim()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	pt._forward_3d_gui_input(cam, down) # the Path3D editor grabs anchor 1...
	var keep2 := path.curve.get_point_position(2)
	path.curve.set_point_position(1, path.to_local(Vector3(1, 8, 12.5))) # ...and drags it, in the air, with the box's top (2, 1, 0) behind it
	var landed := path.to_global(path.curve.get_point_position(1))
	check(landed.distance_to(Vector3(2, 1, 0)) < 0.02 and path.curve.get_point_position(2) == keep2, "a dragged anchor lands on the reference under it (%s), the others stay" % landed)
	var up := down.duplicate()
	up.pressed = false
	pt._forward_3d_gui_input(cam, up)
	path.curve.set_point_position(1, path.to_local(pts[1]))
	check(path.to_global(path.curve.get_point_position(1)).distance_to(pts[1]) < 0.01, "button up: edits stay as made (inspector, undo)")

	# --- grid snap ---
	var grid_i := -1
	main = _open(pt)
	for i in main.item_count:
		if main.get_item_text(i).begins_with("Snap to Grid"):
			grid_i = i
	check(grid_i >= 0 and not main.is_item_checked(grid_i), "builder menu: Snap to Grid, off")
	main.index_pressed.emit(grid_i)
	check(pt.TrackPreview.value("grid_snap") and _open(pt).is_item_checked(grid_i), "picking it turns it on")
	var on_ref: Dictionary = pt.pick(cam, cam.unproject_position(Vector3(-2.7, 1, 0.3)), false)
	check(on_ref.position.distance_to(Vector3(-3, 1, 0)) < 0.01, "on a reference: the nearest grid point, still on its surface (%s)" % on_ref.position)
	var loose: Dictionary = pt.pick(cam, cam.unproject_position(Vector3(20.3, 0, 0.4)), false)
	check(loose.position.distance_to(Vector3(20, 0, 0)) < 0.01, "free: the nearest grid point on its plane (%s)" % loose.position)
	pt.set_look("grid_step", 0.5)
	loose = pt.pick(cam, cam.unproject_position(Vector3(20.3, 0, 0.4)), false)
	check(loose.position.distance_to(Vector3(20.5, 0, 0.5)) < 0.01, "grid step from the settings (0.5 m)")
	pt._forward_3d_gui_input(cam, down)
	path.curve.set_point_position(2, path.to_local(Vector3(20.2, 5.1, 0.1))) # dragged in the air, nothing under it
	check(path.to_global(path.curve.get_point_position(2)).distance_to(Vector3(20, 5, 0)) < 0.01, "a dragged anchor snaps to the grid too")
	pt._forward_3d_gui_input(cam, up)
	path.curve.set_point_position(2, keep2)
	pt.set_look("grid_snap", false)
	pt.set_look("grid_step", 1.0)

	# --- group ---
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(plat) # its platform: still counts as the track
	await frames(2)
	check(pt._track_menu.visible and pt._track_menu.text == "", "track menu icon shows when a track (or a part of it) is selected")
	var acts: PopupMenu = pt._track_menu.get_popup()
	check(range(acts.item_count).map(func(i): return acts.get_item_text(i)) == ["Play in Editor", "Group...", "Switch...", "Reconnect"], "track menu: Play in Editor, Group, Switch, Reconnect")
	acts.about_to_popup.emit()
	check(not acts.is_item_checked(0) and not inst.preview, "not playing yet")
	acts.index_pressed.emit(0)
	acts.about_to_popup.emit()
	check(inst.preview and acts.is_item_checked(0), "Play in Editor: on, checked")
	var was := plat.global_position
	await get_tree().create_timer(1.2).timeout # longer than a lap wait
	await physics_frames(2)
	check(plat.global_position.distance_to(was) > 0.05, "the platform moves in the editor")
	acts.index_pressed.emit(0)
	check(not inst.preview, "picking it again stops it")
	hist.undo()
	check(inst.preview, "undoable")
	hist.undo()
	check(not inst.preview, "back to not playing")
	EditorInterface.get_selection().clear()
	await frames(2)
	check(not pt._track_menu.visible, "and hides without one")
	EditorInterface.get_selection().add_node(inst)
	await frames(2)
	var before := inst.global_transform
	acts.index_pressed.emit(1)
	check(pt._group_popup.visible and pt._group_name.text == "TrackGroup", "Group... asks for the group's name")
	pt._group_popup.hide()
	var group: PlatformTrackGroup = pt.create_group("Lift Group")
	check(group.name == &"Lift Group" and group.owner == self and group.get_parent() == self, "group created with its name")
	check(inst.get_parent() == group and inst.owner == self and inst.global_transform.is_equal_approx(before), "track moved in, same place in the world")
	check(group.global_position.distance_to(before.origin) < 0.01, "group centred on its tracks")
	group.show_paths = false
	group.show_destination = false
	group.preview = true
	await frames(2)
	check(not path.visible and _ghosts(inst).is_empty() and inst._previewing(), "group hides paths and ghosts, previews its tracks")
	group.show_paths = true
	group.show_destination = true
	group.preview = false
	await frames(2)
	check(path.visible and _ghosts(inst).size() == 1 and not inst._previewing(), "and back")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(inst)
	await frames(1)
	acts.index_pressed.emit(0)
	await physics_frames(2)
	check(inst.preview and not group.preview, "Play in Editor on a grouped track plays that track")
	hist.undo()
	await physics_frames(2)
	check(not inst.preview, "undo")
	var tmenu: PopupMenu = pt._tracks
	_open(pt)
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
	_open(pt)
	var trm := _remove_item(tmenu)
	check(trm >= 0 and tmenu.get_item_metadata(trm) == [inst], "Remove selected tracks offers the track holding the selected path")
	tmenu.index_pressed.emit(trm)
	await frames(1)
	check(inst.get_parent() == null and _open(pt).get_item_text(1) == "Tracks (0)", "track removed, count updated")
	hist.undo()
	await frames(1)
	check(inst.get_parent() == self and [inst, path, plat, plat.shapes()[0], ].all(func(n): return n.owner == self) and inst.sequences == [seq] and _open(pt).get_item_text(1) == "Tracks (1)", "undo restores the track and everything in it")

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
	var lpath: Path3D = lt.path()
	check(lpath.curve.closed and lpath.curve.point_count == 3, "a closed path, 3 points (no duplicate of the first)")
	var lq: PlatformSequence = lt.sequences[0]
	check(lq.start_anchor == 0 and lq.end_anchor == 0 and not lq.round_trip and lq.trips == 0, "a loop: a full lap one way, forever (round and round)")
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
	check(et.path().curve.closed and et.path().curve.point_count == 3, "Enter with the last anchor 0.1 m from the first: closed")
	await frames(1)
	check(_open(pt).get_item_text(1) == "Tracks (3)", "three tracks counted")

	# --- channel registry ---
	var reg: GDScript = load("res://addons/platform_tools/channel_registry.gd")
	var known: Dictionary = reg.channels()
	check(known.has("remote") and known["remote"].any(func(f): return f.ends_with("platforms_a.tscn")) and known["remote"].any(func(f): return f.ends_with("platforms_b.tscn")), "registry: channels of the saved scenes, with the scenes that use them")
	check(reg.unique("remote", known) == "remote_2" and reg.unique("My Lift", known) == "my_lift" and reg.unique("2 fast", known).is_valid_ascii_identifier(), "registry: free, identifier-safe name suggestions")
	check(reg.problem("remote", known).contains("platforms_a.tscn") and reg.problem("2fast", known) != "" and reg.problem("", known) != "" and reg.problem("fresh_one", known) == "", "registry: a taken, malformed or empty new name is refused")

	# --- adding a switch ---
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(plat)
	await frames(1)
	check(inst.channel == &"" and inst.starts_on, "a new track starts on the world clock")
	acts.index_pressed.emit(2)
	check(pt._switch_popup.visible, "Switch... opens the switch popup")
	var picker = pt._switch_picker
	check(picker.is_new() and picker.value() == StringName(reg.unique("Track", known)) and picker.valid(), "no channel yet: a new channel, named after the track (%s)" % picker.value())
	picker._name.text = "remote"
	picker._name.text_changed.emit("remote")
	check(not picker.valid() and pt._switch_add.disabled and picker._note.text.contains("platforms_a.tscn"), "a name used elsewhere is refused, saying where")
	picker._name.text = "lift_test"
	picker._name.text_changed.emit("lift_test")
	check(picker.valid() and not pt._switch_add.disabled, "a free name is accepted")
	pt._switch_action.select(PlatformSwitch.Action.REVERSE)
	pt._switch_starts.button_pressed = false
	pt._switch_add.pressed.emit()
	var sw: Node = EditorInterface.get_selection().get_selected_nodes()[0]
	check(sw is PlatformSwitch and sw.get_parent() == inst and sw.name == &"ReverseSwitch" and sw.channel == &"lift_test" and sw.action == PlatformSwitch.Action.REVERSE, "switch added to the track, with its channel and action")
	check(sw.owner == self and sw.shapes().size() == 1 and sw.shapes()[0].owner == self and sw.shapes()[0].shape.size == Vector3(2, 2, 2), "switch saved with the scene, a 2 m box zone")
	check(sw.global_position.distance_to(plat.global_position + Vector3(0, 1, 3)) < 0.01, "placed beside the platform's start")
	check(inst.channel == &"lift_test" and not inst.starts_on, "the track joins the channel and waits for the switch")
	check(reg.channels().has("lift_test"), "the new channel is in the registry (open scene, unsaved)")
	hist.undo()
	check(sw.get_parent() == null and inst.channel == &"" and inst.starts_on, "undo: switch gone, track back on the world clock")
	hist.redo()
	check(sw.get_parent() == inst and inst.channel == &"lift_test", "redo")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(lt)
	await frames(1)
	acts.index_pressed.emit(2)
	var shared := -1
	for i in picker._options.item_count:
		if picker._options.get_item_metadata(i) is String and picker._options.get_item_metadata(i) == "lift_test":
			shared = i
	check(shared >= 0 and picker._options.get_item_text(shared).contains(scene_file_path.get_file()), "the dropdown lists the new channel, with the scene using it")
	picker._options.select(shared)
	picker._options.item_selected.emit(shared)
	check(picker.valid() and picker.value() == &"lift_test", "picking an existing channel shares it on purpose")
	pt._switch_add.pressed.emit()
	check(lt.channel == &"lift_test", "second track on the same channel")

	# --- the inspector's channel dropdown ---
	EditorInterface.get_selection().clear() # a fresh inspector (it refreshes shown values on a timer)
	await frames(1)
	EditorInterface.edit_node(lt)
	await frames(3)
	var prop: EditorProperty = null
	var stack: Array[Node] = [EditorInterface.get_inspector()]
	while stack:
		var n: Node = stack.pop_back()
		if n.get_script() == load("res://addons/platform_tools/channel_property.gd"):
			prop = n
		stack.append_array(n.get_children())
	check(prop != null and prop.get_edited_property() == &"channel", "inspector: a track's channel is the channel dropdown")
	var opts: OptionButton = prop._picker._options
	check(opts.get_selected_metadata() == "lift_test" and opts.get_item_metadata(0) == "", "it shows the current channel, and (none) for tracks")
	opts.select(0)
	opts.item_selected.emit(0)
	await frames(1)
	check(lt.channel == &"", "picking (none) clears the channel")
	hist.undo()
	check(lt.channel == &"lift_test", "through the inspector, so undoable")

	# --- previewing all platforms: one clock ---
	_open(pt)
	check(pt._tracks.get_item_text(1) == "Preview All Platforms" and not pt._tracks.is_item_checked(1), "Tracks menu: Preview All Platforms")
	pt._tracks.index_pressed.emit(1)
	check(PlatformProgram.editor_clock == 0.0 and pt._timing.visible and pt._timing_mode.get_selected_id() == pt.MANUAL and pt._timing_label.text == "0.00 s", "on: every track on one clock from 0, manual by default")
	pt._timing_slider.value = 2.0
	await physics_frames(2)
	check(PlatformProgram.editor_clock == 2.0 and pt._timing_label.text == "2.00 s" and [lt, et, inst].all(func(t): return t.platform().global_position.distance_to(t.point_at(2.0 + t.offset)) < 0.01), "manual: the slider sets the clock, every platform shows where it is at 2 s")
	pt._timing_mode.select(pt.AUTOMATIC)
	var clock0 := PlatformProgram.editor_clock
	await get_tree().create_timer(0.5).timeout
	check(PlatformProgram.editor_clock > clock0 + 0.3 and pt._timing_label.text == "%.2f s" % PlatformProgram.editor_clock and absf(pt._timing_slider.value - PlatformProgram.editor_clock) < 0.011, "automatic: the clock runs, time shown")
	_open(pt)
	check(pt._tracks.is_item_checked(1), "the menu shows it on")
	pt._tracks.index_pressed.emit(1)
	check(PlatformProgram.editor_clock < 0.0 and not pt._timing.visible, "picking it again: off, tracks back to their own preview")
	pt._timing_mode.select(pt.MANUAL)

	# --- circuit mode ---
	EditorInterface.get_selection().clear()
	await frames(1)
	var ca: PlatformTrackInstance = pt.create_track(PackedVector3Array([Vector3(0, 0, 30), Vector3(8, 0, 30)]))
	EditorInterface.get_selection().clear()
	var cb: PlatformTrackInstance = pt.create_track(PackedVector3Array([Vector3(9, 0, 30), Vector3(9, 0, 38)])) # starts 1 m from A's end
	var ca_plat := ca.platform()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(ca)
	EditorInterface.get_selection().add_node(cb)
	await frames(1)
	var cg: PlatformTrackGroup = pt.create_group("Line")
	cg.after_last = PlatformProgram.End.PLAY_BACKWARDS # an open circuit: the last end doesn't join the first start
	EditorInterface.edit_node(cg)
	await frames(3)
	var cprop: EditorProperty = null
	stack = [EditorInterface.get_inspector()]
	while stack:
		var n: Node = stack.pop_back()
		if n.get_script() == load("res://addons/platform_tools/plugin.gd").CircuitProperty:
			cprop = n
		stack.append_array(n.get_children())
	check(cprop != null and not cg.circuit and not ca.get_property_list().filter(func(d): return d.name == "channel")[0].usage & PROPERTY_USAGE_EDITOR == 0, "inspector: the group's circuit checkbox; tracks show their own timing")
	cprop._check.button_pressed = true
	await physics_frames(2)
	check(cg.circuit and cg.platform() == ca_plat and ca.platform() == ca_plat and cb.platform() == ca_plat and cb.get_children().filter(func(c): return c is MovingPlatform).is_empty() and ca_plat.owner == self, "circuit on: the first track's platform rides both, the other one goes")
	check([ca, cb].all(func(t): return t.sequences.size() == 1 and t.sequences[0].trips == 1 and not t.sequences[0].round_trip and t.sequences[0].end_anchor == 1), "each track runs once, first anchor to last")
	check(ca.last_point().distance_to(Vector3(8.5, 0, 30)) < 0.01 and cb.first_point().distance_to(Vector3(8.5, 0, 30)) < 0.01, "neighbouring ends meet halfway")
	check(ca._get_configuration_warnings().is_empty() and cb._get_configuration_warnings().is_empty() and cg._get_configuration_warnings().is_empty(), "no warnings")
	check(ca.get_property_list().filter(func(d): return d.name == "channel")[0].usage & PROPERTY_USAGE_EDITOR == 0 and not ca.plays() and cg.plays(), "the timing settings are the group's now")
	var mid := cg.point_at(cg._plan[0][0] + cg._plan[1][0] + cg._plan[2][0] + cg._plan[3][0] + cg._plan[4][0] * 0.5)
	check(mid.distance_to(Vector3(8.75, 0, 34)) < 0.05, "the shared platform rides A, then B (%s)" % mid)
	hist.undo()
	await physics_frames(1)
	check(not cg.circuit and ca.platform() == ca_plat and cb.platform() != null and cb.platform() != ca_plat and ca.sequences[0].trips == 0 and ca.last_point().distance_to(Vector3(8, 0, 30)) < 0.01, "undo: own platforms, sequences and anchors back")
	hist.redo()
	await physics_frames(1)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(cg)
	await frames(1)
	var cc: PlatformTrackInstance = pt.create_track(PackedVector3Array([Vector3(10, 0, 39), Vector3(0, 0, 39)]))
	check(cc.get_parent() == cg and cc.platform() == ca_plat and cc.get_children().filter(func(c): return c is MovingPlatform).is_empty() and cc.sequences[0].trips == 1, "a new track in a circuit rides its platform, once along")
	check(cb.last_point().distance_to(cc.first_point()) < 0.01 and cc.first_point().distance_to(Vector3(9.5, 0, 38.5)) < 0.01, "and joins the previous track's end halfway")
	cb.path().curve.set_point_position(0, cb.path().curve.get_point_position(0) + Vector3(0, 0, 1))
	check(not ca._get_configuration_warnings().is_empty(), "a joint pulled apart: warning")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(ca)
	await frames(1)
	acts.about_to_popup.emit()
	check(acts.get_item_text(3) == "Reconnect" and not acts.is_item_disabled(3), "track menu: Reconnect for a circuit track")
	acts.index_pressed.emit(3)
	check(ca.last_point().distance_to(cb.first_point()) < 0.01 and ca._get_configuration_warnings().is_empty(), "Reconnect joins them again")
	acts.index_pressed.emit(0)
	check(cg.preview and not ca.preview, "Play in Editor on a circuit track plays the circuit")
	hist.undo()
	EditorInterface.edit_node(cg)
	await frames(3)
	stack = [EditorInterface.get_inspector()]
	while stack:
		var n: Node = stack.pop_back()
		if n.get_script() == load("res://addons/platform_tools/plugin.gd").CircuitProperty:
			cprop = n
		stack.append_array(n.get_children())
	cprop._check.button_pressed = false
	await physics_frames(1)
	check(not cg.circuit and [ca, cb, cc].all(func(t): return t.get_children().filter(func(c): return c is MovingPlatform).size() == 1 and t.platform().owner == self) and ca.platform() == ca_plat, "circuit off: each track has its own platform again")
	hist.undo()
	await physics_frames(1)
	check(cg.circuit and cg.platform() == ca_plat and cb.platform() == ca_plat, "undo: back to one shared platform")

	var extra := MovingPlatform.new()
	inst.add_child(extra)
	check(not inst._get_configuration_warnings().is_empty(), "two platforms in a track: warning")
	extra.free()
	EditorInterface.get_selection().clear()
	await frames(1)
	check(_shown(pt) == [pt._main], "nothing selected: back to just the builder icon")
	for k: String in prefs:
		pt.TrackPreview.set_value(k, prefs[k])
	finished = true


func _find_plugin() -> EditorPlugin:
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	while stack:
		var n: Node = stack.pop_back()
		if n is MenuButton and n.tooltip_text == "Platform Track builder":
			for c in n.get_popup().about_to_popup.get_connections():
				if c.callable.get_object() is EditorPlugin:
					return c.callable.get_object()
		stack.append_array(n.get_children())
	return null


## The builder menu, filled as when it opens.
func _open(pt) -> PopupMenu:
	pt._main.get_popup().about_to_popup.emit()
	return pt._main.get_popup()


## The toolbar controls showing.
func _shown(pt) -> Array:
	return pt._bar.get_children().filter(func(c): return c is Control and c.visible)


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
