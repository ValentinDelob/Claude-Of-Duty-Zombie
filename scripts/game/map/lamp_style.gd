class_name LampStyle
extends RefCounted
## Rendu des lampes des cartes (docs/ART_DIRECTION.md « Lumière et
## ambiance ») : règle GLOBALE appliquée par MapProps.add_lamp à toutes les
## lampes (BUNKER K-7, lampes automatiques et luminaires de l'éditeur), sans
## rien changer aux données des cartes.
##
## Une lampe sous un abat-jour (plafond, lampe de bureau) éclaire surtout
## VERS LE BAS : flaque de lumière chaude au sol, plafond laissé dans
## l'ombre bleu-vert, faisceau visible dans la brume volumétrique. Elle est
## faite de deux lumières :
##   - la lampe (OmniLight3D « LampN », groupe RenderQuality.LAMP_GROUP),
##     pilotée par le courant et le grésillement comme avant, ramenée à une
##     faible lueur de proximité (`fill` de son énergie, portée `fill_range`) ;
##   - la flaque (SpotLight3D « Pool », LampPool), dirigée vers le bas, qui
##     recopie couleur et énergie de la lampe (x `pool`) et porte l'ombre
##     (une ombre de projecteur coûte moins qu'une ombre omnidirectionnelle).
## Les autres lampes (appliques, bougies, feu, projecteur de chantier)
## restent une seule lumière omnidirectionnelle (`pool` absent).

## Style par défaut d'une lampe de plafond (BUNKER K-7, lampes automatiques).
const CEILING := {"pool": 3.4, "angle": 50.0, "angle_att": 2.2, "range_k": 1.0,
	"fill": 0.3, "fill_range": 0.55, "fill_att": 1.8, "fog": 1.6, "fill_fog": 0.3}
## Luminaires de l'éditeur (MapCatalog.LIGHTS) : écarts au style par défaut.
## Tube néon : plus large et plus diffus (lumière froide qui lèche les murs).
## Lampe de bureau : cône serré, flaque nette sur le bureau.
const FIXTURES := {
	"neon": {"pool": 2.4, "angle": 70.0, "angle_att": 1.1, "fill": 0.45, "fill_range": 0.7},
	"lustre": {"pool": 2.4, "angle": 66.0, "fill": 0.5, "fill_range": 0.75},
	"lampe_bureau": {"pool": 3.2, "angle": 48.0, "angle_att": 2.0, "range_k": 0.8, "fill": 0.35, "fill_range": 0.6, "fog": 3.0},
}
## Lampe sans abat-jour : une seule lumière omnidirectionnelle, atténuation
## un peu plus forte (lumière qui retombe vite : flaques et recoins sombres).
const OMNI := {"att": 1.6, "fog": 1.0}


## Style d'une lampe : `fixture` (type de luminaire de l'éditeur, « » pour
## une lampe automatique ou de BUNKER K-7). Pure (tests/test_lamp_style.gd).
static func of(fixture: String) -> Dictionary:
	if fixture == "":
		return CEILING.duplicate()
	var d: Dictionary = MapCatalog.LIGHTS.get(fixture, {})
	if FIXTURES.has(fixture):
		var s := CEILING.duplicate()
		s.merge(FIXTURES[fixture], true)
		return s
	if String(d.get("mount", "")) == "plafond":
		return CEILING.duplicate()
	return OMNI.duplicate()


## Le style a-t-il une flaque dirigée vers le bas ?
static func has_pool(style: Dictionary) -> bool:
	return style.has("pool")
