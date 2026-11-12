shader_type sky;
// Night over the spiral beach: black overhead, a hot red band low on the horizon
// (the glow from the whirlpool in the reference), and a field of small stars.

uniform vec3 zenith : source_color = vec3(0.004, 0.0, 0.012);
uniform vec3 band : source_color = vec3(0.55, 0.09, 0.03);
uniform vec3 horizon : source_color = vec3(0.95, 0.32, 0.08);
uniform vec3 below : source_color = vec3(0.02, 0.01, 0.015);
uniform float star_density = 0.996;
// Story: 0 = drained horizon (bone haze), 1 = crimson home (the red band of the reference).
uniform float horizon_amount = 0.0;
uniform vec3 drained_band : source_color = vec3(0.16, 0.15, 0.13);
uniform vec3 drained_horizon : source_color = vec3(0.55, 0.52, 0.45);
// Dawn: 0 night, 1 sunrise. The sun rises where the palm shadows have always pointed.
uniform float dawn = 0.0;
uniform vec3 sun_dir = vec3(-0.7, 0.08, -0.7);
uniform vec3 dawn_zenith : source_color = vec3(0.25, 0.38, 0.62);
uniform vec3 dawn_horizon : source_color = vec3(1.0, 0.72, 0.45);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	float y = EYEDIR.y;
	vec3 b = mix(drained_band, band, horizon_amount);
	vec3 h = mix(drained_horizon, horizon, horizon_amount);
	vec3 col = mix(b, zenith, smoothstep(0.0, 0.35, y));
	col = mix(col, h, exp(-abs(y) * 40.0) * 0.8);
	if (y < 0.0) {
		col = mix(h * 0.4, below, smoothstep(0.0, 0.08, -y));
	}
	vec3 day = mix(dawn_horizon, dawn_zenith, smoothstep(0.0, 0.5, y));
	vec3 sd = normalize(sun_dir);
	float sun_dot = max(dot(EYEDIR, sd), 0.0);
	day += vec3(1.0, 0.8, 0.5) * pow(sun_dot, 12.0) * 0.6 + vec3(1.0, 0.95, 0.8) * smoothstep(0.9993, 0.9996, sun_dot) * 3.0;
	col = mix(col, day, dawn);
	vec3 cell = floor(EYEDIR * 380.0);
	float s = hash(cell);
	if (s > star_density && y > 0.03 && dawn < 0.99) {
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * hash(cell + 1.0)) + s * 50.0);
		col += vec3(1.0, 0.8, 0.7) * tw * smoothstep(0.03, 0.2, y) * 1.4 * (1.0 - dawn);
	}
	COLOR = col;
}
