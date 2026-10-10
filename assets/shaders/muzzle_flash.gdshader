shader_type spatial;
// Flamme de bouche en cubes (VoxelFx.flash_mesh : ViewModel, Fx) : additive,
// non éclairée, couleur de chaque cube (COLOR) × tint. Le maillage est dans
// le repère du canon (-z) ; `spin` le tourne autour du canon (variante à
// chaque tir).
// viewmodel = 1 : même profondeur écrasée que weapon.gdshader, pour que l'arme
// cache la flamme qui passe derrière elle (et qu'aucun mur ne la coupe).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.75, 1.0);
uniform float energy = 1.25;
uniform float spin = 0.0;
uniform float viewmodel = 0.0;

void vertex() {
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	NORMAL.xy = mat2(vec2(c, s), vec2(-s, c)) * NORMAL.xy;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (viewmodel > 0.5) {
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);
	}
}

void fragment() {
	// Faces de côté un peu plus sombres : on lit les cubes.
	float f = 0.7 + 0.3 * abs(NORMAL.z);
	ALBEDO = COLOR.rgb * tint.rgb * energy * f;
	ALPHA = COLOR.a * tint.a;
}
