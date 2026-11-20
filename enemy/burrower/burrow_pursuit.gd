extends EnemyState
## The burrower's chase: digs in (untouchable), travels underground toward the player and
## surfaces next to them -> attack (the burst). Each step needs ground within safe_drop that isn't
## under deep water. Rays leave a block through its back faces, so it passes under walls, but it
## never crosses a gap or water: blocked, it surfaces where it is and gives up for give_up_time.

const DIG_TIME := 0.6
const MAX_TRAVEL := 8.0 ## seconds underground before it surfaces anyway

var _t := 0.0


func enter(_prev: StringName) -> void:
	_t = 0.0
	(e as Burrower).set_burrowed(true)
	e.anim = &"burrow_in"
	e.cue.emit(&"burrow_in")


func exit() -> void:
	(e as Burrower).set_burrowed(false)


func physics(delta: float) -> StringName:
	var b := e as Burrower
	_t += delta
	if not e.has_target() or e.dist_to_target() > e.lose_radius:
		return &"idle"
	if _t < DIG_TIME:
		return &""
	e.anim = &"burrowed"
	var up := e.up_direction
	var to := (e.target_pos() - e.global_position).slide(up)
	if to.length() <= b.surface_radius:
		return &"attack"
	if _t > DIG_TIME + MAX_TRAVEL:
		return _give_up()
	var feet := e.global_position - up * Enemy.HALF_HEIGHT
	var next := feet + to.normalized() * minf(b.burrow_speed * delta, to.length())
	var hit := e.cast(next + up * 0.5, next - up * e.safe_drop)
	if not hit or e.deep_water_at(hit.position):
		return _give_up()
	e.face(e.target_pos())
	e.global_position = hit.position + up * Enemy.HALF_HEIGHT
	return &""


func _give_up() -> StringName:
	e.give_up = e.give_up_time
	e.cue.emit(&"blocked")
	return &"idle"
