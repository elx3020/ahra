@tool
extends EditorPlugin
## NPC builder: one icon menu in the 3D toolbar with
## - New NPC: instances npc/npc.tscn or an NPC type into the edited scene, on the surface below
##   the view centre, and selects it (dragging an NPC scene from the FileSystem dock works too);
## - New NPC Type...: names a type and writes npc/<name>/<name>.tscn, a scene inherited from
##   npc/npc.tscn (look and defaults), then opens it;
## - NPCs (count): pick one to select it, or remove the selected ones.
## While an NPC is selected a second icon menu configures it:
## - Add Interaction: Talk once, Talk (versions), Bark (near, doesn't hold the player), Leave;
##   each gets a unique id and placeholder lines to edit in the inspector;
## - Add Mark: the next click in the viewport puts a Marker3D under the NPC's Marks, on the
##   surface under the cursor (Esc cancels). Marks are floor points the NPC walks to and looks at.
## The inspector does the rest (summaries on each row, fields per step kind, config warnings).
## Every change is undoable.

const NPC_SCENE := "res://npc/npc.tscn"
const FEET := 0.8 ## an NPC's origin is this far above its feet
const TEMPLATES := {
	"talk_once": "Talk once (key, plays a single time)",
	"talk": "Talk (key, repeats with versions)",
	"bark": "Bark (near, doesn't hold the player)",
	"leave": "Leave (key, once: says goodbye, fades out)",
}

# toolbar controls, made in _build_toolbar (member defaults would leak on a script reload)
var _bar: HBoxContainer
var _main: MenuButton ## the NPC builder menu
var _new: PopupMenu ## its New NPC submenu
var _list: PopupMenu ## its NPCs submenu
var _npc_menu: MenuButton ## shown while an NPC is selected
var _templates: PopupMenu
var _status: Label
var _type_dialog: ConfirmationDialog
var _type_name: LineEdit
var _marking: Npc = null ## the NPC waiting for a click to place a mark, or null


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	_build_toolbar()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	EditorInterface.get_selection().selection_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	_marking = null
	EditorInterface.get_selection().selection_changed.disconnect(_refresh)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.queue_free()


func _build_toolbar() -> void:
	_bar = HBoxContainer.new()
	_main = MenuButton.new()
	_new = PopupMenu.new()
	_list = PopupMenu.new()
	_npc_menu = MenuButton.new()
	_templates = PopupMenu.new()
	_status = Label.new()
	_type_dialog = ConfirmationDialog.new()
	_type_name = LineEdit.new()

	_main.icon = _icon(&"CharacterBody3D")
	_main.tooltip_text = "NPC builder"
	var menu := _main.get_popup()
	menu.add_child(_new)
	menu.add_child(_list)
	menu.about_to_popup.connect(_fill_main_menu)
	for m: PopupMenu in [menu, _new, _list]:
		m.index_pressed.connect(func(i: int) -> void: _menu_pick(m, i))
	_bar.add_child(_main)

	_npc_menu.icon = _icon(&"Label3D")
	_npc_menu.tooltip_text = "Selected NPC"
	var nm := _npc_menu.get_popup()
	nm.add_child(_templates)
	nm.add_submenu_node_item("Add Interaction", _templates)
	nm.set_item_icon(0, _icon(&"Add"))
	nm.add_icon_item(_icon(&"Marker3D"), "Add Mark")
	nm.set_item_metadata(1, func() -> void: start_mark(_selected_npc()))
	nm.set_item_tooltip(1, "Click in the viewport to place a mark the NPC can walk to and look at")
	for kind: String in TEMPLATES:
		_templates.add_item(TEMPLATES[kind])
		_templates.set_item_metadata(_templates.item_count - 1, func() -> void: add_interaction(_selected_npc(), kind))
	for m: PopupMenu in [nm, _templates]:
		m.index_pressed.connect(func(i: int) -> void: _menu_pick(m, i))
	_bar.add_child(_npc_menu)

	_status.text = "Click where the mark goes | Esc: cancel"
	_bar.add_child(_status)

	_type_dialog.title = "New NPC Type"
	_type_name.placeholder_text = "Name, e.g. Guard"
	_type_dialog.add_child(_type_name)
	_type_dialog.register_text_enter(_type_name)
	_type_dialog.confirmed.connect(func() -> void: create_type(_type_name.text))
	_bar.add_child(_type_dialog)


func _refresh() -> void:
	_npc_menu.visible = _marking == null and _selected_npc() != null
	_status.visible = _marking != null


func _fill_main_menu() -> void:
	var npcs := all_npcs()
	var menu := _main.get_popup()
	menu.clear()
	menu.add_submenu_node_item("New NPC", _new)
	menu.set_item_icon(0, _icon(&"Add"))
	menu.add_icon_item(_icon(&"PackedScene"), "New NPC Type...")
	menu.set_item_metadata(1, _open_type_dialog)
	menu.set_item_tooltip(1, "A scene inherited from npc.tscn, for a character's look and defaults")
	menu.add_submenu_node_item("NPCs (%d)" % npcs.size(), _list)
	menu.set_item_icon(2, _icon(&"CharacterBody3D"))
	_new.clear()
	for p in npc_scenes():
		_new.add_icon_item(_icon(&"PackedScene"), p.get_file().get_basename())
		_new.set_item_metadata(_new.item_count - 1, func() -> void: add_npc(p))
	_list.clear()
	var root := EditorInterface.get_edited_scene_root()
	for n: Node in npcs:
		_list.add_icon_item(_icon(&"CharacterBody3D"), str(root.get_path_to(n)))
		_list.set_item_metadata(_list.item_count - 1, n)
	if npcs.is_empty():
		_list.add_item("No NPCs in this scene")
		_list.set_item_disabled(_list.item_count - 1, true)
	var selected := _selected_of(func(n: Node) -> bool: return n is Npc)
	_list.add_separator()
	_list.add_icon_item(_icon(&"Remove"), "Remove selected NPCs (%d)" % selected.size())
	_list.set_item_metadata(_list.item_count - 1, selected)
	_list.set_item_disabled(_list.item_count - 1, selected.is_empty())


## A menu entry was picked: its metadata is what to do (call it), a node to select, or nodes to remove.
func _menu_pick(menu: PopupMenu, i: int) -> void:
	var picked: Variant = menu.get_item_metadata(i)
	if picked is Callable:
		picked.call()
	elif picked is Node:
		_select(picked)
	elif picked is Array:
		remove_nodes(picked)


func _open_type_dialog() -> void:
	_type_name.text = ""
	_type_dialog.popup_centered(Vector2i(320, 0))
	_type_name.grab_focus()


# --- creating types and adding NPCs ---

## npc/npc.tscn plus every type scene (npc/<dir>/<dir>.tscn).
func npc_scenes() -> PackedStringArray:
	var out := PackedStringArray([NPC_SCENE])
	for d in DirAccess.get_directories_at("res://npc"):
		var p := "res://npc/%s/%s.tscn" % [d, d]
		if FileAccess.file_exists(p):
			out.append(p)
	return out


## Writes npc/<snake_name>/<snake_name>.tscn, inherited from npc.tscn, and opens it when `open`.
## Returns its path, or "" for an empty name or one already taken.
func create_type(type_name: String, open := true) -> String:
	var pascal := type_name.strip_edges().to_pascal_case()
	var snake := pascal.to_snake_case()
	if snake.is_empty() or not snake.is_valid_identifier():
		return ""
	var dir := "res://npc/" + snake
	var path := "%s/%s.tscn" % [dir, snake]
	if FileAccess.file_exists(path):
		return ""
	# an inherited scene is its root instancing the base; PackedScene.pack() can't record that
	# from script (it saves a full copy), so the file is written as the editor writes it
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_base"]\n\n[node name="%s" instance=ExtResource("1_base")]\n' % [NPC_SCENE, pascal])
	f.close()
	EditorInterface.get_resource_filesystem().scan()
	if open:
		EditorInterface.open_scene_from_path(path)
	return path


## Undoable: instances `scene_path` (an NPC scene) into the edited scene, standing on the surface
## below the view centre, and selects it.
func add_npc(scene_path: String) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	var n := (load(scene_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	n.name = scene_path.get_file().get_basename().to_pascal_case()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add NPC", UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(self, &"_attach", root, n, _view_ground() + Vector3.UP * FEET, root)
	ur.add_do_reference(n)
	ur.add_undo_method(root, &"remove_child", n)
	ur.commit_action()
	_select(n)
	return n


## Only the instance root is owned by the edited scene: its own nodes stay the instance's.
func _attach(parent: Node, n: Node3D, at: Vector3, root: Node) -> void:
	parent.add_child(n, true)
	n.owner = root
	n.global_position = at


func all_npcs() -> Array:
	return _in_scene(func(n: Node) -> bool: return n is Npc)


## Undoable: takes these nodes out of the scene.
func remove_nodes(nodes: Array) -> void:
	if nodes.is_empty():
		return
	var entries := _entries(nodes)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Remove %d NPC%s" % [nodes.size(), "" if nodes.size() == 1 else "s"], UndoRedo.MERGE_DISABLE, nodes[0])
	ur.add_do_method(self, &"_detach", entries)
	ur.add_undo_method(self, &"_restore", entries)
	for n: Node in nodes:
		ur.add_undo_reference(n)
	ur.commit_action()


## Each node, where it is, and the owner of everything under it (removing clears them).
func _entries(nodes: Array) -> Array:
	var entries := nodes.map(func(n: Node) -> Array:
		var saved := ([n] + n.find_children("*", "", true, true)).map(func(m: Node) -> Array: return [m, m.owner])
		return [n, n.get_parent(), n.get_index(), saved])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	return entries


func _detach(entries: Array) -> void:
	for e: Array in entries:
		e[1].remove_child(e[0])


func _restore(entries: Array) -> void:
	for e: Array in entries:
		e[1].add_child(e[0])
		e[1].move_child(e[0], e[2])
		for saved: Array in e[3]:
			saved[0].owner = saved[1]


# --- configuring an NPC ---

## Undoable: appends a new interaction made from `kind` (a TEMPLATES key) with a unique id.
func add_interaction(npc: Npc, kind: String) -> NpcInteraction:
	if npc == null or kind not in TEMPLATES:
		return null
	var i := _template(kind)
	var base := "talk" if kind == "talk_once" else kind
	var taken: Array = npc.interactions.filter(func(x: NpcInteraction) -> bool: return x != null).map(func(x: NpcInteraction) -> StringName: return x.id)
	var id := base
	var k := 2
	while StringName(id) in taken:
		id = "%s%d" % [base, k]
		k += 1
	i.id = StringName(id)
	var before: Array[NpcInteraction] = npc.interactions
	var after := before.duplicate()
	after.append(i)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add NPC interaction", UndoRedo.MERGE_DISABLE, npc)
	ur.add_do_property(npc, &"interactions", after)
	ur.add_undo_property(npc, &"interactions", before)
	ur.commit_action()
	return i


func _template(kind: String) -> NpcInteraction:
	var i := NpcInteraction.new()
	match kind:
		"talk_once":
			i.once = true
			i.steps = [_say(["Hello there. I don't think we've met."]), _say(["Come back any time."])]
		"talk":
			i.steps = [_say(["Good day.", "Lovely weather.", "Hm? Oh, it's you."])]
		"bark":
			i.trigger = NpcInteraction.Trigger.NEAR
			i.locks_player = false
			i.steps = [_say(["Hey, over here!"])]
		"leave":
			i.once = true
			var leave := NpcStep.new()
			leave.kind = NpcStep.Kind.LEAVE
			i.steps = [_say(["I'll be going now."]), leave]
	return i


func _say(lines: Array) -> NpcStep:
	var s := NpcStep.new()
	s.lines = PackedStringArray(lines)
	return s


## The next viewport click places a mark for `npc` (Esc cancels).
func start_mark(npc: Npc) -> void:
	_marking = npc
	_refresh()


## Undoable: a Marker3D under `npc`'s Marks at global `at` (Mark, Mark2...).
func place_mark(npc: Npc, at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = "Mark"
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add NPC mark", UndoRedo.MERGE_DISABLE, npc)
	ur.add_do_method(self, &"_add_mark", npc.get_node(^"Marks"), m, at, EditorInterface.get_edited_scene_root())
	ur.add_do_reference(m)
	ur.add_undo_method(npc.get_node(^"Marks"), &"remove_child", m)
	ur.commit_action()
	return m


func _add_mark(marks: Node, m: Marker3D, at: Vector3, root: Node) -> void:
	marks.add_child(m, true)
	m.owner = root
	m.global_position = at


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _marking == null:
		return AFTER_GUI_INPUT_PASS
	if not is_instance_valid(_marking) or not _marking.is_inside_tree():
		_marking = null
		_refresh()
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var at := pick_surface(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position), _marking.global_position.y - FEET)
		place_mark(_marking, at)
		_marking = null
		_refresh()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_marking = null
		_refresh()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


# --- picking surfaces ---

## Where a ray from `from` along `dir` meets the edited scene's collision (NPC bodies ignored),
## else the horizontal plane at height `fallback_y`.
func pick_surface(from: Vector3, dir: Vector3, fallback_y: float) -> Vector3:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if root:
		var bodies: Array[RID] = []
		for n: Npc in all_npcs():
			bodies.append(n.get_rid())
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0, 0xFFFFFFFF, bodies)
		var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			return hit.position
	var p: Variant = Plane(Vector3.UP, fallback_y).intersects_ray(from, dir)
	return p if p != null else from + dir * 10.0


## The surface under the view centre (the ground plane, y 0, when nothing is hit).
func _view_ground() -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	var mid := Vector2(vp.size) * 0.5
	return pick_surface(cam.project_ray_origin(mid), cam.project_ray_normal(mid), 0.0)


# --- helpers ---

func _selected_npc() -> Npc:
	var npcs := _selected_of(func(n: Node) -> bool: return n is Npc)
	return npcs[0] if npcs else null


func _selected_of(test: Callable) -> Array:
	return EditorInterface.get_selection().get_selected_nodes().filter(test)


func _in_scene(test: Callable) -> Array:
	var root := EditorInterface.get_edited_scene_root()
	return [] if root == null else ([root] + root.find_children("*", "", true, false)).filter(test)


func _select(node: Node) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


func _icon(icon_name: StringName) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon(icon_name if theme.has_icon(icon_name, &"EditorIcons") else &"Node", &"EditorIcons")
