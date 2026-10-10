class_name EditorMap
extends RefCounted
## Carte de l'éditeur (docs/MAP_AUTHORING.md) : cinq fichiers JSON lisibles et
## écrivables à la main, dans un dossier (user://maps/<id>/) ou une archive
## .zip. Coordonnées en mètres (x vers l'est, y vers le sud), identifiants
## stables pour chaque élément.
##   carte.json       id, noms FR/EN, description, musique, version du format
##   pieces.json      pièces (contour, altitude du sol, zone, hauteur de plafond...)
##   ouvertures.json  portes, débris, portes du courant, passages, fenêtres
##   objets.json      tout le reste (murs, piliers, escaliers, pièges, caisse au hasard...)
##   zones.json       zones (noms FR/EN, matériaux) et zone de départ

## Version du format des fichiers :
##   1  premières cartes (v0.1.137) ;
##   2  décor posé (type « prefab »), luminaires réglables (type
##      « luminaire »), textures par pièce (surface_sol, surface_murs,
##      surface_plafond de pieces.json) et plafond des zones (plafond de
##      zones.json). Une carte au format 1 se lit telle quelle : toutes les
##      nouvelles clés sont facultatives (_migrate) ;
##   3  murs en biais : un objet mural (ou une applique) contre un côté de
##      pièce oblique a la clé « angle » (direction du mur vue de l'objet,
##      degrés dans le sens horaire depuis le nord ; « mur » garde la
##      direction cardinale la plus proche). Les côtés en biais, les murs libres
##      en biais et les ouvertures posées dessus n'ont pas de clé nouvelle
##      (coordonnées en mètres, comme avant). Formats 1 et 2 lus tels quels ;
##   4  formes libres : coordonnées sans grille (au centimètre), formes de base
##      (clé « forme » d'une pièce : cercle, ellipse, triangle, L, avec leurs
##      paramètres pour les régénérer ; MapShapes), mur courbe (type
##      « mur_courbe »), rotation au degré près (« rot » entier de 0 à 359 du
##      décor, des luminaires, des piliers, escaliers et pièges). Toutes les
##      nouvelles clés sont facultatives : formats 1 à 3 lus tels quels ;
##   5  objets (docs/MAP_OBJECTS.md) : variante d'aspect (clé « variante » des
##      portes et débris, MapCatalog.VARIANTS ; absente :
##      l'aspect d'avant, jamais écrite pour l'aspect par défaut) et barrière
##      invisible (type « bloc_invisible » : rect, rot, hauteur). Toutes les
##      nouvelles clés sont facultatives : formats 1 à 4 lus tels quels ;
##   6  types d'escaliers (docs/MAP_OBJECTS.md § Escaliers) : « variante »
##      d'un escalier (droit, palier, quart, demi_tour, large, service,
##      colimacon, rampe ; absente : droit, l'escalier d'avant) et ses
##      réglages facultatifs « sens », « marches », « garde_corps », « cotes »
##      (MapCatalog.tidy_stair : jamais écrits à leur valeur par défaut).
##      Formats 1 à 5 lus tels quels (un escalier sans ces clés est droit).
##   7  décor posé librement (docs/MAP_OBJECTS.md § 8) : « hauteur » d'une
##      applique (luminaire mural, m au-dessus du sol ; absente : 2 m, jamais
##      écrite à sa valeur par défaut). Le décor contre un mur, à moitié dedans
##      ou au centimètre n'a pas de clé nouvelle (« position » en mètres,
##      « rot », « mur », « angle » comme avant). Formats 1 à 6 lus tels quels.
##   8  portes à zombies (docs/MAP_OBJECTS.md § 9) : « variante » d'une
##      fenêtre (« porte » : porte simple de 1 m, « porte_double » : 2 m ;
##      absente : la fenêtre d'avant, jamais écrite). La largeur suit le type
##      (pas de clé « largeur »). Formats 1 à 7 lus tels quels.
##   9  barrière invisible en polygone (docs/MAP_OBJECTS.md § 2) : clé
##      « sommets » ([[x, y], ...], 3 à 64 points) à la place de « rect » /
##      « rot » ; posée n'importe où. Une barrière d'avant (rectangle tourné)
##      est lue comme le polygone de ses 4 coins (_normalize) : même place,
##      même collision. Réglage de la carte « chevauchement_decor » (carte.json,
##      vrai / faux, absent : faux) : décor et obstacles peuvent se chevaucher
##      (MapCatalog.OVERLAP_TYPES). Formats 1 à 8 lus tels quels.
##  10  prefabs de la carte (docs/MAP_OBJECTS.md § 11, MapPrefabLib) : dossier
##      prefabs/<pid>/ de la carte (prefab.json, et model.glb pour un modèle
##      importé) ; un décor posé les cite par « prefab » : « map:<pid> » (une
##      carte sans prefab n'a pas de dossier prefabs/) ;
##      et effets (docs/MAP_OBJECTS.md § 12) : type « effet » (clé « effet » :
##      flammes, fumées, étincelles, électricité, eau, ambiance de
##      MapCatalog.EFFECTS ; « position », et selon l'effet « rot », « mur »,
##      « angle ») et ses réglages facultatifs « intensite », « taille »,
##      « couleur », « hauteur » (MapCatalog.tidy_effect : jamais écrits à leur
##      valeur par défaut). Aucune collision. Formats 1 à 9 lus tels quels.
##  11  effets purs et zones (docs/MAP_OBJECTS.md § 12) : un effet ne
##      construit plus aucun objet (bûches, torche, tuyau, boîtier, électrodes,
##      bobine, câble, flaque...) : ce sont des décors du catalogue (type
##      « prefab »), dont certains se posent contre un mur (« mur », « angle »,
##      « hauteur » comme une applique) ou au plafond. Un effet a une « zone »
##      ([largeur, profondeur] en m au sol et au plafond, [largeur,
##      profondeur, hauteur] pour un volume, [largeur, hauteur] au mur),
##      centrée sur « position », tournée avec « rot » ; « taille » (d'avant)
##      est lue comme la zone par défaut × taille. Une carte d'un format plus
##      ancien est CONVERTIE au chargement (_migrate) : chaque effet qui
##      construisait un objet reçoit le décor équivalent au même endroit
##      (MapCatalog.split_legacy_effect), rien ne disparaît.
##  12  hauteurs de pose (docs/EDITOR_VIEWS.md § 7), toutes facultatives :
##      « z » d'un décor posé au sol (m au-dessus du sol : posé sur un autre
##      décor ; un décor qui bloque doit reposer sur un autre), « hauteur »
##      d'un luminaire au sol (sinon : le dessus du meuble dessous),
##      « descente » d'un luminaire, d'un effet ou d'un décor accrochés au
##      plafond (m sous le plafond ; sinon : `drop` du catalogue ou 0).
##      Jamais écrites à leur valeur par défaut (MapVertical.tidy). Aucune
##      conversion : une carte au format 11 ou moins se lit telle quelle.
##  13  VOLUME des effets (docs/MAP_OBJECTS.md § 12, MapCatalog.effect_volume) :
##      tout ce qu'un effet affiche reste dans sa boîte, celle que dessine
##      l'éditeur. Zones par défaut agrandies (fumées, vapeur, étincelles,
##      câble, filet d'eau, torche) et hauteurs par défaut changées (torche,
##      arc, bobine Tesla : la hauteur est le bas ou le milieu du volume). Une
##      carte d'un format plus ancien est CONVERTIE au chargement (_migrate,
##      MapCatalog.migrate_effect_13) : chaque effet garde sa taille et sa place.
##  14  échelle et rotation 3D du décor (docs/EDITOR_SCALE_ROTATE.md, MapScale),
##      clés facultatives d'un objet « prefab », jamais écrites à leur valeur
##      par défaut : « echelle » [sx, sy, sz] (0,25 à 4, repère de l'objet :
##      largeur, profondeur, hauteur) et « incl » [x, y] (degrés, -180 à 180,
##      décor posé au sol seulement : inclinaisons autour des axes X et Y ;
##      « rot » reste le lacet, en degrés entiers). Aucune conversion : une
##      carte au format 13 ou moins se lit telle quelle et s'affiche à l'identique.
##  15  caisse au hasard (type « boite ») posée au sol (docs/MAP_OBJECTS.md § 15) : une « boite »
##      SANS « mur » est au sol, « position » = son centre, « rot » = son
##      orientation (degrés entiers, sens horaire vu de dessus ; à 0 l'avant
##      est au sud). Avec « mur » (et « angle ») : contre un mur, comme avant.
##      Conversion : une boîte d'une carte plus ancienne sans « mur » (fichier
##      écrit à la main : le jeu la mettait contre le mur nord) reçoit
##      « mur » : « n » ; toutes les autres sont lues telles quelles.
##  16  textures de la carte (MapTextureLib, docs/MAP_AUTHORING.md § Textures de
##      la carte) : dossier textures/<tid>/ (texture.json, image.png ou
##      image.jpg, normal.png|jpg facultative) ; une pièce ou une zone les cite
##      dans ses champs de surface par « map:<tid> » (une carte sans texture n'a
##      pas de dossier textures/). Aucune conversion : formats 1 à 15 lus tels quels.
##  17  niveaux libres (docs/LEVELS_PLAN.md, docs/MAP_AUTHORING.md § 4) : plus
##      d'étages. Chaque pièce, ouverture et objet a une « altitude » (m,
##      altitude absolue du sol où il est posé, nombre fini sans borne ; 0 par
##      défaut) ; un escalier a aussi « altitude_haut » (sol d'arrivée, il peut
##      sauter des niveaux) et, droit, palier, large, service ou rampe, une
##      « sortie » facultative (« gauche » / « droite » vu en montant ; absente :
##      en face ; MapCatalog.tidy_stair). Les niveaux sont les altitudes
##      distinctes des pièces (levels, à ALT_EQ près) ; deux pièces qui se
##      recouvrent en plan sont à MIN_STACK (3,1 m) au moins l'une de l'autre
##      (stack_issue) ; une pièce haute est une pièce au grand « plafond »
##      (2,8 m au moins, sans maximum) qui traverse les niveaux du dessus
##      (rooms_through), une pièce posée au-dessus de son vide est une
##      mezzanine. « sans_plafond » : true (jamais écrit à faux) : plafond
##      masqué, murs jusqu'au « plafond », CIEL de la carte au-dessus :
##      « carte.ciel » = {type : « noir » | « jour » | « nuit », luminosite
##      (facteur de 0,1 à 2, 1 par défaut)} (sky_of ; défaut : noir, jamais
##      écrit à sa valeur par défaut). Coordonnées x, y libres (négatives
##      comprises), sans étendue maximale ; hauteurs sans maximum de
##      conception (garde technique MapVertical.TECH_Z). « carte.etages »,
##      « etage » et « double_hauteur » disparaissent. Conversion au
##      chargement, en dernier dans _migrate (migrate_levels) : altitude = sol
##      de l'ancien étage, plafond de l'étage écrit sur la pièce, double
##      hauteur = plafond jusqu'en haut de l'étage du dessus, pièce entièrement
##      couverte par l'étage du dessus = plafond porté sous sa dalle, escalier :
##      altitude_haut = sol de l'étage du dessus (sinon 3,5 m plus haut).
const FORMAT := 17
const FILES := ["carte.json", "pieces.json", "ouvertures.json", "objets.json", "zones.json"]
const DEFAULT_CEILING := 3.2
## Écart par défaut entre deux niveaux (m) : nouveau niveau, ancien étage sans « sol ».
const FLOOR_STEP := 3.5
## Format 17 : deux altitudes sont le même niveau à 5 mm près.
const ALT_EQ := 0.005
## Écart minimal entre deux pièces empilées (hauteur sous plafond 2,8 m + dalle 0,3 m).
const MIN_STACK := 3.1
## Une pièce haute traverse le niveau du dessus si son plafond dépasse le sol
## de ce niveau d'au moins 2,1 m (hauteur de passage).
const HIGH_CLEAR := 2.1
## Exemple livré avec le jeu (lecture seule : « Enregistrer » en fait une copie).
const EXAMPLES := {"draft_arena": "res://assets/maps/draft_arena/"}

var carte: Dictionary = {}
var pieces: Array = []
var ouvertures: Array = []
var objets: Array = []
var zones: Array = []
var depart := ""
## Problèmes de lecture (fichier absent, JSON illisible...) : [fr, en].
var load_errors: Array = []
## Notes de lecture, qui ne refusent pas la carte : [fr, en]. Objets des
## types retirés du jeu (MapCatalog.REMOVED_TYPES) ignorés (strip_removed).
var load_notes: Array = []
## Format 10 : prefabs de la carte (MapPrefabLib) : pid -> définition
## (prefab.json nettoyé) ; modèles importés : pid -> octets du .glb en base64.
var prefabs: Dictionary = {}
var models: Dictionary = {}
## Format 15 : textures de la carte (MapTextureLib) : tid -> définition
## (texture.json nettoyé) ; images : clé de texte -> octets en base64.
var textures: Dictionary = {}
var texture_files: Dictionary = {}


static func blank(map_id := "nouvelle_carte", name_fr := "NOUVELLE CARTE", name_en := "NEW MAP") -> EditorMap:
	var m := EditorMap.new()
	m.carte = {"format": FORMAT, "id": map_id, "nom": {"fr": name_fr, "en": name_en},
		"description": {"fr": "", "en": ""}, "musique": "ambience_bunker", "hauteur_portes": 2.5,
		"lampes_auto": true}
	return m


# ------------------------------------------------------------------ accès

func id() -> String:
	return String(carte.get("id", "carte"))


func display_name() -> String:
	var n: Dictionary = carte.get("nom", {})
	return Lang.t(String(n.get("fr", id())), String(n.get("en", n.get("fr", id()))))


# ------------------------------------------------------------------ niveaux (format 17)

## Niveaux vides ouverts dans l'éditeur (altitudes, m) : affichés et parcourus
## comme les autres, jamais enregistrés (un niveau existe par ses pièces).
var view_levels: Array = []
## Contrôles en cours (freeze_levels) : niveaux gardés tels quels.
var _lv_frozen := 0
var _lv_frame := -1
var _lv_rooms := -1
## Mémoire de levels() : altitudes brutes lues (pièces puis niveaux vides)
## -> niveaux triés.
var _lv_raw: Array = []
var _lv: Array = [0.0]


## Altitude (m) d'un élément : « altitude », 0 si absente ou illisible.
static func alt_of(e: Dictionary) -> float:
	var a: Variant = e.get("altitude", 0.0)
	return float(a) if (a is float or a is int) and is_finite(float(a)) else 0.0


## Altitude d'arrivée d'un escalier : « altitude_haut », sinon un niveau
## standard au-dessus du pied.
static func stair_top(o: Dictionary) -> float:
	var a: Variant = o.get("altitude_haut")
	return float(a) if (a is float or a is int) and is_finite(float(a)) else alt_of(o) + FLOOR_STEP


## Arrivée d'un escalier de la carte : « altitude_haut », sinon le niveau
## suivant celui de son pied.
func stair_top_of(o: Dictionary) -> float:
	if o.has("altitude_haut"):
		return stair_top(o)
	var k := level_of(o)
	return level_alt(k + 1) if k >= 0 else stair_top(o)


## Hauteur sous plafond réglée d'une pièce (m).
static func room_ceiling(p: Dictionary) -> float:
	var c: Variant = p.get("plafond", DEFAULT_CEILING)
	return float(c) if (c is float or c is int) and is_finite(float(c)) else DEFAULT_CEILING


## Altitude du plafond réglé d'une pièce (m).
static func room_top(p: Dictionary) -> float:
	return alt_of(p) + room_ceiling(p)


## Pièce au plafond masqué (« sans_plafond » : true, format 17) : à ciel
## ouvert, murs jusqu'à son plafond réglé.
static func no_ceiling(p: Dictionary) -> bool:
	var v: Variant = p.get("sans_plafond", false)
	return v is bool and v


## Masquer (`hidden`) ou afficher le plafond d'une pièce : la clé n'est écrite
## que pour un plafond masqué.
static func set_no_ceiling(p: Dictionary, hidden: bool) -> void:
	if hidden:
		p["sans_plafond"] = true
	else:
		p.erase("sans_plafond")


## Ciel de la carte (« carte.ciel ») : types, luminosité (facteur) par défaut
## et bornes (panneau, contrôle des cartes reçues).
const SKY_TYPES := ["noir", "jour", "nuit"]
const SKY_DEFAULT := "noir"
const SKY_LUM_DEFAULT := 1.0
const SKY_LUM := [0.1, 2.0]


## Ciel de la carte lu dans `c` (carte.json) : {type, luminosite} ; absent ou
## illisible : noir, luminosité 1.
static func sky_of(c: Dictionary) -> Dictionary:
	var out := {"type": SKY_DEFAULT, "luminosite": SKY_LUM_DEFAULT}
	var s: Variant = c.get("ciel")
	if not s is Dictionary:
		return out
	var t: Variant = s.get("type", SKY_DEFAULT)
	if t is String and t in SKY_TYPES:
		out.type = t
	var l: Variant = s.get("luminosite", SKY_LUM_DEFAULT)
	if (l is float or l is int) and is_finite(float(l)):
		out.luminosite = clampf(float(l), SKY_LUM[0], SKY_LUM[1])
	return out


## Règle le ciel de la carte `c`, jamais écrit à sa valeur par défaut (noir :
## clé retirée, la luminosité n'y change rien ; luminosité 1 : non écrite).
static func set_sky(c: Dictionary, type: String, lum: float) -> void:
	if not type in SKY_TYPES or type == SKY_DEFAULT:
		c.erase("ciel")
		return
	var s := {"type": type}
	if is_finite(lum) and absf(lum - SKY_LUM_DEFAULT) > 0.001:
		s["luminosite"] = snappedf(clampf(lum, SKY_LUM[0], SKY_LUM[1]), 0.01)
	c["ciel"] = s


## Ciel illisible ou par défaut retiré ; sinon réécrit proprement.
static func tidy_sky(c: Dictionary) -> void:
	if c.has("ciel"):
		var s := sky_of(c)
		set_sky(c, String(s.type), float(s.luminosite))


## Altitudes distinctes (à ALT_EQ près) de `alts`, triées.
static func merge_alts(alts: Array) -> Array:
	var s := alts.duplicate()
	s.sort()
	var out := []
	for a in s:
		if out.is_empty() or float(a) - float(out[-1]) > ALT_EQ:
			out.append(float(a))
	return out


## Niveaux de la carte : altitudes distinctes de ses pièces (et des niveaux
## vides de l'éditeur), triées de bas en haut ; une carte sans pièce a
## toujours le niveau 0.
## Le tableau rendu est partagé : ne pas le modifier. Pendant un contrôle
## (freeze_levels : lot de MapRules, construction de la grille) ils ne sont
## pas relus : les altitudes n'y changent pas.
func levels() -> Array:
	if _lv_frozen > 0:
		# Sûreté : un lot resté ouvert ne fige jamais plus d'une image ni une
		# liste de pièces qui a changé de taille.
		if _lv_frame == Engine.get_process_frames() and _lv_rooms == pieces.size():
			return _lv
		_lv_frozen = 0
	# Appelée très souvent (level_of, level_count...) : les altitudes brutes
	# relues sont comparées à celles de la dernière fois, sans rien construire ;
	# niveaux recalculés seulement si l'une a changé.
	var n := pieces.size()
	var nv := view_levels.size()
	var same := _lv_raw.size() == n + nv
	if same:
		for i in n:
			var a: Variant = (pieces[i] as Dictionary).get("altitude", 0.0)
			var r: Variant = _lv_raw[i]
			if typeof(a) != typeof(r) or a != r:
				same = false
				break
	if same:
		for i in nv:
			var a: Variant = view_levels[i]
			var r: Variant = _lv_raw[n + i]
			if typeof(a) != typeof(r) or a != r:
				same = false
				break
	if same:
		return _lv
	var raw := []
	raw.resize(n + nv)
	var src := []
	src.resize(n)
	for i in n:
		raw[i] = (pieces[i] as Dictionary).get("altitude", 0.0)
		src[i] = alt_of(pieces[i])
	for i in nv:
		raw[n + i] = view_levels[i]
	_lv_raw = raw
	src.append_array(view_levels)
	if pieces.is_empty():
		# Carte sans pièce : le rez-de-chaussée existe toujours.
		src.append(0.0)
	_lv = merge_alts(src)
	if _lv.is_empty():
		_lv = [0.0]
	return _lv


## Fige les niveaux pendant un contrôle (boucles chaudes : level_of sur
## chaque élément) ; thaw_levels le termine. Les appels s'emboîtent.
func freeze_levels() -> void:
	if _lv_frozen == 0:
		levels()
		_lv_frame = Engine.get_process_frames()
		_lv_rooms = pieces.size()
		_through_memo = {}
	_lv_frozen += 1


func thaw_levels() -> void:
	_lv_frozen = maxi(0, _lv_frozen - 1)


func level_count() -> int:
	return levels().size()


## Altitude du niveau `k` ; hors de la liste, un niveau tous les FLOOR_STEP m
## au-delà du premier ou du dernier.
func level_alt(k: int) -> float:
	return level_alt_in(levels(), k)


static func level_alt_in(lv: Array, k: int) -> float:
	if k < 0:
		return float(lv[0]) + k * FLOOR_STEP
	if k >= lv.size():
		return float(lv[-1]) + (k - lv.size() + 1) * FLOOR_STEP
	return float(lv[k])


## Indice du niveau d'altitude `alt` (à ALT_EQ près), -1 s'il n'existe pas.
func level_index(alt: float) -> int:
	return level_index_in(levels(), alt)


static func level_index_in(lv: Array, alt: float) -> int:
	var i := lv.bsearch(alt)
	# Voisins i - 1 puis i (sans tableau : appelé pour chaque élément).
	if i >= 1 and i - 1 < lv.size() and absf(float(lv[i - 1]) - alt) <= ALT_EQ:
		return i - 1
	if i < lv.size() and absf(float(lv[i]) - alt) <= ALT_EQ:
		return i
	return -1


## Niveau (indice) d'un élément, -1 si aucune pièce n'est à son altitude.
func level_of(e: Dictionary) -> int:
	return level_index(alt_of(e))


## Niveau le plus proche de l'altitude `alt`.
func nearest_level(alt: float) -> int:
	var lv := levels()
	var best := 0
	for k in lv.size():
		if absf(float(lv[k]) - alt) < absf(float(lv[best]) - alt):
			best = k
	return best


## Altitude décalée de `dk` niveaux dans la liste `lv` (relevée AVANT tout
## changement : déplacer des pièces change les niveaux) ; une altitude hors
## des niveaux est décalée comme son plus proche niveau.
static func alt_shifted(lv: Array, alt: float, dk: int) -> float:
	if dk == 0:
		return alt
	var k := level_index_in(lv, alt)
	if k < 0:
		var best := 0
		for i in lv.size():
			if absf(float(lv[i]) - alt) < absf(float(lv[best]) - alt):
				best = i
		return alt + level_alt_in(lv, best + dk) - float(lv[best])
	return level_alt_in(lv, k + dk)


## Décale un élément de `dk` niveaux (liste `lv` relevée avant tout
## changement) : son altitude, et pour un escalier son arrivée.
static func shift_levels(e: Dictionary, lv: Array, dk: int) -> void:
	if dk == 0:
		return
	if String(e.get("type", "")) == "escalier":
		e["altitude_haut"] = alt_shifted(lv, stair_top(e), dk)
	e["altitude"] = alt_shifted(lv, alt_of(e), dk)


## Monte (ou descend) un élément de `dalt` m : son altitude, et pour un
## escalier son arrivée.
static func shift_alt(e: Dictionary, dalt: float) -> void:
	if dalt == 0.0:
		return
	if String(e.get("type", "")) == "escalier":
		e["altitude_haut"] = snappedf(stair_top(e) + dalt, 0.0001)
	e["altitude"] = snappedf(alt_of(e) + dalt, 0.0001)


## Met l'élément au niveau `k` (altitude du niveau) ; un escalier garde son
## arrivée si c'est un niveau plus haut (escalier qui saute des niveaux,
## escalier qui descend posé depuis son arrivée), sinon il monte au niveau suivant.
func set_level(e: Dictionary, k: int) -> void:
	var lv := levels()
	var a := level_alt_in(lv, k)
	e["altitude"] = a
	if String(e.get("type", "")) == "escalier":
		var top := stair_top(e) if e.has("altitude_haut") else -INF
		if not (top > a + ALT_EQ and level_index_in(lv, top) >= 0):
			e["altitude_haut"] = level_alt_in(lv, k + 1)


## Pièces hautes qui traversent le niveau `k` (vide et murs à ce niveau) :
## pièces d'un niveau plus bas, quel qu'il soit, dont le plafond dépasse le
## sol du niveau `k` de HIGH_CLEAR au moins (l'ancienne « double hauteur »,
## généralisée à tous les niveaux traversés). Seulement les niveaux à
## MIN_STACK m au moins au-dessus de son sol (là où une pièce peut être posée
## au-dessus d'elle : mezzanine) ; un demi-niveau posé à côté ne la coupe pas
## (ses murs montent d'un seul tenant, une porte du bas n'a pas de dalle à 1,2 m).
func rooms_through(k: int) -> Array:
	if k <= 0 or k >= level_count():
		return []
	# Contrôle en cours (freeze_levels) : relu une fois par niveau.
	var memo := _lv_frozen > 0 and _lv_frame == Engine.get_process_frames() and _lv_rooms == pieces.size()
	if memo and _through_memo.has(k):
		return _through_memo[k]
	var sol := level_alt(k)
	var out := []
	for p in pieces:
		if alt_of(p) <= sol - MIN_STACK + ALT_EQ and room_top(p) >= sol + HIGH_CLEAR - ALT_EQ:
			out.append(p)
	if memo:
		_through_memo[k] = out
	return out


## Mémoire de rooms_through pendant un contrôle (freeze_levels).
var _through_memo: Dictionary = {}


## La pièce `p` traverse-t-elle un niveau au-dessus du sien (pièce haute) ?
func is_high(p: Dictionary) -> bool:
	var k := level_of(p)
	if k < 0:
		return false
	var lv := levels()
	var a := alt_of(p)
	for j in range(k + 1, lv.size()):
		if float(lv[j]) - a >= MIN_STACK - ALT_EQ:
			return room_top(p) >= float(lv[j]) + HIGH_CLEAR - ALT_EQ
	return false


## Recouvrement vertical (format 17, niveaux libres) : deux pièces qui se
## recouvrent en plan sont à MIN_STACK m au moins l'une de l'autre (hauteur
## sous plafond 2,8 m + dalle) ; côte à côte, n'importe quel écart (demi-
## niveau). Première paire fautive dont l'une des pièces est dans `ids`
## (toutes les paires : []) : {a, b (pièces), d (écart, m)} ; {} sinon.
## Préfiltre par boîtes englobantes (MapGeom.overlap).
func stack_issue(ids: Array = []) -> Dictionary:
	# Altitudes, contours et boîtes lus une fois (paires : n² sinon).
	var alts := PackedFloat64Array()
	var polys := []
	var boxes := []
	for p in pieces:
		alts.append(alt_of(p))
		var poly := room_poly(p)
		polys.append(poly)
		boxes.append(MapGeom.bbox(poly).grow(-MapGeom.EPS))
	for i in pieces.size():
		var a: Dictionary = pieces[i]
		if not ids.is_empty() and not ids.has(String(a.get("id", ""))):
			continue
		for j in pieces.size():
			if j == i or (ids.is_empty() and j < i):
				continue
			var d := absf(alts[i] - alts[j])
			if d > ALT_EQ and d < MIN_STACK - ALT_EQ and (boxes[i] as Rect2).intersects(boxes[j]) and MapGeom.overlap(polys[i], polys[j]):
				return {"a": a, "b": pieces[j], "d": d}
	return {}


## Texte d'un recouvrement vertical (stack_issue) : [fr, en] ; ["", ""] sans problème.
static func stack_text(si: Dictionary) -> Array:
	if si.is_empty():
		return ["", ""]
	var a: Dictionary = si.a
	var b: Dictionary = si.b
	return ["les pièces « %s » (%s) et « %s » (%s) se recouvrent à %s l'une de l'autre : il faut %s au moins entre deux pièces empilées (hauteur sous plafond 2,8 m + dalle)" % [
			a.get("nom", a.get("id", "")), alt_text(alt_of(a)), b.get("nom", b.get("id", "")), alt_text(alt_of(b)), alt_text(float(si.d)), alt_text(MIN_STACK)],
		"rooms \"%s\" (%s) and \"%s\" (%s) overlap %s apart: stacked rooms must be at least %s apart (2.8 m ceiling + slab)" % [
			a.get("nom", a.get("id", "")), alt_text(alt_of(a), false), b.get("nom", b.get("id", "")), alt_text(alt_of(b), false), alt_text(float(si.d), false), alt_text(MIN_STACK, false)]]


## Déplace le niveau `k` de `dalt` m : tout ce qui y est posé, et l'arrivée
## des escaliers qui y montent.
func shift_level(k: int, dalt: float) -> void:
	var a := level_alt(k)
	for list in [pieces, ouvertures, objets]:
		for e in list:
			var top_here: bool = String(e.get("type", "")) == "escalier" and absf(stair_top(e) - a) <= ALT_EQ
			if absf(alt_of(e) - a) <= ALT_EQ:
				e["altitude"] = snappedf(alt_of(e) + dalt, 0.0001)
			if top_here:
				e["altitude_haut"] = snappedf(stair_top(e) + dalt, 0.0001)
	for i in view_levels.size():
		if absf(float(view_levels[i]) - a) <= ALT_EQ:
			view_levels[i] = float(view_levels[i]) + dalt


## Texte d'une altitude : « 3,5 m » (`fr` : virgule décimale).
static func alt_text(a: float, fr := true) -> String:
	var t := ("%.2f" % snappedf(a, 0.01)).rstrip("0").trim_suffix(".")
	if t == "-0":
		t = "0"
	return (t.replace(".", ",") if fr else t) + " m"


## Nom d'un niveau dans la langue du jeu : « Niveau 3,5 m » / « Level 3.5 m ».
static func level_name(a: float) -> String:
	return Lang.t("Niveau %s" % alt_text(a), "Level %s" % alt_text(a, false))


func find(eid: String) -> Dictionary:
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == eid:
				return e
	return {}


## Liste qui contient l'élément `eid` (pieces, ouvertures, objets ou zones).
func list_of(eid: String) -> Array:
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == eid:
				return list
	return []


func remove(eid: String) -> void:
	var list := list_of(eid)
	for i in list.size():
		if String(list[i].get("id", "")) == eid:
			list.remove_at(i)
			return


## Pièces, ouvertures, objets posés au niveau `k` (même altitude à ALT_EQ près).
func rooms_on(k: int) -> Array:
	return _on(pieces, k)


func openings_on(k: int) -> Array:
	return _on(ouvertures, k)


func objects_on(k: int) -> Array:
	return _on(objets, k)


func _on(list: Array, k: int) -> Array:
	if k < 0 or k >= level_count():
		return []
	var a := level_alt(k)
	return list.filter(func(e): return absf(alt_of(e) - a) <= ALT_EQ)


func zone(zid: String) -> Dictionary:
	for z in zones:
		if String(z.id) == zid:
			return z
	return {}


func zone_name(zid: String) -> String:
	var z := zone(zid)
	if z.is_empty():
		return zid
	var n: Dictionary = z.get("nom", {})
	return Lang.t(String(n.get("fr", zid)), String(n.get("en", n.get("fr", zid))))


func rooms_of_zone(zid: String) -> Array:
	return pieces.filter(func(p): return String(p.get("zone", "")) == zid)


func room_poly(p: Dictionary) -> PackedVector2Array:
	return MapGeom.poly(p.get("contour", []))


## Nouvel identifiant stable : préfixe + premier numéro libre.
func new_id(prefix: String) -> String:
	var used := {}
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			used[String(e.get("id", ""))] = true
	var n := 1
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


## Nouvelle zone (nom par défaut « Zone N »).
func add_zone(name_fr := "", name_en := "") -> Dictionary:
	var zid := new_id("z")
	var n := zones.size() + 1
	var z := {"id": zid, "nom": {"fr": name_fr if name_fr != "" else "Zone %d" % n, "en": name_en if name_en != "" else "Zone %d" % n}}
	zones.append(z)
	if depart == "":
		depart = zid
	return z


## Zones sans pièce retirées, zone de départ toujours valide.
func tidy_zones() -> void:
	var used := {}
	for p in pieces:
		used[String(p.get("zone", ""))] = true
	zones = zones.filter(func(z): return used.has(String(z.id)))
	if zone(depart).is_empty():
		depart = String(zones[0].id) if not zones.is_empty() else ""


# ------------------------------------------------------------------ copie (annuler / rétablir)

## Les définitions des prefabs de la carte (format 10) en font partie (clé
## « prefabs », seulement s'il y en a : une carte sans prefab garde la forme
## d'avant) ; leurs modèles (base64, lourds) non : ils restent dans `models`.
func to_dict() -> Dictionary:
	var d := {"carte": carte, "pieces": pieces, "ouvertures": ouvertures, "objets": objets, "zones": zones, "depart": depart}
	if not prefabs.is_empty():
		d["prefabs"] = prefabs
	# Format 15 : définitions des textures (leurs images restent dans texture_files).
	if not textures.is_empty():
		d["textures"] = textures
	return d


func snapshot() -> Dictionary:
	return to_dict().duplicate(true)


func restore(s: Dictionary) -> void:
	var d := s.duplicate(true)
	carte = d.get("carte", {})
	pieces = d.get("pieces", [])
	ouvertures = d.get("ouvertures", [])
	objets = d.get("objets", [])
	zones = d.get("zones", [])
	depart = String(d.get("depart", ""))
	# Prefabs (carte entière reçue d'une session : contrôlés un par un).
	prefabs = {}
	var pf: Variant = d.get("prefabs", {})
	if pf is Dictionary:
		for pid in pf:
			if MapPrefabLib.pid_ok(pid):
				var def := MapPrefabLib.sanitize(pf[pid])
				if not def.is_empty():
					prefabs[pid] = def
	activate_prefabs()
	textures = MapTextureLib.read_snapshot(d.get("textures", {}))


func duplicate_map() -> EditorMap:
	var m := EditorMap.new()
	m.restore(snapshot())
	m.models = models.duplicate()
	m.texture_files = texture_files.duplicate()
	m.view_levels = view_levels.duplicate()
	return m


## Deux cartes identiques (contenu des cinq fichiers et des prefabs) ?
func same_as(other: EditorMap) -> bool:
	return file_texts() == other.file_texts()


# ------------------------------------------------------------------ prefabs de la carte (format 10)

## Rend les prefabs de cette carte visibles du catalogue (inventaire, pose,
## validateur, export) : MapCatalog.set_map_prefabs (fil principal seulement).
func activate_prefabs() -> void:
	MapCatalog.set_map_prefabs(prefabs)


## Ajoute (ou remplace) le prefab `pid` ; `glb` : octets du modèle importé.
## Aucun nombre maximal de prefabs ni de modèles (pas de quota).
func set_prefab(pid: String, def: Dictionary, glb := PackedByteArray()) -> bool:
	var s := MapPrefabLib.sanitize(def)
	if s.is_empty() or not MapPrefabLib.pid_ok(pid):
		return false
	if MapPrefabLib.is_model(s):
		if not glb.is_empty():
			models[pid] = Marshalls.raw_to_base64(glb)
		elif not models.has(pid):
			return false
	else:
		models.erase(pid)
	prefabs[pid] = s
	activate_prefabs()
	return true


func remove_prefab(pid: String) -> void:
	prefabs.erase(pid)
	models.erase(pid)
	activate_prefabs()


func model_count() -> int:
	return prefabs.keys().filter(func(p): return MapPrefabLib.is_model(prefabs[p])).size()


## Octets du modèle importé du prefab `pid` (vide s'il n'en a pas).
func model_bytes(pid: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(String(models[pid])) if models.has(pid) else PackedByteArray()


## Objets posés qui citent le prefab `pid`.
func prefab_users(pid: String) -> Array:
	var r := MapPrefabLib.ref(pid)
	return objets.filter(func(o): return String(o.get("type", "")) == "prefab" and String(o.get("prefab", "")) == r)


## Entrées de prefab des textes de la carte (MapPrefabLib.def_key / model_key).
func prefab_texts() -> Dictionary:
	var out := {}
	var ids := prefabs.keys()
	ids.sort()
	for pid in ids:
		out[MapPrefabLib.def_key(pid)] = MapPrefabLib.def_text(prefabs[pid])
		if MapPrefabLib.is_model(prefabs[pid]) and models.has(pid):
			out[MapPrefabLib.model_key(pid)] = String(models[pid])
	return out


## Lit les entrées de prefab parmi des textes (from_texts) ; les illisibles
## sont ignorées avec un message (load_errors).
func _read_prefab_texts(texts: Dictionary) -> void:
	prefabs = {}
	models = {}
	var keys := texts.keys().filter(func(k): return not MapPrefabLib.parse_key(k).is_empty())
	keys.sort()
	for k in keys:
		var pk := MapPrefabLib.parse_key(k)
		if pk[1] != MapPrefabLib.DEF_FILE:
			continue
		var pid := String(pk[0])
		var j := JSON.new()
		var bad: Array = ["JSON illisible", "unreadable JSON"] if j.parse(String(texts[k])) != OK else MapPrefabLib.check_def(j.data)
		if not bad.is_empty():
			load_errors.append(["prefab %s ignoré : %s" % [pid, bad[0]], "prefab %s ignored: %s" % [pid, bad[1]]])
			continue
		var def := MapPrefabLib.sanitize(j.data)
		prefabs[pid] = def
		var mk := MapPrefabLib.model_key(pid)
		if MapPrefabLib.is_model(def):
			if texts.has(mk) and texts[mk] is String:
				models[pid] = String(texts[mk])
			else:
				load_errors.append(["prefab %s : modèle %s absent (boîte à la place)" % [pid, MapPrefabLib.MODEL_FILE], "prefab %s: model %s missing (box instead)" % [pid, MapPrefabLib.MODEL_FILE]])


# ------------------------------------------------------------------ fichiers

## Contenu des cinq fichiers (JSON lisible : un élément par ligne). Les
## nombres entiers s'écrivent sans décimale (17 et non 17.0) : un fichier relu
## puis réenregistré est identique.
func file_texts() -> Dictionary:
	var c := carte.duplicate(true)
	c["format"] = FORMAT
	var out := {
		"carte.json": dump(_ints(c)),
		"pieces.json": dump(_ints({"pieces": pieces})),
		"ouvertures.json": dump(_ints({"ouvertures": ouvertures})),
		"objets.json": dump(_ints({"objets": _objets_out()})),
		"zones.json": dump(_ints({"depart": depart, "zones": zones})),
	}
	# Format 10 : prefabs de la carte, après les cinq fichiers (aucun : rien de plus).
	out.merge(prefab_texts())
	# Format 15 : textures de la carte.
	out.merge(MapTextureLib.texts_of(self))
	return out


## Objets tels qu'écrits : format 17, l'arrivée d'un escalier (« altitude_haut »)
## est toujours écrite (escalier créé en mémoire sans elle : le niveau suivant).
func _objets_out() -> Array:
	if not objets.any(func(o): return o is Dictionary and String(o.get("type", "")) == "escalier" and not o.has("altitude_haut")):
		return objets
	var out := []
	for o in objets:
		if o is Dictionary and String(o.get("type", "")) == "escalier" and not o.has("altitude_haut"):
			var c: Dictionary = o.duplicate()
			c["altitude_haut"] = stair_top_of(o)
			out.append(c)
		else:
			out.append(o)
	return out


static func _ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		# Jamais NaN ni infini dans un fichier (JSON invalide) : 0.
		if not is_finite(f):
			return 0
		if f == floorf(f) and absf(f) < 1e12:
			return int(f)
		return snappedf(f, 0.0001)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return _ints(x))
	return v


static func from_texts(texts: Dictionary) -> EditorMap:
	var m := EditorMap.new()
	var parsed := {}
	for f in FILES:
		if not texts.has(f):
			m.load_errors.append(["fichier %s absent" % f, "missing file %s" % f])
			parsed[f] = {}
			continue
		var j := JSON.new()
		if j.parse(String(texts[f])) != OK or not j.data is Dictionary:
			m.load_errors.append(["%s illisible (ligne %d : %s)" % [f, j.get_error_line(), j.get_error_message()],
				"%s unreadable (line %d: %s)" % [f, j.get_error_line(), j.get_error_message()]])
			parsed[f] = {}
			continue
		parsed[f] = j.data
	m.carte = parsed["carte.json"]
	if m.carte.is_empty():
		m.carte = blank().carte
	if int(m.carte.get("format", FORMAT)) > FORMAT:
		m.load_errors.append(["format %d plus récent que celui du jeu (%d)" % [int(m.carte.format), FORMAT],
			"format %d is newer than the game's (%d)" % [int(m.carte.format), FORMAT]])
	m.pieces = parsed["pieces.json"].get("pieces", [])
	m.ouvertures = parsed["ouvertures.json"].get("ouvertures", [])
	m.objets = parsed["objets.json"].get("objets", [])
	m.zones = parsed["zones.json"].get("zones", [])
	m.depart = String(parsed["zones.json"].get("depart", ""))
	m.format_read = int(m.carte.get("format", FORMAT))
	m.format_given = m.carte.has("format")
	m.strip_removed()
	m._read_prefab_texts(texts)
	MapTextureLib.read_texts(m, texts)
	m._migrate(m.format_read)
	m._normalize()
	m.activate_prefabs()
	m._tidy_scale()
	return m


## Retire les objets des types retirés du jeu (MapCatalog.REMOVED_TYPES :
## atouts, armes murales, achats de grenades, Pack-a-Punch). Une carte d'avant
## se charge encore ; ces objets sont ignorés avec un avertissement
## (push_warning, et une note pour l'utilisateur : load_notes). Rend le
## nombre d'objets retirés.
func strip_removed() -> int:
	var kept := []
	var n := 0
	for o in objets:
		if o is Dictionary and String(o.get("type", "")) in MapCatalog.REMOVED_TYPES:
			n += 1
			continue
		kept.append(o)
	if n == 0:
		return 0
	objets = kept
	push_warning("[EditorMap] %d objet(s) retiré(s) du jeu ignoré(s) (atouts, armes murales, grenades, Pack-a-Punch)" % n)
	load_notes.append(["%d objet(s) qui n'existent plus ignorés (atouts, armes murales, grenades, Pack-a-Punch)" % n,
		"%d object(s) that no longer exist ignored (perks, wall weapons, grenades, Pack-a-Punch)" % n])
	return n


## Mise à niveau d'une carte d'un format plus ancien (elle sera écrite au
## format FORMAT à l'enregistrement).
func _migrate(from: int) -> void:
	if from < 2:
		# Format 1 -> 2 : rien à convertir (nouvelles clés facultatives) ;
		# les lampes, caisses et barils du format 1 restent des types admis.
		pass
	if from < 3:
		# Format 2 -> 3 : rien à convertir (« angle » facultatif : sans lui, un
		# objet mural suit « mur » comme avant).
		pass
	if from < 4:
		# Format 3 -> 4 : rien à convertir (« forme », « rot » des rectangles et
		# murs courbes facultatifs ; « rot » du décor : 0, 90, 180 ou 270 comme avant).
		pass
	if from < 5:
		# Format 4 -> 5 : rien à convertir (« variante » facultative : sans elle,
		# l'aspect d'avant ; « bloc_invisible » : un nouveau type).
		pass
	if from < 6:
		# Format 5 -> 6 : rien à convertir (escalier sans « variante » : droit,
		# sans réglage : comme avant).
		pass
	if from < 7:
		# Format 6 -> 7 : rien à convertir (applique sans « hauteur » : à 2 m,
		# comme avant ; le décor garde sa position).
		pass
	if from < 8:
		# Format 7 -> 8 : rien à convertir (fenêtre sans « variante » : la
		# fenêtre d'avant, même découpe, mêmes planches).
		pass
	if from < 9:
		# Format 8 -> 9 : barrière invisible rectangle -> polygone de ses 4
		# coins (fait par _normalize pour tout fichier, même écrit à la main) ;
		# pas de « chevauchement_decor » : les règles de pose d'avant.
		pass
	if from < 10:
		# Format 9 -> 10 : rien à convertir (pas de dossier prefabs/ : aucun
		# prefab de la carte ; le décor du catalogue garde sa clé « prefab »).
		pass
	if from < 11:
		# Format 10 -> 11 : effets purs. Les objets que construisait un effet
		# (bûches, torche, tuyau...) deviennent des décors posés à côté de lui,
		# au même endroit ; « taille » devient la zone (MapCatalog.tidy_effect,
		# _normalize). Une seule fois : la carte est réécrite au format 11.
		split_legacy_effects()
	if from < 12:
		# Format 11 -> 12 : rien à convertir (sans « z », « descente » ni
		# « hauteur » au sol : les hauteurs d'avant).
		pass
	if from < 13:
		# Format 12 -> 13 : volume des effets. Chaque effet garde sa taille
		# (zone par défaut d'avant écrite, « taille » d'avant convertie) et sa
		# place (« hauteur » écrite décalée) : MapCatalog.migrate_effect_13.
		for o in objets:
			if o is Dictionary:
				MapCatalog.migrate_effect_13(o)
	if from < 14:
		# Format 13 -> 14 : rien à convertir (sans « echelle » ni « incl » : le
		# décor garde sa taille et reste droit, comme avant).
		pass
	for o in objets:
		if not (o is Dictionary and String(o.get("type", "")) == "boite"):
			continue
		# Sans « format » (fichier écrit à la main) : une boîte sans « mur » ni
		# « rot » est lue comme avant le format 15 (contre le mur nord) ; avec
		# « rot » (clé du format 15), c'est bien une boîte au sol.
		var old_box: bool = from < 15 or (not format_given and not o.has("rot"))
		if old_box and not o.has("mur"):
			# Format 14 -> 15 : une boîte sans « mur » (fichier écrit à la main)
			# était contre le mur nord ; au format 15 elle serait au sol.
			o["mur"] = "n"
		if o.has("mur"):
			# Boîte murale : jamais de « rot » (celle-ci est pour la boîte au sol).
			o.erase("rot")
	if from < 16:
		# Format 15 -> 16 : rien à convertir (pas de dossier textures/ : aucune
		# texture de la carte ; les surfaces du jeu restent des clés de WorldLook).
		pass
	# Format 16 -> 17 : niveaux libres, EN DERNIER (les conversions d'avant
	# lisent encore « etage »). Aussi pour un fichier écrit à la main au
	# format 17 qui garde des clés d'étage.
	if from < 17 or has_legacy_levels(carte, pieces, ouvertures, objets):
		migrate_levels()


## Clés d'étage (format 16 et avant) dans la carte ou ses éléments ?
static func has_legacy_levels(c: Dictionary, rooms: Array, openings: Array, objects: Array) -> bool:
	if c.has("etages"):
		return true
	for list in [rooms, openings, objects]:
		for e in list:
			if e is Dictionary and (e.has("etage") or e.has("double_hauteur")):
				return true
	return false


## Format 16 -> 17 (docs/LEVELS_PLAN.md § 2) :
##   1. sol et hauteur de chaque ancien étage (absents : k × 3,5 m et 3,2 m) ;
##   2. pièce de l'étage k : altitude = son sol ; sans « plafond », celui de
##      l'étage (écrit s'il diffère de 3,2 m) ; « double_hauteur » avec un étage
##      au-dessus : plafond jusqu'en haut de l'étage du dessus (pièce haute) ;
##      pièce entièrement recouverte par des pièces de l'étage du dessus :
##      plafond porté au moins au dessous de leur dalle (même aspect qu'avant :
##      le plafond était la dalle) ;
##   3. ouvertures, objets : altitude = sol de leur étage ; escalier : arrivée
##      au sol de l'étage du dessus (sinon 3,5 m plus haut : l'erreur reste) ;
##   4. « etages », « etage » et « double_hauteur » retirés.
## Un élément sans « etage » est à l'étage 0 ; un élément qui a déjà une
## « altitude » (fichier au format 17 écrit à la main) la garde.
func migrate_levels() -> void:
	var et: Variant = carte.get("etages", [])
	var sols := []
	var hs := []
	if et is Array:
		for k in (et as Array).size():
			var f: Variant = et[k]
			var fd: Dictionary = f if f is Dictionary else {}
			var sv: Variant = fd.get("sol", k * FLOOR_STEP)
			var hv: Variant = fd.get("hauteur", DEFAULT_CEILING)
			sols.append(float(sv) if (sv is float or sv is int) and is_finite(float(sv)) else k * FLOOR_STEP)
			hs.append(float(hv) if (hv is float or hv is int) and is_finite(float(hv)) else DEFAULT_CEILING)
	var n := maxi(1, sols.size())
	var sol := func(k: int) -> float: return float(sols[k]) if k >= 0 and k < sols.size() else k * FLOOR_STEP
	var hgt := func(k: int) -> float: return float(hs[k]) if k >= 0 and k < hs.size() else DEFAULT_CEILING
	var floor_of := func(e: Dictionary) -> int:
		var v: Variant = e.get("etage", 0)
		return int(v) if (v is float or v is int) and is_finite(float(v)) else 0
	# Pièces de chaque étage (avant tout changement) : recouvrement par le dessus.
	var by_floor := {}
	for p in pieces:
		if p is Dictionary and (p.has("etage") or not p.has("altitude")):
			(by_floor.get_or_add(floor_of.call(p), []) as Array).append(p)
	for p in pieces:
		if not p is Dictionary or (p.has("altitude") and not p.has("etage")):
			if p is Dictionary:
				p.erase("double_hauteur")
			continue
		var k: int = floor_of.call(p)
		var base: float = sol.call(k)
		var ch := float(p.plafond) if (p.get("plafond") is float or p.get("plafond") is int) and is_finite(float(p.plafond)) else float(hgt.call(k))
		if bool(p.get("double_hauteur", false)) and k + 1 < n:
			ch = float(sol.call(k + 1)) + float(hgt.call(k + 1)) - base
		elif k + 1 < n and _covered_by(p, by_floor.get(k + 1, [])):
			ch = maxf(ch, float(sol.call(k + 1)) - MapValidator.DALLE - base)
		p["altitude"] = base
		if absf(ch - DEFAULT_CEILING) > 0.0005:
			p["plafond"] = snappedf(ch, 0.0001)
		else:
			p.erase("plafond")
		p.erase("etage")
		p.erase("double_hauteur")
	for list in [ouvertures, objets]:
		for o in list:
			if not o is Dictionary or (o.has("altitude") and not o.has("etage")):
				continue
			var k: int = floor_of.call(o)
			o["altitude"] = sol.call(k)
			if String(o.get("type", "")) == "escalier":
				o["altitude_haut"] = sol.call(k + 1) if k + 1 < n else float(sol.call(k)) + FLOOR_STEP
			o.erase("etage")
	carte.erase("etages")


## Pièce `p` entièrement recouverte par les pièces `above` (chaque case
## intérieure sous l'une d'elles) ?
static func _covered_by(p: Dictionary, above: Array) -> bool:
	if above.is_empty():
		return false
	var cells: Array = MapRaster.room_cells(MapGeom.poly(p.get("contour", [])))[1]
	if cells.is_empty():
		return false
	var polys := above.map(func(q): return MapGeom.poly(q.get("contour", [])))
	for c in cells:
		var at := MapGeom.cell_center(c)
		if not polys.any(func(poly): return Geometry2D.is_point_in_polygon(at, poly)):
			return false
	return true


## Format 14 : « echelle » et « incl » remises en ordre (MapScale.tidy), après
## l'activation des prefabs de la carte (un prefab qui contient un objet de
## jeu ne change pas d'échelle : clé retirée, avec un message de chargement).
func _tidy_scale() -> void:
	for o in objets:
		if o is Dictionary:
			var msg := MapScale.tidy(o)
			if not msg.is_empty():
				load_errors.append(msg)


## Format 11 : décor de chaque effet d'avant (MapCatalog.split_legacy_effect),
## ajouté à la carte ; jamais deux fois le même décor au même endroit.
## Rend le nombre de décors ajoutés.
func split_legacy_effects() -> int:
	var added := []
	# Identifiants libres : ni dans la carte, ni déjà donnés par la conversion.
	var issued := {}
	var next_id := func(prefix: String) -> String:
		var i := 1
		while issued.has("%s%d" % [prefix, i]) or not find("%s%d" % [prefix, i]).is_empty():
			i += 1
		issued["%s%d" % [prefix, i]] = true
		return "%s%d" % [prefix, i]
	for o in objets:
		if o is Dictionary and String(o.get("type", "")) == "effet":
			added.append_array(MapCatalog.split_legacy_effect(o, objets + added, next_id))
	objets.append_array(added)
	return added.size()


## Version du format lue dans carte.json (FORMAT pour une carte neuve).
var format_read := FORMAT
## Faux : carte.json sans clé « format » (écrite à la main). Lue au format
## courant, sauf pour la caisse au hasard (_migrate) : le cas ambigu se lit comme
## avant le format 15.
var format_given := true


## Valeurs lues du JSON remises au bon type (étages entiers, identifiants en texte).
func _normalize() -> void:
	for list in [pieces, ouvertures, objets]:
		for e in list:
			e["id"] = String(e.get("id", ""))
			# Format 17 : altitude finie (0 sinon).
			e["altitude"] = alt_of(e)
	for p in pieces:
		# Plafond masqué : « sans_plafond » vrai seulement, jamais écrit à faux.
		if p.has("sans_plafond"):
			set_no_ceiling(p, no_ceiling(p))
		# Forme de base illisible (fichier écrit à la main) : la pièce reste un polygone.
		if p.has("forme") and not MapShapes.valid(p.forme):
			p.erase("forme")
		elif p.has("forme") and p.forme.has("points"):
			p.forme["points"] = clampi(int(p.forme.points), MapShapes.MIN_POINTS, MapShapes.MAX_POINTS)
	for o in objets:
		if o.has("rot"):
			var rv = o.rot
			o["rot"] = posmod(roundi(float(rv)), 360) if (rv is float or rv is int) and is_finite(float(rv)) else 0
		if String(o.get("type", "")) == "mur_courbe" and o.has("segments"):
			o["segments"] = clampi(int(o.segments), MapShapes.MIN_SEGMENTS, MapShapes.MAX_SEGMENTS)
		if o.has("angle"):
			var ang := float(o.angle) if (o.angle is float or o.angle is int) else NAN
			if is_finite(ang):
				o["angle"] = snappedf(fposmod(ang, 360.0), 0.01)
			else:
				o.erase("angle")
	# Variante inconnue ou par défaut (fichier écrit à la main) : clé retirée,
	# l'élément garde l'aspect par défaut.
	for list in [ouvertures, objets]:
		for e in list:
			if e.has("variante") and (not MapCatalog.variants(String(e.get("type", ""))).has(e.variante) \
					or e.variante == MapCatalog.default_variant(String(e.get("type", "")))):
				e.erase("variante")
	# Réglages d'escalier illisibles ou par défaut retirés (format 6).
	for o in objets:
		MapCatalog.tidy_stair(o)
		# Réglages d'un effet (format 10) : illisibles ou par défaut retirés.
		MapCatalog.tidy_effect(o)
	# Hauteur d'une applique (format 7) : illisible, par défaut ou sur un
	# luminaire qui n'est pas mural, retirée ; sinon bornée.
	# Format 11 : de même pour un décor mural ; un décor qui n'est pas mural n'a
	# ni « mur », ni « angle », ni « hauteur » ; un décor mural, pas de « rot ».
	for o in objets:
		var t := String(o.get("type", ""))
		if t == "prefab":
			if MapCatalog.light_mount(o) == "mur":
				o.erase("rot")
			else:
				for key in ["mur", "angle", "hauteur"]:
					o.erase(key)
		if o.has("hauteur") and t in ["luminaire", "prefab"]:
			if t == "luminaire" and MapCatalog.light_mount(o) == "sol":
				# Format 12 : hauteur d'un luminaire au sol (m), bornée.
				var hv: Variant = o.hauteur
				if (hv is float or hv is int) and is_finite(float(hv)):
					o["hauteur"] = snappedf(clampf(float(hv), 0.0, MapCatalog.WALL_LIGHT_HEIGHT[1]), 0.01)
				else:
					o.erase("hauteur")
			else:
				MapCatalog.set_wall_light_height(o, float(o.hauteur) if (o.hauteur is float or o.hauteur is int) else NAN)
		# Format 12 : « z », « descente » illisibles, hors de leur type ou par défaut retirées.
		MapVertical.tidy(o)
	# Barrière invisible (format 9) : un polygone « sommets » ; un rectangle
	# d'avant (« rect », « rot ») devient le polygone de ses 4 coins.
	for o in objets:
		if String(o.get("type", "")) == "bloc_invisible":
			normalize_clip(o)
	# Ciel de la carte illisible ou par défaut : retiré.
	tidy_sky(carte)
	# Réglage « chevauchement_decor » illisible ou faux : retiré (règles d'avant).
	if carte.has(MapCatalog.OVERLAP_KEY) and not (carte[MapCatalog.OVERLAP_KEY] is bool and carte[MapCatalog.OVERLAP_KEY]):
		carte.erase(MapCatalog.OVERLAP_KEY)
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == "":
				e["id"] = new_id("x")
	# Identifiant en double (fichier écrit à la main) : le contrôle de
	# légitimité refuserait la carte en jeu ; le second reçoit un numéro libre.
	var seen := {}
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			var eid := String(e.id)
			if seen.has(eid):
				var prefix := eid.rstrip("0123456789")
				e["id"] = new_id(prefix if prefix != "" else "x")
			seen[String(e.id)] = true
	# Escalier sans arrivée (fichier écrit à la main) : premier niveau au-dessus
	# dont une pièce contient le haut des marches, sinon 3,5 m plus haut.
	for o in objets:
		if String(o.get("type", "")) == "escalier":
			o["altitude_haut"] = stair_top(o) if o.has("altitude_haut") else guess_stair_top(o)
	if zone(depart).is_empty() and not zones.is_empty():
		depart = String(zones[0].id)


## Arrivée d'un escalier sans « altitude_haut » : le premier niveau au-dessus
## de son pied dont une pièce contient le haut des marches, sinon 3,5 m plus haut.
func guess_stair_top(o: Dictionary) -> float:
	var a := alt_of(o)
	var fr := MapRaster.stair_frame(o)
	var top: Vector2 = fr.center + (fr.up as Vector2) * (float(fr.length) * 0.5 + 0.3)
	for la in levels():
		if float(la) > a + ALT_EQ:
			for p in pieces:
				if absf(alt_of(p) - float(la)) <= ALT_EQ and MapGeom.contains(room_poly(p), top):
					return float(la)
	return a + FLOOR_STEP


## Barrière invisible lue d'un fichier (format 9) : ses « sommets » lisibles
## gardés au millimètre ; sinon le rectangle d'avant (« rect », « rot »)
## devient le polygone de ses 4 coins (même place, même collision) et ces deux
## clés disparaissent. Hauteur illisible ou trop basse retirée (jusqu'au
## plafond), trop haute bornée.
static func normalize_clip(o: Dictionary) -> void:
	var num := func(x: Variant) -> bool: return (x is float or x is int) and is_finite(float(x))
	var pts := []
	var s: Variant = o.get("sommets")
	if s is Array:
		for p in s:
			if p is Array and p.size() == 2 and num.call(p[0]) and num.call(p[1]):
				pts.append(MapGeom.arr(Vector2(float(p[0]), float(p[1]))))
		o["sommets"] = pts
	else:
		var r: Variant = o.get("rect")
		if r is Array and r.size() == 4 and r.all(func(x): return num.call(x)):
			o["sommets"] = MapGeom.poly_arr(MapRaster.rect_poly(o))
			o.erase("rect")
			o.erase("rot")
	if o.has("sommets"):
		o.erase("rect")
		o.erase("rot")
	if o.has("hauteur"):
		var hv: Variant = o.hauteur
		if not num.call(hv) or float(hv) < MapCatalog.CLIP_HEIGHT[0]:
			o.erase("hauteur")
		else:
			o["hauteur"] = snappedf(minf(float(hv), MapCatalog.CLIP_HEIGHT[1]), 0.01)


func save_dir(dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return err
	var texts := file_texts()
	for f in FILES:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		if fa == null:
			return FileAccess.get_open_error()
		fa.store_string(texts[f])
		fa.close()
	# Format 10 : prefabs/<pid>/prefab.json et model.glb (les prefabs retirés
	# de la carte sont effacés du dossier).
	var perr := MapPrefabLib.write_dir(dir, texts)
	if perr != OK:
		return perr
	# Format 15 : textures/<tid>/texture.json et ses images.
	return MapTextureLib.write_dir(dir, texts)


## Limites des fichiers lus (cartes reçues, archives : jamais de lecture sans
## borne). Une carte réelle pèse quelques dizaines de Ko.
const MAX_FILE_BYTES := 2 * 1024 * 1024
const MAX_ARCHIVE_BYTES := 2 * 1024 * 1024
const MAX_ARCHIVE_ENTRIES := 32
## Format 10 : une archive qui porte des prefabs de la carte n'a pas de
## taille ni de nombre d'entrées de prefab maximal (pas de quota : seulement
## la structure du .zip sans ZIP64, 4 Go et 65 535 entrées) ; les entrées de
## prefab ne comptent pas dans MAX_ARCHIVE_ENTRIES. Seule sûreté de taille :
## pas de « bombe » de compression (CustomMapGuard.zip_bomb).


## Texte d'un fichier de `max_bytes` au plus ; null s'il est absent, illisible
## ou trop gros.
static func read_text(path: String, max_bytes := MAX_FILE_BYTES) -> Variant:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null or fa.get_length() > max_bytes:
		return null
	return fa.get_as_text()


static func load_dir(dir: String) -> EditorMap:
	var texts := {}
	var too_big := []
	for f in FILES:
		var p := dir.path_join(f)
		if FileAccess.file_exists(p):
			var t = read_text(p)
			if t == null:
				too_big.append(f)
				continue
			texts[f] = t
	# Format 10 : prefabs de la carte (tailles bornées avant lecture).
	var pf := MapPrefabLib.read_dir(dir)
	texts.merge(pf.texts)
	# Format 15 : textures de la carte.
	var tx := MapTextureLib.read_dir(dir)
	texts.merge(tx.texts)
	(pf.reasons as Array).append_array(tx.reasons)
	var m := from_texts(texts)
	for f in too_big:
		m.load_errors.append(["%s trop gros (2 Mo au plus) ou illisible" % f, "%s too big (2 MB at most) or unreadable" % f])
	m.load_errors.append_array(pf.reasons)
	return m


static func is_map_dir(dir: String) -> bool:
	return dir != "" and FileAccess.file_exists(dir.path_join("carte.json"))


## Archive .zip : les cinq fichiers à la racine.
func export_zip(path: String) -> Error:
	var z := ZIPPacker.new()
	var err := z.open(path)
	if err != OK:
		return err
	var texts := file_texts()
	for f in texts:
		z.start_file(f)
		# Format 10 : un modèle importé est écrit en binaire (.glb).
		z.write_file(Marshalls.base64_to_raw(String(texts[f])) if String(f).ends_with(MapPrefabLib.MODEL_FILE) or MapTextureLib.is_binary_key(f) else String(texts[f]).to_utf8_buffer())
		z.close_file()
	return z.close()


## Archive venue d'ailleurs : contrôle de légitimité (CustomMapGuard) avant
## tout, tailles lues avant d'extraire, cinq JSON seulement (à la racine ou
## dans un dossier de l'archive). Refusée : carte vide avec les raisons.
## Deux barrières : d'abord la liste stricte des entrées (2 Mo, 32 entrées, cinq
## JSON et rien d'autre, lue dans le répertoire central), puis le contrôle commun
## aux cartes reçues en réseau.
static func import_zip(path: String) -> EditorMap:
	var pre := _precheck_zip(path)
	if not pre.is_empty():
		var bad := EditorMap.new()
		bad.load_errors.append(pre)
		return bad
	var got := CustomMapGuard.read_zip_texts(path)
	var refused: Array = got.reasons
	if refused.is_empty():
		refused = CustomMapGuard.check_texts(got.texts).reasons
	if not refused.is_empty():
		var m := EditorMap.new()
		m.load_errors = refused
		return m
	return from_texts(got.texts)


## Première barrière d'import_zip : [fr, en] si l'archive est refusée, [] sinon.
static func _precheck_zip(path: String) -> Array:
	var dir := zip_directory(path)
	if dir.has("error"):
		return dir.error
	var n: int = dir.size
	@warning_ignore("integer_division")
	var kb := n / 1024  # Ko entiers (troncature voulue)
	var listing := zip_entries(dir.bytes)
	if listing.has("error"):
		return listing.error
	# Sans prefab (format 10) : la limite d'avant, 2 Mo.
	var with_prefabs := (listing.entries as Array).any(func(e): return String(e.name).contains(MapPrefabLib.DIR + "/") or String(e.name).contains(MapTextureLib.DIR + "/"))
	if n > MAX_ARCHIVE_BYTES and not with_prefabs:
		return ["archive trop grosse (%d Ko, 2 Mo au plus)" % kb, "archive too big (%d KB, 2 MB at most)" % kb]
	return check_zip_entries(listing.entries, {})


## Vérifie les entrées d'une archive (zip_entries) ; remplit `wanted` (nom de
## base -> chemin) ; rend [fr, en] si l'archive est refusée, [] sinon.
static func check_zip_entries(entries: Array, wanted: Dictionary) -> Array:
	var plain := entries.filter(func(e): return not String(e.name).contains(MapPrefabLib.DIR + "/") and not String(e.name).contains(MapTextureLib.DIR + "/")).size()
	if plain > MAX_ARCHIVE_ENTRIES:
		return ["trop d'entrées dans l'archive (%d, %d au plus hors prefabs et textures)" % [plain, MAX_ARCHIVE_ENTRIES], "too many entries in the archive (%d, %d at most besides prefabs and textures)" % [plain, MAX_ARCHIVE_ENTRIES]]
	var folder = null
	# Dossier des cinq fichiers (racine ou un dossier) : les prefabs y sont rangés.
	for e in entries:
		var nm := String(e.name)
		if nm.get_file() in FILES and not nm.get_base_dir().contains("/"):
			folder = nm.get_base_dir()
			break
	for e in entries:
		var name := String(e.name)
		if name.contains("..") or name.begins_with("/") or name.contains("\\") or name.contains(":"):
			return ["chemin interdit dans l'archive : %s" % name.left(80), "forbidden path in the archive: %s" % name.left(80)]
		# Format 10 : prefabs de la carte (prefabs/, prefabs/<pid>/, et leurs
		# deux fichiers), dans le dossier des cinq fichiers.
		var rel := name.trim_prefix(String(folder) + "/") if folder != null and String(folder) != "" else name
		if folder != null and String(folder) != "" and not name.begins_with(String(folder) + "/") and name != String(folder) + "/":
			rel = ""
		if rel == MapPrefabLib.DIR + "/" or (rel.begins_with(MapPrefabLib.DIR + "/") and rel.ends_with("/") and rel.count("/") == 2
				and MapPrefabLib.pid_ok(rel.split("/")[1])):
			continue
		var pk := MapPrefabLib.parse_key(rel)
		if not pk.is_empty():
			# prefab.json : borné (définition valide) ; model.glb : aucune
			# taille maximale, seulement pas de « bombe » de compression.
			if (pk[1] == MapPrefabLib.DEF_FILE and int(e.size) > MapPrefabLib.MAX_DEF_BYTES) or wanted.has(rel):
				return ["prefab trop gros ou en double dans l'archive : %s" % name.left(80), "prefab too big or duplicated in the archive: %s" % name.left(80)]
			if CustomMapGuard.zip_bomb(int(e.size), int(e.get("csize", 0))):
				return ["modèle trop compressé dans l'archive (« bombe » de décompression) : %s" % name.left(80), "model compressed too much in the archive (decompression bomb): %s" % name.left(80)]
			wanted[rel] = name
			continue
		# Format 15 : textures de la carte (textures/, textures/<tid>/ et leurs
		# fichiers admis), sans quota de taille (l'archive est bornée en tout).
		if rel == MapTextureLib.DIR + "/" or (rel.begins_with(MapTextureLib.DIR + "/") and rel.ends_with("/") and rel.count("/") == 2
				and MapTextureLib.tid_ok(rel.split("/")[1])):
			continue
		if not MapTextureLib.parse_key(rel).is_empty():
			if wanted.has(rel):
				return ["texture en double dans l'archive : %s" % name.left(80), "texture duplicated in the archive: %s" % name.left(80)]
			wanted[rel] = name
			continue
		if name.ends_with("/"):
			if name.count("/") > 1:
				return ["dossier inattendu dans l'archive : %s" % name.left(80), "unexpected folder in the archive: %s" % name.left(80)]
			continue
		var base := name.get_file()
		var dir := name.get_base_dir()
		if not base in FILES or dir.contains("/") or (folder != null and dir != folder) or wanted.has(base):
			return ["fichier inattendu dans l'archive : %s (seulement %s)" % [name.left(80), ", ".join(FILES)],
				"unexpected file in the archive: %s (only %s)" % [name.left(80), ", ".join(FILES)]]
		folder = dir
		if int(e.size) > MAX_FILE_BYTES:
			@warning_ignore("integer_division")
			var kb := int(e.size) / 1024  # Ko entiers (troncature voulue)
			return ["%s trop gros dans l'archive (%d Ko décompressés, 2 Mo au plus)" % [base, kb],
				"%s too big in the archive (%d KB uncompressed, 2 MB at most)" % [base, kb]]
		wanted[base] = name
	return []


## Répertoire central d'une archive lu sur le disque SANS charger l'archive
## entière (elle peut peser des centaines de Mo) : la fin du fichier (fin du
## répertoire et son commentaire), puis le répertoire lui-même. Rend
## {bytes : le répertoire suivi de sa fin, décalage remis à 0 (ce que lisent
## zip_entries et CustomMapGuard.read_zip_texts), size : taille de
## l'archive} ou {error: [fr, en]}.
static func zip_directory(path: String) -> Dictionary:
	var bad := {"error": ["archive illisible (répertoire du zip abîmé)", "unreadable archive (broken zip directory)"]}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"error": ["archive illisible : %s" % path.get_file(), "unreadable archive: %s" % path.get_file()]}
	var n := fa.get_length()
	if n < 22:
		fa.close()
		return bad
	var tail_n := mini(n, 22 + 65535)
	fa.seek(n - tail_n)
	var tail := fa.get_buffer(tail_n)
	var eocd := -1
	var i := tail.size() - 22
	while i >= 0:
		if tail.decode_u32(i) == 0x06054b50:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		fa.close()
		return bad
	var cd_size := tail.decode_u32(eocd + 12)
	var at := tail.decode_u32(eocd + 16)
	if at == 0xFFFFFFFF or cd_size == 0xFFFFFFFF or at + cd_size > n - tail_n + eocd:
		fa.close()
		return bad
	fa.seek(at)
	var out := fa.get_buffer(cd_size)
	fa.close()
	if out.size() != cd_size:
		return bad
	var end := tail.slice(eocd)
	end.encode_u32(16, 0)
	out.append_array(end)
	return {"bytes": out, "size": n}


## Entrées d'une archive .zip lues dans son répertoire central, sans rien
## décompresser : {"entries": [{name, size (décompressé), csize}]} ou
## {"error": [fr, en]} (archive abîmée, ZIP64 refusé). `bytes` : l'archive
## entière ou son répertoire (zip_directory).
static func zip_entries(bytes: PackedByteArray) -> Dictionary:
	var bad := {"error": ["archive illisible (répertoire du zip abîmé)", "unreadable archive (broken zip directory)"]}
	var n := bytes.size()
	# Fin du répertoire central : signature 0x06054b50, au plus 64 Ko de commentaire.
	var eocd := -1
	var i := n - 22
	while i >= maxi(0, n - 22 - 65535):
		if bytes.decode_u32(i) == 0x06054b50:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		return bad
	var count := bytes.decode_u16(eocd + 10)
	var cd_size := bytes.decode_u32(eocd + 12)
	var at := bytes.decode_u32(eocd + 16)
	if count == 0xFFFF or at == 0xFFFFFFFF or at + cd_size > eocd:
		return bad
	var out := []
	for k in count:
		if at + 46 > eocd or bytes.decode_u32(at) != 0x02014b50:
			return bad
		var csize := bytes.decode_u32(at + 20)
		var size := bytes.decode_u32(at + 24)
		var ln := bytes.decode_u16(at + 28)
		var lx := bytes.decode_u16(at + 30)
		var lc := bytes.decode_u16(at + 32)
		if size == 0xFFFFFFFF or csize == 0xFFFFFFFF or at + 46 + ln > eocd:
			return bad
		out.append({"name": bytes.slice(at + 46, at + 46 + ln).get_string_from_utf8(), "size": size, "csize": csize})
		at += 46 + ln + lx + lc
	return {"entries": out}


## JSON lisible dans un diff : une entrée (pièce, porte, objet...) par ligne.
static func dump(v: Variant, depth := 0) -> String:
	var pad := " ".repeat(depth + 1)
	if v is Dictionary and depth < 2:
		var parts := PackedStringArray()
		for k in v:
			parts.append("%s%s: %s" % [pad, JSON.stringify(String(k)), dump(v[k], depth + 1)])
		return "{\n%s\n%s}" % [",\n".join(parts), " ".repeat(depth)] if not parts.is_empty() else "{}"
	if v is Array and depth < 2 and not v.is_empty() and (v[0] is Dictionary or v[0] is Array):
		var parts := PackedStringArray()
		for e in v:
			parts.append(pad + JSON.stringify(e, "", false))
		return "[\n%s\n%s]" % [",\n".join(parts), " ".repeat(depth)]
	return JSON.stringify(v, "", false)


# ------------------------------------------------------------------ emplacements

## Dossier des cartes du joueur (user://maps ; en autotest, un dossier de
## tests/_out propre au scénario : jamais les cartes du joueur).
static var root_override := ""


static func maps_root() -> String:
	if root_override != "":
		return root_override
	if AutotestMode.is_running():
		return ProjectSettings.globalize_path("res://tests/_out/editor_maps_%s" % AutotestMode.scenario_name())
	return "user://maps"


## Longueur maximale d'un identifiant de carte (nom de dossier).
const MAX_ID_LEN := 48


## Identifiant de carte admis : 1 à 48 caractères parmi a-z, 0-9 et _ (le
## format de slug) ; jamais de chemin (« .. », « / »...).
static func valid_id(map_id: String) -> bool:
	if map_id.is_empty() or map_id.length() > MAX_ID_LEN:
		return false
	for ch in map_id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


## Dossier de la carte `map_id` dans le dossier des cartes ; "" si
## l'identifiant n'est pas admis (valid_id).
static func map_dir(map_id: String) -> String:
	if not valid_id(map_id):
		return ""
	return maps_root().path_join(map_id)


## Cartes enregistrées : [{id, dir, name}], triées par nom.
static func list_maps() -> Array:
	var out := []
	var root := maps_root()
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			if d.begins_with("_") or not valid_id(d):
				continue
			var dir := root.path_join(d)
			if not is_map_dir(dir):
				continue
			var txt = read_text(dir.path_join("carte.json"))
			var c = JSON.parse_string(txt) if txt != null else null
			var n: Dictionary = c.get("nom", {}) if c is Dictionary else {}
			out.append({"id": d, "dir": dir, "name": Lang.t(String(n.get("fr", d)), String(n.get("en", n.get("fr", d))))})
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


## Chemin absolu normalisé (user://, res:// globalisés ; « \ » en « / »).
static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p).replace("\\", "/").simplify_path()


## Supprime définitivement la carte du joueur rangée dans `dir` (dossier
## entier). Refusé (false, message dans la console) hors du dossier des cartes
## (maps_root : enfant direct seulement, jamais « .. »), pour les exemples
## (EXAMPLES), les dossiers internes (« _autosave »...), les noms non admis
## (valid_id) et tout lien symbolique dedans (jamais suivi hors du dossier).
static func delete_map(dir: String) -> bool:
	var refuse := func(why: String) -> bool:
		push_warning("[EditorMap] suppression refusée (%s) : %s" % [why, dir])
		return false
	if dir.strip_edges() == "" or dir.contains(".."):
		return refuse.call("chemin")
	var target := _abs(dir).trim_suffix("/")
	var root := _abs(maps_root()).trim_suffix("/")
	for ex in EXAMPLES.values():
		if target == _abs(String(ex)).trim_suffix("/"):
			return refuse.call("exemple")
	var id := target.get_file()
	if root == "" or target.get_base_dir() != root or not valid_id(id) or id.begins_with("_"):
		return refuse.call("hors du dossier des cartes")
	var parent := DirAccess.open(root)
	if parent == null or not parent.dir_exists(id):
		return refuse.call("introuvable")
	if parent.is_link(id) or _has_link(target):
		return refuse.call("lien symbolique")
	if not is_map_dir(target):
		return refuse.call("pas une carte")
	var err := _remove_tree(target)
	if err != OK:
		push_warning("[EditorMap] suppression incomplète (%s) : %s" % [error_string(err), target])
		return false
	return true


## Un lien symbolique quelque part dans `dir` (sous-dossiers compris) ?
static func _has_link(dir: String) -> bool:
	var d := DirAccess.open(dir)
	if d == null:
		return true
	d.include_hidden = true
	for f in d.get_files():
		if d.is_link(f):
			return true
	for s in d.get_directories():
		if d.is_link(s) or _has_link(dir.path_join(s)):
			return true
	return false


static func _remove_tree(dir: String) -> Error:
	var d := DirAccess.open(dir)
	if d == null:
		return DirAccess.get_open_error()
	d.include_hidden = true
	for s in d.get_directories():
		var e := _remove_tree(dir.path_join(s))
		if e != OK:
			return e
	for f in d.get_files():
		var e := DirAccess.remove_absolute(dir.path_join(f))
		if e != OK:
			return e
	return DirAccess.remove_absolute(dir)


## Identifiant de dossier tiré d'un nom (minuscules, chiffres et _).
static func slug(s: String) -> String:
	var t := s.strip_edges().to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"],
			["ô", "o"], ["û", "u"], ["ù", "u"], ["ç", "c"]]:
		t = t.replace(pair[0], pair[1])
	var out := ""
	for ch in t:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	# Place pour un suffixe « _2 » sans dépasser MAX_ID_LEN.
	out = out.left(MAX_ID_LEN - 8).trim_suffix("_")
	return out if out != "" else "carte"
