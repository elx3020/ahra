class_name SlowMo
extends RefCounted
## Slow motion, static only: the one owner of Engine.time_scale. Three factors multiply:
## - a hit-stop (`add(feel)`): a brief dip when the player is hurt or lands a hit. One at a time:
##   while one runs, new ones are dropped (not queued), so a swing hitting two enemies plays one.
##   Only a stronger feel in the same physics frame replaces it (a hit and a hurt at once).
## - `area`: the player's EnvProfile.time_scale, set by GameArea (slow places).
## - bullet time: `bullet_target`, set by the Player, eased; the Player divides `bullet` out of
##   its own clock so it keeps full speed.
## World applies `update()` every frame (also while paused: then the scale is 1, so menus never
## slow). Hit-stop lengths are real seconds. The toggle DISABLE is read in `add` (a running stop
## finishes) and covers hit-stops only. Must not reference the World autoload (Player, Enemy and
## Projectile call it; -s tests compile it first).

enum Feel { SHOT, HIT, HURT, KILL } ## later = stronger (the same-frame tie-break)

const DISABLE := "ahra/time/disable_hit_stop"
const MIN_SCALE := 0.02 ## the product never goes lower (time_scale 0 stalls the game)
const BULLET_EASE := 0.15 ## seconds to ease between full speed and 0.3
## speed: the world's speed while it holds; hold, then ramp back to 1 (smoothstep), real seconds
const FEELS := {
	Feel.SHOT: {speed = 0.3, hold = 0.04, ramp = 0.04}, ## a player shot hits an enemy
	Feel.HIT: {speed = 0.12, hold = 0.07, ramp = 0.05}, ## a melee swing lands (any number of enemies)
	Feel.HURT: {speed = 0.08, hold = 0.10, ramp = 0.08}, ## the player is hurt
	Feel.KILL: {speed = 0.05, hold = 0.14, ramp = 0.10}, ## a player attack kills, or the player dies
}

static var area := 1.0 ## the player's env time_scale, set by GameArea every frame
static var bullet_target := 1.0 ## set by the Player: its bullet_scale while on, 1 while off
static var bullet := 1.0 ## the bullet factor inside the last returned scale (1 while paused)
static var real_delta := 0.0 ## the last update's unscaled frame time
static var stops := 0 ## hit-stops started (tests read it)
static var stop := {} ## the running hit-stop {feel, age, frame}; empty when none
static var _level := 1.0 ## the eased bullet factor, kept while paused


## A hit-stop, unless one is running (or the toggle is on).
static func add(feel: Feel) -> void:
	if ProjectSettings.get_setting(DISABLE, false):
		return
	var frame := Engine.get_physics_frames()
	if stop.is_empty():
		stops += 1
	elif not (stop.frame == frame and feel > stop.feel):
		return
	stop = {feel = feel, age = 0.0, frame = frame}


## Ages the stop by `real_dt`, eases bullet time, and returns the next Engine.time_scale.
static func update(real_dt: float, paused: bool) -> float:
	real_delta = real_dt
	if paused:
		bullet = 1.0
		return 1.0
	_level = move_toward(_level, bullet_target, real_dt * 0.7 / BULLET_EASE)
	bullet = _level
	var f := 1.0
	if not stop.is_empty():
		stop.age += real_dt
		var p: Dictionary = FEELS[stop.feel]
		if stop.age >= p.hold + p.ramp:
			stop = {}
		else:
			f = lerpf(p.speed, 1.0, smoothstep(0.0, p.ramp, stop.age - p.hold))
	return maxf(MIN_SCALE, f * area * bullet)


static func clear() -> void:
	stop = {}
	area = 1.0
	bullet_target = 1.0
	bullet = 1.0
	_level = 1.0
