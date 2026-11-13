shader_type canvas_item;
// The Negative: the world seen from inside the Watcher's stare. Colours invert and the
// shadows go solid, a flat sheet of bone where the dark was.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec4 bone : source_color = vec4(0.93, 0.9, 0.84, 1.0);
uniform vec4 ink : source_color = vec4(0.08, 0.02, 0.06, 1.0);

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 inv = 1.0 - c;
	vec3 col = lum < 0.18 ? bone.rgb : mix(ink.rgb, inv, smoothstep(0.18, 0.7, lum));
	COLOR = vec4(col, 1.0);
}
