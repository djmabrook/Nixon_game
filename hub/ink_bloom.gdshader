shader_type spatial;
// The ink bloom at a groove's outer end, in front of its door (art/tex/groove_ink_bloom_mask.png,
// top-down). It grows out from the centre as the ink fills the groove: `grow` 0 hides it,
// 1 shows every branch. Tinted with the room's ink in code.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2D mask : filter_nearest;
uniform vec3 tint : source_color = vec3(1.0, 0.32, 0.08);
uniform float grow = 0.0;
uniform float glow = 1.3;

void fragment() {
	float m = texture(mask, UV).a * texture(mask, UV).r;
	float d = length(UV - 0.5) * 2.0;   // 0 centre, 1 edge
	if (m < 0.5 || d > grow * 1.05) {
		discard;
	}
	ALBEDO = tint * glow;
}
