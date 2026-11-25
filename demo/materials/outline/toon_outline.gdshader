// Toon outline post-process. Drawn on a full-screen quad (toon_outline.tscn), it compares each
// pixel with its neighbours in three buffers and draws three kinds of line, each switchable:
//   silhouette: depth jumps (an object against what is behind it)
//   edges:      normal jumps on one surface (creases, facet borders, where objects meet)
//   details:    colour jumps in the rendered image (moss against rock, painted patches)
// Lines get their width, gaps and wobble from noise anchored in world space, so they stay on the
// geometry when the camera moves, and they turn thinner on lit faces. Edge lines are a soft-light
// blend over the surface under them (brighter on lit faces, darker in shadow); silhouette and
// detail lines are drawn in the line colour. Detail lines on the border of a cast shadow are
// dropped: the quad is lit (colour in EMISSION, no ambient) only so light() can read the sun's
// shadow map at the darker side of the border, moved there through LIGHT_VERTEX.
// The normal buffer exists only in Forward+. In Compatibility, normals are rebuilt from depth.
shader_type spatial;
render_mode fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, ambient_light_disabled, specular_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif

group_uniforms line;
/// Colour of silhouette and detail lines.
uniform vec4 line_color : source_color = vec4(0.07, 0.05, 0.08, 1.0);
/// Base line width in pixels (each line type multiplies it).
uniform float line_width : hint_range(0.5, 8.0) = 2.2;
/// 0 = flat line colour, 1 = a darkened version of the surface under the line (coloured ink).
uniform float surface_tint : hint_range(0.0, 1.0) = 0.25;

group_uniforms silhouette;
uniform bool show_silhouette = true;
/// Smooth silhouette borders: pixels near one run its test 4 more times.
uniform bool silhouette_antialias = true;
/// Width multiplier for silhouette lines.
uniform float silhouette_width : hint_range(0.0, 4.0) = 1.5;
/// How far behind the surface, in metres, the neighbour must be to count as a silhouette.
uniform float silhouette_threshold : hint_range(0.01, 2.0) = 0.15;

group_uniforms edges;
uniform bool show_edges = true;
/// Smooth crease borders: pixels near one run its test 4 more times.
uniform bool edge_antialias = true;
/// Width multiplier for crease lines (they draw on both faces of the crease, so keep it lower).
uniform float edge_width : hint_range(0.0, 4.0) = 0.7;
/// Bend needed for a crease line: 0 = any bend, 1 = a 90 degree corner.
uniform float edge_threshold : hint_range(0.01, 1.0) = 0.25;
/// Soft-light layer for edges on lit faces. Light colours brighten the surface; white = most.
uniform vec3 highlight_color : source_color = vec3(1.0, 0.95, 0.85);
/// Soft-light layer for edges in shadow. Dark colours darken the surface; black = most.
uniform vec3 shadow_color : source_color = vec3(0.0, 0.0, 0.03);

group_uniforms details;
uniform bool show_details = true;
/// Smooth colour-border lines: pixels near one run their test 4 more times.
uniform bool detail_antialias = true;
/// Width multiplier for colour-border lines.
uniform float detail_width : hint_range(0.0, 4.0) = 0.6;
/// Colour difference needed for a detail line.
uniform float detail_threshold : hint_range(0.01, 1.0) = 0.12;
/// 1 = only changes of hue count, so toon light bands draw no lines.
uniform float detail_ignore_shading : hint_range(0.0, 1.0) = 0.85;
/// What a lit colour gets multiplied by in cast shadow (a white wall's shadow). Detail lines along
/// this tint are checked against the sun's shadow map and dropped where they border a shadow.
uniform vec3 cast_shadow_tint : source_color = vec3(0.46, 0.57, 0.73);
/// How loosely a colour change must follow the tint to be checked. 0 = shadows draw lines.
uniform float cast_shadow_tolerance : hint_range(0.0, 1.0) = 0.4;

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

/// Rotated-grid sample points inside a pixel, for antialiasing.
const vec2 SUBPIXEL[4] = vec2[](
	vec2(0.125, 0.375), vec2(-0.375, 0.125), vec2(0.375, -0.125), vec2(-0.125, -0.375));
/// How much wider, in pixels, the antialias pre-check reaches than the test: the sample points sit
/// up to 0.4 px from the pixel point.
const float AA_REACH = 0.5;

/// Line alpha with and without the shadow-like detail lines; light() picks between them.
varying float v_alpha_kept;
varying float v_alpha_dropped;

/// 1 when b could be a seen in a cast shadow or out of one: their colour ratio follows
/// cast_shadow_tint. Dark moss on light moss can look the same, so light() has the last word.
float shadow_step(vec3 a, vec3 b) {
	if (cast_shadow_tolerance <= 0.0) {
		return 0.0;
	}
	vec3 s = log(max(cast_shadow_tint, vec3(0.001)));
	vec3 v = log(max(b, vec3(1e-4)) / max(a, vec3(1e-4)));
	// k = how much of a full shadow the change is (negative: out of one); off = sine of its angle
	// to the tint.
	float k = dot(v, s) / max(dot(s, s), 1e-4);
	float off = length(v - k * s) / max(length(v), 1e-4);
	return smoothstep(0.15, 0.3, abs(k))
			* (1.0 - smoothstep(cast_shadow_tolerance, cast_shadow_tolerance + 0.1, off));
}

/// Neighbour i at r pixels from c_uv, kept off the screen border.
vec2 neighbour(vec2 c_uv, vec2 px, int i, float r) {
	return clamp(c_uv + DIRS[i] * r * px, px * 2.0, 1.0 - px * 2.0);
}

// Each test gives the line strength at the pixel point c_uv, r = its line width in pixels.
// Depth tests measure the neighbour's distance from this pixel's surface plane, in metres,
// so they hold up on surfaces seen at a grazing angle and at any camera distance.

/// both_sides: also count the far side of a depth jump, where the line isn't drawn (a pixel there
/// can have sample points on the near side).
float silhouette_test(vec2 c_uv, vec2 px, mat4 ip, float r, bool both_sides) {
	vec3 pc = view_pos(c_uv, ip);
	vec3 nc = view_normal(c_uv, px, ip);
	float sil = 0.0;
	for (int i = 0; i < 8; i++) {
		float behind = -dot(view_pos_sky(neighbour(c_uv, px, i, r), ip) - pc, nc);
		behind = both_sides ? abs(behind) : behind;
		sil = max(sil, smoothstep(silhouette_threshold, silhouette_threshold * 1.5, behind));
	}
	return sil;
}

float edge_test(vec2 c_uv, vec2 px, mat4 ip, float r) {
	vec3 pc = view_pos(c_uv, ip);
	vec3 nc = view_normal(c_uv, px, ip);
	float edge = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 o = neighbour(c_uv, px, i, r);
		float off_plane = abs(dot(view_pos_sky(o, ip) - pc, nc));
		if (off_plane < silhouette_threshold) {
			float bend = 1.0 - dot(nc, view_normal(o, px, ip));
			edge = max(edge, smoothstep(edge_threshold, edge_threshold * 1.4, bend));
		}
	}
	return edge;
}

/// Detail and shadow-like detail. For the strongest shadow-like detail so far (best), dark_uv is
/// its darker side. shadows = false skips the shadow check: every detail counts as not shadow-like.
vec2 detail_test(vec2 c_uv, vec2 px, float r, bool shadows, inout float best, inout vec2 dark_uv) {
	vec3 sc = textureLod(screen_tex, c_uv, 0.0).rgb;
	vec3 cc = chroma(sc);
	float det = 0.0;
	float shadowy = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 o = neighbour(c_uv, px, i, r);
		vec3 sn = textureLod(screen_tex, o, 0.0).rgb;
		float d_hue = length(chroma(sn) - cc) * 3.0;
		float d_all = length(sn - sc);
		float d = smoothstep(detail_threshold, detail_threshold * 1.5,
				mix(d_all, d_hue, detail_ignore_shading));
		float t = shadows ? shadow_step(sc, sn) : 0.0;
		det = max(det, d * (1.0 - t));
		shadowy = max(shadowy, d * t);
		if (d * t > best) {
			best = d * t;
			dark_uv = dot(sn, vec3(1.0)) < dot(sc, vec3(1.0)) ? o : c_uv;
		}
	}
	return vec2(det, shadowy);
}

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

	// Line strengths: silhouette, edge, detail, shadow-like detail. A line type that's off costs
	// nothing. Antialias averages a test over four points inside the pixel, so line borders get
	// partial coverage instead of stair steps. That's 4x the cost, so a pixel first runs one test
	// reaching AA_REACH further, and only one near a line pays for the four.
	vec4 lines = vec4(0.0);
	float best = 0.0;
	vec2 dark_uv = c_uv;
	if (show_silhouette) {
		float r = w * silhouette_width;
		if (!silhouette_antialias) {
			lines.x = silhouette_test(c_uv, px, ip, r, false);
		} else if (silhouette_test(c_uv, px, ip, r + AA_REACH, true) > 0.0) {
			for (int s = 0; s < 4; s++) {
				lines.x += silhouette_test(c_uv + SUBPIXEL[s] * px, px, ip, r, false) * 0.25;
			}
		}
	}
	if (show_edges) {
		float r = w * edge_width;
		if (!edge_antialias) {
			lines.y = edge_test(c_uv, px, ip, r);
		} else if (edge_test(c_uv, px, ip, r + AA_REACH) > 0.0) {
			for (int s = 0; s < 4; s++) {
				lines.y += edge_test(c_uv + SUBPIXEL[s] * px, px, ip, r) * 0.25;
			}
		}
	}
	if (show_details) {
		float r = w * detail_width;
		if (!detail_antialias) {
			lines.zw = detail_test(c_uv, px, r, true, best, dark_uv);
		} else if (detail_test(c_uv, px, r + AA_REACH, false, best, dark_uv).x > 0.0) {
			// (without the shadow check it leaves best and dark_uv alone)
			for (int s = 0; s < 4; s++) {
				lines.zw += detail_test(c_uv + SUBPIXEL[s] * px, px, r, true, best, dark_uv) * 0.25;
			}
		}
	}

	float gap = break_amount > 0.0 ? smoothstep(break_amount - 0.04, break_amount + 0.04, n_break) : 1.0;
	float edge_line = lines.y * gap;
	float ink_dropped = max(lines.x * (break_silhouette ? gap : 1.0), lines.z * gap);
	float ink = max(ink_dropped, lines.w * gap);
	if (max(edge_line, ink) <= 0.001) {
		discard;
	}

	// Edges, soft light (pegtop): layer > 0.5 brightens the base, < 0.5 darkens it. The layer
	// slides from the shadow colour to the highlight colour with how lit the pixel is.
	vec3 base = clamp(sc, 0.0, 1.0);
	vec3 layer = mix(shadow_color, highlight_color, lit);
	vec3 soft = (1.0 - 2.0 * layer) * base * base + 2.0 * layer * base;
	// Silhouettes and details: line colour, drawn over edges where they meet.
	vec3 inked = mix(line_color.rgb, sc * 0.35, surface_tint);
	ALBEDO = vec3(0.0);
	EMISSION = mix(soft, inked, ink);
	float fade = 1.0 - light_fade * lit;
	v_alpha_kept = clamp(max(edge_line, ink * line_color.a) * fade, 0.0, 1.0);
	v_alpha_dropped = clamp(max(edge_line, ink_dropped * line_color.a) * fade, 0.0, 1.0);
	ALPHA = v_alpha_kept;
	// Light the darker side of the strongest shadow-like detail, for light() to read its shadow.
	LIGHT_VERTEX = view_pos(dark_uv, ip);
	NORMAL = view_normal(dark_uv, px, ip);
}

void light() {
	// In the sun's shadow: the shadow-like detail line is the shadow's own border, drop it.
	// ponytail: the last directional light wins; fine while scenes have one sun.
	if (LIGHT_IS_DIRECTIONAL) {
		ALPHA = mix(v_alpha_dropped, v_alpha_kept, ATTENUATION);
	}
}
