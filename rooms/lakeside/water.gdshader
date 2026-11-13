shader_type spatial;
// Black lake. Nearly mirror-smooth, so the campfire paints moving red glints on it
// and the moon draws thin white lines. Placeholder until the shared dither pass lands.

uniform vec3 deep : source_color = vec3(0.012, 0.012, 0.016);
uniform vec3 fire_color : source_color = vec3(1.0, 0.15, 0.06);
// Up to four fires, set by lakeside.gd every frame: xyz = world position, w = reach (0 = off).
uniform vec4 fire0;
uniform vec4 fire1;
uniform vec4 fire2;
uniform vec4 fire3;

// Broken red bands of reflected firelight, rippling outward from each fire.
float fire_glint(vec4 f, vec2 p, float t) {
	if (f.w <= 0.0) return 0.0;
	float d = length(p - f.xz);
	float fall = 1.0 - smoothstep(0.0, min(f.w * 1.3, 40.0), d);
	float ring = sin(d * 8.0 - t * 2.6) * 0.5 + 0.5;
	float chop = sin(p.x * 13.0 + t * 2.0) * sin(p.y * 11.0 - t * 1.7);
	return fall * fall * step(0.62, ring * 0.65 + chop * 0.45);
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float t = TIME;
	vec3 n = vec3(
		sin(p.x * 3.1 + t * 1.3) * 0.07 + sin(p.y * 2.3 - t * 0.9) * 0.05 + sin((p.x + p.y) * 7.0 + t * 2.1) * 0.02,
		1.0,
		cos(p.y * 3.7 + t * 1.1) * 0.07 + cos(p.x * 1.9 + t * 0.7) * 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
	ALBEDO = deep;
	float g = max(max(fire_glint(fire0, p, t), fire_glint(fire1, p, t)), max(fire_glint(fire2, p, t), fire_glint(fire3, p, t)));
	// Sparse moon dashes far from any fire.
	float moon = step(0.985, sin(p.x * 0.9 + sin(p.y * 0.5 + t * 0.2) * 2.0)) * step(0.9, sin(p.y * 9.0 + t * 0.6)) * step(0.6, sin(p.x * 0.31 - p.y * 0.17));
	EMISSION = fire_color * g * 1.4 + vec3(0.55) * moon * (1.0 - g);
	ROUGHNESS = 0.06;
	SPECULAR = 1.0;
	METALLIC = 0.0;
}
