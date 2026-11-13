shader_type spatial;
render_mode unshaded;
// Night sea around the beach: dark teal with slow shimmering bands near the shore.

uniform vec3 deep : source_color = vec3(0.02, 0.10, 0.12);
uniform vec3 shallow : source_color = vec3(0.05, 0.42, 0.42);
uniform vec3 glint : source_color = vec3(1.0, 0.45, 0.25);
uniform float shore_radius = 1000.0;
// Story palette: 0 = black sea, 1 = full teal. Each ink brings back a third.
uniform float color_amount = 0.0;
// Dawn: the sea fades into bone mist toward the horizon, so far silhouettes sit on mist.
uniform float dawn = 0.0;
uniform vec3 dawn_near : source_color = vec3(0.55, 0.42, 0.38);
uniform vec3 dawn_mist : source_color = vec3(0.93, 0.88, 0.80);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float r = length(p);
	// The beach and funnel sit inside the shore; the sea plane is only a ring around them.
	if (r < shore_radius - 10.0) {
		discard;
	}
	float t = clamp((r - shore_radius) / 900.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, sqrt(t));
	vec3 black_sea = mix(vec3(0.06, 0.06, 0.06), vec3(0.0), sqrt(t));
	col = mix(black_sea, col, color_amount);
	// Rings of foam/shimmer rolling toward the shore.
	float band = sin(r * 0.12 + TIME * 1.4 + sin(atan(p.y, p.x) * 5.0) * 0.6);
	col += mix(vec3(0.2), vec3(0.08, 0.2, 0.2), color_amount) * smoothstep(0.92, 1.0, band) * (1.0 - t);
	// The vortex's red glow catches the water.
	float sparkle = step(0.995, fract(sin(dot(floor(p * 1.0), vec2(12.9898, 78.233)) + floor(TIME * 2.0)) * 43758.5453));
	col += mix(vec3(0.5, 0.48, 0.42), glint, color_amount) * sparkle * 0.6 * (1.0 - t * 0.5) * (1.0 - dawn);
	col = mix(col, mix(dawn_near, dawn_mist, sqrt(t)), dawn);
	ALBEDO = col;
}
