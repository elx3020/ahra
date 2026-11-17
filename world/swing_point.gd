@tool
class_name SwingPoint
extends Node3D
## Anchor the player can grab (grab key) when within grab_radius while airborne.

@export var grab_radius := 7.0

var _rope := MeshInstance3D.new()


func _ready() -> void:
	add_to_group(&"swing_point")
	var knob := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	knob.mesh = s
	add_child(knob)
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.03
	c.height = 1.0
	_rope.mesh = c
	_rope.top_level = true
	_rope.visible = false
	add_child(_rope)


func show_rope(to: Vector3) -> void:
	var d := to - global_position
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	_rope.global_transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), global_position + d * 0.5)
	if not _rope.visible:
		_rope.reset_physics_interpolation()
		_rope.visible = true


func hide_rope() -> void:
	_rope.visible = false
