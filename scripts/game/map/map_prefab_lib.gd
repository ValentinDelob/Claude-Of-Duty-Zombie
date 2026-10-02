class_name MapPrefabLib
extends RefCounted
## PREFABS DE LA CARTE (format 10, docs/MAP_OBJECTS.md § 11) : décor propre à
## une carte, rangé DANS son dossier, à côté des cinq JSON :
##   prefabs/<pid>/prefab.json   définition (nom, emprise, collision...)
##   prefabs/<pid>/model.glb     modèle importé (seulement un prefab « modèle »)
## Un objet posé le cite comme un décor du catalogue : {"type": "prefab",
## "prefab": "map:<pid>", "position", "rot"} (même pose, mêmes règles, même
## rotation, même chevauchement que le décor du catalogue).
##
## Deux sortes de prefab :
##   - GROUPE : des décors du catalogue (MapCatalog.PREFABS) assemblés, chacun
##     à sa place et sa rotation (« parties » : [{decor, pos [x, y] (m, autour
##     du centre du prefab, x vers l'est, y vers le sud), rot (degrés)}]) ;
##   - MODÈLE : un fichier .glb importé du disque (« modele » : {echelle,
##     aabb [x0, y0, z0, x1, y1, z1] du modèle brut, sha256}), chargé en jeu par
##     GLTFDocument (pas de pipeline d'import : marche dans le jeu exporté).
## Collision : TOUJOURS des CollisionBox décrites dans prefab.json (« boxes » :
## [{center, size, yaw, barrier}] en coordonnées du prefab, comme
## <modèle>.collision.json), jamais une collision tirée du modèle.
##
## Dans les textes d'une carte (EditorMap.file_texts, paquet réseau, cache,
## archive), un prefab est une entrée de plus : « prefabs/<pid>/prefab.json »
## (texte JSON) et « prefabs/<pid>/model.glb » (octets du modèle en base64 ; sur
## le disque et dans une archive : le fichier binaire).
##
## Sûreté (cartes reçues d'autres joueurs, CustomMapGuard) : définition
## vérifiée clé par clé (check_def), modèle vérifié AVANT tout décodage par le
## moteur (check_glb : en-tête GLB, morceaux, JSON, aucune adresse externe
## « uri », extensions admises, images PNG / JPEG de 4096 px au plus,
## triangles, tailles) ; limites de nombre et de taille ci-dessous.

const DIR := "prefabs"
const DEF_FILE := "prefab.json"
const MODEL_FILE := "model.glb"
## Préfixe d'un prefab de la carte dans la clé « prefab » d'un objet posé.
const REF := "map:"
const FORMAT := 1
const MAX_PREFABS := 32
const MAX_MODELS := 8
const MAX_MODEL_BYTES := 8 * 1024 * 1024
const MAX_MODELS_BYTES := 24 * 1024 * 1024
const MAX_DEF_BYTES := 64 * 1024
const MAX_PID := 32
const MAX_PARTS := 48
const MAX_BOXES := 32
const MAX_TRIANGLES := 150000
const MAX_VERTICES := 600000
const MAX_IMAGE_SIDE := 4096
## Emprise (cases de 0,5 m) et dimensions (m) bornées.
const MAX_FP := 40
const MAX_SIZE := 30.0
const SCALE := [0.01, 100.0]
const BLOCKS := ["solide", "barriere", "non"]
## Extensions glTF obligatoires admises (lues par le moteur, sans code).
const ALLOWED_EXT := ["KHR_materials_emissive_strength", "KHR_texture_transform", "KHR_mesh_quantization", "KHR_materials_unlit"]
const IMAGE_TYPES := ["image/png", "image/jpeg"]
const DEFAULT_COLOR := "#9a8f80"
## Longueur maximale du base64 d'un modèle (MAX_MODEL_BYTES octets).
const MAX_MODEL_B64 := 11184812


# ------------------------------------------------------------------ noms et clés

## Identifiant de prefab (nom de son dossier) : 1 à 32 caractères parmi a-z,
## 0-9 et _ (jamais de chemin).
static func pid_ok(s: Variant) -> bool:
	return s is String and String(s).length() <= MAX_PID and EditorMap.valid_id(s)


static func ref(pid: String) -> String:
	return REF + pid


## Identifiant de prefab d'une clé « prefab » d'objet (« map:<pid> ») ; "" sinon.
static func pid_of(prefab: Variant) -> String:
	if prefab is String and String(prefab).begins_with(REF):
		var pid := String(prefab).substr(REF.length())
		return pid if pid_ok(pid) else ""
	return ""


static func is_ref(prefab: Variant) -> bool:
	return pid_of(prefab) != ""


static func def_key(pid: String) -> String:
	return "%s/%s/%s" % [DIR, pid, DEF_FILE]


static func model_key(pid: String) -> String:
	return "%s/%s/%s" % [DIR, pid, MODEL_FILE]


## Clé de texte d'une carte -> [pid, fichier] si c'est une entrée de prefab
## admise (prefabs/<pid>/prefab.json ou model.glb), [] sinon.
static func parse_key(k: Variant) -> Array:
	if not k is String:
		return []
	var parts := String(k).split("/")
	if parts.size() != 3 or parts[0] != DIR or not pid_ok(parts[1]) or not parts[2] in [DEF_FILE, MODEL_FILE]:
		return []
	return [parts[1], parts[2]]


## Nouvel identifiant libre tiré d'un nom (EditorMap.slug, 24 caractères).
static func new_pid(name: String, used: Dictionary) -> String:
	var base := EditorMap.slug(name).left(24).trim_suffix("_")
	if base == "" or base == "carte":
		base = "prefab"
	var pid := base
	var n := 2
	while used.has(pid):
		pid = "%s_%d" % [base, n]
		n += 1
	return pid


# ------------------------------------------------------------------ définition

static func _num(v: Variant, lo: float, hi: float) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func _vec(v: Variant, n: int, lo: float, hi: float) -> bool:
	if not (v is Array and v.size() == n):
		return false
	for x in v:
		if not _num(x, lo, hi):
			return false
	return true


static func _bad(fr: String, en: String) -> Array:
	return [fr, en]


## Contrôle d'une définition (prefab.json lu) ; [fr, en] si elle est refusée,
## [] sinon. Liste blanche des clés et des valeurs ; une seule des deux sortes
## (« parties » ou « modele »).
static func check_def(d: Variant) -> Array:
	if not d is Dictionary:
		return _bad("prefab.json : objet JSON attendu", "prefab.json: JSON object expected")
	var allowed := ["format", "nom", "fp", "h", "bloque", "surface", "couleur", "boxes", "parties", "modele"]
	for k in d:
		if not (k is String and k in allowed):
			return _bad("prefab.json : clé inconnue « %s »" % CustomMapGuard.clean_display(str(k), 24), "prefab.json: unknown key \"%s\"" % CustomMapGuard.clean_display(str(k), 24))
	if d.has("format") and not (_num(d.format, 1, FORMAT) and float(d.format) == floorf(float(d.format))):
		return _bad("prefab.json : format inconnu", "prefab.json: unknown format")
	var nom: Variant = d.get("nom")
	if not (nom is Dictionary and nom.size() >= 1 and nom.size() <= 2):
		return _bad("prefab.json : nom {fr, en} attendu", "prefab.json: name {fr, en} expected")
	for k in nom:
		if not (k in ["fr", "en"] and nom[k] is String and String(nom[k]).strip_edges() != "" and CustomMapGuard.name_ok(nom[k])):
			return _bad("prefab.json : nom refusé", "prefab.json: name refused")
	if not (d.get("fp") is Array and d.fp.size() == 2 and _num(d.fp[0], 1, MAX_FP) and _num(d.fp[1], 1, MAX_FP)
			and float(d.fp[0]) == floorf(float(d.fp[0])) and float(d.fp[1]) == floorf(float(d.fp[1]))):
		return _bad("prefab.json : emprise « fp » [1 à %d, 1 à %d] attendue" % [MAX_FP, MAX_FP], "prefab.json: footprint \"fp\" [1 to %d, 1 to %d] expected" % [MAX_FP, MAX_FP])
	if not _num(d.get("h"), 0.01, MAX_SIZE):
		return _bad("prefab.json : hauteur « h » hors limites", "prefab.json: height \"h\" out of range")
	if not (d.get("bloque") is String and d.bloque in BLOCKS):
		return _bad("prefab.json : « bloque » : solide, barriere ou non", "prefab.json: \"bloque\": solide, barriere or non")
	if d.has("surface") and not (d.surface is String and WorldLook.SURFACES.has(d.surface)):
		return _bad("prefab.json : surface inconnue", "prefab.json: unknown surface")
	if d.has("couleur"):
		var c: Variant = d.couleur
		if not (c is String and c.length() == 7 and c.begins_with("#") and c.substr(1).is_valid_hex_number()):
			return _bad("prefab.json : couleur #rrggbb attendue", "prefab.json: #rrggbb colour expected")
	var boxes: Variant = d.get("boxes", [])
	if not (boxes is Array and boxes.size() <= MAX_BOXES):
		return _bad("prefab.json : « boxes » : %d pavés au plus" % MAX_BOXES, "prefab.json: \"boxes\": %d boxes at most" % MAX_BOXES)
	for b in boxes:
		if not (b is Dictionary and b.has("center") and b.has("size")):
			return _bad("prefab.json : pavé de collision {center, size} attendu", "prefab.json: collision box {center, size} expected")
		for k in b:
			if not k in ["center", "size", "yaw", "barrier"]:
				return _bad("prefab.json : clé de pavé inconnue", "prefab.json: unknown box key")
		if not (_vec(b.center, 3, -MAX_SIZE, MAX_SIZE) and _vec(b.size, 3, 0.01, MAX_SIZE)):
			return _bad("prefab.json : pavé de collision hors limites", "prefab.json: collision box out of range")
		if b.has("yaw") and not _num(b.yaw, -TAU, TAU):
			return _bad("prefab.json : lacet de pavé hors limites", "prefab.json: box yaw out of range")
		if b.has("barrier") and not b.barrier is bool:
			return _bad("prefab.json : « barrier » vrai / faux attendu", "prefab.json: \"barrier\" true / false expected")
	var has_parts: bool = d.has("parties")
	var has_model: bool = d.has("modele")
	if has_parts == has_model:
		return _bad("prefab.json : « parties » ou « modele » (l'un des deux) attendu", "prefab.json: \"parties\" or \"modele\" (one of them) expected")
	if has_parts:
		var parts: Variant = d.parties
		if not (parts is Array and parts.size() >= 1 and parts.size() <= MAX_PARTS):
			return _bad("prefab.json : 1 à %d parties attendues" % MAX_PARTS, "prefab.json: 1 to %d parts expected" % MAX_PARTS)
		for p in parts:
			if not (p is Dictionary and p.get("decor") is String and MapCatalog.PREFABS.has(p.decor)):
				return _bad("prefab.json : partie : décor du catalogue attendu", "prefab.json: part: catalogue prop expected")
			for k in p:
				if not k in ["decor", "pos", "rot"]:
					return _bad("prefab.json : clé de partie inconnue", "prefab.json: unknown part key")
			if not _vec(p.get("pos"), 2, -MAX_SIZE, MAX_SIZE):
				return _bad("prefab.json : position de partie hors limites", "prefab.json: part position out of range")
			if p.has("rot") and not (_num(p.rot, 0, 359) and float(p.rot) == floorf(float(p.rot))):
				return _bad("prefab.json : rotation de partie (0 à 359)", "prefab.json: part rotation (0 to 359)")
	else:
		var md: Variant = d.modele
		if not md is Dictionary:
			return _bad("prefab.json : « modele » {echelle, aabb, sha256} attendu", "prefab.json: \"modele\" {echelle, aabb, sha256} expected")
		for k in md:
			if not k in ["echelle", "aabb", "sha256"]:
				return _bad("prefab.json : clé de modèle inconnue", "prefab.json: unknown model key")
		if not _num(md.get("echelle"), SCALE[0], SCALE[1]):
			return _bad("prefab.json : échelle hors limites (%s à %s)" % [str(SCALE[0]), str(SCALE[1])], "prefab.json: scale out of range (%s to %s)" % [str(SCALE[0]), str(SCALE[1])])
		if not _vec(md.get("aabb"), 6, -10000.0, 10000.0):
			return _bad("prefab.json : boîte englobante « aabb » attendue", "prefab.json: bounding box \"aabb\" expected")
		if not (md.get("sha256") is String and CustomMapGuard.sha_ok(md.sha256)):
			return _bad("prefab.json : empreinte « sha256 » attendue", "prefab.json: \"sha256\" fingerprint expected")
	return []


## Définition nettoyée (nombres arrondis, valeurs par défaut retirées) ; {} si
## elle est refusée (check_def).
static func sanitize(d: Variant) -> Dictionary:
	if not check_def(d).is_empty():
		return {}
	var out: Dictionary = (d as Dictionary).duplicate(true)
	out["format"] = FORMAT
	out["fp"] = [int(out.fp[0]), int(out.fp[1])]
	out["h"] = snappedf(float(out.h), 0.01)
	var boxes := []
	for b in out.get("boxes", []):
		var nb := {"center": (b.center as Array).map(func(x): return snappedf(float(x), 0.001)),
			"size": (b.size as Array).map(func(x): return snappedf(float(x), 0.001))}
		if b.has("yaw") and absf(float(b.yaw)) > 0.0001:
			nb["yaw"] = snappedf(float(b.yaw), 0.0001)
		if bool(b.get("barrier", false)):
			nb["barrier"] = true
		boxes.append(nb)
	out["boxes"] = boxes
	if out.has("parties"):
		var parts := []
		for p in out.parties:
			var np := {"decor": String(p.decor), "pos": [snappedf(float(p.pos[0]), 0.01), snappedf(float(p.pos[1]), 0.01)]}
			if int(p.get("rot", 0)) != 0:
				np["rot"] = int(p.rot)
			parts.append(np)
		out["parties"] = parts
	return out


## Texte de prefab.json (JSON lisible, une ligne par pavé / partie ; nombres
## entiers sans décimale, comme les fichiers de la carte).
static func def_text(d: Dictionary) -> String:
	return EditorMap.dump(EditorMap._ints(d))


## Nom affiché.
static func name_of(d: Dictionary) -> String:
	var n: Dictionary = d.get("nom", {})
	return Lang.t(String(n.get("fr", n.get("en", "?"))), String(n.get("en", n.get("fr", "?"))))


static func is_model(d: Dictionary) -> bool:
	return d.has("modele")


static func color_of(d: Dictionary) -> Color:
	var c := String(d.get("couleur", DEFAULT_COLOR))
	return Color.html(c) if Color.html_is_valid(c) else Color.html(DEFAULT_COLOR)


# ------------------------------------------------------------------ prefab GROUPE (depuis le décor posé)

## Pavés de collision d'un décor du catalogue (coordonnées de l'objet) : ses
## « boxes », sinon celles de son modèle (<modèle>.collision.json), sinon un
## pavé de son emprise et de sa hauteur.
static func catalog_boxes(id: String) -> Array:
	var d: Dictionary = MapCatalog.PREFABS.get(id, {})
	if d.is_empty():
		return []
	if d.has("boxes"):
		return d.boxes
	if d.has("model"):
		var path := "res://assets/models/kino/%s.collision.json" % String(d.model)
		if FileAccess.file_exists(path):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if j is Dictionary and j.get("boxes") is Array and not (j.boxes as Array).is_empty():
				var s := float(d.get("scale", 1.0))
				var out := []
				for b in j.boxes:
					out.append({"center": (b.center as Array).map(func(x): return float(x) * s), "size": (b.size as Array).map(func(x): return float(x) * s),
						"yaw": float(b.get("yaw", 0.0)), "barrier": bool(b.get("barrier", false))})
				return out
	var fp: Array = d.fp
	var h := float(d.h)
	return [{"center": [0.0, h * 0.5, 0.0], "size": [float(fp[0]) * 0.5, h, float(fp[1]) * 0.5]}]


## Décor du catalogue qui peut entrer dans un prefab groupe : un « prefab » du
## catalogue (pas un prefab de la carte, pas un luminaire).
static func groupable(o: Dictionary) -> bool:
	return String(o.get("type", "")) == "prefab" and MapCatalog.PREFABS.has(String(o.get("prefab", "")))


## Prefab groupe tiré d'objets posés (décor du catalogue) : parties autour du
## centre de leur emprise commune, emprise, hauteur, collision (les pavés de
## chaque partie qui bloque, à sa place), surface, couleur. {def, center} ou
## {error: [fr, en]}.
static func from_objects(name_fr: String, name_en: String, objs: Array) -> Dictionary:
	var parts := objs.filter(func(o): return groupable(o))
	if parts.is_empty():
		return {"error": ["aucun décor du catalogue dans la sélection", "no catalogue prop in the selection"]}
	if parts.size() > MAX_PARTS:
		return {"error": ["trop de décors (%d, au plus %d)" % [parts.size(), MAX_PARTS], "too many props (%d, at most %d)" % [parts.size(), MAX_PARTS]]}
	var bb := Rect2()
	var first := true
	for o in parts:
		var r := MapGeom.bbox(MapRaster.floor_poly(o))
		bb = r if first else bb.merge(r)
		first = false
	var c := MapGeom.round_cm(bb.get_center())
	var h := 0.0
	var block := "non"
	var surface := ""
	var col := Color(0, 0, 0)
	var out_parts := []
	var boxes := []
	for o in parts:
		var id := String(o.prefab)
		var d: Dictionary = MapCatalog.PREFABS[id]
		var pos := MapGeom.v2(o.position) - c
		var rot := posmod(int(o.get("rot", 0)), 360)
		var p := {"decor": id, "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]}
		if rot != 0:
			p["rot"] = rot
		out_parts.append(p)
		h = maxf(h, float(d.h))
		col += Color(d.color)
		var b := String(d.bloque)
		if b == "solide" or (b == "barriere" and block == "non"):
			block = b
		if b == "non":
			continue
		if surface == "":
			surface = String(d.get("surface", "concrete"))
		var yaw := -deg_to_rad(float(rot))
		var basis := Basis(Vector3.UP, yaw)
		for bx in catalog_boxes(id):
			var bc: Array = bx.center
			var wc := basis * Vector3(float(bc[0]), float(bc[1]), float(bc[2])) + Vector3(pos.x, 0.0, pos.y)
			var nb := {"center": [wc.x, wc.y, wc.z], "size": bx.size, "yaw": wrapf(yaw + float(bx.get("yaw", 0.0)), -PI, PI)}
			if b == "barriere" or bool(bx.get("barrier", false)):
				nb["barrier"] = true
			boxes.append(nb)
	if boxes.size() > MAX_BOXES:
		return {"error": ["trop de pavés de collision (%d, au plus %d)" % [boxes.size(), MAX_BOXES], "too many collision boxes (%d, at most %d)" % [boxes.size(), MAX_BOXES]]}
	col /= float(parts.size())
	var fp := [clampi(ceili(bb.size.x / MapGeom.CELL - 0.01), 1, MAX_FP), clampi(ceili(bb.size.y / MapGeom.CELL - 0.01), 1, MAX_FP)]
	var d := {"format": FORMAT, "nom": {"fr": name_fr, "en": name_en}, "fp": fp, "h": maxf(h, 0.1), "bloque": block,
		"surface": surface if surface != "" else "concrete", "couleur": "#" + col.to_html(false), "boxes": boxes, "parties": out_parts}
	var s := sanitize(d)
	if s.is_empty():
		return {"error": check_def(d)}
	return {"def": s, "center": c}


# ------------------------------------------------------------------ prefab MODÈLE (importé)

## Prefab modèle tiré des octets d'un .glb déjà contrôlé (check_glb) : boîte
## englobante lue dans la scène, empreinte, emprise, collision (un pavé de la
## boîte englobante). {def} ou {error: [fr, en]}.
static func from_model(name_fr: String, name_en: String, glb: PackedByteArray, scale := 1.0, block := "solide") -> Dictionary:
	var bad := check_glb(glb)
	if not bad.is_empty():
		return {"error": bad}
	var scene := instantiate(glb)
	if scene == null:
		return {"error": ["modèle illisible", "unreadable model"]}
	var bb := scene_aabb(scene)
	scene.free()
	if bb.size.length() < 0.001:
		return {"error": ["modèle vide (aucun maillage)", "empty model (no mesh)"]}
	var d := {"format": FORMAT, "nom": {"fr": name_fr, "en": name_en}, "bloque": block, "surface": "concrete", "couleur": DEFAULT_COLOR,
		"modele": {"echelle": clampf(scale, SCALE[0], SCALE[1]), "aabb": [bb.position.x, bb.position.y, bb.position.z, bb.end.x, bb.end.y, bb.end.z].map(func(x): return snappedf(x, 0.0001)),
			"sha256": CustomMapGuard.sha256_hex(glb)}}
	refit(d)
	var s := sanitize(d)
	if s.is_empty():
		return {"error": check_def(d)}
	return {"def": s}


## Boîte englobante du modèle brut (aabb), mise à l'échelle.
static func model_box(d: Dictionary) -> AABB:
	var a: Array = d.modele.aabb
	var s := float(d.modele.echelle)
	var p := Vector3(float(a[0]), float(a[1]), float(a[2])) * s
	return AABB(p, (Vector3(float(a[3]), float(a[4]), float(a[5])) * s - p).abs())


## Décalage du modèle sous l'origine du prefab : centré en x et z, posé au
## sol (bas de sa boîte englobante à y = 0).
static func model_offset(d: Dictionary) -> Vector3:
	var b := model_box(d)
	var c := b.get_center()
	return Vector3(-c.x, -b.position.y, -c.z)


## Emprise, hauteur et collision d'un prefab modèle recalculées (échelle ou
## collision changée) : un pavé de sa boîte englobante (aucun : « non »).
static func refit(d: Dictionary) -> void:
	var b := model_box(d)
	var sz := b.size.clamp(Vector3.ONE * 0.01, Vector3.ONE * MAX_SIZE)
	d["fp"] = [clampi(ceili(sz.x / MapGeom.CELL - 0.01), 1, MAX_FP), clampi(ceili(sz.z / MapGeom.CELL - 0.01), 1, MAX_FP)]
	d["h"] = snappedf(clampf(sz.y, 0.01, MAX_SIZE), 0.01)
	var block := String(d.get("bloque", "solide"))
	if block == "non":
		d["boxes"] = []
	else:
		var box := {"center": [0.0, snappedf(sz.y * 0.5, 0.001), 0.0], "size": [snappedf(sz.x, 0.001), snappedf(sz.y, 0.001), snappedf(sz.z, 0.001)]}
		if block == "barriere":
			box["barrier"] = true
		d["boxes"] = [box]


## Boîte englobante des maillages d'une scène (hors de l'arbre), dans le
## repère de sa racine.
static func scene_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var a := xf * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


# ------------------------------------------------------------------ modèle : contrôle et chargement

## Contrôle d'un .glb (octets) AVANT de le donner au moteur ; [fr, en] si
## refusé, [] sinon. Rien n'est décodé ici que l'en-tête, le JSON et
## l'en-tête des images.
static func check_glb(b: PackedByteArray) -> Array:
	var n := b.size()
	if n > MAX_MODEL_BYTES:
		@warning_ignore("integer_division")
		return _bad("modèle trop gros (%d Ko, %d Mo au plus)" % [n / 1024, MAX_MODEL_BYTES / 1048576], "model too big (%d KB, %d MB at most)" % [n / 1024, MAX_MODEL_BYTES / 1048576])
	if n < 28 or b.decode_u32(0) != 0x46546C67 or b.decode_u32(4) != 2 or b.decode_u32(8) != n:
		return _bad("modèle refusé : pas un fichier .glb (glTF 2 binaire)", "model refused: not a .glb file (binary glTF 2)")
	var jlen := b.decode_u32(12)
	if b.decode_u32(16) != 0x4E4F534A or jlen < 2 or jlen > mini(n - 20, 4 * 1024 * 1024):
		return _bad("modèle refusé : morceau JSON invalide", "model refused: invalid JSON chunk")
	var bin_at := 20 + jlen
	var bin_len := 0
	if bin_at < n:
		if bin_at + 8 > n or b.decode_u32(bin_at + 4) != 0x004E4942:
			return _bad("modèle refusé : morceau inattendu", "model refused: unexpected chunk")
		bin_len = b.decode_u32(bin_at)
		if bin_at + 8 + bin_len != n:
			return _bad("modèle refusé : taille des morceaux incorrecte", "model refused: wrong chunk sizes")
	var txt: Variant = CustomMapGuard.decode_utf8(b.slice(20, 20 + jlen).duplicate())
	if txt == null:
		# Remplissage d'espaces à la fin du JSON : permis.
		txt = CustomMapGuard.decode_utf8(_rstrip_zero(b.slice(20, 20 + jlen)))
	if txt == null:
		return _bad("modèle refusé : JSON invalide (UTF-8)", "model refused: invalid JSON (UTF-8)")
	var depth := CustomMapGuard.json_depth(txt)
	if depth < 0 or depth > 24:
		return _bad("modèle refusé : JSON trop imbriqué", "model refused: JSON nested too deep")
	var j: Variant = CustomMapGuard.parse_json(txt)
	if not j is Dictionary:
		return _bad("modèle refusé : JSON illisible", "model refused: unreadable JSON")
	return check_gltf_json(j, b, bin_at + 8, bin_len)


static func _rstrip_zero(b: PackedByteArray) -> PackedByteArray:
	var n := b.size()
	while n > 0 and (b[n - 1] == 0 or b[n - 1] == 0x20):
		n -= 1
	return b.slice(0, n)


## Une clé « uri » quelque part (adresse externe, fichier à côté, data:) ?
static func _has_uri(v: Variant, depth := 0) -> bool:
	if depth > 30:
		return true
	if v is Dictionary:
		for k in v:
			if String(k) == "uri" or _has_uri(v[k], depth + 1):
				return true
	elif v is Array:
		for x in v:
			if _has_uri(x, depth + 1):
				return true
	return false


static func _list(j: Dictionary, key: String) -> Array:
	var v: Variant = j.get(key, [])
	return v if v is Array else []


## Contrôle du JSON d'un glTF (morceau JSON d'un .glb ; `bin` : octets du
## fichier, morceau BIN à `bin_at`, `bin_len` octets).
static func check_gltf_json(j: Dictionary, bin: PackedByteArray, bin_at: int, bin_len: int) -> Array:
	var asset: Variant = j.get("asset")
	if not (asset is Dictionary and String(asset.get("version", "")) == "2.0"):
		return _bad("modèle refusé : glTF 2.0 attendu", "model refused: glTF 2.0 expected")
	if _has_uri(j):
		return _bad("modèle refusé : adresse externe (« uri ») interdite, tout doit être dans le .glb", "model refused: external address (\"uri\") not allowed, everything must be inside the .glb")
	for k in ["extensionsRequired", "extensionsUsed"]:
		if j.has(k) and not j[k] is Array:
			return _bad("modèle refusé : extensions illisibles", "model refused: unreadable extensions")
	for e in _list(j, "extensionsRequired"):
		if not (e is String and e in ALLOWED_EXT):
			return _bad("modèle refusé : extension non admise « %s »" % CustomMapGuard.clean_display(str(e), 40), "model refused: extension not allowed \"%s\"" % CustomMapGuard.clean_display(str(e), 40))
	var limits := {"nodes": 4096, "meshes": 1024, "accessors": 16384, "bufferViews": 16384, "materials": 256, "images": 32, "textures": 64,
		"buffers": 1, "samplers": 64, "skins": 64, "animations": 64, "scenes": 8}
	for k in limits:
		if j.has(k) and not j[k] is Array:
			return _bad("modèle refusé : « %s » illisible" % k, "model refused: unreadable \"%s\"" % k)
		if _list(j, k).size() > int(limits[k]):
			return _bad("modèle refusé : trop de %s (%d au plus)" % [k, limits[k]], "model refused: too many %s (%d at most)" % [k, limits[k]])
	for buf in _list(j, "buffers"):
		if not (buf is Dictionary and _num(buf.get("byteLength"), 0, bin_len)):
			return _bad("modèle refusé : tampon invalide", "model refused: invalid buffer")
	var views := _list(j, "bufferViews")
	for v in views:
		if not (v is Dictionary and _num(v.get("buffer", 0), 0, 0) and _num(v.get("byteLength"), 0, bin_len) and _num(v.get("byteOffset", 0), 0, bin_len)
				and float(v.get("byteOffset", 0)) + float(v.byteLength) <= bin_len):
			return _bad("modèle refusé : vue de tampon hors du fichier", "model refused: buffer view outside the file")
	var accessors := _list(j, "accessors")
	for a in accessors:
		if not (a is Dictionary and _num(a.get("count"), 0, MAX_VERTICES * 3)):
			return _bad("modèle refusé : accesseur invalide", "model refused: invalid accessor")
	# Images : dans le fichier (vue de tampon), PNG ou JPEG, côtés bornés.
	for im in _list(j, "images"):
		if not (im is Dictionary and im.get("mimeType") is String and im.mimeType in IMAGE_TYPES and _num(im.get("bufferView"), 0, views.size() - 1)):
			return _bad("modèle refusé : image PNG ou JPEG intégrée attendue", "model refused: embedded PNG or JPEG image expected")
		var v: Dictionary = views[int(im.bufferView)]
		var off := bin_at + int(v.get("byteOffset", 0))
		var dims := image_size(bin.slice(off, off + mini(int(v.byteLength), 1 << 20)))
		if dims.x <= 0 or dims.y <= 0:
			return _bad("modèle refusé : image illisible", "model refused: unreadable image")
		if dims.x > MAX_IMAGE_SIDE or dims.y > MAX_IMAGE_SIDE:
			return _bad("modèle refusé : image trop grande (%d × %d, %d px au plus)" % [dims.x, dims.y, MAX_IMAGE_SIDE], "model refused: image too large (%d × %d, %d px at most)" % [dims.x, dims.y, MAX_IMAGE_SIDE])
	# Triangles : chaque maillage autant de fois que des nœuds le citent.
	var meshes := _list(j, "meshes")
	var uses := {}
	for nd in _list(j, "nodes"):
		if nd is Dictionary and nd.has("mesh"):
			if not _num(nd.mesh, 0, meshes.size() - 1):
				return _bad("modèle refusé : nœud invalide", "model refused: invalid node")
			uses[int(nd.mesh)] = int(uses.get(int(nd.mesh), 0)) + 1
	var tris := 0
	var verts := 0
	for i in meshes.size():
		var m: Variant = meshes[i]
		if not (m is Dictionary and m.get("primitives") is Array):
			return _bad("modèle refusé : maillage invalide", "model refused: invalid mesh")
		var mt := 0
		for p in m.primitives:
			if not (p is Dictionary and p.get("attributes") is Dictionary and _num(p.attributes.get("POSITION"), 0, accessors.size() - 1)):
				return _bad("modèle refusé : primitive sans positions", "model refused: primitive without positions")
			var pc := int(accessors[int(p.attributes.POSITION)].count)
			verts += pc
			var cnt := pc
			if p.has("indices"):
				if not _num(p.indices, 0, accessors.size() - 1):
					return _bad("modèle refusé : indices invalides", "model refused: invalid indices")
				cnt = int(accessors[int(p.indices)].count)
			var mode := int(p.get("mode", 4)) if (p.get("mode", 4) is float or p.get("mode", 4) is int) else 4
			@warning_ignore("integer_division")
			mt += cnt / 3 if mode == 4 else (maxi(0, cnt - 2) if mode in [5, 6] else 0)
		tris += mt * maxi(1, int(uses.get(i, 0)))
		if tris > MAX_TRIANGLES or verts > MAX_VERTICES:
			return _bad("modèle refusé : trop de triangles (au plus %d)" % MAX_TRIANGLES, "model refused: too many triangles (at most %d)" % MAX_TRIANGLES)
	if meshes.is_empty():
		return _bad("modèle refusé : aucun maillage", "model refused: no mesh")
	return []


## Côtés d'une image PNG ou JPEG lus dans son en-tête (Vector2i.ZERO si illisible).
static func image_size(b: PackedByteArray) -> Vector2i:
	if b.size() >= 24 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		return Vector2i(_be32(b, 16), _be32(b, 20))
	if b.size() >= 4 and b[0] == 0xFF and b[1] == 0xD8:
		var i := 2
		while i + 9 < b.size():
			if b[i] != 0xFF:
				return Vector2i.ZERO
			var mk := b[i + 1]
			if mk == 0xD8 or mk == 0x01 or (mk >= 0xD0 and mk <= 0xD7):
				i += 2
				continue
			var ln := (b[i + 2] << 8) | b[i + 3]
			if mk >= 0xC0 and mk <= 0xCF and not mk in [0xC4, 0xC8, 0xCC]:
				return Vector2i((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6])
			if ln < 2:
				return Vector2i.ZERO
			i += 2 + ln
	return Vector2i.ZERO


static func _be32(b: PackedByteArray, i: int) -> int:
	return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]


## Scène d'un .glb contrôlé (GLTFDocument : aucune ressource du projet, aucun
## script), sans ce qui n'est pas du décor (collisions, lumières, caméras,
## sons, animations) ; null si illisible (journalisé).
static func instantiate(glb: PackedByteArray) -> Node3D:
	if not check_glb(glb).is_empty():
		push_warning("[MapPrefabLib] modèle refusé : " + str(check_glb(glb)[0]))
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(glb, "", st) != OK:
		push_warning("[MapPrefabLib] modèle illisible (GLTFDocument)")
		return null
	var scene := doc.generate_scene(st)
	if not scene is Node3D:
		if scene != null:
			scene.free()
		push_warning("[MapPrefabLib] modèle sans scène 3D")
		return null
	for n in scene.find_children("*", "", true, false):
		if not is_instance_valid(n):
			continue
		if n is CollisionObject3D or n is CollisionShape3D or n is Light3D or n is Camera3D or n is AudioStreamPlayer3D or n is AnimationMixer:
			n.get_parent().remove_child(n)
			n.free()
	return scene


## .glb (octets) tiré d'un fichier .glb ou .gltf du disque, pour l'IMPORT :
## un .gltf est accepté seulement avec ses données intégrées (adresses
## « data: »), puis réécrit en .glb par GLTFDocument. {glb} ou {error: [fr, en]}.
static func read_import(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not ext in ["glb", "gltf"]:
		return {"error": ["fichier refusé : .glb ou .gltf seulement", "file refused: .glb or .gltf only"]}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"error": ["fichier illisible : %s" % path.get_file(), "unreadable file: %s" % path.get_file()]}
	var n := fa.get_length()
	if n > MAX_MODEL_BYTES:
		fa.close()
		@warning_ignore("integer_division")
		return {"error": ["fichier trop gros (%d Ko, %d Mo au plus)" % [n / 1024, MAX_MODEL_BYTES / 1048576], "file too big (%d KB, %d MB at most)" % [n / 1024, MAX_MODEL_BYTES / 1048576]]}
	var b := fa.get_buffer(n)
	fa.close()
	if ext == "glb":
		var bad := check_glb(b)
		return {"error": bad} if not bad.is_empty() else {"glb": b}
	var txt: Variant = CustomMapGuard.decode_utf8(b)
	var j: Variant = CustomMapGuard.parse_json(txt) if txt != null and CustomMapGuard.json_depth(txt) in range(0, 25) else null
	if not j is Dictionary:
		return {"error": ["fichier .gltf illisible", "unreadable .gltf file"]}
	if _external_uri(j):
		return {"error": ["fichier .gltf refusé : ses données doivent être intégrées (pas de fichier .bin ou d'image à côté) ; exportez plutôt un .glb",
			"file .gltf refused: its data must be embedded (no .bin or image file next to it); export a .glb instead"]}
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(b, "", st) != OK:
		return {"error": ["fichier .gltf illisible", "unreadable .gltf file"]}
	var scene := doc.generate_scene(st)
	if scene == null:
		return {"error": ["fichier .gltf sans scène", ".gltf file without a scene"]}
	var out := to_glb(scene)
	scene.free()
	if out.is_empty():
		return {"error": ["conversion en .glb impossible", "could not convert to .glb"]}
	var bad2 := check_glb(out)
	return {"error": bad2} if not bad2.is_empty() else {"glb": out}


## Une adresse « uri » qui n'est pas des données intégrées (« data: ») ?
static func _external_uri(v: Variant, depth := 0) -> bool:
	if depth > 30:
		return true
	if v is Dictionary:
		for k in v:
			if String(k) == "uri" and not (v[k] is String and String(v[k]).begins_with("data:")):
				return true
			if _external_uri(v[k], depth + 1):
				return true
	elif v is Array:
		for x in v:
			if _external_uri(x, depth + 1):
				return true
	return false


## Scène -> octets .glb (GLTFDocument) ; vide en cas d'échec.
static func to_glb(scene: Node) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_scene(scene, st) != OK:
		return PackedByteArray()
	return doc.generate_buffer(st)


# ------------------------------------------------------------------ dossier

## Entrées de prefab d'un dossier de carte (prefabs/<pid>/...), tailles
## vérifiées AVANT lecture : {texts: {clé: texte (prefab.json) ou base64
## (model.glb)}, reasons}. Seuls ces deux fichiers sont lus ; les dossiers au
## nom non admis sont ignorés.
static func read_dir(dir: String) -> Dictionary:
	var texts := {}
	var reasons := []
	var root := dir.path_join(DIR)
	if not DirAccess.dir_exists_absolute(root):
		return {"texts": texts, "reasons": reasons}
	var pids := Array(DirAccess.get_directories_at(root)).filter(func(p): return pid_ok(p))
	pids.sort()
	if pids.size() > MAX_PREFABS:
		reasons.append(["trop de prefabs (%d, au plus %d)" % [pids.size(), MAX_PREFABS], "too many prefabs (%d, at most %d)" % [pids.size(), MAX_PREFABS]])
		pids = pids.slice(0, MAX_PREFABS)
	var total := 0
	for pid in pids:
		var dp := root.path_join(pid).path_join(DEF_FILE)
		if not FileAccess.file_exists(dp):
			continue
		var t: Variant = EditorMap.read_text(dp, MAX_DEF_BYTES)
		if t == null:
			reasons.append(["prefab %s : prefab.json trop gros ou illisible" % pid, "prefab %s: prefab.json too big or unreadable" % pid])
			continue
		texts[def_key(pid)] = t
		var mp := root.path_join(pid).path_join(MODEL_FILE)
		if FileAccess.file_exists(mp):
			var fa := FileAccess.open(mp, FileAccess.READ)
			if fa == null:
				continue
			var n := fa.get_length()
			total += n
			if n > MAX_MODEL_BYTES or total > MAX_MODELS_BYTES:
				fa.close()
				reasons.append(["prefab %s : modèle trop gros" % pid, "prefab %s: model too big" % pid])
				continue
			texts[model_key(pid)] = Marshalls.raw_to_base64(fa.get_buffer(n))
			fa.close()
	return {"texts": texts, "reasons": reasons}


## Écrit les entrées de prefab (`texts` : clé -> texte ou base64) dans le
## dossier de la carte et retire les dossiers de prefab qui n'y sont plus
## (seulement des dossiers au nom admis, et seulement leurs deux fichiers). Un
## modèle déjà là, identique (même SHA-256), n'est pas réécrit.
static func write_dir(dir: String, texts: Dictionary) -> Error:
	var root := dir.path_join(DIR)
	var keep := {}
	for k in texts:
		var pk := parse_key(k)
		if not pk.is_empty():
			keep[pk[0]] = true
	if DirAccess.dir_exists_absolute(root):
		for p in DirAccess.get_directories_at(root):
			if pid_ok(p) and not keep.has(p):
				remove_prefab_dir(root.path_join(p))
	if keep.is_empty():
		if DirAccess.dir_exists_absolute(root) and DirAccess.get_directories_at(root).is_empty() and DirAccess.get_files_at(root).is_empty():
			DirAccess.remove_absolute(root)
		return OK
	for k in texts:
		var pk := parse_key(k)
		if pk.is_empty():
			continue
		var pd := root.path_join(String(pk[0]))
		var err := DirAccess.make_dir_recursive_absolute(pd)
		if err != OK and not DirAccess.dir_exists_absolute(pd):
			return err
		var path := pd.path_join(String(pk[1]))
		if pk[1] == MODEL_FILE:
			var bytes := Marshalls.base64_to_raw(String(texts[k]))
			if FileAccess.file_exists(path) and FileAccess.get_size(path) == bytes.size() \
					and FileAccess.get_sha256(path) == CustomMapGuard.sha256_hex(bytes):
				continue
			var fb := FileAccess.open(path, FileAccess.WRITE)
			if fb == null:
				return FileAccess.get_open_error()
			fb.store_buffer(bytes)
			fb.close()
		else:
			var ft := FileAccess.open(path, FileAccess.WRITE)
			if ft == null:
				return FileAccess.get_open_error()
			ft.store_string(String(texts[k]))
			ft.close()
		# Modèle retiré d'un prefab (devenu un groupe) : fichier effacé.
		if pk[1] == DEF_FILE and not texts.has(model_key(String(pk[0]))) and FileAccess.file_exists(pd.path_join(MODEL_FILE)):
			DirAccess.remove_absolute(pd.path_join(MODEL_FILE))
	return OK


## Efface un dossier de prefab : ses deux fichiers, puis le dossier s'il est vide.
static func remove_prefab_dir(pd: String) -> void:
	for f in [DEF_FILE, MODEL_FILE]:
		if FileAccess.file_exists(pd.path_join(f)):
			DirAccess.remove_absolute(pd.path_join(f))
	DirAccess.remove_absolute(pd)


## Efface tout le dossier prefabs/ d'une carte (cache : carte retirée).
static func remove_all(dir: String) -> void:
	var root := dir.path_join(DIR)
	if not DirAccess.dir_exists_absolute(root):
		return
	for p in DirAccess.get_directories_at(root):
		if pid_ok(p):
			remove_prefab_dir(root.path_join(p))
	DirAccess.remove_absolute(root)


# ------------------------------------------------------------------ contrôle des textes d'une carte reçue

## Contrôle des entrées de prefab parmi les textes d'une carte (CustomMapGuard) :
## noms des entrées, nombre, tailles, définitions, modèles (base64 puis
## check_glb, empreinte), modèle présent pour chaque prefab modèle (et
## seulement pour eux). `refs` : prefabs cités par les objets posés (doivent
## exister). Liste de raisons [fr, en] (vide : accepté).
static func check_entries(texts: Dictionary, refs: Dictionary) -> Array:
	var out := []
	var defs := {}
	var models := {}
	var total := 0
	for k in texts:
		var pk := parse_key(k)
		if pk.is_empty():
			continue
		if not texts[k] is String:
			out.append(["prefab : entrée illisible", "prefab: unreadable entry"])
			return out
		if pk[1] == DEF_FILE:
			defs[pk[0]] = texts[k]
		else:
			models[pk[0]] = texts[k]
	if defs.size() > MAX_PREFABS:
		return [["trop de prefabs (%d, au plus %d)" % [defs.size(), MAX_PREFABS], "too many prefabs (%d, at most %d)" % [defs.size(), MAX_PREFABS]]]
	if models.size() > MAX_MODELS:
		return [["trop de modèles importés (%d, au plus %d)" % [models.size(), MAX_MODELS], "too many imported models (%d, at most %d)" % [models.size(), MAX_MODELS]]]
	for pid in models:
		if not defs.has(pid):
			return [["prefab %s : modèle sans prefab.json" % pid, "prefab %s: model without prefab.json" % pid]]
	for pid in defs:
		var t: String = defs[pid]
		if t.to_utf8_buffer().size() > MAX_DEF_BYTES:
			return [["prefab %s : prefab.json trop gros" % pid, "prefab %s: prefab.json too big" % pid]]
		var dep := CustomMapGuard.json_depth(t)
		var d: Variant = CustomMapGuard.parse_json(t) if dep >= 0 and dep <= 6 else null
		var bad := check_def(d)
		if not bad.is_empty():
			return [["prefab %s : %s" % [pid, bad[0]], "prefab %s: %s" % [pid, bad[1]]]]
		if is_model(d) != models.has(pid):
			return [["prefab %s : modèle absent ou en trop" % pid, "prefab %s: missing or unexpected model" % pid]]
		if models.has(pid):
			var s: String = models[pid]
			if s.length() > MAX_MODEL_B64:
				return [["prefab %s : modèle trop gros" % pid, "prefab %s: model too big" % pid]]
			# Alphabet base64 vérifié avant le décodage (pas d'erreur du moteur).
			var b64re := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")
			if s.is_empty() or s.length() % 4 != 0 or b64re.search(s) == null:
				return [["prefab %s : modèle mal encodé" % pid, "prefab %s: badly encoded model" % pid]]
			var raw := Marshalls.base64_to_raw(s)
			if raw.is_empty() or Marshalls.raw_to_base64(raw) != s:
				return [["prefab %s : modèle mal encodé" % pid, "prefab %s: badly encoded model" % pid]]
			total += raw.size()
			if total > MAX_MODELS_BYTES:
				@warning_ignore("integer_division")
				return [["modèles trop gros (%d Mo au plus en tout)" % (MAX_MODELS_BYTES / 1048576), "models too big (%d MB at most in all)" % (MAX_MODELS_BYTES / 1048576)]]
			var gb := check_glb(raw)
			if not gb.is_empty():
				return [["prefab %s : %s" % [pid, gb[0]], "prefab %s: %s" % [pid, gb[1]]]]
			if CustomMapGuard.sha256_hex(raw) != String(d.modele.sha256):
				return [["prefab %s : empreinte du modèle incorrecte" % pid, "prefab %s: wrong model fingerprint" % pid]]
	for pid in refs:
		if not defs.has(pid):
			out.append(["objet posé : prefab de la carte « %s » absent" % pid, "placed object: map prefab \"%s\" missing" % pid])
			return out
	return out
