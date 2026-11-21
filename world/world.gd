extends Node
## Autoload "World": state that outlives scene changes. The world clock and the
## platform channels live here, so every area computes its platforms from the same
## timeline. Story flags and NPC memory live here too. Saving the game = saving `time`,
## `channels`, `signals`, `flags` and `npcs` (plain data).
## It also owns the screen fade (`fade`), which survives scene changes.

signal flags_changed

var time := 0.0 ## world seconds; pauses with the tree, keeps running across scene changes
## Story flags: game-wide name -> int (keys are Strings). Set by NPC flag/leave steps or any code.
var flags := {}
## NPC memory per placement (Channels.id of the NPC): {plays = {interaction key: count},
## gone = bool, pos = Vector3, facing = Vector3}; pos/facing only once the NPC has moved.
var npcs := {}
var fade_rect: ColorRect ## the black full-screen overlay fade() tweens

var _fade_tween: Tween
var spawn: StringName ## marker the next area puts the player at (set by SceneDoor)
## channel key ("area:name", see Channels) -> state, changed by PlatformSwitches, read by tracks:
##   t0: last change, drive: [drive of starts-off, of starts-on platforms] at t0,
##   flip: power toggled, dir: +1/-1, run_start/run_end: RUN window (forced on),
##   rates: (speed, start wait, end wait) multipliers,
##   changes: rate history [[time, drive off, drive on, speed, start wait, end wait]],
##   bounds: run-once platforms' ends {track path#platform: [starts_on, low, high]}
var channels := {}
## end signals tracks have sent (PlatformSequence.end_signal): "area:track path#signal" -> how many
## times, so an area loading later neither misses nor repeats them
var signals := {}
## Door switch state per placement (Channels.id): {on, locked} for weight plates, {shot_at, end}
## (world times) for energy switches. Doors read it through openness(). Saved with the rest.
var switches := {}
## Weights' memory per placement (Channels.id): {pos, basis, gravity}, {gone = true} for a
## destroyed hand-placed one, {alive = names} for a dispenser. Written by GameArea and Dispenser.
var bodies := {}
## Every saved scene's door switches by channel (baked in the editor): see switches_of().
var registry: SwitchRegistry


func _ready() -> void:
	registry = load(SwitchRegistry.PATH) if ResourceLoader.exists(SwitchRegistry.PATH) else SwitchRegistry.new()
	var layer := CanvasLayer.new()
	layer.layer = 100
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade_rect)
	add_child(layer)


func _physics_process(delta: float) -> void:
	time += delta


## A story flag's value; 0 when unset.
func flag(flag_name: StringName) -> int:
	return flags.get(String(flag_name), 0)


## Sets a story flag (0 clears it) and tells listeners (NPCs re-check what they say and whether
## they are present).
func set_flag(flag_name: StringName, value := 1) -> void:
	flags[String(flag_name)] = value
	flags_changed.emit()


## The memory entry of the NPC placed at `id` (Channels.id), created on first use. Returned by
## reference: the NPC writes into it.
func npc_memory(id: String) -> Dictionary:
	if id not in npcs:
		npcs[id] = {plays = {}, gone = false}
	return npcs[id]


## Forgets every story flag and all NPC memory (a new game; the demo's debug key).
func reset_story() -> void:
	flags.clear()
	npcs.clear()
	flags_changed.emit()


## Tweens the screen overlay to `to_alpha` (1 = black) over `duration` seconds. Awaitable.
## A new fade replaces one still running, so `fade(0.0, 0.0)` clears the screen for good.
## ponytail: a replaced fade never emits `finished`, so whoever awaits it never resumes; today
## the only such awaiter is a leave whose NPC is gone. Return a cancel flag if fades ever overlap.
func fade(to_alpha: float, duration := 0.4) -> void:
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	if duration <= 0.0:
		fade_rect.color.a = to_alpha
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", to_alpha, duration)
	await _fade_tween.finished


## Motion seconds a channel has given its platforms so far: grows while they move,
## shrinks while reversed, held between the ends of any run-once platform on it.
## starts_on: platforms that move until a POWER switch stops them. `bounded` false: ignore the
## run-once ends, as if they kept going since the last change (when did they pass a point).
func drive(channel: StringName, starts_on: bool, bounded := true) -> float:
	var c: Dictionary = channels.get(channel, {})
	if c.is_empty():
		return time if starts_on else 0.0
	var run := maxf(0.0, minf(time, c.run_end) - maxf(c.t0, c.run_start))
	var moving := 1.0 if starts_on != c.flip else 0.0
	var d: float = c.drive[int(starts_on)] + c.dir * (run + (time - c.t0 - run) * moving)
	var low := INF
	var high := -INF
	for b: Array in c.bounds.values():
		if b[0] == starts_on:
			low = minf(low, b[1])
			high = maxf(high, b[2])
	return clampf(d, low, high) if bounded and low <= high else d


func changes(channel: StringName) -> Array:
	return channels.get(channel, {}).get("changes", [])


func rates(channel: StringName) -> Vector3:
	return channels.get(channel, {}).get("rates", Vector3.ONE)


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


## SPEED / START_WAIT / END_WAIT: new multipliers. Tracks re-time their program from where their platforms are.
func set_rates(channel: StringName, r: Vector3) -> void:
	var c := _settle(channel)
	c.rates = r
	c.changes.append([time, c.drive[0], c.drive[1], r.x, r.y, r.z])


## A track's end signal: the tracks on `channel` waiting for a switch start moving (like POWER;
## nothing happens if they already do), as if switched on at world time `at`, which is earlier
## than now when the signal fired while the area was away or the clock skipped.
func power_on(channel: StringName, at: float) -> void:
	var since: float = channels.get(channel, {}).get("t0", 0.0)
	var c := _settle(channel)
	if c.flip:
		return
	c.flip = true
	var late := clampf(time - at, 0.0, time - since)
	c.drive[0] += c.dir * late # the waiting tracks have been moving since `at`...
	c.drive[1] -= c.dir * late # ...and always-on ones on the channel stopped then, as with POWER


## A run-once platform's program ends, in drive seconds (see PlatformProgram._rebase).
func bound(channel: StringName, platform: String, starts_on: bool, low: float, high: float) -> void:
	_settle(channel).bounds[platform] = [starts_on, low, high]


## Brings a channel's drive up to now (creating it if needed) before a change.
func _settle(channel: StringName) -> Dictionary:
	if channel not in channels:
		channels[channel] = {t0 = 0.0, drive = [0.0, 0.0], flip = false, dir = 1.0, run_start = 0.0,
			run_end = 0.0, rates = Vector3.ONE, changes = [], bounds = {}}
	var c: Dictionary = channels[channel]
	c.drive = [drive(channel, false), drive(channel, true)]
	c.t0 = time
	return c


## The switches on a door channel: [id, kind] pairs, kind "hold", "latch" or "energy". The baked
## registry (every saved scene, visited or not) plus the switches loaded now (scenes built in code).
## ponytail: scans the door_switch group on every call; cache per physics frame if puzzles get big.
func switches_of(channel: StringName) -> Array:
	var out: Array = registry.channels.get(String(channel), []).duplicate()
	var seen := {}
	for s: Array in out:
		seen[s[0]] = true
	for n in get_tree().get_nodes_in_group(&"door_switch"):
		var id: String = n.switch_id()
		if not seen.has(id) and Channels.key(n, n.channel) == channel:
			seen[id] = true
			out.append([id, n.kind()])
	return out


## A weight plate's state changed (`on`: something rests on it). Latch plates lock when this
## makes every switch on the channel on at once.
func press(channel: StringName, id: String, on: bool) -> void:
	var s: Dictionary = switches.get(id, {on = false, locked = false})
	s.on = on
	switches[id] = s
	_check_lock(channel)


## A shot hit an energy switch: `add` more seconds of energy, at most `cap` seconds in all.
func charge(channel: StringName, id: String, add: float, cap: float) -> void:
	var s: Dictionary = switches.get(id, {shot_at = 0.0, end = 0.0})
	var left := maxf(s.end - time, 0.0)
	s.end = time + minf(left + add, cap)
	s.shot_at = time
	switches[id] = s
	_check_lock(channel)


## Plates: on or locked. Energy switches: energy left. A switch with no state yet is off.
func switch_on(id: String) -> bool:
	var s: Dictionary = switches.get(id, {})
	if s.has("end"):
		return time < s.end
	return s.get("on", false) or s.get("locked", false)


## An energy switch's charge left, 0..1 of what it had at its last shot.
func energy(id: String) -> float:
	var s: Dictionary = switches.get(id, {})
	if not s.has("end") or s.end <= s.shot_at:
		return 0.0
	return clampf((s.end - time) / (s.end - s.shot_at), 0.0, 1.0)


## How open the doors on `channel` are, 0..1: shut unless every switch is on; with energy
## switches, the smallest charge left (the door slides shut as it drains).
func openness(channel: StringName) -> float:
	var list := switches_of(channel)
	if list.is_empty():
		return 0.0
	var out := 1.0
	for s: Array in list:
		if not switch_on(s[0]):
			return 0.0
		if s[1] == "energy":
			out = minf(out, energy(s[0]))
	return out


## The doors are open for good: every switch on the channel is a locked latch plate.
func solved(channel: StringName) -> bool:
	var list := switches_of(channel)
	return not list.is_empty() and list.all(func(s: Array) -> bool:
		return s[1] == "latch" and switches.get(s[0], {}).get("locked", false))


func _check_lock(channel: StringName) -> void:
	var list := switches_of(channel)
	if list.is_empty() or not list.all(func(s: Array) -> bool: return switch_on(s[0])):
		return
	for s: Array in list:
		if s[1] == "latch":
			var st: Dictionary = switches.get(s[0], {on = true, locked = false})
			st.locked = true
			switches[s[0]] = st


func debug_text() -> String:
	var out := ""
	for ch: StringName in channels:
		var c: Dictionary = channels[ch]
		out += "\n  %s: %s%s, speed x%.2f, start wait x%.2f, end wait x%.2f%s" % [ch,
			"toggled, " if c.flip else "", "reversed" if c.dir < 0.0 else "forward", c.rates.x, c.rates.y, c.rates.z,
			", running %.1fs" % (c.run_end - time) if time < c.run_end else ""]
	var pairs := PackedStringArray()
	for f: String in flags:
		pairs.append("%s=%d" % [f, flags[f]])
	var on := PackedStringArray()
	for id: String in switches:
		if switch_on(id):
			on.append(id.get_slice(":", 1) + (" (locked)" if switches[id].get("locked", false) else ""))
	return "\nchannels:" + (out if out else " none") + "\nflags: " + (", ".join(pairs) if pairs else "none") \
		+ "\nswitches: " + (", ".join(on) + " on" if on else "none on")
