shader_type spatial;
// The pressed circle once the ring has cut it free. Same wires as the plain, drawn in
// the mesh's own space so they stay put while it falls away into the dark.
render_mode unshaded, cull_disabled;

uniform float radius = 36.0;
uniform float cell = 8.0;
uniform float fade = 1.0;
uniform vec3 wire : source_color = vec3(0.86, 0.07, 0.19);
uniform vec3 bone : source_color = vec3(0.94, 0.90, 0.85);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp);
	if (r > radius) discard;
	vec2 g = lp / cell;
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 d = abs(fract(g - 0.5) - 0.5) / fw;
	float l = 1.0 - clamp(min(d.x, d.y), 0.0, 1.0);
	float rim = smoothstep(radius - 0.9, radius - 0.1, r);
	vec2 g2 = lp / (cell * 0.25);
	vec2 fw2 = max(fwidth(g2), vec2(1e-5));
	vec2 d2 = abs(fract(g2 - 0.5) - 0.5) / fw2;
	float l2 = 1.0 - clamp(min(d2.x, d2.y), 0.0, 1.0);
	vec3 c = vec3(0.03, 0.006, 0.01) + wire * max(l * 1.2, l2 * 0.35) + bone * rim * 2.0;
	ALBEDO = c * fade;
}
