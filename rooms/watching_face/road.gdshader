shader_type spatial;
render_mode unshaded;
// The striped road: a tie unrolled toward the face. Diagonal bands, soft edges.

uniform vec4 band_a : source_color = vec4(0.42, 0.03, 0.12, 1.0);
uniform vec4 band_b : source_color = vec4(0.95, 0.72, 0.86, 1.0);
uniform vec4 band_c : source_color = vec4(0.05, 0.02, 0.12, 1.0);
uniform float band = 5.0;
uniform float half_width = 15.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = (world_pos.x + world_pos.z) / band;
	float k = fract(t / 3.0) * 3.0;
	vec3 col = k < 1.0 ? band_a.rgb : (k < 1.35 ? band_b.rgb : band_c.rgb);
	float edge = smoothstep(half_width, half_width - 0.6, abs(world_pos.x));
	ALBEDO = col;
	ALPHA = edge;
}
