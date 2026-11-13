shader_type spatial;
// A painted cut-out standing on the horizon (art/tex/horizon_*.png). Unshaded and outside
// the fog, so it reads as a flat silhouette at any distance. Drained it shows only its
// light and dark in bone; the Watcher's red eyes keep their colour unless eyes_dim says so.
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float color_amount = 1.0;
uniform vec3 drained_dark : source_color = vec3(0.02, 0.02, 0.02);
uniform vec3 drained_light : source_color = vec3(0.62, 0.58, 0.5);
uniform vec3 haze : source_color = vec3(0.32, 0.07, 0.06);
uniform float haze_amount = 0.12;
// 1 = red pixels keep their colour when drained (only the Watcher's eyes do).
uniform float keep_red = 0.0;
// 1 = the red pixels (the Watcher's eyes) go dark.
uniform float eyes_dim = 0.0;
// Lit things (the beacon's fire) can glow through the dither.
uniform float glow = 1.0;

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	vec3 col = c.rgb;
	float red = step(0.3, col.r - max(col.g, col.b) * 1.2) * step(0.45, col.r) * keep_red;
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 drained = mix(drained_dark, drained_light, smoothstep(0.05, 0.8, l));
	col = mix(drained, col, max(color_amount, red * (1.0 - eyes_dim)));
	col = mix(col, vec3(0.03, 0.01, 0.015), red * eyes_dim);
	col = mix(col, haze, haze_amount * (1.0 - red));
	ALBEDO = col * mix(1.0, glow, red);
}
