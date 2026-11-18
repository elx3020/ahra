@tool
class_name MovingPlatform
extends AnimatableBody3D
## Box platform that rides its parent Path3D (draw the route with the editor's Path3D tools;
## move the Path3D to move both). Several platforms can share one path.
## Position is a pure function of time and its channel, never simulated step by step:
## it can't drift, it is already in the right place when an area loads, and platforms
## with the same timing stay in sync forever. For walls/ceilings make the box thin on that
## axis (or rotate it) and pair it with a GravityZone. A `surface` profile turns it into an
## ice / mud / wind... platform: an EnvZone wrapping the box rides along with it.
##
## Program, repeating: `laps` passes forward -> wait -> `laps_back` passes back -> cooldown.
## A pass is the path's length: closed curves keep circling, open ones bounce at the ends.
##   ping-pong / elevator: 1, 1   endless loop (closed curve): 1, 0   3 laps out and back: 3, 3

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
@export var speed := 2.0 ## m/s along the path
@export var laps := 1 ## passes forward before turning
@export var laps_back := 1 ## passes back after turning (0 = never turns)
@export var wait := 0.5 ## pause when turning
@export var cooldown := 0.5 ## pause after the passes back, before repeating
@export var offset := 0.0 ## seconds ahead on the timeline: spreads platforms sharing a path or channel
@export_group("Schedule")
@export var on_time := 3.0 ## with off_time > 0: moves on_time seconds...
@export var off_time := 0.0 ## ...then stops off_time seconds, repeating (0 = no schedule)
@export_group("Switches")
@export var channel: StringName ## PlatformSwitches on this channel control it (empty = world clock, no switches)
@export var starts_on := true ## moves on its own until a POWER switch stops it; off = waits for a switch
@export_group("Editor")
@export var preview := false ## animate in the editor to check timing and sync
@export var show_track := true ## draw the path in game, so players can read where it goes

var _shape := BoxShape3D.new()
var _mesh := BoxMesh.new()
var _mat := StandardMaterial3D.new()
var _rates := Vector2.ONE ## channel speed / cooldown multipliers
var _shift := 0.0 ## program clock shift that keeps motion continuous across rate changes
var _rebased := 0 ## channel rate changes folded into _shift


func _ready() -> void:
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	_mesh.material = _mat
	_build()
	if surface:
		var z := EnvZone.new()
		z.profile = surface
		z.size = size + Vector3.ONE * 0.6
		z.color = Color(color, 0.12)
		add_child(z)
	if show_track and not Engine.is_editor_hint():
		_draw_track()
	_follow()
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	_follow()


func _get_configuration_warnings() -> PackedStringArray:
	if not get_parent() is Path3D:
		return ["Put the platform under a Path3D: it follows the parent's curve."]
	return []


## Program seconds so far: channel drive (or world clock) + offset, through the schedule.
func motion_time() -> float:
	if Engine.is_editor_hint():
		return _schedule(offset + (Time.get_ticks_msec() * 0.001 if preview else 0.0))
	return _schedule((World.drive(channel, starts_on) if channel else World.time) + offset)


## Where on the path (0..length) the platform is after t program seconds.
func distance(t: float) -> float:
	var length := _curve().get_baked_length()
	var s := _travel(t + _shift)
	return fposmod(s, length) if _curve().closed else pingpong(s, length)


func _schedule(t: float) -> float:
	if off_time <= 0.0:
		return t
	var cycle := on_time + off_time
	return floorf(t / cycle) * on_time + minf(fposmod(t, cycle), on_time)


## Leg durations: forward, wait, back, cooldown.
func _legs() -> Array[float]:
	var lap := _curve().get_baked_length() / maxf(speed * _rates.x, 0.01)
	return [laps * lap, wait, laps_back * lap, cooldown * _rates.y]


## Program time t -> (cycle, leg, fraction of that leg).
func _locate(t: float, legs: Array[float]) -> Vector3:
	var cycle: float = legs[0] + legs[1] + legs[2] + legs[3]
	if cycle <= 0.0:
		return Vector3.ZERO
	var k := floorf(t / cycle)
	var u := t - k * cycle
	for i in 3:
		if u < legs[i]:
			return Vector3(k, i, u / legs[i])
		u -= legs[i]
	return Vector3(k, 3, u / legs[3] if legs[3] > 0.0 else 0.0)


## Signed distance travelled (before folding onto the path).
func _travel(t: float) -> float:
	var at := _locate(t, _legs())
	var length := _curve().get_baked_length()
	var s := at.x * (laps - laps_back) * length
	match int(at.y):
		0: return s + at.z * laps * length
		1: return s + laps * length
		2: return s + (laps - at.z * laps_back) * length
	return s + (laps - laps_back) * length


## Speed / cooldown switches change leg lengths: shift the program clock so the platform
## carries on from the same cycle, leg and fraction of that leg instead of jumping.
func _rebase() -> void:
	var changes := World.changes(channel)
	if changes.size() == _rebased:
		return
	_rates = Vector2.ONE
	_shift = 0.0
	for c: Array in changes:
		var t := _schedule(c[2 if starts_on else 1] + offset)
		var at := _locate(t + _shift, _legs())
		_rates = Vector2(c[3], c[4])
		var legs := _legs()
		var cycle: float = legs[0] + legs[1] + legs[2] + legs[3]
		var into := 0.0
		for i in int(at.y):
			into += legs[i]
		_shift = at.x * cycle + into + at.z * legs[int(at.y)] - t
	_rebased = changes.size()


func _curve() -> Curve3D:
	var path := get_parent() as Path3D
	return path.curve if path else null


func _follow() -> void:
	var c := _curve()
	if c and c.point_count > 1:
		if channel and not Engine.is_editor_hint():
			_rebase()
		position = c.sample_baked(distance(motion_time()))


func _build() -> void:
	_shape.size = size
	_mesh.size = size
	_mat.albedo_color = color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED


func _draw_track() -> void:
	var c := _curve()
	if c == null or c.point_count < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for v in c.get_baked_points(): # closed curves bake their closing segment too
		im.surface_add_vertex(v)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, 1.0).lightened(0.4)
	mi.material_override = m
	mi.top_level = true # the track stays put while the platform moves
	add_child(mi)
	mi.global_transform = get_parent().global_transform
