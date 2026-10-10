shader_type spatial;
// Surface unie (mesure du coût de pixel_surface.gdshader, scénario perf_costs).
uniform vec4 color_a : source_color = vec4(0.35, 0.34, 0.32, 1.0);
uniform float roughness_base = 0.9;

void fragment() {
	ALBEDO = color_a.rgb;
	ROUGHNESS = roughness_base;
}
