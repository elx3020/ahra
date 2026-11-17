@tool
class_name Zone
extends Area3D
## Box trigger that builds its own collision shape + translucent debug box from `size`.
## Subclasses override _player_entered/_player_exited.

@export var size := Vector3(4, 3, 4):
	set(v):
		size = v
		_build()
@export var color := Color(1, 1, 1, 0.2):
	set(v):
		color = v
		_build()

var _shape := BoxShape3D.new()
var _mesh := BoxMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material = _mat
	_build()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


func _build() -> void:
	_shape.size = size
	_mesh.size = size
	_mat.albedo_color = color


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
