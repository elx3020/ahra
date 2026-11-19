@tool
extends EditorPlugin
## Shape editing for nodes built on ShapeSet (Zone, MovingPlatform, ShapeReference): the inspector's Shapes
## section gets an Add Shape menu and Remove buttons (undoable), and a selected node shows
## resize handles for all its shapes at once.

var _inspector := ShapeInspector.new()
var _gizmo := ShapeGizmo.new()


func _enter_tree() -> void:
	add_inspector_plugin(_inspector)
	add_node_3d_gizmo_plugin(_gizmo)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	remove_node_3d_gizmo_plugin(_gizmo)


class ShapeInspector extends EditorInspectorPlugin:
	const SHAPES := {
		Box = &"BoxShape3D",
		Sphere = &"SphereShape3D",
		Capsule = &"CapsuleShape3D",
		Cylinder = &"CylinderShape3D",
		HeightMap = &"HeightMapShape3D",
		Convex = &"ConvexPolygonShape3D",
		Concave = &"ConcavePolygonShape3D",
	}

	func _can_handle(o: Object) -> bool:
		return o is Zone or o is MovingPlatform or o is ShapeReference # the ShapeSet nodes

	func _parse_property(o: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
		var node := o as Node3D
		if name == "shapes/add":
			var menu := MenuButton.new()
			menu.text = "Add Shape"
			menu.icon = _icon(&"Add")
			menu.flat = false
			var popup := menu.get_popup()
			for kind: String in SHAPES:
				popup.add_icon_item(_icon(SHAPES[kind]), kind.capitalize())
			popup.index_pressed.connect(func(i: int) -> void: add(node, SHAPES.keys()[i]))
			add_custom_control(menu)
			return true
		if name.ends_with("/remove"):
			var cs: CollisionShape3D = node.get_node(NodePath(name.get_slice("/", 1)))
			var button := Button.new()
			button.text = "Remove %s" % cs.name
			button.icon = _icon(&"Remove")
			button.pressed.connect(remove.bind(node, cs))
			add_custom_control(button)
			return true
		return false

	## Adds a `kind` shape with default settings at the node's origin.
	func add(node: Node3D, kind: String) -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		cs.name = kind
		match kind:
			# empty by default: start them as a 1 m cube
			"Convex": cs.shape = BoxMesh.new().create_convex_shape()
			"Concave": cs.shape = BoxMesh.new().create_trimesh_shape()
			_: cs.shape = ClassDB.instantiate(SHAPES[kind])
		cs.shape.resource_local_to_scene = true # instances of a scene don't share it either
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Add %s shape to %s" % [kind, node.name], UndoRedo.MERGE_DISABLE, node)
		ur.add_do_method(self, &"_attach", node, cs, -1, EditorInterface.get_edited_scene_root())
		ur.add_do_reference(cs)
		ur.add_undo_method(node, &"remove_child", cs)
		ur.commit_action()
		return cs

	func remove(node: Node3D, cs: CollisionShape3D) -> void:
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Remove %s from %s" % [cs.name, node.name], UndoRedo.MERGE_DISABLE, node)
		ur.add_do_method(node, &"remove_child", cs)
		ur.add_undo_method(self, &"_attach", node, cs, cs.get_index(), cs.owner)
		ur.add_undo_reference(cs)
		ur.commit_action()

	func _attach(node: Node3D, cs: CollisionShape3D, index: int, owner: Node) -> void:
		node.add_child(cs, true)
		if index >= 0:
			node.move_child(cs, index)
		cs.owner = owner # saved with the scene

	func _icon(name: StringName) -> Texture2D:
		return EditorInterface.get_editor_theme().get_icon(name, &"EditorIcons")


## Handles for every primitive shape of the selected node: box faces, radius, height.
## Handle id = shape index * 3 + axis (box: x/y/z size; others: 0 = radius, 1 = height).
## ponytail: ignores the editor's snap setting; boxes resize symmetrically around their centre.
class ShapeGizmo extends EditorNode3DGizmoPlugin:
	func _init() -> void:
		create_handle_material("handles")

	func _get_gizmo_name() -> String:
		return "Shapes"

	func _has_gizmo(node: Node3D) -> bool:
		# asked when the node enters the tree, before its _ready: check the class, not a group
		return node is Zone or node is MovingPlatform or node is ShapeReference

	func _redraw(g: EditorNode3DGizmo) -> void:
		g.clear()
		var points := PackedVector3Array()
		var ids := PackedInt32Array()
		var kids := ShapeSet.of(g.get_node_3d())
		for i in kids.size():
			for axis in axes(kids[i].shape):
				points.append(kids[i].transform * handle(kids[i].shape, axis))
				ids.append(i * 3 + axis)
		if not points.is_empty():
			g.add_handles(points, get_material("handles", g), ids)

	func _get_handle_name(g: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
		var cs := _node(g, id)
		return "%s %s" % [cs.name, prop(cs.shape, id % 3)]

	func _get_handle_value(g: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
		var s := _node(g, id).shape
		return s.get(prop(s, id % 3))

	func _set_handle(g: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen: Vector2) -> void:
		var cs := _node(g, id)
		var axis := id % 3
		# closest point on the handle's axis to the mouse ray, in the shape's space
		var to_local := cs.global_transform.affine_inverse()
		var from := to_local * camera.project_ray_origin(screen)
		var to := to_local * (camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * 4096.0)
		var reach := Vector3.ZERO
		reach[axis] = 4096.0
		var d := maxf(Geometry3D.get_closest_points_between_segments(-reach, reach, from, to)[0][axis], 0.001)
		resize(cs.shape, axis, d)

	func _commit_handle(g: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
		var cs := _node(g, id)
		var p := prop(cs.shape, id % 3)
		if cancel:
			cs.shape.set(p, restore)
			return
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Resize %s" % cs.name, UndoRedo.MERGE_DISABLE, g.get_node_3d())
		ur.add_do_property(cs.shape, p, cs.shape.get(p))
		ur.add_undo_property(cs.shape, p, restore)
		ur.commit_action()

	## Axes with a handle: x/y/z for boxes, radius (0) and height (1) for round shapes.
	static func axes(s: Shape3D) -> Array[int]:
		if s is BoxShape3D:
			return [0, 1, 2]
		if s is SphereShape3D:
			return [0]
		if s is CapsuleShape3D or s is CylinderShape3D:
			return [0, 1]
		return []

	static func prop(s: Shape3D, axis: int) -> StringName:
		if s is BoxShape3D:
			return &"size"
		return &"height" if axis == 1 else &"radius"

	## Handle position in the shape's space.
	static func handle(s: Shape3D, axis: int) -> Vector3:
		var v := Vector3.ZERO
		if s is BoxShape3D:
			v[axis] = (s as BoxShape3D).size[axis] * 0.5
		elif axis == 1:
			v.y = s.get(&"height") * 0.5
		else:
			v.x = s.get(&"radius")
		return v

	## Moves the handle on `axis` to distance d from the centre.
	static func resize(s: Shape3D, axis: int, d: float) -> void:
		if s is BoxShape3D:
			var box := s as BoxShape3D
			var size := box.size
			size[axis] = d * 2.0
			box.size = size
		else:
			s.set(prop(s, axis), d * 2.0 if axis == 1 else d)

	func _node(g: EditorNode3DGizmo, id: int) -> CollisionShape3D:
		return ShapeSet.of(g.get_node_3d())[int(id / 3.0)]
