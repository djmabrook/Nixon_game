shader_type spatial;
render_mode cull_disabled;
// The board. Deck: near-black with a thin stripe and a spiral inlay. Rim and belly: light that
// drifts through the spectrum (hue from the Board script, faster with flow).

uniform float hue = 0.0;
uniform float flow = 0.0;

varying vec3 part;

vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

void vertex() {
	part = COLOR.rgb;
}

void fragment() {
	vec2 p = UV - 0.5;
	float along = UV.y;
	vec3 shift = hsv(fract(hue + along * 0.35), 0.85, 1.0);
	// Deck: stripe down the middle, a spiral inlay, everything else soot.
	float stripe = 1.0 - smoothstep(0.035, 0.05, abs(p.x));
	float r = length(p * vec2(1.0, 0.35));
	float spiral = smoothstep(0.6, 0.9, sin(atan(p.y, p.x) * 2.0 + r * 60.0));
	vec3 deck = vec3(0.045, 0.04, 0.05) + shift * (stripe * 0.25 + spiral * 0.05 * (1.0 - stripe));
	ALBEDO = mix(vec3(0.02), deck, part.g);
	ROUGHNESS = 0.6;
	float rim = part.r;
	float belly = part.b;
	EMISSION = shift * (rim * (1.6 + 4.0 * flow) + belly * (2.0 + 5.0 * flow) + part.g * stripe * (0.4 + 1.6 * flow));
}
