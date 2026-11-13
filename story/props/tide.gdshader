shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// The wash at the tideline. UV.x runs along the shore (metres), UV.y runs seaward (metres
// from the wake spot). Water lies seaward of `edge`; a ragged foam lace rides the edge;
// sand the water has just left stays dark and glossy up to `wet_edge`.

uniform float edge = 4.0;        // metres seaward of the wake spot where the water starts
uniform float wet_edge = 2.0;    // highest the water has reached lately
uniform float swell = 0.0;       // 0..1, a big wave: foam thickens, the lace runs further
uniform vec3 water_color : source_color = vec3(0.020, 0.018, 0.022);
uniform vec3 deep_color : source_color = vec3(0.004, 0.004, 0.008);
uniform vec3 foam_color : source_color = vec3(0.937, 0.902, 0.847);
uniform vec3 wet_color : source_color = vec3(0.07, 0.055, 0.05);
uniform vec3 shine_color : source_color = vec3(0.55, 0.42, 0.40);
uniform float fade_along = 160.0; // metres along the shore before the sheet fades out
uniform float fade_sea = 70.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float t = TIME;
	// The edge is ragged and slides sideways a little, like real swash.
	float rag = (fbm(vec2(u * 0.18 + t * 0.15, t * 0.07)) - 0.5) * (3.0 + 4.0 * swell)
			+ sin(u * 0.05 + t * 0.4) * 1.2;
	float e = edge + rag;
	float d = v - e;                // >0 in the water
	float along = 1.0 - smoothstep(fade_along * 0.6, fade_along, abs(u));
	float seaward = 1.0 - smoothstep(fade_sea * 0.5, fade_sea, v);

	vec3 col;
	float a;
	if (d > 0.0) {
		// Water: near the edge it is a thin black film, deeper out it darkens.
		col = mix(water_color, deep_color, smoothstep(0.0, 25.0, d));
		// Foam lace: a bright rim, then broken streaks behind it.
		float rim = 1.0 - smoothstep(0.0, 0.35 + 0.9 * swell, d);
		float streak = step(0.62 - 0.12 * swell, fbm(vec2(u * 0.6, (v - t * 0.6) * 0.9))) * (1.0 - smoothstep(0.5, 6.0 + 8.0 * swell, d));
		float bubbles = step(0.86, hash(floor(vec2(u, v) * 3.0) + floor(t * 6.0))) * (1.0 - smoothstep(0.0, 2.5, d));
		float foam = clamp(rim + streak * 0.8 + bubbles * 0.6, 0.0, 1.0);
		col = mix(col, foam_color, foam);
		a = mix(0.92, 1.0, foam) * along;
	} else {
		// Wet sand the water just left: dark with a moon sheen, drying from the top down.
		float wet = smoothstep(wet_edge + rag * 0.4, e, v);
		float shine = pow(fbm(vec2(u * 0.25, v * 1.6)), 3.0) * wet;
		col = mix(wet_color, shine_color, shine);
		a = wet * 0.85 * along;
	}
	ALBEDO = col;
	ALPHA = a * seaward;
}
