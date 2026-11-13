shader_type sky;
// Open sky outside the pupil's shadow fades to a starless crimson night inside it.
// Below the horizon is the void under the grid: pure black, so a laid hole shows nothing.

uniform float eclipse = 0.0;
uniform vec3 top_lit : source_color = vec3(0.52, 0.06, 0.12);
uniform vec3 horizon_lit : source_color = vec3(0.96, 0.80, 0.76);
uniform vec3 top_dark : source_color = vec3(0.02, 0.004, 0.006);
uniform vec3 horizon_dark : source_color = vec3(0.20, 0.02, 0.04);
uniform vec3 void_col : source_color = vec3(0.0);

void sky() {
	float y = EYEDIR.y;
	vec3 top = mix(top_lit, top_dark, eclipse);
	vec3 hor = mix(horizon_lit, horizon_dark, eclipse);
	vec3 c = mix(hor, top, pow(clamp(y, 0.0, 1.0), 0.42));
	// A thin hot band right on the horizon line.
	c += hor * 0.35 * exp(-abs(y) * 60.0);
	if (y < 0.0) {
		c = mix(hor, void_col, clamp(-y * 14.0, 0.0, 1.0));
	}
	COLOR = c;
}
