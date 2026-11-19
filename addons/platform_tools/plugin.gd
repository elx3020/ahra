@tool
extends EditorPlugin
## Platform Track builder: one icon menu in the 3D toolbar with
## - Shape Refs (count): add a ShapeReference (pick its shape; Plane = an infinite plane) that
##   track anchors snap onto, pick one to select it (its inspector edits its shapes), or remove
##   the selected ones;
## - Tracks (count): New Track, then each track (pick one to select it), then remove the selected
##   ones. New Track: click anchors in the viewport (on a ShapeReference's surface, else on a
##   plane through the last anchor: horizontal, or vertical facing the camera with Shift), Enter
##   or Finish to build a PlatformTrackInstance (2+ anchors), Esc or Cancel to drop it. Clicking
##   the first anchor again (3+ placed) closes the loop and builds it. A 3D preview shows where
##   the next anchor goes and the path being drawn; the toolbar shows Finish / Cancel meanwhile;
## - Preview Settings: the preview's colours, opacity and look (saved in editor settings).
## While tracks are selected a second icon menu acts on them:
## - Play in Editor: their platforms move in the editor (a grouped track plays its whole group);
## - Group: names a new PlatformTrackGroup and moves them in;
## - Switch: adds a PlatformSwitch next to the track and puts the tracks' platforms on its
##   channel, picked from the channel registry or a new name that can't collide with one used
##   anywhere in the project.
## The inspector's `channel` field (platforms, switches) becomes the same channel dropdown.
## Every change is undoable.

const TrackPreview := preload("track_preview.gd")
const ChannelPicker := preload("channel_picker.gd")
const SWITCH_SIZE := Vector3(2, 2, 2) ## a new switch's zone

const SHAPES := {
	Box = &"BoxShape3D",
	Sphere = &"SphereShape3D",
	Capsule = &"CapsuleShape3D",
	Cylinder = &"CylinderShape3D",
	Plane = &"WorldBoundaryShape3D",
}
const REF_SCALE := 4.0 ## shape references start this many times Godot's default shape size
const PLATFORM_SIZE := Vector3(3, 0.5, 3) ## a new track's platform: a box this size...
const LOOP_LAPS := 2 ## ...on a loop sequence: out and back (a closed path: 1 lap, round and round)
const CLOSE_PIXELS := 12.0 ## the cursor this close to the first anchor (3+ placed) snaps there and closes the loop
const CLOSE_DISTANCE := 0.25 ## Enter with the last anchor this close (m) to the first also closes it

# toolbar controls, made in _build_toolbar (member defaults would leak on a script reload)
var _bar: HBoxContainer
var _main: MenuButton ## the Platform Track builder menu
var _refs: PopupMenu ## its Shape Refs submenu
var _ref_add: PopupMenu
var _tracks: PopupMenu ## its Tracks submenu
var _track_menu: MenuButton ## shown while tracks are selected
var _status: Label
var _finish: Button
var _cancel: Button
var _group_popup: PopupPanel
var _group_name: LineEdit
var _look_popup: PopupPanel
var _look_grid: GridContainer
var _switch_popup: PopupPanel
var _switch_picker: VBoxContainer
var _switch_action: OptionButton
var _switch_starts: CheckBox
var _switch_add: Button
var _channel_inspector: EditorInspectorPlugin

var _placing := false
var _anchors := PackedVector3Array()
var _hover := {} ## where a click would put the next anchor: {position, snapped}
var _preview: Node3D ## TrackPreview, an internal child of the edited scene while placing


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	TrackPreview.register()
	_channel_inspector = ChannelInspector.new()
	add_inspector_plugin(_channel_inspector)
	_build_toolbar()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	EditorInterface.get_selection().selection_changed.connect(_refresh)
	EditorInterface.get_editor_settings().settings_changed.connect(_render)
	scene_changed.connect(_on_scene_changed)
	_refresh()


func _exit_tree() -> void:
	cancel_track()
	EditorInterface.get_selection().selection_changed.disconnect(_refresh)
	EditorInterface.get_editor_settings().settings_changed.disconnect(_render)
	scene_changed.disconnect(_on_scene_changed)
	remove_inspector_plugin(_channel_inspector)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.queue_free()


func _build_toolbar() -> void:
	_bar = HBoxContainer.new()
	_main = MenuButton.new()
	_refs = PopupMenu.new()
	_ref_add = PopupMenu.new()
	_tracks = PopupMenu.new()
	_track_menu = MenuButton.new()
	_status = Label.new()
	_finish = Button.new()
	_cancel = Button.new()
	_group_popup = PopupPanel.new()
	_group_name = LineEdit.new()
	_look_popup = PopupPanel.new()
	_look_grid = GridContainer.new()
	_switch_popup = PopupPanel.new()
	_switch_picker = ChannelPicker.new()
	_switch_action = OptionButton.new()
	_switch_starts = CheckBox.new()
	_switch_add = Button.new()

	# the Platform Track builder menu: Shape Refs, Tracks (New Track first), Preview Settings
	_main.icon = _icon(&"Path3D")
	_main.tooltip_text = "Platform Track builder"
	var menu := _main.get_popup()
	menu.add_child(_refs)
	menu.add_child(_tracks)
	_refs.add_child(_ref_add)
	for kind: String in SHAPES:
		_ref_add.add_icon_item(_icon(SHAPES[kind]), kind)
	_ref_add.index_pressed.connect(func(i: int) -> void: add_shape_reference(SHAPES.keys()[i]))
	menu.about_to_popup.connect(_fill_main_menu)
	for m: PopupMenu in [menu, _refs, _tracks]:
		m.index_pressed.connect(func(i: int) -> void: _menu_pick(m, i))
	_bar.add_child(_main)

	# the selected tracks' menu
	_track_menu.icon = _icon(&"AnimatableBody3D")
	_track_menu.tooltip_text = "Selected platform tracks"
	var tm := _track_menu.get_popup()
	tm.add_icon_check_item(_icon(&"Play"), "Play in Editor")
	tm.set_item_metadata(0, func() -> void: play_in_editor(not is_playing()))
	tm.set_item_tooltip(0, "Move their platforms in the editor (a grouped track plays its whole group)")
	tm.add_icon_item(_icon(&"Groups"), "Group...")
	tm.set_item_metadata(1, _open_group_popup)
	tm.add_icon_item(_icon(&"Signals"), "Switch...")
	tm.set_item_metadata(2, _open_switch_popup)
	tm.set_item_tooltip(2, "Add a switch that controls the selected tracks")
	tm.about_to_popup.connect(func() -> void: tm.set_item_checked(0, is_playing()))
	tm.index_pressed.connect(func(i: int) -> void: _menu_pick(tm, i))
	_bar.add_child(_track_menu)

	# while placing a track
	_bar.add_child(_status)
	_finish.text = "Finish"
	_finish.pressed.connect(finish_track)
	_bar.add_child(_finish)
	_cancel.text = "Cancel"
	_cancel.pressed.connect(cancel_track)
	_bar.add_child(_cancel)

	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(320, 0)
	var grid := GridContainer.new()
	grid.columns = 2
	for row: Array in [["Channel", _switch_picker], ["Action", _switch_action], ["Track starts moving", _switch_starts]]:
		var label := Label.new()
		label.text = row[0]
		grid.add_child(label)
		row[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row[1])
	for action: String in PlatformSwitch.Action.keys():
		_switch_action.add_item(action.capitalize())
	_switch_starts.tooltip_text = "Off: the platforms wait at their start until the switch is used"
	form.add_child(grid)
	_switch_add.text = "Add Switch"
	_switch_add.pressed.connect(func() -> void:
		_switch_popup.hide()
		add_switch(_switch_picker.value(), _switch_action.selected, _switch_starts.button_pressed))
	form.add_child(_switch_add)
	_switch_picker.allow_none = false
	_switch_picker.edited.connect(func() -> void: _switch_add.disabled = not _switch_picker.valid())
	_switch_popup.add_child(form)
	_bar.add_child(_switch_popup)

	var panel := VBoxContainer.new()
	_look_grid.columns = 2
	panel.add_child(_look_grid)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(reset_look)
	panel.add_child(reset)
	_look_popup.add_child(panel)
	_bar.add_child(_look_popup)
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
	for c: Control in [_status, _finish, _cancel]:
		c.visible = _placing
	_status.text = "%d anchor%s | Shift: vertical plane | click the first anchor: close the loop | Enter: finish | Esc: cancel" % [_anchors.size(), "" if _anchors.size() == 1 else "s"]
	_track_menu.visible = not _placing and not selected_tracks().is_empty()


## Shows `popup` below `button`.
func _popup_under(popup: Popup, button: Control, width: int) -> void:
	popup.popup(Rect2i(Vector2i(button.get_screen_position() + Vector2(0, button.size.y)), Vector2i(width, 0)))


# --- managing references and tracks ---

func all_references() -> Array:
	return _in_scene(func(n: Node) -> bool: return n is ShapeReference)


func all_tracks() -> Array:
	return _in_scene(func(n: Node) -> bool: return n is PlatformTrackInstance)


func _in_scene(test: Callable) -> Array:
	var root := EditorInterface.get_edited_scene_root()
	return [] if root == null else ([root] + root.find_children("*", "", true, false)).filter(test)


## Rebuilds the builder menu and its submenus (counts, lists) each time it opens.
func _fill_main_menu() -> void:
	var refs := all_references()
	var tracks := all_tracks()
	var menu := _main.get_popup()
	menu.clear()
	menu.add_submenu_node_item("Shape Refs (%d)" % refs.size(), _refs)
	menu.set_item_icon(0, _icon(&"CollisionShape3D"))
	menu.add_submenu_node_item("Tracks (%d)" % tracks.size(), _tracks)
	menu.set_item_icon(1, _icon(&"Path3D"))
	menu.add_separator()
	menu.add_icon_item(_icon(&"Tools"), "Preview Settings...")
	menu.set_item_metadata(menu.item_count - 1, _open_look_popup)
	menu.set_item_tooltip(menu.item_count - 1, "Colours, opacity and look of the track builder's preview")
	_refs.clear()
	_refs.add_submenu_node_item("Add", _ref_add)
	_refs.set_item_icon(0, _icon(&"Add"))
	_refs.add_separator()
	_fill_list(_refs, refs, _selected_of(func(n: Node) -> bool: return n is ShapeReference), "references")
	_tracks.clear()
	_tracks.add_icon_item(_icon(&"Curve3D"), "New Track")
	_tracks.set_item_metadata(0, start_track)
	_tracks.add_separator()
	_fill_list(_tracks, tracks, selected_tracks(), "tracks")


## An entry per node (picking it selects it), then "Remove selected" for `selected`.
func _fill_list(menu: PopupMenu, nodes: Array, selected: Array, what: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	for n: Node in nodes:
		var icon := &"Path3D"
		if n is ShapeReference and not n.shapes().is_empty():
			icon = StringName(n.shapes()[0].shape.get_class())
		menu.add_icon_item(_icon(icon), str(root.get_path_to(n)))
		menu.set_item_metadata(menu.item_count - 1, n)
	if nodes.is_empty():
		menu.add_item("No %s in this scene" % what)
		menu.set_item_disabled(menu.item_count - 1, true)
	menu.add_separator()
	menu.add_icon_item(_icon(&"Remove"), "Remove selected %s (%d)" % [what, selected.size()])
	menu.set_item_metadata(menu.item_count - 1, selected)
	menu.set_item_disabled(menu.item_count - 1, selected.is_empty())


## A menu entry was picked: its metadata is what to do (call it), a node to select, or nodes to remove.
func _menu_pick(menu: PopupMenu, i: int) -> void:
	var picked: Variant = menu.get_item_metadata(i)
	if picked is Callable:
		picked.call()
	elif picked is Node:
		_select(picked)
	elif picked is Array:
		remove_nodes(picked)


## Undoable: takes these nodes (shape references, tracks...) out of the scene.
func remove_nodes(nodes: Array) -> void:
	if nodes.is_empty():
		return
	# each node, where it was, and the owner of everything saved under it (removing clears them)
	var entries := nodes.map(func(n: Node) -> Array:
		var saved := ([n] + n.find_children("*", "", true, true)).map(func(m: Node) -> Array: return [m, m.owner])
		return [n, n.get_parent(), n.get_index(), saved])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Remove %d node%s" % [nodes.size(), "" if nodes.size() == 1 else "s"], UndoRedo.MERGE_DISABLE, nodes[0])
	ur.add_do_method(self, &"_detach", entries)
	ur.add_undo_method(self, &"_restore", entries)
	for n: Node in nodes:
		ur.add_undo_reference(n)
	ur.commit_action()


func _detach(entries: Array) -> void:
	for e: Array in entries:
		e[1].remove_child(e[0])


func _restore(entries: Array) -> void:
	for e: Array in entries: # by original index, so putting each back restores the order
		e[1].add_child(e[0])
		e[1].move_child(e[0], e[2])
		for saved: Array in e[3]:
			saved[0].owner = saved[1]


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
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	cancel_track()
	_placing = true
	_preview = TrackPreview.new()
	root.add_child(_preview, false, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock
	_refresh()
	_render()


func cancel_track() -> void:
	_placing = false
	_anchors.clear()
	_hover = {}
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_refresh()


func _render() -> void:
	if _placing and is_instance_valid(_preview):
		_preview.show_track(_anchors, _hover)


func _on_scene_changed(_root: Node) -> void:
	cancel_track() # the preview and anchors belong to the scene that was open


## Builds the track from the anchors placed so far (2+), else just ends placing. A closed path
## when `close`, or when the last of 4+ anchors came back to the first one.
func finish_track(close := false) -> PlatformTrackInstance:
	var points := _anchors.duplicate()
	cancel_track()
	if not close and points.size() >= 4 and points[-1].distance_to(points[0]) <= CLOSE_DISTANCE:
		points.remove_at(points.size() - 1)
		close = true
	return create_track(points, close) if points.size() >= 2 else null


## A PlatformTrackInstance at points[0]: a Path3D through `points`, and a box platform on a
## loop sequence along it (`closed`: round the loop, again and again). It goes into the
## selected group, if any, else the scene root.
func create_track(points: PackedVector3Array, closed := false) -> PlatformTrackInstance:
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
	path.curve.closed = closed
	for p in points:
		path.curve.add_point(frame.affine_inverse() * p)
	inst.add_child(path)
	var plat := MovingPlatform.new()
	plat.name = "Platform"
	if closed:
		plat.repeat = MovingPlatform.Repeat.RESTART # keep going round the same way
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
	seq.laps = 1 if closed else LOOP_LAPS
	plat.add_child(seq)
	inst.add_child(plat)
	_add(parent, inst, "Add platform track")
	return inst


## Viewport input while placing anchors (forwarding is always on, whatever is selected).
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _placing:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_hover = pick(camera, event.position, event.shift_pressed)
		_render()
		return AFTER_GUI_INPUT_PASS # keep camera navigation
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var at := pick(camera, event.position, event.shift_pressed)
			if at.get("closes", false):
				finish_track(true)
			else:
				_anchors.append(at.position)
				_refresh()
				_render()
		return AFTER_GUI_INPUT_STOP # no selection clicks while placing
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_track()
			return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			finish_track()
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## Where a click at `screen` puts an anchor, as {position, snapped, closes}: the first anchor
## when the mouse is on it (3+ placed: closes the loop), else the nearest ShapeReference surface
## under the mouse, else a plane through the last anchor (y 0 for the first): horizontal, or
## with `vertical` upright and facing the camera, to raise or lower the track.
func pick(camera: Camera3D, screen: Vector2, vertical: bool) -> Dictionary:
	if _anchors.size() >= 3 and not camera.is_position_behind(_anchors[0]) \
			and camera.unproject_position(_anchors[0]).distance_to(screen) <= CLOSE_PIXELS:
		return {position = _anchors[0], snapped = true, closes = true}
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


# --- switches and channels ---

func _open_switch_popup() -> void:
	var tracks := selected_tracks()
	if tracks.is_empty():
		return
	var plat: MovingPlatform = tracks[0].platform()
	_switch_picker.setup(plat.channel if plat else &"", String(tracks[0].name))
	_switch_starts.button_pressed = plat.starts_on if plat else true
	_popup_under(_switch_popup, _track_menu, 340)


## Undoable: a PlatformSwitch (box zone) on `channel` doing `action`, placed beside the first
## selected track's platform as a child of that track (move it anywhere), and every selected
## track's platform put on that channel with `starts_on`.
func add_switch(channel: StringName, action: int, starts_on: bool) -> PlatformSwitch:
	var tracks := selected_tracks()
	if tracks.is_empty() or channel == &"":
		return null
	var host: PlatformTrackInstance = tracks[0]
	var sw := PlatformSwitch.new()
	sw.name = String(PlatformSwitch.Action.keys()[action]).to_pascal_case() + "Switch"
	sw.channel = channel
	sw.action = action
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	var box := BoxShape3D.new()
	box.size = SWITCH_SIZE
	box.resource_local_to_scene = true
	cs.shape = box
	sw.add_child(cs)
	var plat := host.platform()
	var start := plat.global_position if plat else host.global_position
	sw.transform = host.global_transform.affine_inverse() * Transform3D(host.global_basis, start + Vector3(0, 1, 3)) # beside the platform's start
	var built := [sw] + sw.find_children("*", "", true, false)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add %s switch on channel %s" % [PlatformSwitch.Action.keys()[action].capitalize(), channel], UndoRedo.MERGE_DISABLE, host)
	ur.add_do_method(self, &"_attach", host, sw, built, EditorInterface.get_edited_scene_root())
	ur.add_do_reference(sw)
	ur.add_undo_method(host, &"remove_child", sw)
	for t: PlatformTrackInstance in tracks:
		var p := t.platform()
		if p:
			ur.add_do_property(p, &"channel", channel)
			ur.add_undo_property(p, &"channel", p.channel)
			ur.add_do_property(p, &"starts_on", starts_on)
			ur.add_undo_property(p, &"starts_on", p.starts_on)
	ur.commit_action()
	_select(sw)
	return sw


## The inspector's `channel` field on platforms and switches: the channel picker.
class ChannelInspector extends EditorInspectorPlugin:
	const ChannelProperty := preload("channel_property.gd")

	func _can_handle(o: Object) -> bool:
		return o is MovingPlatform or o is PlatformSwitch

	func _parse_property(_o: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
		if name != "channel":
			return false
		add_property_editor(name, ChannelProperty.new())
		return true


# --- preview settings ---

func _open_look_popup() -> void:
	_fill_look_panel()
	_popup_under(_look_popup, _main, 300)


## Rebuilds the Preview panel's rows from the current editor settings.
func _fill_look_panel() -> void:
	for c in _look_grid.get_children():
		c.free()
	for s: Array in TrackPreview.SETTINGS:
		var setting: String = s[0]
		var label := Label.new()
		label.text = s[1]
		_look_grid.add_child(label)
		var v: Variant = TrackPreview.value(setting)
		var edit: Control
		if v is Color:
			var swatch := ColorPickerButton.new()
			swatch.color = v
			swatch.edit_alpha = true # the colour's alpha is its transparency
			swatch.custom_minimum_size = Vector2(80, 0)
			swatch.color_changed.connect(func(c: Color) -> void: set_look(setting, c))
			edit = swatch
		elif v is bool:
			var check := CheckBox.new()
			check.button_pressed = v
			check.toggled.connect(func(on: bool) -> void: set_look(setting, on))
			edit = check
		elif s[3] == PROPERTY_HINT_ENUM:
			var options := OptionButton.new()
			for item in String(s[4]).split(","):
				options.add_item(item)
			options.selected = v
			options.item_selected.connect(func(i: int) -> void: set_look(setting, i))
			edit = options
		else:
			var spin := SpinBox.new()
			var r := String(s[4]).split(",")
			spin.min_value = float(r[0])
			spin.max_value = float(r[1])
			spin.step = float(r[2])
			spin.value = v
			spin.value_changed.connect(func(x: float) -> void: set_look(setting, x))
			edit = spin
		edit.name = setting
		_look_grid.add_child(edit)


## Changes a preview setting (saved in the editor settings) and redraws.
func set_look(setting: String, v: Variant) -> void:
	TrackPreview.set_value(setting, v)
	_render()


func reset_look() -> void:
	for s: Array in TrackPreview.SETTINGS:
		TrackPreview.set_value(s[0], s[2])
	_fill_look_panel()
	_render()


# --- play in editor ---

## What plays each selected track in the editor: its group (which plays all its tracks), else
## its platform. Both have a `preview` flag.
func _players() -> Array:
	var out := []
	for t: PlatformTrackInstance in selected_tracks():
		var p: Node = t.get_parent() if t.get_parent() is PlatformTrackGroup else t.platform()
		if p and not out.has(p):
			out.append(p)
	return out


func is_playing() -> bool:
	var players := _players()
	return not players.is_empty() and players.all(func(p: Node) -> bool: return p.preview)


## Undoable: the selected tracks' platforms move in the editor (or stop).
func play_in_editor(on: bool) -> void:
	var players := _players()
	if players.is_empty():
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Play platform tracks in the editor" if on else "Stop platform tracks in the editor", UndoRedo.MERGE_DISABLE, players[0])
	for p: Node in players:
		ur.add_do_property(p, &"preview", on)
		ur.add_undo_property(p, &"preview", p.preview)
	ur.commit_action()


# --- groups ---

## The PlatformTrackInstances selected, directly or through one of their children.
func selected_tracks() -> Array:
	return _selected_of(func(n: Node) -> bool: return n is PlatformTrackInstance)


## The nodes passing `test` that are selected, or that hold something selected.
func _selected_of(test: Callable) -> Array:
	var out := []
	for n in EditorInterface.get_selection().get_selected_nodes():
		while n and not test.call(n):
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


func _open_group_popup() -> void:
	_group_name.text = "TrackGroup"
	_popup_under(_group_popup, _track_menu, 240)
	_group_name.grab_focus()
	_group_name.select_all()


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
