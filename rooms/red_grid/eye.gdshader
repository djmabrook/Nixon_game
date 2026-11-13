shader_type spatial;
// The sky ceiling: the Watcher's eye seen from underneath. A plane kilometres wide at the
// pupil's height. The pupil itself is a black disc mesh; this draws the target rings of the
// iris around it, the fibres, and a catchlight, fading out toward the horizon.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, blend_mix;

uniform float pupil_radius = 1500.0;
uniform float iris_radius = 3300.0;
uniform float fade_radius = 5600.0;
// 0 open, 1 the eye is shut (after the fog lid closes).
uniform float shut = 0.0;
// 0 lit sky behind, 1 the room is in eclipse. Shifts the rings from ink to embers.
uniform float eclipse = 0.0;

uniform vec3 crimson : source_color = vec3(0.78, 0.06, 0.18);
uniform vec3 deep : source_color = vec3(0.06, 0.004, 0.012);
uniform vec3 bone : source_color = vec3(0.94, 0.90, 0.85);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = wp.xz;
	float r = length(p);
	float a = atan(p.y, p.x);

	// A thin crescent of reflected light just inside the rim, like a wet eye.
	float rr = r / pupil_radius;
	float side = dot(normalize(p + vec2(0.001)), normalize(vec2(-0.6, 0.8)));
	float catchlight = smoothstep(0.86, 0.9, rr) * (1.0 - smoothstep(0.93, 0.96, rr)) * smoothstep(0.55, 0.9, side);
	float catch2 = 0.0;

	if (r < pupil_radius) {
		float c = max(catchlight, catch2) * (1.0 - shut);
		if (c < 0.01) discard;
		ALBEDO = bone * 0.9;
		ALPHA = c * 0.55;
	} else {
		float t = (r - pupil_radius) / (iris_radius - pupil_radius);
		// Target rings: two strong bands and a thin inner limbal ring.
		float bands = smoothstep(0.02, 0.0, abs(t - 0.04)) * 0.9;
		bands += smoothstep(0.09, 0.0, abs(t - 0.32)) * 0.8;
		bands += smoothstep(0.05, 0.0, abs(t - 0.7)) * 0.6;
		bands += smoothstep(0.03, 0.0, abs(t - 1.0)) * 1.0;
		// Fibres: thin radial spokes that flicker very slowly.
		float spokes = pow(abs(sin(a * 90.0 + hash(vec2(floor(a * 90.0 / PI), 1.0)) * 6.0)), 18.0);
		spokes *= smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.85, 1.0, t)) * 0.55;
		float body = (1.0 - smoothstep(0.0, 1.0, t)) * 0.55 + 0.25;
		float ink = clamp(bands + spokes, 0.0, 1.0);
		vec3 col = mix(deep, crimson, ink);
		col = mix(col, bone, smoothstep(0.03, 0.0, abs(t - 0.04)) * 0.5);
		float alpha = clamp(body + ink, 0.0, 1.0);
		alpha *= 1.0 - smoothstep(iris_radius, fade_radius, r);
		alpha *= 1.0 - shut * 0.92;
		ALBEDO = col * mix(1.0, 0.8, eclipse);
		ALPHA = alpha;
	}
}
