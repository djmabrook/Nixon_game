shader_type spatial;
// The crimson wire plain. It sags under the Watcher's pupil, darkens inside the
// pupil's shadow, and is cut wherever a hole has been laid on it.
// Lines are drawn per pixel from world XZ and fade into their average colour with
// distance, so a 640x360 frame shows a clean grid instead of moire.
// The floor is lit (it takes the little man's late shadow); the wires are emission.
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// Shape of the sag. Keep in step with red_grid.gd (sag_height()).
uniform float sag_depth = 220.0;
uniform float sag_radius = 800.0;
// Square cut-out for the far plane, so it doesn't overlap the near mesh.
uniform float inner_cut = 0.0;

uniform float cell = 8.0;
uniform float major_every = 8.0;

// The pupil's shadow on the plain: full dark inside shadow_inner, full light past shadow_outer.
uniform float shadow_inner = 1050.0;
uniform float shadow_outer = 1900.0;
// 0..1 as the fog lid closes over the pupil and light comes back.
uniform float lid = 0.0;

// The pressed circle at the bottom, bounded by the ring of sockets.
uniform float plug_radius = 36.0;
uniform float plug_gone = 0.0;
uniform float cut_flash = 0.0;
uniform float socket_filled[6];
uniform float socket_angle0 = 0.0;

// Holes: xz, radius, kind (0 none, 1 loose: wires drawn toward it, 2 laid: grid cut away).
uniform vec4 holes[12];

// A ring wave across the wires (a disc laid, the plug falling).
uniform vec2 wave_pos = vec2(0.0);
uniform float wave_age = 100.0;
uniform float wave_strength = 0.0;

uniform vec3 floor_lit : source_color = vec3(0.36, 0.035, 0.07);
uniform vec3 floor_dark : source_color = vec3(0.035, 0.006, 0.011);
uniform vec3 wire : source_color = vec3(0.86, 0.07, 0.19);
uniform vec3 bone : source_color = vec3(0.94, 0.90, 0.85);

varying vec3 wp;

float sag_at(vec2 p) {
	float t = clamp(length(p) / sag_radius, 0.0, 1.0);
	float s = 1.0 - t * t;
	return -sag_depth * s * s;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y += sag_at(w.xz);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	wp = w;
}

// Anti-aliased grid lines: 1 on a line, 0 between. `px` is the width in screen pixels.
float grid_lines(vec2 p, float px, out float far_fade) {
	vec2 fw = max(fwidth(p), vec2(1e-5));
	vec2 d = abs(fract(p - 0.5) - 0.5) / fw;
	float l = 1.0 - clamp(min(d.x, d.y) - (px - 1.0) * 0.5, 0.0, 1.0);
	float f = max(fw.x, fw.y);
	far_fade = 1.0 - smoothstep(0.18, 0.55, f);
	float avg = clamp(px * f, 0.0, 1.0) * 0.9;
	return mix(avg, l, far_fade);
}

void fragment() {
	vec2 p = wp.xz;
	if (inner_cut > 0.0 && max(abs(p.x), abs(p.y)) < inner_cut) {
		discard;
	}
	float r = length(p);
	if (plug_gone > 0.5 && r < plug_radius) {
		discard;
	}

	float glow_boost = 0.0;
	for (int i = 0; i < 12; i++) {
		vec4 h = holes[i];
		if (h.w < 0.5) continue;
		float d = length(p - h.xy);
		if (h.w > 1.5) {
			if (d < h.z) discard;
			// A laid hole drinks the light around its lip.
			glow_boost += 0.6 * (1.0 - smoothstep(h.z, h.z + 3.0, d));
		} else {
			// A loose hole: ripples run inward to it, so it can be found from afar.
			float rings = pow(0.5 + 0.5 * sin((d + TIME * 7.0) * 0.55), 10.0);
			glow_boost += rings * 2.2 * (1.0 - smoothstep(h.z, h.z + 26.0, d));
		}
	}

	float fade_minor;
	float fade_major;
	float fade_fine;
	float fine = grid_lines(p / (cell * 0.25), 1.0, fade_fine) * fade_fine;
	float minor = grid_lines(p / cell, 1.5, fade_minor);
	float major = grid_lines(p / (cell * major_every), 2.0, fade_major);

	// Light: the pupil's shadow. The fog lid gives most of it back.
	float lit = smoothstep(shadow_inner, shadow_outer, r);
	lit = mix(lit, 1.0, lid * 0.8);
	float dark = 1.0 - lit;

	// Pulses run down the wires into the bottom of the sag: the stare pressing.
	float in_sag = 1.0 - smoothstep(sag_radius * 0.6, sag_radius * 1.4, r);
	float pulse = pow(0.5 + 0.5 * sin((r + TIME * 55.0) * 0.012), 16.0) * in_sag * (1.0 - lid);

	// One-off ring wave.
	float wd = length(p - wave_pos);
	float front = wave_age * 120.0;
	float wave = exp(-abs(wd - front) * 0.08) * wave_strength * exp(-wave_age * 0.6);

	// The bowl's walls catch the stare: their wires stay brighter in the dark.
	float wall = in_sag * (1.0 - lid) * 0.35;
	float wire_e = mix(0.55 + wall, 1.0, lit) + pulse * 1.4 + glow_boost + wave * 2.5;
	vec3 col_minor = wire * wire_e * 0.75;
	vec3 col_major = mix(wire, bone, 0.25 * lit + 0.4 * pulse) * wire_e * 1.15;

	// The crease around the pressed circle and the six sockets on it.
	float creasew = max(fwidth(r), 1e-4);
	float crease = 1.0 - clamp(abs(r - plug_radius) / creasew - 0.5, 0.0, 1.0);
	float ang = atan(p.y, p.x) - socket_angle0;
	ang = mod(ang, TAU);
	float seg = TAU / 6.0;
	int k = int(floor(ang / seg));
	float both = socket_filled[k % 6] * socket_filled[(k + 1) % 6];
	float crease_e = (0.45 + 0.35 * sin(TIME * 2.0)) * (1.0 - plug_gone) + both * 3.0 + cut_flash * 6.0;
	vec3 crease_col = mix(wire, bone, clamp(both * 0.7 + cut_flash, 0.0, 1.0)) * crease_e;

	vec3 em = col_minor * fine * 0.55;
	em = max(em, col_minor * minor);
	em = max(em, col_major * major);
	em = max(em, crease_col * crease);

	ALBEDO = mix(floor_dark, floor_lit, lit) * (1.0 + glow_boost * 0.15);
	// Unlit wires stay in the dark; the floor itself is lit by the sun so it takes his shadow.
	EMISSION = em;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Flat light, no falloff with angle: a printed plain. ATTENUATION carries the shadow.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
