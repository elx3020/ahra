// Blender's Image Texture "Box" projection, for meshes whose UVs aren't used.
// Matches Blender's Texture Coordinate (Object) -> Mapping (Scale) -> Image Texture (Box):
// pass the object-space position and normal from vertex() through blender_axes().
//
//   varying vec3 box_co;
//   varying vec3 box_n;
//   void vertex() { box_co = blender_axes(VERTEX) * scale; box_n = blender_axes(NORMAL); }
//   void fragment() { ALBEDO = box_projection(tex, box_co, box_n, blend).rgb; }
//
// Give the sampler repeat_enable. Port of Cycles' svm_node_tex_image_box.

/// Godot's Y-up axes to Blender's Z-up (glTF import turns Blender's (x, y, z) into (x, z, -y)).
vec3 blender_axes(vec3 v) {
	return vec3(v.x, -v.z, v.y);
}

/// How much of the X, Y and Z projections a surface with normal n gets; sums to 1.
/// blend is the Image Texture node's Blend: 0 = hard seams between the sides.
vec3 box_weights(vec3 n, float blend) {
	n = abs(n);
	n /= max(n.x + n.y + n.z, 1e-6);
	float limit = 0.5 * (1.0 + blend);
	// Corners of the barycentric triangle: one side only.
	if (n.x > limit * (n.x + n.y) && n.x > limit * (n.x + n.z)) {
		return vec3(1.0, 0.0, 0.0);
	}
	if (n.y > limit * (n.x + n.y) && n.y > limit * (n.y + n.z)) {
		return vec3(0.0, 1.0, 0.0);
	}
	if (n.z > limit * (n.x + n.z) && n.z > limit * (n.y + n.z)) {
		return vec3(0.0, 0.0, 1.0);
	}
	if (blend <= 0.0) {
		return vec3(1.0, 0.0, 0.0); // Exact ties; Blender falls back to X too.
	}
	// Edges: two sides.
	if (n.z < (1.0 - limit) * (n.x + n.y)) {
		float x = clamp((n.x / (n.x + n.y) - 0.5 * (1.0 - blend)) / blend, 0.0, 1.0);
		return vec3(x, 1.0 - x, 0.0);
	}
	if (n.x < (1.0 - limit) * (n.y + n.z)) {
		float y = clamp((n.y / (n.y + n.z) - 0.5 * (1.0 - blend)) / blend, 0.0, 1.0);
		return vec3(0.0, y, 1.0 - y);
	}
	if (n.y < (1.0 - limit) * (n.x + n.z)) {
		float x = clamp((n.x / (n.x + n.z) - 0.5 * (1.0 - blend)) / blend, 0.0, 1.0);
		return vec3(x, 0.0, 1.0 - x);
	}
	// Middle: all three.
	return ((2.0 - limit) * n + (limit - 1.0)) / (2.0 * limit - 1.0);
}

/// tex box-projected at Blender object coordinates co (Mapping already applied), for a
/// surface with Blender-axis normal n.
vec4 box_projection(sampler2D tex, vec3 co, vec3 n, float blend) {
	vec3 w = box_weights(n, blend);
	// Blender flips the sides that face away so none shows the image mirrored. Its images
	// start at the bottom-left corner and Godot's at the top-left, hence the 1 - v.
	vec2 uv_x = vec2(n.x < 0.0 ? 1.0 - co.y : co.y, 1.0 - co.z);
	vec2 uv_y = vec2(n.y > 0.0 ? 1.0 - co.x : co.x, 1.0 - co.z);
	vec2 uv_z = vec2(n.z > 0.0 ? 1.0 - co.y : co.y, 1.0 - co.x);
	// Sampled outside any branch so mipmap selection stays defined.
	return w.x * texture(tex, uv_x) + w.y * texture(tex, uv_y) + w.z * texture(tex, uv_z);
}
