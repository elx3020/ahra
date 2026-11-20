extends EnemyState
## The burrower's chase: digs in (untouchable), travels underground and surfaces next to the
## player -> attack (the burst). Each step needs ground within safe_drop that isn't under deep
## water. Rays leave a block through its back faces, so it passes under walls, but it never
## crosses a gap or water: blocked, it surfaces and gives up for give_up_time.
## It only surfaces in the open: a spot on a ring around the player with open sky above it, room
## for the body and a clear line to the player (_surface_spot). Giving up, it comes up at the
## last open spot it passed, never inside a wall.
## ponytail: "open sky" is a ray from 10 m up, so under a roof it never finds a spot; a proper
## inside-the-block test when burrowers go indoors.

const DIG_TIME := 0.6
const MAX_TRAVEL := 8.0 ## seconds underground before it surfaces anyway
const SPOT_RANGE := 6.0 ## looks for a surface spot once this close to the player
const PLAYER_HALF_HEIGHT := 0.9

var _t := 0.0
var _last_open := Vector3.ZERO ## feet point where it could surface if it has to give up


func enter(_prev: StringName) -> void:
	_t = 0.0
	_last_open = e.global_position - e.up_direction * Enemy.HALF_HEIGHT
	(e as Burrower).set_burrowed(true)
	e.anim = &"burrow_in"
	e.cue.emit(&"burrow_in")


func exit() -> void:
	(e as Burrower).set_burrowed(false)


func physics(delta: float) -> StringName:
	var b := e as Burrower
	_t += delta
	if not e.has_target() or e.dist_to_target() > e.lose_radius:
		return _give_up()
	if _t < DIG_TIME:
		return &""
	e.anim = &"burrowed"
	var up := e.up_direction
	var feet := e.global_position - up * Enemy.HALF_HEIGHT
	var goal := e.target_pos() - up * PLAYER_HALF_HEIGHT
	var spot: Variant = null
	if (goal - feet).slide(up).length() <= SPOT_RANGE:
		spot = _surface_spot()
		if spot == null and (goal - feet).slide(up).length() <= b.surface_radius:
			return _give_up() # right next to the player and nowhere to come up
		if spot != null:
			goal = spot
	var to := (goal - feet).slide(up)
	if spot != null and to.length() <= b.burrow_speed * delta:
		e.global_position = spot + up * Enemy.HALF_HEIGHT
		return &"attack"
	if _t > DIG_TIME + MAX_TRAVEL:
		return _give_up()
	var next := feet + to.normalized() * minf(b.burrow_speed * delta, to.length())
	var hit := e.cast(next + up * 0.5, next - up * e.safe_drop)
	if not hit or e.deep_water_at(hit.position) or e.leashed(e.chase_area, hit.position):
		return _give_up() # a gap, water, or the chase area's border
	e.face(e.target_pos())
	e.global_position = hit.position + up * Enemy.HALF_HEIGHT
	if _open_at(hit.position):
		_last_open = hit.position
	return &""


## The open spot nearest this enemy on a ring around the player (radius 0.8 x surface_radius):
## at the player's floor level, not under deep water, room for the body, a clear line to the
## player. A feet point, or null.
func _surface_spot() -> Variant:
	var b := e as Burrower
	var up := e.up_direction
	var t := e.target_pos()
	var floor_h := t.dot(up) - PLAYER_HALF_HEIGHT
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var best: Variant = null
	var best_d := INF
	for i in 8:
		var at := t + side.rotated(up, TAU * i / 8.0) * b.surface_radius * 0.8
		var hit := e.cast(at + up * 10.0, at - up * (PLAYER_HALF_HEIGHT + e.safe_drop))
		if not hit or absf((hit.position as Vector3).dot(up) - floor_h) > e.safe_drop:
			continue # the top of a wall (or a roof), or a drop
		var g: Vector3 = hit.position
		var c := g + up * (Enemy.HALF_HEIGHT + 0.1)
		var d := c.distance_to(e.global_position)
		if d < best_d and not e.deep_water_at(g) and not e.leashed(e.chase_area, g) and e.fits_at(c) and e.cast(c, t).is_empty():
			best = g
			best_d = d
	return best


## Open sky above this ground point (the first thing a ray from 10 m up meets is the point
## itself) and room for the body.
func _open_at(ground: Vector3) -> bool:
	var up := e.up_direction
	var hit := e.cast(ground + up * 10.0, ground - up * 0.2)
	return hit and absf((hit.position - ground).dot(up)) < 0.3 and e.fits_at(ground + up * (Enemy.HALF_HEIGHT + 0.1))


func _give_up() -> StringName:
	var up := e.up_direction
	if not _open_at(e.global_position - up * Enemy.HALF_HEIGHT):
		e.global_position = _last_open + up * Enemy.HALF_HEIGHT # still underground: nobody sees the move
	e.give_up = e.give_up_time
	e.cue.emit(&"blocked")
	return &"idle"
