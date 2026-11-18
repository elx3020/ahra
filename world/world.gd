extends Node
## Autoload "World": state that outlives scene changes. The world clock and the
## platform channels live here, so every area computes its platforms from the same
## timeline. Saving the game = saving `time` and `channels` (plain data).

var time := 0.0 ## world seconds; pauses with the tree, keeps running across scene changes
var spawn: StringName ## marker the next area puts the player at (set by SceneDoor)
## channel -> state, changed by PlatformSwitches, read by MovingPlatforms:
##   t0: last change, drive: [drive of starts-off, of starts-on platforms] at t0,
##   flip: power toggled, dir: +1/-1, run_start/run_end: RUN window (forced on),
##   rates: (speed, cooldown) multipliers, changes: rate history [[time, drive off, drive on, speed, cooldown]]
var channels := {}


func _physics_process(delta: float) -> void:
	time += delta


## Motion seconds a channel has given its platforms so far: grows while they move,
## shrinks while reversed. starts_on: platforms that move until a POWER switch stops them.
func drive(channel: StringName, starts_on: bool) -> float:
	var c: Dictionary = channels.get(channel, {})
	if c.is_empty():
		return time if starts_on else 0.0
	var run := maxf(0.0, minf(time, c.run_end) - maxf(c.t0, c.run_start))
	var moving := 1.0 if starts_on != c.flip else 0.0
	return c.drive[int(starts_on)] + c.dir * (run + (time - c.t0 - run) * moving)


func changes(channel: StringName) -> Array:
	return channels.get(channel, {}).get("changes", [])


func rates(channel: StringName) -> Vector2:
	return channels.get(channel, {}).get("rates", Vector2.ONE)


## POWER: moving <-> stopped.
func toggle(channel: StringName) -> void:
	var c := _settle(channel)
	c.flip = not c.flip


## RUN: after `delay`, move for `duration` seconds (a new press restarts it).
func run(channel: StringName, delay: float, duration: float) -> void:
	var c := _settle(channel)
	c.run_start = time + delay
	c.run_end = time + delay + duration


## REVERSE: platforms retrace their motion.
func reverse(channel: StringName) -> void:
	_settle(channel).dir *= -1.0


## SPEED / COOLDOWN: new multipliers. Platforms re-time their program from where they are.
func set_rates(channel: StringName, r: Vector2) -> void:
	var c := _settle(channel)
	c.rates = r
	c.changes.append([time, c.drive[0], c.drive[1], r.x, r.y])


## Brings a channel's drive up to now (creating it if needed) before a change.
func _settle(channel: StringName) -> Dictionary:
	if channel not in channels:
		channels[channel] = {t0 = 0.0, drive = [0.0, 0.0], flip = false, dir = 1.0,
			run_start = 0.0, run_end = 0.0, rates = Vector2.ONE, changes = []}
	var c: Dictionary = channels[channel]
	c.drive = [drive(channel, false), drive(channel, true)]
	c.t0 = time
	return c


func debug_text() -> String:
	var out := ""
	for ch: StringName in channels:
		var c: Dictionary = channels[ch]
		out += "\n  %s: %s%s, speed x%.2f, cooldown x%.2f%s" % [ch, "toggled, " if c.flip else "",
			"reversed" if c.dir < 0.0 else "forward", c.rates.x, c.rates.y,
			", running %.1fs" % (c.run_end - time) if time < c.run_end else ""]
	return "\nchannels:" + (out if out else " none")
