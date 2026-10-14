// Éclairage EN APLATS du style ILLUSTRÉ (IllustratedStyle, prototype ;
// docs/ART_DIRECTION.md « Style illustré »). Jamais inclus par un shader du
// jeu : IllustratedStyle l'ajoute à la fin d'une COPIE du shader (variante
// générée), après avoir défini STYLE_CEL et la sorte de surface :
//   CEL_ARCHI (pixel_surface), CEL_PROP (voxel_prop), CEL_CHAR (zombies,
//   joueurs), CEL_WEAPON (armes et mains).
// Le style CLASSIQUE garde l'éclairage du moteur (aucune fonction light()).
//
// Pour chaque lampe :
//   - FACE : N·L ramené à trois tons (dos, demi-ton, plein), transitions
//     courtes : une face de cube a un ton unique, comme une planche coloriée
//     en aplats. Les faces rasantes (N·L < CEL_FACE_LIT) restent dans l'ombre
//     (sinon un grand mur éclairé de biais devient un disque net) ;
//   - FLAQUE DE LUMIÈRE : l'atténuation (distance, cône, ombre portée) est
//     ramenée en partie à des paliers dont le niveau est le MILIEU de la
//     plage (même énergie moyenne qu'en CLASSIQUE) ; sous le premier palier,
//     elle est gardée telle quelle (pas de disque autour des lampes faibles) ;
//   - TEINTE : le demi-ton tire vers le bleu-vert (ombres colorées), la
//     pleine lumière vers le chaud ; le dos garde la lumière d'ambiance
//     (bleu-vert, WorldLook) ;
//   - SPÉCULAIRE : un seul reflet net, seulement sur les matières lisses
//     (flaques, métal, sang frais), atténué (CEL_SPEC).
// Les émissions (yeux, ampoules, lueurs de butin) ne passent pas par light()
// et restent intactes.

// CEL_FULL : niveau du plein ton ; CEL_MID : demi-ton ; CEL_POOL : part des
// paliers dans la flaque de lumière ; CEL_SPEC : force du reflet.
#ifdef CEL_ARCHI
const float CEL_FULL = 0.85;
const float CEL_MID = 0.32;
const float CEL_POOL = 0.75;
const float CEL_SPEC = 0.6;
#elif defined(CEL_CHAR)
const float CEL_FULL = 0.85;
const float CEL_MID = 0.32;
const float CEL_POOL = 0.5;
const float CEL_SPEC = 0.4;
#elif defined(CEL_WEAPON)
const float CEL_FULL = 0.7;
const float CEL_MID = 0.3;
const float CEL_POOL = 0.3;
const float CEL_SPEC = 0.5;
#else
const float CEL_FULL = 0.85;
const float CEL_MID = 0.32;
const float CEL_POOL = 0.65;
const float CEL_SPEC = 0.5;
#endif
// Seuils N·L : face éclairée (demi-ton) puis plein ton ; demi-largeur des
// transitions.
const float CEL_FACE_LIT = 0.1;
const float CEL_FACE_CUT = 0.42;
const float CEL_FACE_SOFT = 0.04;
// Paliers de la flaque : seuils d'atténuation (au-dessous du premier :
// atténuation gardée) et demi-largeur des transitions.
const float CEL_POOL_T1 = 0.2;
const float CEL_POOL_T2 = 0.35;
const float CEL_POOL_T3 = 0.65;
const float CEL_POOL_SOFT = 0.05;
// Teintes (multiplient la couleur de la lampe) : demi-ton froid, plein chaud.
const vec3 CEL_COOL = vec3(0.78, 0.96, 1.1);
const vec3 CEL_WARM = vec3(1.07, 1.0, 0.9);

float cel_pool(float a) {
	float s1 = smoothstep(CEL_POOL_T1 - CEL_POOL_SOFT, CEL_POOL_T1 + CEL_POOL_SOFT, a);
	float s2 = smoothstep(CEL_POOL_T2 - CEL_POOL_SOFT, CEL_POOL_T2 + CEL_POOL_SOFT, a);
	float s3 = smoothstep(CEL_POOL_T3 - CEL_POOL_SOFT, CEL_POOL_T3 + CEL_POOL_SOFT, a);
	float q = mix(a, (CEL_POOL_T1 + CEL_POOL_T2) * 0.5, s1);
	q = mix(q, (CEL_POOL_T2 + CEL_POOL_T3) * 0.5, s2);
	q = mix(q, 0.92, s3);
	return mix(a, q, CEL_POOL);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(CEL_FACE_LIT - CEL_FACE_SOFT, CEL_FACE_LIT + CEL_FACE_SOFT, ndl);
	float full = smoothstep(CEL_FACE_CUT - CEL_FACE_SOFT, CEL_FACE_CUT + CEL_FACE_SOFT, ndl);
	float face = lit * mix(CEL_MID, CEL_FULL, full);
	float pool = LIGHT_IS_DIRECTIONAL ? ATTENUATION : cel_pool(clamp(ATTENUATION, 0.0, 1.0));
	vec3 tint = mix(CEL_COOL, CEL_WARM, full);
	DIFFUSE_LIGHT += LIGHT_COLOR * (face * pool / PI) * tint;
	// Reflet net des matières lisses seulement.
	float gloss = clamp(1.0 - ROUGHNESS, 0.0, 1.0);
	if (gloss > 0.35) {
		vec3 h = LIGHT + VIEW;
		h *= inversesqrt(max(dot(h, h), 1e-6));
		float shin = exp2(3.0 + 8.0 * gloss);
		float sp = pow(clamp(dot(NORMAL, h), 0.0, 1.0), shin);
		float band = smoothstep(0.4, 0.5, sp) * lit;
		SPECULAR_LIGHT += LIGHT_COLOR * (band * pool * SPECULAR_AMOUNT * CEL_SPEC * gloss * 0.5) * CEL_WARM;
	}
}
