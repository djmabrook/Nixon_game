shader_type spatial;
render_mode diffuse_burley;
// World-space checkerboard. Black tiles show flowing lines while the gravity tide pulls.

uniform vec3 pink : source_color = vec3(1.0, 0.56, 0.56);
uniform vec3 black : source_color = vec3(0.03, 0.018, 0.026);
uniform vec3 flow_color : source_color = vec3(1.0, 0.22, 0.32);
uniform float tile_size = 1.5;
uniform vec2 tide_dir = vec2(0.0, 0.0);
uniform float tide_strength = 0.0;
uniform float warn = 0.0;
uniform vec3 ripple_origin = vec3(0.0);
uniform float ripple_time = 100.0;
uniform float calm = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wpos - wnorm * 0.002;
	vec2 cell = floor(p.xz / tile_size);
	float is_black = mod(cell.x + cell.y, 2.0);
	vec2 local = fract(p.xz / tile_size);
	float edge = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
	float top = step(0.5, wnorm.y);

	vec3 col = mix(pink, black, is_black);
	// Soft bevel so tiles read as tiles even through the dither.
	col *= mix(0.8, 1.0, smoothstep(0.0, 0.07, edge) * top + (1.0 - top));
	// Sides of the board are darker.
	col *= mix(0.55, 1.0, top);

	// Flow lines on black tiles, moving downhill.
	float along = dot(p.xz, tide_dir);
	float wave = sin(along * 3.2 - TIME * 7.0) * 0.5 + 0.5;
	float lines = smoothstep(0.7, 1.0, wave) * smoothstep(0.03, 0.12, edge);
	vec3 emit = flow_color * lines * tide_strength * is_black * 1.8;

	// Telegraph: black tiles shiver before the tide turns.
	emit += flow_color * is_black * warn * (0.15 + 0.15 * sin(TIME * 24.0)) * smoothstep(0.03, 0.12, edge);

	// Completion ripple from the socket.
	float d = length(p.xz - ripple_origin.xz);
	float front = ripple_time * 8.0;
	float ring = exp(-pow((d - front) * 1.4, 2.0)) * exp(-ripple_time * 0.6);
	emit += vec3(1.0, 0.62, 0.72) * ring * 2.2;
	// After completion the pink tiles glow a little, like a held breath.
	emit += pink * (1.0 - is_black) * calm * (0.10 + 0.05 * sin(TIME * 1.5 + d * 0.6));

	ALBEDO = col;
	EMISSION = emit * top;
	ROUGHNESS = mix(0.42, 0.85, is_black);
	SPECULAR = 0.45;
}
