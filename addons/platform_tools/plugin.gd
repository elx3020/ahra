@tool
extends EditorPlugin
## Platform edit mode: a "Platform Edit" toggle in the 3D toolbar. While it is on the toolbar shows
## - Shape Ref: adds a ShapeReference (pick its shape) that track anchors snap onto;
## - New Track: click anchors in the viewport (on a ShapeReference's surface, else on a plane
##   through the last anchor: horizontal, or vertical facing the camera with Shift), Enter or
##   Finish to build a PlatformTrackInstance (2+ anchors), Esc or Cancel to drop it;
## - Group: shown while tracks are selected; names a new PlatformTrackGroup and moves them in.
## Every change is undoable.

const SHAPES := {
	Box = &"BoxShape3D",
	Sphere = &"SphereShape3D",
	Capsule = &"CapsuleShape3D",
	Cylinder = &"CylinderShape3D",
}
const REF_SCALE := 4.0 ## shape references start this many times Godot's default shape size
const PLATFORM_SIZE := Vector3(3, 0.5, 3) ## a new track's platform: a box this size...
const LOOP_LAPS := 2 ## ...on a loop sequence: out and back

# toolbar controls, made in _build_toolbar (member defaults would leak on a script reload)
var _bar: HBoxContainer
var _toggle: Button
var _tools: HBoxContainer
var _status: Label
var _finish: Button
var _cancel: Button
var _group: Button
var _group_popup: PopupPanel
var _group_name: LineEdit

var _placing := false
var _anchors := PackedVector3Array()
var _hover := {} ## where a click would put the next anchor: {position, snapped}
var _camera: Camera3D ## the viewport camera of the last input event (for the overlay)


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	_build_toolbar()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	EditorInterface.get_selection().selection_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	cancel_track()
	EditorInterface.get_selection().selection_changed.disconnect(_refresh)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.queue_free()


func _build_toolbar() -> void:
	_bar = HBoxContainer.new()
	_toggle = Button.new()
	_tools = HBoxContainer.new()
	_status = Label.new()
	_finish = Button.new()
	_cancel = Button.new()
	_group = Button.new()
	_group_popup = PopupPanel.new()
	_group_name = LineEdit.new()
	_toggle.text = "Platform Edit"
	_toggle.toggle_mode = true
	_toggle.icon = _icon(&"Path3D")
	_toggle.toggled.connect(func(on: bool) -> void:
		if not on:
			cancel_track()
		_refresh())
	_bar.add_child(_toggle)
	_bar.add_child(_tools)

	var refs := MenuButton.new()
	refs.text = "Shape Ref"
	refs.flat = false
	refs.icon = _icon(&"CollisionShape3D")
	for kind: String in SHAPES:
		refs.get_popup().add_icon_item(_icon(SHAPES[kind]), kind)
	refs.get_popup().index_pressed.connect(func(i: int) -> void: add_shape_reference(SHAPES.keys()[i]))
	_tools.add_child(refs)

	var track := Button.new()
	track.text = "New Track"
	track.icon = _icon(&"Curve3D")
	track.pressed.connect(start_track)
	_tools.add_child(track)
	_tools.add_child(_status)
	_finish.text = "Finish"
	_finish.pressed.connect(finish_track)
	_tools.add_child(_finish)
	_cancel.text = "Cancel"
	_cancel.pressed.connect(cancel_track)
	_tools.add_child(_cancel)

	_group.text = "Group..."
	_group.icon = _icon(&"Groups")
	_group.pressed.connect(func() -> void:
		_group_name.text = "TrackGroup"
		_group_popup.popup(Rect2i(Vector2i(_group.get_screen_position() + Vector2(0, _group.size.y)), Vector2i(240, 0)))
		_group_name.grab_focus()
		_group_name.select_all())
	_tools.add_child(_group)
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "Name of the new group"
	box.add_child(label)
	_group_name.text_submitted.connect(func(_t: String) -> void: _create_group_from_popup())
	box.add_child(_group_name)
	var create := Button.new()
	create.text = "Create Group"
	create.pressed.connect(_create_group_from_popup)
	box.add_child(create)
	_group_popup.add_child(box)
	_bar.add_child(_group_popup)


func _refresh() -> void:
	_tools.visible = _toggle.button_pressed
	_status.visible = _placing
	_finish.visible = _placing
	_cancel.visible = _placing
	_status.text = "%d anchor%s" % [_anchors.size(), "" if _anchors.size() == 1 else "s"]
	_group.visible = not _placing and not selected_tracks().is_empty()


# --- shape references ---

## Adds a ShapeReference with a `kind` shape where the view centre meets the ground (y 0).
func add_shape_reference(kind: String) -> ShapeReference:
	var root := EditorInterface.get_edited_scene_root()
	var ref := ShapeReference.new()
	ref.name = kind + "Ref"
	var cs := CollisionShape3D.new()
	cs.name = kind
	cs.shape = ClassDB.instantiate(SHAPES[kind])
	for p in [&"size", &"height", &"radius"]: # height first: a capsule grows its height to fit a radius
		if p in cs.shape:
			cs.shape.set(p, cs.shape.get(p) * REF_SCALE)
	cs.shape.resource_local_to_scene = true
	ref.add_child(cs)
	var at := _view_centre()
	ref.position = root.to_local(at) if root is Node3D else at
	_add(root, ref, "Add %s shape reference" % kind)
	return ref


func _view_centre() -> Vector3:
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var mid := Vector2(EditorInterface.get_editor_viewport_3d(0).size) * 0.5
	var from := cam.project_ray_origin(mid)
	var dir := cam.project_ray_normal(mid)
	var p: Variant = Plane.PLANE_XZ.intersects_ray(from, dir)
	return p if p != null and from.distance_to(p) < 200.0 else from + dir * 10.0


# --- new track ---

func start_track() -> void:
	_placing = true
	_anchors.clear()
	_hover = {}
	_refresh()
	update_overlays()


func cancel_track() -> void:
	_placing = false
	_anchors.clear()
	_hover = {}
	_refresh()
	update_overlays()


## Builds the track from the anchors placed so far (2+), else just ends placing.
func finish_track() -> PlatformTrackInstance:
	var points := _anchors.duplicate()
	cancel_track()
	return create_track(points) if points.size() >= 2 else null


## A PlatformTrackInstance at points[0]: a Path3D through `points`, and a box platform on a
## loop sequence along it. It goes into the selected group, if any, else the scene root.
func create_track(points: PackedVector3Array) -> PlatformTrackInstance:
	var root := EditorInterface.get_edited_scene_root()
	var parent: Node = _selected_group()
	if parent == null:
		parent = root
	var inst := PlatformTrackInstance.new()
	inst.name = "Track"
	var basis: Basis = parent.global_basis if parent is Node3D else Basis.IDENTITY
	var frame := Transform3D(basis, points[0]) # the instance's global transform once added
	inst.transform = parent.global_transform.affine_inverse() * frame if parent is Node3D else frame
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	for p in points:
		path.curve.add_point(frame.affine_inverse() * p)
	inst.add_child(path)
	var plat := MovingPlatform.new()
	plat.name = "Platform"
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	var box := BoxShape3D.new()
	box.size = PLATFORM_SIZE
	box.resource_local_to_scene = true
	cs.shape = box
	plat.add_child(cs)
	var seq := PlatformSequence.new()
	seq.name = "Sequence"
	seq.path = path
	seq.laps = LOOP_LAPS
	plat.add_child(seq)
	inst.add_child(plat)
	_add(parent, inst, "Add platform track")
	return inst


## Viewport input while placing anchors (forwarding is always on, whatever is selected).
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _placing:
		return AFTER_GUI_INPUT_PASS
	_camera = camera
	if event is InputEventMouseMotion:
		_hover = pick(camera, event.position, event.shift_pressed)
		update_overlays()
		return AFTER_GUI_INPUT_PASS # keep camera navigation
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_anchors.append(pick(camera, event.position, event.shift_pressed).position)
			_refresh()
			update_overlays()
		return AFTER_GUI_INPUT_STOP # no selection clicks while placing
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_track()
			return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			finish_track()
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## Where a click at `screen` puts an anchor: the nearest ShapeReference surface under the
## mouse, else a plane through the last anchor (y 0 for the first): horizontal, or with
## `vertical` upright and facing the camera, to raise or lower the track.
func pick(camera: Camera3D, screen: Vector2, vertical: bool) -> Dictionary:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var best := {}
	for ref in camera.get_tree().get_nodes_in_group(ShapeSet.GROUP):
		if ref is ShapeReference:
			var hit: Dictionary = ref.cast(from, dir)
			if not hit.is_empty() and (best.is_empty() or from.distance_to(hit.position) < from.distance_to(best.position)):
				best = hit
	if not best.is_empty():
		return {position = best.position, snapped = true}
	var through := _anchors[-1] if not _anchors.is_empty() else Vector3.ZERO
	var normal := Vector3.UP
	if vertical and not _anchors.is_empty():
		var facing := Vector3(dir.x, 0, dir.z)
		normal = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	var p: Variant = Plane(normal, through).intersects_ray(from, dir)
	return {position = p if p != null else from + dir * 10.0, snapped = false}


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _placing or _camera == null:
		return
	var pts := Array(_anchors)
	if not _hover.is_empty():
		pts.append(_hover.position)
	for i in range(1, pts.size()):
		if not _camera.is_position_behind(pts[i - 1]) and not _camera.is_position_behind(pts[i]):
			overlay.draw_line(_camera.unproject_position(pts[i - 1]), _camera.unproject_position(pts[i]), Color(1, 1, 1, 0.8), 2.0)
	for p in _anchors:
		if not _camera.is_position_behind(p):
			overlay.draw_circle(_camera.unproject_position(p), 5.0, Color.WHITE)
	if not _hover.is_empty() and not _camera.is_position_behind(_hover.position):
		overlay.draw_circle(_camera.unproject_position(_hover.position), 6.0, Color(0.3, 1, 0.4) if _hover.snapped else Color(1, 0.85, 0.2))
	var font := overlay.get_theme_default_font()
	overlay.draw_string(font, Vector2(16, overlay.size.y - 20), "New track: %d anchors. Click: add (snaps to shape references; Shift: vertical plane). Enter: finish. Esc: cancel." % _anchors.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


# --- groups ---

## The PlatformTrackInstances selected, directly or through one of their children.
func selected_tracks() -> Array[PlatformTrackInstance]:
	var out: Array[PlatformTrackInstance] = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		while n and not n is PlatformTrackInstance:
			n = n.get_parent()
		if n and not out.has(n):
			out.append(n)
	return out


## The group that is selected, or that holds something selected.
func _selected_group() -> PlatformTrackGroup:
	for n in EditorInterface.get_selection().get_selected_nodes():
		while n and not n is PlatformTrackGroup:
			n = n.get_parent()
		if n:
			return n
	return null


func _create_group_from_popup() -> void:
	_group_popup.hide()
	create_group(_group_name.text)


## Moves the selected tracks into a new PlatformTrackGroup named `group_name`, centred on them,
## under the first track's parent. Tracks keep their place in the world.
func create_group(group_name: String) -> PlatformTrackGroup:
	var tracks := selected_tracks()
	if tracks.is_empty():
		return null
	var group := PlatformTrackGroup.new()
	group.name = group_name.strip_edges().validate_node_name() if group_name.strip_edges() else "TrackGroup"
	var centre := Vector3.ZERO
	for t in tracks:
		centre += t.global_position
	centre /= tracks.size()
	var homes := tracks.map(func(t: Node) -> Array: return [t, t.get_parent(), t.get_index()])
	homes.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Group %d platform tracks" % tracks.size(), UndoRedo.MERGE_DISABLE, tracks[0])
	ur.add_do_method(self, &"_group_in", tracks[0].get_parent(), group, tracks, centre, EditorInterface.get_edited_scene_root())
	ur.add_do_reference(group)
	ur.add_undo_method(self, &"_group_out", group, homes)
	ur.commit_action()
	_select(group)
	return group


func _group_in(parent: Node, group: PlatformTrackGroup, tracks: Array, centre: Vector3, root: Node) -> void:
	parent.add_child(group, true)
	group.owner = root
	group.global_position = centre
	for t: Node in tracks:
		t.reparent(group) # keeps its global transform and its owner


func _group_out(group: PlatformTrackGroup, homes: Array) -> void:
	for h: Array in homes: # by original index, so moving each back restores the order
		h[0].reparent(h[1])
		h[1].move_child(h[0], h[2])
	group.get_parent().remove_child(group)


# --- helpers ---

## Undoable: adds `node` and the subtree built under it to `parent`, saved with the scene, and
## selects it. Only the nodes built here get saved, not what their scripts add in the editor.
func _add(parent: Node, node: Node, action: String) -> void:
	var built := [node] + node.find_children("*", "", true, false)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, parent)
	ur.add_do_method(self, &"_attach", parent, node, built, EditorInterface.get_edited_scene_root())
	ur.add_do_reference(node)
	ur.add_undo_method(parent, &"remove_child", node)
	ur.commit_action()
	_select(node)


func _attach(parent: Node, node: Node, built: Array, root: Node) -> void:
	parent.add_child(node, true)
	for n: Node in built:
		n.owner = root


func _select(node: Node) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


func _icon(name: StringName) -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(name, &"EditorIcons")
