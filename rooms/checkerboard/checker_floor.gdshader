shader_type spatial;
render_mode diffuse_burley;
// World-space checkerboard that runs to the horizon without shimmering
// (box-filtered checker). Black tiles show flowing lines while the gravity tide pulls.

uniform vec3 pink : source_color = vec3(1.0, 0.56, 0.56);
uniform vec3 black : source_color = vec3(0.03, 0.018, 0.026);
uniform vec3 flow_color : source_color = vec3(1.0, 0.22, 0.32);
uniform float tile_size = 6.0;
uniform vec2 tide_dir = vec2(0.0, 0.0);
uniform float tide_strength = 0.0;
uniform float warn = 0.0;
uniform vec3 ripple_origin = vec3(0.0);
uniform float ripple_time = 1000.0;
uniform float ripple_speed = 28.0;
uniform float calm = 0.0;
uniform float footing = 0.0;
uniform vec3 trail[8];
instance uniform float use_hole = 0.0;
uniform vec2 hole_min = vec2(0.0);
uniform vec2 hole_max = vec2(0.0);

varying vec3 wpos;
varying vec3 wnorm;

// Analytically filtered checker: 0 = pink, 1 = black, greys in the distance.
float checker(vec2 p) {
	vec2 w = fwidth(p) + 1e-4;
	vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 + 0.5 * i.x * i.y;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wpos - wnorm * 0.002;
	if (use_hole > 0.5 && all(greaterThan(p.xz, hole_min)) && all(lessThan(p.xz, hole_max))) {
		discard;
	}
	vec2 q = p.xz / tile_size;
	float is_black = checker(q);
	vec2 local = fract(q);
	float edge = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
	float top = step(0.5, wnorm.y);
	// Bevel lines only close up, where they won't alias.
	float near = 1.0 - smoothstep(0.02, 0.12, fwidth(q.x));

	vec3 col = mix(pink, black, is_black);
	col *= mix(1.0, mix(0.82, 1.0, smoothstep(0.0, 0.03, edge)), near * top);
	col *= mix(0.55, 1.0, top);

	float along = dot(p.xz, tide_dir);
	float wave = sin(along * 0.6 - TIME * 9.0) * 0.5 + 0.5;
	float lines = smoothstep(0.75, 1.0, wave) * smoothstep(0.02, 0.06, edge);
	vec3 emit = flow_color * lines * tide_strength * is_black * near * 1.8;
	emit += flow_color * is_black * near * warn * (0.12 + 0.12 * sin(TIME * 24.0)) * smoothstep(0.02, 0.06, edge);

	float d = length(p.xz - ripple_origin.xz);
	float front = ripple_time * ripple_speed;
	float ring = exp(-pow((d - front) * 0.35, 2.0)) * exp(-ripple_time * 0.25);
	emit += vec3(1.0, 0.62, 0.72) * ring * 2.4;
	// Pink footing: salmon tiles bloom where he has walked.
	float foot = 0.0;
	for (int i = 0; i < 8; i++) {
		float fd = length(p.xz - trail[i].xz);
		foot = max(foot, (1.0 - smoothstep(tile_size * 0.4, tile_size * 1.4, fd)) * (1.0 - float(i) / 8.0));
	}
	emit += vec3(1.0, 0.62, 0.58) * foot * footing * (1.0 - is_black) * 0.9;
	emit += pink * (1.0 - is_black) * calm * (0.08 + 0.05 * sin(TIME * 1.2 - d * 0.08));

	ALBEDO = col;
	EMISSION = emit * top;
	ROUGHNESS = mix(0.6, 0.85, is_black);
	SPECULAR = 0.2;
}
