shader_type spatial;
// The fog that rises after the mend and closes over the pupil like an eyelid.
// An almond-shaped opening shrinks from both sides until it is shut.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, blend_mix;

uniform float presence = 0.0;
uniform float close = 0.0;
uniform float open_radius = 1750.0;
uniform float outer_radius = 5200.0;
uniform vec3 tint : source_color = vec3(0.95, 0.90, 0.86);
uniform vec3 shade : source_color = vec3(0.60, 0.36, 0.38);

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz / open_radius;
	// Almond opening: |z| < (1 - x^2) * (1 - close). Lids meet along the x axis.
	float half_h = max(1.0 - p.x * p.x, 0.0) * (1.0 - close) * 1.15;
	float billow = fbm(wp.xz * 0.0016 + vec2(TIME * 0.01, 0.0)) - 0.5;
	float inside = abs(p.y) - half_h + billow * 0.35;
	float lid_mask = smoothstep(-0.02, 0.12, inside);
	if (close >= 0.999) lid_mask = 1.0;
	float r = length(wp.xz);
	float edge_fade = 1.0 - smoothstep(outer_radius * 0.75, outer_radius, r);
	float body = 0.75 + 0.25 * fbm(wp.xz * 0.004 - vec2(0.0, TIME * 0.02));
	// A darker crease where the two lids meet.
	float seam = exp(-abs(p.y) * 30.0) * close;
	ALBEDO = mix(tint, shade, clamp(seam + (1.0 - body) * 0.6, 0.0, 1.0));
	ALPHA = lid_mask * edge_fade * body * presence;
}
