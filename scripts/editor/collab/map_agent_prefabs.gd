class_name MapAgentPrefabs
extends RefCounted
## PREFABS DE LA CARTE PILOTÉS PAR CLAUDE (MCP ; docs/MAP_COLLAB.md § 5.2,
## docs/MAP_OBJECTS.md § 11) : lister, créer (groupe), importer un modèle 3D,
## importer des prefabs d'une autre carte, régler, supprimer. Mêmes fonctions
## que l'interface (MapPrefabTools, MapPrefabLib, EditorMap), mêmes contrôles,
## sans boîte de dialogue :
##   - la bibliothèque ne change qu'en solo ou chez l'hôte d'une session (un
##     invité reçoit une erreur) ;
##   - elle n'est PAS dans l'historique d'annulation (comme dans l'interface) ;
##     ce qui touche aux objets posés (décor remplacé par la prefab, objets
##     d'une prefab supprimée) passe par la session comme un lot de Claude
##     (auteur « <moi>:claude » : editor_undo_last / Ctrl+Z l'annulent) ;
##   - l'éditeur se met à jour comme après l'action à la main (inventaire,
##     rendu, invités de la session) et la carte est marquée modifiée.
## Point d'entrée : handle(editor, cmd, args) -> résultat ou {error: texte dans
## la langue du jeu} ; tool_defs() : définitions des outils MCP ({name,
## description, inputSchema, cmd} : un outil avec « cmd » est transmis tel
## quel à l'éditeur, ses arguments deviennent `args`).

## Commandes traitées ici (MapAgentLink les lui délègue).
const CMDS := ["prefab_list", "prefab_sources", "prefab_create", "prefab_import_model", "prefab_import", "prefab_update", "prefab_delete"]
## Objets posés listés au plus par prefab (prefab_list).
const MAX_LISTED_USERS := 50


static func handles(cmd: String) -> bool:
	return cmd in CMDS


static func handle(editor: Node, cmd: String, args: Dictionary) -> Dictionary:
	var ed := editor as MapEditor
	if ed == null or ed.prefab_tools == null or ed.doc == null:
		return _err("prefabs : commande impossible sans l'éditeur de cartes ouvert", "prefabs: command unavailable without the map editor open")
	match cmd:
		"prefab_list":
			return cmd_list(ed)
		"prefab_sources":
			return cmd_sources(ed)
		"prefab_create":
			return cmd_create(ed, args)
		"prefab_import_model":
			return cmd_import_model(ed, args)
		"prefab_import":
			return cmd_import(ed, args)
		"prefab_update":
			return cmd_update(ed, args)
		"prefab_delete":
			return cmd_delete(ed, args)
	return _err("commande inconnue : %s" % cmd.left(40), "unknown command: %s" % cmd.left(40))


static func _err(fr: String, en: String) -> Dictionary:
	return {"error": Lang.t(fr, en)}


## Rappel joint aux résultats qui changent la bibliothèque.
static func note_library() -> String:
	return Lang.t("La bibliothèque des prefabs n'est pas dans l'historique d'annulation : editor_undo_last et Ctrl+Z ne la défont pas (prefab_delete retire une prefab). La carte est marquée modifiée : l'utilisateur l'enregistre (les modèles sont copiés dans le dossier de la carte à l'enregistrement).",
		"The prefab library is not in the undo history: editor_undo_last and Ctrl+Z do not revert it (prefab_delete removes a prefab). The map is marked modified: the user saves it (models are copied into the map folder when saving).")


## La bibliothèque peut-elle changer ? (solo ou hôte) "" si oui, sinon la raison.
static func _refused(ed: MapEditor) -> String:
	if ed.prefab_tools._can_edit():
		return ""
	return ed.prefab_tools.last_error


static func _str(args: Dictionary, k: String) -> String:
	return String(args[k]).strip_edges() if args.get(k) is String else ""


static func _num_arg(args: Dictionary, k: String) -> Variant:
	var v: Variant = args.get(k)
	return float(v) if (v is float or v is int) and is_finite(float(v)) else null


# ------------------------------------------------------------------ informations

## Fiche d'une prefab de la carte (prefab_list, résultats des autres commandes).
static func info(doc: EditorMap, pid: String) -> Dictionary:
	var d: Dictionary = doc.prefabs.get(pid, {})
	if d.is_empty():
		return {}
	var fp: Array = d.get("fp", [1, 1])
	var users := doc.prefab_users(pid)
	var out := {"pid": pid, "ref": MapPrefabLib.ref(pid), "objet": {"type": "prefab", "prefab": MapPrefabLib.ref(pid)},
		"nom": (d.get("nom", {}) as Dictionary).duplicate(), "sorte": "modele" if MapPrefabLib.is_model(d) else "groupe",
		"emprise_cases": [int(fp[0]), int(fp[1])], "emprise_m": [float(fp[0]) * MapGeom.CELL, float(fp[1]) * MapGeom.CELL],
		"hauteur": float(d.get("h", 0.0)), "bloque": String(d.get("bloque", "non")), "collision": (d.get("boxes", []) as Array).duplicate(true),
		"pose": users.size(), "objets_poses": users.slice(0, MAX_LISTED_USERS).map(func(o): return String(o.get("id", "")))}
	if MapPrefabLib.is_model(d):
		var b := MapPrefabLib.model_box(d)
		out["echelle"] = float(d.modele.echelle)
		# Dimensions à l'échelle : x vers l'est, y vers le sud, hauteur.
		out["taille_modele_m"] = [snappedf(b.size.x, 0.001), snappedf(b.size.z, 0.001), snappedf(b.size.y, 0.001)]
		out["aabb_brute"] = (d.modele.aabb as Array).duplicate()
		out["sha256"] = String(d.modele.sha256)
		out.merge(model_numbers(doc, pid))
	else:
		out["parties"] = (d.get("parties", []) as Array).duplicate(true)
	return out


## Taille, triangles, sommets... d'un modèle importé, lus dans son en-tête
## (seul le début du base64 est décodé).
static func model_numbers(doc: EditorMap, pid: String) -> Dictionary:
	if not doc.models.has(pid):
		return {"modele_absent": true}
	var s := String(doc.models[pid])
	var pad := 2 if s.ends_with("==") else (1 if s.ends_with("=") else 0)
	@warning_ignore("integer_division")
	var size := s.length() / 4 * 3 - pad
	var out := {"octets": size}
	var head := Marshalls.base64_to_raw(s.left(mini(s.length(), 40)))
	if head.size() >= 20:
		var need := 20 + int(head.decode_u32(12))
		@warning_ignore("integer_division")
		var chars := mini(s.length(), (need + 2) / 3 * 4)
		var st := MapPrefabLib.model_stats(Marshalls.base64_to_raw(s.left(chars)).slice(0, need))
		for k in ["triangles", "sommets", "maillages", "materiaux", "images"]:
			if st.has(k):
				out[k] = st[k]
	return out


static func cmd_list(ed: MapEditor) -> Dictionary:
	var ids := ed.doc.prefabs.keys()
	ids.sort()
	var list := ids.map(func(pid): return info(ed.doc, pid))
	return {"prefabs": list, "nombre": list.size(), "modeles": ed.doc.model_count(), "peut_modifier": not _is_guest(ed),
		"note": note_library()}


static func _is_guest(ed: MapEditor) -> bool:
	return ed.collab != null and ed.collab.role == MapCollab.Role.GUEST


## Résumé des prefabs de la carte pour la commande catalog.
static func catalog_info(editor: Node) -> Array:
	var ed := editor as MapEditor
	if ed == null or ed.doc == null:
		return []
	var ids := ed.doc.prefabs.keys()
	ids.sort()
	var out := []
	for pid in ids:
		var d: Dictionary = ed.doc.prefabs[pid]
		out.append({"pid": pid, "ref": MapPrefabLib.ref(pid), "nom": d.get("nom", {}), "sorte": "modele" if MapPrefabLib.is_model(d) else "groupe",
			"emprise_cases": d.get("fp", [1, 1]), "hauteur": d.get("h", 0.0), "bloque": d.get("bloque", "non"), "pose": ed.doc.prefab_users(pid).size()})
	return out


## Cartes de l'utilisateur (user://maps) et leurs prefabs importables
## (prefab.json lus, modèles seulement mesurés).
static func cmd_sources(ed: MapEditor) -> Dictionary:
	var open_dir := EditorMap._abs(ed.map_dir).trim_suffix("/") if ed.map_dir != "" else ""
	var maps := []
	var without := 0
	for m in EditorMap.list_maps():
		var dir := String(m.dir)
		var pf := _dir_defs(dir.path_join(MapPrefabLib.DIR))
		if pf.is_empty():
			without += 1
			continue
		maps.append({"carte": String(m.id), "nom": String(m.name), "dossier": EditorMap._abs(dir), "ouverte": EditorMap._abs(dir).trim_suffix("/") == open_dir,
			"prefabs": pf})
	return {"cartes": maps, "cartes_sans_prefab": without, "dossier_des_cartes": EditorMap._abs(EditorMap.maps_root()),
		"aide": Lang.t("prefab_import {carte: <carte>, pids: [...]} les copie dans la carte ouverte.", "prefab_import {carte: <map>, pids: [...]} copies them into the open map.")}


## Prefabs d'un dossier prefabs/ (définitions valides seulement).
static func _dir_defs(root: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var pids := Array(DirAccess.get_directories_at(root)).filter(func(p): return MapPrefabLib.pid_ok(p))
	pids.sort()
	for pid in pids:
		var t: Variant = EditorMap.read_text(root.path_join(pid).path_join(MapPrefabLib.DEF_FILE), MapPrefabLib.MAX_DEF_BYTES)
		var d: Variant = CustomMapGuard.parse_json(t) if t != null and CustomMapGuard.json_depth(t) in range(0, 7) else null
		if not MapPrefabLib.check_def(d).is_empty():
			continue
		var e := {"pid": pid, "nom": d.nom, "sorte": "modele" if MapPrefabLib.is_model(d) else "groupe", "emprise_cases": d.fp, "hauteur": d.h}
		var mp := root.path_join(pid).path_join(MapPrefabLib.MODEL_FILE)
		if MapPrefabLib.is_model(d):
			e["octets"] = FileAccess.get_size(mp) if FileAccess.file_exists(mp) else 0
		out.append(e)
	return out


# ------------------------------------------------------------------ créer (groupe)

## prefab_create : prefab GROUPE depuis des objets posés (`ids`, avec
## `remplacer`) ou depuis des `parties` de décors du catalogue.
static func cmd_create(ed: MapEditor, args: Dictionary) -> Dictionary:
	var has_ids := args.get("ids") is Array
	var has_parts := args.get("parties") is Array
	if has_ids == has_parts:
		return _err("prefab_create : donnez « ids » (objets posés) OU « parties » (décors du catalogue), pas les deux",
			"prefab_create: give \"ids\" (placed objects) OR \"parties\" (catalogue props), not both")
	var why := _refused(ed)
	if why != "":
		return {"error": why}
	var tools := ed.prefab_tools
	var name := _str(args, "nom")
	if name == "":
		name = Lang.t("Prefab %d", "Prefab %d") % (ed.doc.prefabs.size() + 1)
	if has_parts:
		var objs := []
		var parts: Array = args.parties
		if parts.is_empty() or parts.size() > MapPrefabLib.MAX_PARTS:
			return _err("prefab_create : 1 à %d parties" % MapPrefabLib.MAX_PARTS, "prefab_create: 1 to %d parts" % MapPrefabLib.MAX_PARTS)
		for i in parts.size():
			var p: Variant = parts[i]
			if not (p is Dictionary and p.get("decor") is String and MapCatalog.floor_prefab(String(p.decor))):
				return _err("partie %d : « decor » doit être un décor du catalogue posé au sol (editor_catalog, « prefabs » de mount « sol », pas « map: »)" % i,
					"part %d: \"decor\" must be a catalogue prop placed on the floor (editor_catalog, \"prefabs\" with mount \"sol\", not \"map:\")" % i)
			var pos: Variant = p.get("pos", [0, 0])
			if not (pos is Array and pos.size() == 2 and (pos[0] is float or pos[0] is int) and (pos[1] is float or pos[1] is int)
					and absf(float(pos[0])) <= MapPrefabLib.MAX_SIZE and absf(float(pos[1])) <= MapPrefabLib.MAX_SIZE):
				return _err("partie %d : « pos » [x, y] en m (±%d)" % [i, int(MapPrefabLib.MAX_SIZE)], "part %d: \"pos\" [x, y] in m (±%d)" % [i, int(MapPrefabLib.MAX_SIZE)])
			var rot: Variant = p.get("rot", 0)
			if not ((rot is float or rot is int) and is_finite(float(rot))):
				return _err("partie %d : « rot » en degrés" % i, "part %d: \"rot\" in degrees" % i)
			objs.append({"type": "prefab", "prefab": String(p.decor), "position": [float(pos[0]), float(pos[1])], "rot": posmod(roundi(float(rot)), 360), "altitude": 0.0})
		var made := tools.make_group(objs, name)
		if made.is_empty():
			return {"error": tools.last_error}
		var out := info(ed.doc, String(made.pid))
		out["contenu"] = MapPrefabTools.parts_text(objs)
		out["note"] = note_library() + " " + Lang.t("Les positions des parties sont recentrées sur le centre de leur emprise commune (point d'ancrage).",
			"Part positions are re-centred on the centre of their common footprint (anchor point).")
		return out
	# Depuis des objets posés (comme « Créer une prefab » sur la sélection).
	var ids: Array = (args.ids as Array).filter(func(x): return x is String)
	var missing := ids.filter(func(x): return ed.doc.find(x).is_empty())
	var an := MapPrefabTools.analyze(ed.doc, ids.filter(func(x): return not ed.doc.find(x).is_empty()))
	var excluded := []
	for k in MapPrefabTools.EXCLUDED:
		if an.excluded.has(k):
			var en: Array = MapPrefabTools.EXCLUDED[k]
			excluded.append({"sorte": Lang.t(en[0], en[1]), "nombre": int(an.excluded[k]), "raison": Lang.t(en[2], en[3])})
	var parts2: Array = an.parts
	if parts2.is_empty():
		var e := _err("prefab_create : aucun décor du catalogue posé au sol parmi ces éléments", "prefab_create: no catalogue prop placed on the floor among these elements")
		e["error"] += " " + JSON.stringify({"exclus": excluded, "absents": missing})
		return e
	if parts2.size() > MapPrefabLib.MAX_PARTS:
		return _err("prefab_create : %d décors, %d au plus dans une prefab" % [parts2.size(), MapPrefabLib.MAX_PARTS], "prefab_create: %d props, at most %d in a prefab" % [parts2.size(), MapPrefabLib.MAX_PARTS])
	var replace := bool(args.get("remplacer", true)) if args.get("remplacer") is bool else true
	var made2 := tools.make_group(parts2, name)
	if made2.is_empty():
		return {"error": tools.last_error}
	var pid := String(made2.pid)
	var out2 := info(ed.doc, pid)
	out2["contenu"] = MapPrefabTools.parts_text(parts2)
	out2["parties_reprises"] = parts2.map(func(o): return String(o.id))
	out2["exclus"] = excluded
	out2["absents"] = missing
	out2["remplace"] = false
	if replace:
		# Décor remplacé par la prefab posée à sa place : un lot de Claude
		# (annulable : editor_undo_last, Ctrl+Z).
		var alt := EditorMap.alt_of(parts2[0])
		var ops := parts2.map(func(o): return {"op": "del", "coll": "objets", "id": String(o.id)})
		ops.append({"op": "add", "coll": "objets", "el": {"type": "prefab", "prefab": MapPrefabLib.ref(pid), "position": MapGeom.arr(made2.center), "rot": 0, "altitude": alt}})
		var label := _str(args, "label").left(120)
		if label == "":
			label = Lang.t("Prefab « %s » posée à la place du décor", "Prefab \"%s\" placed instead of the props") % MapPrefabLib.name_of(made2.def)
		var sub := _submit(ed, ops, label)
		out2["remplace"] = true
		out2["objet_pose"] = String(sub.ids.get("#%d" % parts2.size(), ""))
		out2["cid"] = sub.cid
		out2["pose"] = ed.doc.prefab_users(pid).size()
	out2["note"] = note_library() + (Lang.t(" Le remplacement du décor par la prefab est, lui, annulable (editor_undo_last).", " Replacing the props with the prefab can be undone (editor_undo_last).") if replace else "")
	return out2


## Lot d'opérations sur les objets au nom de Claude (comme apply) :
## {cid, ids}. Sans session : appliqué comme un changement de l'éditeur.
static func _submit(ed: MapEditor, ops: Array, label: String) -> Dictionary:
	var res := MapOps.resolve_adds(ed.doc, ops)
	if ed.collab == null:
		ed.push_undo()
		MapOps.apply(ed.doc, res.ops)
		ed.changed()
		return {"cid": "", "ids": res.ids}
	var ch := ed.collab.submit_ops(res.ops, Lang.t("Claude : %s", "Claude: %s") % label, ed.collab.my_id + ":claude")
	return {"cid": String(ch.get("cid", "")), "ids": res.ids}


# ------------------------------------------------------------------ importer un modèle

## prefab_import_model : modèle .glb / .gltf d'un fichier local (`chemin`) ou
## de `data_base64`.
static func cmd_import_model(ed: MapEditor, args: Dictionary) -> Dictionary:
	var path := _str(args, "chemin")
	var data := _str(args, "data_base64")
	if (path == "") == (data == ""):
		return _err("prefab_import_model : donnez « chemin » (fichier .glb ou .gltf de cet ordinateur) OU « data_base64 »",
			"prefab_import_model: give \"chemin\" (a .glb or .gltf file on this computer) OR \"data_base64\"")
	var scale := 1.0
	var sv: Variant = _num_arg(args, "echelle")
	if args.has("echelle"):
		if sv == null or float(sv) < MapPrefabLib.SCALE[0] or float(sv) > MapPrefabLib.SCALE[1]:
			return _err("« echelle » : nombre de %s à %s" % [str(MapPrefabLib.SCALE[0]), str(MapPrefabLib.SCALE[1])], "\"echelle\": number from %s to %s" % [str(MapPrefabLib.SCALE[0]), str(MapPrefabLib.SCALE[1])])
		scale = float(sv)
	var block := _str(args, "bloque") if args.has("bloque") else "solide"
	if not block in MapPrefabLib.BLOCKS:
		return _err("« bloque » : solide, barriere ou non", "\"bloque\": solide, barriere or non")
	var why := _refused(ed)
	if why != "":
		return {"error": why}
	var tools := ed.prefab_tools
	var name := _str(args, "nom")
	var pid := ""
	if path != "":
		var p := path.replace("\\", "/")
		if not FileAccess.file_exists(p):
			return _err("fichier absent : %s" % p.left(200), "missing file: %s" % p.left(200))
		pid = tools.import_file(p, name, scale, block, false)
	else:
		var b64 := data.replace("\n", "").replace("\r", "").replace(" ", "")
		if b64.length() % 4 != 0 or RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$").search(b64) == null:
			return _err("« data_base64 » : base64 invalide", "\"data_base64\": invalid base64")
		var fmt := _str(args, "format").to_lower()
		if not fmt in ["", "glb", "gltf"]:
			return _err("« format » : glb ou gltf", "\"format\": glb or gltf")
		var got := MapPrefabLib.import_bytes(Marshalls.base64_to_raw(b64), fmt)
		if got.has("error"):
			return _err("Import refusé : %s" % got.error[0], "Import refused: %s" % got.error[1])
		pid = tools.import_glb(got.glb, name, scale, block, false)
	if pid == "":
		return {"error": tools.last_error}
	var out := info(ed.doc, pid)
	out["note"] = note_library() + " " + Lang.t("Emprise, hauteur et collision (un pavé de la boîte englobante) viennent du modèle à son échelle ; prefab_update change échelle et collision.",
		"Footprint, height and collision (one box of the bounding box) come from the model at its scale; prefab_update changes scale and collision.")
	return out


# ------------------------------------------------------------------ importer d'une autre carte

## prefab_import : prefabs d'une autre carte (`carte`) ou d'un dossier
## (`chemin` : dossier de prefab ou de carte), copiés dans la carte ouverte.
static func cmd_import(ed: MapEditor, args: Dictionary) -> Dictionary:
	var map_id := _str(args, "carte")
	var path := _str(args, "chemin").replace("\\", "/")
	if (map_id == "") == (path == ""):
		return _err("prefab_import : donnez « carte » (une carte de l'utilisateur, prefab_sources) OU « chemin » (dossier)",
			"prefab_import: give \"carte\" (one of the user's maps, prefab_sources) OR \"chemin\" (folder)")
	var why := _refused(ed)
	if why != "":
		return {"error": why}
	var src := read_source(map_id, path)
	if src.has("error"):
		return src
	var texts: Dictionary = src.texts
	var avail := []
	for k in texts:
		var pk := MapPrefabLib.parse_key(k)
		if not pk.is_empty() and pk[1] == MapPrefabLib.DEF_FILE:
			avail.append(String(pk[0]))
	avail.sort()
	var wanted := avail
	if args.get("pids") is Array:
		wanted = (args.pids as Array).filter(func(x): return x is String)
		var unknown := wanted.filter(func(x): return not x in avail)
		if not unknown.is_empty():
			return _err("prefab(s) absente(s) de la source : %s (disponibles : %s)" % [", ".join(unknown), ", ".join(avail)],
				"prefab(s) missing from the source: %s (available: %s)" % [", ".join(unknown), ", ".join(avail)])
	if wanted.is_empty():
		return _err("aucune prefab à importer dans la source", "no prefab to import in the source")
	var done := []
	var refused := []
	var used := ed.doc.prefabs.duplicate()
	for spid in wanted:
		# Mêmes contrôles qu'une carte reçue (définition, modèle, empreinte).
		var sub := {MapPrefabLib.def_key(spid): texts[MapPrefabLib.def_key(spid)]}
		if texts.has(MapPrefabLib.model_key(spid)):
			sub[MapPrefabLib.model_key(spid)] = texts[MapPrefabLib.model_key(spid)]
		var bad := MapPrefabLib.check_entries(sub, {})
		if not bad.is_empty():
			refused.append({"pid": spid, "raison": Lang.t(String(bad[0][0]), String(bad[0][1]))})
			continue
		var def := MapPrefabLib.sanitize(CustomMapGuard.parse_json(String(sub[MapPrefabLib.def_key(spid)])))
		var glb := Marshalls.base64_to_raw(String(sub[MapPrefabLib.model_key(spid)])) if MapPrefabLib.is_model(def) else PackedByteArray()
		var npid: String = spid if not used.has(spid) else MapPrefabLib.new_pid(spid, used)
		if not ed.doc.set_prefab(npid, def, glb):
			refused.append({"pid": spid, "raison": Lang.t("prefab refusée", "prefab refused")})
			continue
		used[npid] = true
		done.append({"pid_source": spid, "pid": npid, "ref": MapPrefabLib.ref(npid), "renomme": npid != spid, "nom": def.nom,
			"sorte": "modele" if MapPrefabLib.is_model(def) else "groupe"})
	if not done.is_empty():
		ed.prefab_tools._library_changed()
		ed.set_status(Lang.t("%d prefab(s) importée(s) par Claude : inventaire, « Prefabs de la carte »", "%d prefab(s) imported by Claude: inventory, \"Map prefabs\"") % done.size())
	elif not refused.is_empty():
		return {"error": Lang.t("aucune prefab importée : %s", "no prefab imported: %s") % "; ".join(refused.map(func(r): return "%s (%s)" % [r.pid, r.raison]))}
	return {"importes": done, "refuses": refused, "source": src.source, "note": note_library() + " " + Lang.t("Un pid déjà pris dans la carte ouverte reçoit un nouveau pid (« renomme »).", "A pid already used in the open map gets a new pid (\"renomme\").")}


## Textes de prefab d'une source (MapPrefabLib.read_dir : clé -> texte ou
## base64) : {texts, source} ou {error}.
##   `map_id` : une carte de l'utilisateur (EditorMap.map_dir) ;
##   `path` : dossier d'UNE prefab (prefab.json, model.glb éventuel ; son nom
##   de dossier donne le pid) ou dossier d'une carte (avec prefabs/).
static func read_source(map_id: String, path: String) -> Dictionary:
	if map_id != "":
		var dir := EditorMap.map_dir(map_id)
		if dir == "" or not EditorMap.is_map_dir(dir):
			return _err("carte inconnue : « %s » (prefab_sources donne les cartes)" % map_id.left(48), "unknown map: \"%s\" (prefab_sources lists the maps)" % map_id.left(48))
		return {"texts": MapPrefabLib.read_dir(dir).texts, "source": EditorMap._abs(dir)}
	var p := path.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(p):
		return _err("dossier absent : %s" % p.left(200), "missing folder: %s" % p.left(200))
	if FileAccess.file_exists(p.path_join(MapPrefabLib.DEF_FILE)):
		var spid := p.get_file()
		if not MapPrefabLib.pid_ok(spid):
			spid = MapPrefabLib.new_pid(spid.replace("-", "_"), {})
		var t: Variant = EditorMap.read_text(p.path_join(MapPrefabLib.DEF_FILE), MapPrefabLib.MAX_DEF_BYTES)
		if t == null:
			return _err("prefab.json trop gros ou illisible", "prefab.json too big or unreadable")
		var texts := {MapPrefabLib.def_key(spid): t}
		var mp := p.path_join(MapPrefabLib.MODEL_FILE)
		if FileAccess.file_exists(mp):
			texts[MapPrefabLib.model_key(spid)] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(mp))
		return {"texts": texts, "source": p}
	if DirAccess.dir_exists_absolute(p.path_join(MapPrefabLib.DIR)):
		return {"texts": MapPrefabLib.read_dir(p).texts, "source": p}
	return _err("ni dossier de prefab (prefab.json) ni dossier de carte (prefabs/) : %s" % p.left(200), "neither a prefab folder (prefab.json) nor a map folder (prefabs/): %s" % p.left(200))


# ------------------------------------------------------------------ régler, supprimer

static func _pid_arg(ed: MapEditor, args: Dictionary) -> String:
	var pid := _str(args, "pid").trim_prefix(MapPrefabLib.REF)
	return pid if ed.doc.prefabs.has(pid) else ""


static func _unknown(args: Dictionary) -> Dictionary:
	return _err("prefab inconnue : « %s » (prefab_list donne les prefabs de la carte)" % _str(args, "pid").left(40),
		"unknown prefab: \"%s\" (prefab_list lists the map prefabs)" % _str(args, "pid").left(40))


## prefab_update : nom ; modèle : échelle et collision (comme ⚙).
static func cmd_update(ed: MapEditor, args: Dictionary) -> Dictionary:
	var pid := _pid_arg(ed, args)
	if pid == "":
		return _unknown(args)
	var why := _refused(ed)
	if why != "":
		return {"error": why}
	var def: Dictionary = ed.doc.prefabs[pid]
	var name := _str(args, "nom")
	if args.has("nom"):
		var nm := MapPrefabTools.clean_name(name)
		if nm == "" or not CustomMapGuard.name_ok(nm):
			return _err("« nom » refusé (texte de 1 à %d caractères, sans balise)" % CustomMapGuard.MAX_NAME, "\"nom\" refused (text of 1 to %d characters, no tag)" % CustomMapGuard.MAX_NAME)
	var scale := -1.0
	var block := ""
	if args.has("echelle") or args.has("bloque"):
		if not MapPrefabLib.is_model(def):
			return _err("« echelle » et « bloque » : seulement pour un modèle importé (une prefab groupe garde la collision de ses parties)",
				"\"echelle\" and \"bloque\": only for an imported model (a group prefab keeps its parts' collision)")
		if args.has("echelle"):
			var sv: Variant = _num_arg(args, "echelle")
			if sv == null or float(sv) < MapPrefabLib.SCALE[0] or float(sv) > MapPrefabLib.SCALE[1]:
				return _err("« echelle » : nombre de %s à %s" % [str(MapPrefabLib.SCALE[0]), str(MapPrefabLib.SCALE[1])], "\"echelle\": number from %s to %s" % [str(MapPrefabLib.SCALE[0]), str(MapPrefabLib.SCALE[1])])
			scale = float(sv)
		if args.has("bloque"):
			block = _str(args, "bloque")
			if not block in MapPrefabLib.BLOCKS:
				return _err("« bloque » : solide, barriere ou non", "\"bloque\": solide, barriere or non")
	if not (args.has("nom") or args.has("echelle") or args.has("bloque")):
		return _err("prefab_update : rien à changer (nom, echelle, bloque)", "prefab_update: nothing to change (nom, echelle, bloque)")
	if not ed.prefab_tools.update_prefab(pid, name, scale, block):
		return {"error": ed.prefab_tools.last_error}
	var out := info(ed.doc, pid)
	# Objets posés devenus mal placés (emprise changée) : dessinés en rouge.
	var bad := {}
	MapRules.begin_batch(ed.doc)
	for o in ed.doc.prefab_users(pid):
		var r := MapRules.check_existing(ed.doc, o)
		if not r.ok:
			bad[String(o.id)] = MapRules.why(r)
	MapRules.end_batch()
	out["objets_mal_places"] = bad
	out["note"] = note_library()
	return out


## prefab_delete : refusé si la prefab est posée, sauf `avec_objets` (ses
## objets posés retirés par un lot de Claude, annulable ; la prefab, non).
static func cmd_delete(ed: MapEditor, args: Dictionary) -> Dictionary:
	var pid := _pid_arg(ed, args)
	if pid == "":
		return _unknown(args)
	var why := _refused(ed)
	if why != "":
		return {"error": why}
	var users := ed.doc.prefab_users(pid)
	var with_users := args.get("avec_objets") is bool and bool(args.avec_objets)
	var ids := users.map(func(o): return String(o.id))
	if not users.is_empty() and not with_users:
		return _err("prefab posée %d fois (%s) : supprimez d'abord ses objets, ou « avec_objets »: true" % [users.size(), ", ".join(ids.slice(0, 20))],
			"prefab placed %d times (%s): delete its objects first, or \"avec_objets\": true" % [users.size(), ", ".join(ids.slice(0, 20))])
	var nm := MapPrefabLib.name_of(ed.doc.prefabs[pid])
	var cid := ""
	if not users.is_empty():
		var label := _str(args, "label").left(120)
		if label == "":
			label = Lang.t("objets de la prefab « %s » supprimés", "objects of prefab \"%s\" deleted") % nm
		cid = String(_submit(ed, ids.map(func(i): return {"op": "del", "coll": "objets", "id": i}), label).cid)
	if not ed.prefab_tools.delete_prefab(pid, false):
		return {"error": ed.prefab_tools.last_error}
	return {"supprime": pid, "nom": nm, "objets_supprimes": ids, "cid": cid,
		"note": note_library() + (Lang.t(" La suppression des objets posés est, elle, annulable (editor_undo_last), mais la prefab ne revient pas : réimportez-la ou recréez-la d'abord.",
			" Deleting the placed objects can be undone (editor_undo_last), but the prefab does not come back: re-import or re-create it first.") if not ids.is_empty() else "")}


# ------------------------------------------------------------------ outils MCP

## Définitions des outils MCP ({name, description, inputSchema, cmd}).
static func tool_defs() -> Array:
	var lib_note := "La bibliothèque des prefabs n'est PAS dans l'historique d'annulation (editor_undo_last / Ctrl+Z ne la défont pas). Seuls l'éditeur seul (solo) ou l'HÔTE d'une session la changent : chez un invité, erreur. La carte est marquée modifiée ; l'utilisateur l'enregistre (modèles copiés dans prefabs/<pid>/model.glb du dossier de la carte). Aucune limite de nombre ni de taille de prefabs ou de modèles : c'est au concepteur de gérer ses ressources."
	return [
		{"name": "editor_prefab_list", "cmd": "prefab_list",
			"description": "Liste les PREFABS DE LA CARTE ouverte (décor propre à la carte, editor_guide topic « objets », section 11) : pour chacune pid, référence « map:<pid> » à mettre dans un objet posé {\"type\": \"prefab\", \"prefab\": \"map:<pid>\", \"position\": [x, y], \"rot\": 0} (editor_apply, comme un décor du catalogue), nom {fr, en}, sorte (« groupe » : décors du catalogue assemblés, « parties » [{decor, pos [x, y] m autour du centre, rot °}] ; « modele » : fichier .glb importé), emprise (cases de 0,5 m et m, x vers l'est, y vers le sud), hauteur (m), bloque (solide / barriere / non), pavés de collision, nombre de fois posée et ids des objets posés ; pour un modèle : échelle, taille à l'échelle [x, y, hauteur] (m), boîte englobante brute, octets, triangles, sommets, maillages, matériaux, images, sha256. « peut_modifier » : faux chez un invité de session.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "editor_prefab_sources", "cmd": "prefab_sources",
			"description": "Liste les AUTRES cartes de l'utilisateur (dossier user://maps) qui ont des prefabs, avec leurs prefabs importables (pid, nom, sorte, emprise, hauteur, octets du modèle) et le dossier de chaque carte. « ouverte » : la carte ouverte elle-même. À utiliser avant editor_prefab_import.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "editor_prefab_create", "cmd": "prefab_create",
			"description": "Crée une prefab GROUPE (des décors du catalogue assemblés en un objet réutilisable), de deux façons :\n1) « ids » : depuis des objets POSÉS (comme « Créer une prefab » sur la sélection ; les décors d'une pièce choisie comptent). Seul le décor du catalogue posé au sol entre dans une prefab ; pièces, portes, fenêtres, murs, objets de jeu (caisse au hasard, pièges…), effets, luminaires, décors muraux et autres prefabs sont exclus (rendus dans « exclus » avec la raison). Un seul niveau (même altitude). Décors ni mis à l'échelle ni inclinés. « remplacer » (défaut true) : les décors repris sont remplacés par la prefab posée à leur place (centre de leur emprise, rot 0) — ce remplacement est un lot de Claude, annulable par editor_undo_last ; false : la prefab est seulement ajoutée à l'inventaire.\n2) « parties » : [{\"decor\": id de décor du catalogue posé au sol (editor_catalog, « prefabs » de mount « sol »), \"pos\": [x, y] en m (x vers l'est, y vers le sud, ±30), \"rot\": degrés}], 1 à 48 parties ; positions recentrées sur le centre de leur emprise commune (point d'ancrage). Rien n'est posé.\nCollision : les pavés de chaque partie qui bloque (32 pavés au plus). Rend la fiche de la prefab (pid, ref « map:<pid> », emprise, hauteur, collision…), « contenu », « exclus », « absents » (ids inconnus), « objet_pose » et « cid » si remplacée. " + lib_note,
			"inputSchema": {"type": "object", "properties": {
				"nom": {"type": "string", "description": "Nom de la prefab (64 caractères au plus, sans balise). Défaut : « Prefab N »."},
				"ids": {"type": "array", "items": {"type": "string"}, "description": "Objets posés à grouper (ids de editor_get_map / editor_get_selection)."},
				"remplacer": {"type": "boolean", "description": "Avec « ids » : remplacer ce décor par la prefab posée à sa place (défaut true, annulable)."},
				"parties": {"type": "array", "items": {"type": "object", "properties": {"decor": {"type": "string"}, "pos": {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2},
					"rot": {"type": "number"}}, "required": ["decor", "pos"]}, "description": "Sans « ids » : décors du catalogue et leur place autour du centre."},
				"label": {"type": "string", "description": "Libellé de l'historique pour le remplacement (français)."}},
				"additionalProperties": false}},
		{"name": "editor_prefab_import_model", "cmd": "prefab_import_model",
			"description": "Importe un MODÈLE 3D (.glb, ou .gltf aux données intégrées « data: », réécrit en .glb) comme prefab de la carte, depuis « chemin » (chemin absolu d'un fichier de CET ordinateur : Claude tourne sur la même machine que le jeu, ex. C:/Users/moi/Downloads/statue.glb) ou depuis « data_base64 » (contenu du fichier en base64 ; « format » glb/gltf, deviné sinon). Mêmes contrôles de sûreté que l'import de l'interface : en-tête GLB, morceaux, aucune adresse externe « uri » (tout dans le fichier), extensions admises (pas de Draco ni meshopt), images PNG ou JPEG intégrées de 16384 px de côté au plus, au moins un maillage. STYLE CUBIQUE obligatoire (docs regles § 6.6) : que des cubes de 5 cm, faces alignées sur les axes, sommets sur la grille de 5 cm à l’échelle demandée, pas d’ombrage lissé ; sinon refusé avec la raison (faces fautives, premier exemple). Le modèle est posé au sol, centré ; « echelle » (0,01 à 100, défaut 1 : unités du modèle en mètres) ; « bloque » : « solide » (bloque joueurs, zombies et balles, défaut), « barriere » (bloque les déplacements, les balles passent), « non » (on marche dessus) ; la collision est TOUJOURS un pavé de sa boîte englobante (jamais tirée du maillage). Rend la fiche (pid, ref « map:<pid> » à poser avec editor_apply, emprise_m, hauteur, taille_modele_m, aabb_brute, collision, octets, triangles…). Aucune limite de taille ni de nombre de modèles. " + lib_note,
			"inputSchema": {"type": "object", "properties": {
				"chemin": {"type": "string", "description": "Chemin absolu du fichier .glb ou .gltf sur cet ordinateur."},
				"data_base64": {"type": "string", "description": "Contenu du fichier en base64 (au lieu de « chemin »)."},
				"format": {"type": "string", "enum": ["glb", "gltf"], "description": "Avec data_base64 : format du contenu (deviné sinon)."},
				"nom": {"type": "string", "description": "Nom de la prefab (défaut : nom du fichier)."},
				"echelle": {"type": "number", "minimum": 0.01, "maximum": 100, "description": "Échelle (défaut 1)."},
				"bloque": {"type": "string", "enum": ["solide", "barriere", "non"], "description": "Collision (défaut solide)."}},
				"additionalProperties": false}},
		{"name": "editor_prefab_import", "cmd": "prefab_import",
			"description": "Copie des prefabs EXISTANTES dans la carte ouverte : depuis une AUTRE carte de l'utilisateur (« carte » : son id, voir editor_prefab_sources ; « pids » facultatif : toutes sinon), ou depuis « chemin » : dossier d'UNE prefab (…/prefabs/<pid>/ avec prefab.json et éventuellement model.glb) ou dossier d'une carte (qui a un dossier prefabs/). Chaque prefab passe les contrôles des cartes reçues (définition, modèle, empreinte sha256) ; une prefab refusée est listée dans « refuses » avec la raison. Un pid déjà pris dans la carte ouverte reçoit un nouveau pid libre (« renomme »: true) : utilisez le « ref » rendu. Rien n'est posé. " + lib_note,
			"inputSchema": {"type": "object", "properties": {
				"carte": {"type": "string", "description": "Id (dossier) d'une carte de l'utilisateur."},
				"chemin": {"type": "string", "description": "Dossier d'une prefab ou d'une carte (chemin absolu)."},
				"pids": {"type": "array", "items": {"type": "string"}, "description": "Prefabs à importer (toutes par défaut)."}},
				"additionalProperties": false}},
		{"name": "editor_prefab_update", "cmd": "prefab_update",
			"description": "Règle une prefab de la carte (comme ⚙) : « nom » ; pour un MODÈLE importé seulement : « echelle » (0,01 à 100) et « bloque » (solide / barriere / non) — emprise, hauteur et pavé de collision sont recalculés (les objets déjà posés suivent ; ceux devenus mal placés sont rendus dans « objets_mal_places »). Une prefab groupe garde la collision de ses parties. Rend la fiche à jour. " + lib_note,
			"inputSchema": {"type": "object", "properties": {
				"pid": {"type": "string", "description": "pid de la prefab (ou « map:<pid> »)."},
				"nom": {"type": "string"},
				"echelle": {"type": "number", "minimum": 0.01, "maximum": 100},
				"bloque": {"type": "string", "enum": ["solide", "barriere", "non"]}},
				"required": ["pid"], "additionalProperties": false}},
		{"name": "editor_prefab_delete", "cmd": "prefab_delete",
			"description": "Supprime une prefab de la carte. Refusé si elle est posée, sauf « avec_objets »: true : ses objets posés sont d'abord supprimés par un lot de Claude (annulable par editor_undo_last, mais la prefab elle-même ne revient pas). Rend {supprime, nom, objets_supprimes, cid}. " + lib_note,
			"inputSchema": {"type": "object", "properties": {
				"pid": {"type": "string", "description": "pid de la prefab (ou « map:<pid> »)."},
				"avec_objets": {"type": "boolean", "description": "Supprimer aussi ses objets posés (défaut false)."},
				"label": {"type": "string", "description": "Libellé de l'historique pour la suppression des objets."}},
				"required": ["pid"], "additionalProperties": false}},
	]
