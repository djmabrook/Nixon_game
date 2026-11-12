shader_type spatial;
// Things that exist only in firelight. Every fragment checks how much fire reaches it,
// and dissolves through an ordered 1-bit dither where the light thins out. A thin white
// rim burns along the edge of reality. Colossal shapes reveal part by part as a flame
// passes, so a torch carried past a drowned giant uncovers it a slice at a time.
//
// lakeside.gd writes the fires every frame. Per-look settings (tint, sink, climb) are plain
// uniforms: lakeside_look.gd keeps one material per look, shared by every mesh with that
// look, so a thousand stones cost a handful of materials (instance uniforms run out).

uniform vec4 tint : source_color = vec4(0.6, 0.6, 0.6, 1.0);
// > 0: the object reveals as a whole (by its origin) and rises this many metres out of
// the lake as it becomes real. Used for stepping stones, whose collision matches it.
uniform float sink = 0.0;
uniform float always_real = 0.0;
// climb = 1: ignore the fires; reality rises from the ground up to climb_y (world metres).
// invert = 1: the opposite, it exists until the climbing light reaches it.
uniform float climb = 0.0;
uniform float invert = 0.0;
uniform float climb_y = 0.0;
uniform float climb_band = 40.0;

// xyz = world position, w = reach in metres (0 = off).
uniform vec4 fire0;
uniform vec4 fire1;
uniform vec4 fire2;
uniform vec4 fire3;
uniform float rim_strength = 0.9;

varying vec3 wpos;
varying float origin_amount;

float reach(vec4 f, vec3 p) {
	if (f.w <= 0.0) return 0.0;
	float d = length(p.xz - f.xz);
	float band = max(1.2, f.w * 0.12);
	return 1.0 - smoothstep(f.w - band, f.w, d);
}

float amount(vec3 p) {
	return max(max(reach(fire0, p), reach(fire1, p)), max(reach(fire2, p), reach(fire3, p)));
}

float bayer4(vec2 c) {
	int x = int(mod(c.x, 4.0));
	int y = int(mod(c.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	origin_amount = max(amount(origin), always_real);
	if (sink > 0.0) {
		float s = length(MODEL_MATRIX[1].xyz);
		VERTEX.y -= (1.0 - origin_amount) * sink / max(s, 0.001);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = sink > 0.0 ? origin_amount : max(amount(wpos), always_real);
	if (climb > 0.0) {
		a = 1.0 - smoothstep(climb_y - climb_band, climb_y, wpos.y);
		a = mix(a, 1.0 - a, invert);
	}
	float th = bayer4(floor(FRAGCOORD.xy / 2.0));
	if (a < th) {
		discard;
	}
	ALBEDO = tint.rgb;
	ROUGHNESS = 1.0;
	float edge = 1.0 - smoothstep(0.0, 0.16, a - th);
	EMISSION = vec3(1.0) * edge * rim_strength * step(a, 0.995);
}
