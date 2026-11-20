extends EnemyState
## The burrower's attack: bursts out of the ground, hurting the player within burst_radius (the
## player's own knockback applies), then rests stunned for rest_time.

const BURST_TIME := 0.4

var _t := 0.0


func enter(_prev: StringName) -> void:
	var b := e as Burrower
	_t = 0.0
	e.anim = &"surface"
	e.cue.emit(&"surface")
	e.attack_cd = e.attack_cooldown
	if e.has_target() and e.dist_to_target() <= b.burst_radius and e.cast(e.global_position, e.target_pos()).is_empty():
		var hp := e.target.health
		e.target.damage(b.burst_damage, e.global_position)
		if e.target.health < hp:
			e.mood = minf(e.mood + 0.1, 1.0)


func physics(delta: float) -> StringName:
	e.hold(delta)
	_t += delta
	if _t < BURST_TIME:
		return &""
	e.stun_for = (e as Burrower).rest_time
	return &"stun"
