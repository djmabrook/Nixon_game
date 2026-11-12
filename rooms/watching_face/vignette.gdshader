shader_type canvas_item;
// Darkens the screen edges, and closes in while the face stares (ink draining toward black).
// `flash` is a brief white-pink pop used for the reveal sting and the catch.

uniform float stare = 0.0;
uniform float flash = 0.0;
uniform vec4 tint : source_color = vec4(0.06, 0.02, 0.05, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 16.0 / 9.0;
	float v = smoothstep(0.35, 1.0, length(uv));
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	float a = v * (0.35 + 0.55 * stare * pulse);
	vec3 col = mix(vec3(0.0), tint.rgb, stare);
	col = mix(col, vec3(1.0, 0.85, 0.95), flash);
	COLOR = vec4(col, clamp(a + flash * 0.6, 0.0, 1.0));
}
