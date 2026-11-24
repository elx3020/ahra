@tool
class_name ToonOutline
extends MeshInstance3D
## Full-screen toon outline (toon_outline.gdshader). Instance toon_outline.tscn anywhere in a
## scene: it draws over everything the camera sees, in the game and in the editor viewport.
## Each frame it hands the shader the direction towards the sun, so lines thin out on lit faces.

## Light the lines react to. Empty = the first visible DirectionalLight3D in the scene.
@export var sun: DirectionalLight3D

var _found: DirectionalLight3D


func _process(_delta: float) -> void:
	var mat := material_override as ShaderMaterial
	var light := _light()
	if mat and light:
		mat.set_shader_parameter(&"light_direction", light.global_basis.z)


func _light() -> DirectionalLight3D:
	if sun:
		return sun
	if is_instance_valid(_found) and _found.is_visible_in_tree():
		return _found
	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root == null:
		return null
	_found = null
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light.is_visible_in_tree():
			_found = light
			break
	return _found
