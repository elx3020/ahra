// Ink outline for toon_rock.gdshader: an inverted hull drawn as the material's next pass.
// The mesh is bent like the main pass, grown by outline_width and drawn back faces only.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

#include "res://shaders/toon_rock.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.08, 1.0);
/// Outline thickness in metres.
uniform float outline_width : hint_range(0.0, 0.2) = 0.03;
/// 1 = grow away from the mesh origin (no gaps on hard-edged meshes; the origin must be
/// inside the rock), 0 = grow along the normals (even width, but gaps at hard edges).
uniform float outline_radial : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	vec3 scale = rock_scale(MODEL_MATRIX);
	vec3 seed = rock_seed_offset(NODE_POSITION_WORLD);
	VERTEX = rock_deform(VERTEX, scale, seed);
	vec3 radial = length(VERTEX) > 0.0001 ? normalize(VERTEX) : NORMAL;
	vec3 dir = normalize(mix(NORMAL, radial, outline_radial));
	VERTEX += dir * outline_width / scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
