class_name EditorMap
extends RefCounted
## Carte de l'éditeur (docs/MAP_AUTHORING.md) : cinq fichiers JSON lisibles et
## écrivables à la main, dans un dossier (user://maps/<id>/) ou une archive
## .zip. Coordonnées en mètres (x vers l'est, y vers le sud), identifiants
## stables pour chaque élément.
##   carte.json       id, noms FR/EN, description, musique, version du format, étages
##   pieces.json      pièces (contour, étage, zone, hauteur de plafond...)
##   ouvertures.json  portes, débris, portes du courant, passages, fenêtres
##   objets.json      tout le reste (murs, piliers, escaliers, atouts, armes, boîte...)
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
##      portes, débris et armes murales, MapCatalog.VARIANTS ; absente :
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
##   10 effets (docs/MAP_OBJECTS.md § 11) : type « effet » (clé « effet » :
##      flammes, fumées, étincelles, électricité, eau, ambiance de
##      MapCatalog.EFFECTS ; « position », et selon l'effet « rot », « mur »,
##      « angle ») et ses réglages facultatifs « intensite », « taille »,
##      « couleur », « hauteur » (MapCatalog.tidy_effect : jamais écrits à leur
##      valeur par défaut). Aucune collision. Formats 1 à 9 lus tels quels.
const FORMAT := 10
const FILES := ["carte.json", "pieces.json", "ouvertures.json", "objets.json", "zones.json"]
const DEFAULT_CEILING := 3.2
const FLOOR_STEP := 3.5
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


static func blank(map_id := "nouvelle_carte", name_fr := "NOUVELLE CARTE", name_en := "NEW MAP") -> EditorMap:
	var m := EditorMap.new()
	m.carte = {"format": FORMAT, "id": map_id, "nom": {"fr": name_fr, "en": name_en},
		"description": {"fr": "", "en": ""}, "musique": "ambience_bunker", "hauteur_portes": 2.5,
		"lampes_auto": true, "etages": [{"sol": 0.0, "hauteur": DEFAULT_CEILING}]}
	return m


# ------------------------------------------------------------------ accès

func id() -> String:
	return String(carte.get("id", "carte"))


func display_name() -> String:
	var n: Dictionary = carte.get("nom", {})
	return Lang.t(String(n.get("fr", id())), String(n.get("en", n.get("fr", id()))))


func floors() -> Array:
	return carte.get("etages", [])


func floor_count() -> int:
	return maxi(1, floors().size())


func floor_sol(k: int) -> float:
	var f: Array = floors()
	return float(f[k].get("sol", k * FLOOR_STEP)) if k < f.size() else k * FLOOR_STEP


func floor_height(k: int) -> float:
	var f: Array = floors()
	return float(f[k].get("hauteur", DEFAULT_CEILING)) if k < f.size() else DEFAULT_CEILING


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


func rooms_on(k: int) -> Array:
	return pieces.filter(func(p): return int(p.get("etage", 0)) == k)


func openings_on(k: int) -> Array:
	return ouvertures.filter(func(o): return int(o.get("etage", 0)) == k)


func objects_on(k: int) -> Array:
	return objets.filter(func(o): return int(o.get("etage", 0)) == k)


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

func to_dict() -> Dictionary:
	return {"carte": carte, "pieces": pieces, "ouvertures": ouvertures, "objets": objets, "zones": zones, "depart": depart}


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


func duplicate_map() -> EditorMap:
	var m := EditorMap.new()
	m.restore(snapshot())
	return m


## Deux cartes identiques (contenu des cinq fichiers) ?
func same_as(other: EditorMap) -> bool:
	return file_texts() == other.file_texts()


# ------------------------------------------------------------------ fichiers

## Contenu des cinq fichiers (JSON lisible : un élément par ligne). Les
## nombres entiers s'écrivent sans décimale (17 et non 17.0) : un fichier relu
## puis réenregistré est identique.
func file_texts() -> Dictionary:
	var c := carte.duplicate(true)
	c["format"] = FORMAT
	return {
		"carte.json": dump(_ints(c)),
		"pieces.json": dump(_ints({"pieces": pieces})),
		"ouvertures.json": dump(_ints({"ouvertures": ouvertures})),
		"objets.json": dump(_ints({"objets": objets})),
		"zones.json": dump(_ints({"depart": depart, "zones": zones})),
	}


static func _ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
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
	m._migrate(m.format_read)
	m._normalize()
	return m


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


## Version du format lue dans carte.json (FORMAT pour une carte neuve).
var format_read := FORMAT


## Valeurs lues du JSON remises au bon type (étages entiers, identifiants en texte).
func _normalize() -> void:
	for list in [pieces, ouvertures, objets]:
		for e in list:
			e["id"] = String(e.get("id", ""))
			e["etage"] = int(e.get("etage", 0))
	for p in pieces:
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
	for o in objets:
		if o.has("hauteur") and String(o.get("type", "")) == "luminaire":
			MapCatalog.set_wall_light_height(o, float(o.hauteur) if (o.hauteur is float or o.hauteur is int) else NAN)
	# Barrière invisible (format 9) : un polygone « sommets » ; un rectangle
	# d'avant (« rect », « rot ») devient le polygone de ses 4 coins.
	for o in objets:
		if String(o.get("type", "")) == "bloc_invisible":
			normalize_clip(o)
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
	if floors().is_empty():
		carte["etages"] = [{"sol": 0.0, "hauteur": DEFAULT_CEILING}]
	if zone(depart).is_empty() and not zones.is_empty():
		depart = String(zones[0].id)


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
	for f in texts:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		if fa == null:
			return FileAccess.get_open_error()
		fa.store_string(texts[f])
		fa.close()
	return OK


## Limites des fichiers lus (cartes reçues, archives : jamais de lecture sans
## borne). Une carte réelle pèse quelques dizaines de Ko.
const MAX_FILE_BYTES := 2 * 1024 * 1024
const MAX_ARCHIVE_BYTES := 2 * 1024 * 1024
const MAX_ARCHIVE_ENTRIES := 32


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
	var m := from_texts(texts)
	for f in too_big:
		m.load_errors.append(["%s trop gros (2 Mo au plus) ou illisible" % f, "%s too big (2 MB at most) or unreadable" % f])
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
	for f in FILES:
		z.start_file(f)
		z.write_file(String(texts[f]).to_utf8_buffer())
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
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ["archive illisible : %s" % path, "unreadable archive: %s" % path]
	var n := fa.get_length()
	if n > MAX_ARCHIVE_BYTES:
		@warning_ignore("integer_division")
		var kb := n / 1024  # Ko entiers (troncature voulue)
		return ["archive trop grosse (%d Ko, 2 Mo au plus)" % kb, "archive too big (%d KB, 2 MB at most)" % kb]
	var listing := zip_entries(fa.get_buffer(n))
	fa.close()
	if listing.has("error"):
		return listing.error
	return check_zip_entries(listing.entries, {})


## Vérifie les entrées d'une archive (zip_entries) ; remplit `wanted` (nom de
## base -> chemin) ; rend [fr, en] si l'archive est refusée, [] sinon.
static func check_zip_entries(entries: Array, wanted: Dictionary) -> Array:
	if entries.size() > MAX_ARCHIVE_ENTRIES:
		return ["trop d'entrées dans l'archive (%d, 32 au plus)" % entries.size(), "too many entries in the archive (%d, 32 at most)" % entries.size()]
	var folder = null
	for e in entries:
		var name := String(e.name)
		if name.contains("..") or name.begins_with("/") or name.contains("\\") or name.contains(":"):
			return ["chemin interdit dans l'archive : %s" % name.left(80), "forbidden path in the archive: %s" % name.left(80)]
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


## Entrées d'une archive .zip lues dans son répertoire central, sans rien
## décompresser : {"entries": [{name, size (décompressé), csize}]} ou
## {"error": [fr, en]} (archive abîmée, ZIP64 refusé).
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
