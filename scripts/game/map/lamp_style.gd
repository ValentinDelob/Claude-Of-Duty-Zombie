class_name LampStyle
extends RefCounted
## Rendu des lampes des cartes (docs/ART_DIRECTION.md « Lumière et
## ambiance ») : règle GLOBALE appliquée par MapProps.add_lamp à toutes les
## lampes (BUNKER K-7, lampes automatiques et luminaires de l'éditeur), sans
## rien changer aux données des cartes.
##
## Une lampe sous un abat-jour (plafond, lampe de bureau) éclaire surtout
## VERS LE BAS : flaque de lumière chaude au sol, faisceau visible dans la
## brume volumétrique. Elle est faite de deux lumières :
##   - la lampe (OmniLight3D « LampN », groupe RenderQuality.LAMP_GROUP),
##     pilotée par le courant et le grésillement comme avant, ramenée à une
##     faible lueur de proximité (`fill` de son énergie, portée `fill_range`) ;
##   - la flaque (SpotLight3D « Pool », LampPool), dirigée vers le bas, qui
##     recopie couleur et énergie de la lampe (x `pool`) et porte l'ombre
##     (une ombre de projecteur coûte moins qu'une ombre omnidirectionnelle).
## Lampe de plafond : en plus, un REBOND (SpotLight3D « Bounce », enfant de
## la lampe, sans ombre ni brume) posé `bounce_drop` m sous la lampe et
## dirigé vers le HAUT (cône `bounce_angle`) : la lumière renvoyée par la
## flaque éclaire le plafond autour de la lampe (plafond bleu-vert lisible,
## pas noir), `bounce` x l'énergie de la flaque (LampPool la recopie).
## Les autres lampes (appliques, bougies, feu, projecteur de chantier)
## restent une seule lumière omnidirectionnelle (`pool` absent).
## Sources d'appoint colorées (MapCatalog.LIGHTS « accent » : gyrophare,
## écran, tubes à essai, panneau de sortie, enseigne) : ACCENT, une lumière
## omnidirectionnelle courte, jamais d'ombre ; le gyrophare ajoute deux
## faisceaux tournants (BeaconSpin, réglages BEACON).

## Style par défaut d'une lampe de plafond (BUNKER K-7, lampes automatiques).
const CEILING := {"pool": 3.4, "angle": 50.0, "angle_att": 2.2, "range_k": 1.0,
	"fill": 0.3, "fill_range": 0.55, "fill_att": 1.8, "fog": 2.6, "fill_fog": 0.3,
	"bounce": 0.24, "bounce_drop": 2.0, "bounce_angle": 58.0, "bounce_range": 5.5}
## Luminaires de l'éditeur (MapCatalog.LIGHTS) : écarts au style par défaut.
## Tube néon : plus large et plus diffus (lumière froide qui lèche les murs).
## Lampe de bureau : cône serré, flaque nette sur le bureau, pas de rebond.
const FIXTURES := {
	"neon": {"pool": 2.4, "angle": 70.0, "angle_att": 1.1, "fill": 0.45, "fill_range": 0.7},
	"lustre": {"pool": 2.4, "angle": 66.0, "fill": 0.5, "fill_range": 0.75},
	"lampe_bureau": {"pool": 3.2, "angle": 48.0, "angle_att": 2.0, "range_k": 0.8, "fill": 0.35, "fill_range": 0.6, "fog": 3.0, "bounce": 0.0},
}
## Lampe sans abat-jour : une seule lumière omnidirectionnelle, atténuation
## un peu plus forte (lumière qui retombe vite : flaques et recoins sombres).
const OMNI := {"att": 1.6, "fog": 1.0}
## Source d'appoint colorée : lumière courte qui tombe vite, un peu de halo
## dans la brume, jamais d'ombre.
const ACCENT := {"att": 2.0, "fog": 0.8, "no_shadow": true, "specular": 0.0}
## Gyrophare : deux faisceaux opposés qui tournent (BeaconSpin), `beam` x
## l'énergie de la lampe, un tour en `period` s.
const BEACON := {"beam": 3.5, "beam_angle": 20.0, "beam_range": 7.0, "period": 1.6, "beam_fog": 2.0}


## Style d'une lampe : `fixture` (type de luminaire de l'éditeur, « » pour
## une lampe automatique ou de BUNKER K-7). Pure (tests/test_lamp_style.gd).
static func of(fixture: String) -> Dictionary:
	if fixture == "":
		return CEILING.duplicate()
	var d: Dictionary = MapCatalog.LIGHTS.get(fixture, {})
	if d.has("accent"):
		var a := ACCENT.duplicate()
		a["accent"] = String(d.accent)
		return a
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


## Le style a-t-il un rebond vers le plafond ?
static func has_bounce(style: Dictionary) -> bool:
	return has_pool(style) and float(style.get("bounce", 0.0)) > 0.0


## Source d'appoint colorée (« » : non) : « beacon », « screen », « glow », « sign ».
static func accent_of(style: Dictionary) -> String:
	return String(style.get("accent", ""))
