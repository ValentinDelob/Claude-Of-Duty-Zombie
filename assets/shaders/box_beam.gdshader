shader_type spatial;
// Colonne de lumière de la boîte mystère (BO1) : pâle et douce, visible de
// loin dans le noir, presque effacée de près. Cylindre ouvert, additif :
// bords fondus (incidence), fondu en bas et vers le haut, léger frémissement.
// Sert aussi au halo doré qui monte du coffre ouvert (fade = ouverture).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.62, 0.76, 1.0, 1.0);
// Intensité au cœur (le reste en découle) : voir MysteryBox.BEAM_INTENSITY.
uniform float intensity = 0.05;
uniform float height = 2.3;
// Distance (m) en dessous de laquelle la colonne s'efface (on est dessus).
uniform float near_fade = 6.0;
// Gain au-delà de 30 m.
uniform float far_boost = 1.4;
uniform sampler2D noise_lattice : filter_linear, repeat_enable;
// 0 : caché (départ de la boîte), 1 : normal.
instance uniform float fade = 1.0;

varying float h01;
varying vec2 ang;

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return textureLod(noise_lattice, (i + f + 0.5) / 64.0, 0.0).r;
}

void vertex() {
	h01 = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	ang = VERTEX.xz;
}

void fragment() {
	// Incidence : plein au centre de la colonne, nul sur ses bords.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = facing * facing * facing;
	// Fondu en bas (posé sur le couvercle) et vers le haut (s'éteint au plafond).
	// Base bornée à 0 : avec le MSAA (qualité HAUTE), les varyings sont
	// extrapolés hors du triangle sur ses bords (h01 un peu > 1) ; pow() d'un
	// négatif donne NaN, que le glow étale en énorme tache blanche aveuglante.
	float vert = smoothstep(0.0, 0.18, h01) * pow(max(1.0 - h01, 0.0), 1.3);
	// Frémissement lent qui monte (poussière dans la lumière).
	float shimmer = 0.75 + 0.25 * noise2(vec2(ang.x * 5.0 + ang.y * 3.0, h01 * 4.0 - TIME * 0.35));
	// Presque invisible de près (on est dessus), un peu plus nette au loin
	// (la colonne y est fine : c'est là qu'elle sert de repère).
	float d = length(VERTEX);
	float dist = smoothstep(0.3, near_fade, d) * mix(1.0, far_boost, smoothstep(12.0, 30.0, d));
	ALBEDO = color.rgb * (intensity * soft * vert * shimmer * dist * fade);
}
