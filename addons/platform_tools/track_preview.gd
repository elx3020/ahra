@tool
extends Node3D
## The track builder's 3D preview, shown while placing anchors: a cursor marker where the next
## anchor goes (its colour tells a snap onto a ShapeReference from a free point), markers on the
## anchors placed so far, and the path that finishing would build, as a tube.
## Its look comes from editor settings under platform_tools/preview/ (toolbar: Preview Settings),
## which also hold the anchors' grid snap (grid_snap, grid_step).

const PREFIX := "platform_tools/preview/"
## [name, label, default, hint, hint string]
const SETTINGS := [
	["path_color", "Path", Color(1, 1, 1, 0.85), PROPERTY_HINT_NONE, ""],
	["next_color", "Next segment", Color(1, 1, 1, 0.4), PROPERTY_HINT_NONE, ""],
	["anchor_color", "Anchors", Color(0.85, 0.9, 1, 0.95), PROPERTY_HINT_NONE, ""],
	["cursor_color", "Cursor (free)", Color(1, 0.85, 0.2, 0.95), PROPERTY_HINT_NONE, ""],
	["snap_color", "Cursor (on a shape)", Color(0.3, 1, 0.4, 0.95), PROPERTY_HINT_NONE, ""],
	["close_color", "Cursor (closes the loop)", Color(0.35, 0.75, 1, 0.95), PROPERTY_HINT_NONE, ""],
	["opacity", "Opacity", 1.0, PROPERTY_HINT_RANGE, "0,1,0.05"],
	["marker_size", "Marker size", 0.35, PROPERTY_HINT_RANGE, "0.05,3,0.05"],
	["path_width", "Path width", 0.08, PROPERTY_HINT_RANGE, "0.01,1,0.01"],
	["marker_shape", "Marker shape", 0, PROPERTY_HINT_ENUM, "Sphere,Cube,Diamond"],
	["on_top", "Draw on top", true, PROPERTY_HINT_NONE, ""],
	["grid_snap", "Snap anchors to grid", false, PROPERTY_HINT_NONE, ""],
	["grid_step", "Grid step (m)", 1.0, PROPERTY_HINT_RANGE, "0.05,10,0.05"],
]


## Adds the settings (with their defaults) to the editor settings, once per editor session.
static func register() -> void:
	var es := EditorInterface.get_editor_settings()
	for s: Array in SETTINGS:
		var key: String = PREFIX + s[0]
		if not es.has_setting(key):
			es.set_setting(key, s[2])
		es.set_initial_value(key, s[2], false)
		es.add_property_info({name = key, type = typeof(s[2]), hint = s[3], hint_string = s[4]})


static func value(setting: String) -> Variant:
	return EditorInterface.get_editor_settings().get_setting(PREFIX + setting)


static func set_value(setting: String, v: Variant) -> void:
	EditorInterface.get_editor_settings().set_setting(PREFIX + setting, v)


## Redraws for these anchors and cursor ({position, snapped, closes}, or {} when off the viewport).
func show_track(anchors: PackedVector3Array, cursor: Dictionary) -> void:
	for c in get_children():
		c.free()
	var pts := Array(anchors)
	if not cursor.is_empty():
		pts.append(cursor.position)
	for i in range(1, pts.size()):
		var next := i == pts.size() - 1 and not cursor.is_empty()
		_segment(pts[i - 1], pts[i], value("next_color" if next else "path_color"))
	var size: float = value("marker_size")
	for p in anchors:
		_marker(p, size, value("anchor_color"))
	if not cursor.is_empty():
		var look := "close_color" if cursor.get("closes", false) else "snap_color" if cursor.snapped else "cursor_color"
		_marker(cursor.position, size * 1.4, value(look))


func _marker(at: Vector3, size: float, color: Color) -> void:
	if value("marker_shape") == 1:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * size
		_add(box, Transform3D(Basis.IDENTITY, at), color)
		return
	var ball := SphereMesh.new()
	ball.radius = size * 0.5
	ball.height = size
	if value("marker_shape") == 2: # a diamond: a sphere with 4 sides and 1 ring
		ball.radial_segments = 4
		ball.rings = 1
	_add(ball, Transform3D(Basis.IDENTITY, at), color)


func _segment(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var tube := CylinderMesh.new()
	tube.top_radius = value("path_width") * 0.5
	tube.bottom_radius = tube.top_radius
	tube.height = 1.0
	tube.radial_segments = 8
	tube.rings = 0
	var turn := Basis(Quaternion(Vector3.UP, (b - a) / length)) # the tube's axis along a -> b
	_add(tube, Transform3D(turn * Basis.from_scale(Vector3(1, length, 1)), (a + b) * 0.5), color)


func _add(mesh: Mesh, at: Transform3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = value("on_top")
	mat.albedo_color = Color(color, color.a * value("opacity"))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = at
	add_child(mi)
