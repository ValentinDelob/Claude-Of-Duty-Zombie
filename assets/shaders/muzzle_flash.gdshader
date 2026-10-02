shader_type spatial;
// Flamme de bouche (ViewModel, Fx) : additive, non éclairée.
// billboard = 1 : le quad fait face à la caméra (échelle du nœud gardée),
// tourné de `spin` rad autour de l'axe de vue (variante à chaque tir).
// viewmodel = 1 : même profondeur écrasée que weapon.gdshader, pour que l'arme
// cache la flamme qui passe derrière elle (et qu'aucun mur ne la coupe).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.75, 1.0);
uniform float billboard = 0.0;
uniform float spin = 0.0;
uniform float viewmodel = 0.0;

void vertex() {
	if (billboard > 0.5) {
		float c = cos(spin);
		float s = sin(spin);
		VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (viewmodel > 0.5) {
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);
	}
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a;
}
