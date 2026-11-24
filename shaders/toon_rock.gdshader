// Toon rock: one material for every rock, no textures and no UVs needed.
// Flat facets, banded light with warm lit / cool shadow tints, painted colour patches,
// ink cracks from 3D Voronoi edges, and moss on up-facing faces with noisy, drippy edges.
// The outline is the next pass (toon_rock_outline.gdshader). Per-rock settings live in
// toon_rock.gdshaderinc as instance uniforms.
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://shaders/toon_rock.gdshaderinc"

group_uniforms rock;
/// Main stone colour.
uniform vec4 rock_color : source_color = vec4(0.62, 0.56, 0.50, 1.0);
/// Second stone colour for the painted patches.
uniform vec4 rock_color_alt : source_color = vec4(0.48, 0.47, 0.50, 1.0);
/// How much of each patch takes the second colour (0 = plain rock).
uniform float patch_amount : hint_range(0.0, 1.0) = 0.7;
/// Patch size: higher = smaller patches.
uniform float patch_scale : hint_range(0.1, 6.0) = 0.9;
/// 1 = hard facets from the real geometry, 0 = the mesh's own smooth normals.
uniform float flat_shading : hint_range(0.0, 1.0) = 1.0;

group_uniforms toon_light;
/// Number of light values: 2 = lit/shadow, 3 = lit/mid/shadow.
uniform int bands : hint_range(2, 5) = 3;
/// Moves the light/shadow border: positive = more of the rock lit.
uniform float band_offset : hint_range(-1.0, 1.0) = 0.0;
/// Blur of the band borders (0 = razor sharp).
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
/// Tint of lit faces (warm).
uniform vec4 lit_tint : source_color = vec4(1.0, 0.93, 0.80, 1.0);
/// Tint added to faces in shadow (cool), from directional lights only.
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.50, 0.75, 1.0);
/// How bright the cool shadow fill is, relative to the light.
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.3;

group_uniforms cracks;
uniform vec4 crack_color : source_color = vec4(0.10, 0.08, 0.10, 1.0);
/// Crack cells per metre: higher = smaller cracks.
uniform float crack_scale : hint_range(0.1, 10.0) = 0.9;
/// Line width, as a fraction of a cell.
uniform float crack_width : hint_range(0.0, 0.2) = 0.025;
/// How much of the surface has cracks (they come and go in patches).
uniform float crack_coverage : hint_range(0.0, 1.0) = 0.4;

group_uniforms moss;
uniform vec4 moss_color : source_color = vec4(0.42, 0.56, 0.25, 1.0);
/// Second moss colour for patches.
uniform vec4 moss_color_alt : source_color = vec4(0.32, 0.46, 0.22, 1.0);
/// Darker rim along the moss border.
uniform vec4 moss_edge_color : source_color = vec4(0.20, 0.33, 0.15, 1.0);
/// Moss cover: -1 = none, 0 = tops only, 1 = most of the rock.
uniform float moss_amount : hint_range(-1.0, 1.0) = 0.0;
/// Which way is "up" for moss (world space).
uniform vec3 moss_direction = vec3(0.0, 1.0, 0.0);
/// How ragged the moss border is.
uniform float moss_edge_noise : hint_range(0.0, 1.0) = 0.35;
/// Size of the raggedness: higher = finer.
uniform float moss_noise_scale : hint_range(0.1, 10.0) = 2.5;
/// Width of the dark rim, in the same units as moss_amount.
uniform float moss_edge_width : hint_range(0.0, 0.3) = 0.1;
/// Strength of the drips running down the sides.
uniform float drip_amount : hint_range(0.0, 1.5) = 0.7;
/// Drips per metre around the rock.
uniform float drip_scale : hint_range(0.5, 12.0) = 4.0;
/// Drips fade out below the mesh origin over this many mesh units
/// (assumes the origin is about in the middle of the rock, as with primitives).
uniform float drip_reach : hint_range(0.0, 2.0) = 0.35;

varying vec3 v_rock_p; // scaled object position + seed: pattern space, in metres
varying vec3 v_local; // deformed object position, mesh units
varying vec3 v_seed;

vec3 hue_rotate(vec3 c, float turns) {
	float a = turns * TAU;
	vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

/// Distance to the nearest 3D Voronoi cell border (two-pass, after Inigo Quilez).
float voronoi_border(vec3 x) {
	vec3 n = floor(x);
	vec3 f = fract(x);
	vec3 mr = vec3(0.0);
	vec3 mg = vec3(0.0);
	float md = 8.0;
	for (int k = -1; k <= 1; k++)
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec3 g = vec3(float(i), float(j), float(k));
		vec3 r = g + rock_hash3(n + g) - f;
		float d = dot(r, r);
		if (d < md) {
			md = d;
			mr = r;
			mg = g;
		}
	}
	md = 8.0;
	for (int k = -2; k <= 2; k++)
	for (int j = -2; j <= 2; j++)
	for (int i = -2; i <= 2; i++) {
		vec3 g = mg + vec3(float(i), float(j), float(k));
		vec3 r = g + rock_hash3(n + g) - f;
		vec3 diff = r - mr;
		if (dot(diff, diff) > 0.00001) {
			md = min(md, dot(0.5 * (mr + r), normalize(diff)));
		}
	}
	return md;
}

float toon(float x) {
	float n = float(max(bands, 2) - 1);
	float v = x * n + 0.5;
	float b = floor(v) + smoothstep(1.0 - band_softness, 1.0, fract(v));
	return clamp(b / n, 0.0, 1.0);
}

void vertex() {
	vec3 scale = rock_scale(MODEL_MATRIX);
	v_seed = rock_seed_offset(NODE_POSITION_WORLD);
	VERTEX = rock_deform(VERTEX, scale, v_seed);
	v_local = VERTEX;
	v_rock_p = VERTEX * scale + v_seed;
}

void fragment() {
	// Flat normal from the screen-space derivatives of the position: hard facets on any mesh.
	vec3 flat_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_n, -VERTEX) < 0.0) {
		flat_n = -flat_n;
	}
	vec3 n = normalize(mix(NORMAL, flat_n, flat_shading));
	NORMAL = n;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 p = v_rock_p;

	// Stone: two colours in hard-edged painted patches.
	float patch_n = rock_fbm(p * patch_scale);
	float patch_aa = fwidth(patch_n) + 0.001;
	vec3 albedo = mix(rock_color.rgb, rock_color_alt.rgb,
			smoothstep(0.5 - patch_aa, 0.5 + patch_aa, patch_n) * patch_amount);

	// Cracks: Voronoi cell borders, shown only where a low-frequency mask allows.
	float cs = crack_scale * crack_scale_mult;
	float border = voronoi_border(p * cs);
	float mask = smoothstep(1.0 - crack_coverage - 0.08, 1.0 - crack_coverage + 0.08,
			rock_noise(p * cs * 0.35 + 7.7));
	float w = crack_width * mask;
	float baa = fwidth(border);
	float crack = (1.0 - smoothstep(w - baa, w + baa, border)) * step(0.001, w);
	albedo = mix(albedo, crack_color.rgb, crack);

	// Moss: faces pointing up, border broken by noise, drips hanging down the sides.
	float up = dot(world_n, normalize(moss_direction));
	float m = up - 0.55 + moss_amount + moss_offset;
	m += (rock_fbm(p * moss_noise_scale + 3.3) - 0.5) * 2.0 * moss_edge_noise;
	vec3 drip_p = vec3(p.x * drip_scale, p.y * drip_scale * 0.12, p.z * drip_scale);
	float drip = smoothstep(0.45, 0.8, rock_noise(drip_p + 19.1)) * drip_amount;
	drip *= smoothstep(-drip_reach, drip_reach, v_local.y) * smoothstep(-0.5, 0.0, up);
	m += drip;
	float maa = fwidth(m) + 0.001;
	float moss = smoothstep(-maa, maa, m);
	float moss_inner = smoothstep(moss_edge_width - maa, moss_edge_width + maa, m);
	float moss_patch = smoothstep(0.48, 0.52, rock_noise(p * moss_noise_scale * 0.7 + 41.0));
	vec3 moss_col = mix(moss_color.rgb, moss_color_alt.rgb, moss_patch);
	moss_col = mix(moss_edge_color.rgb, moss_col, moss_inner);
	albedo = mix(albedo, moss_col, moss);

	ALBEDO = hue_rotate(albedo, hue_shift);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float x = clamp(dot(NORMAL, LIGHT) + band_offset, 0.0, 1.0) * ATTENUATION;
	float band = toon(x);
	// LIGHT_COLOR carries a factor of PI for physically based models; take it out.
	vec3 c = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += c * lit_tint.rgb * band;
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += c * shadow_tint.rgb * shadow_fill * (1.0 - band);
	}
}
