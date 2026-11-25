// Bakes demo/enviroment/forest_pattern.gdshaderinc into a mesh's UV2 layout. forest_baker.gd draws
// the mesh with this into a SubViewport the size of the texture: each triangle lands at its UV2
// position, and each texel gets the pattern at its point on the mesh. Two passes per mesh, which
// forest_dilate.gdshader merges into one texture (see forest_baked.gdshader for the layout).
// The viewport stores sRGB, so values are decoded from sRGB here and come out as written.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

#include "res://demo/enviroment/forest_pattern.gdshaderinc"

/// Off: Facets normal (world axes, 0..1 encoded), white for Bark. On: the colour value, grey.
uniform bool bake_scalar = false;

varying vec3 v_obj;
varying vec3 v_nobj;

void vertex() {
	v_obj = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	v_nobj = vec3(NORMAL.x, -NORMAL.z, NORMAL.y);
	POSITION = vec4(UV2 * 2.0 - 1.0, 0.5, 1.0);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 albedo;
	vec3 world_normal;
	float scalar;
	forest_pattern(v_obj, v_nobj, albedo, world_normal, scalar);
	vec3 value = bake_scalar ? vec3(scalar) : (pattern == 0 ? world_normal * 0.5 + 0.5 : vec3(1.0));
	ALBEDO = srgb_to_linear(value);
}
