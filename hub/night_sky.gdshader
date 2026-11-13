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

// Painted strips (art/tex): the night horizon, the dawn horizon, and the pale sun.
// Each strip wraps once around the horizon; its bottom row sits on the horizon line
// and its top row at strip_height (EYEDIR.y).
uniform sampler2D night_strip : source_color, filter_nearest, repeat_enable;
uniform sampler2D dawn_strip : source_color, filter_nearest, repeat_enable;
// Salmon home: the pink storm rolls in over the horizon strip.
uniform sampler2D storm_strip : source_color, filter_nearest, repeat_enable;
uniform float storm_amount = 0.0;
// Where the storm stands (radians, same as the landmark's angle) and how wide it spreads.
uniform float storm_angle = 5.236;
uniform float storm_spread = 1.1;
// How many times each strip repeats around the horizon.
uniform float strip_repeat = 2.0;
uniform sampler2D sun_tex : source_color, filter_nearest;
uniform float strip_height = 0.42;
// The dawn strip covers more of the sky: its top row reaches this EYEDIR.y.
uniform float dawn_strip_height = 0.8;
uniform float strip_amount = 1.0;
uniform float sun_size = 0.09;

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
	// The painted night strip. Drained it is only its light and dark, in bone haze.
	float az = atan(EYEDIR.z, EYEDIR.x);
	vec2 suv = vec2((az / TAU + 0.5) * strip_repeat, clamp(1.0 - y / strip_height, 0.001, 0.999));  // clamped: the strips repeat sideways only
	float strip_mask = step(0.0, y) * (1.0 - smoothstep(strip_height * 0.75, strip_height, y)) * strip_amount;
	vec3 nt = textureLod(night_strip, suv, 0.0).rgb;
	float nl = dot(nt, vec3(0.3, 0.59, 0.11));
	vec3 nt_drained = mix(zenith, drained_horizon, clamp(nl * 1.8, 0.0, 1.0));
	vec3 night_col = mix(nt_drained, nt, horizon_amount);
	vec3 storm_col = textureLod(storm_strip, suv, 0.0).rgb;
	float storm_d = abs(mod(az - storm_angle + PI, TAU) - PI);
	float storm_k = storm_amount * (1.0 - smoothstep(storm_spread * 0.6, storm_spread, storm_d));
	night_col = mix(night_col, storm_col, storm_k * step(0.12, dot(storm_col, vec3(0.3, 0.59, 0.11))));
	col = mix(col, night_col, strip_mask);

	// Dawn is the painted dawn strip stretched up the whole sky (its top row is the zenith),
	// with no smooth gradient, so it keeps its dither and its palette.
	vec2 duv = vec2(suv.x, clamp(1.0 - y / dawn_strip_height, 0.001, 0.999));
	vec3 day = textureLod(dawn_strip, duv, 0.0).rgb;
	vec3 sd = normalize(sun_dir);
	float sun_dot = max(dot(EYEDIR, sd), 0.0);
	// The pale sun sprite, flat-on to the eye.
	vec3 s_right = normalize(cross(vec3(0.0, 1.0, 0.0), sd));
	vec3 s_up = cross(sd, s_right);
	vec2 sp = vec2(dot(EYEDIR, s_right), -dot(EYEDIR, s_up)) / sun_size + 0.5;
	if (sun_dot > 0.0 && sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0) {
		vec4 st = textureLod(sun_tex, sp, 0.0);
		day = mix(day, st.rgb * 1.6, st.a);
	}
	col = mix(col, day, dawn);
	vec3 cell = floor(EYEDIR * 380.0);
	float s = hash(cell);
	if (s > star_density && y > 0.03 && dawn < 0.99) {
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * hash(cell + 1.0)) + s * 50.0);
		col += vec3(1.0, 0.8, 0.7) * tw * smoothstep(0.03, 0.2, y) * 1.4 * (1.0 - dawn);
	}
	COLOR = col;
}
