shader_type spatial;
// A small black disc: a hole you can carry. Near-black with a slow swirl deep inside
// and a thin wire rim, so it reads as an opening, not a plate.
render_mode unshaded, cull_disabled;

uniform vec3 rim_col : source_color = vec3(0.86, 0.07, 0.19);
uniform float rim = 1.0;
uniform float ink = 0.0;  // 1 = the crimson ink disc he takes home

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 1.6);
	vec3 col = vec3(0.0) + vec3(0.09, 0.01, 0.02) * swirl * (1.0 - r) * (1.0 + ink * 3.0);
	float ring = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.97, 1.0, r));
	col = mix(col, rim_col * (1.0 + ink * 1.5), ring * rim);
	ALBEDO = col;
}
