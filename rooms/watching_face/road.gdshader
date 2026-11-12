shader_type spatial;
render_mode unshaded;
// The tie road: diagonal regimental stripes in black, bone and ultraviolet, soft at the edges (UV.x runs across).

uniform vec4 band_a : source_color = vec4(0.3, 0.16, 0.75, 1.0);
uniform vec4 band_b : source_color = vec4(0.92, 0.9, 0.84, 1.0);
uniform vec4 band_c : source_color = vec4(0.03, 0.02, 0.05, 1.0);
uniform float band = 7.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = (world_pos.x + world_pos.z) / band;
	float k = fract(t / 3.0) * 3.0;
	vec3 col = k < 1.0 ? band_a.rgb : (k < 1.35 ? band_b.rgb : band_c.rgb);
	float edge = smoothstep(0.0, 0.02, UV.x) * smoothstep(1.0, 0.98, UV.x);
	ALBEDO = col;
	ALPHA = edge;
}
