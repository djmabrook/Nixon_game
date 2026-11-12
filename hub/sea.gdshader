shader_type spatial;
render_mode unshaded;
// Night sea around the beach: dark teal with slow shimmering bands near the shore.

uniform vec3 deep : source_color = vec3(0.02, 0.10, 0.12);
uniform vec3 shallow : source_color = vec3(0.05, 0.42, 0.42);
uniform vec3 glint : source_color = vec3(1.0, 0.45, 0.25);
uniform float shore_radius = 23.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float r = length(p);
	// The beach and funnel sit inside the shore; the sea plane is only a ring around them.
	if (r < shore_radius - 1.5) {
		discard;
	}
	float t = clamp((r - shore_radius) / 18.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, sqrt(t));
	// Rings of foam/shimmer rolling toward the shore.
	float band = sin(r * 2.2 + TIME * 1.4 + sin(atan(p.y, p.x) * 5.0) * 0.6);
	col += vec3(0.08, 0.2, 0.2) * smoothstep(0.92, 1.0, band) * (1.0 - t);
	// The vortex's red glow catches the water.
	float sparkle = step(0.995, fract(sin(dot(floor(p * 3.0), vec2(12.9898, 78.233)) + floor(TIME * 2.0)) * 43758.5453));
	col += glint * sparkle * 0.6 * (1.0 - t * 0.5);
	ALBEDO = col;
}
