shader_type spatial;
// One footprint from the drawn sheet: INSTANCE_CUSTOM.r picks the stage (0 fresh, 1 gone),
// so a print fades by losing dither dots rather than by going see-through.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D stages : source_color, filter_nearest;
uniform float stage_count = 6.0;

varying float fade;
varying vec4 tint;

void vertex() {
	fade = INSTANCE_CUSTOM.r;
	tint = COLOR;
}

void fragment() {
	float s = min(floor(fade * stage_count), stage_count - 1.0);
	vec4 t = texture(stages, vec2((UV.x + s) / stage_count, UV.y));
	if (t.a < 0.5 || tint.a < 0.01) {
		discard;
	}
	ALBEDO = tint.rgb;
}
