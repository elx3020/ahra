// Shared by toon_rock.gdshader and toon_rock_outline.gdshader, so the outline pass bends
// the mesh exactly like the main pass.
//
// Per-rock settings are instance uniforms: set them on the MeshInstance3D under
// Geometry > Instance Shader Parameters, not on the material. One material serves every rock.
// The fixed instance_index keeps the slots the same in both passes, so both read one value.

/// Added to the rock's seed. Change it to re-roll a rock's shape, cracks and moss.
instance uniform float rock_seed : instance_index(0) = 0.0;
/// 1 = the seed also comes from the rock's world position (copies differ for free).
/// Set 0 on rocks that move, or their shape and pattern would crawl.
instance uniform float position_seed : instance_index(1) = 1.0;
/// Hue rotation of the whole rock, in turns (0.05 = a slight warm/cool shift).
instance uniform float hue_shift : instance_index(2) = 0.0;
/// Added to the material's moss_amount: positive = more moss on this rock.
instance uniform float moss_offset : instance_index(3) = 0.0;
/// Multiplies the material's crack_scale: above 1 = smaller, denser cracks.
instance uniform float crack_scale_mult : instance_index(4) = 1.0;
/// How far, in metres, vertices are pushed in or out by noise. Turns primitives into rocks;
/// use 0 on rocks that are already modelled.
instance uniform float shape_jitter : instance_index(5) = 0.15;
/// Size of the shape noise: higher = more, smaller lumps.
instance uniform float shape_noise_scale : instance_index(6) = 1.6;

float rock_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 rock_hash3(vec3 p) {
	return vec3(rock_hash(p), rock_hash(p + 17.13), rock_hash(p + 31.71));
}

float rock_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(rock_hash(i), rock_hash(i + vec3(1, 0, 0)), f.x),
			mix(rock_hash(i + vec3(0, 1, 0)), rock_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(rock_hash(i + vec3(0, 0, 1)), rock_hash(i + vec3(1, 0, 1)), f.x),
			mix(rock_hash(i + vec3(0, 1, 1)), rock_hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float rock_fbm(vec3 p) {
	return rock_noise(p) * 0.55 + rock_noise(p * 2.07 + 5.3) * 0.3 + rock_noise(p * 4.13 + 11.7) * 0.15;
}

/// The node's scale per axis, so patterns keep their size in metres on scaled rocks.
vec3 rock_scale(mat4 model) {
	return vec3(length(model[0].xyz), length(model[1].xyz), length(model[2].xyz));
}

/// Offset into the noise fields for this rock.
vec3 rock_seed_offset(vec3 node_position) {
	float s = rock_seed * 7.31 + position_seed * dot(node_position, vec3(1.731, 3.137, 2.371));
	return rock_hash3(vec3(s, s * 0.37, s * 0.73) + 0.5) * 64.0;
}

/// Pushes a vertex in or out along the direction from the mesh origin. Split vertices
/// (hard edges, UV seams) share a position, so they move together and no gaps open.
vec3 rock_deform(vec3 v, vec3 scale, vec3 seed) {
	float r = length(v);
	if (r < 0.0001 || shape_jitter <= 0.0) {
		return v;
	}
	vec3 p = v * scale * shape_noise_scale + seed;
	float d = rock_noise(p) * 0.7 + rock_noise(p * 2.3 + 3.1) * 0.3 - 0.5;
	return v + (v / r) * d * 2.0 * shape_jitter / scale;
}
