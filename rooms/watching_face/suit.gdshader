shader_type spatial;
// His suit: flat grey cloth with fine pinstripes, at the scale of a mountain range.

uniform vec4 cloth : source_color = vec4(0.36, 0.35, 0.42, 1.0);
uniform vec4 stripe : source_color = vec4(0.62, 0.6, 0.7, 1.0);
uniform float spacing = 9.0;
uniform float width = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float g = abs(fract(world_pos.x / spacing - 0.5) - 0.5) * spacing;
	float aa = fwidth(world_pos.x) * 0.75;
	float line = 1.0 - smoothstep(width - aa, width + aa, g);
	line *= 1.0 - smoothstep(0.2, 0.6, fwidth(world_pos.x / spacing));
	ALBEDO = mix(cloth.rgb, stripe.rgb, line * 0.6);
	ROUGHNESS = 0.95;
}
