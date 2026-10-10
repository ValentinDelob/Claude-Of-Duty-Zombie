extends TestCase
## Cartes perso en multijoueur : paquet canonique et empreinte, réception par
## morceaux (MapTransfer), contrôle de légitimité (CustomMapGuard), cache par
## hash, archive .zip. Aucun fichier du joueur : cache et archives dans tests/_out.

const DRAFT := "res://assets/maps/draft_arena/"
var _cache := ""


func before_each() -> void:
	_cache = ProjectSettings.globalize_path("res://tests/_out/maps_cache_unit")
	_rm(_cache)
	CustomMapGuard.cache_override = _cache


func after_each() -> void:
	_rm(_cache)
	CustomMapGuard.cache_override = ""


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _draft_texts() -> Dictionary:
	return EditorMap.load_dir(DRAFT).file_texts()


## Textes de DRAFT ARENA avec un fichier remplacé par `v` (texte, ou valeur JSON).
func _with(file: String, v: Variant) -> Dictionary:
	var t := _draft_texts()
	t[file] = v if v is String else JSON.stringify(v)
	return t


func _refused(texts: Dictionary, what: String) -> void:
	var r := CustomMapGuard.check_texts(texts)
	assert_false(r.ok, "refus attendu : " + what)
	var reasons: Array = r.get("reasons", [])
	assert_true(not reasons.is_empty() and reasons[0] is Array and reasons[0].size() == 2 and String(reasons[0][0]) != "" and String(reasons[0][1]) != "",
		"raison FR/EN : %s -> %s" % [what, str(reasons)])


func _objets_plus(extra: Dictionary) -> Dictionary:
	var o = JSON.parse_string(_draft_texts()["objets.json"])
	o.objets.append(extra)
	return o


# ------------------------------------------------------------------ paquet et empreinte

func test_draft_arena_package_accepted() -> void:
	var m := EditorMap.load_dir(DRAFT)
	var pk := CustomMapGuard.package_of(m)
	assert_true(CustomMapGuard.sha_ok(pk.sha), "empreinte SHA-256 : " + pk.sha)
	assert_true(pk.bytes.size() < CustomMapGuard.MAX_PACKAGE_BYTES)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "DRAFT ARENA acceptée : " + str(chk.get("reasons")))
	# Paquet stable : même carte relue -> même octets, même empreinte ;
	# la carte reçue, repaquetée, redonne exactement le même paquet.
	assert_eq(CustomMapGuard.package_of(EditorMap.load_dir(DRAFT)).sha, pk.sha, "empreinte stable")
	assert_eq(CustomMapGuard.package_of(chk.map).sha, pk.sha, "repaquetage identique")
	var u := CustomMapGuard.unpack(pk.bytes)
	assert_true(u.ok and u.texts.size() == 5 and u.texts.keys().all(func(k): return k in EditorMap.FILES), "exactement les cinq JSON")
	# Une valeur changée change l'empreinte.
	var m2 := EditorMap.load_dir(DRAFT)
	m2.ouvertures[0]["prix"] = 1500
	assert_true(CustomMapGuard.package_of(m2).sha != pk.sha, "empreinte différente si la carte change")


func test_package_refusals() -> void:
	var pk := CustomMapGuard.package_of(EditorMap.load_dir(DRAFT))
	assert_eq(CustomMapGuard.check_package(pk.bytes, "0".repeat(64)).code, "hash", "empreinte annoncée fausse")
	var flipped: PackedByteArray = pk.bytes.duplicate()
	flipped[100] = flipped[100] ^ 1
	assert_eq(CustomMapGuard.check_package(flipped, pk.sha).code, "hash", "octet modifié")
	# Paquet non canonique (espaces ajoutés dans un JSON) : refusé même avec la bonne empreinte.
	var texts: Dictionary = pk.texts.duplicate()
	texts["carte.json"] = String(texts["carte.json"]).replace("{", "{  ")
	var odd := CustomMapGuard.pack(texts)
	var r := CustomMapGuard.check_package(odd, CustomMapGuard.sha256_hex(odd))
	assert_false(r.ok, "paquet non canonique refusé")
	# Fichier en plus dans le paquet, UTF-8 invalide, paquet vide.
	var d = JSON.parse_string(pk.bytes.get_string_from_utf8())
	d.fichiers["script.gd"] = "extends Node"
	var extra := JSON.stringify(d, "", true).to_utf8_buffer()
	assert_false(CustomMapGuard.check_package(extra, CustomMapGuard.sha256_hex(extra)).ok, "fichier en plus refusé")
	var bad_utf8 := PackedByteArray([0x7b, 0xff, 0xfe, 0x7d])
	assert_false(CustomMapGuard.unpack(bad_utf8).ok, "UTF-8 invalide refusé")
	assert_false(CustomMapGuard.unpack(PackedByteArray()).ok, "paquet vide refusé")
	var huge := PackedByteArray()
	huge.resize(CustomMapGuard.MAX_PACKAGE_BYTES + 1)
	huge.fill(0x20)
	assert_false(CustomMapGuard.unpack(huge).ok, "paquet trop gros refusé")


# ------------------------------------------------------------------ réception par morceaux

func _offer(bytes: PackedByteArray, chunk := 1024) -> Dictionary:
	return {"sha": CustomMapGuard.sha256_hex(bytes), "size": bytes.size(), "chunk": chunk,
		"chunks": ceili(float(bytes.size()) / chunk), "nom": {"fr": "ARÈNE", "en": "ARENA"}, "n": 1}


func _chunk(bytes: PackedByteArray, i: int, chunk := 1024) -> PackedByteArray:
	return bytes.slice(i * chunk, mini((i + 1) * chunk, bytes.size()))


func test_transfer_in_order() -> void:
	var b: PackedByteArray = CustomMapGuard.package_of(EditorMap.load_dir(DRAFT)).bytes
	var o := _offer(b)
	assert_true(o.chunks >= 3, "plusieurs morceaux (%d)" % o.chunks)
	var rx := MapTransfer.new()
	assert_eq(rx.begin(o), "")
	for i in o.chunks:
		assert_eq(rx.add(i, _chunk(b, i)), "", "morceau %d" % i)
	assert_true(rx.complete() and rx.progress() == 100)
	var res := rx.finish()
	assert_true(res.ok and res.bytes == b, "paquet reconstitué à l'identique")


func test_transfer_refusals() -> void:
	var b: PackedByteArray = CustomMapGuard.package_of(EditorMap.load_dir(DRAFT)).bytes
	var o := _offer(b)
	# Dans le désordre.
	var rx := MapTransfer.new()
	rx.begin(o)
	assert_eq(rx.add(1, _chunk(b, 1)), "desordre", "morceau 1 avant 0")
	# En double.
	rx = MapTransfer.new()
	rx.begin(o)
	rx.add(0, _chunk(b, 0))
	assert_eq(rx.add(0, _chunk(b, 0)), "double", "morceau 0 deux fois")
	# Hors de la plage annoncée.
	rx = MapTransfer.new()
	rx.begin(o)
	assert_eq(rx.add(o.chunks + 3, PackedByteArray([1])), "desordre", "index hors plage")
	# Manquants : la fin est refusée.
	rx = MapTransfer.new()
	rx.begin(o)
	rx.add(0, _chunk(b, 0))
	assert_false(rx.complete())
	assert_eq(rx.finish().code, "manquant", "morceaux manquants")
	# Trop gros, ou d'une taille différente de celle annoncée.
	rx = MapTransfer.new()
	rx.begin(o)
	var big := PackedByteArray()
	big.resize(2048)
	assert_eq(rx.add(0, big), "trop_gros", "morceau plus gros que la taille annoncée")
	rx = MapTransfer.new()
	rx.begin(o)
	assert_eq(rx.add(0, PackedByteArray([1, 2, 3])), "morceau", "morceau trop court")
	# Empreinte fausse (un octet modifié en route).
	rx = MapTransfer.new()
	rx.begin(o)
	for i in o.chunks:
		var c := _chunk(b, i)
		if i == 1:
			c[0] = c[0] ^ 0x5A
		rx.add(i, c)
	assert_eq(rx.finish().code, "hash", "empreinte fausse")
	# Annonces invalides.
	var bad := o.duplicate(true)
	bad.chunks += 1
	assert_eq(MapTransfer.new().begin(bad), "offre", "nombre de morceaux incohérent")
	bad = o.duplicate(true)
	bad.size = CustomMapGuard.MAX_TRANSFER_BYTES + 1
	bad.chunks = ceili(float(bad.size) / bad.chunk)
	assert_eq(MapTransfer.new().begin(bad), "trop_gros", "carte annoncée trop grosse")
	bad = o.duplicate(true)
	bad.sha = "../../evil"
	assert_eq(MapTransfer.new().begin(bad), "offre", "empreinte non hexadécimale")
	bad = o.duplicate(true)
	bad.chunk = 64
	bad.chunks = ceili(float(bad.size) / 64)
	assert_eq(MapTransfer.new().begin(bad), "offre", "morceaux trop petits")
	bad = o.duplicate(true)
	bad.nom = {"fr": "[url=x]piège[/url]"}
	assert_eq(MapTransfer.new().begin(bad), "offre", "BBCode dans le nom annoncé")
	bad = o.duplicate(true)
	bad["script"] = "x"
	assert_eq(MapTransfer.new().begin(bad), "offre", "clé en plus dans l'annonce")


# ------------------------------------------------------------------ contrôle de légitimité

func test_guard_accepts_draft_arena() -> void:
	var r := CustomMapGuard.check_full(_draft_texts())
	assert_true(r.ok, "DRAFT ARENA : " + str(r.get("reasons")))
	# Textes d'origine (tels qu'écrits sur le disque) aussi.
	var got := CustomMapGuard.read_dir_texts(DRAFT)
	assert_true(got.reasons.is_empty() and CustomMapGuard.check_texts(got.texts).ok, "fichiers d'origine acceptés")


func test_guard_refusals() -> void:
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "depart", "altitude": 0, "position": [12, 20], "script": "res://x.gd"})), "clé inconnue")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "script", "altitude": 0, "position": [12, 20]})), "type inconnu")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "atout", "atout": "../../boot", "altitude": 0, "position": [12, 20], "mur": "n"})), "atout : identifiant piégé")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "arme", "arme": "res://x.gd", "altitude": 0, "position": [12, 20], "mur": "n"})), "arme : identifiant piégé")
	var c = JSON.parse_string(_draft_texts()["carte.json"])
	c.nom = {"fr": "A".repeat(20000), "en": "A"}
	_refused(_with("carte.json", c), "chaîne géante")
	c = JSON.parse_string(_draft_texts()["carte.json"])
	c.nom = {"fr": "[color=red]PIÈGE[/color]", "en": "TRAP"}
	_refused(_with("carte.json", c), "BBCode dans le nom")
	c = JSON.parse_string(_draft_texts()["carte.json"])
	c.nom = {"fr": "Nom\u0007bip", "en": "x"}
	_refused(_with("carte.json", c), "caractère de contrôle")
	c = JSON.parse_string(_draft_texts()["carte.json"])
	c.id = "../../../system32"
	_refused(_with("carte.json", c), "chemin ../ dans l'identifiant")
	c = JSON.parse_string(_draft_texts()["carte.json"])
	c.musique = "res://scripts/boot"
	_refused(_with("carte.json", c), "musique hors liste")
	# NaN / infini : 1e999 est lu comme l'infini.
	var t := _draft_texts()
	t["objets.json"] = String(t["objets.json"]).replace("[12,26]", "[1e999,26]")
	assert_true(String(t["objets.json"]).contains("1e999"))
	_refused(t, "nombre infini")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "altitude": 0, "position": [1000000, 5]})), "coordonnée énorme")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "etage": 7, "position": [5, 5]})), "clé etage du format 16")
	_refused(_with("objets.json", _objets_plus({"id": "../q1", "type": "lampe", "altitude": 0, "position": [5, 5]})), "chemin dans un identifiant d'élément")
	_refused(_with("objets.json", _objets_plus({"id": "x1", "type": "lampe", "altitude": 0, "position": [5, 5]})), "identifiant en double")
	var o = JSON.parse_string(_draft_texts()["ouvertures.json"])
	o.ouvertures[0]["prix"] = 99999999
	_refused(_with("ouvertures.json", o), "prix énorme")
	_refused(_with("pieces.json", "{ pas du json"), "faux JSON")
	_refused(_with("pieces.json", "[1, 2, 3]"), "JSON qui n'est pas un objet")
	var deep := "{\"pieces\": " + "[".repeat(60) + "]".repeat(60) + "}"
	_refused(_with("pieces.json", deep), "JSON trop profond")
	var many := {"objets": []}
	for i in CustomMapGuard.MAX_OBJECTS + 1:
		many.objets.append({"id": "l%d" % i, "type": "lampe", "altitude": 0, "position": [5, 5]})
	_refused(_with("objets.json", many), "trop d'objets")
	var p = JSON.parse_string(_draft_texts()["pieces.json"])
	var pts := []
	for i in CustomMapGuard.MAX_VERTICES + 1:
		pts.append([10 + 5 * cos(i * 0.1), 10 + 5 * sin(i * 0.1)])
	p.pieces[0]["contour"] = pts
	_refused(_with("pieces.json", p), "trop de sommets")
	var z = JSON.parse_string(_draft_texts()["zones.json"])
	z.zones[0]["sol"] = "res://evil.tres"
	_refused(_with("zones.json", z), "surface inconnue")
	var extra := _draft_texts()
	extra["evil.tscn"] = "[gd_scene]"
	_refused(extra, "fichier en plus")
	var missing := _draft_texts()
	missing.erase("zones.json")
	_refused(missing, "fichier absent")


## Carte à murs en biais (format 3) partagée en multijoueur : acceptée,
## même empreinte chez l'invité ; l'angle d'un objet mural est borné (nombre
## fini de 0 à 360) et une carte d'un format plus récent est refusée.
func test_guard_diagonal_walls() -> void:
	CustomMapGuard.reset_schema()
	var m: EditorMap = preload("res://tests/test_map_editor_diagonal.gd").diag_map()
	var pk := CustomMapGuard.package_of(m)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "carte à murs en biais acceptée : " + str(chk.get("reasons")))
	assert_eq(CustomMapGuard.package_of(chk.map).sha, pk.sha, "même empreinte chez l'invité")
	assert_true(CustomMapGuard.check_full(m.file_texts()).ok, "contrôle complet (jouabilité comprise)")
	assert_true(String(m.file_texts()["objets.json"]).contains("\"angle\":45"), "clé angle transmise")
	var kinds := MapCatalog.allowed_kinds()
	for t in ["atout", "arme", "boite", "grenades", "pap", "courant", "poste_central", "levier", "luminaire", "evacuation"]:
		assert_eq(kinds[t].keys.get("angle", {}).get("t", ""), "number", "angle admis pour %s" % t)
	for bad in ["400", "-5", "1e999", "\"nord\"", "[45]", "true"]:
		var t := m.file_texts()
		t["objets.json"] = String(t["objets.json"]).replace("\"angle\":45", "\"angle\":" + bad)
		assert_true(String(t["objets.json"]).contains("\"angle\":" + bad), "remplacement %s" % bad)
		_refused(t, "angle %s" % bad)
	# Angle sur un objet qui n'est pas mural : clé inconnue.
	var t2 := m.file_texts()
	t2["objets.json"] = String(t2["objets.json"]).replace("\"type\":\"depart\"", "\"type\":\"depart\",\"angle\":45")
	_refused(t2, "angle sur le départ")
	var t3 := m.file_texts()
	t3["carte.json"] = String(t3["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": %d" % (EditorMap.FORMAT + 1))
	_refused(t3, "format plus récent que le jeu")


## Carte à formes libres (format 4 : salle ronde de 32 points, annexe sans
## grille, mur courbe, pilier tourné) partagée en multijoueur : acceptée, même
## empreinte chez l'invité, rejouée à l'identique ; valeurs piégées refusées.
func test_guard_free_shapes_shared() -> void:
	CustomMapGuard.reset_schema()
	var m: EditorMap = preload("res://tests/test_map_editor_freeform.gd").round_map()
	var pk := CustomMapGuard.package_of(m)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "carte à formes libres acceptée : " + str(chk.get("reasons")))
	if not chk.ok:
		return
	assert_eq(CustomMapGuard.package_of(chk.map).sha, pk.sha, "même empreinte chez l'invité")
	assert_true(chk.map.same_as(m), "carte reçue identique")
	# Même description en maillage chez l'hôte et chez l'invité.
	var vh := MapRaster.build(m).v
	vh.analyze()
	var vg := MapRaster.build(chk.map).v
	vg.analyze()
	assert_eq(JSON.stringify(MapLayoutExport.build(vg), "", true), JSON.stringify(MapLayoutExport.build(vh), "", true), "géométrie identique des deux côtés")
	var t := m.file_texts()
	for s in [["pieces.json", "\"points\":32", "\"points\":65"], ["pieces.json", "\"type\":\"cercle\"", "\"type\":\"../x\""],
			["objets.json", "\"rot\":30", "\"rot\":400"], ["objets.json", "\"segments\":8", "\"segments\":0"],
			["objets.json", "\"rayon\":7", "\"rayon\":1e999"]]:
		var tt := t.duplicate()
		tt[s[0]] = String(tt[s[0]]).replace(s[1], s[2])
		assert_true(String(tt[s[0]]).contains(s[2]), "remplacement %s" % s[2])
		_refused(tt, "forme libre piégée %s" % s[2])


func test_guard_unplayable_map() -> void:
	# Sûre mais injouable (aucune pièce) : refusée par le validateur de l'éditeur.
	var blank := EditorMap.blank("vide", "VIDE", "EMPTY")
	var r := CustomMapGuard.check_texts(blank.file_texts())
	assert_true(r.ok, "carte vide sûre : " + str(r.get("reasons")))
	var full := CustomMapGuard.check_full(blank.file_texts())
	assert_false(full.ok, "carte vide injouable")
	assert_eq(full.get("code", ""), "injouable")


func test_guard_catalog_adapter() -> void:
	CustomMapGuard.reset_schema()
	var src := CustomMapGuard.catalog_source()
	assert_true(not src.items.is_empty() and not src.surfaces.is_empty() and not src.musics.is_empty(), "catalogue lu")
	var sc := CustomMapGuard.schema()
	# Types retirés du jeu (atouts, armes murales, grenades, Pack-a-Punch) :
	# encore admis, pour lire les cartes d'avant (l'éditeur les ignore).
	for t in MapCatalog.REMOVED_TYPES:
		assert_true(sc.kinds.has(t), "type d'avant %s encore lu" % t)
	for t in ["porte", "debris", "fenetre", "passage", "porte_courant"]:
		assert_true(t in sc.openings, "ouverture %s" % t)
	for t in ["boite", "teleporteur", "courant", "piege", "levier", "depart", "lampe", "escalier", "mur"]:
		assert_true(sc.kinds.has(t), "objet %s" % t)
	for s in MapCatalog.materials():
		assert_true(sc.surfaces.has(s), "surface %s" % s)


## Catalogue au format 2 (API finale de l'éditeur : MapCatalog.allowed_kinds,
## allowed_surfaces, room_keys, zone_keys), recopié en plus petit pour tester
## l'adaptateur avant la fusion.
func _v2_source() -> Dictionary:
	var dirs := {"t": "enum", "values": ["n", "e", "s", "o"]}
	var rot := {"t": "enum", "values": [0, 90, 180, 270]}
	var point := {"t": "point"}
	var price := {"t": "int", "min": 0, "max": 100000}
	var width := {"t": "number", "min": 0.5, "max": 20.0}
	var out := {}
	var add := func(file: String, type: String, keys: Dictionary, req: Array) -> void:
		var k := {"id": {"t": "id"}, "type": {"t": "enum", "values": [type]}, "altitude": {"t": "number"}}
		k.merge(keys)
		out[type] = {"file": file, "required": ["id", "type"] + req, "keys": k}
	for t in ["porte", "debris"]:
		add.call("ouvertures.json", t, {"position": point, "largeur": width, "prix": price}, ["position"])
	for t in ["porte_courant", "passage"]:
		add.call("ouvertures.json", t, {"position": point, "largeur": width}, ["position"])
	add.call("ouvertures.json", "fenetre", {"position": point, "largeur": {"t": "number", "min": 1.0, "max": 1.0}}, ["position"])
	for t in ["pilier", "piege"]:
		add.call("objets.json", t, {"rect": {"t": "rect"}}, ["rect"])
	add.call("objets.json", "escalier", {"rect": {"t": "rect"}, "monte": dirs}, ["rect"])
	add.call("objets.json", "mur", {"a": point, "b": point, "epaisseur": {"t": "enum", "values": [0.5, 1.5, 2.5]}}, ["a", "b"])
	add.call("objets.json", "atout", {"atout": {"t": "enum", "values": ["titan", "lazarus"]}, "position": point, "mur": dirs}, ["atout", "position"])
	add.call("objets.json", "arme", {"arme": {"t": "enum", "values": ["m14", "mp5k", "bowie"]}, "position": point, "mur": dirs}, ["arme", "position"])
	add.call("objets.json", "boite", {"position": point, "mur": dirs, "depart": {"t": "bool"}}, ["position"])
	for t in ["grenades", "pap", "courant", "poste_central", "levier", "evacuation"]:
		add.call("objets.json", t, {"position": point, "mur": dirs}, ["position"])
	for t in ["depart", "apparition", "teleporteur", "arrivee", "lampe", "caisse", "baril"]:
		add.call("objets.json", t, {"position": point}, ["position"])
	add.call("objets.json", "prefab", {"prefab": {"t": "enum", "values": ["chaise", "etabli"]}, "position": point, "rot": rot}, ["prefab", "position"])
	add.call("objets.json", "luminaire", {"luminaire": {"t": "enum", "values": ["applique", "neon"]}, "position": point, "rot": rot, "mur": dirs,
		"couleur": {"t": "color"}, "intensite": {"t": "number", "min": 0.1, "max": 8.0}, "portee": {"t": "number", "min": 1.0, "max": 20.0},
		"courant": {"t": "bool"}, "vacille": {"t": "bool"}}, ["luminaire", "position"])
	var surf := {"t": "enum", "values": MapCatalog.materials()}
	return {"items": MapCatalog.items(), "kinds": out, "surfaces": MapCatalog.materials(), "musics": MapCatalog.musics(),
		"room_keys": {"id": {"t": "id"}, "nom": {"t": "text", "max": 64}, "altitude": {"t": "number"}, "zone": {"t": "id"},
			"contour": {"t": "polygon", "min": 3, "max": 64}, "plafond": {"t": "number", "min": 2.0, "max": 20.0},
			"surface_sol": surf, "surface_murs": surf, "surface_plafond": surf},
		"zone_keys": {"id": {"t": "id"}, "nom": {"t": "names", "max": 64}, "sol": surf, "murs": surf, "plafond": surf}}


func test_guard_catalog_v2_adapter() -> void:
	CustomMapGuard.source_override = _v2_source()
	CustomMapGuard.reset_schema()
	# Une carte au format 1 reste valide.
	var r := CustomMapGuard.check_texts(_draft_texts())
	assert_true(r.ok, "DRAFT ARENA avec le catalogue v2 : " + str(r.get("reasons")))
	# Nouveaux éléments du format 2 : préfabriqué, luminaire, textures par pièce, plafond de zone.
	var o = JSON.parse_string(_draft_texts()["objets.json"])
	o.objets.append({"id": "f1", "type": "prefab", "prefab": "chaise", "altitude": 0, "position": [12, 20], "rot": 90})
	o.objets.append({"id": "l9", "type": "luminaire", "luminaire": "neon", "altitude": 0, "position": [12, 22], "couleur": "#ffcc88", "intensite": 2.5, "courant": true})
	var p = JSON.parse_string(_draft_texts()["pieces.json"])
	p.pieces[0]["surface_sol"] = MapCatalog.materials()[0]
	var z = JSON.parse_string(_draft_texts()["zones.json"])
	z.zones[0]["plafond"] = MapCatalog.materials()[0]
	var t := _draft_texts()
	t["objets.json"] = JSON.stringify(o)
	t["pieces.json"] = JSON.stringify(p)
	t["zones.json"] = JSON.stringify(z)
	r = CustomMapGuard.check_texts(t)
	assert_true(r.ok, "éléments du format 2 acceptés : " + str(r.get("reasons")))
	# Et leurs valeurs hors liste refusées.
	var bad := [
		{"id": "f2", "type": "prefab", "prefab": "../../scripts/boot", "altitude": 0, "position": [12, 20]},
		{"id": "f3", "type": "prefab", "prefab": "chaise", "altitude": 0, "position": [12, 20], "rot": 45},
		{"id": "l2", "type": "luminaire", "luminaire": "neon", "altitude": 0, "position": [12, 20], "couleur": "red"},
		{"id": "l3", "type": "luminaire", "luminaire": "neon", "altitude": 0, "position": [12, 20], "intensite": 1e6},
		{"id": "l4", "type": "luminaire", "altitude": 0, "position": [12, 20]},
		{"id": "l5", "type": "luminaire", "luminaire": "neon", "altitude": 0, "position": [12, 20], "script": "x"},
	]
	for b in bad:
		_refused(_with("objets.json", _objets_plus(b)), "format 2 : %s" % str(b))
	p = JSON.parse_string(_draft_texts()["pieces.json"])
	p.pieces[0]["surface_sol"] = "res://evil.tres"
	_refused(_with("pieces.json", p), "texture de pièce inconnue")
	p = JSON.parse_string(_draft_texts()["pieces.json"])
	p.pieces[0]["nom"] = "[img]res://icon.svg[/img]"
	_refused(_with("pieces.json", p), "balise dans un nom de pièce")
	CustomMapGuard.source_override = {}
	CustomMapGuard.reset_schema()


func test_display_names_cleaned() -> void:
	assert_eq(CustomMapGuard.clean_display("[b]Salle[/b]\u202e\n"), "(b)Salle(/b)")
	assert_false(CustomMapGuard.name_ok("<script>"))
	assert_true(CustomMapGuard.name_ok("Salle des machines"))
	assert_true(CustomMapGuard.map_id_ok("draft_arena"))
	for bad in ["../x", "a/b", "c:\\x", "", "A B", "x:y"]:
		assert_false(CustomMapGuard.map_id_ok(bad), "identifiant de carte « %s » refusé" % bad)
	assert_eq(CustomMapGuard.json_depth("{\"a\": \"[[[\", \"b\": [[1]]}"), 3, "crochets dans les chaînes ignorés")


# ------------------------------------------------------------------ cache et archive

func test_cache_by_hash() -> void:
	var pk := CustomMapGuard.package_of(EditorMap.load_dir(DRAFT))
	assert_false(CustomMapGuard.is_cached(pk.sha))
	assert_eq(CustomMapGuard.store(pk.sha, pk.texts), OK)
	assert_true(CustomMapGuard.is_cached(pk.sha), "carte en cache")
	assert_eq(CustomMapGuard.cache_dir(pk.sha), _cache.path_join(pk.sha), "dossier = empreinte")
	var r := CustomMapGuard.load_cached(pk.sha, true)
	assert_true(r.ok, "relue du cache : " + str(r.get("reasons")))
	assert_true(Game.has_map(EditorMapDef.SHARED_PREFIX + pk.sha), "le jeu trouve la carte partagée")
	var def := EditorMapDef.shared(EditorMapDef.SHARED_PREFIX + pk.sha)
	assert_true(def != null and def.is_valid() and def.id == EditorMapDef.SHARED_PREFIX + pk.sha, "carte partagée jouable")
	# Fichier du cache modifié : empreinte fausse, refus.
	var f := FileAccess.open(CustomMapGuard.cache_dir(pk.sha).path_join("objets.json"), FileAccess.WRITE)
	f.store_string("{\"objets\": []}")
	f.close()
	assert_false(CustomMapGuard.load_cached(pk.sha).ok, "cache modifié refusé")
	assert_true(EditorMapDef.shared(EditorMapDef.SHARED_PREFIX + pk.sha) == null, "jamais chargée")
	assert_false(CustomMapGuard.is_cached("../" + pk.sha.substr(3)), "empreinte invalide")
	assert_eq(CustomMapGuard.store("../../evil", pk.texts), ERR_INVALID_PARAMETER, "pas de chemin")
	# Cache borné : les plus anciennes cartes partent, un dossier étranger reste.
	DirAccess.make_dir_recursive_absolute(_cache.path_join("notes"))
	for i in CustomMapGuard.MAX_CACHED + 3:
		var s := CustomMapGuard.sha256_hex(str(i).to_utf8_buffer())
		DirAccess.make_dir_recursive_absolute(_cache.path_join(s))
		var fa := FileAccess.open(_cache.path_join(s).path_join("carte.json"), FileAccess.WRITE)
		fa.store_string("{}")
		fa.close()
	CustomMapGuard.prune_cache()
	var left := DirAccess.get_directories_at(_cache)
	assert_true(left.size() <= CustomMapGuard.MAX_CACHED and "notes" in left, "cache borné (%d dossiers)" % left.size())


func test_zip_import_guarded() -> void:
	var dir := ProjectSettings.globalize_path("res://tests/_out")
	DirAccess.make_dir_recursive_absolute(dir)
	var ok_zip := dir.path_join("guard_ok.zip")
	var m := EditorMap.load_dir(DRAFT)
	assert_eq(m.export_zip(ok_zip), OK)
	var back := EditorMap.import_zip(ok_zip)
	assert_true(back.load_errors.is_empty() and back.same_as(m), "archive saine importée : " + str(back.load_errors))
	# Archive avec un script et une scène en plus : ignorés (jamais extraits).
	var extra_zip := dir.path_join("guard_extra.zip")
	var z := ZIPPacker.new()
	z.open(extra_zip)
	var texts := m.file_texts()
	for f in EditorMap.FILES:
		z.start_file(f)
		z.write_file(String(texts[f]).to_utf8_buffer())
		z.close_file()
	for f in ["evil.gd", "evil.tscn", "icon.png"]:
		z.start_file(f)
		z.write_file("extends Node\nfunc _init(): OS.execute(\"calc\", [])".to_utf8_buffer())
		z.close_file()
	z.close()
	var got := CustomMapGuard.read_zip_texts(extra_zip)
	assert_true(got.reasons.is_empty() and got.texts.size() == 5, "seuls les cinq JSON sont lus")
	# Archive avec un objet interdit : refusée, carte vide et raisons.
	var bad_zip := dir.path_join("guard_bad.zip")
	z = ZIPPacker.new()
	z.open(bad_zip)
	for f in EditorMap.FILES:
		z.start_file(f)
		var s := String(texts[f])
		if f == "objets.json":
			s = JSON.stringify(_objets_plus({"id": "q1", "type": "script", "altitude": 0, "position": [5, 5]}))
		z.write_file(s.to_utf8_buffer())
		z.close_file()
	z.close()
	var refused := EditorMap.import_zip(bad_zip)
	assert_true(not refused.load_errors.is_empty() and refused.pieces.is_empty(), "archive piégée refusée : " + str(refused.load_errors))
	# Pas une archive.
	var junk := dir.path_join("guard_junk.zip")
	var jf := FileAccess.open(junk, FileAccess.WRITE)
	jf.store_string("ceci n'est pas une archive")
	jf.close()
	assert_false(CustomMapGuard.read_zip_texts(junk).reasons.is_empty(), "fausse archive refusée")
	for p in [ok_zip, extra_zip, bad_zip, junk]:
		DirAccess.remove_absolute(p)
