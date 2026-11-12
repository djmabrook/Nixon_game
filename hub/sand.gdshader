shader_type spatial;
// Night sand around the vortex. Fine ridges spiral into the center and flow inward;
// one wider groove (an "arm") per room spirals to that room's spot on the pit's rim.
// Toward the center the sand turns into the dark slate of the vortex itself.
// Placeholder look: swap sand_tex in when the art lands, the spiral math stays.

#define MAX_ARMS 16

uniform vec3 sand_light : source_color = vec3(0.93, 0.62, 0.45);
uniform vec3 sand_dark : source_color = vec3(0.55, 0.30, 0.22);
uniform vec3 vortex_light : source_color = vec3(0.47, 0.48, 0.60);
uniform vec3 vortex_dark : source_color = vec3(0.10, 0.10, 0.16);
uniform vec3 groove_color : source_color = vec3(0.30, 0.15, 0.13);

// Ridges: how many spiral lines there are, and how far apart they sit (world units).
uniform float ridge_starts = 36.0;
uniform float ridge_spacing = 0.42;
uniform float flow_speed = 0.6;

// The vortex: radius where sand turns slate, and the pit's rim.
uniform float vortex_radius = 6.5;
uniform float pit_radius = 1.6;

// Arms. arm_angle(r) = arm_offset + i * TAU / arm_count + arm_winding * (r - pit_radius)
uniform int arm_count = 0;
uniform float arm_offset = 0.0;
uniform float arm_winding = 0.32;
uniform float arm_width = 0.9;
uniform vec4 arm_colors[MAX_ARMS];     // rgb = room tint, a = 1 open / 0 completed
uniform float arm_glow = 0.9;
// Which arm the player is walking on (-1 = none). Brightens that arm.
uniform int focus_arm = -1;
uniform float focus_amount = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = world_pos.xz;
	float r = max(length(p), 0.0001);
	float theta = atan(p.y, p.x);

	// Ridges: a log spiral, drifting inward over time.
	float ridge_phase = theta * ridge_starts + r * TAU / ridge_spacing + TIME * flow_speed * TAU / ridge_spacing;
	float ridge = 0.5 + 0.5 * sin(ridge_phase);
	ridge = smoothstep(0.25, 0.75, ridge);

	float vortex_t = 1.0 - smoothstep(pit_radius, vortex_radius, r);
	vec3 light_col = mix(sand_light, vortex_light, vortex_t);
	vec3 dark_col = mix(sand_dark, vortex_dark, vortex_t);
	vec3 col = mix(dark_col, light_col, ridge);

	// Grain so flat areas are never flat once the dither pass quantises them.
	col *= 0.92 + 0.16 * hash(floor(p * 10.0));

	// Arms: grooves spiralling to each room's spot on the rim.
	vec3 emit = vec3(0.0);
	if (arm_count > 0) {
		float n = float(arm_count);
		float u = (theta - arm_offset - arm_winding * (r - pit_radius)) * n / TAU;
		float nearest = floor(u + 0.5);
		float d = abs(u - nearest) * TAU / n * r;   // arc distance to the groove centre
		int idx = int(mod(nearest, n));
		float groove = 1.0 - smoothstep(arm_width * 0.5, arm_width * 0.5 + 0.12, d);
		float fade_in = smoothstep(pit_radius, pit_radius + 0.6, r) * (1.0 - smoothstep(19.0, 22.0, r));
		groove *= fade_in;
		vec4 tint = arm_colors[idx];
		float open = tint.a;
		// Pulses run down each open groove toward the pit.
		float pulse = 0.5 + 0.5 * sin(r * 1.6 + TIME * 3.0);
		float focus = (idx == focus_arm) ? focus_amount : 0.0;
		col = mix(col, groove_color * mix(0.6, 1.0, ridge), groove * 0.85);
		emit += tint.rgb * groove * open * arm_glow * (0.35 + 0.65 * pulse) * (1.0 + 1.5 * focus);
	}

	// The pit: near black, a tight swirl and a hot rim.
	float pit = 1.0 - smoothstep(pit_radius - 0.2, pit_radius + 0.15, r);
	float swirl = 0.5 + 0.5 * sin(theta * 3.0 + log(r) * 8.0 + TIME * 4.0);
	col = mix(col, vortex_dark * (0.3 + 0.4 * swirl), pit);
	float rim = exp(-pow((r - pit_radius) / 0.25, 2.0));
	emit += vec3(1.0, 0.25, 0.08) * rim * (0.6 + 0.3 * sin(TIME * 2.0));

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = emit;
}
