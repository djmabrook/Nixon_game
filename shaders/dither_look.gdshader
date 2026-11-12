// Dither Look: low-resolution, ordered (Bayer) dithered, limited-palette post-process.
//
// Draws on top of everything below its CanvasLayer. It reads the finished frame,
// snaps it to a coarse "virtual pixel" grid, grades it, adds a Bayer threshold and
// picks the nearest colour from a palette texture.
//
// Two looks (A and B) are evaluated so one can dissolve into the other through the
// dither pattern itself ("blend" goes 0 -> 1). Driven by DitherLook (dither_look.gd);
// you normally never touch these uniforms by hand.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

const int MAX_COLORS = 32;

// ---- Look A ----
uniform sampler2D palette_a : filter_nearest, repeat_disable;
uniform int palette_size_a = 2;
// x = pixel size (screen px per virtual px), y = dither spread, z = bayer levels (1=2x2, 2=4x4, 3=8x8), w = accent threshold
uniform vec4 shape_a = vec4(4.0, 1.0, 3.0, 0.0);
// x = contrast, y = brightness, z = saturation, w = grain
uniform vec4 grade_a = vec4(1.0, 0.0, 1.0, 0.0);
uniform bool soft_a = true;

// ---- Look B ----
uniform sampler2D palette_b : filter_nearest, repeat_disable;
uniform int palette_size_b = 2;
uniform vec4 shape_b = vec4(4.0, 1.0, 3.0, 0.0);
uniform vec4 grade_b = vec4(1.0, 0.0, 1.0, 0.0);
uniform bool soft_b = true;

uniform float blend : hint_range(0.0, 1.0) = 0.0;
// Camera position in real screen pixels. Added to the pixel grid and the Bayer pattern so both
// stay glued to the world instead of the screen: no "shower door" crawl when the camera pans.
uniform vec2 grid_offset = vec2(0.0);
uniform bool enabled = true;

// Ordered dither threshold in [0,1). levels: 1 -> 2x2, 2 -> 4x4, 3 -> 8x8.
float bayer(ivec2 p, int levels) {
	int v = 0;
	for (int i = 0; i < levels; i++) {
		int xi = (p.x >> i) & 1;
		int yi = (p.y >> i) & 1;
		v = v + ((2 * (xi ^ yi) + yi) << (2 * (levels - 1 - i)));
	}
	float n = float(1 << (2 * levels));
	return (float(v) + 0.5) / n;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float saturation_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mx <= 0.0001 ? 0.0 : (mx - mn) / mx;
}

// "Redmean" weighted RGB distance: cheap and close enough to perceptual for small palettes.
float color_dist(vec3 a, vec3 b) {
	vec3 d = a - b;
	float r = 0.5 * (a.r + b.r);
	return (2.0 + r) * d.r * d.r + 4.0 * d.g * d.g + (3.0 - r) * d.b * d.b;
}

vec3 grade(vec3 c, vec4 g) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, g.z);                 // saturation
	c = (c - 0.5) * g.x + 0.5 + g.y;          // contrast / brightness
	return clamp(c, 0.0, 1.0);
}

vec3 sample_block(vec2 block_origin_px, float px, vec2 screen_px, bool soft) {
	if (!soft) {
		return textureLod(screen_tex, (block_origin_px + 0.5 * px) / screen_px, 0.0).rgb;
	}
	// 4 taps inside the virtual pixel: smoother, less crawling than a single point sample.
	vec3 c = vec3(0.0);
	c += textureLod(screen_tex, (block_origin_px + vec2(0.25, 0.25) * px) / screen_px, 0.0).rgb;
	c += textureLod(screen_tex, (block_origin_px + vec2(0.75, 0.25) * px) / screen_px, 0.0).rgb;
	c += textureLod(screen_tex, (block_origin_px + vec2(0.25, 0.75) * px) / screen_px, 0.0).rgb;
	c += textureLod(screen_tex, (block_origin_px + vec2(0.75, 0.75) * px) / screen_px, 0.0).rgb;
	return c * 0.25;
}

vec3 run_look(vec2 frag_px, vec2 screen_px, sampler2D pal, int pal_size, vec4 shape, vec4 grd, bool soft) {
	float px = max(1.0, shape.x);
	vec2 world_px = frag_px + grid_offset;
	ivec2 cell = ivec2(floor(world_px / px));
	vec2 origin = vec2(cell) * px - grid_offset;

	vec3 src = grade(sample_block(origin, px, screen_px, soft), grd);
	float src_sat = saturation_of(src);

	float t = bayer(cell, int(shape.z)) - 0.5;
	if (grd.w > 0.0) {
		t += (hash12(vec2(cell)) - 0.5) * grd.w;  // static, world-anchored grain: never flickers
	}
	// Fade the dither out right at pure black and pure white so empty skies and voids stay
	// clean instead of carrying a faint pattern.
	float l = dot(src, vec3(0.299, 0.587, 0.114));
	float edge = clamp(min(l, 1.0 - l) * 14.0, 0.0, 1.0);
	vec3 c = src + t * shape.y * edge;

	// Accents: when shape.w > 0, strongly coloured palette entries are only used for
	// strongly coloured, reasonably bright source pixels. That keeps a 1-bit scene grey
	// but lets a red fire stay red, like the lakeside still. "Strongly coloured" palette
	// entries are those with saturation above 0.45.
	bool use_accents_gate = shape.w > 0.0;
	bool src_is_accent = src_sat >= shape.w && max(src.r, max(src.g, src.b)) > 0.3;

	vec3 best = vec3(0.0);
	float best_d = 1e9;
	int n = clamp(pal_size, 1, MAX_COLORS);
	for (int i = 0; i < MAX_COLORS; i++) {
		if (i >= n) break;
		vec3 p = texelFetch(pal, ivec2(i, 0), 0).rgb;
		if (use_accents_gate && !src_is_accent && saturation_of(p) > 0.45) continue;
		float d = color_dist(c, p);
		if (d < best_d) { best_d = d; best = p; }
	}
	return best;
}

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag_px = FRAGCOORD.xy;
	if (!enabled) {
		COLOR = vec4(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, 1.0);
	} else {
		vec3 out_c;
		if (blend <= 0.0) {
			out_c = run_look(frag_px, screen_px, palette_a, palette_size_a, shape_a, grade_a, soft_a);
		} else if (blend >= 1.0) {
			out_c = run_look(frag_px, screen_px, palette_b, palette_size_b, shape_b, grade_b, soft_b);
		} else {
			// Dissolve through the dither pattern on the coarser of the two grids.
			float px = max(shape_a.x, shape_b.x);
			float th = bayer(ivec2(floor((frag_px + grid_offset) / px)), 3);
			if (th < blend) {
				out_c = run_look(frag_px, screen_px, palette_b, palette_size_b, shape_b, grade_b, soft_b);
			} else {
				out_c = run_look(frag_px, screen_px, palette_a, palette_size_a, shape_a, grade_a, soft_a);
			}
		}
		COLOR = vec4(out_c, 1.0);
	}
}
