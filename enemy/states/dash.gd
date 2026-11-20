extends EnemyState
## Fixed-speed burst toward Enemy.move_to (a landing across a gap), no gravity. Ends back at goal,
## or falling if it came up short.

var _t := 0.0
var _dir := Vector3.ZERO


func enter(_prev: StringName) -> void:
	var to := (e.move_to - e.global_position).slide(e.up_direction)
	_dir = to.normalized()
	e.facing = _dir
	_t = minf(e.dash_distance, to.length() + 0.8) / e.dash_speed
	e.spend(e.dash_cost)
	e.anim = &"dash"
	e.cue.emit(&"dash")


func physics(delta: float) -> StringName:
	e.velocity = _dir * e.dash_speed
	e.move_and_slide()
	_t -= delta
	if _t > 0.0:
		return &""
	e.velocity = e.velocity.limit_length(e.walk_speed)
	return e.goal if e.is_on_floor() else &"jump"
