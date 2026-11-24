// Main material of the deep forest scene (enviroment_test.tscn), ported from deep_forest.blend.
// There every material is a Principled BSDF; the plain ones are StandardMaterial3D here. These
// ones feed the BSDF from 3D procedural textures in object space (Noise, Voronoi), which
// StandardMaterial3D has no counterpart for, so this shader rebuilds those node trees. The noise
// follows EEVEE's own GLSL (Jenkins lookup3 hash + Perlin fBm for Noise Texture, PCG-hashed cells
// for Voronoi), so the patterns land where they do in Blender.
//   Facets (rock, ground uv.001, crystal): the noise-warped object position picks a Voronoi cell,
//     and the mesh normal bent towards the cell's position gives flat facets; how far up a facet
//     points picks its colour.
//   Bark (Material.001): each Voronoi cell gets its own shade of the base colour. Its wave bump
//     (normals tilted ~1.5 degrees) is left out.
//   Canopy (Material.003): noise holes in a shadow-only plane high above, dappling the sunlight.
// Blender is Z up, Godot Y up (glTF: x, z, -y): patterns read the mesh in Blender's axes.
// Diffuse is Lambert, like the Principled BSDF; specular 0.5 is its default IOR level.
shader_type spatial;
render_mode diffuse_lambert;

uniform int pattern : hint_enum("Facets", "Bark", "Canopy") = 0;

group_uniforms colour;
/// Principled Base Color. Facets: faces turned up past top_threshold, and facets at or below
/// side_threshold. Bark: the colour each cell shades.
uniform vec3 base_color : source_color = vec3(0.482, 0.627, 0.569);
/// Facets: colour of side faces whose facet points up more than side_threshold.
uniform vec3 side_color : source_color = vec3(0.725, 0.512, 0.516);
/// Facets: mesh normal up component (Blender Z) above which a face is base_color whatever its facet.
uniform float top_threshold = 0.48;
/// Facets: facet up component above which a face (not turned up past top_threshold) is side_color.
uniform float side_threshold = -0.22;
/// Facets: colour times (facet up component)^shade_power. Bark: cell shade^shade_power.
/// 0 = flat colour.
uniform float shade_power = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.683;
uniform vec3 emission : source_color = vec3(1.0);
uniform float emission_strength = 0.0;

group_uniforms noise;
/// Noise Texture (3D fBm, roughness 0.5, lacunarity 2, normalized).
uniform float noise_scale = 5.0;
uniform float noise_detail : hint_range(0.0, 15.0) = 2.0;
/// Facets: Mix factor from the noise (0) to the object position (1) for the Voronoi input.
uniform float warp : hint_range(0.0, 1.0) = 0.751;
/// Canopy: holes where the noise is at or below this.
uniform float cutout : hint_range(0.0, 1.0) = 0.6;

group_uniforms cells;
/// Voronoi Texture (3D F1, randomness 1, roughness 0.5, lacunarity 2).
uniform float cell_scale = 0.69;
/// Voronoi Detail, whole octaves only.
uniform int cell_detail : hint_range(0, 4) = 1;
uniform bool cell_manhattan = false;
/// Facets: Mix factor from the mesh normal (0) to the cell position (1) for the shading normal.
uniform float facet : hint_range(0.0, 1.0) = 0.552;
/// Bark: Color Ramp end. Cell brightness 0..ramp_end maps to shade 0..1.
uniform float ramp_end : hint_range(0.01, 1.0) = 0.964;

varying vec3 v_obj;
varying vec3 v_nobj;

// Jenkins lookup3 hash of three words, as Blender's hash_uint3.
uint rot(uint x, uint k) {
	return (x << k) | (x >> (32u - k));
}

uint hash3(uint kx, uint ky, uint kz) {
	uint a = 3735928584u; // 0xdeadbeef + (3 << 2) + 13
	uint b = a;
	uint c = a;
	c += kz;
	b += ky;
	a += kx;
	c ^= b; c -= rot(b, 14u);
	a ^= c; a -= rot(c, 11u);
	b ^= a; b -= rot(a, 25u);
	c ^= b; c -= rot(b, 16u);
	a ^= c; a -= rot(c, 4u);
	b ^= a; b -= rot(a, 14u);
	c ^= b; c -= rot(b, 24u);
	return c;
}

float grad(ivec3 cell, vec3 f) {
	uint h = hash3(uint(cell.x), uint(cell.y), uint(cell.z)) & 15u;
	float u = h < 8u ? f.x : f.y;
	float v = h < 4u ? f.y : (h == 12u || h == 14u ? f.x : f.z);
	return ((h & 1u) != 0u ? -u : u) + ((h & 2u) != 0u ? -v : v);
}

/// Blender's signed Perlin noise (snoise), about -1..1.
float snoise(vec3 p) {
	vec3 pf = floor(p);
	ivec3 i = ivec3(pf);
	vec3 f = p - pf;
	vec3 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float x0 = mix(grad(i, f), grad(i + ivec3(1, 0, 0), f - vec3(1.0, 0.0, 0.0)), w.x);
	float x1 = mix(grad(i + ivec3(0, 1, 0), f - vec3(0.0, 1.0, 0.0)), grad(i + ivec3(1, 1, 0), f - vec3(1.0, 1.0, 0.0)), w.x);
	float x2 = mix(grad(i + ivec3(0, 0, 1), f - vec3(0.0, 0.0, 1.0)), grad(i + ivec3(1, 0, 1), f - vec3(1.0, 0.0, 1.0)), w.x);
	float x3 = mix(grad(i + ivec3(0, 1, 1), f - vec3(0.0, 1.0, 1.0)), grad(i + ivec3(1, 1, 1), f - vec3(1.0)), w.x);
	return 0.982 * mix(mix(x0, x1, w.y), mix(x2, x3, w.y), w.z);
}

/// Noise Texture Factor: normalized fBm, fractional detail blends in the last octave.
float fbm(vec3 p, float detail) {
	float scale = 1.0;
	float amp = 1.0;
	float max_amp = 0.0;
	float sum = 0.0;
	for (int i = 0; i <= int(detail); i++) {
		sum += snoise(p * scale) * amp;
		max_amp += amp;
		amp *= 0.5;
		scale *= 2.0;
	}
	float value = 0.5 * sum / max_amp + 0.5;
	float rest = detail - floor(detail);
	if (rest > 0.0) {
		float more = 0.5 * (sum + snoise(p * scale) * amp) / (max_amp + amp) + 0.5;
		value = mix(value, more, rest);
	}
	return value;
}

/// Blender's PCG hash of a Voronoi cell, 0..1 per axis.
vec3 cell_hash(ivec3 v) {
	v = v * 1664525 + 1013904223;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> ivec3(16);
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return vec3(v & ivec3(2147483647)) * (1.0 / 2147483647.0);
}

void voronoi_f1(vec3 coord, out vec3 pos, out vec3 col) {
	vec3 cf = floor(coord);
	vec3 local = coord - cf;
	ivec3 c = ivec3(cf);
	float best = 1e30;
	ivec3 best_off = ivec3(0);
	vec3 best_point = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				ivec3 off = ivec3(i, j, k);
				vec3 d = vec3(off) + cell_hash(c + off) - local;
				float dist = cell_manhattan ? abs(d.x) + abs(d.y) + abs(d.z) : length(d);
				if (dist < best) {
					best = dist;
					best_off = off;
					best_point = d + local;
				}
			}
		}
	}
	pos = best_point + cf;
	col = cell_hash(c + best_off);
}

/// Voronoi Texture Position (in input units) and Color, fractal over cell_detail octaves.
void voronoi(vec3 p, out vec3 pos, out vec3 col) {
	vec3 coord = p * cell_scale;
	voronoi_f1(coord, pos, col);
	float scale = 1.0;
	float amp = 1.0;
	for (int i = 0; i < cell_detail; i++) {
		scale *= 2.0;
		amp *= 0.5;
		vec3 octave_pos;
		vec3 octave_col;
		voronoi_f1(coord * scale, octave_pos, octave_col);
		col += octave_col * amp;
		pos = mix(pos, octave_pos / scale, amp);
	}
	pos /= cell_scale;
}

/// Math node Power: 0 for a negative base (whole exponents aside, unused here).
float blender_pow(float a, float b) {
	return b == 0.0 ? 1.0 : (a >= 0.0 ? pow(a, b) : 0.0);
}

void vertex() {
	v_obj = vec3(VERTEX.x, -VERTEX.z, VERTEX.y);
	v_nobj = vec3(NORMAL.x, -NORMAL.z, NORMAL.y);
}

void fragment() {
	ROUGHNESS = roughness;
	EMISSION = emission * emission_strength;
	ALBEDO = base_color;
	if (pattern == 0) {
		vec3 n = normalize(v_nobj);
		vec3 warped = mix(vec3(fbm(v_obj * noise_scale, noise_detail)), v_obj, warp);
		vec3 cell_pos;
		vec3 cell_col;
		voronoi(warped, cell_pos, cell_col);
		// Blender feeds this object-space blend into the BSDF's world-space Normal input.
		vec3 f = mix(n, cell_pos, facet);
		bool side = n.z <= top_threshold && f.z > side_threshold;
		ALBEDO = (side ? side_color : base_color) * blender_pow(f.z, shade_power);
		NORMAL = normalize((VIEW_MATRIX * vec4(f.x, f.z, -f.y, 0.0)).xyz);
	} else if (pattern == 1) {
		vec3 cell_pos;
		vec3 cell_col;
		voronoi(v_obj, cell_pos, cell_col);
		float shade = clamp(dot(cell_col, vec3(0.2126729, 0.7151522, 0.072175)) / ramp_end, 0.0, 1.0);
		ALBEDO = base_color * blender_pow(shade, shade_power);
	} else if (fbm(vec3(UV.x, 1.0 - UV.y, 0.0) * noise_scale, noise_detail) <= cutout) {
		discard;
	}
}
