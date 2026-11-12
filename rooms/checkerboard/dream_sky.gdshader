shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Screen-filling backdrop that hangs behind the room: black void, a band of
// pink storm cloud streaking sideways, and a thin red horizon line.

uniform float drift_speed = 0.012;
uniform float lean = 0.0;   // nudged by the tide so the sky leans with gravity
uniform float bloom = 0.0;  // flashes on completion

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_speed;
	float y = uv.y + (uv.x - 0.5) * (0.08 + lean);
	vec3 col = vec3(0.010, 0.006, 0.016);

	// Cloud band, stretched sideways so it streaks like the reference.
	float warp = fbm(vec2(uv.x * 1.5 - t, y * 6.0));
	float n = fbm(vec2(uv.x * 2.2 - t * 2.0, y * 16.0 + warp * 2.5));
	float band = smoothstep(0.30, 0.0, abs(y - 0.30));
	float lower = smoothstep(0.18, 0.38, y);
	vec3 pinkc = mix(vec3(0.85, 0.30, 0.52), vec3(0.92, 0.80, 0.95), smoothstep(0.55, 0.85, n) * lower);
	float cloud = smoothstep(0.38, 0.72, n) * band;
	vec3 darkc = vec3(0.16, 0.15, 0.20) * smoothstep(0.45, 0.8, fbm(vec2(uv.x * 3.0 - t * 1.4, y * 9.0)));
	col = mix(col, darkc, band * (1.0 - lower));
	col = mix(col, pinkc, cloud * mix(0.35, 1.0, lower));

	// Thin red horizon.
	col += vec3(0.6, 0.04, 0.07) * exp(-pow((y - 0.47) * 90.0, 2.0));
	col += vec3(0.30, 0.02, 0.05) * exp(-pow((y - 0.47) * 14.0, 2.0)) * 0.25;

	col += vec3(1.0, 0.7, 0.8) * bloom * band * 0.6;
	ALBEDO = col;
}
