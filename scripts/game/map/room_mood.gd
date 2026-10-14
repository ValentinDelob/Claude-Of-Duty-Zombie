class_name RoomMood
extends RefCounted
## AMBIANCE d'une pièce (docs/ART_DIRECTION.md « Ambiance des pièces ») : la
## lumière raconte la pièce. Comme sur l'image de référence
## (docs/art/gemini_target.webp), un couloir de laboratoire froid bleu-vert
## donne sur une salle du fond éclairée en orange chaud.
##
## Préréglages (PRESETS) : « froid », « chaud », « alarme », « neon »,
## « eteint ». Une ambiance règle, pour sa pièce :
##   - la couleur des lampes automatiques et des luminaires laissés à leur
##     couleur du catalogue (`lamp`, mélangée à `lamp_mix`) et leur énergie
##     (`lamp_energy`) ; un luminaire recoloré par l'auteur garde sa couleur ;
##   - une lumière de remplissage (OmniLight3D sans ombre, `fill`,
##     `fill_energy`) qui teinte les murs et le plafond ; « alarme » la fait
##     pulser (`pulse`, période en s) ;
##   - la brume de la pièce (FogVolume : `fog` albédo, `fog_density`,
##     `fog_emission`), visible en MEDIUM et HIGH (brume volumétrique).
##
## Ambiance d'une pièce = celle choisie dans l'éditeur (clé facultative
## « ambiance » d'une pièce ou de sa zone, format 23), sinon DÉDUITE (derive)
## de son nom, du nom de sa zone, de son sol et de ses luminaires ; rien de
## parlant : « » (ambiance standard, aucun réglage : lampes chaudes sur
## l'ambiante bleu-vert de WorldLook). Pure : tests/test_room_mood.gd.

## Valeur « déduite » de l'éditeur (jamais écrite dans un fichier).
const AUTO := "auto"
const ORDER := ["froid", "chaud", "alarme", "neon", "eteint"]
const PRESETS := {
	"froid": {"fr": "Froid", "en": "Cold",
		"lamp": Color(0.74, 0.9, 1.0), "lamp_mix": 0.8, "lamp_energy": 0.85,
		"fill": Color(0.32, 0.66, 0.74), "fill_energy": 0.55,
		"fog": Color(0.55, 0.85, 0.92), "fog_density": 0.01, "fog_emission": Color(0.004, 0.014, 0.017)},
	"chaud": {"fr": "Chaud", "en": "Warm",
		"lamp": Color(1.0, 0.56, 0.26), "lamp_mix": 0.85, "lamp_energy": 1.35,
		"fill": Color(1.0, 0.54, 0.24), "fill_energy": 1.5,
		"fog": Color(1.0, 0.7, 0.42), "fog_density": 0.014, "fog_emission": Color(0.02, 0.009, 0.002)},
	"alarme": {"fr": "Alarme", "en": "Alarm",
		"lamp": Color(1.0, 0.42, 0.28), "lamp_mix": 0.55, "lamp_energy": 0.8,
		"fill": Color(1.0, 0.13, 0.05), "fill_energy": 0.85, "pulse": 1.6,
		"fog": Color(1.0, 0.45, 0.38), "fog_density": 0.012, "fog_emission": Color(0.024, 0.003, 0.0)},
	"neon": {"fr": "Néon", "en": "Neon",
		"lamp": Color(0.82, 0.55, 1.0), "lamp_mix": 0.65, "lamp_energy": 1.0,
		"fill": Color(0.72, 0.26, 1.0), "fill_energy": 0.75,
		"fog": Color(0.8, 0.6, 1.0), "fog_density": 0.012, "fog_emission": Color(0.012, 0.004, 0.02)},
	"eteint": {"fr": "Éteint", "en": "Lights out",
		"lamp": Color(0.82, 0.88, 0.92), "lamp_mix": 0.5, "lamp_energy": 0.3,
		"fill": Color(0.16, 0.34, 0.42), "fill_energy": 0.3,
		"fog": Color(0.4, 0.56, 0.62), "fog_density": 0.02, "fog_emission": Color(0.0, 0.0, 0.0)},
}

## Mots-clés des noms (minuscules, sans accents), français et anglais. Le
## premier préréglage dont un mot apparaît dans un nom l'emporte (ordre de
## KEYWORDS : l'alarme avant le reste).
const KEYWORDS := [
	["froid", ["chambre froide", "cold room", "frigo", "morgue"]],
	["alarme", ["generat", "alarm", "chaufferie", "reacteur", "reactor", "confinement", "urgence", "emergency",
		"machine", "turbine", "boiler", "quarantaine", "quarantine"]],
	["eteint", ["rituel", "ritual", "crypte", "crypt", "cave", "egout", "sewer", "abandon", "ruine", "ruin",
		"sous-sol", "basement", "catacomb", "ossuaire"]],
	["neon", ["neon", "arcade", "serveur", "server", "informatique", "computer", "salle de controle", "control room",
		"club", "bar ", "casino"]],
	["chaud", ["dortoir", "barrack", "bureau", "office", "garde", "guard", "cuisine", "kitchen", "cantine", "canteen",
		"refectoire", "mess", "salon", "lounge", "chambre", "bedroom", "foyer", "biblio", "library", "archive",
		"directeur", "director", "repos","atelier", "workshop", "chapelle", "chapel", "loge", "theatre",
		"theater", "salle a manger", "dining", "quartier", "quarters"]],
	["froid", ["labo", "lab", "couloir", "corridor", "hallway", "cellule", "cell", "infirmerie", "infirmary",
		"hopital", "hospital", "bloc", "operat", "stockage", "storage",
		"isolement", "isolation", "douche", "shower", "sanitaire", "toilet", "pharmac", "ward"]],
]
## Sols chauds (bois, moquettes) et froids (carrelage, métal) : indice faible,
## utilisé seulement sans nom parlant.
const WARM_FLOORS := ["wood", "parquet", "carpet_red", "carpet_theater", "stage_wood", "dark_wood", "velvet"]
const COLD_FLOORS := ["tiles", "metal", "steel"]
## Luminaires qui disent l'ambiance de leur pièce (MapCatalog.LIGHTS) : un
## gyrophare met la pièce en alarme, une enseigne au néon en néon ; les
## flammes et le lustre la réchauffent, les tubes néon la refroidissent
## (indices faibles : seulement sans nom parlant). Ampoules, suspensions,
## appliques et lampes de bureau ne disent rien (lampes standard).
const STRONG_FIXTURES := {"gyrophare": "alarme", "enseigne": "neon"}
const WARM_FIXTURES := ["feu", "bougies", "lustre"]
const COLD_FIXTURES := ["neon"]


static func is_preset(v: Variant) -> bool:
	return v is String and PRESETS.has(v)


static func preset(mood: String) -> Dictionary:
	return PRESETS.get(mood, {})


## Nom affiché (langue du jeu) ; « » : « Standard ».
static func display_name(mood: String) -> String:
	if not PRESETS.has(mood):
		return Lang.t("Standard", "Standard")
	return Lang.t(String(PRESETS[mood].fr), String(PRESETS[mood].en))


## Minuscules sans accents (comparaison des mots-clés).
static func fold(s: String) -> String:
	var t := s.to_lower()
	var from := "àâäáãéèêëíìîïóòôöõúùûüçñœ"
	var to := ["a", "a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "o", "u", "u", "u", "u", "c", "n", "oe"]
	var out := ""
	for i in t.length():
		var ch := t[i]
		var k := from.find(ch)
		out += to[k] if k >= 0 else ch
	return out


## Préréglage dont un mot-clé apparaît dans `names` (« » : aucun).
static func from_names(names: Array) -> String:
	var hay := ""
	for n in names:
		hay += " " + fold(String(n)) + " "
	for entry in KEYWORDS:
		for w: String in entry[1]:
			if hay.contains(w):
				return String(entry[0])
	return ""


## Ambiance DÉDUITE d'une pièce : luminaire fort (gyrophare, enseigne), puis
## noms (pièce, zone), puis indices faibles (luminaires, sol). « » : standard.
static func derive(names: Array, floor_key := "", fixtures: Array = []) -> String:
	for f in fixtures:
		if STRONG_FIXTURES.has(String(f)):
			return String(STRONG_FIXTURES[String(f)])
	var by_name := from_names(names)
	if by_name != "":
		return by_name
	var warm := 0
	var cold := 0
	for f in fixtures:
		if String(f) in WARM_FIXTURES:
			warm += 1
		elif String(f) in COLD_FIXTURES:
			cold += 1
	if warm > cold:
		return "chaud"
	if cold > warm:
		return "froid"
	if floor_key in WARM_FLOORS:
		return "chaud"
	if floor_key in COLD_FLOORS:
		return "froid"
	return ""


## Ambiance d'une pièce : la sienne (éditeur), sinon celle de sa zone, sinon
## déduite. `room_value` / `zone_value` : clé « ambiance » (absente : null).
static func resolve(room_value: Variant, zone_value: Variant, derived: String) -> String:
	if is_preset(room_value):
		return String(room_value)
	if is_preset(zone_value):
		return String(zone_value)
	return derived


## Couleur et énergie d'une lampe de la pièce : `color` mélangée à la
## couleur de l'ambiance si `tintable` (lampe automatique, luminaire à sa
## couleur du catalogue) ; énergie x `lamp_energy`. Rend [Color, float].
static func lamp(mood: String, color: Color, energy: float, tintable := true) -> Array:
	var p := preset(mood)
	if p.is_empty():
		return [color, energy]
	var c := color
	if tintable:
		c = color.lerp(p.lamp, float(p.lamp_mix))
	return [c, energy * float(p.lamp_energy)]
