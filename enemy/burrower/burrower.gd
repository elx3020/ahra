class_name Burrower
extends Enemy
## Digs in, travels underground toward the player (under walls, never across gaps or water),
## bursts out next to them and rests stunned: the player's window. Heavy, so pushes don't move it.
## Plays the shared states its own way: pursuit = dig + travel (burrow_pursuit.gd), attack = the
## surfacing burst (burrow_attack.gd). Every other state is the base one.

@export_group("Burrow")
@export var burrow_speed := 7.0
@export var surface_radius := 1.5 ## surfaces this close to the player (planar)
@export var burst_radius := 2.0
@export var burst_damage := 20.0
@export var rest_time := 2.5 ## stun after the burst

var burrowed := false
var _layer := 0


func _init() -> void:
	states[&"pursuit"] = preload("burrow_pursuit.gd").new()
	states[&"attack"] = preload("burrow_attack.gd").new()


## Underground: on no collision layer, so nothing hits it and triggers don't see it; only the
## mound shows. The mask stays: the travel rays (Enemy.cast) use it. It moves by position, so the
## mask never blocks it.
func set_burrowed(on: bool) -> void:
	if on == burrowed:
		return
	burrowed = on
	if on:
		_layer = collision_layer
		collision_layer = 0
		velocity = Vector3.ZERO
	else:
		collision_layer = _layer
	$Visual.visible = not on
	$Mound.visible = on
