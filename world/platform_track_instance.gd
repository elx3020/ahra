@tool
class_name PlatformTrackInstance
extends Node3D
## One moving-platform track: Path3D children and one MovingPlatform child that rides them,
## with exactly one PlatformSequence per path (several paths = multipath, one platform).
## The Platform Tools' New Track button builds one; edit its path with Godot's Path3D tools.
## Editor: a ghost of the platform marks the end of each path. Inside a PlatformTrackGroup it
## follows the group's preview / show_paths / show_destination settings.

var _ghost_mat := StandardMaterial3D.new()
var _ghosts: Array[Node3D] = [] ## internal children, one per path
var _ghost_look := [] ## what the ghosts were built for: platform shapes, path count, shown
var _layout := [] ## paths / platform / sequence targets the warnings were computed for


func _ready() -> void:
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.22)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var group := get_parent() as PlatformTrackGroup
	var plat := platform()
	var tracks := paths()
	if group:
		for t in tracks:
			if t.visible != group.show_paths:
				t.visible = group.show_paths
		if plat and plat.preview != group.preview:
			plat.preview = group.preview
	_place_ghosts(plat, tracks, group.show_destination if group else true)
	var layout := [tracks, plat, _targets(plat)]
	if layout != _layout:
		_layout = layout
		update_configuration_warnings()


## The MovingPlatform child (null if missing).
func platform() -> MovingPlatform:
	for c in get_children():
		if c is MovingPlatform:
			return c
	return null


func paths() -> Array[Path3D]:
	var out: Array[Path3D] = []
	for c in get_children():
		if c is Path3D:
			out.append(c)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var plats := get_children().filter(func(c: Node) -> bool: return c is MovingPlatform)
	if plats.size() != 1:
		out.append("Needs exactly one MovingPlatform child, which rides every path (has %d)." % plats.size())
	var tracks := paths()
	if tracks.is_empty():
		out.append("Needs a Path3D child.")
	var targets := _targets(platform())
	for t in tracks:
		if targets.count(t) != 1:
			out.append("%s needs exactly one PlatformSequence on the platform (has %d)." % [t.name, targets.count(t)])
	return out


## The path of each of the platform's sequences.
func _targets(plat: MovingPlatform) -> Array:
	var out := []
	if plat:
		for q in plat.get_children():
			if q is PlatformSequence:
				out.append(q.path)
	return out


func _place_ghosts(plat: MovingPlatform, tracks: Array[Path3D], shown: bool) -> void:
	var look := [ShapeSet.stamp(plat) if plat else [], tracks.size(), shown]
	if look != _ghost_look:
		_ghost_look = look
		for g in _ghosts:
			g.free()
		_ghosts.clear()
		if shown and plat:
			for t in tracks:
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
		var curve := tracks[i].curve
		if curve and curve.point_count > 0:
			var end := 0 if curve.closed else curve.point_count - 1 # a lap of a loop ends where it starts
			_ghosts[i].global_transform = Transform3D(plat.global_basis, tracks[i].to_global(curve.get_point_position(end)))
