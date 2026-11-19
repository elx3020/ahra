@tool
class_name PlatformTrackInstance
extends PlatformProgram
## A track: its Path3D children (one, or several: multipath) and the sequences that move a
## platform along them, played one after another (see PlatformSequence). Each sequence runs on
## one of the paths; a sequence on another path than the previous one starts at that path's
## anchor where the platform was left (a junction), so paths can branch off and come back.
## Its MovingPlatform child rides it; it can be always on or switched on (channel / starts_on).
## Inside a circuit (a PlatformTrackGroup with `circuit` on) the group's platform rides every
## track in turn: the track has no platform and the timing settings are the group's.
## The Platform Tools' New Track builds one and Add Path adds paths; edit them with Godot's
## Path3D tools. Editor: a ghost of the platform marks the end of each path. Inside a group it
## follows the group's show_paths / show_destination settings.

const JOIN := 0.05 ## metres: a junction farther apart than this makes the platform jump

@export var sequences: Array[PlatformSequence] = []

var _ghost_mat := StandardMaterial3D.new()
var _ghosts: Array[Node3D] = [] ## internal children: the platform's shapes at the end of each path
var _ghost_look := [] ## what the ghosts were built for: platform shapes, paths, shown
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


## Its Path3D children, in order (a sequence's `path` indexes this).
func paths() -> Array[Path3D]:
	var out: Array[Path3D] = []
	for c in get_children():
		if c is Path3D:
			out.append(c)
	return out


## The first path (null if none).
func path() -> Path3D:
	var all := paths()
	return all[0] if not all.is_empty() else null


## The path sequence q runs on (null if its index or curve is unusable).
func path_of(q: PlatformSequence) -> Path3D:
	var all := paths()
	if q == null or q.path < 0 or q.path >= all.size() or all[q.path].curve == null or all[q.path].curve.point_count < 2:
		return null
	return all[q.path]


## [path, anchor] where the program picks the platform up / leaves it (a forever sequence: its
## end anchor). Circuits join one track's exit to the next one's entry.
func entry() -> Array:
	for q in sequences:
		if path_of(q):
			return [path_of(q), q.start_anchor]
	return [path(), 0]


func exit() -> Array:
	for i in range(sequences.size() - 1, -1, -1):
		var q := sequences[i]
		if path_of(q):
			return [path_of(q), q.end_anchor if q.trips == 0 else q.finish_anchor()]
	var line := path()
	return [line, 0 if line == null or line.curve.closed else line.curve.point_count - 1]


func first_point() -> Vector3:
	return _point(entry())


func last_point() -> Vector3:
	return _point(exit())


## World position of [path, anchor].
func _point(at: Array) -> Vector3:
	var line: Path3D = at[0]
	return line.to_global(line.curve.get_point_position(clampi(at[1], 0, line.curve.point_count - 1)))


## Each sequence starts where the previous one left the platform: the same anchor on the same
## path, or the nearest anchor of its own path (the junction). Also fills the path dropdowns.
func chain_sequences() -> void:
	var names := ",".join(paths().map(func(p: Path3D) -> String: return String(p.name)))
	var prev: PlatformSequence = null
	for q in sequences:
		if q == null:
			continue
		var start := -1
		if prev and path_of(prev) and path_of(q):
			start = prev.finish_anchor() if q.path == prev.path else _nearest_anchor(path_of(q), _point([path_of(prev), prev.finish_anchor()]))
		if start >= 0 and q.start_anchor != start:
			q.start_anchor = start
		if q.locked != (prev != null) or q.path_names != names:
			q.locked = prev != null
			q.path_names = names
			q.notify_property_list_changed()
		prev = q


func _nearest_anchor(line: Path3D, global: Vector3) -> int:
	var best := 0
	for i in line.curve.point_count:
		if line.to_global(line.curve.get_point_position(i)).distance_to(global) < line.to_global(line.curve.get_point_position(best)).distance_to(global):
			best = i
	return best


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var group := get_parent() as PlatformTrackGroup
	if group:
		for line in paths():
			if line.visible != group.show_paths:
				line.visible = group.show_paths
	if not plays():
		chain_sequences() # the circuit compiles them, but keep the inspector in step anyway
	_place_ghosts(platform(), group.show_destination if group else true)
	var w := _get_configuration_warnings()
	if w != _warned:
		_warned = w
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var lines := paths()
	if lines.is_empty():
		out.append("Needs a Path3D child.")
	var plats := get_children().filter(func(c: Node) -> bool: return c is MovingPlatform).size()
	if circuit() and plats > 0:
		out.append("In a circuit the group's platform rides every track: this one needs none.")
	elif not circuit() and plats != 1:
		out.append("Needs exactly one MovingPlatform child (has %d)." % plats)
	for line in lines:
		if line.curve == null or line.curve.point_count < 2:
			out.append("%s needs at least 2 anchors." % line.name)
	if sequences.is_empty():
		out.append("Add a sequence: it moves the platform between two anchors of a path.")
	for i in sequences.size():
		var q := sequences[i]
		var line := path_of(q)
		if q == null:
			out.append("Sequence %d is empty: pick New PlatformSequence." % i)
		elif line == null:
			out.append("Sequence %d: no usable path %d (the track has %d)." % [i, q.path, lines.size()])
		elif q.start_anchor >= line.curve.point_count or q.end_anchor >= line.curve.point_count or q.start_anchor < 0 or q.end_anchor < 0:
			out.append("Sequence %d: %s's anchors go from 0 to %d." % [i, line.name, line.curve.point_count - 1])
		elif q.start_anchor == q.end_anchor and not line.curve.closed:
			out.append("Sequence %d: start and end anchor are the same (only a closed path allows that: a full lap)." % i)
		elif q.trips == 0 and i < sequences.size() - 1:
			out.append("Sequence %d repeats forever: the ones after it never play." % i)
		elif q.trips == 0 and q.end_signal != &"":
			out.append("Sequence %d repeats forever: it never ends, so its end signal never fires." % i)
		elif i > 0 and path_of(sequences[i - 1]) and sequences[i - 1].path != q.path:
			var gap := _point([path_of(sequences[i - 1]), sequences[i - 1].finish_anchor()]).distance_to(_point([line, q.start_anchor]))
			if gap > JOIN:
				out.append("Sequence %d starts %.2f m from where sequence %d leaves the platform: give %s an anchor there." % [i, gap, i - 1, line.name])
	var c := circuit()
	if c and not sequences.is_empty() and not sequences.has(null) and path():
		var tracks: Array = c.tracks()
		var next: Variant = tracks[tracks.find(self) + 1] if tracks.find(self) < tracks.size() - 1 else null
		if next and sequences.any(func(q: PlatformSequence) -> bool: return q.trips == 0):
			out.append("In a circuit a sequence repeating forever stops the platform from reaching %s." % next.name)
		if next and next.path() and next.path().curve and next.path().curve.point_count > 0 and last_point().distance_to(next.first_point()) > JOIN:
			out.append("It leaves the platform %.2f m from where %s picks it up: it would jump (Reconnect joins them)." % [last_point().distance_to(next.first_point()), next.name])
	return out


func _place_ghosts(plat: MovingPlatform, shown: bool) -> void:
	var lines := paths().filter(func(p: Path3D) -> bool: return p.curve != null and p.curve.point_count > 0)
	var look := [ShapeSet.stamp(plat) if plat else [], lines, shown]
	if look != _ghost_look:
		_ghost_look = look
		for g in _ghosts:
			g.free()
		_ghosts.clear()
		if shown and plat:
			for line in lines:
				var ghost := Node3D.new()
				ghost.top_level = true
				for cs in plat.shapes():
					var mi := MeshInstance3D.new()
					mi.mesh = ShapeSet.solid_mesh(cs.shape)
					mi.material_override = _ghost_mat
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.transform = cs.transform
					ghost.add_child(mi)
				add_child(ghost, false, Node.INTERNAL_MODE_BACK) # not saved, not in the scene tree dock
				_ghosts.append(ghost)
	for i in _ghosts.size():
		var line: Path3D = lines[i]
		_ghosts[i].global_transform = Transform3D(plat.global_basis, _point([line, 0 if line.curve.closed else line.curve.point_count - 1]))
