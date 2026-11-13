shader_type spatial;
// A click ripple on the ground: one thin ring that grows and dithers away.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.937, 0.902, 0.847, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.08;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	float r = mix(0.1, 1.0, progress);
	float ring = 1.0 - step(width, abs(d - r));
	float fade = (1.0 - progress) * color.a;
	if (ring < 0.5 || bayer4(FRAGCOORD.xy) >= fade) {
		discard;
	}
	ALBEDO = color.rgb;
}
