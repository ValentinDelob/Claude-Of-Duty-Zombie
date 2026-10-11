shader_type canvas_item;
render_mode unshaded;
// Boîte plate du hub v2 (Hub2Box sans flou) : fond, liseré, biseaux.

#include "res://assets/shaders/hub2_box.gdshaderinc"

void fragment() {
	vec2 aa2 = fwidth(local_pos);
	float aa = max(max(aa2.x, aa2.y), 0.0001);
	vec4 c = hub2_over(vec4(border_color.rgb, border_color.a * hub2_border(local_pos, aa)), fill);
	c.a *= hub2_mask(local_pos, aa);
	// COLOR (entrée) : modulate des parents (fondu des écrans).
	COLOR = c * COLOR;
}
