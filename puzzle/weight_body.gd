@tool
class_name WeightBody
extends RigidBody3D
## A weight: a box or a ball that presses weight plates. Characters push it by walking into it
## (push_from), the player carries and throws it. Its gravity is its own and sticky, like the
## player's: a GravityZone sets it on entry and nothing sets it back. Heavier means slower to push,
## more friction, more stamina to carry and shorter throws.
## Its shape is its CollisionShape3D children, drawn as lit `color` meshes (ShapeSet).
## Never references World: Player and Zone type it, and -s tests compile those before autoloads
## exist. GameArea and Dispenser remember it (state / restore).

signal destroyed
signal cue(name: StringName) ## land (a hard impact), destroy

const LAND_SPEED := 6.0 ## impact speed (m/s) that cues a landing

@export_range(0.1, 1000.0, 0.1, "or_greater") var weight := 12.0 ## its mass; push speed, carry drain and throw distance scale with it
@export var gravity := 32.0 ## the same pull as the player
@export var color := Color(0.75, 0.6, 0.4):
	set(v):
		color = v
		_mat.albedo_color = v

var gravity_dir := Vector3.DOWN
var carrier: Node3D ## the player while it is carried (frozen, collision off)
var gone := false ## destroyed: freed at the end of the frame
var dispensed := false ## spawned by a Dispenser, which remembers it (not placed in the scene)

var _mat := StandardMaterial3D.new()
var _seen := [null, null] ## ShapeSet.refresh state
var _last_speed := 0.0


func _ready() -> void:
	_mat.albedo_color = color
	_seen = ShapeSet.setup(self, _mat, true)
	add_to_group(&"weight")
	if Engine.is_editor_hint():
		return
	mass = weight
	linear_damp = weight * 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = clampf(0.1 + weight * 0.01, 0.1, 0.5)
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(func(_b: Node) -> void:
		if _last_speed > LAND_SPEED:
			cue.emit(&"land"))
	set_gravity_dir(gravity_dir)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_seen = ShapeSet.refresh(self, _seen, _mat, true)
		return
	_last_speed = linear_velocity.length()


## Sticky gravity along `dir`: the engine's gravity is off, a constant force pulls instead.
func set_gravity_dir(dir: Vector3) -> void:
	gravity_dir = dir.normalized()
	gravity_scale = 0.0
	constant_force = gravity_dir * gravity * mass
	sleeping = false


## Moves its planar velocity (across its own up) toward `dir * speed`, scaled by how strong the
## pusher is against its weight.
func push(dir: Vector3, speed: float, strength: float) -> void:
	var up := -gravity_dir
	var vert := linear_velocity.project(up)
	var target := dir.slide(up).normalized() * speed * clampf(strength / weight, 0.05, 1.0)
	var flat := linear_velocity - vert
	if flat.dot(target.normalized()) < target.length(): # never slows one already going faster
		linear_velocity = vert + flat.slide(target.normalized()) + target
	sleeping = false


## Pushes every weight `body` walked into this frame (its slide collisions): side contacts only, so
## standing on a weight doesn't shove it. Call right after the body's move_and_slide.
static func push_from(body: CharacterBody3D, strength: float, speed: float) -> void:
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var w := c.get_collider() as WeightBody
		if w == null or w.carrier != null or w.gone:
			continue
		var n := c.get_normal().slide(body.up_direction)
		if n.length() > 0.5:
			w.push(-n.normalized(), speed, strength)


## Lost for good (a kill zone, out of the area's bounds): a dispenser replaces it.
func destroy() -> void:
	if gone:
		return
	gone = true
	cue.emit(&"destroy")
	destroyed.emit()
	queue_free()


## What GameArea remembers of it.
func state() -> Dictionary:
	return {pos = global_position, basis = global_basis, gravity = gravity_dir}


func restore(s: Dictionary) -> void:
	global_transform = Transform3D(s.basis, s.pos)
	set_gravity_dir(s.gravity)
	linear_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _get_property_list() -> Array[Dictionary]:
	return ShapeSet.property_list(self)


func _get(property: StringName) -> Variant:
	return ShapeSet.get_row(self, property)


func _set(property: StringName, value: Variant) -> bool:
	return ShapeSet.set_row(self, property, value)
