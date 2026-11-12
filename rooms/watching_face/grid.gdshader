shader_type spatial;
render_mode unshaded, cull_disabled;
// The purple grid. Lines bend toward the face like a weight on a sheet, a dark
// shadow sits under it (so you can read where it is even off screen), and rings
// ripple out of it while it moves.

uniform vec4 base_color : source_color = vec4(0.07, 0.015, 0.13, 1.0);
uniform vec4 line_color : source_color = vec4(0.78, 0.32, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.25, 0.55, 1.0);
uniform float cell = 2.0;
uniform float line_width = 0.06;
uniform vec3 face_pos = vec3(0.0, 0.0, 0.0);
uniform float face_motion = 0.0;   // 0..1, how hard it is moving
uniform float stare = 0.0;         // 0..1, how locked-on it is
uniform float sag = 1.6;           // how far lines pull toward the face
uniform vec2 half_extent = vec2(13.0, 22.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float w) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	vec2 aa = fwidth(p) * 0.75;
	vec2 l = 1.0 - smoothstep(vec2(w) - aa, vec2(w) + aa, g);
	return max(l.x, l.y);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 d = p - face_pos.xz;
	float r = length(d);
	// Gravity well: pull the lattice toward the point under the face.
	float well = sag * exp(-r * r / 40.0);
	vec2 warped = p - normalize(d + 1e-4) * well;

	float lines = grid_line(warped, line_width);
	// Brighter major lines every 4 cells.
	vec2 gm = abs(fract(warped / (cell * 4.0) - 0.5) - 0.5) * cell * 4.0;
	float major = 1.0 - smoothstep(line_width * 1.6, line_width * 1.6 + fwidth(p.x), min(gm.x, gm.y));

	// Ripples while the face moves.
	float ripple = sin(r * 1.4 - TIME * 7.0) * 0.5 + 0.5;
	ripple *= face_motion * exp(-r / 9.0);

	vec3 lc = mix(line_color.rgb, hot_color.rgb, clamp(stare * 0.8 + ripple, 0.0, 1.0));
	float glow = lines * (0.55 + 0.45 * major) * (0.7 + 0.6 * ripple);

	// Soft shadow under the face.
	float shadow = 1.0 - smoothstep(1.5, 4.2, r) * 1.0;
	shadow *= 0.85;

	// Glowing boundary and darkness past it.
	vec2 edge = half_extent - abs(p);
	float rim = 1.0 - smoothstep(0.0, 0.25, min(edge.x, edge.y));

	vec3 col = base_color.rgb + lc * glow;
	col = mix(col, vec3(0.0), shadow);
	col += hot_color.rgb * rim * 0.8;
	ALBEDO = col;
}
