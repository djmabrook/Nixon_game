shader_type spatial;
// The far ring: a skyline of invented glyph towers, kilometres out, kept crisp through
// the fog and tinted toward the horizon so it sits behind several sheets of air.
render_mode unshaded, cull_front, fog_disabled, depth_draw_opaque;

uniform sampler2D skyline : source_color, filter_nearest, repeat_enable;
uniform float repeats = 7.0;
uniform vec3 haze : source_color = vec3(0.96, 0.80, 0.76);
uniform float haze_amount = 0.35;
uniform float darkness = 0.0;

void fragment() {
	vec4 t = texture(skyline, vec2(UV.x * repeats, UV.y));
	if (t.a < 0.5) discard;
	vec3 c = mix(t.rgb, haze, haze_amount);
	ALBEDO = mix(c, vec3(0.03, 0.005, 0.01), darkness);
}
