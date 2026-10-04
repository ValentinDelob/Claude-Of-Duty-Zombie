class_name McpTools
extends RefCounted
## Outils MCP de l'éditeur de cartes (serveur MCP du jeu, McpServer ;
## docs/MCP.md). Registre extensible : une définition = {name, description,
## inputSchema} plus
## - `cmd` : commande transmise TELLE QUELLE (arguments compris) à
##   `handle(cmd, args)` de l'éditeur ouvert (MapAgentLink) ; le résultat
##   (Dictionary) est rendu en texte JSON, {"error": texte} en erreur d'outil ;
## - ou `fn` : Callable(args: Dictionary) -> Array (contenu MCP) ou Err
##   (erreur d'outil), coroutine permise (contrôles d'arguments, résumé…).
## add_tool() en ajoute ou en remplace (même nom).
##
## Contrôles et messages repris du pont Python d'origine
## (tools/mcp/map_editor_mcp.py, supprimé) : mêmes noms, schémas, erreurs.

const MAX_OPS := 5000
const MAX_DEPTH := 8
const MAX_ID_LEN := 64
const MAX_BATCH_BYTES := 2 * 1024 * 1024 - 4096
const COLLS := ["pieces", "ouvertures", "objets", "zones"]
const VIEWS := ["dessus", "avant", "arriere", "gauche", "droite", "dessous"]
const MAX_EVENTS := 100
## Résumé de carte (portage GDScript de map_geom.py), chargé s'il existe.

const OPEN_EDITOR := "Éditeur de cartes non ouvert : ouvre l'éditeur de cartes du jeu (menu principal > ÉDITEUR DE CARTES) avec une carte, puis réessaie. (Le serveur MCP répond tant que le jeu tourne ; les outils de carte ont besoin de l'éditeur.)"


## Erreur d'outil (résultat isError) ; tout autre retour d'un `fn` est du contenu.
class Err:
	var text := ""

	func _init(t: String) -> void:
		text = t


## Serveur (éditeur enregistré, journal des événements).
var server: Node
var defs: Array = []


func _init(srv: Node = null) -> void:
	server = srv
	defs = _builtin()
	# Prefabs et modèles 3D de la carte (commandes de MapAgentPrefabs).
	for d in MapAgentPrefabs.tool_defs():
		add_tool(d)
	# Textures de la carte (format 16, MapAgentTextures).
	for d in MapAgentTextures.tool_defs():
		add_tool(d)


## Ajoute (ou remplace, même nom) un outil. Rend "" ou l'erreur.
func add_tool(def: Dictionary) -> String:
	if not def.get("name") is String or String(def.name).is_empty() or not def.get("description") is String or not def.get("inputSchema") is Dictionary:
		return "outil : name, description et inputSchema obligatoires"
	if not (def.get("cmd") is String or def.get("fn") is Callable):
		return "outil %s : « cmd » (commande de l'éditeur) ou « fn » (Callable) obligatoire" % def.name
	for i in defs.size():
		if String(defs[i].name) == String(def.name):
			defs[i] = def
			return ""
	defs.append(def)
	return ""


func find(name: String) -> Dictionary:
	for d in defs:
		if String(d.name) == name:
			return d
	return {}


## Liste publiée (tools/list) : sans `cmd` ni `fn`.
func list() -> Array:
	var out := []
	for d: Dictionary in defs:
		var pub := {}
		for k in d:
			if k != "cmd" and k != "fn":
				pub[k] = d[k]
		out.append(pub)
	return out


## tools/call : {content, isError}. Jamais d'erreur de script remontée : un
## résultat inattendu devient une erreur d'outil.
func call_tool(name: String, args: Variant) -> Dictionary:
	var d := find(name)
	if d.is_empty():
		return result([text("Outil inconnu : %s" % name.left(80))], true)
	if not args is Dictionary:
		return result([text("Arguments invalides (objet JSON attendu).")], true)
	var out: Variant
	if d.get("fn") is Callable:
		out = await (d.fn as Callable).call(args)
	else:
		var r: Variant = await request(String(d.cmd), args)
		out = r if r is Err else [text(r)]
	if out is Err:
		return result([text((out as Err).text)], true)
	if not out is Array:
		return result([text("Erreur interne du serveur MCP (outil %s)." % name)], true)
	return result(out, false)


static func result(content: Array, is_error: bool) -> Dictionary:
	return {"content": content, "isError": is_error}


static func text(v: Variant) -> Dictionary:
	return {"type": "text", "text": v if v is String else JSON.stringify(v, "", false)}


## Commande à l'éditeur ouvert : son résultat, ou Err.
func request(cmd: String, args: Dictionary) -> Variant:
	var ed: Object = server.editor() if server != null else null
	if ed == null:
		return Err.new(OPEN_EDITOR)
	var r: Variant = await ed.handle(cmd, args)
	if r is Dictionary and (r as Dictionary).size() == 1 and (r as Dictionary).has("error"):
		return Err.new(str(r.error) if str(r.error) != "" else "erreur inconnue de l'éditeur")
	if r == null:
		return Err.new("l'éditeur n'a pas répondu à « %s »" % cmd)
	# Résultat vide : la commande a échoué en route (erreur de script) ; ne
	# jamais le faire passer pour un succès.
	if r is Dictionary and (r as Dictionary).is_empty():
		return Err.new("l'éditeur a échoué sur « %s » (erreur interne, voir le journal du jeu) : rien n'a été appliqué, vérifie avec editor_get_map" % cmd)
	return r


# ------------------------------------------------------------------ contrôle des opérations

static func _depth(v: Variant, d := 1) -> int:
	var m := d
	if v is Dictionary:
		for x in (v as Dictionary).values():
			m = maxi(m, _depth(x, d + 1))
	elif v is Array:
		for x in v:
			m = maxi(m, _depth(x, d + 1))
	return m


static func _finite(v: Variant) -> bool:
	if v is float:
		return is_finite(v)
	if v is Dictionary:
		return (v as Dictionary).values().all(func(x): return _finite(x))
	if v is Array:
		return (v as Array).all(func(x): return _finite(x))
	return true


## Entier JSON (les nombres JSON arrivent en float).
static func is_int(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15)


static func is_num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _repr(v: Variant) -> String:
	if v == null:
		return "None"
	if v is String:
		return "'%s'" % String(v).left(40)
	return str(v).left(40)


## Contrôle local d'un lot (avant envoi) ; "" si valide. Reprend
## MapOps.validate (docs/MAP_COLLAB.md § 2) pour une erreur claire.
static func check_ops(ops: Variant) -> String:
	if not ops is Array or (ops as Array).is_empty():
		return "ops doit être une liste non vide d'opérations"
	if (ops as Array).size() > MAX_OPS:
		return "trop d'opérations (%d, %d au plus par lot)" % [(ops as Array).size(), MAX_OPS]
	for i in (ops as Array).size():
		var op: Variant = ops[i]
		var where := "ops[%d]" % i
		if not op is Dictionary:
			return "%s : une opération est un objet JSON" % where
		var kind: Variant = op.get("op")
		var kname := String(kind) if kind is String else ""
		if kname in ["put", "add", "del"] and not (op.get("coll") is String and String(op.coll) in COLLS):
			return "%s : coll doit être l'une de %s" % [where, ", ".join(COLLS)]
		match kname:
			"put":
				var el: Variant = op.get("el")
				if not el is Dictionary:
					return "%s : put demande « el » (l'élément complet)" % where
				var eid: Variant = el.get("id")
				if not eid is String or String(eid).is_empty() or String(eid).length() > MAX_ID_LEN:
					return "%s : put demande un el.id texte de 1 à %d caractères (pour créer, utilise « add »)" % [where, MAX_ID_LEN]
			"add":
				var el: Variant = op.get("el")
				if not el is Dictionary:
					return "%s : add demande « el »" % where
				var eid: Variant = el.get("id")
				if eid != null and not (eid is String and String(eid).begins_with("$") and String(eid).substr(1).is_valid_int() and not String(eid).substr(1).begins_with("-") and not String(eid).substr(1).begins_with("+")):
					return "%s : add : el.id absent ou provisoire (\"$1\", \"$2\"…), l'éditeur attribue le vrai id" % where
			"del":
				if not op.get("id") is String or String(op.id).is_empty():
					return "%s : del demande « id »" % where
			"carte":
				if not op.get("carte") is Dictionary:
					return "%s : carte demande « carte » (le dictionnaire carte complet)" % where
			"depart":
				if not op.get("id") is String:
					return "%s : depart demande « id » (id de zone)" % where
			_:
				return "%s : op inconnue %s (put, add, del, carte, depart)" % [where, _repr(kind)]
		var el: Variant = op.get("el")
		if kname in ["put", "add"] and el is Dictionary and String((el as Dictionary).get("type", "")) == "escalier" and (el as Dictionary).has("marches"):
			# Nombre de marches : toujours automatique (≈ 18 cm chacune) ; une
			# carte d'avant qui l'avait le perd à sa relecture (tidy_stair).
			return "%s : le nombre de marches n'est plus réglable (toujours automatique, ≈ 18 cm par marche) : retire « marches »" % where
		if _depth(op) > MAX_DEPTH:
			return "%s : trop profond (%d niveaux au plus)" % [where, MAX_DEPTH]
		if not _finite(op):
			return "%s : nombre non fini (NaN ou infini)" % where
	var size := JSON.stringify(ops, "", false).to_utf8_buffer().size()
	if size > MAX_BATCH_BYTES:
		return "lot trop gros (%d octets, 2 Mo au plus par message)" % size
	return ""


## « ids » : liste de textes non vides (Err sinon).
static func _ids(args: Dictionary, required := true) -> Variant:
	var ids: Variant = args.get("ids")
	if ids == null and not required:
		return []
	if not ids is Array or not (ids as Array).all(func(i): return i is String and not String(i).is_empty()) or (required and (ids as Array).is_empty()):
		return Err.new("« ids » doit être une liste d'identifiants texte (ex. [\"p3\", \"o1\"]).")
	return ids


## Carte complète de l'éditeur ouvert (ou Err).
func _map() -> Variant:
	var doc: Variant = await request("get_map", {})
	if doc is Err:
		return doc
	if not doc is Dictionary:
		return Err.new("réponse get_map inattendue de l'éditeur")
	return doc


# ------------------------------------------------------------------ outils

func _t_get_map(args: Dictionary) -> Variant:
	var fmt: Variant = args.get("format", "summary")
	if not (fmt is String and String(fmt) in ["summary", "full"]):
		return Err.new("format : \"summary\" ou \"full\"")
	var floor_v: Variant = args.get("floor")
	if fmt == "summary" and floor_v != null and not (is_int(floor_v) and float(floor_v) >= 0):
		return Err.new("floor : entier ≥ 0")
	var doc: Variant = await _map()
	if doc is Err:
		return doc
	if fmt == "full":
		return [text(doc)]
	return [text(MapSummary.summarize(doc, -1 if floor_v == null else int(floor_v)))]


func _t_get_element(args: Dictionary) -> Variant:
	var ids: Variant = _ids(args)
	if ids is Err:
		return ids
	var r: Variant = await request("get_elements", {"ids": ids})
	if not r is Err:
		return [text(r)]
	# Éditeur d'avant les vues multiples : les éléments sans hauteurs.
	if not ((r as Err).text.contains("commande inconnue") or (r as Err).text.contains("unknown command")):
		return r
	var doc: Variant = await _map()
	if doc is Err:
		return doc
	return [text(MapSummary.find_elements(doc, ids))]


func _t_apply(args: Dictionary) -> Variant:
	var label: Variant = args.get("label")
	if not label is String or String(label).strip_edges().is_empty():
		return Err.new("« label » obligatoire : un libellé court en français (affiché à l'utilisateur).")
	var ops: Variant = args.get("ops")
	var err := check_ops(ops)
	if err != "":
		return Err.new("Lot refusé avant envoi : " + err)
	var animate: Variant = args.get("animate", true)
	if not animate is bool:
		return Err.new("animate : true ou false")
	var cut: Variant = args.get("decouper", false)
	if not cut is bool:
		return Err.new("decouper : true ou false")
	var req := {"label": String(label).strip_edges().left(120), "ops": ops, "animate": animate}
	if cut:
		req["decouper"] = true
	var res: Variant = await request("apply", req)
	if res is Err:
		return res
	var out := [text(res)]
	if res is Dictionary and res.get("decoupe") is Array and not (res.decoupe as Array).is_empty():
		var parts := []
		for d in res.decoupe:
			if d is Dictionary:
				parts.append(str(d.get("texte", "")))
		out.append(text("Découpe faite : %s Préviens l'utilisateur." % " ".join(parts)))
	if res is Dictionary and res.get("invalid") is Dictionary and not (res.invalid as Dictionary).is_empty():
		out.append(text("Attention : %d élément(s) refusé(s) par l'éditeur (voir « invalid ») ; le reste du lot est appliqué." % (res.invalid as Dictionary).size()))
	return out


func _t_screenshot(args: Dictionary) -> Variant:
	var a := {}
	if args.has("floor"):
		var f: Variant = args.floor
		if not (is_int(f) and float(f) >= 0):
			return Err.new("floor : entier ≥ 0")
		a["floor"] = int(f)
	var ids: Variant = _ids(args, false)
	if ids is Err:
		return ids
	if not (ids as Array).is_empty():
		a["ids"] = ids
	var view: Variant = args.get("view", "dessus")
	if not (view is String and String(view) in VIEWS):
		return Err.new("view : " + ", ".join(VIEWS))
	if view != "dessus":
		a["view"] = view
	if args.has("coupe"):
		var c: Variant = args.coupe
		if not c is Array or (c as Array).size() != 2 or not (c as Array).all(func(x): return is_num(x)):
			return Err.new("coupe : [p0, p1] en mètres")
		a["coupe"] = [float(c[0]), float(c[1])]
	var res: Variant = await request("screenshot", a)
	if res is Err:
		return res
	if not res is Dictionary or not res.get("png_base64") is String:
		return Err.new("réponse screenshot inattendue de l'éditeur")
	# Éditeur d'avant les vues multiples : il ignore `view` et rend le plan.
	if view != "dessus" and str(res.get("view", "")) != view:
		return Err.new("cet éditeur ne sait pas montrer la vue « %s » (mettez-le à jour) ; seule la vue dessus est disponible" % view)
	var data := String(res.png_base64)
	var raw := Marshalls.base64_to_raw(data)
	if raw.is_empty():
		return Err.new("image illisible renvoyée par l'éditeur")
	if raw.size() < 4 or raw[0] != 0x89 or raw[1] != 0x50 or raw[2] != 0x4E or raw[3] != 0x47:
		return Err.new("l'éditeur n'a pas renvoyé un PNG")
	var info := {}
	for k in res:
		if k != "png_base64":
			info[k] = res[k]
	if info.has("bounds_z"):
		info["unites"] = "bounds_h = axe horizontal de l'écran (vraies coordonnées, gauche → droite), bounds_z = altitude (bas → haut), en mètres"
	else:
		info["unites"] = "bounds = [x0, y0, x1, y1] en mètres (x vers l'est, y vers le sud)"
	return [{"type": "image", "data": data, "mimeType": "image/png"}, text(info)]


func _t_highlight(args: Dictionary) -> Variant:
	var ids: Variant = _ids(args)
	if ids is Err:
		return ids
	var msg: Variant = args.get("message", "")
	if not msg is String:
		return Err.new("message : texte")
	var sel: Variant = args.get("select", false)
	if not sel is bool:
		return Err.new("select : vrai ou faux")
	var req := {"ids": ids, "message": String(msg).left(200)}
	if sel:
		req["select"] = true
	var r: Variant = await request("highlight", req)
	return r if r is Err else [text(r)]


func _t_events(args: Dictionary) -> Variant:
	var limit: Variant = args.get("limit", 20)
	if not (is_int(limit) and float(limit) >= 1 and float(limit) <= MAX_EVENTS):
		return Err.new("limit : entier de 1 à 100")
	var all: Array = server.events if server != null else []
	var evs := all.slice(maxi(0, all.size() - int(limit)))
	var on: bool = server != null and server.editor() != null
	if evs.is_empty():
		return [text("Aucun événement reçu de l'éditeur depuis le lancement du jeu." + ("" if on else " (éditeur de cartes fermé pour l'instant)"))]
	return [text({"events": evs, "connecte": on})]


func _t_plan_corridor(args: Dictionary) -> Variant:
	var a: Variant = args.get("room_a")
	var b: Variant = args.get("room_b")
	if not a is String or not b is String:
		return Err.new("room_a et room_b : id ou nom de pièce (texte)")
	var width: Variant = args.get("width", args.get("largeur", 2.5))
	if not is_num(width):
		return Err.new("width : nombre (m)")
	var price: Variant = args.get("price")
	if price != null and not (is_int(price) and float(price) >= 0):
		return Err.new("price : entier ≥ 0")
	var doc: Variant = await _map()
	if doc is Err:
		return doc
	var plan: Variant = MapSummary.plan_corridor(doc, String(a), String(b), float(width), -1 if price == null else int(price))
	if plan is Dictionary and (plan as Dictionary).has("error"):
		return Err.new("Pas de proposition : %s" % str(plan.error))
	return [text(plan)]


func _t_guide(args: Dictionary) -> Variant:
	var r := McpDocs.guide(args.get("topic"), args.get("section"))
	if r.has("error"):
		return Err.new(String(r.error))
	return [text(String(r.text))]


# ------------------------------------------------------------------ définitions

static func _ids_schema(desc: String) -> Dictionary:
	return {"type": "array", "items": {"type": "string"}, "description": desc}


static func _no_args() -> Dictionary:
	return {"type": "object", "properties": {}, "additionalProperties": false}


func _builtin() -> Array:
	return [
		{
			"name": "editor_guide",
			"description": "Documentation de l'éditeur de cartes livrée avec le jeu. topic : « regles » (règles de conception OBLIGATOIRES et leur grille de contrôle), "
				+ "« consignes » (consignes détaillées : hauteurs, échelle et inclinaison, escaliers, pièces qui se recouvrent), « format » (l'éditeur et le format des "
				+ "éléments), « objets » (variantes, barrière invisible, escaliers, décor libre, portes à zombies, effets), « vues » (élévations, hauteurs), « echelle » "
				+ "(échelle et rotation 3D du décor). Les gros sujets rendent la liste de leurs sections : rappeler avec « section » (numéro comme \"4\" ou \"6.4\", ou mots du titre). Sans topic : la liste des sujets.",
			"inputSchema": {"type": "object", "properties": {
				"topic": {"type": "string", "enum": McpDocs.TOPICS, "description": "Sujet."},
				"section": {"type": "string", "description": "Section à rendre seule (facultatif) : numéro (\"4\", \"6.4\", \"2 bis\") ou mots du titre."},
			}, "additionalProperties": false},
			"fn": _t_guide,
		},
		{
			"name": "editor_status",
			"description": "État de l'éditeur de cartes ouvert : carte (id, nom), rôle (solo / hôte / invité), participants, "
				+ "étage affiché, sélection, modifications non enregistrées. À appeler en premier.",
			"inputSchema": _no_args(),
			"cmd": "status",
		},
		{
			"name": "editor_get_map",
			"description": "Lit la carte ouverte. format \"summary\" (défaut) : résumé calculé pour raisonner — par étage, pièces "
				+ "(id, nom, zone, bbox [x0,y0,x1,y1] en m, surface m², contour si non rectangulaire, voisines par mur "
				+ "commun avec le bord partagé, pièces proches non collées avec les points les plus proches), "
				+ "ouvertures (type, position, largeur, prix, pièces reliées), objets regroupés par type (id, position "
				+ "ou rect, sommets d'une barrière invisible, atout/arme/prefab, mur), zones et zone de départ, totaux. format \"full\" : la carte "
				+ "complète {carte, pieces, ouvertures, objets, zones, depart} (format : editor_guide, sujet « format », section « Format des fichiers »).",
			"inputSchema": {"type": "object", "properties": {
				"format": {"type": "string", "enum": ["summary", "full"], "default": "summary"},
				"floor": {"type": "integer", "minimum": 0, "description": "Résumé d'un seul étage (facultatif)."},
			}, "additionalProperties": false},
			"fn": _t_get_map,
		},
		{
			"name": "editor_get_element",
			"description": "Éléments complets (toutes leurs clés) d'après leurs ids, avec leur collection (pieces, ouvertures, "
				+ "objets, zones) et leurs hauteurs : z_min / z_max (m, absolus : la boîte de l'élément, plafond réel "
				+ "compris), z_monde (altitude du point de pose), hauteur_pose (m au-dessus du sol de l'étage, si le type "
				+ "en a une) et glissement_vertical (pose, niveau, fixe) ; objets : dimensions [l, p, h] finales (décor), "
				+ "echelle_possible, inclinaison_possible et raison (format 14). À relire avant un « put » qui modifie un élément.",
			"inputSchema": {"type": "object", "properties": {"ids": _ids_schema("Ids des éléments (p3, o1, a2…).")},
				"required": ["ids"], "additionalProperties": false},
			"fn": _t_get_element,
		},
		{
			"name": "editor_get_selection",
			"description": "Ce que l'utilisateur a sélectionné dans l'éditeur : ids (plusieurs en sélection multiple), éléments complets, étage affiché et position "
				+ "de la souris sur le plan (m). « ça », « cette pièce », « ici » désignent souvent la sélection ou le curseur.",
			"inputSchema": _no_args(),
			"cmd": "get_selection",
		},
		{
			"name": "editor_apply",
			"description": "Applique un lot d'opérations à la carte, en direct chez tous les participants. UN appel = UNE étape "
				+ "d'annulation (Ctrl+Z) pour l'utilisateur. Opérations : "
				+ "{\"op\":\"add\",\"coll\":C,\"el\":{…}} crée (sans id, ou id provisoire \"$1\", \"$2\"… que l'on peut "
				+ "citer ailleurs dans le même lot, ex. \"zone\":\"$1\" ; l'éditeur attribue les vrais ids, rendus dans "
				+ "« ids ») ; {\"op\":\"put\",\"coll\":C,\"el\":{\"id\":…,…}} remplace l'élément entier de même id ; "
				+ "{\"op\":\"del\",\"coll\":C,\"id\":…} supprime ; {\"op\":\"carte\",\"carte\":{…}} remplace carte "
				+ "(étages, noms) ; {\"op\":\"depart\",\"id\":zone} zone de départ. C ∈ pieces, ouvertures, objets, zones. "
				+ "Chaque élément porte « etage ». Résultat : cid, ids attribués, éléments refusés (invalid). "
				+ "Hauteurs, échelle et inclinaison du décor, escaliers, pièce posée sur une autre : lire d'abord editor_guide « consignes ».",
			"inputSchema": {"type": "object", "properties": {
				"label": {"type": "string", "minLength": 1, "maxLength": 120,
					"description": "Libellé court en français affiché à l'utilisateur et dans l'historique (« Couloir entrée → atelier »)."},
				"ops": {"type": "array", "minItems": 1, "maxItems": MAX_OPS, "items": {"type": "object", "properties": {
					"op": {"type": "string", "enum": ["add", "put", "del", "carte", "depart"]},
					"coll": {"type": "string", "enum": COLLS},
					"el": {"type": "object"}, "id": {"type": "string"}, "carte": {"type": "object"},
				}, "required": ["op"]}},
				"animate": {"type": "boolean", "default": true,
					"description": "Faire apparaître les éléments un par un chez l'utilisateur (défaut true)."},
				"decouper": {"type": "boolean", "default": false,
					"description": "Une pièce du lot recouvre des pièces existantes du même étage : true les découpe "
						+ "(la partie recouverte leur est retirée, dans le même lot ; détail dans « decoupe ») ; "
						+ "false (défaut) : le lot est refusé avec l'explication."},
			}, "required": ["label", "ops"], "additionalProperties": false},
			"fn": _t_apply,
		},
		{
			"name": "editor_undo_last",
			"description": "Annule la dernière modification de Claude encore active (comme un Ctrl+Z limité à Claude ; les "
				+ "éléments retouchés entre-temps par quelqu'un d'autre ne sont pas annulés).",
			"inputSchema": _no_args(),
			"cmd": "undo",
		},
		{
			"name": "editor_validate",
			"description": "Lance le validateur de l'éditeur (MapValidator) : erreurs bloquantes (carte refusée par TESTER) et "
				+ "avertissements de conception BO1, avec positions en mètres. À appeler après chaque modification.",
			"inputSchema": _no_args(),
			"cmd": "validate",
		},
		{
			"name": "editor_screenshot",
			"description": "Image PNG de l'éditeur pour voir le résultat : le plan d'un étage (view \"dessus\", défaut) ou une "
				+ "élévation qui montre tous les étages empilés à leur vraie hauteur (view \"avant\" : caméra au sud, "
				+ "regard vers le nord ; \"arriere\", \"gauche\", \"droite\", \"dessous\"), éventuellement cadrée sur des "
				+ "éléments. coupe [p0, p1] (élévations) : ne garder nettes que les éléments dans cette tranche de "
				+ "profondeur (y en avant/arriere, x en gauche/droite). Le texte joint donne les bornes en mètres.",
			"inputSchema": {"type": "object", "properties": {
				"floor": {"type": "integer", "minimum": 0, "description": "Étage (défaut : celui affiché ; plan seulement)."},
				"ids": _ids_schema("Cadrer sur ces éléments (facultatif)."),
				"view": {"type": "string", "enum": VIEWS, "default": "dessus", "description": "Plan ou élévation."},
				"coupe": {"type": "array", "minItems": 2, "maxItems": 2, "items": {"type": "number"},
					"description": "Tranche de profondeur [p0, p1] en m (élévations, facultatif)."},
			}, "additionalProperties": false},
			"fn": _t_screenshot,
		},
		{
			"name": "editor_highlight",
			"description": "Montre des éléments à l'utilisateur dans l'éditeur (contour pulsé + bulle avec le message). "
				+ "Pour désigner ce dont tu parles ou poser une question sur un endroit précis. Avec select: true, "
				+ "ils deviennent aussi la sélection de l'utilisateur (plusieurs ids : sélection multiple, prête pour "
				+ "un clic droit > Créer une prefab…, Dupliquer…). Si l'utilisateur est en plein geste (déplacement, "
				+ "rotation, poignée, tracé), la sélection n'est PAS changée (le geste serait annulé) : le résultat "
				+ "porte « busy » ; réessaie un peu plus tard.",
			"inputSchema": {"type": "object", "properties": {
				"ids": _ids_schema("Éléments à montrer."),
				"message": {"type": "string", "maxLength": 200, "description": "Bulle affichée (français)."},
				"select": {"type": "boolean", "description": "Sélectionner aussi ces éléments dans l'éditeur (défaut : non)."},
			}, "required": ["ids"], "additionalProperties": false},
			"fn": _t_highlight,
		},
		{
			"name": "editor_catalog",
			"description": "Catalogue de l'éditeur : types d'objets et d'ouvertures admis avec leurs clés (MapCatalog), décors "
				+ "(prefabs), luminaires, armes, atouts, textures ; « echelle »: false sur ce qui ne change jamais d'échelle "
				+ "(format 14). À lire avant de créer un type d'objet inconnu.",
			"inputSchema": _no_args(),
			"cmd": "catalog",
		},
		{
			"name": "editor_events",
			"description": "Derniers événements poussés par l'éditeur (changements faits par l'utilisateur ou d'autres "
				+ "participants, sélection, participants), du plus ancien au plus récent ; 100 gardés au plus.",
			"inputSchema": {"type": "object", "properties": {
				"limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 20},
			}, "additionalProperties": false},
			"fn": _t_events,
		},
		{
			"name": "editor_plan_corridor",
			"description": "PROPOSE (sans rien appliquer) les ops d'un couloir entre deux pièces du même étage : couloir droit "
				+ "si leurs murs se font face, en L sinon ; une simple porte si elles ont déjà un mur commun. Le couloir "
				+ "va dans la zone de room_a (passage libre côté A), porte payante côté B si B est d'une autre zone. "
				+ "Contrôle chevauchements et ouvertures existantes, signale les écarts aux règles (§ 3.2). "
				+ "Relire puis passer les ops à editor_apply avec le label proposé.",
			"inputSchema": {"type": "object", "properties": {
				"room_a": {"type": "string", "description": "Pièce de départ : id (p1…) ou nom (casse et accents ignorés)."},
				"room_b": {"type": "string", "description": "Pièce d'arrivée : id ou nom."},
				"width": {"type": "number", "minimum": 1, "maximum": 6, "default": 2.5,
					"description": "Largeur en m (multiple de 0,5 ; couloir principal 2 à 3 m)."},
				"price": {"type": "integer", "minimum": 0, "description": "Prix de la porte côté B (défaut : 750/1000/1250 selon les portes déjà posées)."},
			}, "required": ["room_a", "room_b"], "additionalProperties": false},
			"fn": _t_plan_corridor,
		},
	]
