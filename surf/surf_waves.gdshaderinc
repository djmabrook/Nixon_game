// Moving swells for a SurfTerrain. Mirrors SurfWave.height() and SurfTerrain.moving_height()
// exactly; SurfTerrain feeds these uniforms every frame (surf_time, the packed waves, calm spots).
//
//   #include "res://surf/surf_waves.gdshaderinc"
//   void vertex() { surf_displace(VERTEX, NORMAL, MODEL_MATRIX); }

#define SURF_MAX_WAVES 8
#define SURF_MAX_CALM 32

uniform float surf_time = 0.0;
uniform int surf_wave_count = 0;
uniform vec4 surf_wa[SURF_MAX_WAVES];   // kind, center x, center z, arms
uniform vec4 surf_wb[SURF_MAX_WAVES];   // wavelength, speed, amplitude, sharpness
uniform vec4 surf_wc[SURF_MAX_WAVES];   // window: inner start, inner full, outer full, outer end
uniform vec4 surf_wd[SURF_MAX_WAVES];   // direction x, direction z, phase, -
uniform int surf_calm_count = 0;
uniform vec4 surf_calm[SURF_MAX_CALM];  // x, z, radius, -

float surf_wave(int i, vec2 xz, float t) {
	vec4 a = surf_wa[i];
	vec4 b = surf_wb[i];
	vec4 c = surf_wc[i];
	vec4 d = surf_wd[i];
	vec2 rel = xz - a.yz;
	float r = length(rel);
	float w = 1.0;
	if (c.y > 0.0) { w *= smoothstep(c.x, c.y, r); }
	if (c.w > 0.0) { w *= 1.0 - smoothstep(c.z, c.w, r); }
	if (w <= 0.0) { return 0.0; }
	float k = 6.28318530718 / max(b.x, 0.01);
	float ph;
	if (a.x > 0.5) {
		ph = k * r - k * b.y * t + a.w * atan(rel.y, rel.x) + d.z;
	} else {
		ph = k * dot(xz, d.xy) - k * b.y * t + d.z;
	}
	float u = 0.5 + 0.5 * sin(ph);
	float v = pow(u, 1.0 + 3.0 * b.w);
	return b.z * (2.0 * v - 1.0) * w;
}

float surf_calm_at(vec2 xz) {
	float m = 1.0;
	for (int i = 0; i < SURF_MAX_CALM; i++) {
		if (i >= surf_calm_count) { break; }
		vec4 s = surf_calm[i];
		m = min(m, smoothstep(s.z, s.z * 1.8, length(xz - s.xy)));
	}
	return m;
}

float surf_moving(vec2 xz) {
	float h = 0.0;
	for (int i = 0; i < SURF_MAX_WAVES; i++) {
		if (i >= surf_wave_count) { break; }
		h += surf_wave(i, xz, surf_time);
	}
	return h * surf_calm_at(xz);
}

// Adds the moving swells to a static ground vertex and bends its normal to match.
void surf_displace(inout vec3 vertex, inout vec3 normal, mat4 model) {
	if (surf_wave_count == 0) { return; }
	vec2 xz = (model * vec4(vertex, 1.0)).xz;
	float e = 0.6;
	float h = surf_moving(xz);
	float hx = (surf_moving(xz + vec2(e, 0.0)) - surf_moving(xz - vec2(e, 0.0))) / (2.0 * e);
	float hz = (surf_moving(xz + vec2(0.0, e)) - surf_moving(xz - vec2(0.0, e))) / (2.0 * e);
	vertex.y += h;
	// Recover the static slope from the baked normal, add the swell's, rebuild.
	float ny = max(normal.y, 0.05);
	vec2 base_grad = -normal.xz / ny;
	normal = normalize(vec3(-(base_grad.x + hx), 1.0, -(base_grad.y + hz)));
}
