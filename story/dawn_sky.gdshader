shader_type sky;
// Dawn over the whole land: indigo overhead, rose through the middle, a gold-ember band on
// the horizon that burns hottest under the sun, and the sun itself, a bone-white disc
// with a soft corona. `sun_dir` is where the sun stands (every palm shadow pointed there).

uniform vec3 sun_dir = vec3(0.0, 0.05, -1.0);
uniform float rise : hint_range(0.0, 1.0) = 0.0;  // 0 before dawn, 1 the sun fully up
uniform vec3 zenith : source_color = vec3(0.075, 0.06, 0.17);
uniform vec3 zenith_day : source_color = vec3(0.32, 0.36, 0.55);
uniform vec3 middle : source_color = vec3(0.62, 0.32, 0.40);
uniform vec3 horizon : source_color = vec3(1.0, 0.56, 0.30);
uniform vec3 horizon_far : source_color = vec3(0.55, 0.28, 0.32);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.80);
uniform vec3 ground : source_color = vec3(0.12, 0.06, 0.06);

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(sun_dir);
	float h = d.y;
	float toward = dot(normalize(vec2(d.x, d.z) + 1e-5), normalize(vec2(s.x, s.z) + 1e-5)) * 0.5 + 0.5;
	vec3 band = mix(horizon_far, horizon, pow(toward, 2.5));
	vec3 top = mix(zenith, zenith_day, rise * 0.6);
	vec3 col = mix(band, middle, smoothstep(0.0, 0.18, h));
	col = mix(col, top, smoothstep(0.12, 0.65, h));
	col *= mix(0.55, 1.0, rise);
	// The sun: a crisp disc and a broad glow; brighter as it clears the sea.
	float a = dot(d, s);
	float disc = smoothstep(0.99955, 0.9997, a);
	float glow = pow(max(a, 0.0), 220.0) * 1.4 + pow(max(a, 0.0), 12.0) * 0.35;
	col += sun_color * (disc * 6.0 + glow) * mix(0.4, 1.0, rise);
	// Below the horizon: the dark sea reflects a little of the band.
	if (h < 0.0) col = mix(band * 0.35, ground, smoothstep(0.0, -0.2, h));
	COLOR = col;
}
