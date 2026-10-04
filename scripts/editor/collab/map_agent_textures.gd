class_name MapAgentTextures
extends RefCounted
## TEXTURES DE LA CARTE pilotées par Claude (MCP, docs/MAP_COLLAB.md § 5.2 ;
## format 15 : MapTextureLib, MapTextureTools). Commandes de la liaison agent
## (MapAgentLink._handle les délègue ici) :
##   texture_list            textures du jeu ET de la carte, référence à écrire,
##                           où chacune est utilisée
##   texture_import          image PNG / JPEG d'un chemin local ou en base64
##   texture_update          réglages (nom, taille du motif, rugosité, métal,
##                           teinte, image, carte des normales)
##   texture_delete          suppression (utilisée : refusée sauf « forcer »)
##   texture_import_from_map copie depuis une autre carte de l'utilisateur
## Appliquer une texture à une pièce ou une zone passe par « apply » (put de
## l'élément avec « surface_sol » : « map:<tid> »...) : MapOps.check_elements
## refuse une texture inconnue.
## Même règle que l'éditeur : en session, seul l'hôte (ou le solo) change la
## bibliothèque ; la carte est alors renvoyée aux invités (sans les images).
## Résultat : un dictionnaire, ou {"error": texte} dans la langue du jeu.

const CMDS := ["texture_list", "texture_import", "texture_update", "texture_delete", "texture_import_from_map"]


## Exécute la commande `cmd`. `editor` : l'éditeur (MapEditor), ou sans
## interface la liaison (MapAgentLink), la session (MapCollab) ou la carte
## (EditorMap) elle-même.
static func handle(editor: Object, cmd: String, args: Dictionary) -> Dictionary:
	var ctx := _ctx(editor)
	var doc: EditorMap = ctx.doc
	if doc == null:
		return _err(["aucune carte ouverte", "no open map"])
	match cmd:
		"texture_list":
			return list(doc)
	if not cmd in CMDS:
		return _err(["commande inconnue : %s" % cmd.left(40), "unknown command: %s" % cmd.left(40)])
	var collab: MapCollab = ctx.collab
	if collab != null and collab.role == MapCollab.Role.GUEST:
		return _err(["seul l'hôte de la session change les textures de la carte (vous êtes invité) : choisir une texture existante reste possible avec editor_apply",
			"only the session host changes the map textures (you are a guest): picking an existing texture is still possible with editor_apply"])
	var res: Dictionary
	match cmd:
		"texture_import":
			res = _import(doc, args)
		"texture_update":
			res = _update(doc, args)
		"texture_delete":
			res = _delete(doc, collab, args)
		"texture_import_from_map":
			res = _import_from_map(doc, args)
	if not res.has("error"):
		_changed(ctx)
	return res


static func _err(r: Array) -> Dictionary:
	return {"error": Lang.t(String(r[0]), String(r[1]))}


static func _ctx(editor: Object) -> Dictionary:
	var ed: MapEditor = null
	var collab: MapCollab = null
	var doc: EditorMap = null
	if editor is MapEditor:
		ed = editor
		collab = ed.collab
		doc = ed.doc
	elif editor is MapCollab:
		collab = editor
	elif editor is EditorMap:
		doc = editor
	elif editor != null:
		if editor.get("editor") is MapEditor:
			ed = editor.get("editor")
			doc = ed.doc
		if editor.get("collab") is MapCollab:
			collab = editor.get("collab")
	if doc == null and collab != null:
		doc = collab.doc
	return {"ed": ed, "collab": collab, "doc": doc}


## Bibliothèque changée : éditeur (panneaux, aperçu, carte modifiée) et invités.
static func _changed(ctx: Dictionary) -> void:
	if ctx.ed != null and (ctx.ed as MapEditor).texture_tools != null:
		(ctx.ed as MapEditor).texture_tools.library_changed()
	elif ctx.collab != null:
		(ctx.collab as MapCollab).broadcast_map()


# ------------------------------------------------------------------ commandes

## Description d'une texture de la carte (liste, résultats).
static func describe(doc: EditorMap, tid: String) -> Dictionary:
	var d: Dictionary = doc.textures[tid]
	var out := {"id": tid, "ref": MapTextureLib.ref(tid), "nom": d.nom, "taille": d.taille,
		"rugosite": d.get("rugosite", MapTextureLib.DEFAULTS.rugosite), "metal": d.get("metal", MapTextureLib.DEFAULTS.metal),
		"teinte": d.get("teinte", MapTextureLib.DEFAULTS.teinte), "couleur_moyenne": d.get("couleur", ""),
		"image": MapTextureLib.image_file(doc.texture_files, tid), "normale": MapTextureLib.image_file(doc.texture_files, tid, true) != "",
		"utilisee_par": MapTextureLib.users(doc, tid)}
	var b := MapTextureLib.image_bytes(doc.texture_files, tid)
	if not b.is_empty():
		var s := MapTextureLib.image_size(b)
		out["px"] = [s.x, s.y]
		out["hauteur_motif"] = snappedf(float(d.taille) * s.y / maxf(1.0, s.x), 0.01)
		out["octets"] = b.size()
	else:
		out["image_absente"] = true
	return out


static func list(doc: EditorMap) -> Dictionary:
	var game := []
	for k in MapCatalog.allowed_surfaces():
		var n: Array = MapCatalog.SURFACE_NAMES.get(k, [k, k])
		game.append({"ref": k, "nom": {"fr": n[0], "en": n[1]}})
	var used := {}
	for p in doc.pieces:
		for k in ["surface_sol", "surface_murs", "surface_plafond"]:
			if p.has(k) and not MapTextureLib.is_ref(p[k]):
				used.get_or_add(String(p[k]), []).append({"id": String(p.get("id", "")), "coll": "pieces", "cle": k})
	for z in doc.zones:
		for k in ["sol", "murs", "plafond"]:
			if z.has(k) and not MapTextureLib.is_ref(z[k]):
				used.get_or_add(String(z[k]), []).append({"id": String(z.get("id", "")), "coll": "zones", "cle": k})
	for g in game:
		if used.has(g.ref):
			g["utilisee_par"] = used[g.ref]
	var mine := []
	var ids := doc.textures.keys()
	ids.sort()
	for tid in ids:
		mine.append(describe(doc, tid))
	# Citées mais absentes de la bibliothèque (surface par défaut en jeu).
	var missing := {}
	for p in doc.pieces + doc.zones:
		for k in ["surface_sol", "surface_murs", "surface_plafond", "sol", "murs", "plafond"]:
			var tid := MapTextureLib.tid_of(p.get(k))
			if tid != "" and not doc.textures.has(tid):
				missing.get_or_add(MapTextureLib.ref(tid), []).append({"id": String(p.get("id", "")), "cle": k})
	return {"jeu": game, "carte": mine, "absentes": missing,
		"defauts": {"zone": {"sol": "concrete", "murs": "wall", "plafond": "ceiling"},
			"piece": Lang.t("sans clé : la surface de sa zone", "no key: its zone's surface")},
		"champs": {"pieces": ["surface_sol", "surface_murs", "surface_plafond"], "zones": ["sol", "murs", "plafond"]}}


## Octets d'une image d'après `chemin` (fichier local) ou `base64` ; {bytes},
## {} (rien de donné) ou {error}.
static func _bytes_of(args: Dictionary, path_key: String, b64_key: String) -> Dictionary:
	if args.get(path_key) is String and String(args[path_key]).strip_edges() != "":
		var got := MapTextureTools.read_file(String(args[path_key]).strip_edges())
		return _err(got.error) if got.has("error") else got
	if args.get(b64_key) is String and String(args[b64_key]) != "":
		var s := String(args[b64_key]).strip_edges()
		# « data:image/png;base64,... » accepté.
		if s.begins_with("data:") and s.contains(","):
			s = s.substr(s.find(",") + 1)
		s = s.replace("\n", "").replace("\r", "").replace(" ", "")
		var re := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")
		if s.length() % 4 != 0 or re.search(s) == null:
			return _err(["%s : base64 invalide" % b64_key, "%s: invalid base64" % b64_key])
		var raw := Marshalls.base64_to_raw(s)
		if raw.is_empty():
			return _err(["%s : base64 vide" % b64_key, "%s: empty base64" % b64_key])
		return {"bytes": raw}
	return {}


## Réglages communs des arguments (nom, taille, rugosite, metal, teinte).
static func _opts(args: Dictionary) -> Dictionary:
	var o := {}
	for k in ["nom", "taille", "rugosite", "metal", "teinte"]:
		if args.has(k) and args[k] != null:
			o[k] = args[k]
	return o


static func _import(doc: EditorMap, args: Dictionary) -> Dictionary:
	var img := _bytes_of(args, "chemin", "data_base64")
	if img.has("error"):
		return img
	if img.is_empty():
		return _err(["« chemin » (fichier PNG / JPEG de cet ordinateur) ou « data_base64 » attendu", "\"chemin\" (PNG / JPEG file on this computer) or \"data_base64\" expected"])
	var o := _opts(args)
	if args.get("id") is String and String(args.id) != "":
		o["id"] = String(args.id)
	if args.get("chemin") is String:
		o["nom_fichier"] = String(args.chemin).get_file()
	var nrm := _bytes_of(args, "normale_chemin", "normale_base64")
	if nrm.has("error"):
		return nrm
	if nrm.has("bytes"):
		o["normale"] = nrm.bytes
	var res := MapTextureTools.import_bytes(doc, img.bytes, o)
	if res.has("error"):
		return _err(res.error)
	var out := describe(doc, String(res.tid))
	out["a_faire"] = Lang.t("Appliquer : editor_apply, « put » de la pièce complète avec \"surface_sol\" (ou surface_murs, surface_plafond) : \"%s\" ; d'une zone avec \"sol\" / \"murs\" / \"plafond\"." % out.ref,
		"Apply: editor_apply, \"put\" of the whole room with \"surface_sol\" (or surface_murs, surface_plafond): \"%s\"; of a zone with \"sol\" / \"murs\" / \"plafond\"." % out.ref)
	return out


static func _tid_arg(doc: EditorMap, args: Dictionary) -> String:
	var v: Variant = args.get("id")
	if not v is String:
		return ""
	var s := String(v)
	if MapTextureLib.is_ref(s):
		s = MapTextureLib.tid_of(s)
	return s if doc.textures.has(s) else ""


static func _update(doc: EditorMap, args: Dictionary) -> Dictionary:
	var tid := _tid_arg(doc, args)
	if tid == "":
		return _err(["« id » : texture de la carte inconnue (editor_texture_list)", "\"id\": unknown map texture (editor_texture_list)"])
	var o := _opts(args)
	var img := _bytes_of(args, "image_chemin", "image_base64")
	if img.has("error"):
		return img
	if img.has("bytes"):
		o["image"] = img.bytes
	var nrm := _bytes_of(args, "normale_chemin", "normale_base64")
	if nrm.has("error"):
		return nrm
	if nrm.has("bytes"):
		o["normale"] = nrm.bytes
	if args.get("retirer_normale") is bool:
		o["retirer_normale"] = args.retirer_normale
	if o.is_empty():
		return _err(["aucun réglage à changer", "no setting to change"])
	var res := MapTextureTools.update(doc, tid, o)
	if res.has("error"):
		return _err(res.error)
	return describe(doc, tid)


static func _delete(doc: EditorMap, collab: MapCollab, args: Dictionary) -> Dictionary:
	var tid := _tid_arg(doc, args)
	if tid == "":
		return _err(["« id » : texture de la carte inconnue (editor_texture_list)", "\"id\": unknown map texture (editor_texture_list)"])
	var ops := MapTextureTools.users_reset_ops(doc, tid)
	var force: bool = args.get("forcer") is bool and bool(args.forcer)
	if not ops.is_empty() and not force:
		return _err(["texture « %s » utilisée par %s : choisissez d'abord une autre surface, ou « forcer » : true (ces éléments reprennent leur surface par défaut)" % [tid, ", ".join(MapOps.ids_of(ops))],
			"texture \"%s\" used by %s: pick another surface first, or \"forcer\": true (these elements go back to their default surface)" % [tid, ", ".join(MapOps.ids_of(ops))]])
	var cid := ""
	if not ops.is_empty():
		if collab != null:
			cid = String(collab.submit_ops(ops, Lang.t("Claude : texture « %s » retirée", "Claude: texture \"%s\" removed") % tid, collab.my_id + ":claude").get("cid", ""))
		else:
			MapOps.apply(doc, ops)
	MapTextureLib.remove(doc, tid)
	var out := {"supprimee": tid, "remises_par_defaut": MapOps.ids_of(ops)}
	if cid != "":
		out["cid"] = cid
	return out


static func _import_from_map(doc: EditorMap, args: Dictionary) -> Dictionary:
	var mid := String(args.get("carte", "")) if args.get("carte") is String else ""
	var dir := EditorMap.map_dir(mid)
	if dir == "" or not EditorMap.is_map_dir(dir):
		var names := EditorMap.list_maps().map(func(m): return String(m.id))
		return {"error": Lang.t("« carte » : identifiant d'une carte de l'utilisateur attendu (%s)", "\"carte\": identifier of one of the user's maps expected (%s)") % ", ".join(names)}
	if mid == doc.id():
		return _err(["c'est la carte ouverte", "this is the open map"])
	var src := EditorMap.load_dir(dir)
	var wanted: Array = []
	if args.get("ids") is Array:
		for v in args.ids:
			var s := MapTextureLib.tid_of(v) if MapTextureLib.is_ref(v) else (String(v) if v is String else "")
			if not src.textures.has(s):
				return {"error": Lang.t("texture « %s » absente de la carte « %s » (elle a : %s)", "texture \"%s\" not in map \"%s\" (it has: %s)") % [str(v).left(40), mid, ", ".join(src.textures.keys())]}
			wanted.append(s)
	else:
		wanted = src.textures.keys()
	if wanted.is_empty():
		return _err(["cette carte n'a aucune texture", "this map has no texture"])
	var done := []
	for tid in wanted:
		var img := MapTextureLib.image_bytes(src.texture_files, tid)
		if img.is_empty():
			return {"error": Lang.t("texture « %s » sans image dans la carte « %s »", "texture \"%s\" has no image in map \"%s\"") % [tid, mid]}
		var o := {"nom": src.textures[tid].nom, "taille": src.textures[tid].taille}
		for k in ["rugosite", "metal", "teinte"]:
			if src.textures[tid].has(k):
				o[k] = src.textures[tid][k]
		var n := MapTextureLib.image_bytes(src.texture_files, tid, true)
		if not n.is_empty():
			o["normale"] = n
		if not doc.textures.has(tid):
			o["id"] = tid
		var res := MapTextureTools.import_bytes(doc, img, o)
		if res.has("error"):
			return _err(res.error)
		done.append({"source": tid, "id": res.tid, "ref": MapTextureLib.ref(res.tid)})
	return {"importees": done}


# ------------------------------------------------------------------ catalogue

## Textures de la carte pour la commande « catalog » : [{ref, nom, taille}].
static func catalog_textures(doc: EditorMap) -> Array:
	var out := []
	var ids := doc.textures.keys()
	ids.sort()
	for tid in ids:
		out.append({"ref": MapTextureLib.ref(tid), "nom": doc.textures[tid].nom, "taille": doc.textures[tid].taille,
			"image": MapTextureLib.image_file(doc.texture_files, tid) != ""})
	return out


# ------------------------------------------------------------------ outils MCP

const _REF_DOC := "Une texture de la carte s'écrit « map:<id> » dans les champs de surface : pièce (pieces) « surface_sol », « surface_murs », « surface_plafond » ; zone (zones) « sol », « murs », « plafond ». Une surface du jeu s'écrit par sa clé (« concrete », « brick », « tiles »…, voir editor_texture_list). Pièce sans ces clés : la surface de sa zone ; zone sans elles : sol « concrete », murs « wall », plafond « ceiling »."
const _SET_DOC := "Réglages : « nom » (texte, ou {\"fr\", \"en\"} ; 64 caractères au plus, sans balise), « taille » (m, de 0,05 à 100 : LARGEUR d'une répétition de l'image, la hauteur suit les proportions de l'image ; la même échelle s'applique au sol, aux murs et au plafond, en coordonnées du monde : un carrelage de 30 cm dont l'image montre 4 × 4 carreaux → taille 1,2 ; une brique dont l'image fait 2 m de large → 2), « rugosite » (0 brillant à 1 mat, défaut 0,85), « metal » (0 à 1, défaut 0), « teinte » (\"#rrggbb\", multiplie l'image, défaut \"#ffffff\")."


## Définitions des outils MCP : {name, description, inputSchema, cmd}.
static func tool_defs() -> Array:
	var settings := {
		"nom": {"description": "Nom affiché : texte (même nom en français et en anglais) ou {\"fr\": \"…\", \"en\": \"…\"}.", "oneOf": [{"type": "string"}, {"type": "object", "properties": {"fr": {"type": "string"}, "en": {"type": "string"}}}]},
		"taille": {"type": "number", "minimum": MapTextureLib.SIZE[0], "maximum": MapTextureLib.SIZE[1], "description": "Largeur en mètres d'UNE répétition de l'image (hauteur : selon ses proportions). Défaut à l'import : 2."},
		"rugosite": {"type": "number", "minimum": 0, "maximum": 1, "description": "0 brillant, 1 mat (défaut 0,85)."},
		"metal": {"type": "number", "minimum": 0, "maximum": 1, "description": "Aspect métallique (défaut 0)."},
		"teinte": {"type": "string", "pattern": "^#?[0-9a-fA-F]{6}$", "description": "Couleur multipliée à l'image, \"#rrggbb\" (défaut \"#ffffff\" : l'image telle quelle)."},
	}
	var props_with := func(extra: Dictionary) -> Dictionary:
		var p := settings.duplicate(true)
		p.merge(extra, true)
		return p
	return [
		{"name": "editor_texture_list", "cmd": "texture_list",
			"description": "Liste les textures utilisables pour les sols, murs et plafonds : « jeu » (surfaces du jeu : ref = clé à écrire, nom) et « carte » (textures importées dans cette carte : ref « map:<id> », nom, taille du motif en m, hauteur_motif, px (côtés de l'image), rugosite, metal, teinte, normale, utilisee_par [{id, coll, cle}]) ; « absentes » : textures citées mais introuvables (le jeu met la surface par défaut). " + _REF_DOC + " Pour appliquer une texture : editor_get_element de la pièce ou de la zone, puis editor_apply avec un « put » de l'élément complet où \"surface_sol\": \"map:carrelage_bleu\" (une étape d'annulation).",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "editor_texture_import", "cmd": "texture_import",
			"description": "Importe une image PNG ou JPEG comme texture de la carte (copiée dans le dossier de la carte : textures/<id>/image.png|jpg, écrite à l'enregistrement ; aucune limite de taille ni de nombre, seulement 16384 px de côté au plus). Source : « chemin » (fichier de CET ordinateur, l'éditeur tourne sur la même machine que toi ; chemin absolu, ex. \"C:/Users/moi/Images/carrelage.png\") ou « data_base64 » (octets de l'image en base64, \"data:image/png;base64,…\" accepté ; préfère « chemin » pour une grosse image). Facultatif : « normale_chemin » / « normale_base64 » (carte des normales, convention OpenGL, Y vers le haut), « id » (identifiant voulu : a-z, 0-9, _ ; sinon tiré du nom). " + _SET_DOC + " Rend la texture (ref « map:<id> » à écrire dans editor_apply). Session collaborative : hôte ou solo seulement ; les invités voient la surface par défaut à la place de l'image. Ne l'applique à aucune pièce : utilise ensuite editor_apply.",
			"inputSchema": {"type": "object", "properties": props_with.call({
				"chemin": {"type": "string", "description": "Chemin absolu d'un fichier .png, .jpg ou .jpeg de cet ordinateur."},
				"data_base64": {"type": "string", "description": "Image PNG ou JPEG en base64 (à la place de « chemin »)."},
				"normale_chemin": {"type": "string", "description": "Carte des normales facultative (fichier .png / .jpg)."},
				"normale_base64": {"type": "string", "description": "Carte des normales facultative en base64."},
				"id": {"type": "string", "pattern": "^[a-z0-9_]{1,32}$", "description": "Identifiant voulu (sans « __ » ni _ au bord) ; sinon tiré du nom."}}),
				"additionalProperties": false}},
		{"name": "editor_texture_update", "cmd": "texture_update",
			"description": "Change les réglages d'une texture de la carte (« id » : son identifiant ou sa ref « map:<id> »). " + _SET_DOC + " Aussi : « image_chemin » / « image_base64 » (remplacer l'image), « normale_chemin » / « normale_base64 » (carte des normales), « retirer_normale » : true. Les pièces et zones qui l'utilisent changent d'aspect aussitôt (aucune annulation par Ctrl+Z : la bibliothèque n'est pas dans l'historique). Hôte ou solo seulement.",
			"inputSchema": {"type": "object", "required": ["id"], "properties": props_with.call({
				"id": {"type": "string", "description": "Identifiant de la texture (ou « map:<id> »)."},
				"image_chemin": {"type": "string"}, "image_base64": {"type": "string"},
				"normale_chemin": {"type": "string"}, "normale_base64": {"type": "string"},
				"retirer_normale": {"type": "boolean"}}),
				"additionalProperties": false}},
		{"name": "editor_texture_delete", "cmd": "texture_delete",
			"description": "Supprime une texture de la carte (« id »). Refusé si une pièce ou une zone l'utilise (le refus les nomme), sauf « forcer » : true : ces éléments reprennent leur surface par défaut (zone, ou celle du jeu) dans UNE modification annulable (editor_undo_last), puis la texture est retirée. Hôte ou solo seulement.",
			"inputSchema": {"type": "object", "required": ["id"], "properties": {
				"id": {"type": "string", "description": "Identifiant de la texture (ou « map:<id> »)."},
				"forcer": {"type": "boolean", "description": "Vrai : supprimer même si elle est utilisée (surface par défaut remise)."}},
				"additionalProperties": false}},
		{"name": "editor_texture_import_from_map", "cmd": "texture_import_from_map",
			"description": "Copie des textures d'une AUTRE carte de l'utilisateur (« carte » : identifiant de son dossier, ex. \"bunker_nord\" ; une carte inconnue : le refus liste les cartes) dans la carte ouverte, avec leurs réglages et leur carte des normales. « ids » facultatif : identifiants (ou refs) à copier, sinon toutes. Un identifiant déjà pris dans la carte ouverte reçoit un nouvel identifiant (rendu dans « importees » : [{source, id, ref}]). Hôte ou solo seulement.",
			"inputSchema": {"type": "object", "required": ["carte"], "properties": {
				"carte": {"type": "string", "description": "Identifiant de l'autre carte (nom de son dossier)."},
				"ids": {"type": "array", "items": {"type": "string"}, "description": "Textures à copier (toutes si absent)."}},
				"additionalProperties": false}},
	]
