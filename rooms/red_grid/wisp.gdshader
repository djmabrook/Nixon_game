shader_type spatial;
// A column of fog motes spiralling down into a loose hole, so it can be spotted
// from hundreds of metres. Each quad carries its phase in UV2.x and is placed here.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec3 tint : source_color = vec3(0.94, 0.88, 0.84);
uniform float height = 30.0;
uniform float strength = 1.0;
uniform float swirl = 1.0;

varying float life;

void vertex() {
	float ph = UV2.x;
	float t = fract(TIME * 0.09 + ph * 7.31);
	life = t;
	float hgt = (1.0 - t) * height;
	float ang = ph * 37.0 + TIME * 1.1 * swirl + t * 6.0;
	float rad = 0.6 + hgt * 0.22;
	vec3 centre = vec3(cos(ang) * rad, hgt, sin(ang) * rad);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float size = 0.12 + 0.22 * (1.0 - t);
	// Streaks: stretched along the fall, so they read as fog drawn down, not as balls.
	vec3 local = centre + right * (UV.x - 0.5) * size + up * (UV.y - 0.5) * size * 4.0;
	VERTEX = local;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = 1.0 - smoothstep(0.4, 1.0, length(c));
	float fade = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.85, 1.0, life));
	ALBEDO = tint * d * fade * strength;
}
