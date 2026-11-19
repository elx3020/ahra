@tool
class_name PlatformTrackInstance
extends PlatformProgram
## A track: the Path3D child a platform follows and the sequences that move it along it, played
## one after another (see PlatformSequence). Its MovingPlatform child rides it; it can be always
## on or switched on (channel / starts_on). Inside a circuit (a PlatformTrackGroup with
## `circuit` on) the group's platform rides every track in turn: the track has no platform and
## the timing settings are the group's.
## The Platform Tools' New Track builds one; edit the path with Godot's Path3D tools.
## Editor: a ghost of the platform marks the end of the path. Inside a group it follows the
## group's show_paths / show_destination settings.

@export var sequences: Array[PlatformSequence] = []

var _ghost_mat := StandardMaterial3D.new()
var _ghost: Node3D ## internal child: the platform's shapes at the end of the path
var _ghost_look := [] ## what the ghost was built for: platform shapes, shown
var _warned := PackedStringArray()


func _ready() -> void:
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.22)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		notify_property_list_changed() # in or out of a circuit: the timing settings show or hide


func plays() -> bool:
	return circuit() == null


func tracks() -> Array:
	return [self]


## The circuit this track is part of (null: it runs its own platform).
func circuit() -> PlatformTrackGroup:
	var g := get_parent() as PlatformTrackGroup
	return g if g and g.circuit else null


## What runs this track: itself, or its circuit.
func program() -> PlatformProgram:
	return circuit() if circuit() else self


## Its platform, or its circuit's.
func platform() -> MovingPlatform:
	return circuit().platform() if circuit() else super()


func path() -> Path3D:
	for c in get_children():
		if c is Path3D:
			return c
	return null


## World position of anchor 0 / of the anchor the path ends on (a closed path ends where it starts).
func first_point() -> Vector3:
	var line := path()
	return line.to_global(line.curve.get_point_position(0))


func last_point() -> Vector3:
	var line := path()
	return line.to_global(line.curve.get_point_position(0 if line.curve.closed else line.curve.point_count - 1))


## Each sequence starts where the previous one left the platform.
func chain_sequences() -> void:
	var prev: PlatformSequence = null
	for q in sequences:
		if q == null:
			continue
		if prev and q.start_anchor != prev.finish_anchor():
			q.start_anchor = prev.finish_anchor()
		if q.locked != (prev != null):
			q.locked = prev != null
			q.notify_property_list_changed()
		prev = q


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var group := get_parent() as PlatformTrackGroup
	var line := path()
	if group and line and line.visible != group.show_paths:
		line.visible = group.show_paths
	if not plays():
		chain_sequences() # the circuit compiles them, but keep the inspector in step anyway
	_place_ghost(platform(), line, group.show_destination if group else true)
	var w := _get_configuration_warnings()
	if w != _warned:
		_warned = w
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var lines := get_children().filter(func(c: Node) -> bool: return c is Path3D)
	if lines.size() != 1:
		out.append("Needs exactly one Path3D child (has %d)." % lines.size())
	var plats := get_children().filter(func(c: Node) -> bool: return c is MovingPlatform).size()
	if circuit() and plats > 0:
		out.append("In a circuit the group's platform rides every track: this one needs none.")
	elif not circuit() and plats != 1:
		out.append("Needs exactly one MovingPlatform child (has %d)." % plats)
	var line := path()
	if line == null or line.curve == null or line.curve.point_count < 2:
		out.append("The path needs at least 2 anchors.")
		return out
	if sequences.is_empty():
		out.append("Add a sequence: it moves the platform between two anchors of the path.")
	var n := line.curve.point_count
	for i in sequences.size():
		var q := sequences[i]
		if q == null:
			out.append("Sequence %d is empty: pick New PlatformSequence." % i)
		elif q.start_anchor >= n or q.end_anchor >= n or q.start_anchor < 0 or q.end_anchor < 0:
			out.append("Sequence %d: anchors go from 0 to %d." % [i, n - 1])
		elif q.start_anchor == q.end_anchor and not line.curve.closed:
			out.append("Sequence %d: start and end anchor are the same (only a closed path allows that: a full lap)." % i)
		elif q.trips == 0 and i < sequences.size() - 1:
			out.append("Sequence %d repeats forever: the ones after it never play." % i)
	var c := circuit()
	if c and not sequences.is_empty() and not sequences.has(null):
		var end := 0 if line.curve.closed else n - 1
		if sequences[0].start_anchor != 0:
			out.append("In a circuit the first sequence starts on anchor 0, where the previous track ends.")
		var tracks: Array = c.tracks()
		var next: Variant = tracks[tracks.find(self) + 1] if tracks.find(self) < tracks.size() - 1 else null
		if next and (sequences[-1].trips == 0 or sequences[-1].finish_anchor() != end):
			out.append("In a circuit the last sequence must leave the platform on anchor %d, where the next track starts." % end)
		if next and next.path() and next.path().curve and next.path().curve.point_count > 0 and last_point().distance_to(next.first_point()) > 0.05:
			out.append("The path ends %.2f m from where %s starts: the platform would jump (Reconnect joins them)." % [last_point().distance_to(next.first_point()), next.name])
	return out


func _place_ghost(plat: MovingPlatform, line: Path3D, shown: bool) -> void:
	var look := [ShapeSet.stamp(plat) if plat else [], shown and line != null]
	if look != _ghost_look:
		_ghost_look = look
		if _ghost:
			_ghost.free()
			_ghost = null
		if look[1] and plat:
			_ghost = Node3D.new()
			_ghost.top_level = true
			for cs in plat.shapes():
				var mi := MeshInstance3D.new()
				mi.mesh = ShapeSet.solid_mesh(cs.shape)
				mi.material_override = _ghost_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.transform = cs.transform
				_ghost.add_child(mi)
			add_child(_ghost, false, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock
	if _ghost and line.curve and line.curve.point_count > 0:
		_ghost.global_transform = Transform3D(plat.global_basis, last_point())
