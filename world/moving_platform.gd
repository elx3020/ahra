@tool
class_name MovingPlatform
extends AnimatableBody3D
## Box platform that plays a program: its PlatformSequence children, in order. Each sequence
## moves it along a Path3D (its own, or the platform's parent Path3D), so a program can chain
## paths into a circuit. Draw paths with the editor's Path3D tools.
## Position is a pure function of time and its channel, never simulated step by step:
## it can't drift, it is already in the right place when an area loads, and platforms
## with the same timing stay in sync forever. For walls/ceilings make the box thin on that
## axis (or rotate it) and pair it with a GravityZone. A `surface` profile turns it into an
## ice / mud / wind... platform: an EnvZone wrapping the box rides along with it.

enum Repeat {
	NONE, ## play once and stay at the end (a REVERSE switch brings it back)
	REVERSE, ## then play the whole program backwards, then forwards again...
	RESTART, ## then start over (the program must end where it starts)
}

@export var size := Vector3(3, 0.5, 3):
	set(v):
		size = v
		_build()
@export var color := Color(0.55, 0.6, 0.75):
	set(v):
		color = v
		_build()
@export var surface: EnvProfile ## optional: environment applied while touching the platform
@export_group("Program")
@export var repeat := Repeat.REVERSE ## what happens after the last sequence
@export var offset := 0.0 ## seconds ahead on the timeline: spreads platforms sharing a path or channel
## Every sequence uses lap_wait / sequence_wait below, and wait switches can change them.
@export var shared_waits := false:
	set(v):
		shared_waits = v
		notify_property_list_changed()
		for s in get_children():
			s.notify_property_list_changed()
@export var lap_wait := 0.5 ## shared: pause before each lap
@export var sequence_wait := 0.5 ## shared: pause after each sequence
@export_group("Schedule")
@export var on_time := 3.0 ## with off_time > 0: moves on_time seconds...
@export var off_time := 0.0 ## ...then stops off_time seconds, repeating (0 = no schedule)
@export_group("Switches")
@export var channel: StringName ## PlatformSwitches on this channel control it (empty = world clock, no switches)
@export var starts_on := true ## moves on its own until a POWER switch stops it; off = waits for a switch
@export_group("Editor")
@export var preview := false ## animate in the editor to check timing and sync
@export var show_track := true ## draw the paths in game, so players can read where it goes

var _shape := BoxShape3D.new()
var _mesh := BoxMesh.new()
var _mat := StandardMaterial3D.new()
var _sequences: Array[PlatformSequence] = [] ## children with a usable path
var _plan: Array = [] ## compiled program, one entry per wait or lap: [seconds, sequence, from, to] (distances on its path)
var _duration := 0.0
var _rates := Vector3.ONE ## channel multipliers: speed, lap wait, sequence wait
var _shift := 0.0 ## program clock shift that keeps motion continuous across rate changes
var _rebased := -1 ## channel rate changes folded into _shift
var _cs: CollisionShape3D
var _warmup := 2 ## physics frames with collision off while the body travels from the scene origin to its place


func _ready() -> void:
	_cs = CollisionShape3D.new() # made here, not as a member default: a script reload would leak it
	_cs.shape = _shape
	# the body starts at the scene origin and its first placement is a physics move (Jolt
	# moves kinematic bodies): keep collision off for it, or it carries whatever stands there
	_cs.disabled = not Engine.is_editor_hint()
	add_child(_cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	_mesh.material = _mat
	_build()
	if surface:
		var z := EnvZone.new()
		z.profile = surface
		var box := BoxShape3D.new()
		box.size = size + Vector3.ONE * 0.6
		z.add_shape(box)
		z.color = Color(color, 0.12)
		add_child(z)
	_compile()
	if not Engine.is_editor_hint() and show_track:
		_draw_tracks()
	_follow()
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var before := _duration
		_compile() # pick up inspector edits
		if before != _duration:
			update_configuration_warnings()
	elif _warmup > 0:
		_warmup -= 1
		_cs.disabled = _warmup > 0
	_follow()


func _validate_property(p: Dictionary) -> void:
	if p.name in ["lap_wait", "sequence_wait"] and not shared_waits:
		p.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	_compile()
	var out := PackedStringArray()
	if _sequences.is_empty():
		out.append("Add PlatformSequence children, each with a Path3D (or put the platform under a Path3D).")
	for i in _sequences.size():
		var next := i + 1
		if next == _sequences.size():
			if repeat != Repeat.RESTART:
				break
			next = 0
		var gap := _at(i, _sequences[i].laps * _length(i)).distance_to(_at(next, 0.0))
		if gap > 0.05:
			out.append("%s starts %.2f m from where %s ends: the platform would jump." % [_sequences[next].name, gap, _sequences[i].name])
	return out


## Program seconds so far: channel drive (or world clock) + offset, through the schedule.
func motion_time() -> float:
	if Engine.is_editor_hint():
		return _schedule(offset + (Time.get_ticks_msec() * 0.001 if preview else 0.0))
	return _schedule((World.drive(channel, starts_on) if channel else World.time) + offset)


## Where the platform is after t program seconds.
func point_at(t: float) -> Vector3:
	var at := _locate(_fold(t + _shift)[2])
	var e: Array = _plan[int(at.x)]
	return _at(e[1], lerpf(e[2], e[3], at.y))


func _follow() -> void:
	if channel and not Engine.is_editor_hint():
		_rebase()
	if _duration > 0.0:
		global_position = point_at(motion_time())


func _path(q: PlatformSequence) -> Path3D:
	return q.path if q.path else get_parent() as Path3D


func _length(i: int) -> float:
	return _path(_sequences[i]).curve.get_baked_length()


## Point at distance s along sequence i's path: closed paths keep circling, open ones bounce.
func _at(i: int, s: float) -> Vector3:
	var path := _path(_sequences[i])
	var length := _length(i)
	return path.to_global(path.curve.sample_baked(fposmod(s, length) if path.curve.closed else pingpong(s, length)))


func _compile() -> void:
	_sequences.clear()
	_plan.clear()
	_duration = 0.0
	for q in get_children():
		if q is PlatformSequence and _path(q) and _path(q).curve and _path(q).curve.point_count > 1:
			_sequences.append(q)
	for i in _sequences.size():
		var q := _sequences[i]
		var length := _length(i)
		var lw := lap_wait * _rates.y if shared_waits else q.lap_wait
		var sw := sequence_wait * _rates.z if shared_waits else q.sequence_wait
		var travel := length / maxf(q.speed * _rates.x, 0.01)
		for j in q.laps:
			_plan.append([lw, i, j * length, j * length])
			_plan.append([travel, i, j * length, (j + 1) * length])
		_plan.append([sw, i, q.laps * length, q.laps * length])
	for e in _plan:
		_duration += e[0]


## Program time -> [period, playing backwards, seconds into the program].
func _fold(t: float) -> Array:
	var d := _duration
	if d <= 0.0:
		return [0.0, false, 0.0]
	match repeat:
		Repeat.NONE:
			return [0.0, false, clampf(t, 0.0, d)]
		Repeat.RESTART:
			var k := floorf(t / d)
			return [k, false, t - k * d]
	var k := floorf(t / (2.0 * d))
	var u := t - k * 2.0 * d
	return [k, u > d, 2.0 * d - u if u > d else u]


func _unfold(k: float, backwards: bool, x: float) -> float:
	match repeat:
		Repeat.NONE:
			return x
		Repeat.RESTART:
			return k * _duration + x
	return k * 2.0 * _duration + (2.0 * _duration - x if backwards else x)


## Seconds into the program -> (plan entry, fraction of it).
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


func _schedule(t: float) -> float:
	if off_time <= 0.0:
		return t
	var cycle := on_time + off_time
	return floorf(t / cycle) * on_time + minf(fposmod(t, cycle), on_time)


func _unschedule(t: float) -> float:
	if off_time <= 0.0:
		return t
	var k := floorf(t / on_time)
	return k * (on_time + off_time) + t - k * on_time


## Speed / wait switches change segment lengths: shift the program clock so the platform
## carries on from the same segment and fraction of it instead of jumping.
func _rebase() -> void:
	var changes := World.changes(channel)
	if changes.size() == _rebased:
		return
	_rates = Vector3.ONE
	_shift = 0.0
	_compile()
	for c: Array in changes:
		var t := _schedule(c[2 if starts_on else 1] + offset)
		var f := _fold(t + _shift)
		var at := _locate(f[2])
		_rates = Vector3(c[3], c[4], c[5])
		_compile()
		_shift = _unfold(f[0], f[1], _time_at(at)) - t
	_rebased = changes.size()
	if repeat == Repeat.NONE and _duration > 0.0:
		# stop the channel at this program's ends, so REVERSE turns it back at once
		# instead of first unwinding the time it spent parked at the end
		World.bound(channel, str(get_path()), starts_on, _unschedule(-_shift) - offset, _unschedule(_duration - _shift) - offset)


func _build() -> void:
	_shape.size = size
	_mesh.size = size
	_mat.albedo_color = color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED


func _draw_tracks() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, 1.0).lightened(0.4)
	var drawn := []
	for q in _sequences:
		var path := _path(q)
		if path in drawn:
			continue
		drawn.append(path)
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for v in path.curve.get_baked_points(): # closed curves bake their closing segment too
			im.surface_add_vertex(v)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = m
		mi.top_level = true # the track stays put while the platform moves
		add_child(mi)
		mi.global_transform = path.global_transform
