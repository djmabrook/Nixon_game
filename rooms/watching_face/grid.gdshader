shader_type spatial;
render_mode unshaded;
// The endless purple grid. Lines sag toward the point under the face like a weight
// on a sheet, a vast shadow pools beneath it (you can read where it is without looking),
// and rings ripple out of it while it moves. Distances are in metres.

uniform vec4 base_color : source_color = vec4(0.02, 0.01, 0.05, 1.0);
uniform vec4 line_color : source_color = vec4(0.5, 0.32, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.92, 0.9, 0.86, 1.0);
uniform float cell = 4.0;
uniform float line_width = 0.07;
uniform vec3 face_pos = vec3(0.0, 0.0, 0.0);
uniform float face_radius = 45.0;
uniform float face_motion = 0.0;   // 0..1, how hard it is moving
uniform float stare = 0.0;         // 0..1, how locked-on it is
uniform float sag = 9.0;           // metres the lattice pulls toward the face

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float size, float w) {
	vec2 q = p / size;
	vec2 fw = fwidth(q);
	vec2 g = abs(fract(q - 0.5) - 0.5);
	vec2 l = 1.0 - smoothstep(vec2(w / size) - fw, vec2(w / size) + fw, g);
	// Fade lines out where they'd turn to moire in the distance.
	float fade = 1.0 - smoothstep(0.15, 0.5, max(fw.x, fw.y));
	return max(l.x, l.y) * fade;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 d = p - face_pos.xz;
	float r = length(d);
	float wr = face_radius * 1.8;
	float well = sag * exp(-r * r / (wr * wr));
	vec2 warped = p - normalize(d + 1e-4) * well;

	float minor = grid_line(warped, cell, line_width);
	float major = grid_line(warped, cell * 8.0, line_width * 3.0);

	float ripple = sin(r * 0.25 - TIME * 5.0) * 0.5 + 0.5;
	ripple *= face_motion * exp(-r / (face_radius * 4.0));

	vec3 lc = mix(line_color.rgb, hot_color.rgb, clamp(stare * 0.7 + ripple, 0.0, 1.0));
	float glow = max(minor * 0.5, major) * (0.75 + 0.8 * ripple);

	float shadow = (1.0 - smoothstep(face_radius * 0.4, face_radius * 1.3, r)) * 0.9;

	vec3 col = base_color.rgb + lc * glow * 1.4;
	col = mix(col, vec3(0.0), shadow);
	ALBEDO = col;
}
