shader_type spatial;
// Nappe de fumée / brume basse : quad face caméra, bruit animé qui dérive,
// éclairé par les lampes, fondu près des surfaces (profondeur) et des bords.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.52, 1.0);
uniform float density = 0.24;
uniform float speed = 0.02;
instance uniform float seed = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += noise(p) * a;
		p = p * 2.02 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	vec2 p = uv * vec2(3.0, 1.6) + vec2(seed * 7.3, seed * 2.1);
	float n = fbm(p + vec2(t, t * 0.3) + noise(p * 0.7 - vec2(t * 0.6, 0.0)) * 1.4);
	// Bords du quad adoucis.
	float edge = smoothstep(0.0, 0.3, uv.x) * (1.0 - smoothstep(0.7, 1.0, uv.x))
			* smoothstep(0.0, 0.35, uv.y) * (1.0 - smoothstep(0.55, 1.0, uv.y));
	// Fondu près des surfaces opaques (sol, murs).
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -world.z / world.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / 0.8, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(smoothstep(0.35, 0.85, n) * edge * soft * density, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
