shader_type canvas_item;
// Dégradé radial du hub v2 (radial-gradient(circle at X% Y%, c0, c1 R%)) :
// `color` au centre, transparent à `radius` (pixels du rectangle dessiné),
// interpolation linéaire comme le CSS. Récapitulatif : éclair doré du
// passage de niveau (@keyframes lvlFlash). Voir Hub2RecapPanel.

uniform vec4 color : source_color = vec4(0.96, 0.77, 0.26, 0.55);
uniform vec2 center = vec2(0.3, 0.42);
uniform float radius = 600.0;
uniform vec2 rect_size = vec2(1280.0, 720.0);

void fragment() {
	vec2 p = UV * rect_size;
	float d = distance(p, center * rect_size);
	float k = clamp(1.0 - d / max(radius, 1.0), 0.0, 1.0);
	// Multiplié par la couleur du sommet : modulate du nœud et de ses parents.
	COLOR = vec4(color.rgb, color.a * k) * COLOR;
}
