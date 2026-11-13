shader_type spatial;
// The Stray's skin. Bone face, black rim, and three tricks:
//  - ink_flash: the arrow's tip borrows the room's ink for a beat (a cursor over a link)
//  - face_off: the face blinks to black, like a cursor blinking
//  - vanish: an ordered-dither dissolve, so it glitches out and back in like a lost pointer
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.937, 0.902, 0.847);
uniform vec3 dark_color : source_color = vec3(0.051, 0.043, 0.039);
uniform vec4 ink : source_color = vec4(0.0);
uniform float ink_flash : hint_range(0.0, 1.0) = 0.0;
uniform float face_off : hint_range(0.0, 1.0) = 0.0;
uniform float vanish : hint_range(0.0, 1.0) = 0.0;
uniform bool is_face = false;
// It is from the frame, not the world: mostly self-lit, so its bone face reads even with
// the sun behind it. 0 = lit like a prop, 1 = flat like a cursor on a screen.
uniform float self_lit : hint_range(0.0, 1.0) = 0.7;
// Arrow tip in the model's own space (the GLB is authored flat in XY, tail tip at the origin).
uniform vec2 tip = vec2(-0.42, 0.551);
uniform float tip_radius = 0.2;

varying vec3 local_pos;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	if (vanish > 0.0 && bayer4(FRAGCOORD.xy) < vanish) {
		discard;
	}
	vec3 c = base_color;
	if (is_face) {
		float near_tip = step(distance(local_pos.xy, tip), tip_radius);
		c = mix(c, ink.rgb, near_tip * ink_flash * ink.a);
		c = mix(c, dark_color, face_off);
	}
	ALBEDO = c * (1.0 - self_lit);
	EMISSION = c * self_lit;
	ROUGHNESS = 1.0;
}
