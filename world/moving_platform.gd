@tool
class_name MovingPlatform
extends AnimatableBody3D
## Box platform that rides its parent Path3D (draw the route with the editor's Path3D tools;
## move the Path3D to move both). Several platforms can share one path.
## Position is a pure function of World.time and its activation, never simulated step by
## step: it can't drift, it is already in the right place when an area loads, and platforms
## with the same timing stay in sync forever. For walls/ceilings make the box thin on that
## axis (or rotate it) and pair it with a GravityZone. A `surface` profile turns it into an
## ice / mud / wind... platform: an EnvZone wrapping the box rides along with it.

enum Motion { PING_PONG, LOOP } ## LOOP: close the curve (Curve3D.closed) or it jumps back to the start
enum Activation { ALWAYS, TIMED, SWITCH }

@export var size := Vector3(3, 0.5, 3):
	set(v):
		size = v
		_build()
@export var color := Color(0.55, 0.6, 0.75):
	set(v):
		color = v
		_build()
@export var surface: EnvProfile ## optional: environment applied while touching the platform
@export_group("Motion")
@export var speed := 2.0 ## m/s along the path
@export var motion := Motion.PING_PONG
@export var wait := 0.5 ## seconds stopped at each end (ping-pong) / at the start of each lap (loop)
@export var offset := 0.0 ## seconds ahead on the timeline: spreads platforms that share a path
@export_group("Activation")
@export var activation := Activation.ALWAYS
@export var on_time := 3.0 ## TIMED: moves for on_time...
@export var off_time := 2.0 ## ...then stops for off_time, repeating
@export var channel: StringName ## SWITCH: moves while PlatformSwitches on this channel have it on
@export_group("Editor")
@export var preview := false ## animate in the editor (as ALWAYS) to check timing and sync
@export var show_track := true ## draw the path in game, so players can read where it goes

var _shape := BoxShape3D.new()
var _mesh := BoxMesh.new()
var _mat := StandardMaterial3D.new()


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


## Seconds of motion so far = where the platform is on its path.
func motion_time() -> float:
	if Engine.is_editor_hint():
		return offset + (Time.get_ticks_msec() * 0.001 if preview else 0.0)
	var t := World.time + offset
	match activation:
		Activation.TIMED:
			var cycle := on_time + off_time
			return floorf(t / cycle) * on_time + minf(fposmod(t, cycle), on_time)
		Activation.SWITCH:
			return World.active_time(channel) + offset
	return t


## Distance along the path after t seconds of motion.
func distance(t: float) -> float:
	var length := _curve().get_baked_length()
	var travel := length / maxf(speed, 0.01)
	var leg := travel + wait
	if motion == Motion.LOOP:
		return clampf(fposmod(t, leg) - wait, 0.0, travel) * speed
	var u := fposmod(t, 2.0 * leg)
	var d := clampf(fposmod(u, leg) - wait, 0.0, travel) * speed
	return d if u < leg else length - d


func _curve() -> Curve3D:
	var path := get_parent() as Path3D
	return path.curve if path else null


func _follow() -> void:
	var c := _curve()
	if c and c.point_count > 1:
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
