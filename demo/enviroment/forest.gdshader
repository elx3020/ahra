// Main material of the deep forest scene (enviroment_test.tscn): the procedural patterns of
// forest_pattern.gdshaderinc, evaluated per pixel.
// Opaque only: no discard or alpha, so Godot's shared vertex-only material draws these meshes in
// shadow maps and in a depth-only prepass.
// Diffuse is Lambert, like the Principled BSDF; specular 0.5 is its default IOR level.
shader_type spatial;
render_mode diffuse_lambert;

#include "res://demo/enviroment/forest_pattern.gdshaderinc"

varying vec3 v_obj;
varying vec3 v_nobj;

void vertex() {
	v_obj = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	v_nobj = vec3(NORMAL.x, -NORMAL.z, NORMAL.y);
}

void fragment() {
	vec3 albedo;
	vec3 world_normal;
	float scalar;
	forest_pattern(v_obj, v_nobj, albedo, world_normal, scalar);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	EMISSION = emission * emission_strength;
	if (pattern == 0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	}
}
