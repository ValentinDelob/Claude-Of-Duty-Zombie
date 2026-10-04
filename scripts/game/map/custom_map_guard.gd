class_name CustomMapGuard
extends RefCounted
## Contrôle de légitimité des cartes perso (éditeur de cartes) venues d'ailleurs :
## carte reçue d'un hôte en multijoueur, archive .zip importée, carte locale
## ouverte pour jouer. Une carte n'est QUE des données : cinq textes JSON
## (EditorMap.FILES), jamais un fichier Godot (.tres, .tscn, script, image) :
## une ressource Godot peut embarquer du code. Rien ici n'appelle load(),
## ResourceLoader ni un décodeur d'image : les textes sont lus en UTF-8 puis
## analysés par le lecteur JSON du moteur (parse_json : JSON.parse, comme
## JSON.parse_string mais sans message d'erreur du moteur sur un texte
## invalide), et chaque valeur est vérifiée.
##
## Contrôles (docs/MAP_AUTHORING.md, « Cartes perso en multijoueur ») :
##   - limites dures : taille du paquet, profondeur JSON, nombre de pièces,
##     d'ouvertures, d'objets, de zones, d'étages, de sommets, longueur des
##     textes, coordonnées finies et bornées, prix bornés ;
##   - liste blanche des clés et des valeurs, tirée du catalogue de l'éditeur
##     (MapCatalog : types d'objets, atouts, armes, surfaces, musiques) par UNE
##     seule fonction adaptatrice, catalog_source() ;
##   - identifiants et noms nettoyés : pas de chemin (.., /, \, :), pas de
##     caractère de contrôle, pas de balise BBCode ou HTML dans un nom affiché ;
##   - jouabilité : le validateur de l'éditeur (MapRaster + MapValidator).
##
## Paquet réseau canonique (pack / unpack) : JSON trié
## {"format": 1, "fichiers": {"carte.json": "...", ...}} en UTF-8 ; son
## SHA-256 identifie la carte. Cache : user://maps_cache/<sha256>/ (le nom du
## dossier est le hash, jamais un nom fourni par l'hôte).

## Version du paquet réseau (2 : carte avec des prefabs de la carte, format 10).
const PACKAGE_FORMAT := 1
const PACKAGE_FORMAT_PREFABS := 2
## Taille maximale du paquet sans prefab (et de l'ensemble des cinq fichiers).
const MAX_PACKAGE_BYTES := 2 * 1024 * 1024
## Taille maximale d'un paquet avec des prefabs (modèles en base64 compris :
## MapPrefabLib.MAX_MODELS_BYTES) : annonces et transferts (MapShare).
const MAX_TRANSFER_BYTES := 40 * 1024 * 1024
## Taille des morceaux envoyés sur le réseau (et plus petite taille acceptée).
const CHUNK_BYTES := 16 * 1024
const MIN_CHUNK_BYTES := 1024
## Archive .zip : taille du fichier et nombre d'entrées lus avant d'extraire.
## Format 10 : de quoi contenir les prefabs de la carte (MapPrefabLib : 32
## prefabs, 24 Mo de modèles au plus).
const MAX_ZIP_BYTES := 30 * 1024 * 1024
const MAX_ZIP_ENTRIES := 160
## Profondeur d'imbrication JSON (pieces.json : {pieces:[{contour:[[x,y]]}]} = 4).
const MAX_DEPTH := 6
const MAX_ROOMS := 256
const MAX_OPENINGS := 512
const MAX_OBJECTS := 2048
## Effets (type « effet », format 10) au plus par carte : coût des particules.
const MAX_EFFECTS := 64
const MAX_ZONES := 64
const MAX_FLOORS := 8
## Sommets par pièce : un cercle de 64 points (MapShapes.MAX_POINTS) et de la
## marge pour ses retouches ; le total reste borné.
const MAX_VERTICES := 128
const MAX_TOTAL_VERTICES := 4096
## Coordonnées en mètres dans le plan de l'éditeur (x, y positifs).
const MAX_COORD := 256.0
## Somme des rectangles englobants des pièces (m²) : borne le travail du validateur.
const MAX_ROOM_AREA := 100000.0
const MAX_PRICE := 100000
const MAX_ID := 32
const MAX_NAME := 64
const MAX_TEXT := 600
## Cartes gardées dans le cache (les plus anciennes sont effacées au-delà).
const MAX_CACHED := 32
## Nombre maximal de raisons rapportées (la première suffit à refuser).
const MAX_REASONS := 8

## Raisons de refus d'un transfert (codes échangés sur le réseau, textes locaux).
const REASONS := {
	"offre": ["annonce de carte invalide", "invalid map announcement"],
	"trop_gros": ["carte trop volumineuse", "map too large"],
	"morceau": ["morceau de carte invalide (taille)", "invalid map chunk (size)"],
	"desordre": ["morceaux de carte dans le désordre", "map chunks out of order"],
	"double": ["morceau de carte reçu deux fois", "map chunk received twice"],
	"manquant": ["morceaux de carte manquants", "missing map chunks"],
	"taille": ["taille de la carte incorrecte", "wrong map size"],
	"hash": ["empreinte SHA-256 incorrecte : carte corrompue", "wrong SHA-256 fingerprint: corrupted map"],
	"contenu": ["contenu de carte refusé (données non autorisées)", "map content refused (data not allowed)"],
	"injouable": ["carte refusée par le validateur (injouable)", "map refused by the validator (unplayable)"],
	"cache": ["impossible d'enregistrer la carte", "could not save the map"],
}

## Cache des cartes reçues (tests : dossier de tests/_out, jamais celui du joueur).
static var cache_override := ""
static var _schema: Dictionary = {}


# ------------------------------------------------------------------ catalogue

## Catalogue imposé par les tests (même forme que catalog_source()) ; vide :
## le vrai catalogue de l'éditeur.
static var source_override: Dictionary = {}


## ADAPTATEUR UNIQUE vers le catalogue de l'éditeur : tout ce que la liste
## blanche accepte vient d'ici. Retourne :
##   items     : objets du catalogue (MapCatalog.items(), avec leur `make`) ;
##   kinds     : MapCatalog.allowed_kinds() quand elle existe (carte au format
##               2 : {type: {file, required, keys: {clé: spec}}}), sinon {} ;
##   room_keys : MapCatalog.room_keys() quand elle existe, sinon {} ;
##   zone_keys : MapCatalog.zone_keys() quand elle existe, sinon {} ;
##   surfaces  : MapCatalog.allowed_surfaces(), sinon MapCatalog.materials() ;
##   musics    : MapCatalog.musics().
## Les fonctions facultatives sont cherchées par leur nom : ce fichier se
## compile avec ou sans elles. Sans elles, le schéma est déduit des objets du
## catalogue (`make`) et de leurs outils de pose.
static func catalog_source() -> Dictionary:
	if not source_override.is_empty():
		return source_override
	var cat: GDScript = MapCatalog
	var names := {}
	for m in cat.get_script_method_list():
		names[String(m.name)] = true
	var src := {"items": MapCatalog.items(), "kinds": {}, "room_keys": {}, "zone_keys": {},
		"surfaces": MapCatalog.materials(), "musics": MapCatalog.musics()}
	for f in ["allowed_kinds", "room_keys", "zone_keys"]:
		if names.has(f):
			var v: Variant = cat.call(f)
			if v is Dictionary:
				src["kinds" if f == "allowed_kinds" else f] = v
	if names.has("allowed_surfaces"):
		src.surfaces = _as_list(cat.call("allowed_surfaces"))
	return src


## Liste de textes tirée d'un tableau ou des clés d'un dictionnaire.
static func _as_list(v: Variant) -> Array:
	var out := []
	if v is Dictionary:
		for k in v:
			out.append(String(k))
	elif v is Array or v is PackedStringArray:
		for k in v:
			out.append(String(k))
	return out


## Oublie le schéma construit (tests, catalogue modifié).
static func reset_schema() -> void:
	_schema = {}


## Règle du contrôle tirée d'une spec du catalogue (format 2) :
## {"t": id | int | number | bool | enum | point | rect | color | text | names | polygon | points | dims}.
static func _rule_of_spec(s: Variant) -> Variant:
	if not s is Dictionary:
		return ""
	match String(s.get("t", "")):
		"id":
			return "id"
		"int":
			return "int:%s:%s" % [str(float(s.get("min", -1000))), str(float(s.get("max", 1000)))]
		"number":
			return "num:%s:%s" % [str(float(s.get("min", -1000))), str(float(s.get("max", 1000)))]
		"bool":
			return "bool"
		"enum":
			var d := {}
			for v in s.get("values", []):
				d[_enum_key(v)] = true
			return d
		"point":
			return "pt"
		"rect":
			return "rect"
		"color":
			return "color"
		"text":
			return "text:%d" % clampi(int(s.get("max", MAX_NAME)), 1, MAX_TEXT)
		"names":
			return "names"
		"polygon":
			return "polygon"
		"points":
			return "points:%d:%d" % [clampi(int(s.get("min", 3)), 1, MAX_VERTICES), clampi(int(s.get("max", MAX_VERTICES)), 1, MAX_VERTICES)]
		"shape":
			return "forme"
		"dims":
			# Format 11 : liste de min à max nombres, chacun de lo à hi (zone d'un effet).
			return "dims:%d:%d:%s:%s" % [clampi(int(s.get("min", 1)), 1, 8), clampi(int(s.get("max", 3)), 1, 8),
				str(float(s.get("lo", 0.0))), str(float(s.get("hi", 1000.0)))]
		"prefab":
			# Format 10 : décor du catalogue (values) ou prefab de la carte « map:<pid> ».
			var d := {}
			for v in s.get("values", []):
				d[String(v)] = true
			return {"prefab_ref": d}
	return ""


## Clé d'une valeur permise : les nombres en flottant (le JSON lit 90 comme 90.0).
static func _enum_key(v: Variant) -> Variant:
	return float(v) if (v is int or v is float) else v


## Schéma de la liste blanche, construit une fois depuis catalog_source().
##   kinds[type] = {file, keys: {clé: règle}, required: [clés]} ;
##   room_keys, zone_keys : {clé: règle} ; règles : "bool", "pt", "rect", "id",
##   "dir", "prix", "color", "name", "names", "floor", "zone_ref", "polygon",
##   "surface", "num:<min>:<max>", "int:<min>:<max>", "text:<max>",
##   "points:<min>:<max>" (liste de points, format 9), "dims:<min>:<max>:<lo>:<hi>"
##   (liste de nombres bornés, format 11), ou un dictionnaire de
##   valeurs permises.
static func schema() -> Dictionary:
	if not _schema.is_empty():
		return _schema
	var src := catalog_source()
	var dirs := {}
	for d in MapGeom.DIRS:
		dirs[String(d)] = true
	var surfaces := {}
	for s in src.get("surfaces", []):
		surfaces[String(s)] = true
	var musics := {}
	for s in src.get("musics", []):
		musics[String(s)] = true
	var kinds := {}
	var room_forms := {}
	for it in src.get("items", []):
		var make: Dictionary = it.get("make", {})
		if make.has("forme"):
			room_forms[String(make.forme)] = true
	var table: Variant = src.get("kinds", {})
	if table is Dictionary and not table.is_empty():
		# Format 2 : table typée du catalogue (MapCatalog.allowed_kinds).
		for t in table:
			var d: Variant = table[t]
			if not (t is String and d is Dictionary):
				continue
			var keys := {}
			var spec_keys: Variant = d.get("keys", {})
			if spec_keys is Dictionary:
				for k in spec_keys:
					if not k in ["id", "type", "etage"]:
						keys[String(k)] = _rule_of_spec(spec_keys[k])
			var req := []
			for k in d.get("required", []):
				if not k in ["id", "type", "etage"]:
					req.append(String(k))
			kinds[t] = {"file": String(d.get("file", "objets.json")), "keys": keys, "required": req}
	else:
		# Format 1 : déduit des objets du catalogue (`make`) et de leurs outils.
		var tool_keys := {
			"opening": {"position": "pt", "largeur": "num:0.5:20", "prix": "prix"},
			"wall_item": {"position": "pt", "mur": "dir", "prix": "prix"},
			"floor_item": {"position": "pt", "prix": "prix"},
			"rect": {"rect": "rect", "prix": "prix"},
			"wall": {"a": "pt", "b": "pt"},
		}
		var generic := {}
		for t in tool_keys:
			generic.merge(tool_keys[t])
		for it in src.get("items", []):
			var make: Dictionary = it.get("make", {})
			if not make.has("type"):
				continue
			var t := String(make.type)
			var tool := String(it.get("tool", ""))
			if not kinds.has(t):
				kinds[t] = {"file": "ouvertures.json" if tool == "opening" else "objets.json",
					"keys": (tool_keys.get(tool, generic) as Dictionary).duplicate(), "required": []}
			var keys: Dictionary = kinds[t].keys
			if it.get("wall_snap", false):
				# Format 15 : la boîte mystère se pose au sol OU contre un mur.
				keys.merge(tool_keys.wall_item)
			for k in make:
				if k == "type":
					continue
				var v: Variant = make[k]
				if k in ["mur", "monte"]:
					keys[k] = "dir"
				elif v is bool:
					keys[k] = "bool"
				elif v is float or v is int:
					keys[k] = {"epaisseur": "num:0.1:5", "largeur": "num:0.5:20"}.get(k, "num:-1000:1000")
				else:
					# Texte : seulement les valeurs du catalogue (atouts, armes...).
					var allowed: Dictionary = keys.get(k, {}) if keys.get(k) is Dictionary else {}
					allowed[String(v)] = true
					keys[k] = allowed
	# Pièces et zones : clés du catalogue (format 2) ou celles du format 1.
	var room_keys := {"id": "id", "nom": "name", "etage": "floor", "zone": "zone_ref", "contour": "polygon",
		"plafond": "num:1.5:30", "double_hauteur": "bool", "forme": room_forms, "sol": "surface", "murs": "surface"}
	var rk: Variant = src.get("room_keys", {})
	if rk is Dictionary and not rk.is_empty():
		room_keys = {}
		for k in rk:
			room_keys[String(k)] = _rule_of_spec(rk[k])
		room_keys.merge({"id": "id", "etage": "floor", "contour": "polygon"}, true)
		if room_keys.has("zone"):
			room_keys["zone"] = "zone_ref"
	var zone_keys := {"id": "id", "nom": "names", "sol": "surface", "murs": "surface"}
	var zk: Variant = src.get("zone_keys", {})
	if zk is Dictionary and not zk.is_empty():
		zone_keys = {}
		for k in zk:
			zone_keys[String(k)] = _rule_of_spec(zk[k])
		zone_keys["id"] = "id"
	_schema = {"kinds": kinds, "dirs": dirs, "surfaces": surfaces, "musics": musics, "room_keys": room_keys, "zone_keys": zone_keys,
		"openings": kinds.keys().filter(func(t): return String(kinds[t].file) == "ouvertures.json")}
	return _schema


# ------------------------------------------------------------------ textes et noms

## Texte UTF-8 valide, sans octet nul (un décodage silencieux : pas d'erreur
## imprimée par le moteur sur un octet invalide).
static func utf8_ok(b: PackedByteArray) -> bool:
	var i := 0
	var n := b.size()
	while i < n:
		var c := b[i]
		if c < 0x80:
			if c == 0:
				return false
			i += 1
			continue
		var extra := 0
		var lo := 0x80
		var hi := 0xBF
		if c >= 0xC2 and c <= 0xDF:
			extra = 1
		elif c >= 0xE0 and c <= 0xEF:
			extra = 2
			if c == 0xE0:
				lo = 0xA0
			elif c == 0xED:
				hi = 0x9F
		elif c >= 0xF0 and c <= 0xF4:
			extra = 3
			if c == 0xF0:
				lo = 0x90
			elif c == 0xF4:
				hi = 0x8F
		else:
			return false
		if i + extra >= n:
			return false
		for j in extra:
			var d := b[i + 1 + j]
			if j == 0 and (d < lo or d > hi):
				return false
			if d < 0x80 or d > 0xBF:
				return false
		i += extra + 1
	return true


## Octets -> texte, ou null s'ils ne sont pas de l'UTF-8 propre.
static func decode_utf8(b: PackedByteArray) -> Variant:
	if not utf8_ok(b):
		return null
	return b.get_string_from_utf8()


static func _has_control(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		# Contrôles C0/C1, séparateurs de ligne, marques et contrôles bidirectionnels.
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			return true
	return false


## Identifiant d'élément (p1, z3, o12...) : lettres, chiffres, _ et -.
static func id_ok(s: String) -> bool:
	if s.is_empty() or s.length() > MAX_ID:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45):
			return false
	return true


## Identifiant de carte (nom de dossier) : minuscules, chiffres et _, comme EditorMap.slug.
static func map_id_ok(s: String) -> bool:
	if s.is_empty() or s.length() > MAX_NAME:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 122) or c == 95):
			return false
	return true


## Dossier d'une carte du joueur (user://maps/<dossier>) : un seul nom de
## dossier, jamais un chemin (.., /, \, :), ni caractère de contrôle ou
## interdit sous Windows.
static func folder_ok(s: String) -> bool:
	if s.is_empty() or s.length() > MAX_NAME or s.begins_with(".") or _has_control(s):
		return false
	for bad in ["/", "\\", ":", "..", "*", "?", "\"", "<", ">", "|"]:
		if s.contains(bad):
			return false
	return true


## Identifiant de carte du jeu acceptable : carte du registre, carte du joueur
## « perso:<dossier> » (dossier sûr) ou carte partagée « partage:<sha256> ».
static func game_map_id_ok(map_id: String) -> bool:
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		return sha_ok(map_id.trim_prefix(EditorMapDef.SHARED_PREFIX))
	if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX):
		return folder_ok(map_id.trim_prefix(EditorMapDef.CUSTOM_PREFIX))
	return map_id.length() <= MAX_ID and id_ok(map_id)


## Nom de modèle ou de fichier d'asset (sans chemin ni extension) : lettres,
## chiffres, _ et -.
static func asset_name_ok(s: String) -> bool:
	if s.is_empty() or s.length() > 64:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45):
			return false
	return true


## Atout connu du jeu (PerkDB) : seul identifiant accepté pour bâtir une machine.
static func perk_ok(id: Variant) -> bool:
	return id is String and PerkDB.PERKS.has(id)


## Arme connue du jeu (WeaponDB, KnifeDB) : seul identifiant accepté pour un achat mural.
static func weapon_ok(id: Variant) -> bool:
	return id is String and (WeaponDB.WEAPONS.has(id) or KnifeDB.exists(id))


## Nom affiché (carte, pièce, zone) : court, sans contrôle, sans balise
## ([b], [url=...], <...>) ni chemin.
static func name_ok(s: String, max_len := MAX_NAME) -> bool:
	if s.length() > max_len or _has_control(s):
		return false
	for bad in ["[", "]", "<", ">", "\\", "..", "{", "}"]:
		if s.contains(bad):
			return false
	return true


## Texte libre (description) : borné, sans contrôle sauf retour à la ligne, sans balise.
static func text_ok(s: String) -> bool:
	return name_ok(s.replace("\n", " "), MAX_TEXT)


## Nom prêt à afficher (défense en profondeur, même après contrôle) : contrôles
## retirés, crochets et chevrons remplacés, longueur bornée.
static func clean_display(s: String, max_len := MAX_NAME) -> String:
	var out := ""
	for i in mini(s.length(), max_len):
		var ch := s[i]
		var c := s.unicode_at(i)
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			continue
		out += {"[": "(", "]": ")", "<": "(", ">": ")", "{": "(", "}": ")", "\\": "/"}.get(ch, ch)
	return out.strip_edges()


static func sha_ok(s: String) -> bool:
	if s.length() != 64:
		return false
	for i in 64:
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func sha256_hex(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()


# ------------------------------------------------------------------ contrôle d'une carte

## Texte JSON -> valeur (null s'il est illisible). Données seulement : le
## lecteur JSON ne crée ni objet ni ressource.
static func parse_json(s: String) -> Variant:
	var j := JSON.new()
	if j.parse(s) != OK:
		return null
	return j.data


## Profondeur d'imbrication d'un texte JSON ([ et { hors des chaînes), lue
## AVANT l'analyse. -1 : chaîne non fermée.
static func json_depth(s: String) -> int:
	var depth := 0
	var best := 0
	var in_str := false
	var esc := false
	for i in s.length():
		var c := s.unicode_at(i)
		if in_str:
			if esc:
				esc = false
			elif c == 92:
				esc = true
			elif c == 34:
				in_str = false
			continue
		if c == 34:
			in_str = true
		elif c == 91 or c == 123:
			depth += 1
			best = maxi(best, depth)
		elif c == 93 or c == 125:
			depth -= 1
	return -1 if in_str else best


class Check:
	var reasons: Array = []
	var count := 0
	var ids := {}
	var floors := 1
	var area := 0.0
	var vertices := 0
	var effects := 0

	func bad(fr: String, en: String) -> void:
		if reasons.size() < CustomMapGuard.MAX_REASONS:
			reasons.append([fr, en])

	func failed() -> bool:
		return not reasons.is_empty()


## Contrôle de sûreté des cinq textes (nom de fichier -> texte). Ne demande pas
## la jouabilité (voir check_playable). Retourne {ok, reasons: [[fr, en]...],
## map: EditorMap (seulement si ok)}.
static func check_texts(texts: Dictionary) -> Dictionary:
	var c := Check.new()
	var parsed := {}
	var total := 0
	for k in texts:
		if not (k is String and (String(k) in EditorMap.FILES or not MapPrefabLib.parse_key(k).is_empty())):
			c.bad("fichier non autorisé dans la carte : %s" % clean_display(str(k), 40), "file not allowed in the map: %s" % clean_display(str(k), 40))
	for f in EditorMap.FILES:
		if not texts.has(f) or not texts[f] is String:
			c.bad("fichier %s absent" % f, "missing file %s" % f)
			continue
		var t: String = texts[f]
		total += t.to_utf8_buffer().size()
		if total > MAX_PACKAGE_BYTES:
			@warning_ignore("integer_division")
			c.bad("carte trop volumineuse (plus de %d Mo)" % (MAX_PACKAGE_BYTES / 1048576), "map too large (over %d MB)" % (MAX_PACKAGE_BYTES / 1048576))
			break
		var d := json_depth(t)
		if d < 0 or d > MAX_DEPTH:
			c.bad("%s : JSON trop imbriqué ou mal fermé" % f, "%s: JSON nested too deep or not closed" % f)
			continue
		var v: Variant = parse_json(t)
		if not v is Dictionary:
			c.bad("%s : JSON illisible" % f, "%s: unreadable JSON" % f)
			continue
		parsed[f] = v
	if c.failed():
		return {"ok": false, "reasons": c.reasons}
	_check_carte(c, parsed["carte.json"])
	_check_list_file(c, parsed["pieces.json"], "pieces.json", "pieces", MAX_ROOMS, _check_room)
	_check_list_file(c, parsed["ouvertures.json"], "ouvertures.json", "ouvertures", MAX_OPENINGS, _check_opening)
	_check_list_file(c, parsed["objets.json"], "objets.json", "objets", MAX_OBJECTS, _check_object)
	_check_zones(c, parsed["zones.json"])
	if c.vertices > MAX_TOTAL_VERTICES:
		c.bad("trop de sommets de pièces (%d, au plus %d)" % [c.vertices, MAX_TOTAL_VERTICES], "too many room vertices (%d, at most %d)" % [c.vertices, MAX_TOTAL_VERTICES])
	if c.area > MAX_ROOM_AREA:
		c.bad("pièces trop grandes (%d m², au plus %d)" % [int(c.area), int(MAX_ROOM_AREA)], "rooms too large (%d m², at most %d)" % [int(c.area), int(MAX_ROOM_AREA)])
	if c.failed():
		return {"ok": false, "reasons": c.reasons}
	# Format 10 : prefabs de la carte (définitions, modèles, prefabs cités).
	var refs := {}
	for o in (parsed["objets.json"] as Dictionary).get("objets", []):
		if o is Dictionary and String(o.get("type", "")) == "prefab" and MapPrefabLib.is_ref(o.get("prefab")):
			refs[MapPrefabLib.pid_of(o.prefab)] = true
	for r in MapPrefabLib.check_entries(texts, refs):
		c.bad(String(r[0]), String(r[1]))
	if c.failed():
		return {"ok": false, "reasons": c.reasons}
	# Format 14 : échelle et inclinaison du décor, selon sa définition
	# (catalogue ou prefab.json lu) : inclinaison au sol seulement, dimensions
	# finales bornées, prefab qui contient un objet de jeu jamais redimensionné.
	_check_scales(c, parsed["objets.json"], texts)
	if c.failed():
		return {"ok": false, "reasons": c.reasons}
	var m := EditorMap.from_texts(texts)
	if not m.load_errors.is_empty():
		return {"ok": false, "reasons": m.load_errors.slice(0, MAX_REASONS)}
	return {"ok": true, "reasons": [], "map": m}


## Format 14 (§ 5.3 de docs/EDITOR_SCALE_ROTATE.md) : « echelle » et « incl »
## des décors posés, contrôlées avec la définition de leur décor.
static func _check_scales(c: Check, objets: Dictionary, texts: Dictionary) -> void:
	var defs := {}
	for k in texts:
		var pk := MapPrefabLib.parse_key(k)
		if not pk.is_empty() and pk[1] == MapPrefabLib.DEF_FILE:
			var d: Variant = parse_json(String(texts[k]))
			if d is Dictionary:
				defs[pk[0]] = d
	var fixed_of := {}
	for o in objets.get("objets", []):
		if not (o is Dictionary and (o.has("echelle") or o.has("incl"))):
			continue
		var id := String(o.get("prefab", ""))
		var d: Dictionary = {}
		var fixed := []
		var pid := MapPrefabLib.pid_of(id)
		if pid != "":
			d = defs.get(pid, {})
			if not fixed_of.has(pid):
				fixed_of[pid] = MapScale.unscalable_parts(d, defs)
			fixed = fixed_of[pid]
		else:
			d = MapCatalog.PREFABS.get(id, {})
		var bad := MapScale.check_object(o, d, fixed)
		if not bad.is_empty():
			var what := "objets.json (%s)" % clean_display(str(o.get("id", "?")), 24)
			c.bad("%s : %s" % [what, bad[0]], "%s: %s" % [what, bad[1]])
			return


## La carte passe le validateur de jouabilité de l'éditeur ? Raisons des
## premières erreurs sinon (vide : jouable).
static func check_playable(m: EditorMap) -> Array:
	var v := MapRaster.build(m).v
	v.analyze()
	if v.ok():
		return []
	var out := [["carte injouable (validateur de l'éditeur)", "unplayable map (editor validator)"]]
	for e in v.errors().slice(0, 3):
		out.append([String(e.fr), String(e.en)])
	return out


## Contrôle complet : sûreté puis jouabilité.
static func check_full(texts: Dictionary) -> Dictionary:
	var r := check_texts(texts)
	if r.ok:
		var p := check_playable(r.map)
		if not p.is_empty():
			return {"ok": false, "reasons": p, "code": "injouable"}
	elif not r.has("code"):
		r["code"] = "contenu"
	return r


## Textes identiques à ceux que l'éditeur réécrirait (forme canonique) ?
static func is_canonical(texts: Dictionary, m: EditorMap) -> bool:
	return m.file_texts() == texts


static func reasons_text(reasons: Array) -> String:
	return "\n".join(reasons.map(func(r): return Lang.t(String(r[0]), String(r[1]))))


static func reason_text(code: String) -> String:
	var r: Array = REASONS.get(code, ["carte refusée", "map refused"])
	return Lang.t(r[0], r[1])


# Nombres, points, rectangles.

static func _num(c: Check, v: Variant, lo: float, hi: float, what: String) -> bool:
	if not (v is float or v is int):
		c.bad("%s : nombre attendu" % what, "%s: number expected" % what)
		return false
	var f := float(v)
	if is_nan(f) or is_inf(f) or f < lo or f > hi:
		c.bad("%s : nombre hors limites (%s à %s)" % [what, str(lo), str(hi)], "%s: number out of range (%s to %s)" % [what, str(lo), str(hi)])
		return false
	return true


static func _int(c: Check, v: Variant, lo: int, hi: int, what: String) -> bool:
	if not _num(c, v, lo, hi, what):
		return false
	if float(v) != floorf(float(v)):
		c.bad("%s : nombre entier attendu" % what, "%s: whole number expected" % what)
		return false
	return true


static func _pt(c: Check, v: Variant, what: String) -> bool:
	if not (v is Array and v.size() == 2):
		c.bad("%s : point [x, y] attendu" % what, "%s: point [x, y] expected" % what)
		return false
	return _num(c, v[0], 0.0, MAX_COORD, what) and _num(c, v[1], 0.0, MAX_COORD, what)


static func _rect(c: Check, v: Variant, what: String) -> bool:
	if not (v is Array and v.size() == 4):
		c.bad("%s : rectangle [x0, y0, x1, y1] attendu" % what, "%s: rectangle [x0, y0, x1, y1] expected" % what)
		return false
	for x in v:
		if not _num(c, x, 0.0, MAX_COORD, what):
			return false
	return true


static func _id(c: Check, v: Variant, what: String, unique := true) -> bool:
	if not (v is String and id_ok(v)):
		c.bad("%s : identifiant invalide (lettres, chiffres, _ et -, %d au plus)" % [what, MAX_ID],
			"%s: invalid identifier (letters, digits, _ and -, %d at most)" % [what, MAX_ID])
		return false
	if unique:
		if c.ids.has(v):
			c.bad("%s : identifiant « %s » en double" % [what, v], "%s: duplicate identifier \"%s\"" % [what, v])
			return false
		c.ids[v] = true
	return true


static func _name(c: Check, v: Variant, what: String) -> bool:
	if not (v is String and name_ok(v)):
		c.bad("%s : nom refusé (%d caractères au plus, sans caractère de contrôle, balise ni chemin)" % [what, MAX_NAME],
			"%s: name refused (%d characters at most, no control character, tag nor path)" % [what, MAX_NAME])
		return false
	return true


## Nom bilingue {"fr": ..., "en": ...} (texte libre si `long`).
static func _names(c: Check, v: Variant, what: String, long := false) -> bool:
	if not v is Dictionary:
		c.bad("%s : {\"fr\", \"en\"} attendu" % what, "%s: {\"fr\", \"en\"} expected" % what)
		return false
	for k in v:
		if not k in ["fr", "en"]:
			c.bad("%s : clé inconnue « %s »" % [what, clean_display(str(k), 24)], "%s: unknown key \"%s\"" % [what, clean_display(str(k), 24)])
			return false
		var s: Variant = v[k]
		if not s is String or not (text_ok(s) if long else name_ok(s)):
			c.bad("%s : texte refusé (trop long, caractère de contrôle, balise ou chemin)" % what,
				"%s: text refused (too long, control character, tag or path)" % what)
			return false
	return true


static func _keys(c: Check, d: Dictionary, allowed: Dictionary, what: String) -> bool:
	for k in d:
		if not (k is String and allowed.has(k)):
			c.bad("%s : clé inconnue « %s »" % [what, clean_display(str(k), 24)], "%s: unknown key \"%s\"" % [what, clean_display(str(k), 24)])
			return false
	return true


static func _floor_index(c: Check, v: Variant, what: String) -> bool:
	return _int(c, v, 0, c.floors - 1, what + " (étage)")


## Valeur selon une règle du schéma.
static func _rule(c: Check, rule: Variant, v: Variant, what: String) -> bool:
	var sc := schema()
	if rule is Dictionary and rule.has("prefab_ref"):
		# Format 10 : un décor du catalogue, ou un prefab de la carte « map:<pid> »
		# (son existence est vérifiée avec les fichiers de prefab, check_texts).
		if not (v is String and ((rule.prefab_ref as Dictionary).has(v) or MapPrefabLib.is_ref(v))):
			c.bad("%s : décor inconnu « %s »" % [what, clean_display(str(v), 24)], "%s: unknown prop \"%s\"" % [what, clean_display(str(v), 24)])
			return false
		return true
	if rule is Dictionary:
		# Valeurs permises (texte, nombre, vrai / faux) : jamais un tableau ni un objet.
		if not ((v is String or v is bool or v is float or v is int) and rule.has(_enum_key(v))):
			c.bad("%s : valeur non autorisée « %s »" % [what, clean_display(str(v), 24)], "%s: value not allowed \"%s\"" % [what, clean_display(str(v), 24)])
			return false
		return true
	var r := String(rule)
	match r:
		"name":
			return _name(c, v, what)
		"names":
			return _names(c, v, what)
		"floor":
			return _floor_index(c, v, what)
		"zone_ref":
			if not (v is String and (v == "" or id_ok(v))):
				c.bad("%s : zone invalide" % what, "%s: invalid zone" % what)
				return false
			return true
		"color":
			if not (v is String and v.length() == 7 and v.begins_with("#") and v.substr(1).is_valid_hex_number()):
				c.bad("%s : couleur #rrggbb attendue" % what, "%s: #rrggbb colour expected" % what)
				return false
			return true
		"polygon":
			c.bad("%s : liste de points inattendue" % what, "%s: unexpected point list" % what)
			return false
		"forme":
			return _forme(c, v, what)
		"bool":
			if not v is bool:
				c.bad("%s : vrai / faux attendu" % what, "%s: true / false expected" % what)
				return false
			return true
		"pt":
			return _pt(c, v, what)
		"rect":
			return _rect(c, v, what)
		"id":
			return _id(c, v, what, false)
		"dir":
			if not (v is String and sc.dirs.has(v)):
				c.bad("%s : direction n, e, s ou o attendue" % what, "%s: direction n, e, s or o expected" % what)
				return false
			return true
		"prix":
			return _int(c, v, 0, MAX_PRICE, what)
		"surface":
			if not (v is String and sc.surfaces.has(v)):
				c.bad("%s : surface inconnue « %s »" % [what, clean_display(str(v), 24)], "%s: unknown surface \"%s\"" % [what, clean_display(str(v), 24)])
				return false
			return true
	if r.begins_with("num:"):
		var p := r.split(":")
		return _num(c, v, float(p[1]), float(p[2]), what)
	if r.begins_with("int:"):
		var p := r.split(":")
		return _int(c, v, int(float(p[1])), int(float(p[2])), what)
	if r.begins_with("points:"):
		# Liste de points [x, y] (format 9 : sommets d'une barrière invisible).
		var p := r.split(":")
		var lo := int(p[1])
		var hi := int(p[2])
		if not (v is Array and v.size() >= lo and v.size() <= hi):
			c.bad("%s : liste de %d à %d points attendue" % [what, lo, hi], "%s: list of %d to %d points expected" % [what, lo, hi])
			return false
		for q in v:
			if not _pt(c, q, what):
				return false
		return true
	if r.begins_with("dims:"):
		# Liste de nombres bornés (format 11 : zone d'un effet, en m).
		var p := r.split(":")
		if not (v is Array and v.size() >= int(p[1]) and v.size() <= int(p[2])):
			c.bad("%s : liste de %s à %s nombres attendue" % [what, p[1], p[2]], "%s: list of %s to %s numbers expected" % [what, p[1], p[2]])
			return false
		for x in v:
			if not _num(c, x, float(p[3]), float(p[4]), what):
				return false
		return true
	if r.begins_with("text:"):
		if not (v is String and name_ok(v, int(r.substr(5)))):
			c.bad("%s : texte refusé (trop long, caractère de contrôle, balise ou chemin)" % what,
				"%s: text refused (too long, control character, tag or path)" % what)
			return false
		return true
	# Valeur d'un type ajouté sans schéma : un scalaire court et sûr.
	if v is bool or ((v is float or v is int) and _num(c, v, -1000.0, 1000.0, what)):
		return true
	if v is String and id_ok(v):
		return true
	c.bad("%s : valeur refusée" % what, "%s: value refused" % what)
	return false


## Forme de base d'une pièce (format 4, MapShapes) : {type, centre, rx, ry,
## points (3 à 64), angle (0 à 360), bras (0,2 à 0,8)}, rien d'autre ; nombres
## finis et bornés.
static func _forme(c: Check, v: Variant, what: String) -> bool:
	if not v is Dictionary:
		c.bad("%s : forme {type, centre...} attendue" % what, "%s: shape {type, centre...} expected" % what)
		return false
	var allowed := {"type": 1, "centre": 1, "rx": 1, "ry": 1, "points": 1, "angle": 1, "bras": 1}
	if not _keys(c, v, allowed, what):
		return false
	if not (v.get("type") is String and String(v.type) in MapShapes.TYPES):
		c.bad("%s : type de forme inconnu" % what, "%s: unknown shape type" % what)
		return false
	if not (v.has("centre") and _pt(c, v.centre, what + " (centre)")):
		if not v.has("centre"):
			c.bad("%s : centre de la forme absent" % what, "%s: missing shape centre" % what)
		return false
	if not (v.has("rx") and _num(c, v.rx, 0.1, MapShapes.MAX_RADIUS, what + " (rx)")):
		if not v.has("rx"):
			c.bad("%s : rayon de la forme absent" % what, "%s: missing shape radius" % what)
		return false
	if v.has("ry") and not _num(c, v.ry, 0.1, MapShapes.MAX_RADIUS, what + " (ry)"):
		return false
	if v.has("points") and not _int(c, v.points, MapShapes.MIN_POINTS, MapShapes.MAX_POINTS, what + " (points)"):
		return false
	if v.has("angle") and not _num(c, v.angle, 0.0, 360.0, what + " (angle)"):
		return false
	if v.has("bras") and not _num(c, v.bras, 0.2, 0.8, what + " (bras)"):
		return false
	return true


# Fichiers.

static func _check_carte(c: Check, d: Dictionary) -> void:
	var what := "carte.json"
	if not _keys(c, d, {"format": 1, "id": 1, "nom": 1, "description": 1, "musique": 1, "hauteur_portes": 1, "lampes_auto": 1, "etages": 1,
			MapCatalog.OVERLAP_KEY: 1}, what):
		return
	if d.has("format"):
		_int(c, d.format, 1, EditorMap.FORMAT, what + " (format)")
	if not (d.get("id") is String and map_id_ok(d.get("id"))):
		c.bad("carte.json : identifiant de carte invalide (minuscules, chiffres et _ seulement)", "carte.json: invalid map identifier (lowercase letters, digits and _ only)")
	if d.has("nom"):
		_names(c, d.nom, what + " (nom)")
	if d.has("description"):
		_names(c, d.description, what + " (description)", true)
	if d.has("musique") and not (d.musique is String and schema().musics.has(d.musique)):
		c.bad("carte.json : musique inconnue", "carte.json: unknown music")
	if d.has("hauteur_portes"):
		_num(c, d.hauteur_portes, 1.5, 10.0, what + " (hauteur_portes)")
	if d.has("lampes_auto"):
		_rule(c, "bool", d.lampes_auto, what + " (lampes_auto)")
	if d.has(MapCatalog.OVERLAP_KEY):
		# Format 9 : décor et obstacles qui peuvent se chevaucher (vrai / faux).
		_rule(c, "bool", d[MapCatalog.OVERLAP_KEY], what + " (%s)" % MapCatalog.OVERLAP_KEY)
	var et: Variant = d.get("etages", [])
	if not (et is Array and et.size() <= MAX_FLOORS):
		c.bad("carte.json : étages (au plus %d)" % MAX_FLOORS, "carte.json: floors (at most %d)" % MAX_FLOORS)
		return
	for e in et:
		if not e is Dictionary or not _keys(c, e, {"sol": 1, "hauteur": 1}, what + " (étage)"):
			c.bad("carte.json : étage invalide", "carte.json: invalid floor")
			return
		if e.has("sol"):
			_num(c, e.sol, -20.0, 200.0, what + " (sol)")
		if e.has("hauteur"):
			_num(c, e.hauteur, 2.0, 30.0, what + " (hauteur)")
	c.floors = maxi(1, et.size())


static func _check_list_file(c: Check, d: Dictionary, file: String, key: String, max_n: int, each: Callable) -> void:
	if not _keys(c, d, {key: 1}, file):
		return
	var list: Variant = d.get(key, [])
	if not list is Array:
		c.bad("%s : liste « %s » attendue" % [file, key], "%s: list \"%s\" expected" % [file, key])
		return
	if list.size() > max_n:
		c.bad("%s : trop d'éléments (%d, au plus %d)" % [file, list.size(), max_n], "%s: too many elements (%d, at most %d)" % [file, list.size(), max_n])
		return
	for i in list.size():
		if c.reasons.size() >= MAX_REASONS:
			return
		var e: Variant = list[i]
		if not e is Dictionary:
			c.bad("%s : élément %d invalide" % [file, i + 1], "%s: invalid element %d" % [file, i + 1])
			continue
		each.call(c, e, "%s, %s" % [file, clean_display(str(e.get("id", i + 1)), 24)])


static func _check_room(c: Check, e: Dictionary, what: String) -> void:
	var rk: Dictionary = schema().room_keys
	if not _keys(c, e, rk, what):
		return
	_id(c, e.get("id"), what)
	for k in e:
		if not k in ["id", "contour"]:
			_rule(c, rk[k], e[k], "%s (%s)" % [what, k])
	var poly: Variant = e.get("contour")
	if not (poly is Array and poly.size() >= 3 and poly.size() <= MAX_VERTICES):
		c.bad("%s : contour de 3 à %d sommets attendu" % [what, MAX_VERTICES], "%s: outline of 3 to %d vertices expected" % [what, MAX_VERTICES])
		return
	c.vertices += poly.size()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		if not _pt(c, p, what):
			return
		lo = lo.min(Vector2(p[0], p[1]))
		hi = hi.max(Vector2(p[0], p[1]))
	c.area += (hi.x - lo.x) * (hi.y - lo.y)


static func _check_opening(c: Check, e: Dictionary, what: String) -> void:
	var sc := schema()
	var t: Variant = e.get("type")
	if not (t is String and sc.kinds.has(t) and sc.kinds[t].file == "ouvertures.json"):
		c.bad("%s : type d'ouverture inconnu « %s »" % [what, clean_display(str(t), 24)], "%s: unknown opening type \"%s\"" % [what, clean_display(str(t), 24)])
		return
	_check_element(c, e, sc.kinds[t], what)


static func _check_object(c: Check, e: Dictionary, what: String) -> void:
	var sc := schema()
	var t: Variant = e.get("type")
	if not (t is String and sc.kinds.has(t) and sc.kinds[t].file == "objets.json"):
		c.bad("%s : type d'objet inconnu « %s »" % [what, clean_display(str(t), 24)], "%s: unknown object type \"%s\"" % [what, clean_display(str(t), 24)])
		return
	var before := c.reasons.size()
	_check_element(c, e, sc.kinds[t], what)
	if t == "bloc_invisible" and c.reasons.size() == before and not (e.has("sommets") or e.has("rect")):
		# Barrière invisible : un polygone (format 9) ou un rectangle d'avant.
		c.bad("%s : barrière sans « sommets » ni « rect »" % what, "%s: barrier without \"sommets\" nor \"rect\"" % what)
	if t == "effet":
		# Format 10 : nombre d'effets borné (particules, lumières).
		c.effects += 1
		if c.effects == MAX_EFFECTS + 1:
			c.bad("objets.json : trop d'effets (au plus %d)" % MAX_EFFECTS, "objets.json: too many effects (at most %d)" % MAX_EFFECTS)
		# Format 11 : zone de l'effet dans SES bornes (dimensions et taille propres à l'effet).
		if c.reasons.size() == before and e.has("zone") and not MapCatalog.effect_zone_ok(String(e.get("effet", "")), e.zone):
			c.bad("%s : zone de l'effet hors de ses bornes" % what, "%s: effect zone out of its bounds" % what)
	if t == "prefab" and c.reasons.size() == before and (e.has("mur") or e.has("angle") or e.has("hauteur")) \
			and MapCatalog.prefab_mount(String(e.get("prefab", ""))) != "mur":
		# Format 11 : « mur », « angle », « hauteur » seulement pour un décor mural.
		c.bad("%s : réglage de mur sur un décor qui n'est pas mural" % what, "%s: wall setting on a prop that is not wall-mounted" % what)
	if t == "boite" and c.reasons.size() == before and e.has("rot") and (e.has("mur") or e.has("angle")):
		# Format 15 : « rot » seulement pour une boîte posée au sol (sans « mur »).
		# La boîte de départ (outil boite_depart) a le même type « boite ».
		c.bad("%s : rotation au sol sur une boîte contre un mur" % what, "%s: floor rotation on a box against a wall" % what)
	if t in ["prefab", "luminaire", "effet"] and c.reasons.size() == before:
		# Format 12 : « z » seulement pour un décor posé au sol, « descente »
		# seulement pour ce qui est accroché au plafond.
		var m := MapVertical.mount_of(e)
		if e.has("z") and (t != "prefab" or m != "sol"):
			c.bad("%s : hauteur de pose « z » sur un élément qui n'est pas un décor au sol" % what, "%s: \"z\" height on an element that is not a floor prop" % what)
		elif e.has("descente") and m != "plafond":
			c.bad("%s : « descente » sur un élément qui n'est pas au plafond" % what, "%s: \"descente\" on an element that is not on the ceiling" % what)
	if t == "mur_courbe" and c.reasons.size() == before:
		# Mur courbe : tout l'arc dans le terrain (0 à MAX_COORD).
		var bb := MapGeom.bbox(MapShapes.wall_arc(e))
		if bb.position.x < -0.001 or bb.position.y < -0.001 or bb.end.x > MAX_COORD or bb.end.y > MAX_COORD:
			c.bad("%s : mur courbe hors du terrain" % what, "%s: curved wall off the board" % what)


static func _check_element(c: Check, e: Dictionary, kind: Dictionary, what: String) -> void:
	var keys: Dictionary = kind.keys
	for k in e:
		if c.reasons.size() >= MAX_REASONS:
			return
		match k:
			"id":
				_id(c, e.id, what)
			"type":
				pass
			"etage":
				_floor_index(c, e.etage, what)
			_:
				if not (k is String and keys.has(k)):
					c.bad("%s : clé inconnue « %s »" % [what, clean_display(str(k), 24)], "%s: unknown key \"%s\"" % [what, clean_display(str(k), 24)])
					return
				_rule(c, keys[k], e[k], "%s (%s)" % [what, k])
	if not e.has("id"):
		c.bad("%s : identifiant absent" % what, "%s: missing identifier" % what)
	for k in kind.get("required", []):
		if not e.has(k):
			c.bad("%s : clé « %s » absente" % [what, k], "%s: missing key \"%s\"" % [what, k])
			return


static func _check_zones(c: Check, d: Dictionary) -> void:
	var what := "zones.json"
	if not _keys(c, d, {"depart": 1, "zones": 1}, what):
		return
	if d.has("depart") and not (d.depart is String and (d.depart == "" or id_ok(d.depart))):
		c.bad("zones.json : zone de départ invalide", "zones.json: invalid start zone")
	var list: Variant = d.get("zones", [])
	if not (list is Array and list.size() <= MAX_ZONES):
		c.bad("zones.json : zones (au plus %d)" % MAX_ZONES, "zones.json: zones (at most %d)" % MAX_ZONES)
		return
	for z in list:
		if c.reasons.size() >= MAX_REASONS:
			return
		var zk: Dictionary = schema().zone_keys
		if not z is Dictionary or not _keys(c, z, zk, what):
			c.bad("zones.json : zone invalide", "zones.json: invalid zone")
			return
		_id(c, z.get("id"), what)
		for k in z:
			if k != "id":
				_rule(c, zk[k], z[k], "%s (%s)" % [what, k])


# ------------------------------------------------------------------ paquet réseau

## Paquet canonique des cinq textes : JSON trié, UTF-8. Carte avec des
## prefabs (format 10) : paquet au format 2, les entrées de prefab en plus
## (prefabs/<pid>/prefab.json, prefabs/<pid>/model.glb en base64) ; une carte
## sans prefab garde exactement le paquet (et l'empreinte) d'avant.
static func pack(texts: Dictionary) -> PackedByteArray:
	var files := {}
	for f in EditorMap.FILES:
		files[f] = String(texts.get(f, ""))
	var fmt := PACKAGE_FORMAT
	for k in texts:
		if not MapPrefabLib.parse_key(k).is_empty():
			files[k] = String(texts[k])
			fmt = PACKAGE_FORMAT_PREFABS
	return JSON.stringify({"format": fmt, "fichiers": files}, "", true).to_utf8_buffer()


## Paquet d'une carte déjà contrôlée : {bytes, sha, texts}.
static func package_of(m: EditorMap) -> Dictionary:
	var texts := m.file_texts()
	var b := pack(texts)
	return {"bytes": b, "sha": sha256_hex(b), "texts": texts}


## Paquet reçu -> {ok, texts, reasons}. Vérifie la taille, l'UTF-8, la forme
## (exactement les cinq fichiers) et que le paquet est canonique (repaqueté à
## l'identique : même empreinte sur toutes les machines).
static func unpack(b: PackedByteArray) -> Dictionary:
	var bad := func(fr: String, en: String) -> Dictionary: return {"ok": false, "reasons": [[fr, en]]}
	if b.is_empty() or b.size() > MAX_TRANSFER_BYTES:
		return bad.call("paquet de carte vide ou trop volumineux", "map package empty or too large")
	var s: Variant = decode_utf8(b)
	if s == null:
		return bad.call("paquet de carte : texte UTF-8 invalide", "map package: invalid UTF-8 text")
	var d := json_depth(s)
	if d < 0 or d > 2:
		return bad.call("paquet de carte : JSON mal formé", "map package: malformed JSON")
	var v: Variant = parse_json(s)
	if not (v is Dictionary and v.size() == 2 and v.get("format") is float and int(v.format) in [PACKAGE_FORMAT, PACKAGE_FORMAT_PREFABS] and v.get("fichiers") is Dictionary):
		return bad.call("paquet de carte : format inconnu", "map package: unknown format")
	# Format 1 (carte sans prefab) : 2 Mo au plus, comme avant.
	if int(v.format) == PACKAGE_FORMAT and b.size() > MAX_PACKAGE_BYTES:
		return bad.call("paquet de carte vide ou trop volumineux", "map package empty or too large")
	var files: Dictionary = v.fichiers
	var texts := {}
	var extra := 0
	for k in files:
		var is_prefab := not MapPrefabLib.parse_key(k).is_empty()
		if not (k is String and (k in EditorMap.FILES or (is_prefab and int(v.format) == PACKAGE_FORMAT_PREFABS)) and files[k] is String):
			return bad.call("paquet de carte : fichier non autorisé", "map package: file not allowed")
		if is_prefab:
			extra += 1
		texts[k] = files[k]
	if texts.size() - extra != EditorMap.FILES.size():
		return bad.call("paquet de carte : fichiers manquants", "map package: missing files")
	if pack(texts) != b:
		return bad.call("paquet de carte non canonique", "map package not canonical")
	return {"ok": true, "texts": texts, "reasons": []}


## Contrôle complet d'un paquet reçu dont on attend l'empreinte `sha` :
## {ok, code, reasons, texts, map}.
static func check_package(b: PackedByteArray, sha: String) -> Dictionary:
	if sha256_hex(b) != sha:
		return {"ok": false, "code": "hash", "reasons": [REASONS.hash]}
	var u := unpack(b)
	if not u.ok:
		return {"ok": false, "code": "contenu", "reasons": u.reasons}
	var r := check_full(u.texts)
	if not r.ok:
		return r
	if not is_canonical(u.texts, r.map):
		return {"ok": false, "code": "contenu", "reasons": [["carte non canonique (réécrite par l'éditeur, elle change)", "map not canonical (it changes when the editor rewrites it)"]]}
	return {"ok": true, "code": "", "reasons": [], "texts": u.texts, "map": r.map}


## Annonce d'une carte par l'hôte : {sha, size, chunk, chunks, nom: {fr, en},
## n (numéro de l'annonce : les morceaux d'une annonce précédente sont ignorés)}.
## Code de raison (REASONS) si elle est invalide, "" sinon.
static func check_offer(o: Variant) -> String:
	if not o is Dictionary or o.size() != 6:
		return "offre"
	for k in ["sha", "size", "chunk", "chunks", "nom", "n"]:
		if not o.has(k):
			return "offre"
	var sha: Variant = o["sha"]
	var size: Variant = o["size"]
	var chunk: Variant = o["chunk"]
	var chunks: Variant = o["chunks"]
	if not (sha is String and sha_ok(sha)):
		return "offre"
	if not (size is int and chunk is int and chunks is int and o["n"] is int and o["n"] >= 0):
		return "offre"
	if size < 1 or size > MAX_TRANSFER_BYTES:
		return "trop_gros"
	if chunk < MIN_CHUNK_BYTES or chunk > CHUNK_BYTES or chunks != ceili(float(size) / chunk):
		return "offre"
	var n: Variant = o["nom"]
	if not (n is Dictionary and n.size() <= 2):
		return "offre"
	for k in n:
		if not (k in ["fr", "en"] and n[k] is String and name_ok(n[k])):
			return "offre"
	return ""


# ------------------------------------------------------------------ fichiers : cache, dossier, archive

static func cache_root() -> String:
	if cache_override != "":
		return cache_override
	if AutotestMode.is_running():
		return ProjectSettings.globalize_path("res://tests/_out/maps_cache_%s" % AutotestMode.scenario_name())
	return "user://maps_cache"


## Dossier du cache d'une carte : son empreinte, jamais un nom venu du réseau.
static func cache_dir(sha: String) -> String:
	assert(sha_ok(sha))
	return cache_root().path_join(sha)


static func is_cached(sha: String) -> bool:
	if not sha_ok(sha):
		return false
	for f in EditorMap.FILES:
		if not FileAccess.file_exists(cache_dir(sha).path_join(f)):
			return false
	return true


## Enregistre les cinq textes (déjà contrôlés) dans le cache.
static func store(sha: String, texts: Dictionary) -> Error:
	if not sha_ok(sha):
		return ERR_INVALID_PARAMETER
	var dir := cache_dir(sha)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return err
	for f in EditorMap.FILES:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		if fa == null:
			return FileAccess.get_open_error()
		fa.store_string(String(texts[f]))
		fa.close()
	# Format 10 : prefabs de la carte (prefabs/<pid>/prefab.json et model.glb).
	var perr := MapPrefabLib.write_dir(dir, texts)
	if perr != OK:
		return perr
	prune_cache(sha)
	return OK


## Cache borné : au-delà de MAX_CACHED cartes, les plus anciennes sont
## effacées (seulement des dossiers nommés par une empreinte, et seulement
## leurs cinq fichiers). `keep` n'est jamais effacée.
static func prune_cache(keep := "") -> void:
	var root := cache_root()
	if not DirAccess.dir_exists_absolute(root):
		return
	var dirs := []
	for d in DirAccess.get_directories_at(root):
		if sha_ok(d) and d != keep:
			dirs.append([FileAccess.get_modified_time(root.path_join(d).path_join("carte.json")), d])
	if dirs.size() < MAX_CACHED:
		return
	dirs.sort()
	for i in dirs.size() - (MAX_CACHED - 1):
		var dir := root.path_join(String(dirs[i][1]))
		for f in EditorMap.FILES:
			DirAccess.remove_absolute(dir.path_join(f))
		MapPrefabLib.remove_all(dir)
		DirAccess.remove_absolute(dir)


## Cinq textes d'un dossier, tailles vérifiées avant lecture : {texts, reasons}.
## Seuls les cinq fichiers de la carte sont lus, rien d'autre du dossier.
static func read_dir_texts(dir: String) -> Dictionary:
	var texts := {}
	var total := 0
	for f in EditorMap.FILES:
		var p := dir.path_join(f)
		if not FileAccess.file_exists(p):
			return {"texts": {}, "reasons": [["fichier %s absent" % f, "missing file %s" % f]]}
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa == null:
			return {"texts": {}, "reasons": [["fichier %s illisible" % f, "unreadable file %s" % f]]}
		total += fa.get_length()
		if total > MAX_PACKAGE_BYTES:
			return {"texts": {}, "reasons": [["carte trop volumineuse", "map too large"]]}
		var s: Variant = decode_utf8(fa.get_buffer(fa.get_length()))
		fa.close()
		if s == null:
			return {"texts": {}, "reasons": [["%s : texte UTF-8 invalide" % f, "%s: invalid UTF-8 text" % f]]}
		texts[f] = s
	# Format 10 : prefabs de la carte (tailles bornées avant lecture).
	var pf := MapPrefabLib.read_dir(dir)
	if not (pf.reasons as Array).is_empty():
		return {"texts": {}, "reasons": pf.reasons}
	texts.merge(pf.texts)
	return {"texts": texts, "reasons": []}


## Carte du cache : empreinte recalculée (dossier modifié = refus) et contrôle
## de sûreté ; `playable` : validateur aussi. {ok, map, texts, reasons}.
static func load_cached(sha: String, playable := false) -> Dictionary:
	if not is_cached(sha):
		return {"ok": false, "reasons": [["carte absente du cache", "map not in the cache"]]}
	var got := read_dir_texts(cache_dir(sha))
	if not got.reasons.is_empty():
		return {"ok": false, "reasons": got.reasons}
	if sha256_hex(pack(got.texts)) != sha:
		return {"ok": false, "reasons": [REASONS.hash]}
	var r := check_full(got.texts) if playable else check_texts(got.texts)
	r["texts"] = got.texts
	return r


## Carte locale (user://maps/<id>/) prête à jouer : sûreté + jouabilité.
static func load_local(dir: String, playable := true) -> Dictionary:
	var got := read_dir_texts(dir)
	if not got.reasons.is_empty():
		return {"ok": false, "reasons": got.reasons}
	var r := check_full(got.texts) if playable else check_texts(got.texts)
	r["texts"] = got.texts
	return r


static func _u16(b: PackedByteArray, i: int) -> int:
	return b[i] | (b[i + 1] << 8)


static func _u32(b: PackedByteArray, i: int) -> int:
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)


## Archive .zip -> {texts, reasons}. Le répertoire central est lu AVANT toute
## extraction : taille de l'archive, nombre d'entrées, tailles décompressées
## (archive « bombe » refusée). Seuls les cinq JSON (et, format 10, les
## fichiers de prefab prefabs/<pid>/prefab.json et model.glb, aux tailles
## bornées par MapPrefabLib) sont extraits, en mémoire (jamais sur le disque),
## le reste de l'archive est ignoré.
static func read_zip_texts(path: String) -> Dictionary:
	var bad := func(fr: String, en: String) -> Dictionary: return {"texts": {}, "reasons": [[fr, en]]}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return bad.call("archive illisible", "unreadable archive")
	if fa.get_length() > MAX_ZIP_BYTES or fa.get_length() < 22:
		fa.close()
		return bad.call("archive trop volumineuse ou vide", "archive too large or empty")
	var b := fa.get_buffer(fa.get_length())
	fa.close()
	var eocd := -1
	for i in range(b.size() - 22, maxi(-1, b.size() - 22 - 65536), -1):
		if b[i] == 0x50 and b[i + 1] == 0x4b and b[i + 2] == 0x05 and b[i + 3] == 0x06:
			eocd = i
			break
	if eocd < 0:
		return bad.call("archive .zip invalide", "invalid .zip archive")
	var entries := _u16(b, eocd + 10)
	var off := _u32(b, eocd + 16)
	if entries > MAX_ZIP_ENTRIES:
		return bad.call("archive : trop de fichiers (%d)" % entries, "archive: too many files (%d)" % entries)
	var wanted := {}   # nom dans l'archive -> taille décompressée
	var seen := {}
	var total := 0
	var prefab_entries := {}   # nom dans l'archive -> [clé, taille, dossier]
	var pf_total := 0
	var folder := ""
	for n in entries:
		if off < 0 or off + 46 > b.size() or _u32(b, off) != 0x02014b50:
			return bad.call("archive .zip invalide", "invalid .zip archive")
		var usize := _u32(b, off + 24)
		var nlen := _u16(b, off + 28)
		var next := off + 46 + nlen + _u16(b, off + 30) + _u16(b, off + 32)
		if next > b.size():
			return bad.call("archive .zip invalide", "invalid .zip archive")
		var raw := b.slice(off + 46, off + 46 + nlen)
		off = next
		var name: Variant = decode_utf8(raw)
		if name == null:
			continue
		var base := String(name).get_file()
		# Format 10 : prefabs de la carte (prefabs/<pid>/prefab.json, model.glb),
		# à la racine ou dans le dossier de l'archive.
		var rel := String(name)
		var pk := MapPrefabLib.parse_key(rel)
		if pk.is_empty() and rel.count("/") == 3:
			rel = rel.substr(rel.find("/") + 1)
			pk = MapPrefabLib.parse_key(rel)
		if not pk.is_empty():
			if usize == 0xFFFFFFFF or usize > (MapPrefabLib.MAX_MODEL_BYTES if pk[1] == MapPrefabLib.MODEL_FILE else MapPrefabLib.MAX_DEF_BYTES):
				return bad.call("archive : prefab %s trop volumineux" % pk[0], "archive: prefab %s too large" % pk[0])
			if pk[1] == MapPrefabLib.MODEL_FILE:
				pf_total += usize
				if pf_total > MapPrefabLib.MAX_MODELS_BYTES:
					return bad.call("archive : modèles trop volumineux", "archive: models too large")
			if not seen.has(rel):
				seen[rel] = true
				prefab_entries[String(name)] = [rel, usize, String(name).trim_suffix(rel)]
			continue
		if not base in EditorMap.FILES or seen.has(base):
			continue
		folder = String(name).trim_suffix(base)
		if usize == 0xFFFFFFFF or usize > MAX_PACKAGE_BYTES:
			return bad.call("archive : %s trop volumineux" % base, "archive: %s too large" % base)
		total += usize
		if total > MAX_PACKAGE_BYTES:
			return bad.call("archive : carte trop volumineuse", "archive: map too large")
		seen[base] = true
		wanted[String(name)] = usize
	var r := ZIPReader.new()
	if r.open(path) != OK:
		return bad.call("archive illisible", "unreadable archive")
	var texts := {}
	for name in wanted:
		var data := r.read_file(name)
		if data.size() != int(wanted[name]):
			r.close()
			return bad.call("archive : taille de %s incorrecte" % String(name).get_file(), "archive: wrong size for %s" % String(name).get_file())
		var s: Variant = decode_utf8(data)
		if s == null:
			r.close()
			return bad.call("archive : %s n'est pas du texte UTF-8" % String(name).get_file(), "archive: %s is not UTF-8 text" % String(name).get_file())
		texts[String(name).get_file()] = s
	for name in prefab_entries:
		var e: Array = prefab_entries[name]
		# Seulement les prefabs du dossier des cinq fichiers.
		if String(e[2]) != folder:
			continue
		var data := r.read_file(name)
		if data.size() != int(e[1]):
			r.close()
			return bad.call("archive : taille de %s incorrecte" % String(e[0]), "archive: wrong size for %s" % String(e[0]))
		if String(e[0]).ends_with(MapPrefabLib.MODEL_FILE):
			texts[String(e[0])] = Marshalls.raw_to_base64(data)
		else:
			var s: Variant = decode_utf8(data)
			if s == null:
				r.close()
				return bad.call("archive : %s n'est pas du texte UTF-8" % String(e[0]), "archive: %s is not UTF-8 text" % String(e[0]))
			texts[String(e[0])] = s
	r.close()
	return {"texts": texts, "reasons": []}
