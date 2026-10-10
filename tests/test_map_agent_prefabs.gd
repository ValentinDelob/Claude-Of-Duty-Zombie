extends TestCase
## Prefabs de la carte pilotés par Claude (MapAgentPrefabs, docs/MAP_COLLAB.md
## § 5.2) : chaque commande (prefab_list, prefab_sources, prefab_create,
## prefab_import_model, prefab_import, prefab_update, prefab_delete), succès et
## refus (invité de session, pid inconnu, fichier absent, .glb invalide,
## prefab posée...), aucun quota (9e et 20e modèle, gros modèle), définitions
## des outils MCP et délégation par MapAgentLink. Cartes et fichiers dans
## tests/_out, jamais chez le joueur.

const TMP := "res://tests/_out/test_map_agent_prefabs"
const P := preload("res://tests/test_map_prefabs.gd")
const DecorFree := preload("res://tests/test_map_decor_free.gd")

var ed: MapEditor


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	CustomMapGuard.cache_override = ProjectSettings.globalize_path(TMP + "/cache")


func after_each() -> void:
	if ed != null and is_instance_valid(ed):
		ed.queue_free()
	ed = null
	EditorMap.root_override = ""
	CustomMapGuard.cache_override = ""
	MapCatalog.set_map_prefabs({})


## Éditeur ouvert sur `doc` (solo).
func _editor(doc: EditorMap) -> MapEditor:
	ed = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.doc = doc
	ed.changed()
	return ed


func _cmd(cmd: String, args := {}) -> Dictionary:
	return MapAgentPrefabs.handle(ed, cmd, args)


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func _ok(r: Dictionary, what: String) -> bool:
	assert_false(r.has("error"), "%s : %s" % [what, str(r.get("error", ""))])
	return not r.has("error")


func _refused(r: Dictionary, what: String) -> void:
	assert_true(r.has("error") and String(r.error) != "", "refusé : %s" % what)


# ------------------------------------------------------------------ outils MCP, délégation

func test_tool_defs_and_dispatch() -> void:
	var defs := MapAgentPrefabs.tool_defs()
	assert_eq(defs.size(), MapAgentPrefabs.CMDS.size(), "un outil par commande")
	var cmds := {}
	for d in defs:
		assert_true(String(d.name).begins_with("editor_prefab_"), "nom d'outil : %s" % d.name)
		assert_true(String(d.description).length() > 80, "description détaillée : %s" % d.name)
		assert_eq(String(d.inputSchema.type), "object", "schéma JSON objet : %s" % d.name)
		assert_true(MapAgentPrefabs.handles(String(d.cmd)), "commande connue : %s" % d.cmd)
		cmds[d.cmd] = true
		# Sérialisable tel quel (registre d'outils MCP).
		assert_true(JSON.parse_string(JSON.stringify(d)) is Dictionary, "définition en JSON : %s" % d.name)
	assert_eq(cmds.size(), MapAgentPrefabs.CMDS.size(), "toutes les commandes ont un outil")
	_refused(MapAgentPrefabs.handle(null, "prefab_list", {}), "sans éditeur")
	assert_false(MapAgentPrefabs.handles("apply"), "les autres commandes restent à MapAgentLink")


# ------------------------------------------------------------------ groupe : créer, lister, régler, supprimer

func test_create_list_update_delete_group() -> void:
	await _editor(P.decorated())
	var crates := String(P._objs(ed.doc, "caisses")[0].id)
	var bags := String(P._objs(ed.doc, "sacs_sable")[0].id)
	var n0 := ed.doc.objets.size()
	# Ni ids ni parties / les deux : refusé.
	_refused(_cmd("prefab_create", {"nom": "X"}), "ni ids ni parties")
	_refused(_cmd("prefab_create", {"ids": [crates], "parties": []}), "ids et parties")
	_refused(_cmd("prefab_create", {"ids": ["o1"]}), "rien que du décor non admis (porte)")
	# Depuis des objets posés, remplacés par la prefab (lot de Claude).
	var r := _cmd("prefab_create", {"nom": "Barricade", "ids": [crates, bags, "o1", "absent_1"]})
	if not _ok(r, "prefab créée depuis le décor posé"):
		return
	var pid := String(r.pid)
	assert_eq(String(r.ref), "map:" + pid, "référence map:<pid>")
	assert_eq(String(r.sorte), "groupe")
	assert_eq((r.parties as Array).size(), 2, "deux parties")
	assert_eq(r.absents, ["absent_1"], "id inconnu signalé")
	assert_eq((r.exclus as Array).size(), 1, "la porte est exclue, avec sa raison")
	assert_true(String(r.exclus[0].raison) != "", "raison de l'exclusion")
	assert_true(bool(r.remplace) and String(r.objet_pose) != "" and String(r.cid) != "", "décor remplacé par un lot de Claude")
	assert_eq(ed.doc.objets.size(), n0 - 1, "deux décors remplacés par un prefab posé")
	assert_eq(ed.doc.prefab_users(pid).size(), 1, "posée une fois")
	assert_true(String(r.note).contains("annul") or String(r.note).contains("undo"), "le résultat rappelle l'historique d'annulation")
	assert_true(ed.dirty, "carte marquée modifiée")
	assert_false(MapCatalog.item("prefab:map:" + pid).is_empty(), "dans l'inventaire (catalogue)")
	# Claude annule son remplacement : décor revenu, bibliothèque gardée.
	var u := ed.collab.request_undo(true)
	assert_false(u.is_empty(), "annulation de Claude")
	assert_eq(ed.doc.objets.size(), n0, "décors d'origine revenus")
	assert_true(ed.doc.prefabs.has(pid), "la prefab reste (bibliothèque hors historique)")
	# Liste.
	var l := _cmd("prefab_list")
	assert_eq(int(l.nombre), 1, "une prefab")
	assert_eq(String(l.prefabs[0].pid), pid)
	assert_eq(int(l.prefabs[0].pose), 0, "plus posée après l'annulation")
	assert_true(bool(l.peut_modifier), "solo : peut modifier")
	# Depuis des parties du catalogue, sans remplacement.
	var r2 := _cmd("prefab_create", {"nom": "Coin", "parties": [{"decor": "caisses", "pos": [0, 0]}, {"decor": "sacs_sable", "pos": [2.5, 0], "rot": 90}]})
	if not _ok(r2, "prefab créée depuis des parties"):
		return
	assert_eq((r2.parties as Array).size(), 2, "deux parties")
	assert_eq(int(r2.parties[1].get("rot", 0)), 90, "rotation gardée")
	assert_eq(ed.doc.prefab_users(String(r2.pid)).size(), 0, "rien n'est posé")
	_refused(_cmd("prefab_create", {"parties": [{"decor": "inconnu", "pos": [0, 0]}]}), "décor inconnu")
	_refused(_cmd("prefab_create", {"parties": [{"decor": "map:" + pid, "pos": [0, 0]}]}), "prefab dans une prefab")
	_refused(_cmd("prefab_create", {"parties": [{"decor": "caisses", "pos": [99, 0]}]}), "partie hors limites")
	# Régler.
	var up := _cmd("prefab_update", {"pid": pid, "nom": "Barricade du fond"})
	if _ok(up, "renommée"):
		assert_eq(String(up.nom.fr), "Barricade du fond")
	_refused(_cmd("prefab_update", {"pid": pid, "echelle": 2.0}), "échelle d'une prefab groupe")
	_refused(_cmd("prefab_update", {"pid": "fantome", "nom": "X"}), "pid inconnu")
	_refused(_cmd("prefab_update", {"pid": pid}), "rien à changer")
	_refused(_cmd("prefab_update", {"pid": pid, "nom": "   "}), "nom vide")
	# Supprimer : refusé tant que posée, sauf avec ses objets (lot de Claude).
	var placed := _cmd("prefab_create", {"nom": "Posée", "ids": [crates, bags]})
	if not _ok(placed, "prefab posée"):
		return
	var ppid := String(placed.pid)
	_refused(_cmd("prefab_delete", {"pid": ppid}), "prefab posée")
	assert_true(ed.doc.prefabs.has(ppid), "toujours là")
	_refused(_cmd("prefab_delete", {"pid": "fantome"}), "pid inconnu")
	var d := _cmd("prefab_delete", {"pid": "map:" + ppid, "avec_objets": true})
	if _ok(d, "supprimée avec ses objets"):
		assert_eq((d.objets_supprimes as Array).size(), 1, "son objet posé supprimé")
		assert_false(ed.doc.prefabs.has(ppid), "retirée de la bibliothèque")
		assert_true(MapCatalog.item("prefab:map:" + ppid).is_empty(), "retirée de l'inventaire")
	var d2 := _cmd("prefab_delete", {"pid": String(r2.pid)})
	_ok(d2, "prefab non posée supprimée")


# ------------------------------------------------------------------ modèles importés

func test_import_model_commands_without_quota() -> void:
	await _editor(DecorFree.two_rooms())
	var src := _abs(TMP + "/src/statue_bleue.glb")
	P._write(src, P.box_glb(Vector3(1, 2, 3)))
	var r := _cmd("prefab_import_model", {"chemin": src, "bloque": "barriere"})
	if not _ok(r, "modèle importé depuis un fichier"):
		return
	assert_eq(String(r.sorte), "modele")
	assert_eq(String(r.bloque), "barriere")
	assert_eq(r.emprise_cases, [2, 6], "emprise tirée de la boîte englobante")
	assert_eq(r.taille_modele_m, [1.0, 3.0, 2.0], "taille x, y (sud), hauteur")
	assert_true(int(r.octets) > 0 and int(r.triangles) == 12, "octets et triangles : %s %s" % [r.get("octets"), r.get("triangles")])
	assert_eq(String(r.nom.fr), "statue bleue", "nom tiré du fichier")
	assert_true(ed.doc.models.has(String(r.pid)), "modèle dans la carte")
	# Refus : fichier absent, .glb invalide, base64 invalide, réglages hors limites.
	_refused(_cmd("prefab_import_model", {"chemin": _abs(TMP + "/src/absent.glb")}), "fichier absent")
	var junk := _abs(TMP + "/src/casse.glb")
	P._write(junk, "pas un glb du tout".to_utf8_buffer())
	_refused(_cmd("prefab_import_model", {"chemin": junk}), ".glb invalide")
	_refused(_cmd("prefab_import_model", {"data_base64": "pas du base64 !"}), "base64 invalide")
	_refused(_cmd("prefab_import_model", {"data_base64": Marshalls.raw_to_base64("glTFxxxxxxxxxxxxxxxxxxxxxxxxxxxx".to_utf8_buffer())}), "contenu invalide")
	_refused(_cmd("prefab_import_model", {"chemin": src, "echelle": 500}), "échelle hors limites")
	_refused(_cmd("prefab_import_model", {"chemin": src, "bloque": "mur"}), "collision inconnue")
	_refused(_cmd("prefab_import_model", {"chemin": src, "data_base64": "AAAA"}), "chemin et data_base64")
	# Style cubique (GAME_CONCEPT.md § 4.19) : 52 cm n'est pas un multiple de 5 cm.
	var nc := _cmd("prefab_import_model", {"data_base64": Marshalls.raw_to_base64(P.box_glb(Vector3(0.52, 1.0, 0.5))), "nom": "Hors grille"})
	_refused(nc, "modèle hors de la grille de 5 cm")
	assert_true(String(nc.get("error", "")).contains("cubique") or String(nc.get("error", "")).contains("cubic"), "raison : style cubique (%s)" % str(nc.get("error", "")))
	_refused(_cmd("prefab_update", {"pid": String(r.pid), "echelle": 1.01}), "échelle qui sort le modèle de la grille")
	# Aucun quota : jusqu'au 20e modèle (anciennes limites : 8 modèles, 32 prefabs).
	for i in 19:
		var b := P.box_glb(Vector3(0.5 + 0.05 * i, 1.0, 0.5))
		var ri := _cmd("prefab_import_model", {"data_base64": Marshalls.raw_to_base64(b), "nom": "Modèle %d" % (i + 2)})
		if not _ok(ri, "modèle n° %d accepté" % (i + 2)):
			return
	assert_eq(ed.doc.model_count(), 20, "20 modèles importés (le 9e et le 20e compris)")
	# Gros modèle (ancienne limite : 8 Mo par modèle, 24 Mo en tout).
	var fat := _abs(TMP + "/src/gros.glb")
	P._write(fat, P.big_glb(9))
	var rb := _cmd("prefab_import_model", {"chemin": fat, "nom": "Gros"})
	if _ok(rb, "modèle de 9 Mo accepté"):
		assert_true(int(rb.octets) > 9 * 1048576, "taille rendue")
	DirAccess.remove_absolute(fat)
	assert_eq(int(_cmd("prefab_list").modeles), 21, "21 modèles listés")
	# Réglages : échelle et collision recalculent emprise et pavé.
	var up := _cmd("prefab_update", {"pid": String(r.pid), "echelle": 2.0, "bloque": "non"})
	if _ok(up, "réglé"):
		assert_eq(up.emprise_cases, [4, 12], "échelle 2 : emprise doublée")
		assert_eq((up.collision as Array).size(), 0, "sans collision")
	_refused(_cmd("prefab_update", {"pid": String(r.pid), "echelle": 0.0}), "échelle nulle")
	# La carte (21 modèles, 9 Mo) passe le contrôle des cartes reçues.
	assert_eq(CustomMapGuard.check_texts(ed.doc.file_texts()).reasons, [], "contrôle des cartes reçues : accepté")


# ------------------------------------------------------------------ importer d'une autre carte

func test_import_prefabs_from_other_map_or_folder() -> void:
	# Carte source enregistrée chez l'utilisateur : un groupe et un modèle.
	var srcmap := P.decorated()
	var parts := P._objs(srcmap, "caisses") + P._objs(srcmap, "sacs_sable")
	assert_true(srcmap.set_prefab("barricade", MapPrefabLib.from_objects("Barricade", "Barricade", parts).def))
	var glb := P.box_glb()
	assert_true(srcmap.set_prefab("statue", MapPrefabLib.from_model("Statue", "Statue", glb).def, glb))
	srcmap.carte["id"] = "source"
	var sdir := EditorMap.map_dir("source")
	assert_eq(srcmap.save_dir(sdir), OK, "carte source enregistrée")
	var plain := DecorFree.two_rooms()
	assert_eq(plain.save_dir(EditorMap.map_dir("sans_prefab")), OK)
	# Carte ouverte : a déjà une prefab « statue » (conflit de pid).
	var doc := DecorFree.two_rooms()
	var other := P.box_glb(Vector3(2, 2, 2))
	doc.set_prefab("statue", MapPrefabLib.from_model("Autre", "Other", other).def, other)
	await _editor(doc)
	var s := _cmd("prefab_sources")
	var found: Array = (s.cartes as Array).filter(func(c): return String(c.carte) == "source")
	assert_eq(found.size(), 1, "carte source listée")
	if found.size() == 1:
		assert_eq((found[0].prefabs as Array).map(func(p): return String(p.pid)), ["barricade", "statue"], "ses prefabs")
	assert_true(int(s.cartes_sans_prefab) >= 1, "carte sans prefab comptée à part")
	# Import de toute la carte : « statue » renommée.
	var r := _cmd("prefab_import", {"carte": "source"})
	if not _ok(r, "import depuis une autre carte"):
		return
	assert_eq((r.importes as Array).size(), 2, "deux prefabs importées")
	var st: Array = (r.importes as Array).filter(func(x): return String(x.pid_source) == "statue")
	assert_true(bool(st[0].renomme) and String(st[0].pid) != "statue", "pid déjà pris : nouveau pid %s" % st[0].pid)
	assert_eq(ed.doc.model_bytes(String(st[0].pid)), glb, "modèle copié")
	assert_eq(ed.doc.model_bytes("statue"), other, "la prefab d'origine n'est pas touchée")
	assert_true(ed.doc.prefabs.has("barricade"), "groupe importé sous son pid")
	# Choix des pids ; pids inconnus, carte inconnue : refusé.
	var r2 := _cmd("prefab_import", {"carte": "source", "pids": ["barricade"]})
	if _ok(r2, "import d'une seule prefab"):
		assert_eq((r2.importes as Array).size(), 1)
	_refused(_cmd("prefab_import", {"carte": "source", "pids": ["fantome"]}), "pid absent de la source")
	_refused(_cmd("prefab_import", {"carte": "inconnue"}), "carte inconnue")
	_refused(_cmd("prefab_import", {"carte": "sans_prefab"}), "carte sans prefab")
	_refused(_cmd("prefab_import", {}), "ni carte ni chemin")
	# Dossier d'une prefab, dossier d'une carte, dossier absent.
	var r3 := _cmd("prefab_import", {"chemin": sdir.path_join("prefabs/statue")})
	if _ok(r3, "import depuis un dossier de prefab"):
		assert_eq((r3.importes as Array).size(), 1)
	var r4 := _cmd("prefab_import", {"chemin": _abs(sdir)})
	if _ok(r4, "import depuis un dossier de carte"):
		assert_eq((r4.importes as Array).size(), 2)
	_refused(_cmd("prefab_import", {"chemin": _abs(TMP + "/nulle_part")}), "dossier absent")
	# Modèle trafiqué (empreinte fausse) : refusé avec la raison.
	var bad := _abs(TMP + "/src/piege/statue")
	DirAccess.make_dir_recursive_absolute(bad)
	var f := FileAccess.open(bad.path_join("prefab.json"), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(sdir.path_join("prefabs/statue/prefab.json")))
	f.close()
	P._write(bad.path_join("model.glb"), other)
	_refused(_cmd("prefab_import", {"chemin": bad}), "empreinte du modèle fausse")


# ------------------------------------------------------------------ session : invité

func test_guest_cannot_change_the_library() -> void:
	var doc := P.decorated()
	var glb := P.box_glb()
	doc.set_prefab("statue", MapPrefabLib.from_model("Statue", "Statue", glb).def, glb)
	await _editor(doc)
	var src := _abs(TMP + "/src/invite.glb")
	P._write(src, glb)
	ed.collab.role = MapCollab.Role.GUEST
	var crates := String(P._objs(ed.doc, "caisses")[0].id)
	for c in [["prefab_create", {"ids": [crates]}], ["prefab_import_model", {"chemin": src}], ["prefab_import", {"chemin": _abs(TMP)}],
			["prefab_update", {"pid": "statue", "nom": "X"}], ["prefab_delete", {"pid": "statue"}]]:
		var r := _cmd(c[0], c[1])
		assert_true(r.has("error") and (String(r.error).contains("hôte") or String(r.error).contains("host")), "invité : %s refusé (%s)" % [c[0], str(r.get("error", ""))])
	var l := _cmd("prefab_list")
	assert_eq(int(l.nombre), 1, "la liste reste lisible")
	assert_false(bool(l.peut_modifier), "invité : ne peut pas modifier")
	assert_true(ed.doc.prefabs.has("statue") and ed.doc.prefabs.size() == 1, "bibliothèque inchangée")
	ed.collab.role = MapCollab.Role.SOLO
