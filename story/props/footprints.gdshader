shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// One footprint: a pressed oval with a lighter crushed rim, on a quad lying on the sand.
uniform vec3 print_color : source_color = vec3(0.045, 0.035, 0.03);
uniform vec3 rim_color : source_color = vec3(0.62, 0.52, 0.44);
void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	// heel + ball: two overlapping ellipses make a sole shape.
	float ball = length((p - vec2(0.0, -0.32)) * vec2(1.45, 1.25));
	float heel = length((p - vec2(0.0, 0.42)) * vec2(1.9, 1.9));
	float d = min(ball, heel);
	float inside = 1.0 - smoothstep(0.62, 0.7, d);
	float rim = smoothstep(0.6, 0.72, d) * (1.0 - smoothstep(0.78, 0.95, d));
	ALBEDO = mix(rim_color, print_color, inside);
	ALPHA = max(inside * 0.9, rim * 0.35) * COLOR.a;
}
