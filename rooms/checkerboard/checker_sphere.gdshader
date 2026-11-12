shader_type spatial;
// Beach-ball checker on a UV sphere, with a soft rim light.

uniform vec3 color_a : source_color = vec3(0.96, 0.46, 0.50);
uniform vec3 color_b : source_color = vec3(0.03, 0.018, 0.026);
uniform float columns = 8.0;
uniform float rows = 4.0;
uniform float glow = 0.0;

void fragment() {
	float c = mod(floor(UV.x * columns) + floor(UV.y * rows), 2.0);
	vec3 col = mix(color_a, color_b, c);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.55, c);
	SPECULAR = 0.65;
	EMISSION = color_a * (fres * 0.22 + glow * (1.0 - c) * 1.4);
}
