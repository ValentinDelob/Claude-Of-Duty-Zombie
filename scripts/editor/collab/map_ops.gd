class_name MapOps
extends RefCounted
## OPÉRATIONS SUR LA CARTE de l'éditeur collaboratif (docs/MAP_COLLAB.md § 2) :
## diff entre deux instantanés, application, inversion, validation, empreinte
## canonique, ids provisoires « $n » des ajouts de l'agent. Logique pure : le
## document est un EditorMap ou son instantané (EditorMap.snapshot()).
##   {op: "put", coll, el, at?}  insère (à l'indice `at` s'il est donné, sinon
##                               en fin) ou remplace l'élément de même id
##   {op: "del", coll, id}       retire l'élément (absent : sans effet)
##   {op: "carte", carte}        remplace le dictionnaire carte
##   {op: "depart", id}          zone de départ
##   {op: "add", coll, el}       agent seulement : id attribué par resolve_adds
## Clé d'un élément touché : « coll:id », « carte » ou « depart ».

const COLLS := ["pieces", "ouvertures", "objets", "zones"]
const OPS := ["put", "del", "carte", "depart", "add"]
const MAX_OPS := 5000
const MAX_BYTES := 2 * 1024 * 1024
const MAX_DEPTH := 8
const MAX_ID_LEN := 64
## Préfixes d'identifiant par type d'objet (mêmes que MapEditor.add_object).
const OBJ_PREFIX := {"atout": "a", "arme": "w", "boite": "b", "depart": "s", "escalier": "e", "pilier": "x", "mur": "m", "mur_courbe": "m",
	"piege": "t", "levier": "l", "prefab": "d", "luminaire": "lu", "bloc_invisible": "i", "effet": "fx"}
## Taille maximale de chaque liste (mêmes limites que les cartes reçues).
const MAX_COUNT := {"pieces": CustomMapGuard.MAX_ROOMS, "ouvertures": CustomMapGuard.MAX_OPENINGS,
	"objets": CustomMapGuard.MAX_OBJECTS, "zones": CustomMapGuard.MAX_ZONES}


# ------------------------------------------------------------------ accès au document

## Liste `coll` du document (la vraie, modifiée sur place).
static func list(doc: Variant, coll: String) -> Array:
	if doc is Dictionary:
		if not (doc as Dictionary).get(coll) is Array:
			doc[coll] = []
		return doc[coll]
	return (doc as Object).get(coll)


static func _carte(doc: Variant) -> Dictionary:
	var c: Variant = doc.get("carte") if doc is Dictionary else (doc as Object).get("carte")
	return c if c is Dictionary else {}


static func _depart(doc: Variant) -> String:
	return String(doc.get("depart", "")) if doc is Dictionary else String((doc as Object).get("depart"))


static func _assign(doc: Variant, key: String, v: Variant) -> void:
	if doc is Dictionary:
		doc[key] = v
	else:
		(doc as Object).set(key, v)


static func key_of(coll: String, id: String) -> String:
	return "%s:%s" % [coll, id]


## Clé de l'élément touché par une opération.
static func op_key(op: Dictionary) -> String:
	match String(op.get("op", "")):
		"carte":
			return "carte"
		"depart":
			return "depart"
		"del":
			return key_of(String(op.get("coll", "")), String(op.get("id", "")))
	var el: Variant = op.get("el", {})
	return key_of(String(op.get("coll", "")), String(el.get("id", "")) if el is Dictionary else "")


## Clés touchées par un lot (sans doublon, dans l'ordre).
static func touched(ops: Array) -> Array:
	var seen := {}
	var out := []
	for op in ops:
		var k := op_key(op)
		if not seen.has(k):
			seen[k] = true
			out.append(k)
	return out


## Identifiants des éléments touchés (ni carte ni départ).
static func ids_of(ops: Array) -> Array:
	var out := []
	for k in touched(ops):
		if k.contains(":"):
			out.append(k.get_slice(":", 1))
	return out


# ------------------------------------------------------------------ diff, application, inverse

## Opérations minimales qui mènent de `before` à `after` (instantanés ou
## cartes) : put des éléments nouveaux (avec leur indice) ou changés, del des
## disparus, carte / depart s'ils ont changé. Si l'ordre des éléments gardés a
## changé dans une liste (rare), elle est remplacée entière.
static func diff(before: Variant, after: Variant) -> Array:
	var ops := []
	for coll in COLLS:
		var a: Array = list(before, coll)
		var b: Array = list(after, coll)
		var old := {}
		for e in a:
			old[String(e.get("id", ""))] = e
		var now := {}
		for e in b:
			now[String(e.get("id", ""))] = true
		# Ordre des éléments gardés inchangé ?
		var kept_a := []
		for e in a:
			if now.has(String(e.get("id", ""))):
				kept_a.append(String(e.get("id", "")))
		var kept_b := []
		for e in b:
			if old.has(String(e.get("id", ""))):
				kept_b.append(String(e.get("id", "")))
		if kept_a != kept_b:
			for e in a:
				ops.append({"op": "del", "coll": coll, "id": String(e.get("id", ""))})
			for i in b.size():
				ops.append({"op": "put", "coll": coll, "el": (b[i] as Dictionary).duplicate(true), "at": i})
			continue
		for e in a:
			if not now.has(String(e.get("id", ""))):
				ops.append({"op": "del", "coll": coll, "id": String(e.get("id", ""))})
		for i in b.size():
			var e: Dictionary = b[i]
			var id := String(e.get("id", ""))
			if not old.has(id):
				ops.append({"op": "put", "coll": coll, "el": e.duplicate(true), "at": i})
			elif not _same(old[id], e):
				ops.append({"op": "put", "coll": coll, "el": e.duplicate(true)})
	if not _same(_carte(before), _carte(after)):
		ops.append({"op": "carte", "carte": _carte(after).duplicate(true)})
	if _depart(before) != _depart(after):
		ops.append({"op": "depart", "id": _depart(after)})
	return ops


## Égalité de contenu (un entier et le même nombre décimal sont égaux).
static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


## Applique les opérations au document (EditorMap ou instantané), dans l'ordre.
## Les éléments sont copiés (aucune référence partagée avec `ops`).
static func apply(doc: Variant, ops: Array) -> void:
	var pos := {}     # coll -> {id: indice}, refait après une insertion ou un retrait
	for op in ops:
		match String(op.get("op", "")):
			"put":
				var coll := String(op.coll)
				var l := list(doc, coll)
				var el: Dictionary = (op.el as Dictionary).duplicate(true)
				var id := String(el.get("id", ""))
				var idx := _index(pos, l, coll, id)
				if idx >= 0:
					l[idx] = el
				else:
					var at := int(op.get("at", -1)) if (op.get("at") is int or op.get("at") is float) else -1
					if at >= 0 and at < l.size():
						l.insert(at, el)
						pos.erase(coll)
					else:
						l.append(el)
						if pos.has(coll):
							pos[coll][id] = l.size() - 1
			"del":
				var coll := String(op.coll)
				var l := list(doc, coll)
				var idx := _index(pos, l, coll, String(op.id))
				if idx >= 0:
					l.remove_at(idx)
					pos.erase(coll)
			"carte":
				_assign(doc, "carte", (op.carte as Dictionary).duplicate(true))
			"depart":
				_assign(doc, "depart", String(op.id))


static func _index(pos: Dictionary, l: Array, coll: String, id: String) -> int:
	if not pos.has(coll):
		var m := {}
		for i in l.size():
			m[String(l[i].get("id", ""))] = i
		pos[coll] = m
	return int(pos[coll].get(id, -1))


## Opérations qui remettent les éléments touchés par `ops` dans leur état de
## `doc_before` (le document AVANT ops) : del des éléments qui n'existaient
## pas, puis put des anciens (avec leur indice, dans l'ordre croissant : une
## suppression annulée retrouve sa place), carte et depart d'avant.
static func inverse(doc_before: Variant, ops: Array) -> Array:
	var dels := []
	var puts := []
	var tail := []
	var where := {}
	for coll in COLLS:
		var l: Array = list(doc_before, coll)
		for i in l.size():
			where[key_of(coll, String(l[i].get("id", "")))] = [coll, i]
	for k in touched(ops):
		if k == "carte":
			tail.append({"op": "carte", "carte": _carte(doc_before).duplicate(true)})
		elif k == "depart":
			tail.append({"op": "depart", "id": _depart(doc_before)})
		elif where.has(k):
			var w: Array = where[k]
			puts.append({"op": "put", "coll": w[0], "el": (list(doc_before, w[0])[w[1]] as Dictionary).duplicate(true), "at": w[1]})
		else:
			dels.append({"op": "del", "coll": k.get_slice(":", 0), "id": k.substr(k.find(":") + 1)})
	puts.sort_custom(func(x, y): return COLLS.find(x.coll) < COLLS.find(y.coll) or (x.coll == y.coll and int(x.at) < int(y.at)))
	return dels + puts + tail


## État actuel des clés `keys` dans `doc`, en opérations (put de l'élément
## présent, del de l'absent) : appliquées à une copie plus ancienne de la
## carte, elles la mettent à jour pour ces éléments seulement.
static func state_of(doc: Variant, keys: Array) -> Array:
	var out := []
	var where := {}
	for coll in COLLS:
		var l: Array = list(doc, coll)
		for i in l.size():
			where[key_of(coll, String(l[i].get("id", "")))] = [coll, i]
	for k in keys:
		if k == "carte":
			out.append({"op": "carte", "carte": _carte(doc).duplicate(true)})
		elif k == "depart":
			out.append({"op": "depart", "id": _depart(doc)})
		elif where.has(k):
			var w: Array = where[k]
			out.append({"op": "put", "coll": w[0], "el": (list(doc, w[0])[w[1]] as Dictionary).duplicate(true), "at": w[1]})
		else:
			out.append({"op": "del", "coll": k.get_slice(":", 0), "id": k.substr(k.find(":") + 1)})
	return out


## Ne garde que les opérations sur les clés `keys`.
static func only(ops: Array, keys: Array) -> Array:
	var want := {}
	for k in keys:
		want[k] = true
	return ops.filter(func(op): return want.has(op_key(op)))


# ------------------------------------------------------------------ validation

## "" si le lot est valide (§ 2) : liste de 5000 opérations au plus, type et
## collection connus, `el` dictionnaire avec un `id` texte non vide de 64
## caractères au plus (`add` : sans id ou id provisoire « $n », seulement si
## `allow_add`), valeurs JSON seulement (pas d'objet), profondeur 8 au plus,
## nombres finis, 2 Mo de JSON au plus. Sinon la raison (texte court).
static func validate(ops: Variant, allow_add := false) -> String:
	if not ops is Array:
		return "ops: liste attendue / list expected"
	if (ops as Array).size() > MAX_OPS:
		return "ops: %d opérations au plus / at most %d operations" % [MAX_OPS, MAX_OPS]
	for i in (ops as Array).size():
		var r := _validate_op(ops[i], allow_add)
		if r != "":
			return "op %d: %s" % [i, r]
	if (ops as Array).size() > 50 and JSON.stringify(ops).length() > MAX_BYTES:
		return "ops: 2 Mo au plus / 2 MB at most"
	return ""


static func _validate_op(op: Variant, allow_add: bool) -> String:
	if not op is Dictionary:
		return "dictionnaire attendu / dictionary expected"
	var kind: Variant = op.get("op")
	if not (kind is String and kind in OPS) or (kind == "add" and not allow_add):
		return "op inconnue / unknown op « %s »" % CustomMapGuard.clean_display(str(kind), 16)
	for k in op:
		if not (k is String and k in ["op", "coll", "el", "id", "carte", "at"]):
			return "clé inconnue / unknown key"
	match String(kind):
		"put", "add":
			if not (op.get("coll") is String and op.coll in COLLS):
				return "coll inconnue / unknown coll"
			var el: Variant = op.get("el")
			if not el is Dictionary:
				return "el: dictionnaire attendu / dictionary expected"
			var id: Variant = el.get("id")
			if kind == "put" and not _id_ok(id):
				return "el.id invalide / invalid el.id"
			if kind == "add" and id != null and not (_id_ok(id) and String(id).begins_with("$")):
				return "add: id absent ou provisoire « $n » / missing or temporary « $n » id"
			if op.has("at") and not ((op.at is int or op.at is float) and is_finite(float(op.at)) and float(op.at) >= 0.0 and float(op.at) < 1e6):
				return "at invalide / invalid at"
			if not value_ok(el, 1):
				return "el: valeur refusée (objet, profondeur, nombre non fini) / value refused"
		"del":
			if not (op.get("coll") is String and op.coll in COLLS):
				return "coll inconnue / unknown coll"
			if not _id_ok(op.get("id")):
				return "id invalide / invalid id"
		"carte":
			if not op.get("carte") is Dictionary or not value_ok(op.carte, 1):
				return "carte: valeur refusée / value refused"
		"depart":
			var id: Variant = op.get("id")
			if not (id is String and (id == "" or _id_ok(id))):
				return "id invalide / invalid id"
	return ""


static func _id_ok(id: Variant) -> bool:
	return id is String and not (id as String).is_empty() and (id as String).length() <= MAX_ID_LEN


## Valeur JSON pure (null, booléen, nombre fini, texte, liste, dictionnaire à
## clés texte), de profondeur MAX_DEPTH au plus.
static func value_ok(v: Variant, depth := 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(v)
		TYPE_ARRAY:
			for x in v:
				if not value_ok(x, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for k in v:
				if not k is String or not value_ok(v[k], depth + 1):
					return false
			return true
	return false


## Valeurs reçues remises au bon type (étage entier, identifiant texte), comme
## EditorMap._normalize : le reste garde les nombres décimaux du JSON.
static func normalize(ops: Array) -> void:
	for op in ops:
		var el: Variant = op.get("el")
		if el is Dictionary:
			if el.has("etage") and (el.etage is float or el.etage is int):
				el["etage"] = int(el.etage)


## Contrôle du contenu des éléments (mêmes règles que les cartes reçues,
## CustomMapGuard : types, clés, valeurs, étages) et des tailles maximales des
## listes. Rend {ops: les opérations admises, invalid: {id: raison}}.
static func check_elements(doc: Variant, ops: Array) -> Dictionary:
	var out := []
	var invalid := {}
	var floors := maxi(1, (_carte(doc).get("etages", []) as Array).size()) if _carte(doc).get("etages") is Array else 1
	var count := {}
	for coll in COLLS:
		count[coll] = list(doc, coll).size()
	var present := {}
	for coll in COLLS:
		for e in list(doc, coll):
			present[key_of(coll, String(e.get("id", "")))] = true
	for op in ops:
		var kind := String(op.get("op", ""))
		var c := CustomMapGuard.Check.new()
		c.floors = floors
		var id := ""
		match kind:
			"put":
				var coll := String(op.coll)
				var el: Dictionary = op.el
				id = String(el.get("id", ""))
				match coll:
					"pieces":
						CustomMapGuard._check_room(c, el, id)
					"ouvertures":
						CustomMapGuard._check_opening(c, el, id)
					"objets":
						CustomMapGuard._check_object(c, el, id)
						if not c.failed():
							_check_scale(c, el)
					"zones":
						_check_zone(c, el, id)
				# Format 15 : une texture de la carte citée doit exister.
				if not c.failed() and coll in ["pieces", "zones"]:
					_check_textures(c, doc, el)
				if not c.failed() and not present.has(key_of(coll, id)):
					if int(count[coll]) >= int(MAX_COUNT[coll]):
						c.bad("%s : trop d'éléments (%d au plus)" % [coll, MAX_COUNT[coll]], "%s: too many elements (at most %d)" % [coll, MAX_COUNT[coll]])
					else:
						count[coll] = int(count[coll]) + 1
						present[key_of(coll, id)] = true
			"carte":
				id = "carte"
				var cd: Dictionary = op.carte
				CustomMapGuard._check_carte(c, cd)
				if not c.failed():
					floors = maxi(1, (cd.get("etages", []) as Array).size())
			"depart":
				id = "depart"
				if not (op.id is String and (op.id == "" or CustomMapGuard.id_ok(op.id))):
					c.bad("zone de départ invalide", "invalid start zone")
			"del":
				present.erase(key_of(String(op.coll), String(op.id)))
		if c.failed():
			invalid[id] = Lang.t(String(c.reasons[0][0]), String(c.reasons[0][1]))
		else:
			out.append(op)
	return {"ops": out, "invalid": invalid}


## Format 14 : échelle et inclinaison d'un décor, avec sa définition (prefab
## de la carte bloqué : le refus nomme l'objet de jeu qu'il contient).
static func _check_scale(c: CustomMapGuard.Check, el: Dictionary) -> void:
	if not (el.has("echelle") or el.has("incl")) or String(el.get("type", "")) != "prefab":
		return
	if el.has("echelle") and not MapScale.read_scale(el.echelle).is_equal_approx(Vector3.ONE) and not MapScale.blockers_of(el).is_empty():
		var r := MapScale.scale_refusal(el)
		c.bad(String(r[0]).to_lower().left(1) + String(r[0]).substr(1), String(r[1]).to_lower().left(1) + String(r[1]).substr(1))
		return
	var bad := MapScale.check_object(el, MapScale.def_of(el), MapScale.blockers_of(el))
	if not bad.is_empty():
		c.bad(String(bad[0]), String(bad[1]))


## Format 15 : champs de surface d'une pièce ou d'une zone qui citent une
## texture de la carte (« map:<tid> ») absente de la bibliothèque du document.
static func _check_textures(c: CustomMapGuard.Check, doc: Variant, el: Dictionary) -> void:
	var defs: Variant = doc.get("textures", {}) if doc is Dictionary else (doc as Object).get("textures")
	for k in ["surface_sol", "surface_murs", "surface_plafond", "sol", "murs", "plafond"]:
		var tid := MapTextureLib.tid_of(el.get(k))
		if tid != "" and not (defs is Dictionary and (defs as Dictionary).has(tid)):
			c.bad("%s : texture de la carte « %s » inconnue (editor_texture_list, editor_texture_import)" % [k, tid],
				"%s: unknown map texture \"%s\" (editor_texture_list, editor_texture_import)" % [k, tid])
			return


static func _check_zone(c: CustomMapGuard.Check, z: Dictionary, what: String) -> void:
	var zk: Dictionary = CustomMapGuard.schema().zone_keys
	if not CustomMapGuard._keys(c, z, zk, what):
		return
	CustomMapGuard._id(c, z.get("id"), what)
	for k in z:
		if k != "id":
			CustomMapGuard._rule(c, zk[k], z[k], "%s (%s)" % [what, k])


# ------------------------------------------------------------------ empreinte

## JSON canonique de la carte : clés triées, nombres entiers sans décimale
## (un 2 local et un 2.0 reçu en JSON s'écrivent pareil), précision complète.
static func canonical(doc: Variant) -> String:
	var d := {"carte": _carte(doc), "depart": _depart(doc)}
	for coll in COLLS:
		d[coll] = list(doc, coll)
	return JSON.stringify(_canon(d), "", true, true)


static func _canon(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if f == floorf(f) and absf(f) < 1e15:
			return int(f)
		return f
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _canon(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return _canon(x))
	return v


static func hash_of(doc: Variant) -> String:
	return canonical(doc).sha256_text()


# ------------------------------------------------------------------ ajouts de l'agent

## Convertit les `add` en `put` : vrai identifiant (préfixe de
## MapEditor.add_object, premier numéro libre), « $n » cités ailleurs dans le
## lot remplacés par l'id attribué, étage 0 par défaut ; une pièce sans zone
## valide reçoit sa zone (même nom, comme add_object), une porte son prix par
## défaut, une seule boîte de départ. Rend {ops, ids: {"$n" (ou "#indice"
## d'un add sans id): id}}.
static func resolve_adds(doc: Variant, ops: Array) -> Dictionary:
	var used := {}
	for coll in COLLS:
		for e in list(doc, coll):
			used[String(e.get("id", ""))] = true
	var ids := {}
	var out := []
	# 1. Identifiants attribués (les références en avant du lot marchent).
	for i in ops.size():
		var op: Dictionary = (ops[i] as Dictionary).duplicate(true)
		if String(op.get("op", "")) == "add":
			var el: Dictionary = op.el
			var coll := String(op.coll)
			var prefix: String = {"pieces": "p", "ouvertures": "o", "zones": "z"}.get(coll, "")
			if prefix == "":
				prefix = String(OBJ_PREFIX.get(String(el.get("type", "")), "x"))
			var nid := _free_id(used, prefix)
			ids[String(el.id) if el.get("id") is String else "#%d" % i] = nid
			el["id"] = nid
			el["etage"] = int(el.get("etage", 0)) if (el.get("etage") is int or el.get("etage") is float) else 0
			op["op"] = "put"
		out.append(op)
	# 2. « $n » remplacés partout (zone d'une pièce, del, depart...).
	for i in out.size():
		out[i] = _subst(out[i], ids)
	# 3. Valeurs par défaut des nouveaux éléments (comme add_object).
	var zones := {}
	for z in list(doc, "zones"):
		zones[String(z.get("id", ""))] = true
	for op in out:
		if op.op == "put" and op.coll == "zones":
			zones[String(op.el.id)] = true
	var new_ids := {}
	for v in ids.values():
		new_ids[v] = true
	var extra := []
	var n_rooms := list(doc, "pieces").size()
	var n_doors := list(doc, "ouvertures").filter(func(o): return String(o.get("type", "")) in ["porte", "debris"]).size()
	var depart := _depart(doc)
	for op in out:
		if op.op != "put" or not new_ids.has(String(op.el.id)):
			continue
		var el: Dictionary = op.el
		match String(op.coll):
			"pieces":
				n_rooms += 1
				var named := el.has("nom")
				if not named:
					el["nom"] = Lang.t("Pièce %d", "Room %d") % n_rooms
				if not zones.has(String(el.get("zone", ""))):
					var zid := _free_id(used, "z")
					zones[zid] = true
					extra.append({"op": "put", "coll": "zones", "el": {"id": zid, "nom": {
						"fr": String(el.nom) if named else "Pièce %d" % n_rooms, "en": String(el.nom) if named else "Room %d" % n_rooms}}})
					el["zone"] = zid
					if depart == "":
						depart = zid
						extra.append({"op": "depart", "id": zid})
			"ouvertures":
				var t := String(el.get("type", ""))
				if t in ["porte", "debris"] and not el.has("prix"):
					el["prix"] = MapCatalog.DOOR_PRICES[mini(n_doors, MapCatalog.DOOR_PRICES.size() - 1)]
				if t in ["porte", "debris"]:
					n_doors += 1
				if t == "fenetre":
					el.erase("largeur")
			"objets":
				if String(el.get("type", "")) == "boite" and el.get("depart", false):
					for q in list(doc, "objets"):
						if String(q.get("type", "")) == "boite" and q.get("depart", false):
							var nq: Dictionary = q.duplicate(true)
							nq["depart"] = false
							extra.append({"op": "put", "coll": "objets", "el": nq})
	# Zones créées avant les pièces qui les citent.
	var zones_first := extra.filter(func(op): return op.op == "put" and op.coll == "zones")
	var rest := extra.filter(func(op): return not (op.op == "put" and op.coll == "zones"))
	return {"ops": zones_first + out + rest, "ids": ids}


static func _free_id(used: Dictionary, prefix: String) -> String:
	var n := 1
	while used.has("%s%d" % [prefix, n]):
		n += 1
	var id := "%s%d" % [prefix, n]
	used[id] = true
	return id


static func _subst(v: Variant, ids: Dictionary) -> Variant:
	if v is String:
		return ids.get(v, v) if (v as String).begins_with("$") else v
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _subst(v[k], ids)
		return out
	if v is Array:
		return (v as Array).map(func(x): return _subst(x, ids))
	return v


# ------------------------------------------------------------------ libellés

## Libellé court d'un changement (« Pièce « Hall » posée », « 3 éléments
## modifiés »), dans la langue du jeu ; `before` : le document avant.
static func describe(ops: Array, before: Variant) -> String:
	var keys := touched(ops).filter(func(k): return k.contains(":") and not k.begins_with("zones:"))
	if keys.is_empty():
		if touched(ops).has("carte"):
			return Lang.t("Réglages de la carte", "Map settings")
		return Lang.t("Zones modifiées", "Zones changed")
	if keys.size() > 1:
		return Lang.t("%d éléments modifiés", "%d elements changed") % keys.size()
	var k: String = keys[0]
	var coll := k.get_slice(":", 0)
	var id := k.substr(k.find(":") + 1)
	var old := {}
	for e in list(before, coll):
		if String(e.get("id", "")) == id:
			old = e
	var now := {}
	for op in ops:
		if op_key(op) == k:
			now = op.el if op.op == "put" else {}
	var e: Dictionary = now if not now.is_empty() else old
	var what := Lang.t("Pièce « %s »", "Room \"%s\"") % e.get("nom", "") if e.has("contour") else MapCatalog.name_of(MapCatalog.item_for(e))
	if old.is_empty():
		return Lang.t("%s posé", "%s placed") % what
	if now.is_empty():
		return Lang.t("%s supprimé", "%s deleted") % what
	return Lang.t("%s modifié", "%s changed") % what
