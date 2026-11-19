@tool
class_name PlatformProgram
extends Node3D
## What moves a platform: the sequences of a PlatformTrackInstance, or, in a circuit (a
## PlatformTrackGroup with `circuit` on), the sequences of each of its tracks in turn. It owns
## the timing (what happens after the last sequence, offset, switches) and drives its
## MovingPlatform child, plus copies of it when `platforms` > 1.
## Position is a pure function of time and channel, never simulated step by step: it can't
## drift, the platform is already in place when an area loads, and tracks with the same timing
## stay in sync forever.

enum End {
	STOP, ## stay where the last sequence leaves the platform (a REVERSE switch brings it back)
	START_OVER, ## play the sequences again from the first (they should end where they start)
	PLAY_BACKWARDS, ## play them backwards to the start, then forwards again...
}

const PROGRAM := [&"after_last", &"offset", &"platforms", &"channel", &"starts_on", &"show_track"]

@export_group("Program")
@export var after_last := End.START_OVER ## once the last sequence ends (never, if one repeats forever)
@export var offset := 0.0 ## seconds ahead on the timeline: shifts it against other tracks on the same clock
@export_range(1, 16, 1, "or_greater") var platforms := 1 ## platforms riding it, spread evenly in time (copies of the first)
@export_group("Switches")
@export var channel: StringName ## PlatformSwitches on this channel control it (empty = world clock, no switches)
@export var starts_on := true ## always on: moves until a POWER switch stops it; off = waits for a switch
@export_group("Display")
@export var preview := false ## move the platforms in the editor, to check timing and sync
@export var show_track := true ## draw the path in game, so players can read where it goes

## Editor only: the scene timing preview's clock (Platform Tools), which every program shows
## instead of its own preview; -1 = off.
static var editor_clock := -1.0

var _plan: Array = [] ## compiled program, one entry per wait or leg: [seconds, path, from, to] (distances along the path)
var _duration := 0.0 ## seconds of the whole plan
var _loop_from := -1.0 ## seconds into the plan where a forever sequence's repeating part starts (-1: none)
var _spacing := 0.0 ## seconds between the platform and each copy (at x1 rates)
var _rates := Vector3.ONE ## channel multipliers: speed, start wait, end wait
var _riders: Array[MovingPlatform] = [] ## the platform, then its copies
var _shifts: Array[float] = [] ## per rider: program clock shift keeping motion continuous across rate changes
var _rebased := -1 ## channel rate changes folded into _shifts
var _copied := [] ## what the copies were built from


## True when this node runs a platform (a track outside a circuit, or a circuit).
func plays() -> bool:
	return true


## The tracks whose sequences make up the program, in order.
func tracks() -> Array:
	return []


## The MovingPlatform child (null if missing).
func platform() -> MovingPlatform:
	for c in get_children():
		if c is MovingPlatform:
			return c
	return null


func _validate_property(p: Dictionary) -> void:
	if p.name in PROGRAM and not plays():
		p.usage = PROPERTY_USAGE_NO_EDITOR


func _ready() -> void:
	if not plays():
		return
	_compile()
	_sync_copies()
	if not Engine.is_editor_hint() and show_track:
		_draw_tracks()
	_follow()
	for r in _riders:
		r.reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if not plays():
		return
	if Engine.is_editor_hint():
		_compile() # pick up inspector and path edits
		_sync_copies()
	_follow()


## Program seconds for rider i: channel drive (or world clock) + offset + its spacing.
func motion_time(rider := 0) -> float:
	var t := offset + rider * _spacing
	if Engine.is_editor_hint():
		if editor_clock >= 0.0:
			return t + editor_clock # switched tracks too: as if switched on at 0
		return t + (Time.get_ticks_msec() * 0.001 if _previewing() else 0.0)
	return t + (World.drive(channel, starts_on) if channel else World.time)


## Where rider i is after t program seconds.
func point_at(t: float, rider := 0) -> Vector3:
	if _plan.is_empty():
		return global_position
	var x: float = _fold(t + (_shifts[rider] if rider < _shifts.size() else 0.0))[2]
	var at := _locate(x)
	var e: Array = _plan[int(at.x)]
	return _at(e[1], lerpf(e[2], e[3], at.y))


func _previewing() -> bool:
	return preview or (get_parent() is PlatformProgram and get_parent().preview)


func _follow() -> void:
	if _duration <= 0.0:
		return
	if channel and not Engine.is_editor_hint():
		_rebase()
	for i in _riders.size():
		if is_instance_valid(_riders[i]):
			_riders[i].global_position = point_at(motion_time(i), i)


## Distance s along `path`, as a world point: closed paths wrap, open ones stop at their ends.
func _at(path: Path3D, s: float) -> Vector3:
	var length := path.curve.get_baked_length()
	return path.to_global(path.curve.sample_baked(fposmod(s, length) if path.curve.closed else clampf(s, 0.0, length)))


func _compile() -> void:
	_plan.clear()
	_duration = 0.0
	_loop_from = -1.0
	for t: PlatformTrackInstance in tracks():
		t.chain_sequences()
		var path := t.path()
		if path == null or path.curve == null or path.curve.point_count < 2:
			continue
		for q in t.sequences:
			if q == null or not _add_legs(q, path):
				continue
			if q.trips == 0:
				break # it never ends: nothing after it plays
		if _loop_from >= 0.0:
			break
	if _rates == Vector3.ONE:
		_spacing = _cycle() / platforms


## Appends sequence q's waits and legs along `path` (false if its anchors are unusable).
func _add_legs(q: PlatformSequence, path: Path3D) -> bool:
	var curve := path.curve
	var n := curve.point_count
	if q.start_anchor < 0 or q.end_anchor < 0 or q.start_anchor >= n or q.end_anchor >= n:
		return false
	var length := curve.get_baked_length()
	var a := curve.get_closest_offset(curve.get_point_position(q.start_anchor))
	var span := curve.get_closest_offset(curve.get_point_position(q.end_anchor)) - a
	if curve.closed:
		span = fposmod(span, length) # forward round the loop
		if is_zero_approx(span):
			span = length # same anchor: a full lap
	elif is_zero_approx(span):
		return false
	var travel := absf(span) / maxf(q.speed * _rates.x, 0.01)
	var legs := q.trips * (2 if q.round_trip else 1)
	if q.trips == 0:
		legs = 2 if q.turns() else 1 # one period of the forever part
		_loop_from = _duration
	for k in legs:
		if q.turns() and k % 2 == 1:
			_push([travel, path, a + span, a])
		else:
			_push([q.start_wait * _rates.y, path, a, a])
			_push([travel, path, a, a + span])
			_push([q.end_wait * _rates.z, path, a + span, a + span])
	return true


func _push(e: Array) -> void:
	_plan.append(e)
	_duration += e[0]


## Seconds after which the motion repeats.
func _cycle() -> float:
	if _loop_from >= 0.0:
		return _duration - _loop_from
	return 2.0 * _duration if after_last == End.PLAY_BACKWARDS else _duration


## Program time -> [period, playing backwards, seconds into the plan].
func _fold(t: float) -> Array:
	var d := _duration
	if d <= 0.0:
		return [0.0, false, 0.0]
	if _loop_from >= 0.0:
		if t < _loop_from and _loop_from > 0.0:
			return [0.0, false, maxf(t, 0.0)]
		var k := floorf((t - _loop_from) / (d - _loop_from))
		return [k, false, t - k * (d - _loop_from)]
	match after_last:
		End.STOP:
			return [0.0, false, clampf(t, 0.0, d)]
		End.START_OVER:
			var k := floorf(t / d)
			return [k, false, t - k * d]
	var k := floorf(t / (2.0 * d))
	var u := t - k * 2.0 * d
	return [k, u > d, 2.0 * d - u if u > d else u]


func _unfold(k: float, backwards: bool, x: float) -> float:
	if _loop_from >= 0.0:
		return x + k * (_duration - _loop_from)
	match after_last:
		End.STOP:
			return x
		End.START_OVER:
			return k * _duration + x
	return k * 2.0 * _duration + (2.0 * _duration - x if backwards else x)


## Seconds into the plan -> (plan entry, fraction of it).
func _locate(x: float) -> Vector2:
	for i in _plan.size():
		var d: float = _plan[i][0]
		if x < d:
			return Vector2(i, x / d)
		x -= d
	return Vector2(_plan.size() - 1, 1.0)


func _time_at(at: Vector2) -> float:
	var x := 0.0
	for i in int(at.x):
		x += _plan[i][0]
	return x + at.y * _plan[int(at.x)][0]


## Speed / wait switches change entry lengths: shift each rider's clock so it carries on from
## the same entry and fraction of it instead of jumping.
func _rebase() -> void:
	var changes := World.changes(channel)
	if changes.size() == _rebased:
		return
	_rates = Vector3.ONE
	_compile()
	_shifts.fill(0.0)
	for c: Array in changes:
		var spots := []
		for i in _riders.size():
			var t: float = c[2 if starts_on else 1] + offset + i * _spacing
			var f := _fold(t + _shifts[i])
			spots.append([t, f, _locate(f[2])])
		_rates = Vector3(c[3], c[4], c[5])
		_compile()
		for i in _riders.size():
			var s: Array = spots[i]
			_shifts[i] = _unfold(s[1][0], s[1][1], _time_at(s[2])) - s[0]
	_rebased = changes.size()
	if after_last == End.STOP and _loop_from < 0.0 and _duration > 0.0:
		# stop the channel at the program's ends, so REVERSE turns it back at once
		# instead of first unwinding the time it spent parked at the end
		for i in _riders.size():
			var start := offset + i * _spacing + _shifts[i]
			World.bound(channel, "%s#%d" % [get_path(), i], starts_on, -start, _duration - start)


## Copies of the platform for `platforms` > 1 (internal children: not saved, never counted as its platform).
func _sync_copies() -> void:
	var plat := platform()
	var want := [plat, platforms, ShapeSet.stamp(plat) if plat else [], plat.color if plat else Color()]
	if want == _copied and _riders.all(is_instance_valid):
		return
	_copied = want
	for r in _riders.slice(1):
		if is_instance_valid(r):
			r.free()
	_riders.clear()
	if plat:
		_riders.append(plat)
		for i in range(1, platforms):
			var c := MovingPlatform.new()
			c.name = "%s%d" % [plat.name, i + 1]
			c.color = plat.color
			c.surface = plat.surface
			c.transform = plat.transform
			for cs in plat.shapes():
				var dup: CollisionShape3D = cs.duplicate()
				dup.disabled = cs.disabled and not plat._warm.has(cs) # the copy runs its own warmup
				c.add_child(dup)
			add_child(c, true, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock
			_riders.append(c)
	_shifts.resize(_riders.size())
	_shifts.fill(0.0)
	_rebased = -1


func _draw_tracks() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(platform().color if platform() else Color.WHITE, 1.0).lightened(0.4)
	for t: PlatformTrackInstance in tracks():
		var path := t.path()
		if path == null or path.curve == null:
			continue
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for v in path.curve.get_baked_points(): # closed curves bake their closing segment too
			im.surface_add_vertex(v)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = m
		path.add_child(mi)
