@tool
class_name ShapeReference
extends StaticBody3D
## Editor guide for laying out tracks: the Platform Tools snap track anchors onto its shapes
## (its CollisionShape3D children, any type). Move/rotate it like any node; edit its shapes
## with the inspector's Shapes section or the viewport handles (Shape Tools).
## It collides with nothing and removes itself when the game runs.

@export var color := Color(0.3, 0.8, 1.0, 0.15):
	set(v):
		color = v
		_mat.albedo_color = v

var _mat := StandardMaterial3D.new()
var _seen := [null, null] ## ShapeSet.refresh state


func _init() -> void:
	collision_layer = 0 # a guide, not geometry: editor ray casts (snap to floor...) pass through
	collision_mask = 0


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	_seen = ShapeSet.setup(self, _mat, false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_seen = ShapeSet.refresh(self, _seen, _mat, false)


func shapes() -> Array[CollisionShape3D]:
	return ShapeSet.of(self)


## Nearest point where the ray (global space) meets one of its shapes, as {position, normal},
## or {} if it misses. Any shape type: it casts against the shape's debug mesh, except a
## WorldBoundaryShape3D (a plane), which is infinite while its debug mesh is a 20 m square.
func cast(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for cs in shapes():
		var to_local := cs.global_transform.affine_inverse()
		var hit := {}
		if cs.shape is WorldBoundaryShape3D:
			var plane := (cs.shape as WorldBoundaryShape3D).plane
			var at: Variant = plane.intersects_ray(to_local * from, to_local.basis * dir)
			if at != null:
				hit = {position = at, normal = plane.normal}
		else:
			hit = cs.shape.get_debug_mesh().generate_triangle_mesh().intersect_ray(to_local * from, to_local.basis * dir)
		if hit.is_empty():
			continue
		var p: Vector3 = cs.global_transform * hit.position
		if best.is_empty() or from.distance_to(p) < from.distance_to(best.position):
			best = {position = p, normal = (cs.global_basis.inverse().transposed() * hit.normal).normalized()}
	return best


func _get_property_list() -> Array[Dictionary]:
	return ShapeSet.property_list(self)


func _get(property: StringName) -> Variant:
	return ShapeSet.get_row(self, property)


func _set(property: StringName, value: Variant) -> bool:
	return ShapeSet.set_row(self, property, value)
