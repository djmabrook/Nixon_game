// Dither Look depth pass: stepped haze bands and silhouette outlines.
//
// Drawn as a full-screen quad inside the 3D scene, so it can read the depth buffer, before
// DitherLook quantises the frame. DitherLook creates and drives it; rooms set the values on
// their DitherLookSettings (haze_* and outline_*).
//
// Haze: instead of smooth fog, distance is cut into a few flat layers, each one step closer to
// the haze colour, so a far mountain reads as standing behind several clear sheets of air.
// Outline: where a surface is much nearer than what is behind it (a colossus against the sky,
// a ridge against the next ridge) an ink line is drawn, so giant things read as silhouettes.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// x = steps (0 = off), y = start distance (m), z = end distance (m), w = max amount at the end (0..1)
uniform vec4 haze = vec4(0.0, 20.0, 1500.0, 0.85);
uniform vec3 haze_color : source_color = vec3(0.86, 0.88, 0.88);
uniform bool haze_sky = false;   // also band the sky (off: the sky stays as rendered)
// x = strength (0 = off), y = thickness in screen px, z = min distance (m), w = depth ratio that counts as an edge
uniform vec4 outline = vec4(0.0, 1.0, 40.0, 1.6);
uniform vec3 outline_color : source_color = vec3(0.08, 0.08, 0.09);
uniform float far_clip = 4000.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float linear_depth(sampler2D dtex, vec2 uv, mat4 inv_proj) {
	float d = textureLod(dtex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float z = linear_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	bool is_sky = z >= far_clip * 0.98;

	if (haze.x > 0.5 && (!is_sky || haze_sky)) {
		float dist = is_sky ? haze.z : z;
		// Log spacing: layers get deeper the further out they are, which reads as scale.
		float f = clamp(log(max(dist, haze.y) / haze.y) / log(haze.z / haze.y), 0.0, 1.0);
		float stepped = floor(f * haze.x + 0.0001) / haze.x;
		c = mix(c, haze_color, stepped * haze.w);
	}

	if (outline.x > 0.0 && !is_sky && z > outline.z) {
		vec2 o = outline.y / VIEWPORT_SIZE;
		float zn = max(max(linear_depth(depth_tex, SCREEN_UV + vec2(o.x, 0.0), INV_PROJECTION_MATRIX),
		                   linear_depth(depth_tex, SCREEN_UV - vec2(o.x, 0.0), INV_PROJECTION_MATRIX)),
		               max(linear_depth(depth_tex, SCREEN_UV + vec2(0.0, o.y), INV_PROJECTION_MATRIX),
		                   linear_depth(depth_tex, SCREEN_UV - vec2(0.0, o.y), INV_PROJECTION_MATRIX)));
		// Only the near side of a depth cliff gets ink, so the line hugs the silhouette.
		float edge = smoothstep(outline.w, outline.w * 1.4, zn / z);
		// Fade in past the min distance so lines don't pop on.
		edge *= smoothstep(outline.z, outline.z * 1.5, z);
		c = mix(c, outline_color, edge * outline.x);
	}

	ALBEDO = c;
}
