extends PlayerState
## Cause-specific death (Player.death_cause: fall / drown / hit), then respawn at the
## checkpoint. No input; physics keeps running, so a fall keeps falling and a
## drowned body drifts in the water. Add causes here + an anim in Player._animate.

const DURATION := {&"fall": 1.0, &"drown": 2.5, &"hit": 1.5}

var _t := 0.0


func enter(_prev: StringName) -> void:
	p.anim = StringName("death_%s" % p.death_cause)
	_t = DURATION.get(p.death_cause, 1.5)


func physics(delta: float) -> StringName:
	p.move_planar(Vector3.ZERO, 0.0, 8.0, delta)
	p.apply_gravity(delta)
	p.slide()
	_t -= delta
	if _t <= 0.0:
		p.respawn()
	return &""
