shader_type spatial;
// Fog pouring down the sag. Strips follow the slope; UV.y runs from the rim (0) to the
// bottom (1). `rise` reverses the flow and lifts the fog away when the grid springs level.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D streaks : source_color, filter_nearest, repeat_enable;
uniform vec3 tint : source_color = vec3(0.94, 0.88, 0.84);
uniform float density = 0.5;
uniform float speed = 0.05;
uniform float rise = 0.0;
uniform float light = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float flow = TIME * speed * (1.0 - 2.0 * rise);
	vec2 uv = vec2(UV.x * 3.0 + seed, UV.y * 6.0 - flow * 6.0);
	float s = texture(streaks, uv).a;
	float n = noise(vec2(UV.x * 7.0 + seed * 3.0, UV.y * 9.0 - flow * 9.0));
	float n2 = noise(vec2(UV.x * 19.0 - seed, UV.y * 22.0 - flow * 15.0));
	float body = s * 0.55 + n * 0.55 + n2 * 0.25;
	float side = sin(UV.x * PI);
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float a = clamp(body * side * side * ends * density, 0.0, 1.0);
	a *= 1.0 - rise;
	ALBEDO = tint * (0.35 + 0.65 * light);
	ALPHA = a;
}
