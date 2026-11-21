class_name Projectile
extends Node3D
## A straight shot. Each physics frame it ray-casts from where it is to where it goes next, so it
## never tunnels. Hitting an Enemy calls Enemy.hit, hitting the Player calls Player.damage (ready
## for enemy shooters), anything with shot() (an EnergySwitch) charges it, anything else just
## ends it. The shooter (`source`) is ignored; a Player source registers the hit or miss for its
## mood. The scene's mesh is the slot for shot VFX.

@export var speed := 30.0
@export var life := 1.5 ## seconds before it fizzles out (a miss)

var velocity := Vector3.ZERO
var damage := 0.0
var push := 0.0 ## knockback impulse (Enemy.hit divides it by weight)
var source: Node3D


## Call after adding it to the tree.
func setup(from: Vector3, dir: Vector3, amount: float, knock: float, shooter: Node3D) -> void:
	global_position = from
	velocity = dir.normalized() * speed
	damage = amount
	push = knock
	source = shooter
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var to := global_position + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, to)
	q.hit_from_inside = true # fired point-blank into an enemy pressed against the shooter
	if is_instance_valid(source) and source is CollisionObject3D: # validity first: `is` errors on a freed shooter
		q.exclude = [(source as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_finish(hit.collider)
		return
	global_position = to
	life -= delta
	if life <= 0.0:
		_finish(null)


func _finish(target: Object) -> void:
	set_physics_process(false)
	var landed := false
	if target is Enemy:
		landed = (target as Enemy).hit(damage, push, global_position)
	elif target is Player:
		(target as Player).damage(damage, global_position)
	elif target and target.has_method(&"shot"): # an EnergySwitch (by method: it reaches World)
		target.shot()
		landed = true
	if is_instance_valid(source) and source is Player:
		(source as Player).register_attack(landed) # a hit the enemy ignored (puppet, i-frames) is a miss
	queue_free()
