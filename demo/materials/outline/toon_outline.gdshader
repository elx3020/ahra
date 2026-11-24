// Toon outline post-process. Drawn on a full-screen quad (toon_outline.tscn), it compares each
// pixel with its neighbours in three buffers and draws three kinds of line, each switchable:
//   silhouette: depth jumps (an object against what is behind it)
//   edges:      normal jumps on one surface (creases, facet borders, where objects meet)
//   details:    colour jumps in the rendered image (moss against rock, painted patches)
// Lines get their width, gaps and wobble from noise anchored in world space, so they stay on the
// geometry when the camera moves, and they turn thinner and paler on lit faces.
// The normal buffer exists only in Forward+. In Compatibility, normals are rebuilt from depth.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif

group_uniforms line;
uniform vec4 line_color : source_color = vec4(0.07, 0.05, 0.08, 1.0);
/// Base line width in pixels (each line type multiplies it).
uniform float line_width : hint_range(0.5, 8.0) = 2.2;
/// 0 = flat line colour, 1 = a darkened version of the surface under the line (coloured ink).
uniform float surface_tint : hint_range(0.0, 1.0) = 0.25;

group_uniforms silhouette;
uniform bool show_silhouette = true;
/// Width multiplier for silhouette lines.
uniform float silhouette_width : hint_range(0.0, 4.0) = 1.5;
/// How far behind the surface, in metres, the neighbour must be to count as a silhouette.
uniform float silhouette_threshold : hint_range(0.01, 2.0) = 0.15;

group_uniforms edges;
uniform bool show_edges = true;
/// Width multiplier for crease lines (they draw on both faces of the crease, so keep it lower).
uniform float edge_width : hint_range(0.0, 4.0) = 0.7;
/// Bend needed for a crease line: 0 = any bend, 1 = a 90 degree corner.
uniform float edge_threshold : hint_range(0.01, 1.0) = 0.25;

group_uniforms details;
uniform bool show_details = true;
/// Width multiplier for colour-border lines.
uniform float detail_width : hint_range(0.0, 4.0) = 0.6;
/// Colour difference needed for a detail line.
uniform float detail_threshold : hint_range(0.01, 1.0) = 0.12;
/// 1 = only changes of hue count, so toon light bands and shadows draw no lines.
uniform float detail_ignore_shading : hint_range(0.0, 1.0) = 0.85;

group_uniforms noise;
/// Noise features per metre. Lower = slow swells in the line, higher = jittery.
uniform float noise_scale : hint_range(0.1, 20.0) = 2.5;
/// How much the width swells and thins (0 = even line).
uniform float width_noise : hint_range(0.0, 1.0) = 0.6;
/// Share of each line broken into gaps (0 = unbroken).
uniform float break_amount : hint_range(0.0, 0.9) = 0.15;
/// Gaps also break silhouettes. Off keeps the outer contour closed.
uniform bool break_silhouette = false;
/// How far lines wander off the true edge, in pixels.
uniform float wobble : hint_range(0.0, 4.0) = 0.8;

group_uniforms light;
/// Direction towards the light, world space. toon_outline.gd keeps it in step with the sun.
uniform vec3 light_direction = vec3(0.4, 0.8, 0.4);
/// How much thinner lines get on lit faces (1 = they vanish).
uniform float light_thin : hint_range(0.0, 1.0) = 0.45;
/// How much thicker lines get on faces turned away from the light.
uniform float shadow_boost : hint_range(0.0, 2.0) = 0.5;
/// How much paler lines get on lit faces.
uniform float light_fade : hint_range(0.0, 1.0) = 0.35;
/// What decides "lit": 0 = face angle to the light only, 1 = brightness of the rendered pixel
/// (also catches cast shadows and toon bands).
uniform float light_from_brightness : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	// Cover the whole screen whatever the camera does.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float raw_depth(vec2 uv) {
	return textureLod(depth_tex, uv, 0.0).r;
}

bool is_sky(float d) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return d >= 1.0;
#else
	return d <= 0.0;
#endif
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = raw_depth(uv);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

/// Position in view space; sky is pushed very far away along its view ray.
vec3 view_pos_sky(vec2 uv, mat4 inv_proj) {
	vec3 p = view_pos(uv, inv_proj);
	return is_sky(raw_depth(uv)) ? normalize(p) * 1e6 : p;
}

vec3 view_normal(vec2 uv, vec2 px, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 c = view_pos(uv, inv_proj);
	vec3 dx = view_pos(uv + vec2(px.x, 0.0), inv_proj) - c;
	vec3 dy = view_pos(uv + vec2(0.0, px.y), inv_proj) - c;
	vec3 n = normalize(cross(dy, dx));
	return dot(n, -c) < 0.0 ? -n : n;
#else
	return normalize(textureLod(normal_tex, uv, 0.0).xyz * 2.0 - 1.0);
#endif
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

vec3 chroma(vec3 c) {
	return c / (c.r + c.g + c.b + 0.05);
}

const vec2 DIRS[8] = vec2[](
	vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
	vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071), vec2(0.7071, -0.7071), vec2(-0.7071, -0.7071));

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	if (is_sky(raw_depth(uv))) {
		discard;
	}
	mat4 ip = INV_PROJECTION_MATRIX;

	// Noise lives on the geometry, not the screen, so lines don't crawl when the camera moves.
	vec3 world = (INV_VIEW_MATRIX * vec4(view_pos(uv, ip), 1.0)).xyz;
	vec3 q = world * noise_scale;
	float n_width = noise(q) * 0.65 + noise(q * 2.3 + 4.1) * 0.35;
	float n_break = noise(q * 0.6 + 17.3);
	vec2 wob = vec2(noise(q * 1.3 + 3.7), noise(q * 1.3 + 9.2)) - 0.5;

	vec2 c_uv = uv + wob * 2.0 * wobble * px;
	vec3 sc = textureLod(screen_tex, c_uv, 0.0).rgb;
	vec3 pc = view_pos(c_uv, ip);
	vec3 nc = view_normal(c_uv, px, ip);

	// Light: face angle to the light, and/or how bright the pixel came out.
	vec3 nw = normalize(mat3(INV_VIEW_MATRIX) * nc);
	float lit_angle = smoothstep(-0.1, 0.5, dot(nw, normalize(light_direction)));
	float luma = dot(sc, vec3(0.299, 0.587, 0.114));
	float lit_bright = smoothstep(0.15, 0.6, luma);
	float lit = mix(lit_angle, lit_bright, light_from_brightness);

	float w = line_width * (1.0 + (n_width - 0.5) * 2.0 * width_noise)
			* mix(1.0 + shadow_boost, 1.0 - light_thin, lit);
	w = max(w, 0.0);

	// Depth tests measure the neighbour's distance from this pixel's surface plane, in metres,
	// so they hold up on surfaces seen at a grazing angle and at any camera distance.
	float sil = 0.0;
	float edge = 0.0;
	float det = 0.0;
	vec3 cc = chroma(sc);
	for (int i = 0; i < 8; i++) {
		if (show_silhouette) {
			vec2 o = clamp(c_uv + DIRS[i] * w * silhouette_width * px, px * 2.0, 1.0 - px * 2.0);
			float behind = -dot(view_pos_sky(o, ip) - pc, nc);
			sil = max(sil, smoothstep(silhouette_threshold, silhouette_threshold * 1.5, behind));
		}
		if (show_edges) {
			vec2 o = clamp(c_uv + DIRS[i] * w * edge_width * px, px * 2.0, 1.0 - px * 2.0);
			float off_plane = abs(dot(view_pos_sky(o, ip) - pc, nc));
			if (off_plane < silhouette_threshold) {
				vec3 nn = view_normal(o, px, ip);
				float bend = 1.0 - dot(nc, nn);
				edge = max(edge, smoothstep(edge_threshold, edge_threshold * 1.4, bend));
			}
		}
		if (show_details) {
			vec2 o = clamp(c_uv + DIRS[i] * w * detail_width * px, px * 2.0, 1.0 - px * 2.0);
			vec3 sn = textureLod(screen_tex, o, 0.0).rgb;
			float d_hue = length(chroma(sn) - cc) * 3.0;
			float d_all = length(sn - sc);
			float diff = mix(d_all, d_hue, detail_ignore_shading);
			det = max(det, smoothstep(detail_threshold, detail_threshold * 1.5, diff));
		}
	}

	float gap = break_amount > 0.0 ? smoothstep(break_amount - 0.04, break_amount + 0.04, n_break) : 1.0;
	float inner = max(edge, det) * gap;
	float outer = sil * (break_silhouette ? gap : 1.0);
	float line = max(outer, inner);
	if (line <= 0.001) {
		discard;
	}

	ALBEDO = mix(line_color.rgb, sc * 0.35, surface_tint);
	ALPHA = clamp(line * line_color.a * (1.0 - light_fade * lit), 0.0, 1.0);
}
