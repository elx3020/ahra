extends EnemyState
## SWING across a gap on Enemy.swing_point: a pendulum for the look, then a release onto
## Enemy.move_to on a free arc (Enemy.arc_to). Releasing early, just past the bottom, keeps the
## bob from swinging into the far edge, which on a symmetric pendulum sits below the mirror point.
## ponytail: the rope mesh belongs to the SwingPoint, so the player and an enemy on the same point
## share one rope.

var _len := 0.0
var _start := 0.0 ## planar distance behind the anchor at the grab, along _dir
var _dir := Vector3.ZERO
var _t := 0.0


func enter(_prev: StringName) -> void:
	var up := e.up_direction
	var anchor := e.swing_point.global_position
	_dir = (e.move_to - e.global_position).slide(up).normalized()
	_len = maxf(e.global_position.distance_to(anchor), 1.5)
	_start = (anchor - e.global_position).slide(up).dot(_dir)
	_t = 0.0
	e.velocity = _dir * 2.0
	e.facing = _dir
	e.anim = &"swing"
	e.cue.emit(&"swing")


func exit() -> void:
	if e.swing_point:
		e.swing_point.hide_rope()


func physics(delta: float) -> StringName:
	var up := e.up_direction
	var anchor := e.swing_point.global_position
	_t += delta
	e.velocity -= up * e.gravity * delta
	e.move_and_slide()
	var off := e.global_position - anchor
	if off.length() > _len: # rope: pull back, drop the outward speed
		var r := off.normalized()
		e.global_position = anchor + r * _len
		e.velocity -= r * maxf(e.velocity.dot(r), 0.0)
	e.swing_point.show_rope(e.global_position)
	var past := (e.global_position - anchor).slide(up).dot(_dir)
	if (e.vspeed() > 0.0 and past >= _start * 0.25) or _t > 4.0:
		var rise := (e.move_to - e.global_position).dot(up) + Enemy.HALF_HEIGHT
		e.launch = e.arc_to(e.move_to, maxf(rise + 1.0, 1.0))
		return &"jump"
	return &""
