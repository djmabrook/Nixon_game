shader_type sky;
// Night over the spiral beach: black overhead, a hot red band low on the horizon
// (the glow from the whirlpool in the reference), and a field of small stars.

uniform vec3 zenith : source_color = vec3(0.004, 0.0, 0.012);
uniform vec3 band : source_color = vec3(0.55, 0.09, 0.03);
uniform vec3 horizon : source_color = vec3(0.95, 0.32, 0.08);
uniform vec3 below : source_color = vec3(0.02, 0.01, 0.015);
uniform float star_density = 0.996;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	float y = EYEDIR.y;
	vec3 col = mix(band, zenith, smoothstep(0.0, 0.35, y));
	col = mix(col, horizon, exp(-abs(y) * 40.0) * 0.8);
	if (y < 0.0) {
		col = mix(horizon * 0.4, below, smoothstep(0.0, 0.08, -y));
	}
	vec3 cell = floor(EYEDIR * 380.0);
	float s = hash(cell);
	if (s > star_density && y > 0.03) {
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * hash(cell + 1.0)) + s * 50.0);
		col += vec3(1.0, 0.8, 0.7) * tw * smoothstep(0.03, 0.2, y) * 1.4;
	}
	COLOR = col;
}
