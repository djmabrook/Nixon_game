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
uniform float ridge_starts = 1200.0;
uniform float ridge_spacing = 3.5;
uniform float flow_speed = 0.25;

// The vortex: radius where sand turns slate, and the pit's rim.
uniform float vortex_radius = 500.0;
uniform float pit_radius = 40.0;
// The dune ridge glows faintly, like the reference's halo.
uniform float crest_radius = 500.0;

// Arms. arm_angle(r) = arm_offset + i * TAU / arm_count + arm_winding * (r - pit_radius)
uniform int arm_count = 0;
uniform float arm_offset = 0.0;
uniform float arm_winding = 0.0102;
uniform float arm_width = 14.0;
uniform float arm_outer_radius = 905.0;
// Per arm: rgb = the room's ink. a = how far the ink has filled the groove, 0 (dry: only a
// faint dotted pulse runs inward) to 1 (full and steady to the beacon); in between, the
// ink has filled it from the pit up to that fraction (the fill animation on return).
uniform vec4 arm_colors[MAX_ARMS];
// Per arm: how far out (m) the groove is drawn at all. A locked groove is 0 until it uncoils.
uniform float arm_reach[MAX_ARMS];
uniform float arm_glow = 0.85;
// Which arm the player is walking on (-1 = none). Brightens that arm.
uniform int focus_arm = -1;
uniform float focus_amount = 0.0;

// Story palette. 0 = drained (black, bone, sand), 1 = full colour (the reference still).
uniform float color_amount = 0.0;
uniform vec3 bone_light : source_color = vec3(0.86, 0.80, 0.68);
uniform vec3 bone_dark : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 drained_vortex_light : source_color = vec3(0.30, 0.29, 0.28);
uniform vec3 drained_vortex_dark : source_color = vec3(0.03, 0.03, 0.03);
// The pit's rim glow (rgb, a = strength). Unlit until ember comes home.
uniform vec4 rim_color : source_color = vec4(1.0, 0.25, 0.08, 0.0);
// With three inks home, rings of ink circle the pit and it reads as an eye.
uniform vec4 eye_rings[3];
uniform float eye_ring_width = 3.0;
// The eye's lid: 0 open, 1 shut (the blink).
uniform float lid = 0.0;

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
	// Fade ridges to flat where they get finer than a few pixels, so the distance never shimmers.
	float ridge_w = fwidth(ridge_phase);
	ridge = mix(ridge, 0.5, smoothstep(0.8, 2.5, ridge_w));
	// Fine ripples between the big ridges, visible only up close (at his feet).
	float fine = 0.5 + 0.5 * sin(ridge_phase * 5.0 + sin(theta * 40.0) * 2.0);
	ridge = mix(ridge, ridge * (0.7 + 0.3 * fine), 1.0 - smoothstep(0.3, 1.2, ridge_w * 5.0));

	float vortex_t = 1.0 - smoothstep(pit_radius, vortex_radius, r);
	vec3 s_light = mix(bone_light, sand_light, color_amount);
	vec3 s_dark = mix(bone_dark, sand_dark, color_amount);
	vec3 v_light = mix(drained_vortex_light, vortex_light, color_amount);
	vec3 v_dark = mix(drained_vortex_dark, vortex_dark, color_amount);
	vec3 light_col = mix(s_light, v_light, vortex_t);
	vec3 dark_col = mix(s_dark, v_dark, vortex_t);
	vec3 col = mix(dark_col, light_col, ridge);

	// Grain so flat areas are never flat once the dither pass quantises them.
	col *= 0.92 + 0.16 * hash(floor(p * 2.0));

	// Arms: grooves spiralling to each room's spot on the rim.
	vec3 emit = vec3(0.0);
	if (arm_count > 0) {
		float n = float(arm_count);
		float u = (theta - arm_offset - arm_winding * (r - pit_radius)) * n / TAU;
		float nearest = floor(u + 0.5);
		float d = abs(u - nearest) * TAU / n * r;   // arc distance to the groove centre
		int idx = int(mod(nearest, n));
		float groove = 1.0 - smoothstep(arm_width * 0.5, arm_width * 0.5 + 2.0, d);
		float fade_in = smoothstep(pit_radius, pit_radius + 6.0, r) * (1.0 - smoothstep(arm_outer_radius - 6.0, arm_outer_radius, r));
		groove *= fade_in;
		groove *= 1.0 - smoothstep(arm_reach[idx] - 10.0, arm_reach[idx], r);
		vec4 tint = arm_colors[idx];
		float full_to = pit_radius + tint.a * (arm_outer_radius - pit_radius);
		float full = tint.a >= 0.999 ? 1.0 : 1.0 - smoothstep(full_to - 8.0, full_to, r);
		// Dry: a faint dotted pulse of the room's ink running inward.
		float dash = smoothstep(0.62, 0.7, fract(r / 22.0 + TIME * 0.35)) * (1.0 - smoothstep(0.85, 0.93, fract(r / 22.0 + TIME * 0.35)));
		float dry = 0.18 * dash;
		// Full: steady, with a slow shimmer.
		float wet = 0.9 + 0.1 * sin(r * 0.05 - TIME * 1.5);
		float focus = (idx == focus_arm) ? focus_amount : 0.0;
		col = mix(col, groove_color * mix(0.6, 1.0, ridge) * mix(0.5, 1.0, color_amount), groove * 0.85);
		col = mix(col, tint.rgb * 0.35, groove * full * 0.6);
		emit += tint.rgb * groove * arm_glow * mix(dry, wet, full) * (1.0 + 0.6 * focus);
	}

	// The eye: rings of ink around the pit once all three inks are home.
	for (int k = 0; k < 3; k++) {
		vec4 ring = eye_rings[k];
		float rr = pit_radius + 4.0 + float(k) * (eye_ring_width * 2.2);
		float band = 1.0 - smoothstep(eye_ring_width * 0.5, eye_ring_width * 0.5 + 1.0, abs(r - rr));
		col = mix(col, ring.rgb * 0.4, band * ring.a);
		emit += ring.rgb * band * ring.a * 1.4;
	}

	// The pit: near black, a tight swirl and a hot rim.
	float pit = 1.0 - smoothstep(pit_radius - 2.0, pit_radius + 1.5, r);
	float swirl = 0.5 + 0.5 * sin(theta * 5.0 + log(r) * 9.0 + TIME * 3.0);
	col = mix(col, vortex_dark * (0.3 + 0.4 * swirl), pit);
	float rim = exp(-pow((r - pit_radius) / 4.0, 2.0));
	emit += rim_color.rgb * rim_color.a * rim * (0.9 + 0.4 * sin(TIME * 2.0));
	float crest = exp(-pow((r - crest_radius) / 12.0, 2.0));
	emit += rim_color.rgb * rim_color.a * crest * 0.25 * ridge;

	// The blink: a lid closing top and bottom over the eye (pit plus rings).
	float eye_r = pit_radius + 4.0 + 3.0 * eye_ring_width * 2.2;
	if (lid > 0.0 && r < eye_r + 2.0) {
		float shut = step(1.0 - lid, abs(p.y) / eye_r);
		col = mix(col, vec3(0.0), shut);
		emit *= 1.0 - shut;
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = emit;
}
