shader_type spatial;
// The stare: a shaft from the pupil's centre down to the bottom of the sag.
// It presses: streaks run downward. `cut` fades it from the bottom up when the lid closes.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, blend_add;

uniform vec3 core : source_color = vec3(0.94, 0.86, 0.82);
uniform vec3 edge : source_color = vec3(0.78, 0.06, 0.18);
uniform float strength = 1.0;
uniform float cut = 0.0;
uniform float bottom_y = -220.0;
uniform float top_y = 880.0;

varying float h;

void vertex() {
	h = ((MODEL_MATRIX * vec4(VERTEX, 1.0)).y - bottom_y) / (top_y - bottom_y);
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float core_k = pow(facing, 3.0);
	float streak = 0.6 + 0.4 * sin(h * 900.0 + TIME * 14.0) * sin(h * 230.0 + TIME * 5.0);
	vec3 c = mix(edge, core, core_k) * (0.35 + 0.65 * core_k) * streak;
	float a = strength * smoothstep(cut, cut + 0.05, h);
	// Bright where it lands, thinner as it climbs into the pupil.
	float landing = 1.0 + 3.0 * exp(-h * 40.0);
	ALBEDO = c * a * landing * (0.7 + 0.3 * sin(TIME * 1.7));
}
