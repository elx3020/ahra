// Merges a mesh's two bake passes (forest_bake.gdshader) into one texture, RGB from the first and
// the second's grey in alpha, and dilates it: the empty texels around each UV2 chart take the
// nearest baked texel within radius. Bilinear filtering and mipmaps at a chart's border then mix in
// the chart's own values instead of the empty background, so seams don't show.
shader_type canvas_item;
render_mode blend_disabled;

/// First pass; its alpha is 0 where no chart was drawn.
uniform sampler2D colour_pass : filter_nearest, repeat_disable;
uniform sampler2D scalar_pass : filter_nearest, repeat_disable;
/// How far, in texels, the fill reaches from a chart.
uniform int radius = 8;

void fragment() {
	vec2 uv = UV;
	if (texture(colour_pass, UV).a < 0.5) {
		vec2 texel = 1.0 / vec2(textureSize(colour_pass, 0));
		float best = float(radius * radius) + 1.0;
		for (int y = -radius; y <= radius; y++) {
			for (int x = -radius; x <= radius; x++) {
				float d = float(x * x + y * y);
				vec2 o = UV + vec2(float(x), float(y)) * texel;
				if (d < best && texture(colour_pass, o).a > 0.5) {
					best = d;
					uv = o;
				}
			}
		}
	}
	COLOR = vec4(texture(colour_pass, uv).rgb, texture(scalar_pass, uv).r);
}
