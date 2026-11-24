## Renders shapes.glb unlit through box_projection.gdshaderinc from the camera of
## blender/box_projection.blend and diffs it against Blender's renders (blender/ref_*.png).
## Needs a window, since shaders don't compile headless:
##   godot --path . --resolution 960x540 -s res://demo/materials/box_projection/compare.gd
## Saves the Godot renders and diffs to user://box_projection/. Exit code = failed cases.
extends SceneTree

const DIR := "res://demo/materials/box_projection/"
## [name, texture, blend]: must match the cases in the Blender references.
const CASES := [["noise", "noise.png", 0.25], ["grid", "blender/grid.png", 0.0], ["grid_blend", "blender/grid.png", 0.6]]
## Pixels further than this apart (0-255, max over RGB) count as different.
const TOLERANCE := 12
## Fail when more of the image than this differs (silhouette aliasing differs a little).
const MAX_DIFFERENT := 0.01
const SHADER := """
shader_type spatial;
render_mode unshaded;
#include "res://demo/materials/box_projection/box_projection.gdshaderinc"
uniform sampler2D tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.5;
uniform float blend;
varying vec3 co;
varying vec3 n;
void vertex() { co = blender_axes(VERTEX) * scale; n = blender_axes(NORMAL); }
void fragment() { ALBEDO = box_projection(tex, co, n, blend).rgb; }
"""


func _initialize() -> void:
	run()


func run() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	var shapes: Node = load(DIR + "shapes.glb").instantiate()
	root.add_child(shapes)
	for m: MeshInstance3D in shapes.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat
	var cam := Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.5, 12), Vector3(0, 0.6, -0.5))
	RenderingServer.set_default_clear_color(Color.BLACK)
	root.use_debanding = false
	# Blender's GPU textures: 2x anisotropic, mipmaps averaged in linear space (see below).
	root.anisotropic_filtering_level = Viewport.ANISOTROPY_2X
	DirAccess.make_dir_recursive_absolute("user://box_projection")

	var failed := 0
	for c: Array in CASES:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + c[1]))
		# Linear before the mipmaps, as Blender does. Godot's own sRGB mipmaps make the grid's
		# thin white labels darker in the distance (14% of pixels off), the noise barely.
		img.convert(Image.FORMAT_RGBF)
		for y in img.get_height():
			for x in img.get_width():
				img.set_pixel(x, y, img.get_pixel(x, y).srgb_to_linear())
		img.generate_mipmaps()
		mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("blend", c[2])
		for i in 10:
			await process_frame
		var got := root.get_texture().get_image()
		got.convert(Image.FORMAT_RGB8)
		var ref := Image.load_from_file(ProjectSettings.globalize_path(DIR + "blender/ref_%s.png" % c[0]))
		ref.convert(Image.FORMAT_RGB8)
		if got.get_size() != ref.get_size():
			print("%s: window is %s, reference %s" % [c[0], got.get_size(), ref.get_size()])
			failed += 1
			continue
		var diff := Image.create(got.get_width(), got.get_height(), false, Image.FORMAT_RGB8)
		var different := 0
		var total := 0.0
		for y in got.get_height():
			for x in got.get_width():
				var a := got.get_pixel(x, y)
				var b := ref.get_pixel(x, y)
				var d := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0
				total += d
				if d > TOLERANCE:
					different += 1
				diff.set_pixel(x, y, Color.from_hsv(0.0, 0.0, minf(d / 32.0, 1.0)))
		var share := float(different) / (got.get_width() * got.get_height())
		var ok := share <= MAX_DIFFERENT
		failed += 0 if ok else 1
		print("%s: mean %.2f/255, %.3f%% of pixels off by more than %d  %s" % [
			c[0], total / (got.get_width() * got.get_height()), share * 100.0, TOLERANCE, "ok" if ok else "FAILED"])
		got.save_png("user://box_projection/godot_%s.png" % c[0])
		diff.save_png("user://box_projection/diff_%s.png" % c[0])
	print("renders in ", ProjectSettings.globalize_path("user://box_projection"))
	print("BOX PROJECTION: ", "OK" if failed == 0 else "%d FAILED" % failed)
	quit(failed)
