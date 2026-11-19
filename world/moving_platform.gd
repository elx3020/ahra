@tool
class_name MovingPlatform
extends AnimatableBody3D
## The body that rides a track: a child of a PlatformTrackInstance, or of a circuit
## (PlatformTrackGroup), which moves it (see PlatformProgram). Without one it stays put.
## Its shape is its CollisionShape3D children, any type and any number (Shape Tools plugin:
## inspector Shapes section + viewport handles), drawn as solid `color` meshes. For walls and
## ceilings make the shape thin on that axis (or rotate it) and pair it with a GravityZone.
## A `surface` profile turns it into an ice / mud / wind... platform: an EnvZone wrapping its
## shapes rides along with it.

@export var color := Color(0.55, 0.6, 0.75):
	set(v):
		color = v
		_paint()
@export var surface: EnvProfile ## optional: environment applied while touching the platform

var _mat := StandardMaterial3D.new()
var _seen := [null, null] ## ShapeSet.refresh state
var _warmup := 2 ## physics frames with collision off while the body travels from the scene origin to its place
var _warm: Array[CollisionShape3D] = [] ## the shapes switched off for the warmup


func _ready() -> void:
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # convex/concave meshes have no guaranteed winding
	_paint()
	_seen = ShapeSet.setup(self, _mat, true)
	if not Engine.is_editor_hint():
		# the body starts at the scene origin and its first placement is a physics move (Jolt
		# moves kinematic bodies): keep collision off for it, or it carries whatever stands there
		for cs in shapes():
			if not cs.disabled:
				cs.disabled = true
				_warm.append(cs)
	if surface:
		var z := EnvZone.new()
		z.profile = surface
		for cs in shapes():
			var g := _grown(cs, 0.3)
			z.add_shape(g[0]).transform = g[1]
		z.color = Color(color, 0.12)
		add_child(z)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_seen = ShapeSet.refresh(self, _seen, _mat, true)
	elif _warmup > 0:
		_warmup -= 1
		if _warmup == 0:
			for cs in _warm:
				cs.disabled = false


## The CollisionShape3D children that have a shape.
func shapes() -> Array[CollisionShape3D]:
	return ShapeSet.of(self)


func _get_property_list() -> Array[Dictionary]:
	return ShapeSet.property_list(self)


func _get(property: StringName) -> Variant:
	return ShapeSet.get_row(self, property)


func _set(property: StringName, value: Variant) -> bool:
	return ShapeSet.set_row(self, property, value)


func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is PlatformProgram:
		return PackedStringArray()
	return PackedStringArray(["Put it in a PlatformTrackInstance (or a circuit PlatformTrackGroup): it moves the platform."])


func _paint() -> void:
	_mat.albedo_color = color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED


## A zone shape covering `cs` plus `m` all round, as [shape, transform]. Primitives keep their
## form; other shapes get their bounding box.
func _grown(cs: CollisionShape3D, m: float) -> Array:
	var s: Shape3D = cs.shape.duplicate()
	if s is BoxShape3D:
		var box := s as BoxShape3D
		box.size += Vector3.ONE * 2.0 * m
	elif s is SphereShape3D:
		var ball := s as SphereShape3D
		ball.radius += m
	elif s is CapsuleShape3D or s is CylinderShape3D:
		s.set(&"height", s.get(&"height") + 2.0 * m) # height first: a capsule keeps height >= 2 * radius
		s.set(&"radius", s.get(&"radius") + m)
	else:
		var b := cs.shape.get_debug_mesh().get_aabb()
		var box := BoxShape3D.new()
		box.size = b.size + Vector3.ONE * 2.0 * m
		return [box, cs.transform.translated_local(b.get_center())]
	return [s, cs.transform]
