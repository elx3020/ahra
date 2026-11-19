@tool
class_name Zone
extends Area3D
## Trigger volume: an Area3D whose CollisionShape3D children are its shape, any mix of box,
## sphere, capsule, cylinder, height map, convex and concave. Each shape is drawn as a
## translucent `color` mesh, in the editor and in game.
## With the Zone Tools plugin (addons/zone_tools) the inspector's Shapes section adds, removes
## and edits the shapes, and the viewport shows resize handles while the zone is selected.
## Subclasses override _player_entered/_player_exited.

@export var color := Color(1, 1, 1, 0.2):
	set(v):
		color = v
		_mat.albedo_color = v

var _mat := StandardMaterial3D.new()
var _drawn := [] ## what the meshes show: each shape's debug mesh + transform (editor redraw check)
var _listed := [] ## the shape nodes the inspector lists


func _ready() -> void:
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	if Engine.is_editor_hint():
		add_to_group(&"zones")
		_unshare.call_deferred() # deferred: the editor sets a duplicate's owner after adding it
		_listed = shapes()
	else:
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
	_draw_shapes()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# a shape's debug mesh is rebuilt whenever the shape changes, so comparing them catches
	# shapes added, removed, swapped or resized, from any inspector, handle or undo
	if _looks() != _drawn:
		_draw_shapes()
		update_gizmos()
	var kids := shapes()
	if kids != _listed:
		_listed = kids
		notify_property_list_changed()


## The CollisionShape3D children that have a shape.
func shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for c in get_children():
		if c is CollisionShape3D and c.shape:
			out.append(c)
	return out


## Adds a shape at `at` (zone space). For zones built in code; in the editor use the inspector.
func add_shape(shape: Shape3D, at := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	add_child(cs)
	if is_node_ready():
		_draw_shapes()
	return cs


## Box around all the shapes, in zone space.
func bounds() -> AABB:
	var out := AABB()
	var kids := shapes()
	for i in kids.size():
		var b := kids[i].transform * kids[i].shape.get_debug_mesh().get_aabb()
		out = b if i == 0 else out.merge(b)
	return out


func _looks() -> Array:
	var out := []
	for cs in shapes():
		out.append_array([cs.shape.get_debug_mesh(), cs.transform])
	return out


func _draw_shapes() -> void:
	for cs in get_children():
		if not cs is CollisionShape3D:
			continue
		for old in cs.get_children(true):
			if old.name == &"ZoneMesh":
				old.free()
		if cs.shape:
			var mi := MeshInstance3D.new()
			mi.name = &"ZoneMesh"
			mi.mesh = cs.shape.get_debug_mesh() # faces + edges, for every shape type
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cs.add_child(mi, false, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock
	_drawn = _looks()


## Duplicating a node (Ctrl+D, copy/paste) shares its shape resources with the original:
## give this zone its own copies, so resizing one zone doesn't resize the other.
func _unshare() -> void:
	if not is_inside_tree() or owner == null or owner != get_tree().edited_scene_root:
		return # a closed tab, or part of an instanced scene / built in code: not a fresh copy
	var taken := {}
	for z in get_tree().get_nodes_in_group(&"zones"):
		if z != self:
			for cs in (z as Zone).shapes():
				taken[cs.shape] = true
	for cs in shapes():
		if taken.has(cs.shape):
			cs.shape = cs.shape.duplicate()


# Inspector: a "Shapes" section with an Add Shape menu, then each shape's resource (its
# settings unfold inline), position, rotation and a Remove button. The menu and the buttons
# are drawn by the Zone Tools plugin in place of the `add` / `remove` placeholders.
func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{name = "shapes/add", type = TYPE_NIL, usage = PROPERTY_USAGE_EDITOR}]
	for cs in shapes():
		var p := "shapes/%s/" % cs.name
		out.append({name = p + "shape", type = TYPE_OBJECT, hint = PROPERTY_HINT_RESOURCE_TYPE, hint_string = "Shape3D", usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "position", type = TYPE_VECTOR3, usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "rotation_degrees", type = TYPE_VECTOR3, usage = PROPERTY_USAGE_EDITOR})
		out.append({name = p + "remove", type = TYPE_NIL, usage = PROPERTY_USAGE_EDITOR})
	return out


func _get(property: StringName) -> Variant:
	var cs := _shape_node(property)
	return cs.get(property.get_slice("/", 2)) if cs else null


func _set(property: StringName, value: Variant) -> bool:
	var cs := _shape_node(property)
	if cs == null:
		return false
	if property.ends_with("/shape") and not value is Shape3D:
		return true # clearing it here would drop the shape from the list without deleting it: use Remove
	cs.set(property.get_slice("/", 2), value)
	return true


## "shapes/<child name>/<property>" -> that child.
func _shape_node(property: StringName) -> CollisionShape3D:
	if not property.begins_with("shapes/") or property.get_slice_count("/") != 3:
		return null
	return get_node_or_null(NodePath(property.get_slice("/", 1))) as CollisionShape3D


func _on_body_entered(b: Node3D) -> void:
	if b is Player:
		_player_entered(b)


func _on_body_exited(b: Node3D) -> void:
	if b is Player:
		_player_exited(b)


func _player_entered(_p: Player) -> void:
	pass


func _player_exited(_p: Player) -> void:
	pass
