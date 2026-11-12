shader_type sky;
// Black void overhead, a band of pink storm cloud streaking around the horizon,
// a thin red horizon line, and the red moon: the Watcher's eye. "Down" points at it.

uniform vec2 tide_dir = vec2(0.0, -1.0);
uniform float tide_strength = 0.0;
uniform vec2 warn_dir = vec2(0.0, -1.0);
uniform float warn = 0.0;
uniform float bloom = 0.0;
uniform vec3 moon_dir = vec3(0.0, 0.06, -1.0);
uniform float moon_size = 0.075;   // angular radius, radians
uniform float moon_open = 1.0;     // 1 = eye wide open, 0 = shut
uniform float moon_glow = 0.5;
uniform vec3 horizon_fog : source_color = vec3(0.10, 0.03, 0.07);

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

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float t = TIME * 0.004;
	vec3 col = vec3(0.008, 0.005, 0.014);

	// Clouds projected onto a far ceiling, so they streak toward the horizon
	// with real perspective and never seam.
	vec2 cuv = d.xz / (max(h, 0.0) + 0.06);
	float warp = fbm(cuv * 0.35 + vec2(t * 8.0, 0.0));
	float n = fbm(cuv * vec2(0.5, 1.4) + vec2(t * 20.0, warp * 1.5));
	float band = smoothstep(0.55, 0.0, h) * smoothstep(-0.03, 0.01, h);
	float low = smoothstep(0.22, 0.02, h);
	vec3 pinkc = mix(vec3(0.82, 0.28, 0.50), vec3(0.95, 0.82, 0.96), smoothstep(0.55, 0.85, n) * low);
	vec3 darkc = vec3(0.14, 0.13, 0.18) * smoothstep(0.45, 0.8, fbm(cuv * 0.8 + vec2(t * 14.0, 3.0)));
	col = mix(col, darkc, band * (1.0 - low));
	col = mix(col, pinkc, smoothstep(0.42, 0.72, n) * band * mix(0.25, 1.0, low));

	// Red horizon line and glow.
	col += vec3(0.75, 0.05, 0.08) * exp(-pow(h * 140.0, 2.0));
	col += vec3(0.35, 0.03, 0.06) * exp(-abs(h) * 18.0) * 0.4;

	// The pull: a red flare on the horizon where down is.
	vec2 flat_dir = normalize(d.xz + vec2(1e-5));
	float toward = max(dot(flat_dir, tide_dir), 0.0);
	float flare = pow(toward, 10.0) * exp(-abs(h) * 6.0);
	col += vec3(1.0, 0.12, 0.2) * flare * tide_strength * 2.2;
	float wtoward = max(dot(flat_dir, warn_dir), 0.0);
	col += vec3(1.0, 0.2, 0.3) * pow(wtoward, 16.0) * exp(-abs(h) * 10.0) * warn * 1.2;

	// The moon. A red disc with a darker iris and pupil, lidded from above and below.
	vec3 md = normalize(moon_dir);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), md));
	vec3 up = cross(md, right);
	vec2 m = vec2(dot(d, right), dot(d, up)) / moon_size;
	float facing = step(0.0, dot(d, md));
	float r = length(m);
	float lid = max(moon_open, 0.001);
	float inside_lid = step(abs(m.y), lid * sqrt(max(1.0 - m.x * m.x, 0.0)));
	float disc = (1.0 - smoothstep(0.97, 1.0, r)) * facing;
	vec3 moon = vec3(0.95, 0.10, 0.12);
	moon = mix(moon, vec3(0.45, 0.02, 0.05), smoothstep(0.62, 0.58, r));
	moon = mix(moon, vec3(0.02, 0.0, 0.01), smoothstep(0.30, 0.26, r));
	moon += vec3(1.0, 0.8, 0.8) * smoothstep(0.12, 0.0, length(m - vec2(-0.18, 0.2))) * 0.8;
	// Shut lid reads as a dark red sliver.
	vec3 lidc = vec3(0.18, 0.02, 0.04);
	vec3 moon_col = mix(lidc, moon, inside_lid);
	// Halo around the eye.
	float halo = exp(-max(r - 1.0, 0.0) * 1.2) * facing * (1.0 - disc);
	col += vec3(1.0, 0.15, 0.2) * halo * moon_glow * 0.5 * smoothstep(0.0, 0.3, moon_open);
	// Only above the horizon: a setting moon sinks behind it.
	float above = smoothstep(-0.002, 0.004, h);
	col = mix(col, moon_col, disc * above);

	col += vec3(1.0, 0.7, 0.85) * bloom * band * 0.7;
	// Below the horizon fade to the fog colour so the floor melts into it.
	col = mix(col, horizon_fog, smoothstep(0.0, -0.08, h));
	COLOR = col;
}
