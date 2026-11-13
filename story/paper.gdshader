shader_type canvas_item;
// The paper margin. Everything outside `rect` (in UV) is bare bone paper with a deckled,
// torn edge; inside, the picture shows through. At reveal 0 nothing is drawn.
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0); // x0, y0, x1, y1
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec3 paper : source_color = vec3(0.937, 0.902, 0.847);
uniform vec3 fibre : source_color = vec3(0.86, 0.81, 0.73);
uniform vec3 shade : source_color = vec3(0.70, 0.64, 0.56);
uniform vec2 screen_px = vec2(640.0, 360.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(float x) { float i = floor(x); float f = fract(x); return mix(hash(vec2(i, 3.1)), hash(vec2(i + 1.0, 3.1)), f * f * (3.0 - 2.0 * f)); }

void fragment() {
	vec2 px = floor(UV * screen_px);
	vec2 uv = (px + 0.5) / screen_px;
	// Deckle: each edge wanders by a pixel or two.
	float dl = (noise(px.y * 0.21) + noise(px.y * 0.9) * 0.5) * 2.0 / screen_px.x;
	float dr = (noise(px.y * 0.23 + 40.0) + noise(px.y * 0.8 + 9.0) * 0.5) * 2.0 / screen_px.x;
	float dt = (noise(px.x * 0.19 + 70.0) + noise(px.x * 0.7 + 3.0) * 0.5) * 2.0 / screen_px.y;
	float db = (noise(px.x * 0.17 + 11.0) + noise(px.x * 0.85 + 5.0) * 0.5) * 2.0 / screen_px.y;
	bool inside = uv.x > rect.x + dl && uv.x < rect.z - dr && uv.y > rect.y + dt && uv.y < rect.w - db;
	if (inside) {
		COLOR = vec4(0.0);
	} else {
		// Fibres and tooth: sparse darker flecks and short horizontal strands.
		float tooth = hash(px);
		float strand = step(0.985, hash(floor(px / vec2(5.0, 1.0)) + 17.0));
		vec3 c = mix(paper, fibre, step(0.93, tooth) * 0.6 + strand * 0.5);
		// The print casts a faint shadow down and to the right onto the paper.
		vec2 o = vec2(2.0, 3.0) / screen_px;
		bool under = uv.x > rect.x + o.x && uv.x < rect.z + o.x && uv.y > rect.y + o.y && uv.y < rect.w + o.y;
		if (under) c = mix(c, shade, 0.55);
		COLOR = vec4(c, reveal);
	}
}
