shader_type sky;
// Night over the grid: near-black violet overhead, a hot magenta band at the horizon,
// a slow field of stars, and a faint second grid wheeling high in the sky.

uniform vec3 zenith : source_color = vec3(0.012, 0.0, 0.03);
uniform vec3 mid : source_color = vec3(0.05, 0.02, 0.14);
uniform vec3 horizon : source_color = vec3(0.42, 0.2, 0.95);
uniform float horizon_sharpness = 9.0;
uniform float star_density = 0.9975;
// 1 while the Watcher is awake; 0 once his eyes are closed and the ultraviolet drains away.
uniform float awake = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(mid, zenith, smoothstep(0.0, 0.6, h));
	vec3 hz = mix(vec3(0.16, 0.14, 0.2), horizon, awake);
	col = mix(col, hz, exp(-abs(h) * horizon_sharpness) * 0.9);
	col = mix(col, mid * 0.4, smoothstep(0.0, -0.2, h));

	// Stars, twinkling slowly.
	vec3 cell = floor(d * 260.0);
	float s = hash(cell);
	float tw = 0.6 + 0.4 * sin(TIME * (1.0 + s * 3.0) + s * 40.0);
	col += vec3(1.0, 0.85, 1.0) * step(star_density, s) * tw * smoothstep(0.02, 0.25, h);

	// A ghost grid on the sky dome.
	vec2 uv = d.xz / max(h, 0.05) * 0.6;
	vec2 g = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	col += vec3(0.5, 0.15, 0.8) * line * 0.08 * awake * smoothstep(0.15, 0.6, h);

	COLOR = col;
}
