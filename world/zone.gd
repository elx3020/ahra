@tool
class_name Zone
extends Area3D
## Trigger volume: an Area3D whose CollisionShape3D children are its shape, any mix of box,
## sphere, capsule, cylinder, height map, convex and concave. Each shape is drawn as a
## translucent `color` mesh, in the editor and in game.
## With the Shape Tools plugin (addons/shape_tools) the inspector's Shapes section adds, removes
## and edits the shapes, and the viewport shows resize handles while the zone is selected.
## Subclasses override _player_entered/_player_exited, and _enemy_entered/_enemy_exited
## where enemies are affected too (EnvZone, KillZone).

@export var color := Color(1, 1, 1, 0.2):
	set(v):
		color = v
		_mat.albedo_color = v

var _mat := StandardMaterial3D.new()
var _seen := [null, null] ## ShapeSet.refresh state


func _ready() -> void:
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	_seen = ShapeSet.setup(self, _mat, false)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_seen = ShapeSet.refresh(self, _seen, _mat, false)


## The CollisionShape3D children that have a shape.
func shapes() -> Array[CollisionShape3D]:
	return ShapeSet.of(self)


## Box around all the shapes, in zone space.
func bounds() -> AABB:
	return ShapeSet.bounds(self)


## Adds a shape at `at` (zone space). For zones built in code; in the editor use the inspector.
func add_shape(shape: Shape3D, at := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	add_child(cs)
	if is_node_ready():
		_seen = ShapeSet.refresh(self, _seen, _mat, false)
	return cs


func _get_property_list() -> Array[Dictionary]:
	return ShapeSet.property_list(self)


func _get(property: StringName) -> Variant:
	return ShapeSet.get_row(self, property)


func _set(property: StringName, value: Variant) -> bool:
	return ShapeSet.set_row(self, property, value)


func _on_body_entered(b: Node3D) -> void:
	if b is Player:
		_player_entered(b)
	elif b is Enemy:
		_enemy_entered(b)


func _on_body_exited(b: Node3D) -> void:
	if b is Player:
		_player_exited(b)
	elif b is Enemy:
		_enemy_exited(b)


func _player_entered(_p: Player) -> void:
	pass


func _player_exited(_p: Player) -> void:
	pass


## Enemies get their own hooks: most triggers (checkpoints, doors, cutscenes) are player-only.
func _enemy_entered(_e: Enemy) -> void:
	pass


func _enemy_exited(_e: Enemy) -> void:
	pass
