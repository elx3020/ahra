// Two-tone noise mapped with box_projection.gdshaderinc, no UVs needed. Same setup as the
// box_noise material in blender/box_projection.blend:
// Texture Coordinate (Object) -> Mapping -> Image Texture (Box) -> Color Ramp -> Base Color.
shader_type spatial;

#include "res://demo/materials/box_projection/box_projection.gdshaderinc"

/// Any tileable texture. noise.png is baked from Blender's Noise Texture (blender/ folder).
uniform sampler2D noise : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
/// Blender's Mapping Scale: texture tiles per metre (0.5 = one tile every 2 m).
uniform float scale = 0.5;
/// Blender's Image Texture Blend: 0 = hard seams between the sides.
uniform float blend : hint_range(0.0, 1.0) = 0.25;
/// Colour where the noise is black (Color Ramp left stop).
uniform vec4 color_a : source_color = vec4(0.184, 0.231, 0.2, 1.0);
/// Colour where the noise is white (Color Ramp right stop).
uniform vec4 color_b : source_color = vec4(0.725, 0.682, 0.58, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

varying vec3 box_co;
varying vec3 box_n;

void vertex() {
	box_co = blender_axes(VERTEX) * scale;
	box_n = blender_axes(NORMAL);
}

void fragment() {
	ALBEDO = mix(color_a.rgb, color_b.rgb, box_projection(noise, box_co, box_n, blend).r);
	ROUGHNESS = roughness;
}
