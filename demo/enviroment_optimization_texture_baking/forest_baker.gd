extends Node
## Bakes the forest's procedural materials (demo/enviroment/forest.gdshader) into UV2 textures on
## the GPU when the area loads, then swaps in forest_baked.gdshader, which only reads them. Until
## the swap, a few frames in, the live materials draw the same pattern.
## Per mesh: two SubViewports draw the mesh unwrapped (forest_bake.gdshader: normal, then colour
## value), a third merges and dilates them (forest_dilate.gdshader) so chart borders don't filter
## in the empty background, and the image is read back into an ImageTexture with mipmaps.
## The meshes need UV2: this folder's forest.glb imports with Light Baking: Static Lightmaps.

const PATTERN_SHADER := preload("res://demo/enviroment/forest.gdshader")
const BAKE_SHADER := preload("forest_bake.gdshader")
const DILATE_SHADER := preload("forest_dilate.gdshader")
const BAKED_SHADER := preload("forest_baked.gdshader")

## Node whose MeshInstance3Ds get baked.
@export var forest: Node3D
## Baked texels per lightmap texel of the import (its lightmap_texel_size is 0.1 m, so 2 = 5 cm).
## The unwrap leaves one lightmap texel between UV2 charts: below 2 baked texels, dilation can fill
## a chart's edge from its neighbour and seams show.
@export_range(0.5, 8.0, 0.5) var texel_scale := 2.0
## How far, in texels, dilation fills around each UV2 chart.
@export_range(0, 32) var dilation := 8
## Meshes baked at once (three viewports each). More at once runs out of D3D12 sampler descriptors.
@export_range(1, 32) var batch_meshes := 8

var _skip: ShaderMaterial


func _ready() -> void:
	# Other surfaces of a baked mesh (glow on some rocks) collapse to a point: nothing drawn.
	_skip = ShaderMaterial.new()
	_skip.shader = Shader.new()
	_skip.shader.code = "shader_type spatial;\nrender_mode unshaded;\nvoid vertex() { POSITION = vec4(2.0, 2.0, 0.5, 1.0); }\n"
	bake()


func bake() -> void:
	if DisplayServer.get_name() == "headless":
		return  # nothing to read back from the dummy renderer; the live materials stay
	var start := Time.get_ticks_msec()
	var jobs: Array[Dictionary] = []
	for mi: MeshInstance3D in forest.find_children("*", "MeshInstance3D", true, false):
		var surfaces: Array[int] = []
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as ShaderMaterial
			if mat and mat.shader == PATTERN_SHADER:
				surfaces.append(s)
		if surfaces.is_empty():
			continue
		var hint: Vector2i = mi.mesh.lightmap_size_hint if mi.mesh is ArrayMesh else Vector2i.ZERO
		if hint == Vector2i.ZERO:
			push_warning("ForestBaker: %s has no UV2 layout, left live" % mi.name)
			continue
		var size := Vector2i((Vector2(hint) * texel_scale).ceil()).clampi(4, 8192)
		jobs.append({mi = mi, surfaces = surfaces, size = size})

	var total := 0
	for job in jobs:
		total += job.size.x * job.size.y
	for i in range(0, jobs.size(), batch_meshes):
		await _bake_batch(jobs.slice(i, i + batch_meshes))

	for job in jobs:
		var mi: MeshInstance3D = job.mi
		for s: int in job.surfaces:
			var baked := _copy_params(mi.get_active_material(s), BAKED_SHADER)
			baked.set_shader_parameter(&"baked", job.texture)
			mi.set_surface_override_material(s, baked)
	print("ForestBaker: %d meshes, %.1f M texels (%.0f MB with mipmaps) in %d ms" % [
			jobs.size(), total / 1e6, total * 4 * 4.0 / 3.0 / 1048576.0, Time.get_ticks_msec() - start])


func _bake_batch(batch: Array[Dictionary]) -> void:
	var viewports: Array[SubViewport] = []
	for job in batch:
		viewports.append(_bake_viewport(job))
	# One frame draws the bakes, the next has the dilation read them whatever order they drew in.
	for i in 2:
		await RenderingServer.frame_post_draw
	for i in batch.size():
		var img := viewports[i].get_texture().get_image()
		img.generate_mipmaps()
		batch[i].texture = ImageTexture.create_from_image(img)
		viewports[i].queue_free()


## The dilation viewport of one mesh, with its two bake viewports inside.
func _bake_viewport(job: Dictionary) -> SubViewport:
	var dilate := SubViewport.new()
	dilate.size = job.size
	dilate.disable_3d = true
	dilate.transparent_bg = true
	dilate.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = job.size
	var mat := ShaderMaterial.new()
	mat.shader = DILATE_SHADER
	rect.material = mat
	dilate.add_child(rect)
	var passes: Array[SubViewport] = [_bake_pass(job, false), _bake_pass(job, true)]
	for p in passes:
		dilate.add_child(p)
	add_child(dilate)
	mat.set_shader_parameter(&"colour_pass", passes[0].get_texture())
	mat.set_shader_parameter(&"scalar_pass", passes[1].get_texture())
	mat.set_shader_parameter(&"radius", dilation)
	return dilate


func _bake_pass(job: Dictionary, scalar: bool) -> SubViewport:
	var mi: MeshInstance3D = job.mi
	var vp := SubViewport.new()
	vp.size = job.size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.mesh_lod_threshold = 0.0  # the full mesh, never an LOD
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(Camera3D.new())  # the bake shader places the triangles; the camera only makes it draw
	var unwrapped := MeshInstance3D.new()
	unwrapped.mesh = mi.mesh
	unwrapped.extra_cull_margin = 16384.0
	unwrapped.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in mi.mesh.get_surface_count():
		var mat := _skip
		if s in job.surfaces:
			mat = _copy_params(mi.get_active_material(s), BAKE_SHADER)
			mat.set_shader_parameter(&"bake_scalar", scalar)
		unwrapped.set_surface_override_material(s, mat)
	vp.add_child(unwrapped)
	return vp


## A material with shader that takes over the live material's pattern settings.
func _copy_params(live: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for u in PATTERN_SHADER.get_shader_uniform_list():
		mat.set_shader_parameter(u.name, live.get_shader_parameter(u.name))
	return mat
