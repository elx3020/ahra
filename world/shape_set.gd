class_name ShapeSet
## Helpers for nodes whose shape is their CollisionShape3D children, any type and any number
## (Zone, MovingPlatform): listing, drawing, bounds, inspector proxies and duplicate handling.
## The Shape Tools plugin (addons/shape_tools) adds/removes the shapes and draws their handles.

const MESH := &"ShapeMesh" ## internal child of each CollisionShape3D that draws it
const GROUP := &"shaped" ## editor only: nodes checked for shapes shared by duplication


## The CollisionShape3D children that have a shape.
static func of(node: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for c in node.get_children():
		if c is CollisionShape3D and c.shape:
			out.append(c)
	return out


## Box around all the shapes, in the node's space.
static func bounds(node: Node) -> AABB:
	var out := AABB()
	var kids := of(node)
	for i in kids.size():
		var b := kids[i].transform * kids[i].shape.get_debug_mesh().get_aabb()
		out = b if i == 0 else out.merge(b)
	return out


## Call from _ready: draws the shapes and, in the editor, joins the duplicate check.
## Returns the state to keep and pass to refresh().
static func setup(node: Node3D, material: Material, solid: bool) -> Array:
	if Engine.is_editor_hint():
		node.add_to_group(GROUP)
	var seen := refresh(node, [null, null], material, solid)
	seen[1] = null # so the first editor refresh, a frame later, checks for shared shapes again:
	return seen # the editor sets a duplicate's owner after adding it


## Redraws, and in the editor refreshes handles and inspector, if the shapes changed since `seen`
## (what this returned last time). A shape rebuilds its debug mesh whenever it changes, so
## comparing those catches shapes added, removed, swapped, resized or moved, from anywhere.
static func refresh(node: Node3D, seen: Array, material: Material, solid: bool) -> Array:
	if seen[1] == null and Engine.is_editor_hint():
		_unshare(node)
	var now := [stamp(node), of(node)]
	if now[0] != seen[0]:
		_draw(node, material, solid)
		node.update_gizmos()
	if now[1] != seen[1]:
		node.notify_property_list_changed()
	return now


## One mesh per shape with `material`: see-through debug meshes (faces + edges), or lit `solid` ones.
static func _draw(node: Node3D, material: Material, solid: bool) -> void:
	for cs in node.get_children():
		if not cs is CollisionShape3D:
			continue
		for old in cs.get_children(true):
			if old.name == MESH:
				old.free()
		if cs.shape:
			var mi := MeshInstance3D.new()
			mi.name = MESH
			mi.mesh = solid_mesh(cs.shape) if solid else cs.shape.get_debug_mesh()
			mi.material_override = material
			if not solid:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cs.add_child(mi, false, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock


## A lit mesh of the shape: primitive meshes for primitive shapes, else the shape's debug faces
## with flat normals (draw them with culling off: their winding isn't guaranteed).
static func solid_mesh(s: Shape3D) -> Mesh:
	if s is BoxShape3D:
		var box := BoxMesh.new()
		box.size = (s as BoxShape3D).size
		return box
	if s is SphereShape3D:
		var ball := SphereMesh.new()
		ball.radius = (s as SphereShape3D).radius
		ball.height = ball.radius * 2.0
		return ball
	if s is CapsuleShape3D:
		var pill := CapsuleMesh.new()
		pill.radius = (s as CapsuleShape3D).radius
		pill.height = (s as CapsuleShape3D).height
		return pill
	if s is CylinderShape3D:
		var can := CylinderMesh.new()
		can.top_radius = (s as CylinderShape3D).radius
		can.bottom_radius = can.top_radius
		can.height = (s as CylinderShape3D).height
		return can
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat
	for v in s.get_debug_mesh().get_faces():
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Changes whenever a shape is added, removed, swapped, resized or moved.
static func stamp(node: Node) -> Array:
	var out := []
	for cs in of(node):
		out.append_array([cs.shape.get_debug_mesh(), cs.transform])
	return out


## Duplicating a node (Ctrl+D, copy/paste) shares its shape resources with the original:
## give the copy its own, so resizing one doesn't resize the other.
static func _unshare(node: Node) -> void:
	if not node.is_inside_tree() or node.owner == null or node.owner != node.get_tree().edited_scene_root:
		return # a closed tab, or part of an instanced scene / built in code: not a fresh copy
	var taken := {}
	for other in node.get_tree().get_nodes_in_group(GROUP):
		if other != node:
			for cs in of(other):
				taken[cs.shape] = true
	for cs in of(node):
		if taken.has(cs.shape):
			cs.shape = cs.shape.duplicate()


# Inspector rows, returned by the node's _get_property_list/_get/_set: a "Shapes" section with
# an Add Shape menu, then per shape its resource (settings unfold inline), position, rotation
# and a Remove button. The plugin draws the menu and buttons in place of `add` / `remove`.
static func property_list(node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{name = "shapes/add", type = TYPE_NIL, usage = PROPERTY_USAGE_EDITOR}]
	for cs in of(node):
		var p := "shapes/%s/" % cs.name
		out.append({name = p + "shape", type = TYPE_OBJECT, hint = PROPERTY_HINT_RESOURCE_TYPE, hint_string = "Shape3D", usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "position", type = TYPE_VECTOR3, usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "rotation_degrees", type = TYPE_VECTOR3, usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "remove", type = TYPE_NIL, usage = PROPERTY_USAGE_EDITOR})
	return out


static func get_row(node: Node, property: StringName) -> Variant:
	var cs := _row_node(node, property)
	return cs.get(property.get_slice("/", 2)) if cs else null


static func set_row(node: Node, property: StringName, value: Variant) -> bool:
	var cs := _row_node(node, property)
	if cs == null:
		return false
	if property.ends_with("/shape") and not value is Shape3D:
		return true # clearing it here would drop the shape from the list without deleting it: use Remove
	cs.set(property.get_slice("/", 2), value)
	return true


## "shapes/<child name>/<property>" -> that child.
static func _row_node(node: Node, property: StringName) -> CollisionShape3D:
	if not property.begins_with("shapes/") or property.get_slice_count("/") != 3:
		return null
	return node.get_node_or_null(NodePath(property.get_slice("/", 1))) as CollisionShape3D
