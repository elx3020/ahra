@tool
class_name EnemyArea
extends Zone
## Where enemies patrol, or how far they chase: any shape (its CollisionShape3D children, edited
## with the Shape Tools plugin), shared by any number of enemies through Enemy.patrol_area and
## Enemy.chase_area. One area can be both.
## ponytail: point-inside tests only work for shapes with volume (box, sphere, capsule, cylinder,
## convex); concave and height-map shapes get a configuration warning.

const TRIES := 12 ## random_ground attempts before giving up


func _init() -> void:
	color = Color(1, 0.6, 0.2, 0.08)


## Whether the global `point` is inside one of the area's shapes.
func contains(point: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = point
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r: Dictionary in get_world_3d().direct_space_state.intersect_point(q, 32):
		if r.collider == self:
			return true
	return false


## A random feet point inside the area where `e` can be: dry ground (or any water, for a swimmer),
## and only under water for a SWIM-only enemy. Casts down through the area from its top, using
## the enemy's rng; null after TRIES misses.
func random_ground(e: Enemy) -> Variant:
	var b := bounds()
	var up := e.up_direction
	for i in TRIES:
		var x := b.position.x + e.rng.randf() * b.size.x
		var z := b.position.z + e.rng.randf() * b.size.z
		var hit := e.cast(to_global(Vector3(x, b.end.y, z)), to_global(Vector3(x, b.position.y, z)))
		if not hit:
			continue
		var g: Vector3 = hit.position
		if not contains(g + up * 0.5):
			continue
		var deep := e.deep_water_at(g)
		if (e.water_bound() and not deep) or (deep and not e.can(Enemy.Ability.SWIM)):
			continue
		return g
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for cs in shapes():
		if cs.shape is ConcavePolygonShape3D or cs.shape is HeightMapShape3D:
			out.append("%s: concave and height-map shapes can't tell whether a point is inside them. Use box, sphere, capsule, cylinder or convex shapes." % cs.name)
	return out
