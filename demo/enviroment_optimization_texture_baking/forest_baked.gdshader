// The forest's procedural materials (demo/enviroment/forest.gdshader) baked into a UV2 texture by
// forest_baker.gd: the same look for one texture read instead of the noise and Voronoi, in the
// depth prepass (which writes the normal for VoxelGI and the outline) and the opaque pass.
// Only the pattern is baked: colours, shade_power (Bark), roughness and emission stay live.
// Opaque only, like forest.gdshader.
shader_type spatial;
render_mode diffuse_lambert;

#include "res://demo/enviroment/forest_pattern.gdshaderinc"

/// RGB: Facets normal in world axes, 0..1 encoded. A: Facets 1 where side_color, Bark the cell shade.
uniform sampler2D baked : filter_linear_mipmap_anisotropic, repeat_disable;

void fragment() {
	vec4 t = texture(baked, UV2);
	ROUGHNESS = roughness;
	EMISSION = emission * emission_strength;
	if (pattern == 0) {
		// ponytail: Facets shade_power isn't baked (every forest Facets material uses 0); bake the
		// facet's up component too if one needs it.
		ALBEDO = mix(base_color, side_color, t.a);
		NORMAL = normalize((VIEW_MATRIX * vec4(t.rgb * 2.0 - 1.0, 0.0)).xyz);
	} else {
		ALBEDO = base_color * blender_pow(t.a, shade_power);
	}
}
