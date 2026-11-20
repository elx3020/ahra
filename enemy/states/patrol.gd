extends EnemyState
## Roaming Enemy.patrol_area while the player hasn't been spotted: goes to a random spot in it
## (EnemyArea.random_ground) with its usual moves, the area's border counting as a ledge, at walk
## speed and without spending stamina. Arrived, blocked or stuck -> idle, which rests and comes back
## with a new spot. Outside the area, any spot inside brings it back. A move (jump, swim...) returns
## here with the same spot.

const MOVES: Array[StringName] = [&"jump", &"dash", &"climb", &"swim", &"swing"]

var _spot := Vector3.ZERO
var _none := false


func enter(prev: StringName) -> void:
	e.reset_watchdog()
	e.anim = &"walk"
	if prev in MOVES and not _none:
		return
	var spot: Variant = e.patrol_area.random_ground(e) if is_instance_valid(e.patrol_area) else null
	_none = spot == null
	if spot != null:
		_spot = spot
		e.aim_override = spot


func physics(delta: float) -> StringName:
	if _none or not is_instance_valid(e.patrol_area):
		return &"idle"
	if e.flail(delta):
		return &""
	if e.give_up <= 0.0 and e.sees_target():
		return &"pursuit"
	if e.swimming():
		e.goal = &"patrol"
		return &"swim"
	if not e.is_on_floor() and not e.can(Enemy.Ability.FLY):
		e.goal = &"patrol"
		return &"jump"
	if (_spot - e.global_position).slide(e.up_direction).length() < 0.5:
		return &"idle"
	var next := e.step_toward(_spot, delta, e.patrol_area, false)
	if next == &"blocked" or (next == &"" and not e.moving_on(delta)):
		return &"idle"
	return next
