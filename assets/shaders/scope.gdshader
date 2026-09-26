shader_type canvas_item;
// Écran de lunette (ScopeOverlay) : lentille ronde au centre, noir autour,
// vignettage et légère aberration chromatique vers le bord de la lentille.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// Rayon de la lentille en fraction de la hauteur de l'écran.
uniform float radius = 0.47;
// Force de l'aberration (décalage des canaux au bord, en fraction d'écran).
uniform float aberration = 0.006;
// Assombrissement du bord intérieur (0..1).
uniform float vignette = 0.7;
// Apparition (0 : noir complet, 1 : lentille ouverte).
uniform float reveal = 1.0;
// Opacité du masque noir hors de la lentille (lunette courte : partielle).
uniform float mask = 1.0;

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 c = (SCREEN_UV - 0.5) * vec2(res.x / res.y, 1.0);
	float d = length(c);
	float r = d / radius;
	vec2 dir = d > 0.0001 ? c / d : vec2(0.0);
	vec2 off = dir * aberration * smoothstep(0.45, 1.0, r) * vec2(res.y / res.x, 1.0);
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off).r;
	col.g = texture(screen_tex, SCREEN_UV).g;
	col.b = texture(screen_tex, SCREEN_UV - off).b;
	col *= 1.0 - smoothstep(0.62, 1.0, r) * vignette;
	// Reflet froid très léger du verre.
	col = mix(col, col * vec3(0.94, 1.0, 1.04), 0.5);
	float inside = 1.0 - smoothstep(0.985, 1.0, r);
	vec3 outside = mix(col * 0.35, vec3(0.0), mask);
	col = mix(outside, col, inside) * reveal;
	COLOR = vec4(col, 1.0);
}
